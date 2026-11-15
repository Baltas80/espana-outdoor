package main

import (
    "context"
    "crypto/rand"
    "crypto/rsa"
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

func TestProviderHTTPClientDoesNotFollowRedirects(t *testing.T) {
    targetHit := false
    target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
        targetHit = true
        w.WriteHeader(http.StatusOK)
    }))
    defer target.Close()

    redirect := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        http.Redirect(w, r, target.URL, http.StatusFound)
    }))
    defer redirect.Close()

    client := newProviderHTTPClient(time.Second)
    response, err := client.Get(redirect.URL)
    if err != nil {
        t.Fatalf("provider client returned error: %v", err)
    }
    defer response.Body.Close()

    if response.StatusCode != http.StatusFound {
        t.Fatalf("expected redirect response to remain visible, got %d", response.StatusCode)
    }
    if targetHit {
        t.Fatal("provider client followed redirect to another host")
    }
}

func TestReadJSONBodyRejectsOversizedPayload(t *testing.T) {
    oversized := `{"data":"` + strings.Repeat("x", maxProviderJSONBytes) + `"}`
    if _, err := readJSONBody(strings.NewReader(oversized)); err == nil {
        t.Fatal("expected oversized provider payload to be rejected")
    }
}

func TestReadJSONBodyRejectsContentBeyondSizeLimit(t *testing.T) {
    valid := `{"ok":true}`
    oversized := valid + strings.Repeat(" ", maxProviderJSONBytes-len(valid)+1)
    if _, err := readJSONBody(strings.NewReader(oversized)); err == nil {
        t.Fatal("expected payload containing content beyond the size limit to be rejected")
    }
}

func TestFreshnessStatus(t *testing.T) {
    now := time.Date(2026, 9, 23, 12, 0, 0, 0, time.UTC)
    entry := cacheEntry{
        freshUntil: now.Add(-1 * time.Minute),
        agingUntil: now.Add(9 * time.Minute),
        staleUntil: now.Add(49 * time.Minute),
    }

    if got := freshnessStatus(now, entry); got != "aging" {
        t.Fatalf("expected aging, got %s", got)
    }

    entry.agingUntil = now.Add(-1 * time.Minute)
    if got := freshnessStatus(now, entry); got != "stale" {
        t.Fatalf("expected stale, got %s", got)
    }

    entry.staleUntil = now.Add(-1 * time.Minute)
    if got := freshnessStatus(now, entry); got != "unavailable" {
        t.Fatalf("expected unavailable, got %s", got)
    }
}

func TestMunicipalityCodeValidation(t *testing.T) {
    for _, tc := range []struct {
        value string
        ok    bool
    }{
        {"03099", true},
        {"1234", false},
        {"123456", false},
        {"03O99", false},
    } {
        if got := validMunicipalityCode(tc.value); got != tc.ok {
            t.Fatalf("validMunicipalityCode(%q) = %v, want %v", tc.value, got, tc.ok)
        }
    }
}

func TestGetJSONWithRetryRetriesTransientProviderFailures(t *testing.T) {
    attempts := 0
    upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        attempts++
        if attempts < 3 {
            http.Error(w, "temporary failure", http.StatusServiceUnavailable)
            return
        }
        w.Header().Set("Content-Type", "application/json")
        _, _ = w.Write([]byte(`{"ok":true}`))
    }))
    defer upstream.Close()

    s := &server{client: upstream.Client()}
    payload, err := s.getJSONWithRetry(context.Background(), upstream.URL, nil)
    if err != nil {
        t.Fatalf("getJSONWithRetry returned error: %v", err)
    }
    if got := attempts; got != 3 {
        t.Fatalf("expected 3 attempts, got %d", got)
    }
    if ok, exists := payload["ok"].(bool); !exists || !ok {
        t.Fatalf("expected successful JSON payload, got %#v", payload)
    }
}

func TestGetJSONWithRetryDoesNotRetryPermanentClientErrors(t *testing.T) {
    attempts := 0
    upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        attempts++
        http.Error(w, "bad request", http.StatusBadRequest)
    }))
    defer upstream.Close()

    s := &server{client: upstream.Client()}
    if _, err := s.getJSONWithRetry(context.Background(), upstream.URL, nil); err == nil {
        t.Fatal("expected provider error")
    }
    if attempts != 1 {
        t.Fatalf("expected one attempt for permanent client error, got %d", attempts)
    }
}

func TestLoadConfigRejectsHTTPOIDCIssuer(t *testing.T) {
    setRequiredConfigEnv(t)
    t.Setenv("OIDC_ISSUER", "http://auth.example.com/realms/espana-outdoor")

    if _, err := loadConfig(time.Now().UTC()); err == nil {
        t.Fatal("expected HTTP OIDC issuer to be rejected")
    }
}

func TestLoadConfigRequiresOIDCRequiredRole(t *testing.T) {
    setRequiredConfigEnv(t)
    t.Setenv("OIDC_REQUIRED_ROLE", "")

    if _, err := loadConfig(time.Now().UTC()); err == nil {
        t.Fatal("expected missing OIDC_REQUIRED_ROLE to be rejected")
    }
}

func TestOIDCAudienceRejectsTokenIssuedForAnotherClient(t *testing.T) {
    verifier, issuer, signingKey, cleanup := newTestOIDCVerifier(t, "espana-outdoor")
    defer cleanup()

    validToken := signTestIDToken(t, signingKey, issuer, "espana-outdoor")
    if _, err := verifier.Verify(context.Background(), validToken); err != nil {
        t.Fatalf("expected token for configured audience to verify: %v", err)
    }

    foreignToken := signTestIDToken(t, signingKey, issuer, "another-client")
    if _, err := verifier.Verify(context.Background(), foreignToken); err == nil {
        t.Fatal("expected token issued for another client to be rejected")
    }
}

func TestOIDCAudienceRejectsMissingAudience(t *testing.T) {
    verifier, issuer, signingKey, cleanup := newTestOIDCVerifier(t, "espana-outdoor")
    defer cleanup()

    signer, err := jose.NewSigner(jose.SigningKey{Algorithm: jose.RS256, Key: signingKey}, nil)
    if err != nil {
        t.Fatalf("create signer: %v", err)
    }
    claims := map[string]any{
        "iss": issuer,
        "sub": "test-user",
        "iat": time.Now().Unix(),
        "exp": time.Now().Add(5 * time.Minute).Unix(),
    }
    token, err := jwt.Signed(signer).Claims(claims).Serialize()
    if err != nil {
        t.Fatalf("serialize token: %v", err)
    }

    if _, err := verifier.Verify(context.Background(), token); err == nil {
        t.Fatal("expected token without audience to be rejected")
    }
}

func TestOIDCJWTRejectsWrongIssuer(t *testing.T) {
    verifier, issuer, signingKey, cleanup := newTestOIDCVerifier(t, "espana-outdoor")
    defer cleanup()

    token := signTestIDTokenWithClaims(t, signingKey, issuer, "espana-outdoor", map[string]any{
        "iss": "https://unexpected.example/realms/other",
    })

    if _, err := verifier.Verify(context.Background(), token); err == nil {
        t.Fatal("expected token with wrong issuer to be rejected")
    }
}

func TestOIDCJWTRejectsExpiredToken(t *testing.T) {
    verifier, issuer, signingKey, cleanup := newTestOIDCVerifier(t, "espana-outdoor")
    defer cleanup()

    token := signTestIDTokenWithClaims(t, signingKey, issuer, "espana-outdoor", map[string]any{
        "exp": time.Now().Add(-1 * time.Minute).Unix(),
    })

    if _, err := verifier.Verify(context.Background(), token); err == nil {
        t.Fatal("expected expired token to be rejected")
    }
}

func TestOIDCJWTRejectsNotYetValidToken(t *testing.T) {
    verifier, issuer, signingKey, cleanup := newTestOIDCVerifier(t, "espana-outdoor")
    defer cleanup()

    token := signTestIDTokenWithClaims(t, signingKey, issuer, "espana-outdoor", map[string]any{
        "nbf": time.Now().Add(5 * time.Minute).Unix(),
    })
    verified, err := verifier.Verify(context.Background(), token)
    if err != nil {
        t.Fatalf("expected signature/issuer/audience validation to pass before temporal claim check: %v", err)
    }

    var claims map[string]any
    if err := verified.Claims(&claims); err != nil {
        t.Fatalf("decode claims: %v", err)
    }
    if err := validateTemporalClaims(claims, time.Now().UTC()); err == nil {
        t.Fatal("expected not-yet-valid token to be rejected by gateway temporal validation")
    }
}

func TestOIDCJWTRejectsFutureIssuedAt(t *testing.T) {
    verifier, issuer, signingKey, cleanup := newTestOIDCVerifier(t, "espana-outdoor")
    defer cleanup()

    token := signTestIDTokenWithClaims(t, signingKey, issuer, "espana-outdoor", map[string]any{
        "iat": time.Now().Add(5 * time.Minute).Unix(),
    })
    verified, err := verifier.Verify(context.Background(), token)
    if err != nil {
        t.Fatalf("expected signature/issuer/audience validation to pass before temporal claim check: %v", err)
    }

    var claims map[string]any
    if err := verified.Claims(&claims); err != nil {
        t.Fatalf("decode claims: %v", err)
    }
    if err := validateTemporalClaims(claims, time.Now().UTC()); err == nil {
        t.Fatal("expected future iat token to be rejected by gateway temporal validation")
    }
}

func TestOIDCJWTRejectsInvalidSignature(t *testing.T) {
    verifier, issuer, _, cleanup := newTestOIDCVerifier(t, "espana-outdoor")
    defer cleanup()

    otherKey, err := rsa.GenerateKey(rand.Reader, 2048)
    if err != nil {
        t.Fatalf("generate alternate signing key: %v", err)
    }

    token := signTestIDToken(t, otherKey, issuer, "espana-outdoor")
    if _, err := verifier.Verify(context.Background(), token); err == nil {
        t.Fatal("expected token with invalid signature to be rejected")
    }
}

func TestOIDCJWTRejectsMalformedToken(t *testing.T) {
    verifier, _, _, cleanup := newTestOIDCVerifier(t, "espana-outdoor")
    defer cleanup()

    if _, err := verifier.Verify(context.Background(), "not-a-jwt"); err == nil {
        t.Fatal("expected malformed token to be rejected")
    }
}

func newTestOIDCVerifier(t *testing.T, audience string) (*oidc.IDTokenVerifier, string, *rsa.PrivateKey, func()) {
    t.Helper()

    key, err := rsa.GenerateKey(rand.Reader, 2048)
    if err != nil {
        t.Fatalf("generate signing key: %v", err)
    }
    publicJWK := jose.JSONWebKey{Key: &key.PublicKey, KeyID: "test-key", Algorithm: string(jose.RS256), Use: "sig"}

    var server *httptest.Server
    server = httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        switch r.URL.Path {
        case "/.well-known/openid-configuration":
            w.Header().Set("Content-Type", "application/json")
            _ = json.NewEncoder(w).Encode(map[string]string{
                "issuer":   server.URL,
                "jwks_uri": server.URL + "/keys",
            })
        case "/keys":
            w.Header().Set("Content-Type", "application/json")
            _ = json.NewEncoder(w).Encode(jose.JSONWebKeySet{Keys: []jose.JSONWebKey{publicJWK}})
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

    return provider.Verifier(&oidc.Config{ClientID: audience}), server.URL, key, server.Close
}

func signTestIDToken(t *testing.T, key *rsa.PrivateKey, issuer, audience string) string {
    return signTestIDTokenWithClaims(t, key, issuer, audience, nil)
}

func signTestIDTokenWithClaims(t *testing.T, key *rsa.PrivateKey, issuer, audience string, overrides map[string]any) string {
    t.Helper()

    signer, err := jose.NewSigner(jose.SigningKey{Algorithm: jose.RS256, Key: key}, nil)
    if err != nil {
        t.Fatalf("create signer: %v", err)
    }

    claims := map[string]any{
        "iss": issuer,
        "sub": "test-user",
        "aud": audience,
        "typ": "Bearer",
        "iat": time.Now().Unix(),
        "exp": time.Now().Add(5 * time.Minute).Unix(),
    }
    for name, value := range overrides {
        claims[name] = value
    }

    token, err := jwt.Signed(signer).Claims(claims).Serialize()
    if err != nil {
        t.Fatalf("serialize token: %v", err)
    }
    return token
}

func setRequiredConfigEnv(t *testing.T) {
    t.Helper()
    t.Setenv("OIDC_ISSUER", "https://auth.example.com/realms/espana-outdoor")
    t.Setenv("OIDC_AUDIENCE", "espana-outdoor")
    t.Setenv("OIDC_REQUIRED_ROLE", "source.read")
    t.Setenv("AEMET_API_KEY", "fixture")
    t.Setenv("AEMET_API_KEY_EXPIRES_AT", time.Now().UTC().Add(time.Hour).Format(time.RFC3339))
    t.Setenv("AEMET_BASE_URL", "https://opendata.aemet.es/opendata/api")
    t.Setenv("CACHE_FRESH_TTL", "10m")
    t.Setenv("CACHE_AGING_TTL", "10m")
    t.Setenv("CACHE_STALE_TTL", "40m")
    t.Setenv("RATE_LIMIT_RPS", "2")
    t.Setenv("RATE_LIMIT_BURST", "10")
    t.Setenv("PROVIDER_TIMEOUT", "15s")
}
