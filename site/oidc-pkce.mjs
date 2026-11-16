const encoder = new TextEncoder();

function requireHttpsUrl(value, label) {
  const url = new URL(value);
  if (url.protocol !== "https:" || url.username || url.password) {
    throw new TypeError(`${label} must be an HTTPS URL without credentials.`);
  }
  return url;
}

export function base64UrlEncode(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

export function createRandomToken(cryptoApi = globalThis.crypto) {
  if (!cryptoApi?.getRandomValues) {
    throw new Error("Secure browser randomness is unavailable.");
  }
  return base64UrlEncode(cryptoApi.getRandomValues(new Uint8Array(32)));
}

export async function createPkcePair(cryptoApi = globalThis.crypto) {
  if (!cryptoApi?.subtle?.digest) {
    throw new Error("Web Crypto SHA-256 is unavailable.");
  }
  const verifier = createRandomToken(cryptoApi);
  const digest = await cryptoApi.subtle.digest("SHA-256", encoder.encode(verifier));
  return { verifier, challenge: base64UrlEncode(new Uint8Array(digest)) };
}

export function stateMatches(expected, received) {
  return typeof expected === "string" &&
    expected.length >= 32 &&
    typeof received === "string" &&
    received.length === expected.length &&
    received === expected;
}

export async function loadOidcDiscovery(issuer, fetchImpl = fetch) {
  const issuerUrl = requireHttpsUrl(issuer, "OIDC issuer");
  const normalizedIssuer = issuerUrl.href.replace(/\/+$/, "");
  const discoveryUrl = `${normalizedIssuer}/.well-known/openid-configuration`;
  const response = await fetchImpl(discoveryUrl, {
    method: "GET",
    headers: { Accept: "application/json" },
    cache: "no-store",
    credentials: "omit",
    redirect: "error",
  });
  if (!response.ok) throw new Error("OIDC_DISCOVERY_FAILED");

  const document = await response.json();
  if (
    !Array.isArray(document.response_types_supported) ||
    !document.response_types_supported.includes("code")
  ) {
    throw new Error("OIDC_CODE_FLOW_UNSUPPORTED");
  }
  if (
    !Array.isArray(document.code_challenge_methods_supported) ||
    !document.code_challenge_methods_supported.includes("S256")
  ) {
    throw new Error("OIDC_PKCE_S256_UNSUPPORTED");
  }
  if (
    Array.isArray(document.grant_types_supported) &&
    !document.grant_types_supported.includes("authorization_code")
  ) {
    throw new Error("OIDC_AUTHORIZATION_CODE_UNSUPPORTED");
  }

  const discoveredIssuer = typeof document.issuer === "string"
    ? document.issuer.replace(/\/+$/, "")
    : "";
  if (discoveredIssuer !== normalizedIssuer) {
    throw new Error("OIDC_ISSUER_MISMATCH");
  }

  const authorizationEndpoint = requireHttpsUrl(
    document.authorization_endpoint,
    "OIDC authorization endpoint",
  );
  const tokenEndpoint = requireHttpsUrl(
    document.token_endpoint,
    "OIDC token endpoint",
  );
  if (
    authorizationEndpoint.origin !== issuerUrl.origin ||
    tokenEndpoint.origin !== issuerUrl.origin
  ) {
    throw new Error("OIDC_ENDPOINT_ORIGIN_MISMATCH");
  }
  return {
    authorizationEndpoint: authorizationEndpoint.href,
    tokenEndpoint: tokenEndpoint.href,
  };
}

export function buildAuthorizationUrl({
  authorizationEndpoint,
  clientId,
  redirectUri,
  scope = "profile email",
  state,
  codeChallenge,
}) {
  const endpoint = requireHttpsUrl(
    authorizationEndpoint,
    "OIDC authorization endpoint",
  );
  const redirect = requireHttpsUrl(redirectUri, "OIDC redirect URI");
  if (!clientId || !state || state.length < 32 || !codeChallenge) {
    throw new TypeError("OIDC client, state and PKCE challenge are required.");
  }
  endpoint.searchParams.set("client_id", clientId);
  endpoint.searchParams.set("redirect_uri", redirect.href);
  endpoint.searchParams.set("response_type", "code");
  endpoint.searchParams.set("response_mode", "query");
  endpoint.searchParams.set("scope", scope);
  endpoint.searchParams.set("state", state);
  endpoint.searchParams.set("code_challenge", codeChallenge);
  endpoint.searchParams.set("code_challenge_method", "S256");
  return endpoint;
}

export async function exchangeAuthorizationCode({
  tokenEndpoint,
  clientId,
  redirectUri,
  code,
  codeVerifier,
  fetchImpl = fetch,
  now = Date.now,
}) {
  const endpoint = requireHttpsUrl(tokenEndpoint, "OIDC token endpoint");
  const redirect = requireHttpsUrl(redirectUri, "OIDC redirect URI");
  if (!clientId || !code || !codeVerifier) {
    throw new TypeError("OIDC authorization code exchange is incomplete.");
  }

  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: clientId,
    code,
    redirect_uri: redirect.href,
    code_verifier: codeVerifier,
  });
  const response = await fetchImpl(endpoint.href, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
    cache: "no-store",
    credentials: "omit",
    redirect: "error",
  });
  if (!response.ok) throw new Error("OIDC_TOKEN_EXCHANGE_FAILED");

  const tokens = await response.json();
  const expiresIn = Number(tokens.expires_in);
  if (
    typeof tokens.access_token !== "string" ||
    tokens.access_token.length < 20 ||
    typeof tokens.token_type !== "string" ||
    tokens.token_type.toLowerCase() !== "bearer" ||
    !Number.isFinite(expiresIn) ||
    expiresIn <= 0
  ) {
    throw new Error("OIDC_TOKEN_RESPONSE_INVALID");
  }

  return {
    accessToken: tokens.access_token,
    expiresAt: now() + expiresIn * 1000,
  };
}
