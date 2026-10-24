package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/time/rate"
)

type config struct {
	databaseURL string
	oidcIssuer string
	oidcAudience string
	allowedOrigins map[string]struct{}
	port string
	allowHTTPDev bool
}

type profile struct {
	DisplayName string    `json:"displayName"`
	Username    string    `json:"username"`
	HomeArea    string    `json:"homeArea"`
	Bio         string    `json:"bio"`
	CreatedAt   time.Time `json:"createdAt,omitempty"`
	UpdatedAt   time.Time `json:"updatedAt,omitempty"`
}

type storedProfile struct {
	Subject string
	profile
}

type server struct {
	cfg config
	db *pgxpool.Pool
	verifier *oidc.IDTokenVerifier
	log *slog.Logger
	limiterMu chan struct{}
	limiters map[string]*rate.Limiter
	limiterLastSeen map[string]time.Time
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := loadConfig()
	if err != nil { panic(err) }

	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	provider, err := discoverOIDCWithRetry(ctx, cfg.oidcIssuer, 30*time.Second)
	if err != nil {
		log.Error("OIDC discovery failed", "error", err)
		os.Exit(1)
	}

	db, err := pgxpool.New(ctx, cfg.databaseURL)
	if err != nil {
		log.Error("database pool failed", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	if err := pingDatabaseWithRetry(ctx, db, 30*time.Second); err != nil {
		log.Error("database unavailable", "error", err)
		os.Exit(1)
	}
	migration, err := os.ReadFile(envOrDefault("PROFILE_MIGRATION_PATH", "migrations/001_user_profiles.sql"))
	if err != nil {
		log.Error("profile migration missing", "error", err)
		os.Exit(1)
	}
	if _, err := db.Exec(ctx, string(migration)); err != nil {
		log.Error("profile migration failed", "error", err)
		os.Exit(1)
	}

	s := &server{
		cfg: cfg,
		db: db,
		verifier: provider.Verifier(&oidc.Config{ClientID: cfg.oidcAudience}),
		log: log,
		limiterMu: make(chan struct{}, 1),
		limiters: make(map[string]*rate.Limiter),
		limiterLastSeen: make(map[string]time.Time),
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.healthz)
	mux.HandleFunc("GET /v1/me/profile", s.getMyProfile)
	mux.HandleFunc("PUT /v1/me/profile", s.putMyProfile)

	httpServer := &http.Server{
		Addr: ":" + cfg.port,
		Handler: s.securityHeaders(s.cors(mux)),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout: 10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout: 60 * time.Second,
		MaxHeaderBytes: 16 << 10,
	}

	go func() {
		log.Info("user-profile service listening", "port", cfg.port)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("profile HTTP server failed", "error", err)
			stop()
		}
	}()

	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		log.Error("profile HTTP shutdown failed", "error", err)
	}
}

func loadConfig() (config, error) {
	databaseURL, err := requiredEnv("DATABASE_URL")
	if err != nil { return config{}, err }
	issuer, err := requiredEnv("OIDC_ISSUER")
	if err != nil { return config{}, err }
	audience, err := requiredEnv("OIDC_AUDIENCE")
	if err != nil { return config{}, err }

	allowHTTP := envOrDefault("ALLOW_HTTP_DEV", "false") == "true"
	if !validIssuer(issuer, allowHTTP) {
		return config{}, errors.New("OIDC_ISSUER must be an HTTPS issuer (HTTP only when ALLOW_HTTP_DEV=true)")
	}

	origins := make(map[string]struct{})
	for _, value := range strings.Split(os.Getenv("CORS_ALLOWED_ORIGINS"), ",") {
		origin := strings.TrimSpace(strings.TrimRight(value, "/"))
		if origin == "" { continue }
		if !strings.HasPrefix(origin, "https://") && !(allowHTTP && strings.HasPrefix(origin, "http://")) {
			return config{}, fmt.Errorf("CORS origin must be HTTPS: %q", origin)
		}
		origins[origin] = struct{}{}
	}

	return config{
		databaseURL: databaseURL,
		oidcIssuer: strings.TrimRight(issuer, "/"),
		oidcAudience: audience,
		allowedOrigins: origins,
		port: envOrDefault("PORT", "8080"),
		allowHTTPDev: allowHTTP,
	}, nil
}

func validIssuer(issuer string, allowHTTP bool) bool {
	return (strings.HasPrefix(issuer, "https://") || (allowHTTP && strings.HasPrefix(issuer, "http://"))) &&
		!strings.ContainsAny(issuer, " \t\r\n")
}

func requiredEnv(name string) (string, error) {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" { return "", fmt.Errorf("%s is required", name) }
	return value, nil
}

func envOrDefault(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" { return value }
	return fallback
}

func discoverOIDCWithRetry(ctx context.Context, issuer string, timeout time.Duration) (*oidc.Provider, error) {
	deadline := time.Now().Add(timeout)
	delay := time.Second
	var lastErr error
	for time.Now().Before(deadline) {
		provider, err := oidc.NewProvider(ctx, issuer)
		if err == nil { return provider, nil }
		lastErr = err
		select {
		case <-ctx.Done(): return nil, ctx.Err()
		case <-time.After(delay):
		}
		if delay < 5*time.Second { delay *= 2 }
	}
	if lastErr == nil { lastErr = errors.New("OIDC discovery timed out") }
	return nil, lastErr
}

func pingDatabaseWithRetry(ctx context.Context, db *pgxpool.Pool, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	delay := time.Second
	var lastErr error
	for time.Now().Before(deadline) {
		pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		err := db.Ping(pingCtx)
		cancel()
		if err == nil { return nil }
		lastErr = err
		select {
		case <-ctx.Done(): return ctx.Err()
		case <-time.After(delay):
		}
		if delay < 5*time.Second { delay *= 2 }
	}
	if lastErr == nil { lastErr = errors.New("database ping timed out") }
	return lastErr
}

func (s *server) securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		next.ServeHTTP(w, r)
	})
}

func (s *server) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := strings.TrimRight(strings.TrimSpace(r.Header.Get("Origin")), "/")
		if origin != "" {
			if _, ok := s.cfg.allowedOrigins[origin]; !ok {
				if r.Method == http.MethodOptions {
					writeError(w, http.StatusForbidden, "origin not allowed")
					return
				}
				// Native clients do not send an Origin header; browser callers
				// receive CORS headers only for explicitly allowed origins.
			} else {
				w.Header().Set("Access-Control-Allow-Origin", origin)
				w.Header().Set("Vary", "Origin")
				w.Header().Set("Access-Control-Allow-Methods", "GET, PUT, OPTIONS")
				w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
				w.Header().Set("Access-Control-Max-Age", "600")
				if r.Method == http.MethodOptions {
					w.WriteHeader(http.StatusNoContent)
					return
				}
			}
		} else if r.Method == http.MethodOptions {
			writeError(w, http.StatusForbidden, "origin required")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *server) healthz(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.db.Ping(ctx); err != nil {
		writeError(w, http.StatusServiceUnavailable, "unavailable")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *server) authenticate(w http.ResponseWriter, r *http.Request) (string, bool) {
	fields := strings.Fields(strings.TrimSpace(r.Header.Get("Authorization")))
	if len(fields) != 2 || !strings.EqualFold(fields[0], "Bearer") {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return "", false
	}
	token, err := s.verifier.Verify(r.Context(), fields[1])
	if err != nil {
		writeError(w, http.StatusUnauthorized, "invalid authentication")
		return "", false
	}
	var claims struct { Subject string `json:"sub"` }
	if err := token.Claims(&claims); err != nil || strings.TrimSpace(claims.Subject) == "" {
		writeError(w, http.StatusUnauthorized, "invalid authentication")
		return "", false
	}
	return claims.Subject, true
}

func (s *server) getMyProfile(w http.ResponseWriter, r *http.Request) {
	subject, ok := s.authenticate(w, r)
	if !ok { return }
	if !s.allow(subject) {
		writeError(w, http.StatusTooManyRequests, "rate limit exceeded")
		return
	}

	var p profile
	err := s.db.QueryRow(r.Context(), `SELECT display_name, username, home_area, bio, created_at, updated_at
		FROM outdoor.user_profiles WHERE subject = $1`, subject).
		Scan(&p.DisplayName, &p.Username, &p.HomeArea, &p.Bio, &p.CreatedAt, &p.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "profile not created")
		return
	}
	if err != nil {
		s.log.Error("profile read failed")
		writeError(w, http.StatusInternalServerError, "could not read profile")
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func (s *server) putMyProfile(w http.ResponseWriter, r *http.Request) {
	subject, ok := s.authenticate(w, r)
	if !ok { return }
	if !s.allow(subject) {
		writeError(w, http.StatusTooManyRequests, "rate limit exceeded")
		return
	}

	var p profile
	if err := decodeJSON(w, r, &p, 8<<10); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	p.DisplayName = strings.TrimSpace(p.DisplayName)
	p.Username = strings.ToLower(strings.TrimSpace(p.Username))
	p.HomeArea = strings.TrimSpace(p.HomeArea)
	p.Bio = strings.TrimSpace(p.Bio)
	if message := validateProfile(p); message != "" {
		writeError(w, http.StatusBadRequest, message)
		return
	}

	err := s.db.QueryRow(r.Context(), `INSERT INTO outdoor.user_profiles
		(subject, display_name, username, home_area, bio)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (subject) DO UPDATE SET
			display_name = EXCLUDED.display_name,
			username = EXCLUDED.username,
			home_area = EXCLUDED.home_area,
			bio = EXCLUDED.bio,
			updated_at = now()
		RETURNING display_name, username, home_area, bio, created_at, updated_at`,
		subject, p.DisplayName, p.Username, p.HomeArea, p.Bio).
		Scan(&p.DisplayName, &p.Username, &p.HomeArea, &p.Bio, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			writeError(w, http.StatusConflict, "username already in use")
			return
		}
		s.log.Error("profile write failed")
		writeError(w, http.StatusInternalServerError, "could not save profile")
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func validateProfile(p profile) string {
	if len([]rune(p.DisplayName)) < 2 || len([]rune(p.DisplayName)) > 50 {
		return "displayName must contain between 2 and 50 characters"
	}
	if !validUsername(p.Username) {
		return "username must be 3-20 lowercase letters, numbers, dots, hyphens or underscores"
	}
	if len([]rune(p.HomeArea)) > 80 { return "homeArea must contain at most 80 characters" }
	if len([]rune(p.Bio)) > 160 { return "bio must contain at most 160 characters" }
	return ""
}

func validUsername(value string) bool {
	if len(value) < 3 || len(value) > 20 { return false }
	for i, r := range value {
		allowed := r >= 'a' && r <= 'z' || r >= '0' && r <= '9' || r == '.' || r == '_' || r == '-'
		if !allowed { return false }
		if i == 0 && !(r >= 'a' && r <= 'z' || r >= '0' && r <= '9') { return false }
	}
	return true
}

func decodeJSON(w http.ResponseWriter, r *http.Request, target any, maxBytes int64) error {
	r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil { return err }
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		if err == nil { return errors.New("multiple JSON values") }
		return err
	}
	return nil
}

func (s *server) allow(subject string) bool {
	select { case s.limiterMu <- struct{}{}: case <-time.After(50 * time.Millisecond): return false }
	defer func() { <-s.limiterMu }()
	now := time.Now()
	for key, last := range s.limiterLastSeen {
		if now.Sub(last) > 15*time.Minute {
			delete(s.limiterLastSeen, key)
			delete(s.limiters, key)
		}
	}
	limiter := s.limiters[subject]
	if limiter == nil {
		if len(s.limiters) >= 4096 {
			for key := range s.limiters { delete(s.limiters, key); delete(s.limiterLastSeen, key); break }
		}
		limiter = rate.NewLimiter(1, 20)
		s.limiters[subject] = limiter
	}
	s.limiterLastSeen[subject] = now
	return limiter.Allow()
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func _unused(io.Reader, context.Context) {}
