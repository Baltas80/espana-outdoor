package main

import (
    "context"
    "crypto/aes"
    "crypto/cipher"
    "crypto/rand"
    "crypto/sha256"
    "crypto/subtle"
    "encoding/base64"
    "encoding/hex"
    "encoding/json"
    "errors"
    "fmt"
    "io"
    "log/slog"
    "math"
    "net"
    "net/http"
    "net/url"
    "os"
    "os/signal"
    "strconv"
    "strings"
    "sync"
    "syscall"
    "time"

    "github.com/coreos/go-oidc/v3/oidc"
    "github.com/jackc/pgx/v5"
    "github.com/jackc/pgx/v5/pgxpool"
    "golang.org/x/time/rate"
)


var emergencyTypes = map[string]struct{}{
    "accident": {},
    "lost": {},
    "medical": {},
    "fire": {},
    "wildlife": {},
    "weather": {},
    "pet": {},
    "unableToSpeak": {},
    "other": {},
}

type config struct {
    databaseURL string
    oidcIssuer string
    oidcAudience string
    publicShareBaseURL string
    locationKey []byte
    port string
    maxTTL time.Duration
    retention time.Duration
    capabilityTTL time.Duration
    maxResponders int
    rateLimit rate.Limit
    rateBurst int
    hsts bool
    allowHTTPDev bool
}

type tokenClaims struct {
    Subject string `json:"sub"`
    Type string `json:"typ"`
    RealmAccess struct {
        Roles []string `json:"roles"`
    } `json:"realm_access"`
    ResourceAccess map[string]struct {
        Roles []string `json:"roles"`
    } `json:"resource_access"`
}

type principal struct {
    Subject string
    Roles map[string]struct{}
}

type locationRecord struct {
    Latitude float64 `json:"latitude"`
    Longitude float64 `json:"longitude"`
    AccuracyMeters float64 `json:"accuracyMeters"`
    CapturedAt time.Time `json:"capturedAt"`
    Type string `json:"type"`
}

type createRequest struct {
    Latitude float64 `json:"latitude"`
    Longitude float64 `json:"longitude"`
    AccuracyMeters float64 `json:"accuracyMeters"`
    Type string `json:"type"`
    ExpiresAt time.Time `json:"expiresAt"`
}

type acceptRequest struct {
    ShareToken string `json:"shareToken"`
}

type acceptResponse struct {
    ID string `json:"id"`
    CapabilityToken string `json:"capabilityToken"`
    ExpiresAt time.Time `json:"expiresAt"`
    Role string `json:"role"`
    Location responseLocation `json:"location"`
}

type responseLocation struct {
    Latitude float64 `json:"latitude"`
    Longitude float64 `json:"longitude"`
    AccuracyMeters float64 `json:"accuracyMeters"`
    CapturedAt time.Time `json:"capturedAt"`
    Type string `json:"type"`
    Exact bool `json:"exact"`
}

type server struct {
    cfg config
    db *pgxpool.Pool
    verifier *oidc.IDTokenVerifier
    publicShareBaseURL *url.URL
    globalMu sync.Mutex
    limiters map[string]*limiterEntry
    log *slog.Logger
}

type limiterEntry struct {
    limiter *rate.Limiter
    lastSeen time.Time
}

func main() {
    ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
    defer stop()

    cfg, err := loadConfig()
    if err != nil {
        panic(err)
    }

    log := slog.New(slog.NewJSONHandler(os.Stdout, nil))

    provider, err := discoverOIDCWithRetry(ctx, cfg.oidcIssuer, 30*time.Second)
    if err != nil {
        log.Error("oidc discovery failed", "error", err)
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
    migrationPath := envOrDefault("RESCUE_MIGRATION_PATH", "migrations/001_rescue_links.sql")
    migration, err := os.ReadFile(migrationPath)
    if err != nil {
        log.Error("database migration file missing", "path", migrationPath, "error", err)
        os.Exit(1)
    }
    if _, err = db.Exec(ctx, string(migration)); err != nil {
        log.Error("database migration failed", "error", err)
        os.Exit(1)
    }

    shareURL, err := normalizePublicShareURL(cfg.publicShareBaseURL, cfg.allowHTTPDev)
    if err != nil {
        log.Error("public share URL invalid", "error", err)
        os.Exit(1)
    }

    s := &server{
        cfg: cfg,
        db: db,
        verifier: provider.Verifier(&oidc.Config{SkipClientIDCheck: true}),
        publicShareBaseURL: shareURL,
        limiters: make(map[string]*limiterEntry),
        log: log,
    }

    go s.cleanupLoop(ctx)

    mux := http.NewServeMux()
    mux.HandleFunc("GET /healthz", s.healthz)
    mux.HandleFunc("POST /v1/rescue-links", s.create)
    mux.HandleFunc("POST /v1/rescue-links/{id}/accept", s.accept)
    mux.HandleFunc("POST /v1/rescue-links/{id}/revoke", s.revoke)
    mux.HandleFunc("GET /v1/rescue-links/{id}/location", s.location)
    mux.HandleFunc("GET /r/{token}", s.sharePreview)

    handler := s.securityHeaders(mux)
    srv := &http.Server{
        Addr: ":" + cfg.port,
        Handler: handler,
        ReadHeaderTimeout: 5 * time.Second,
        ReadTimeout: 15 * time.Second,
        WriteTimeout: 15 * time.Second,
        IdleTimeout: 60 * time.Second,
        MaxHeaderBytes: 16 << 10,
    }

    go func() {
        log.Info("rescue-link listening", "port", cfg.port)
        if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
            log.Error("http server failed", "error", err)
            stop()
        }
    }()

    <-ctx.Done()
    shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer shutdownCancel()
    if err := srv.Shutdown(shutdownCtx); err != nil {
        log.Error("http shutdown failed", "error", err)
    }
}

func discoverOIDCWithRetry(ctx context.Context, issuer string, timeout time.Duration) (*oidc.Provider, error) {
    deadline := time.Now().Add(timeout)
    var lastErr error
    delay := time.Second
    for time.Now().Before(deadline) {
        provider, err := oidc.NewProvider(ctx, issuer)
        if err == nil {
            return provider, nil
        }
        lastErr = err
        select {
        case <-ctx.Done():
            return nil, ctx.Err()
        case <-time.After(delay):
        }
        if delay < 5*time.Second {
            delay *= 2
        }
    }
    if lastErr == nil {
        lastErr = errors.New("OIDC discovery timed out")
    }
    return nil, lastErr
}

func pingDatabaseWithRetry(ctx context.Context, db *pgxpool.Pool, timeout time.Duration) error {
    deadline := time.Now().Add(timeout)
    var lastErr error
    delay := time.Second
    for time.Now().Before(deadline) {
        pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
        err := db.Ping(pingCtx)
        cancel()
        if err == nil {
            return nil
        }
        lastErr = err
        select {
        case <-ctx.Done():
            return ctx.Err()
        case <-time.After(delay):
        }
        if delay < 5*time.Second {
            delay *= 2
        }
    }
    if lastErr == nil {
        lastErr = errors.New("database ping timed out")
    }
    return lastErr
}

func loadConfig() (config, error) {
    databaseURL, err := requiredEnv("DATABASE_URL")
    if err != nil { return config{}, err }
    issuer, err := requiredEnv("OIDC_ISSUER")
    if err != nil { return config{}, err }
    audience, err := requiredEnv("RESCUE_LINK_OIDC_AUDIENCE")
    if err != nil { return config{}, err }
    publicShareBaseURL, err := requiredEnv("PUBLIC_SHARE_BASE_URL")
    if err != nil { return config{}, err }
    keyText, err := requiredEnv("LOCATION_ENCRYPTION_KEY")
    if err != nil { return config{}, err }
    key, err := decodeEncryptionKey(keyText)
    if err != nil { return config{}, err }

    port := envOrDefault("PORT", "8080")
    maxTTL, err := parseDuration("RESCUE_MAX_TTL", "15m")
    if err != nil { return config{}, err }
    retention, err := parseDuration("RESCUE_RETENTION", "24h")
    if err != nil { return config{}, err }
    capabilityTTL, err := parseDuration("RESCUE_CAPABILITY_TTL", "5m")
    if err != nil { return config{}, err }
    maxResponders, err := parseInt("RESCUE_MAX_RESPONDERS", 5)
    if err != nil { return config{}, err }
    rps, err := parseFloat("RESCUE_RATE_LIMIT_RPS", 2)
    if err != nil { return config{}, err }
    burst, err := parseInt("RESCUE_RATE_LIMIT_BURST", 10)
    if err != nil { return config{}, err }

    cfg := config{
        databaseURL: databaseURL,
        oidcIssuer: strings.TrimRight(issuer, "/"),
        oidcAudience: audience,
        publicShareBaseURL: publicShareBaseURL,
        locationKey: key,
        port: port,
        maxTTL: maxTTL,
        retention: retention,
        capabilityTTL: capabilityTTL,
        maxResponders: maxResponders,
        rateLimit: rate.Limit(rps),
        rateBurst: burst,
        hsts: envOrDefault("ENABLE_HSTS", "false") == "true",
        allowHTTPDev: envOrDefault("ALLOW_HTTP_DEV", "false") == "true",
    }

    if cfg.maxTTL <= 30*time.Second || cfg.retention <= cfg.maxTTL || cfg.capabilityTTL <= 0 || cfg.maxResponders <= 0 || cfg.rateLimit <= 0 || cfg.rateBurst <= 0 {
        return config{}, errors.New("invalid Rescue Link limits")
    }
    return cfg, nil
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

func parseDuration(name, fallback string) (time.Duration, error) {
    value := envOrDefault(name, fallback)
    d, err := time.ParseDuration(value)
    if err != nil { return 0, fmt.Errorf("%s: %w", name, err) }
    return d, nil
}

func parseInt(name string, fallback int) (int, error) {
    value := envOrDefault(name, strconv.Itoa(fallback))
    n, err := strconv.Atoi(value)
    if err != nil { return 0, fmt.Errorf("%s: %w", name, err) }
    return n, nil
}

func parseFloat(name string, fallback float64) (float64, error) {
    value := envOrDefault(name, strconv.FormatFloat(fallback, 'f', -1, 64))
    n, err := strconv.ParseFloat(value, 64)
    if err != nil { return 0, fmt.Errorf("%s: %w", name, err) }
    return n, nil
}

func decodeEncryptionKey(value string) ([]byte, error) {
    decoders := []func(string) ([]byte, error){
        base64.StdEncoding.DecodeString,
        base64.RawStdEncoding.DecodeString,
        base64.URLEncoding.DecodeString,
        base64.RawURLEncoding.DecodeString,
        hex.DecodeString,
    }
    for _, decode := range decoders {
        key, err := decode(value)
        if err == nil && len(key) == 32 { return key, nil }
    }
    return nil, errors.New("LOCATION_ENCRYPTION_KEY must decode to exactly 32 bytes")
}

func normalizePublicShareURL(raw string, allowHTTP bool) (*url.URL, error) {
    parsed, err := url.Parse(raw)
    if err != nil { return nil, err }
    if parsed.Host == "" || (parsed.Scheme != "https" && !(allowHTTP && parsed.Scheme == "http")) {
        return nil, errors.New("PUBLIC_SHARE_BASE_URL must be an HTTPS URL")
    }
    parsed.Path = strings.TrimRight(parsed.Path, "/")
    return parsed, nil
}

func (s *server) securityHeaders(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Cache-Control", "no-store")
        w.Header().Set("Referrer-Policy", "no-referrer")
        w.Header().Set("X-Content-Type-Options", "nosniff")
        if s.cfg.hsts { w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains") }
        next.ServeHTTP(w, r)
    })
}

func (s *server) healthz(w http.ResponseWriter, r *http.Request) {
    ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
    defer cancel()
    if err := s.db.Ping(ctx); err != nil {
        writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "unavailable"})
        return
    }
    writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *server) create(w http.ResponseWriter, r *http.Request) {
    p, ok := s.authenticate(w, r)
    if !ok { return }
    if !s.allow("subject:"+p.Subject) { writeError(w, http.StatusTooManyRequests, "rate limit exceeded"); return }

    var req createRequest
    if err := decodeJSON(w, r, &req, 16<<10); err != nil { writeError(w, http.StatusBadRequest, "invalid request"); return }
    if !validCoordinate(req.Latitude, req.Longitude) || math.IsNaN(req.AccuracyMeters) || math.IsInf(req.AccuracyMeters, 0) || req.AccuracyMeters < 0 || req.AccuracyMeters > 5000 {
        writeError(w, http.StatusBadRequest, "invalid location"); return
    }
    if _, exists := emergencyTypes[req.Type]; !exists { writeError(w, http.StatusBadRequest, "invalid emergency type"); return }

    now := time.Now().UTC()
    if req.ExpiresAt.Before(now.Add(30 * time.Second)) {
        writeError(w, http.StatusBadRequest, "expiry is too soon"); return
    }
    maxExpiry := now.Add(s.cfg.maxTTL)
    if req.ExpiresAt.After(maxExpiry) { req.ExpiresAt = maxExpiry }

    id, err := randomToken("rl_", 16)
    if err != nil { writeError(w, http.StatusInternalServerError, "could not create link"); return }
    token, err := randomToken("", 32)
    if err != nil { writeError(w, http.StatusInternalServerError, "could not create link"); return }
    encrypted, err := encryptLocation(s.cfg.locationKey, id, locationRecord{
        Latitude: req.Latitude, Longitude: req.Longitude, AccuracyMeters: req.AccuracyMeters, CapturedAt: now, Type: req.Type,
    })
    if err != nil { writeError(w, http.StatusInternalServerError, "could not protect location"); return }

    _, err = s.db.Exec(r.Context(), `INSERT INTO rescue_links (id, owner_subject, token_hash, encrypted_location, accuracy_meters, emergency_type, created_at, expires_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
        id, p.Subject, tokenHash(token), encrypted, req.AccuracyMeters, req.Type, now, req.ExpiresAt)
    if err != nil { s.log.Error("rescue create failed", "error", err); writeError(w, http.StatusInternalServerError, "could not create link"); return }

    shareURL := *s.publicShareBaseURL
    shareURL.Path = strings.TrimRight(shareURL.Path, "/") + "/r/" + token
    writeJSON(w, http.StatusCreated, map[string]any{
        "id": id,
        "shareToken": token,
        "shareUrl": shareURL.String(),
        "expiresAt": req.ExpiresAt,
    })
}

func (s *server) accept(w http.ResponseWriter, r *http.Request) {
    p, ok := s.authenticate(w, r)
    if !ok { return }
    if !s.allow("subject:"+p.Subject) { writeError(w, http.StatusTooManyRequests, "rate limit exceeded"); return }

    id := r.PathValue("id")
    if id == "" { writeError(w, http.StatusBadRequest, "invalid id"); return }
    var req acceptRequest
    if err := decodeJSON(w, r, &req, 4096); err != nil || len(req.ShareToken) < 32 || len(req.ShareToken) > 256 { writeError(w, http.StatusBadRequest, "invalid acceptance"); return }

    role, ok := p.rescueRole()
    if !ok { writeError(w, http.StatusForbidden, "no Rescue Link role"); return }

    tx, err := s.db.Begin(r.Context())
    if err != nil { s.log.Error("rescue accept transaction failed", "error", err); writeError(w, http.StatusInternalServerError, "temporary failure"); return }
    defer func() { _ = tx.Rollback(r.Context()) }()

    var storedHash, encrypted []byte
    var expiresAt time.Time
    var revokedAt *time.Time
    err = tx.QueryRow(r.Context(), `SELECT token_hash, encrypted_location, expires_at, revoked_at FROM rescue_links WHERE id=$1 FOR UPDATE`, id).Scan(&storedHash, &encrypted, &expiresAt, &revokedAt)
    if errors.Is(err, pgx.ErrNoRows) { writeError(w, http.StatusNotFound, "Rescue Link not found"); return }
    if err != nil { s.log.Error("rescue accept lookup failed", "error", err); writeError(w, http.StatusInternalServerError, "temporary failure"); return }

    if !constantTimeTokenEqual(storedHash, tokenHash(req.ShareToken)) { writeError(w, http.StatusForbidden, "invalid Rescue Link token"); return }
    now := time.Now().UTC()
    if revokedAt != nil || !now.Before(expiresAt) { writeError(w, http.StatusGone, "Rescue Link expired or revoked"); return }

    err = tx.QueryRow(r.Context(), `SELECT 1 FROM rescue_link_responders WHERE link_id=$1 AND subject=$2`, id, p.Subject).Scan(new(int))
    existing := err == nil
    if err != nil && !errors.Is(err, pgx.ErrNoRows) { s.log.Error("rescue responder lookup failed", "error", err); writeError(w, http.StatusInternalServerError, "temporary failure"); return }
    if !existing {
        var count int
        if err = tx.QueryRow(r.Context(), `SELECT count(*) FROM rescue_link_responders WHERE link_id=$1`, id).Scan(&count); err != nil { s.log.Error("rescue responder count failed", "error", err); writeError(w, http.StatusInternalServerError, "temporary failure"); return }
        if count >= s.cfg.maxResponders { writeError(w, http.StatusConflict, "responder limit reached"); return }
    }

    loc, err := decryptLocation(s.cfg.locationKey, id, encrypted)
    if err != nil { s.log.Error("rescue location decrypt failed", "error", err); writeError(w, http.StatusInternalServerError, "location unavailable"); return }
    capability, err := randomToken("rc_", 32)
    if err != nil { writeError(w, http.StatusInternalServerError, "could not create capability"); return }
    capabilityExpiry := expiresAt
    if candidate := now.Add(s.cfg.capabilityTTL); candidate.Before(capabilityExpiry) { capabilityExpiry = candidate }

    _, err = tx.Exec(r.Context(), `INSERT INTO rescue_link_responders (link_id, subject, role, capability_hash, capability_expires_at, accepted_at) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (link_id, subject) DO UPDATE SET role=EXCLUDED.role, capability_hash=EXCLUDED.capability_hash, capability_expires_at=EXCLUDED.capability_expires_at, accepted_at=EXCLUDED.accepted_at`,
        id, p.Subject, role, tokenHash(capability), capabilityExpiry, now)
    if err != nil { s.log.Error("rescue responder upsert failed", "error", err); writeError(w, http.StatusInternalServerError, "temporary failure"); return }
    if _, err = tx.Exec(r.Context(), `UPDATE rescue_links SET accepted_at=$2 WHERE id=$1`, id, now); err != nil { s.log.Error("rescue acceptance update failed", "error", err); writeError(w, http.StatusInternalServerError, "temporary failure"); return }

    if err = tx.Commit(r.Context()); err != nil { s.log.Error("rescue accept commit failed", "error", err); writeError(w, http.StatusInternalServerError, "temporary failure"); return }

    responseLoc := locationResponseForRole(loc, role)
    writeJSON(w, http.StatusOK, acceptResponse{
        ID: id, CapabilityToken: capability, ExpiresAt: capabilityExpiry, Role: role, Location: responseLoc,
    })
}

func (s *server) revoke(w http.ResponseWriter, r *http.Request) {
    p, ok := s.authenticate(w, r)
    if !ok { return }
    if !s.allow("subject:"+p.Subject) { writeError(w, http.StatusTooManyRequests, "rate limit exceeded"); return }
    id := r.PathValue("id")
    if id == "" { writeError(w, http.StatusBadRequest, "invalid id"); return }
    tag, err := s.db.Exec(r.Context(), `UPDATE rescue_links SET revoked_at=COALESCE(revoked_at,$3) WHERE id=$1 AND owner_subject=$2`, id, p.Subject, time.Now().UTC())
    if err != nil { s.log.Error("rescue revoke failed", "error", err); writeError(w, http.StatusInternalServerError, "temporary failure"); return }
    if tag.RowsAffected() == 0 { writeError(w, http.StatusNotFound, "Rescue Link not found"); return }
    w.WriteHeader(http.StatusNoContent)
}

func (s *server) location(w http.ResponseWriter, r *http.Request) {
    p, ok := s.authenticate(w, r)
    if !ok { return }
    if !s.allow("subject:"+p.Subject) { writeError(w, http.StatusTooManyRequests, "rate limit exceeded"); return }
    capability := strings.TrimSpace(r.Header.Get("X-Rescue-Capability"))
    if capability == "" { writeError(w, http.StatusUnauthorized, "capability required"); return }

    id := r.PathValue("id")
    var encrypted []byte
    var role string
    var expiresAt time.Time
    var revokedAt *time.Time
    var capabilityExpiresAt time.Time
    var storedCapability []byte
    err := s.db.QueryRow(r.Context(), `SELECT l.encrypted_location, l.expires_at, l.revoked_at, r.role, r.capability_hash, r.capability_expires_at FROM rescue_links l JOIN rescue_link_responders r ON r.link_id=l.id AND r.subject=$2 WHERE l.id=$1`, id, p.Subject).Scan(&encrypted, &expiresAt, &revokedAt, &role, &storedCapability, &capabilityExpiresAt)
    if errors.Is(err, pgx.ErrNoRows) { writeError(w, http.StatusNotFound, "capability not found"); return }
    if err != nil { s.log.Error("rescue location lookup failed", "error", err); writeError(w, http.StatusInternalServerError, "temporary failure"); return }
    now := time.Now().UTC()
    if !constantTimeTokenEqual(storedCapability, tokenHash(capability)) || revokedAt != nil || !now.Before(expiresAt) || !now.Before(capabilityExpiresAt) {
        writeError(w, http.StatusForbidden, "capability expired or revoked"); return
    }
    loc, err := decryptLocation(s.cfg.locationKey, id, encrypted)
    if err != nil { s.log.Error("rescue location decrypt failed", "error", err); writeError(w, http.StatusInternalServerError, "location unavailable"); return }
    writeJSON(w, http.StatusOK, locationResponseForRole(loc, role))
}

func (s *server) sharePreview(w http.ResponseWriter, r *http.Request) {
    token := r.PathValue("token")
    if len(token) < 32 || len(token) > 256 { writeError(w, http.StatusNotFound, "Rescue Link not available"); return }
    rateKey := r.RemoteAddr
    if host, _, splitErr := net.SplitHostPort(r.RemoteAddr); splitErr == nil {
        rateKey = host
    }
    if !s.allow("ip:"+rateKey) { writeError(w, http.StatusTooManyRequests, "rate limit exceeded"); return }
    var expiresAt time.Time
    var revokedAt *time.Time
    err := s.db.QueryRow(r.Context(), `SELECT expires_at, revoked_at FROM rescue_links WHERE token_hash=$1`, tokenHash(token)).Scan(&expiresAt, &revokedAt)
    if errors.Is(err, pgx.ErrNoRows) { writeError(w, http.StatusNotFound, "Rescue Link not available"); return }
    if err != nil { s.log.Error("rescue preview lookup failed", "error", err); writeError(w, http.StatusInternalServerError, "temporary failure"); return }
    if revokedAt != nil || !time.Now().UTC().Before(expiresAt) { writeError(w, http.StatusNotFound, "Rescue Link not available"); return }
    writeJSON(w, http.StatusOK, map[string]any{
        "status": "active",
        "expiresAt": expiresAt,
        "message": "Abre España Outdoor e inicia sesión para aceptar el Rescue Link.",
    })
}

func containsAudience(audiences []string, expected string) bool {
    if strings.TrimSpace(expected) == "" {
        return false
    }
    for _, audience := range audiences {
        if audience == expected {
            return true
        }
    }
    return false
}

func (s *server) authenticate(w http.ResponseWriter, r *http.Request) (principal, bool) {
    header := strings.TrimSpace(r.Header.Get("Authorization"))
    fields := strings.Fields(header)
    if len(fields) != 2 || !strings.EqualFold(fields[0], "Bearer") {
        writeError(w, http.StatusUnauthorized, "authentication required")
        return principal{}, false
    }

    token, err := s.verifier.Verify(r.Context(), fields[1])
    if err != nil || !containsAudience(token.Audience, s.cfg.oidcAudience) {
        writeError(w, http.StatusUnauthorized, "invalid authentication")
        return principal{}, false
    }

    var claims tokenClaims
    if err = token.Claims(&claims); err != nil ||
        strings.TrimSpace(claims.Subject) == "" ||
        claims.Type != "Bearer" {
        writeError(w, http.StatusUnauthorized, "invalid authentication")
        return principal{}, false
    }

    roles := make(map[string]struct{}, len(claims.RealmAccess.Roles))
    for _, role := range claims.RealmAccess.Roles {
        roles[role] = struct{}{}
    }
    for _, access := range claims.ResourceAccess {
        for _, role := range access.Roles {
            roles[role] = struct{}{}
        }
    }
    return principal{Subject: claims.Subject, Roles: roles}, true
}

func (p principal) rescueRole() (string, bool) {
    candidates := []struct{ claim, role string }{
        {"rescue:official", "officialService"},
        {"rescue:verified-professional", "verifiedProfessional"},
        {"rescue:trusted-contact", "trustedContact"},
        {"rescue:volunteer", "volunteer"},
    }
    for _, candidate := range candidates {
        if _, ok := p.Roles[candidate.claim]; ok { return candidate.role, true }
    }
    return "", false
}

func (s *server) allow(key string) bool {
    now := time.Now()
    s.globalMu.Lock()
    defer s.globalMu.Unlock()
    for k, entry := range s.limiters {
        if now.Sub(entry.lastSeen) > 15*time.Minute { delete(s.limiters, k) }
    }
    entry, ok := s.limiters[key]
    if !ok {
        if len(s.limiters) >= 4096 {
            removed := 0
            for k := range s.limiters { delete(s.limiters, k); removed++; if removed >= 256 { break } }
        }
        entry = &limiterEntry{limiter: rate.NewLimiter(s.cfg.rateLimit, s.cfg.rateBurst)}
        s.limiters[key] = entry
    }
    entry.lastSeen = now
    return entry.limiter.Allow()
}

func (s *server) cleanupLoop(ctx context.Context) {
    ticker := time.NewTicker(1 * time.Hour)
    defer ticker.Stop()
    for {
        select {
        case <-ctx.Done(): return
        case <-ticker.C:
            cutoff := time.Now().UTC().Add(-s.cfg.retention)
            if _, err := s.db.Exec(ctx, `DELETE FROM rescue_links WHERE expires_at < $1`, cutoff); err != nil {
                s.log.Error("rescue retention cleanup failed", "error", err)
            }
        }
    }
}

func validCoordinate(lat, lon float64) bool {
    return !math.IsNaN(lat) && !math.IsInf(lat, 0) && !math.IsNaN(lon) && !math.IsInf(lon, 0) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
}

func locationResponseForRole(loc locationRecord, role string) responseLocation {
    exact := role != "volunteer"
    lat, lon := loc.Latitude, loc.Longitude
    if !exact {
        lat = math.Round(lat*100) / 100
        lon = math.Round(lon*100) / 100
    }
    return responseLocation{
        Latitude: lat,
        Longitude: lon,
        AccuracyMeters: loc.AccuracyMeters,
        CapturedAt: loc.CapturedAt,
        Type: loc.Type,
        Exact: exact,
    }
}

func randomToken(prefix string, size int) (string, error) {
    raw := make([]byte, size)
    if _, err := rand.Read(raw); err != nil { return "", err }
    return prefix + base64.RawURLEncoding.EncodeToString(raw), nil
}

func tokenHash(token string) []byte {
    sum := sha256.Sum256([]byte(token))
    return sum[:]
}

func constantTimeTokenEqual(stored, candidate []byte) bool {
    if len(stored) != len(candidate) { return false }
    return subtle.ConstantTimeCompare(stored, candidate) == 1
}

func encryptLocation(key []byte, id string, loc locationRecord) ([]byte, error) {
    block, err := aes.NewCipher(key)
    if err != nil { return nil, err }
    gcm, err := cipher.NewGCM(block)
    if err != nil { return nil, err }
    nonce := make([]byte, gcm.NonceSize())
    if _, err = rand.Read(nonce); err != nil { return nil, err }
    plaintext, err := json.Marshal(loc)
    if err != nil { return nil, err }
    ciphertext := gcm.Seal(nil, nonce, plaintext, []byte(id))
    return append(nonce, ciphertext...), nil
}

func decryptLocation(key []byte, id string, encrypted []byte) (locationRecord, error) {
    block, err := aes.NewCipher(key)
    if err != nil { return locationRecord{}, err }
    gcm, err := cipher.NewGCM(block)
    if err != nil { return locationRecord{}, err }
    if len(encrypted) < gcm.NonceSize() { return locationRecord{}, errors.New("ciphertext too short") }
    nonce := encrypted[:gcm.NonceSize()]
    ciphertext := encrypted[gcm.NonceSize():]
    plaintext, err := gcm.Open(nil, nonce, ciphertext, []byte(id))
    if err != nil { return locationRecord{}, err }
    var loc locationRecord
    if err := json.Unmarshal(plaintext, &loc); err != nil { return locationRecord{}, err }
    return loc, nil
}

func decodeJSON(w http.ResponseWriter, r *http.Request, dst any, maxBytes int64) error {
    r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
    dec := json.NewDecoder(r.Body)
    dec.DisallowUnknownFields()
    if err := dec.Decode(dst); err != nil {
        return err
    }
    var extra any
    if err := dec.Decode(&extra); err != io.EOF {
        return errors.New("trailing json")
    }
    return nil
}

func writeJSON(w http.ResponseWriter, status int, value any) {
    w.Header().Set("Content-Type", "application/json; charset=utf-8")
    w.WriteHeader(status)
    _ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, message string) {
    writeJSON(w, status, map[string]string{"error": message})
}
