package main

import (
    "net/http"
    "net/http/httptest"
    "testing"
    "time"
)

func TestOIDCClientRoleAcceptsRoleFromConfiguredClient(t *testing.T) {
    claims := map[string]any{
        "realm_access": map[string]any{"roles": []any{"source.read"}},
        "resource_access": map[string]any{
            "espana-outdoor": map[string]any{"roles": []any{"source.read"}},
            "another-client": map[string]any{"roles": []any{"admin"}},
        },
    }
    if err := authorizeClientRole(claims, "espana-outdoor", "source.read"); err != nil {
        t.Fatalf("expected configured client role to be accepted: %v", err)
    }
}

func TestOIDCClientRoleRejectsRealmRoleOnly(t *testing.T) {
    claims := map[string]any{
        "realm_access": map[string]any{"roles": []any{"source.read"}},
        "resource_access": map[string]any{},
    }
    if err := authorizeClientRole(claims, "espana-outdoor", "source.read"); err == nil {
        t.Fatal("expected realm role to be rejected as client authorization")
    }
}

func TestOIDCClientRoleRejectsRoleFromAnotherClient(t *testing.T) {
    claims := map[string]any{
        "resource_access": map[string]any{
            "another-client": map[string]any{"roles": []any{"source.read"}},
        },
    }
    if err := authorizeClientRole(claims, "espana-outdoor", "source.read"); err == nil {
        t.Fatal("expected role from another client to be rejected")
    }
}

func TestOIDCClientRoleRejectsSameRoleNameUnderWrongClient(t *testing.T) {
    claims := map[string]any{
        "resource_access": map[string]any{
            "another-client": map[string]any{"roles": []any{"source.read"}},
            "espana-outdoor": map[string]any{"roles": []any{"source.other"}},
        },
    }
    if err := authorizeClientRole(claims, "espana-outdoor", "source.read"); err == nil {
        t.Fatal("expected same role name in another client to be rejected")
    }
}

func TestOIDCClientRoleAcceptsCorrectRoleWithRolesFromMultipleClients(t *testing.T) {
    claims := map[string]any{
        "realm_access": map[string]any{"roles": []any{"source.read", "admin"}},
        "resource_access": map[string]any{
            "espana-outdoor": map[string]any{"roles": []any{"source.read"}},
            "admin-client":    map[string]any{"roles": []any{"admin"}},
        },
    }
    if err := authorizeClientRole(claims, "espana-outdoor", "source.read"); err != nil {
        t.Fatalf("expected source.read from configured client to be accepted: %v", err)
    }
}

func TestOIDCClientRoleRejectsRealmAdminWithoutExplicitClientAdmin(t *testing.T) {
    claims := map[string]any{
        "realm_access": map[string]any{"roles": []any{"admin"}},
        "resource_access": map[string]any{
            "espana-outdoor": map[string]any{"roles": []any{"source.read"}},
        },
    }
    if err := authorizeClientRole(claims, "espana-outdoor", "admin"); err == nil {
        t.Fatal("expected realm admin without explicit client admin to be rejected")
    }
}

func TestOIDCClientRoleRejectsPrivilegeEscalationAcrossClients(t *testing.T) {
    claims := map[string]any{
        "resource_access": map[string]any{
            "espana-outdoor": map[string]any{"roles": []any{"source.read"}},
            "admin-client":    map[string]any{"roles": []any{"admin"}},
        },
    }
    if err := authorizeClientRole(claims, "espana-outdoor", "admin"); err == nil {
        t.Fatal("expected admin privilege from another client to be rejected")
    }
}

func TestOIDCClientRoleRejectsMalformedAndMissingClaims(t *testing.T) {
    cases := []struct {
        name   string
        claims map[string]any
    }{
        {name: "missing resource_access", claims: map[string]any{}},
        {name: "malformed resource_access", claims: map[string]any{"resource_access": "malformed"}},
        {
            name:   "missing client roles",
            claims: map[string]any{"resource_access": map[string]any{"espana-outdoor": map[string]any{}}},
        },
        {
            name:   "malformed client roles",
            claims: map[string]any{"resource_access": map[string]any{"espana-outdoor": map[string]any{"roles": "malformed"}}},
        },
        {
            name:   "non-string role",
            claims: map[string]any{"resource_access": map[string]any{"espana-outdoor": map[string]any{"roles": []any{123, true}}}},
        },
    }

    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) {
            if err := authorizeClientRole(tc.claims, "espana-outdoor", "source.read"); err == nil {
                t.Fatal("expected malformed or missing authorization claims to be rejected")
            }
        })
    }
}

func TestOIDCClientRoleRejectsInvalidPolicyInputs(t *testing.T) {
    validClaims := map[string]any{
        "resource_access": map[string]any{
            "espana-outdoor": map[string]any{"roles": []any{"source.read"}},
        },
    }

    for _, tc := range []struct {
        clientID     string
        requiredRole string
    }{
        {clientID: "", requiredRole: "source.read"},
        {clientID: "espana-outdoor", requiredRole: ""},
    } {
        if err := authorizeClientRole(validClaims, tc.clientID, tc.requiredRole); err == nil {
            t.Fatalf("expected invalid policy input to be rejected: client=%q role=%q", tc.clientID, tc.requiredRole)
        }
    }
}

func TestOIDCAuthorizationIsEnforcedServerSideForSourceData(t *testing.T) {
    verifier, issuer, signingKey, cleanup := newTestOIDCVerifier(t, "espana-outdoor")
    defer cleanup()

    now := time.Now().UTC()
    newServer := func() *server {
        return &server{
            cfg: config{
                oidcAudience:     "espana-outdoor",
                oidcRequiredRole: "source.read",
                rateLimit:        100,
                rateBurst:        10,
            },
            verifier: verifier,
            cache: map[string]cacheEntry{
                "03099": {
                    data:       []map[string]any{{"date": "2026-10-05"}},
                    fetchedAt:  now,
                    freshUntil: now.Add(time.Minute),
                    agingUntil: now.Add(2 * time.Minute),
                    staleUntil: now.Add(3 * time.Minute),
                },
            },
            limiters: make(map[string]*limiterEntry),
        }
    }

    invoke := func(claims map[string]any) int {
        token := signTestAccessTokenWithClaims(t, signingKey, issuer, "espana-outdoor", claims)
        request := httptest.NewRequest(http.MethodGet, "/v1/sources/aemet-weather?municipalityCode=03099", nil)
        request.Header.Set("Authorization", "Bearer "+token)

        mux := http.NewServeMux()
        mux.HandleFunc("GET /v1/sources/{sourceID}", newServer().sourceData)

        recorder := httptest.NewRecorder()
        mux.ServeHTTP(recorder, request)
        return recorder.Code
    }

    t.Run("valid client role accepted", func(t *testing.T) {
        code := invoke(map[string]any{
            "resource_access": map[string]any{
                "espana-outdoor": map[string]any{"roles": []any{"source.read"}},
            },
        })
        if code != http.StatusOK {
            t.Fatalf("expected HTTP 200, got %d", code)
        }
    })

    t.Run("foreign client role rejected", func(t *testing.T) {
        code := invoke(map[string]any{
            "resource_access": map[string]any{
                "another-client": map[string]any{"roles": []any{"source.read"}},
            },
        })
        if code != http.StatusForbidden {
            t.Fatalf("expected HTTP 403, got %d", code)
        }
    })

    t.Run("realm role rejected without client role", func(t *testing.T) {
        code := invoke(map[string]any{
            "realm_access": map[string]any{"roles": []any{"source.read"}},
            "resource_access": map[string]any{},
        })
        if code != http.StatusForbidden {
            t.Fatalf("expected HTTP 403, got %d", code)
        }
    })

    t.Run("same role name on wrong client rejected", func(t *testing.T) {
        code := invoke(map[string]any{
            "resource_access": map[string]any{
                "another-client": map[string]any{"roles": []any{"source.read"}},
                "espana-outdoor": map[string]any{"roles": []any{"source.other"}},
            },
        })
        if code != http.StatusForbidden {
            t.Fatalf("expected HTTP 403, got %d", code)
        }
    })
}
