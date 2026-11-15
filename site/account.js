import {
  buildAuthorizationUrl,
  createPkcePair,
  createRandomToken,
  exchangeAuthorizationCode,
  loadOidcDiscovery,
  stateMatches,
} from "./oidc-pkce.mjs";

const OIDC_ISSUER = "https://auth.espanaoutdoor.es/realms/espana-outdoor";
const OIDC_CLIENT_ID = "espana-outdoors-mobile";
const COMMUNITY_API_BASE_URL = "https://api.espanaoutdoor.es";
const ALLOWED_WEB_ORIGINS = new Set([
  "https://espanaoutdoor.es",
  "https://www.espanaoutdoor.es",
]);
const REDIRECT_URI = new URL("/cuenta.html", window.location.origin).href;
const TRANSACTION_KEY = "espana-outdoor.oidc.transaction";
const SESSION_KEY = "espana-outdoor.oidc.session";
const TRANSACTION_MAX_AGE_MS = 10 * 60 * 1000;

const statusNode = document.querySelector("[data-account-status]");
const signedOutPanel = document.querySelector("[data-account-signed-out]");
const profileForm = document.querySelector("[data-profile-form]");
const profileSummary = document.querySelector("[data-profile-summary]");
const displayNameInput = document.querySelector("#display-name");
const profileNameNode = document.querySelector("[data-profile-name]");
const profileEmailNode = document.querySelector("[data-profile-email]");
const signInButton = document.querySelector("[data-sign-in]");
const signOutButton = document.querySelector("[data-sign-out]");

function setStatus(message, tone = "info") {
  if (!statusNode) return;
  statusNode.textContent = message;
  statusNode.dataset.tone = tone;
}

function clearSession() {
  sessionStorage.removeItem(SESSION_KEY);
}

function readSession() {
  try {
    const value = JSON.parse(sessionStorage.getItem(SESSION_KEY) || "null");
    if (
      !value ||
      typeof value.accessToken !== "string" ||
      !Number.isFinite(value.expiresAt) ||
      value.expiresAt <= Date.now() + 30_000
    ) {
      clearSession();
      return null;
    }
    return value;
  } catch {
    clearSession();
    return null;
  }
}

function showSignedOut(message) {
  signedOutPanel.hidden = false;
  profileForm.hidden = true;
  profileSummary.hidden = true;
  setStatus(message);
}

function showProfile(profile) {
  signedOutPanel.hidden = true;
  profileForm.hidden = false;
  profileSummary.hidden = false;
  displayNameInput.value = profile.displayName || "";
  profileNameNode.textContent = profile.displayName || "Sin nombre público";
  profileEmailNode.textContent = profile.email || "Correo no verificado o no compartido";
  setStatus("Perfil sincronizado con la cuenta de España Outdoor.", "success");
}

function apiErrorMessage(status) {
  if (status === 401) return "La sesión ha caducado. Vuelve a identificarte.";
  if (status === 403) return "El proveedor de identidad no autoriza este cliente.";
  if (status === 429) return "Demasiadas solicitudes. Espera un momento y vuelve a intentarlo.";
  if (status === 503) return "El servicio de perfiles no está disponible. Falta completar su despliegue o la base de datos.";
  return `No se pudo completar la operación (HTTP ${status}).`;
}

async function requestProfile(session, method = "GET", payload) {
  const response = await fetch(new URL("/v1/me", COMMUNITY_API_BASE_URL), {
    method,
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${session.accessToken}`,
      ...(payload ? { "Content-Type": "application/json" } : {}),
    },
    body: payload ? JSON.stringify(payload) : undefined,
    cache: "no-store",
    credentials: "omit",
    redirect: "error",
  });
  if (response.status === 401) clearSession();
  if (!response.ok) throw new Error(apiErrorMessage(response.status));
  return response.json();
}

async function beginSignIn() {
  if (!ALLOWED_WEB_ORIGINS.has(window.location.origin)) {
    throw new Error("El acceso web solo está habilitado en el dominio oficial.");
  }
  const discovery = await loadOidcDiscovery(OIDC_ISSUER);
  const pkce = await createPkcePair();
  const state = createRandomToken();
  sessionStorage.setItem(TRANSACTION_KEY, JSON.stringify({
    state,
    verifier: pkce.verifier,
    createdAt: Date.now(),
  }));
  const authorizationUrl = buildAuthorizationUrl({
    authorizationEndpoint: discovery.authorizationEndpoint,
    clientId: OIDC_CLIENT_ID,
    redirectUri: REDIRECT_URI,
    state,
    codeChallenge: pkce.challenge,
  });
  window.location.assign(authorizationUrl.href);
}

async function completeCallback() {
  const params = new URLSearchParams(window.location.search);
  const code = params.get("code");
  const providerError = params.get("error");
  if (!code && !providerError) return;

  // Remove authorization codes and provider error details from browser history
  // before making any subsequent network request.
  window.history.replaceState({}, document.title, window.location.pathname);
  if (providerError) {
    sessionStorage.removeItem(TRANSACTION_KEY);
    throw new Error("El proveedor de identidad ha cancelado el acceso.");
  }

  let transaction;
  try {
    transaction = JSON.parse(sessionStorage.getItem(TRANSACTION_KEY) || "null");
  } catch {
    transaction = null;
  }
  sessionStorage.removeItem(TRANSACTION_KEY);

  if (
    !transaction ||
    typeof transaction.state !== "string" ||
    typeof transaction.verifier !== "string" ||
    !Number.isFinite(transaction.createdAt) ||
    Date.now() - transaction.createdAt > TRANSACTION_MAX_AGE_MS ||
    !stateMatches(transaction.state, params.get("state"))
  ) {
    throw new Error("La respuesta de autenticación no supera la validación de estado. Repite el acceso.");
  }

  const discovery = await loadOidcDiscovery(OIDC_ISSUER);
  const token = await exchangeAuthorizationCode({
    tokenEndpoint: discovery.tokenEndpoint,
    clientId: OIDC_CLIENT_ID,
    redirectUri: REDIRECT_URI,
    code,
    codeVerifier: transaction.verifier,
  });
  sessionStorage.setItem(SESSION_KEY, JSON.stringify(token));
}

async function refreshProfile() {
  const session = readSession();
  if (!session) {
    showSignedOut("Accede o crea una cuenta para sincronizar tu perfil con Android.");
    return;
  }
  try {
    const profile = await requestProfile(session);
    showProfile(profile);
  } catch (error) {
    if (!readSession()) {
      showSignedOut(error.message);
      return;
    }
    showSignedOut(error instanceof Error ? error.message : "No se pudo cargar el perfil.");
  }
}

signInButton?.addEventListener("click", async () => {
  signInButton.disabled = true;
  setStatus("Conectando con el proveedor de identidad…");
  try {
    await beginSignIn();
  } catch (error) {
    setStatus(error instanceof Error ? error.message : "No se pudo iniciar el acceso.", "error");
    signInButton.disabled = false;
  }
});

profileForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  const session = readSession();
  if (!session) {
    showSignedOut("La sesión ha caducado. Vuelve a identificarte.");
    return;
  }
  const displayName = displayNameInput.value.trim();
  if (displayName.length < 2 || displayName.length > 80) {
    setStatus("El nombre visible debe tener entre 2 y 80 caracteres.", "error");
    return;
  }
  const saveButton = profileForm.querySelector('button[type="submit"]');
  saveButton.disabled = true;
  try {
    const profile = await requestProfile(session, "PATCH", { displayName });
    showProfile(profile);
    setStatus("Perfil actualizado y sincronizado.", "success");
  } catch (error) {
    setStatus(error instanceof Error ? error.message : "No se pudo guardar el perfil.", "error");
  } finally {
    saveButton.disabled = false;
  }
});

signOutButton?.addEventListener("click", () => {
  clearSession();
  showSignedOut("Sesión cerrada en este navegador. La sesión del proveedor puede seguir activa hasta que expire.");
});

async function initializeAccountPage() {
  if (!ALLOWED_WEB_ORIGINS.has(window.location.origin)) {
    signInButton.disabled = true;
    showSignedOut("La autenticación está restringida a espanaoutdoor.es y www.espanaoutdoor.es.");
    return;
  }
  try {
    await completeCallback();
    await refreshProfile();
  } catch (error) {
    clearSession();
    showSignedOut(error instanceof Error ? error.message : "No se pudo completar la autenticación.");
  }
}

initializeAccountPage();
