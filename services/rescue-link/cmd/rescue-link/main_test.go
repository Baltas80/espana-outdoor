package main

import (
    "bytes"
    "context"
    "crypto/rand"
    "crypto/rsa"
    "encoding/base64"
    "encoding/json"
    "net/http"
    "net/http/httptest"
    "strings"
    "testing"
    "time"

    "github.com/coreos/go-oidc/v3/oidc"
    jose "github.com/go-jose/go-jose/v4"
    "github.com/go-jose/go-jose/v4/jwt"
)

func TestTokenRoundTripAndHash(t *testing.T) {
    token, err := randomToken("rl_", 32)
    if err != nil { t.Fatal(err) }
    if !strings.HasPrefix(token, "rl_") { t.Fatalf("unexpected prefix: %q", token) }
    stored := tokenHash(token)
    if !constantTimeTokenEqual(stored, tokenHash(token)) { t.Fatal("token hash should match") }
    if constantTimeTokenEqual(stored, tokenHash(token+"x")) { t.Fatal("different token must not match") }
}

func TestLocationEncryptionRoundTrip(t *testing.T) {
    key := make([]byte, 32)
    for i := range key { key[i] = byte(i + 1) }
    original := locationRecord{
        Latitude: 40.4, Longitude: -3.7, AccuracyMeters: 8,
        CapturedAt: time.Date(2026, 9, 23, 12, 0, 0, 0, time.UTC),
        Type: "lost",
    }
    encrypted, err := encryptLocation(key, "rl_test", original)
    if err != nil { t.Fatal(err) }
    recovered, err := decryptLocation(key, "rl_test", encrypted)
    if err != nil { t.Fatal(err) }
    if recovered != original { t.Fatalf("location mismatch: %#v != %#v", recovered, original) }
}

func TestLocationEncryptionBindsLinkID(t *testing.T) {
    key := make([]byte, 32)
    encrypted, err := encryptLocation(key, "rl_a", locationRecord{
        Latitude: 40.4, Longitude: -3.7, AccuracyMeters: 5,
        CapturedAt: time.Now().UTC(), Type: "lost",
    })
    if err != nil { t.Fatal(err) }
    if _, err := decryptLocation(key, "rl_b", encrypted); err == nil {
        t.Fatal("ciphertext must not decrypt under another link id")
    }
}

func TestLocationResponseForRole(t *testing.T) {
    loc := locationRecord{
        Latitude: 40.412345, Longitude: -3.712345, AccuracyMeters: 8,
        CapturedAt: time.Date(2026, 9, 23, 12, 0, 0, 0, time.UTC),
        Type: "lost",
    }
    volunteer := locationResponseForRole(loc, "volunteer")
    if volunteer.Exact { t.Fatal("volunteer response must be approximate") }
    if volunteer.Latitude != 40.41 || volunteer.Longitude != -3.71 {
        t.Fatalf("unexpected approximate location: %#v", volunteer)
    }
    official := locationResponseForRole(loc, "officialService")
    if !official.Exact || official.Latitude != loc.Latitude || official.Longitude != loc.Longitude {
        t.Fatal("official response should preserve exact location")
    }
}

func TestDecodeJSONRejectsTrailingData(t *testing.T) {
    body := bytes.NewBufferString(`{"shareToken":"` + strings.Repeat("a", 40) + `"} garbage`)
    req := httptest.NewRequest(http.MethodPost, "/", body)
    if err := decodeJSON(httptest.NewRecorder(), req, &acceptRequest{}, 4096); err == nil {
        t.Fatal("trailing non-JSON data must be rejected")
    }
}



func TestLoadConfigRequiresDedicatedRescueAudience(t *testing.T) {
    setRescueConfigEnvironment(t)
    t.Setenv("OIDC_AUDIENCE", "espana-outdoors-mobile")
    t.Setenv("RESCUE_LINK_OIDC_AUDIENCE", "")

    if _, err := loadConfig(); err == nil {
        t.Fatal("expected dedicated Rescue Link resource-server audience to be required")
    }
}

func TestLoadConfigUsesDedicatedRescueAudience(t *testing.T) {
    setRescueConfigEnvironment(t)
    t.Setenv("OIDC_AUDIENCE", "espana-outdoors-mobile")
    t.Setenv("RESCUE_LINK_OIDC_AUDIENCE", "espana-outdoors-rescue-api")

    cfg, err := loadConfig()
    if err != nil {
        t.Fatalf("loadConfig returned error: %v", err)
    }
    if cfg.oidcAudience != "espana-outdoors-rescue-api" {
        t.Fatalf("Rescue Link audience = %q, want dedicated resource audience", cfg.oidcAudience)
    }
}

func setRescueConfigEnvironment(t *testing.T) {
    t.Helper()
    t.Setenv("DATABASE_URL", "postgresql://espana:password@localhost:5432/espana_outdoor?sslmode=require")
    t.Setenv("ALLOW_HTTP_DEV", "false")
    t.Setenv("OIDC_ISSUER", "https://auth.example.test/realms/espana-outdoor")
    t.Setenv("RESCUE_LINK_OIDC_AUDIENCE", "espana-outdoors-rescue-api")
    t.Setenv("PUBLIC_SHARE_BASE_URL", "https://rescue.example.test")
    t.Setenv("LOCATION_ENCRYPTION_KEY", base64.StdEncoding.EncodeToString(make([]byte, 32)))
    t.Setenv("RESCUE_MAX_TTL", "15m")
    t.Setenv("RESCUE_RETENTION", "24h")
    t.Setenv("RESCUE_CAPABILITY_TTL", "5m")
    t.Setenv("RESCUE_MAX_RESPONDERS", "5")
    t.Setenv("RESCUE_RATE_LIMIT_RPS", "2")
    t.Setenv("RESCUE_RATE_LIMIT_BURST", "10")
}

func TestAuthenticateRejectsIDRefreshUntypedAndWrongAudienceTokens(t *testing.T) {
    verifier, issuer, signingKey, cleanup := newRescueTestVerifier(t)
    defer cleanup()

    cases := []struct {
        name      string
        overrides map[string]any
    }{
        {name: "ID token", overrides: map[string]any{"typ": "ID"}},
        {name: "refresh token", overrides: map[string]any{"typ": "Refresh"}},
        {name: "missing token type", overrides: map[string]any{"typ": nil}},
        {name: "wrong audience", overrides: map[string]any{"aud": "espana-outdoors-mobile"}},
        {name: "missing audience", overrides: map[string]any{"aud": nil}},
    }

    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) {
            rawToken := signRescueTestToken(t, signingKey, issuer, tc.overrides)
            srv := &server{
                cfg: config{oidcAudience: "espana-outdoors-rescue-api"},
                verifier: verifier,
            }
            request := httptest.NewRequest(http.MethodPost, "/v1/rescue-links", nil)
            request.Header.Set("Authorization", "Bearer "+rawToken)
            response := httptest.NewRecorder()

            if _, ok := srv.authenticate(response, request); ok {
                t.Fatal("non-access or wrong-audience token was accepted")
            }
            if response.Code != http.StatusUnauthorized {
                t.Fatalf("status = %d, want %d", response.Code, http.StatusUnauthorized)
            }
        })
    }
}

func TestAuthenticateAcceptsDedicatedAudienceWithMobileAuthorizedParty(t *testing.T) {
    verifier, issuer, signingKey, cleanup := newRescueTestVerifier(t)
    defer cleanup()

    rawToken := signRescueTestToken(t, signingKey, issuer, map[string]any{
        "aud": []string{"espana-outdoors-rescue-api", "account"},
        "azp": "espana-outdoors-mobile",
        "typ": "Bearer",
        "resource_access": map[string]any{
            "espana-outdoors-rescue-api": map[string]any{
                "roles": []string{"rescue:volunteer"},
            },
        },
    })
    srv := &server{
        cfg: config{oidcAudience: "espana-outdoors-rescue-api"},
        verifier: verifier,
    }
    request := httptest.NewRequest(http.MethodPost, "/v1/rescue-links", nil)
    request.Header.Set("Authorization", "Bearer "+rawToken)
    response := httptest.NewRecorder()

    principal, ok := srv.authenticate(response, request)
    if !ok {
        t.Fatalf("valid Rescue Link access token rejected: %s", response.Body.String())
    }
    if principal.Subject != "test-rescue-user" {
        t.Fatalf("subject = %q, want verified subject", principal.Subject)
    }
    if _, ok := principal.Roles["rescue:volunteer"]; !ok {
        t.Fatal("server-side Rescue Link role was not preserved")
    }
}

func TestAuthenticateDoesNotPromoteRealmOrUnrelatedClientRoles(t *testing.T) {
    verifier, issuer, signingKey, cleanup := newRescueTestVerifier(t)
    defer cleanup()

    cases := []struct {
        name    string
        claims  map[string]any
    }{
        {
            name: "realm role",
            claims: map[string]any{
                "realm_access": map[string]any{"roles": []string{"rescue:volunteer"}},
            },
        },
        {
            name: "unrelated client role",
            claims: map[string]any{
                "resource_access": map[string]any{
                    "espana-outdoors-mobile": map[string]any{"roles": []string{"rescue:volunteer"}},
                },
            },
        },
    }

    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) {
            rawToken := signRescueTestToken(t, signingKey, issuer, tc.claims)
            srv := &server{
                cfg: config{oidcAudience: "espana-outdoors-rescue-api"},
                verifier: verifier,
            }
            request := httptest.NewRequest(http.MethodPost, "/v1/rescue-links", nil)
            request.Header.Set("Authorization", "Bearer "+rawToken)
            response := httptest.NewRecorder()

            principal, ok := srv.authenticate(response, request)
            if !ok {
                t.Fatalf("valid access token should authenticate before role authorization: %s", response.Body.String())
            }
            if _, allowed := principal.rescueRole(); allowed {
                t.Fatal("role from realm or unrelated client must not authorize Rescue Link")
            }
        })
    }
}

func newRescueTestVerifier(t *testing.T) (*oidc.IDTokenVerifier, string, *rsa.PrivateKey, func()) {
    t.Helper()

    signingKey, err := rsa.GenerateKey(rand.Reader, 2048)
    if err != nil {
        t.Fatalf("generate signing key: %v", err)
    }
    publicJWK := jose.JSONWebKey{
        Key: signingKey.Public(),
        KeyID: "rescue-test-key",
        Algorithm: string(jose.RS256),
        Use: "sig",
    }

    var server *httptest.Server
    server = httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Content-Type", "application/json")
        switch r.URL.Path {
        case "/.well-known/openid-configuration":
            _ = json.NewEncoder(w).Encode(map[string]string{
                "issuer": server.URL,
                "jwks_uri": server.URL + "/keys",
            })
        case "/keys":
            _ = json.NewEncoder(w).Encode(jose.JSONWebKeySet{
                Keys: []jose.JSONWebKey{publicJWK},
            })
        default:
            http.NotFound(w, r)
        }
    }))

    ctx := oidc.ClientContext(context.Background(), server.Client())
    provider, err := oidc.NewProvider(ctx, server.URL)
    if err != nil {
        server.Close()
        t.Fatalf("OIDC discovery failed: %v", err)
    }

    return provider.Verifier(&oidc.Config{SkipClientIDCheck: true}), server.URL, signingKey, server.Close
}

func signRescueTestToken(t *testing.T, signingKey *rsa.PrivateKey, issuer string, overrides map[string]any) string {
    t.Helper()

    signer, err := jose.NewSigner(jose.SigningKey{Algorithm: jose.RS256, Key: signingKey}, nil)
    if err != nil {
        t.Fatalf("create token signer: %v", err)
    }

    claims := map[string]any{
        "iss": issuer,
        "sub": "test-rescue-user",
        "aud": "espana-outdoors-rescue-api",
        "typ": "Bearer",
        "iat": time.Now().Unix(),
        "exp": time.Now().Add(5 * time.Minute).Unix(),
    }
    for name, value := range overrides {
        if value == nil {
            delete(claims, name)
        } else {
            claims[name] = value
        }
    }

    rawToken, err := jwt.Signed(signer).Claims(claims).Serialize()
    if err != nil {
        t.Fatalf("serialize access token: %v", err)
    }
    return rawToken
}


func TestLoadConfigRejectsExternalHTTPIssuerEvenInDevelopment(t *testing.T) {
    setRescueConfigEnvironment(t)
    t.Setenv("ALLOW_HTTP_DEV", "true")
    t.Setenv("OIDC_ISSUER", "http://auth.example.test/realms/espana-outdoor")

    if _, err := loadConfig(); err == nil {
        t.Fatal("external OIDC issuer must use HTTPS even in local development mode")
    }
}

func TestLoadConfigAllowsInternalDockerIssuerAndDatabaseOnlyInDevelopment(t *testing.T) {
    setRescueConfigEnvironment(t)
    t.Setenv("ALLOW_HTTP_DEV", "true")
    t.Setenv("OIDC_ISSUER", "http://keycloak:8080/realms/espana-outdoor")
    t.Setenv("DATABASE_URL", "postgresql://espana:password@postgres:5432/espana_outdoor?sslmode=disable")

    cfg, err := loadConfig()
    if err != nil {
        t.Fatalf("expected explicitly enabled internal Docker configuration: %v", err)
    }
    if !cfg.allowHTTPDev {
        t.Fatal("expected local development exception to be retained")
    }
}

func TestValidateRescueDatabaseURLRequiresTLSOutsideDevelopment(t *testing.T) {
    cases := []struct {
        name string
        raw string
        allowHTTPDev bool
        wantErr bool
    }{
        {"external plaintext", "postgres://user:pass@db.example.test/app?sslmode=disable", false, true},
        {"external plaintext even in dev", "postgres://user:pass@db.example.test/app?sslmode=disable", true, true},
        {"loopback plaintext without dev flag", "postgres://user:pass@localhost/app?sslmode=disable", false, true},
        {"loopback plaintext in dev", "postgres://user:pass@localhost/app?sslmode=disable", true, false},
        {"docker postgres plaintext in dev", "postgres://user:pass@postgres/app?sslmode=disable", true, false},
        {"external TLS", "postgres://user:pass@db.example.test/app?sslmode=verify-full", false, false},
    }
    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) {
            err := validateRescueDatabaseURL(tc.raw, tc.allowHTTPDev)
            if (err != nil) != tc.wantErr {
                t.Fatalf("validateRescueDatabaseURL error = %v, wantErr=%v", err, tc.wantErr)
            }
        })
    }
}

func TestNormalizePublicShareURLRejectsExternalHTTPInDevelopment(t *testing.T) {
    if _, err := normalizePublicShareURL("http://rescue.example.test", true); err == nil {
        t.Fatal("external HTTP share URL must be rejected even in development mode")
    }
    if _, err := normalizePublicShareURL("http://localhost:8090", true); err != nil {
        t.Fatalf("loopback HTTP share URL should be allowed in development: %v", err)
    }
}
