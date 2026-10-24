package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"regexp"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

const maxProfileBodyBytes = 8 << 10

var usernamePattern = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]{2,19}$`)

type config struct {
	port        string
	issuer      string
	audience    string
	databaseURL string
	webOrigins  map[string]struct{}
}

type server struct {
	cfg      config
	db       *pgxpool.Pool
	verifier *oidc.IDTokenVerifier
	log      *slog.Logger
}

type profileInput struct {
	DisplayName string
	Username    string
	HomeArea    string
	Bio         string
}

type profileRecord struct {
	DisplayName string
	Username    string
	HomeArea    string
	Bio         string
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := loadConfig()
	if err != nil {
		slog.Error("invalid profile API configuration", "error", err)
		os.Exit(1)
	}

	provider, err := oidc.NewProvider(ctx, cfg.issuer)
	if err != nil {
		slog.Error("OIDC discovery failed", "error", err)
		os.Exit(1)
	}

	db, err := pgxpool.New(ctx, cfg.databaseURL)
	if err != nil {
		slog.Error("database configuration failed", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	pingCtx, cancelPing := context.WithTimeout(ctx, 10*time.Second)
	defer cancelPing()
	if err := db.Ping(pingCtx); err != nil {
		slog.Error("database connection failed", "error", err)
		os.Exit(1)
	}
	if err := ensureSchema(pingCtx, db); err != nil {
		slog.Error("profile schema initialization failed", "error", err)
		os.Exit(1)
	}

	s := &server{
		cfg:      cfg,
		db:       db,
		verifier: provider.Verifier(&oidc.Config{ClientID: cfg.audience}),
		log:      slog.New(slog.NewJSONHandler(os.Stdout, nil)),
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.healthz)
	mux.HandleFunc("GET /v1/me/profile", s.requireIdentity(s.getMyProfile))
	mux.HandleFunc("PUT /v1/me/profile", s.requireIdentity(s.saveMyProfile))

	httpServer := &http.Server{
		Addr:              ":" + cfg.port,
		Handler:           s.cors(s.securityHeaders(mux)),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    16 << 10,
	}

	go func() {
		s.log.Info("profile API listening", "port", cfg.port)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			s.log.Error("HTTP server failed", "error", err)
			stop()
		}
	}()

	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		s.log.Error("HTTP shutdown failed", "error", err)
	}
}

func loadConfig() (config, error) {
	issuer := strings.TrimRight(strings.TrimSpace(os.Getenv("OIDC_ISSUER")), "/")
	issuerURL, err := url.Parse(issuer)
	if err != nil || issuerURL == nil || issuerURL.Scheme != "https" || issuerURL.Host == "" || issuerURL.User != nil {
		return config{}, errors.New("OIDC_ISSUER must be an HTTPS issuer URL")
	}

	audience := strings.TrimSpace(os.Getenv("OIDC_AUDIENCE"))
	if audience == "" {
		return config{}, errors.New("OIDC_AUDIENCE is required")
	}
	databaseURL := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if databaseURL == "" {
		return config{}, errors.New("DATABASE_URL is required")
	}

	originText := strings.TrimSpace(os.Getenv("WEB_ORIGINS"))
	if originText == "" {
		originText = "https://espanaoutdoor.es,https://www.espanaoutdoor.es"
	}
	origins := make(map[string]struct{})
	for _, item := range strings.Split(originText, ",") {
		origin := strings.TrimRight(strings.TrimSpace(item), "/")
		if origin == "" {
			continue
		}
		parsed, parseErr := url.Parse(origin)
		if parseErr != nil || parsed.Host == "" || parsed.Scheme != "https" || parsed.Path != "" || parsed.RawQuery != "" || parsed.Fragment != "" {
			return config{}, fmt.Errorf("WEB_ORIGINS contains an invalid HTTPS origin: %q", origin)
		}
		origins[origin] = struct{}{}
	}
	if len(origins) == 0 {
		return config{}, errors.New("at least one HTTPS WEB_ORIGINS entry is required")
	}

	return config{
		port:        envOrDefault("PORT", "8080"),
		issuer:      issuer,
		audience:    audience,
		databaseURL: databaseURL,
		webOrigins:  origins,
	}, nil
}

func envOrDefault(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func ensureSchema(ctx context.Context, db *pgxpool.Pool) error {
	const schema = `
CREATE SCHEMA IF NOT EXISTS outdoor;
CREATE TABLE IF NOT EXISTS outdoor.user_profiles (
    subject TEXT PRIMARY KEY,
    username TEXT NOT NULL,
    display_name TEXT NOT NULL,
    home_area TEXT NOT NULL DEFAULT '',
    bio TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS user_profiles_username_ci_uidx
    ON outdoor.user_profiles (lower(username));
`
	_, err := db.Exec(ctx, schema)
	return err
}

type identityKey struct{}

func (s *server) requireIdentity(next func(http.ResponseWriter, *http.Request, string)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		header := strings.TrimSpace(r.Header.Get("Authorization"))
		parts := strings.SplitN(header, " ", 2)
		if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || strings.TrimSpace(parts[1]) == "" {
			writeError(w, http.StatusUnauthorized, "unauthorized", "Inicia sesión para acceder al perfil.")
			return
		}

		token, err := s.verifier.Verify(r.Context(), strings.TrimSpace(parts[1]))
		if err != nil || strings.TrimSpace(token.Subject) == "" {
			writeError(w, http.StatusUnauthorized, "unauthorized", "La sesión no es válida o ha caducado.")
			return
		}
		next(w, r.WithContext(context.WithValue(r.Context(), identityKey{}, token.Subject)), token.Subject)
	}
}

func (s *server) getMyProfile(w http.ResponseWriter, r *http.Request, subject string) {
	var profile profileRecord
	err := s.db.QueryRow(r.Context(), `
SELECT display_name, username, home_area, bio, created_at, updated_at
FROM outdoor.user_profiles
WHERE subject = $1
`, subject).Scan(
		&profile.DisplayName,
		&profile.Username,
		&profile.HomeArea,
		&profile.Bio,
		&profile.CreatedAt,
		&profile.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "profile not created", "Todavía no has creado tu perfil.")
		return
	}
	if err != nil {
		s.log.Error("profile lookup failed", "error", err)
		writeError(w, http.StatusInternalServerError, "internal_error", "No se pudo cargar el perfil.")
		return
	}
	writeJSON(w, http.StatusOK, profileJSON(profile))
}

func (s *server) saveMyProfile(w http.ResponseWriter, r *http.Request, subject string) {
	r.Body = http.MaxBytesReader(w, r.Body, maxProfileBodyBytes)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()

	var input profileInput
	if err := decoder.Decode(&input); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json", "El contenido del perfil no es válido.")
		return
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		writeError(w, http.StatusBadRequest, "invalid_json", "Envía un único objeto JSON.")
		return
	}

	input, message := normalizeAndValidate(input)
	if message != "" {
		writeError(w, http.StatusBadRequest, "invalid_profile", message)
		return
	}

	var profile profileRecord
	err := s.db.QueryRow(r.Context(), `
INSERT INTO outdoor.user_profiles (subject, username, display_name, home_area, bio)
VALUES ($1, $2, $3, $4, $5)
ON CONFLICT (subject) DO UPDATE SET
    username = EXCLUDED.username,
    display_name = EXCLUDED.display_name,
    home_area = EXCLUDED.home_area,
    bio = EXCLUDED.bio,
    updated_at = now()
RETURNING display_name, username, home_area, bio, created_at, updated_at
`, subject, input.Username, input.DisplayName, input.HomeArea, input.Bio).Scan(
		&profile.DisplayName,
		&profile.Username,
		&profile.HomeArea,
		&profile.Bio,
		&profile.CreatedAt,
		&profile.UpdatedAt,
	)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			writeError(w, http.StatusConflict, "username already in use", "Ese alias ya está utilizado. Elige otro.")
			return
		}
		s.log.Error("profile save failed", "error", err)
		writeError(w, http.StatusInternalServerError, "internal_error", "No se pudo guardar el perfil.")
		return
	}
	writeJSON(w, http.StatusOK, profileJSON(profile))
}

func normalizeAndValidate(input profileInput) (profileInput, string) {
	input.DisplayName = strings.TrimSpace(input.DisplayName)
	input.Username = strings.ToLower(strings.TrimSpace(input.Username))
	input.HomeArea = strings.TrimSpace(input.HomeArea)
	input.Bio = strings.TrimSpace(input.Bio)

	if n := utf8.RuneCountInString(input.DisplayName); n < 2 || n > 50 {
		return input, "El nombre debe tener entre 2 y 50 caracteres."
	}
	if !usernamePattern.MatchString(input.Username) {
		return input, "El alias debe tener entre 3 y 20 caracteres válidos."
	}
	if utf8.RuneCountInString(input.HomeArea) > 80 || utf8.RuneCountInString(input.Bio) > 160 {
		return input, "La zona o la presentación supera la longitud permitida."
	}
	return input, ""
}

func profileJSON(p profileRecord) map[string]any {
	return map[string]any{
		"displayName": p.DisplayName,
		"username":    p.Username,
		"homeArea":    p.HomeArea,
		"bio":         p.Bio,
		"createdAt":   p.CreatedAt.UTC().Format(time.RFC3339),
		"updatedAt":   p.UpdatedAt.UTC().Format(time.RFC3339),
	}
}

func (s *server) healthz(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.db.Ping(ctx); err != nil {
		writeError(w, http.StatusServiceUnavailable, "unavailable", "Servicio no disponible.")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok"})
}

func (s *server) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Add("Vary", "Origin")
		origin := strings.TrimRight(strings.TrimSpace(r.Header.Get("Origin")), "/")
		if origin != "" {
			if _, ok := s.cfg.webOrigins[origin]; !ok {
				writeError(w, http.StatusForbidden, "origin_not_allowed", "Origen no permitido.")
				return
			}
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Methods", "GET, PUT, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.Header().Set("Access-Control-Max-Age", "600")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *server) securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
		next.ServeHTTP(w, r)
	})
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{"error": code, "message": message})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
