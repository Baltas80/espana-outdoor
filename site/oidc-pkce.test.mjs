import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import test from "node:test";

import {
  buildAuthorizationUrl,
  createPkcePair,
  createRandomToken,
  exchangeAuthorizationCode,
  loadOidcDiscovery,
  stateMatches,
} from "./oidc-pkce.mjs";

const issuer = "https://auth.espanaoutdoor.es/realms/espana-outdoor";
const redirectUri = "https://espanaoutdoor.es/cuenta.html";

test("PKCE creates a high-entropy verifier and an S256 challenge", async () => {
  const pair = await createPkcePair(webcrypto);
  assert.match(pair.verifier, /^[A-Za-z0-9_-]{43}$/);
  assert.match(pair.challenge, /^[A-Za-z0-9_-]{43}$/);
  assert.notEqual(pair.verifier, pair.challenge);
});

test("state tokens are random and callback comparison is strict", () => {
  const state = createRandomToken(webcrypto);
  assert.match(state, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(stateMatches(state, state), true);
  assert.equal(stateMatches(state, `${state}x`), false);
  assert.equal(stateMatches("short", "short"), false);
});

test("authorization URL uses code flow and S256 without a client secret", () => {
  const url = buildAuthorizationUrl({
    authorizationEndpoint: `${issuer}/protocol/openid-connect/auth`,
    clientId: "espana-outdoors-web",
    redirectUri,
    state: "a".repeat(43),
    codeChallenge: "b".repeat(43),
  });
  assert.equal(url.searchParams.get("response_type"), "code");
  assert.equal(url.searchParams.get("code_challenge_method"), "S256");
  assert.equal(url.searchParams.get("client_id"), "espana-outdoors-web");
  assert.equal(url.searchParams.get("scope"), "profile email");
  assert.equal(url.searchParams.get("scope").split(" ").includes("openid"), false);
  assert.equal(url.searchParams.has("client_secret"), false);
});

test("authorization URL rejects insecure endpoints and redirect URIs", () => {
  assert.throws(() => buildAuthorizationUrl({
    authorizationEndpoint: "http://auth.example.test/authorize",
    clientId: "web",
    redirectUri,
    state: "a".repeat(43),
    codeChallenge: "b".repeat(43),
  }));
  assert.throws(() => buildAuthorizationUrl({
    authorizationEndpoint: `${issuer}/authorize`,
    clientId: "web",
    redirectUri: "http://espanaoutdoor.es/cuenta.html",
    state: "a".repeat(43),
    codeChallenge: "b".repeat(43),
  }));
});

test("discovery requires the configured issuer and same-origin HTTPS endpoints", async () => {
  const validFetch = async () => ({
    ok: true,
    json: async () => ({
      issuer,
      authorization_endpoint: `${issuer}/protocol/openid-connect/auth`,
      token_endpoint: `${issuer}/protocol/openid-connect/token`,
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
    }),
  });
  const document = await loadOidcDiscovery(issuer, validFetch);
  assert.equal(document.tokenEndpoint, `${issuer}/protocol/openid-connect/token`);

  await assert.rejects(
    loadOidcDiscovery(issuer, async () => ({
      ok: true,
      json: async () => ({
        issuer: "https://attacker.example/realm",
        authorization_endpoint: "https://attacker.example/auth",
        token_endpoint: "https://attacker.example/token",
        response_types_supported: ["code"],
        code_challenge_methods_supported: ["S256"],
      }),
    })),
    /OIDC_ISSUER_MISMATCH/,
  );

  await assert.rejects(
    loadOidcDiscovery(issuer, async () => ({
      ok: true,
      json: async () => ({
        issuer,
        authorization_endpoint: `${issuer}/protocol/openid-connect/auth`,
        token_endpoint: `${issuer}/protocol/openid-connect/token`,
        response_types_supported: ["code"],
        code_challenge_methods_supported: ["plain"],
      }),
    })),
    /OIDC_PKCE_S256_UNSUPPORTED/,
  );
});

test("token exchange sends PKCE fields and accepts only a bearer access token", async () => {
  let captured;
  const result = await exchangeAuthorizationCode({
    tokenEndpoint: `${issuer}/protocol/openid-connect/token`,
    clientId: "espana-outdoors-web",
    redirectUri,
    code: "authorization-code",
    codeVerifier: "v".repeat(43),
    now: () => 1_000,
    fetchImpl: async (_url, options) => {
      captured = new URLSearchParams(options.body);
      return {
        ok: true,
        json: async () => ({
          access_token: "x".repeat(32),
          token_type: "Bearer",
          expires_in: 300,
          refresh_token: "must-not-be-stored",
        }),
      };
    },
  });
  assert.equal(captured.get("grant_type"), "authorization_code");
  assert.equal(captured.get("code_verifier"), "v".repeat(43));
  assert.equal(captured.get("client_secret"), null);
  assert.deepEqual(result, { accessToken: "x".repeat(32), expiresAt: 301_000 });

  await assert.rejects(
    exchangeAuthorizationCode({
      tokenEndpoint: `${issuer}/protocol/openid-connect/token`,
      clientId: "espana-outdoors-web",
      redirectUri,
      code: "authorization-code",
      codeVerifier: "v".repeat(43),
      fetchImpl: async () => ({
        ok: true,
        json: async () => ({
          access_token: "x".repeat(32),
          token_type: "mac",
          expires_in: 300,
        }),
      }),
    }),
    /OIDC_TOKEN_RESPONSE_INVALID/,
  );
});
