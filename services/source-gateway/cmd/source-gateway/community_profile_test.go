package main

import (
    "context"
    "encoding/json"
    "net/http"
    "net/http/httptest"
    "strings"
    "sync"
    "testing"
    "time"
)

type memoryCommunityProfileStore struct {
    mu sync.Mutex
    profiles map[string]communityProfile
    lastSubject string
}

func (s *memoryCommunityProfileStore) upsert(_ context.Context, subject, email, displayName string) (communityProfile, error) {
    s.mu.Lock()
    defer s.mu.Unlock()
    if s.profiles == nil { s.profiles = make(map[string]communityProfile) }
    profile, exists := s.profiles[subject]
    if !exists {
        profile = communityProfile{
            ID: "canonical-" + subject,
            CreatedAt: time.Date(2026, 11, 14, 10, 0, 0, 0, time.UTC),
        }
    }
    if email != "" { profile.Email = email }
    if profile.DisplayName == "" && displayName != "" { profile.DisplayName = displayName }
    s.profiles[subject] = profile
    s.lastSubject = subject
    return profile, nil
}

func (s *memoryCommunityProfileStore) updateDisplayName(_ context.Context, subject, displayName string) (communityProfile, error) {
    s.mu.Lock()
    defer s.mu.Unlock()
    profile, exists := s.profiles[subject]
    if !exists { return communityProfile{}, errCommunityProfileNotFound }
    profile.DisplayName = displayName
    s.profiles[subject] = profile
    s.lastSubject = subject
    return profile, nil
}

func newCommunityProfileTestServer(t *testing.T, claims map[string]any) (*server, string, *memoryCommunityProfileStore, func()) {
    t.Helper()
    verifier, issuer, signingKey, cleanup := newTestOIDCVerifier(t, "espana-outdoors-mobile")
    token := signTestIDTokenWithClaims(t, signingKey, issuer, "espana-outdoors-mobile", claims)
    store := &memoryCommunityProfileStore{}
    srv := &server{
        cfg: config{
            oidcAudience: "espana-outdoors-mobile",
            rateLimit: 100,
            rateBurst: 100,
            allowedOrigins: map[string]struct{}{"https://espanaoutdoor.es": {}},
        },
        verifier: verifier,
        profiles: store,
        limiters: make(map[string]*limiterEntry),
    }
    return srv, token, store, cleanup
}

func TestMyProfileUsesVerifiedSubjectAndVerifiedEmail(t *testing.T) {
    srv, token, store, cleanup := newCommunityProfileTestServer(t, map[string]any{
        "sub": "user-123",
        "name": "Outdoor User",
        "email": "verified@example.test",
        "email_verified": true,
    })
    defer cleanup()

    request := httptest.NewRequest(http.MethodGet, "/v1/me", nil)
    request.Header.Set("Authorization", "Bearer "+token)
    response := httptest.NewRecorder()
    srv.myProfile(response, request)

    if response.Code != http.StatusOK {
        t.Fatalf("expected 200, got %d: %s", response.Code, response.Body.String())
    }
    var profile communityProfile
    if err := json.Unmarshal(response.Body.Bytes(), &profile); err != nil {
        t.Fatalf("decode profile: %v", err)
    }
    if profile.ID != "canonical-user-123" || profile.DisplayName != "Outdoor User" || profile.Email != "verified@example.test" {
        t.Fatalf("unexpected canonical profile: %#v", profile)
    }
    if store.lastSubject != "user-123" {
        t.Fatalf("profile store used subject %q, want verified token subject", store.lastSubject)
    }
    if strings.Contains(response.Body.String(), "subject") {
        t.Fatal("internal OIDC subject must not be exposed to clients")
    }
}

func TestMyProfileDoesNotImportUnverifiedEmail(t *testing.T) {
    srv, token, _, cleanup := newCommunityProfileTestServer(t, map[string]any{
        "sub": "user-456",
        "email": "unverified@example.test",
        "email_verified": false,
    })
    defer cleanup()

    request := httptest.NewRequest(http.MethodGet, "/v1/me", nil)
    request.Header.Set("Authorization", "Bearer "+token)
    response := httptest.NewRecorder()
    srv.myProfile(response, request)

    if response.Code != http.StatusOK {
        t.Fatalf("expected 200, got %d: %s", response.Code, response.Body.String())
    }
    if strings.Contains(response.Body.String(), "unverified@example.test") {
        t.Fatal("unverified email must not be stored or returned")
    }
}

func TestUpdateMyProfileCannotChooseAnotherSubject(t *testing.T) {
    srv, token, store, cleanup := newCommunityProfileTestServer(t, map[string]any{"sub": "user-123"})
    defer cleanup()

    request := httptest.NewRequest(http.MethodPatch, "/v1/me", strings.NewReader("{\"displayName\":\"New Name\",\"subject\":\"victim\"}"))
    request.Header.Set("Authorization", "Bearer "+token)
    request.Header.Set("Content-Type", "application/json")
    response := httptest.NewRecorder()
    srv.updateMyProfile(response, request)

    if response.Code != http.StatusBadRequest {
        t.Fatalf("expected 400 for unrecognized subject field, got %d", response.Code)
    }
    if store.lastSubject != "" {
        t.Fatal("invalid request must not provision or update a profile")
    }
}

func TestUpdateMyProfileChangesAuthenticatedProfileOnly(t *testing.T) {
    srv, token, store, cleanup := newCommunityProfileTestServer(t, map[string]any{"sub": "user-123"})
    defer cleanup()

    request := httptest.NewRequest(http.MethodPatch, "/v1/me", strings.NewReader("{\"displayName\":\"New Name\"}"))
    request.Header.Set("Authorization", "Bearer "+token)
    request.Header.Set("Content-Type", "application/json")
    response := httptest.NewRecorder()
    srv.updateMyProfile(response, request)

    if response.Code != http.StatusOK {
        t.Fatalf("expected 200, got %d: %s", response.Code, response.Body.String())
    }
    if store.lastSubject != "user-123" {
        t.Fatalf("updated subject %q, want authenticated subject", store.lastSubject)
    }
    var profile communityProfile
    if err := json.Unmarshal(response.Body.Bytes(), &profile); err != nil {
        t.Fatalf("decode profile: %v", err)
    }
    if profile.DisplayName != "New Name" {
        t.Fatalf("display name = %q, want New Name", profile.DisplayName)
    }
}

func TestMyProfileRequiresBearerToken(t *testing.T) {
    srv, _, _, cleanup := newCommunityProfileTestServer(t, nil)
    defer cleanup()

    request := httptest.NewRequest(http.MethodGet, "/v1/me", nil)
    response := httptest.NewRecorder()
    srv.myProfile(response, request)
    if response.Code != http.StatusUnauthorized {
        t.Fatalf("expected 401, got %d", response.Code)
    }
}

func TestMyProfileRejectsWrongAudience(t *testing.T) {
    verifier, issuer, signingKey, cleanup := newTestOIDCVerifier(t, "espana-outdoors-mobile")
    defer cleanup()
    token := signTestIDToken(t, signingKey, issuer, "another-client")
    srv := &server{
        cfg: config{oidcAudience: "espana-outdoors-mobile", rateLimit: 10, rateBurst: 10},
        verifier: verifier,
        profiles: &memoryCommunityProfileStore{},
        limiters: make(map[string]*limiterEntry),
    }

    request := httptest.NewRequest(http.MethodGet, "/v1/me", nil)
    request.Header.Set("Authorization", "Bearer "+token)
    response := httptest.NewRecorder()
    srv.myProfile(response, request)
    if response.Code != http.StatusUnauthorized {
        t.Fatalf("expected 401 for wrong audience, got %d", response.Code)
    }
}

func TestCommunityProfileCORSAllowsConfiguredOriginOnly(t *testing.T) {
    srv := &server{cfg: config{allowedOrigins: map[string]struct{}{"https://espanaoutdoor.es": {}}}}
    handler := srv.securityHeaders(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
        w.WriteHeader(http.StatusOK)
    }))

    allowed := httptest.NewRequest(http.MethodOptions, "/v1/me", nil)
    allowed.Header.Set("Origin", "https://espanaoutdoor.es")
    allowedResponse := httptest.NewRecorder()
    handler.ServeHTTP(allowedResponse, allowed)
    if allowedResponse.Code != http.StatusNoContent || allowedResponse.Header().Get("Access-Control-Allow-Origin") != "https://espanaoutdoor.es" {
        t.Fatalf("configured origin was not allowed: %d %#v", allowedResponse.Code, allowedResponse.Header())
    }

    denied := httptest.NewRequest(http.MethodOptions, "/v1/me", nil)
    denied.Header.Set("Origin", "https://attacker.example")
    deniedResponse := httptest.NewRecorder()
    handler.ServeHTTP(deniedResponse, denied)
    if deniedResponse.Code != http.StatusForbidden {
        t.Fatalf("untrusted origin should be rejected, got %d", deniedResponse.Code)
    }
}

func TestNormalizeDisplayName(t *testing.T) {
    if value, err := normalizeDisplayName("  Outdoor User  "); err != nil || value != "Outdoor User" {
        t.Fatalf("valid display name rejected: %q %v", value, err)
    }
    if _, err := normalizeDisplayName("x"); err == nil {
        t.Fatal("one-character display name must be rejected")
    }
    if _, err := normalizeDisplayName(strings.Repeat("x", 81)); err == nil {
        t.Fatal("display name over 80 characters must be rejected")
    }
    if _, err := normalizeDisplayName("bad\nname"); err == nil {
        t.Fatal("control characters must be rejected")
    }
}
