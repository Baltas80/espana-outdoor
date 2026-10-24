import Keycloak from 'https://esm.sh/keycloak-js@26.2.4';

const config = window.ESPANA_OUTDOOR_PROFILE_CONFIG;
const statusNode = document.querySelector('[data-account-status]');
const signedOutPanel = document.querySelector('[data-account-signed-out]');
const signedInPanel = document.querySelector('[data-account-signed-in]');
const form = document.querySelector('[data-account-form]');
const loginButton = document.querySelector('[data-account-login]');
const registerButton = document.querySelector('[data-account-register]');
const logoutButton = document.querySelector('[data-account-logout]');
const saveButton = document.querySelector('[data-account-save]');
const displayName = document.querySelector('#account-display-name');
const username = document.querySelector('#account-username');
const homeArea = document.querySelector('#account-home-area');
const bio = document.querySelector('#account-bio');

const apiBaseUrl = String(config?.apiBaseUrl || '').replace(/\/$/, '');
let keycloak = null;
let apiReady = false;

function showStatus(message, kind = 'info') {
  if (!statusNode) return;
  statusNode.textContent = message;
  statusNode.dataset.kind = kind;
}

function setBusy(busy) {
  for (const button of [loginButton, registerButton, logoutButton, saveButton]) {
    if (button) button.disabled = busy;
  }
}

function showSession(authenticated) {
  if (signedOutPanel) signedOutPanel.hidden = authenticated;
  if (signedInPanel) signedInPanel.hidden = !authenticated;
}

function fillForm(profile) {
  displayName.value = profile?.displayName || '';
  username.value = profile?.username || '';
  homeArea.value = profile?.homeArea || '';
  bio.value = profile?.bio || '';
}

function readForm() {
  return {
    displayName: displayName.value.trim(),
    username: username.value.trim().toLowerCase(),
    homeArea: homeArea.value.trim(),
    bio: bio.value.trim(),
  };
}

async function apiRequest(method, body) {
  if (!keycloak?.authenticated) {
    throw new Error('Inicia sesión para acceder a tu perfil.');
  }
  if (!apiBaseUrl.startsWith('https://')) {
    throw new Error('La API de perfiles no tiene una URL HTTPS válida.');
  }

  await keycloak.updateToken(30);
  const response = await fetch(apiBaseUrl + '/v1/me/profile', {
    method,
    headers: {
      Accept: 'application/json',
      Authorization: 'Bearer ' + keycloak.token,
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
    cache: 'no-store',
    credentials: 'omit',
  });

  if (response.status === 404 && method === 'GET') return null;

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    if (response.status === 409) {
      throw new Error('Ese alias ya está en uso. Elige otro.');
    }
    if (response.status === 401) {
      throw new Error('La sesión ha caducado. Vuelve a iniciar sesión.');
    }
    if (response.status === 400 && payload.error) {
      throw new Error(payload.error);
    }
    throw new Error('El servicio de perfiles no está disponible. Inténtalo más tarde.');
  }
  return payload;
}

async function loadProfile() {
  const profile = await apiRequest('GET');
  fillForm(profile);
  showStatus(
    profile
      ? 'Cuenta conectada. Este perfil es el mismo que usa la aplicación Android.'
      : 'Cuenta conectada. Completa el perfil y guárdalo para usarlo en web y app.',
    'success',
  );
}

async function authenticate(action) {
  if (!keycloak) {
    showStatus('No se ha podido inicializar el proveedor de cuentas.', 'error');
    return;
  }
  setBusy(true);
  try {
    const options = { redirectUri: window.location.href, scope: 'openid profile email' };
    if (action === 'register') await keycloak.register(options);
    else await keycloak.login(options);
  } catch {
    setBusy(false);
    showStatus('No se pudo abrir el proveedor de cuentas. Revisa la conexión.', 'error');
  }
}

loginButton?.addEventListener('click', () => authenticate('login'));
registerButton?.addEventListener('click', () => authenticate('register'));

logoutButton?.addEventListener('click', async () => {
  if (!keycloak) return;
  setBusy(true);
  try {
    await keycloak.logout({ redirectUri: window.location.origin + '/cuenta.html' });
  } catch {
    setBusy(false);
    showStatus('No se pudo cerrar la sesión en el proveedor.', 'error');
  }
});

form?.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!form.reportValidity()) return;

  const profile = readForm();
  const handlePattern = /^[a-z0-9][a-z0-9._-]{2,19}$/;
  if (profile.displayName.length < 2 || profile.displayName.length > 50) {
    showStatus('El nombre visible debe tener entre 2 y 50 caracteres.', 'error');
    return;
  }
  if (!handlePattern.test(profile.username)) {
    showStatus('El alias debe tener entre 3 y 20 caracteres válidos.', 'error');
    return;
  }
  if (profile.homeArea.length > 80 || profile.bio.length > 160) {
    showStatus('La zona o la presentación supera la longitud permitida.', 'error');
    return;
  }

  setBusy(true);
  try {
    const saved = await apiRequest('PUT', profile);
    fillForm(saved);
    showStatus('Perfil guardado en el servidor. Ya está disponible en la app y en la web.', 'success');
  } catch (error) {
    showStatus(error instanceof Error ? error.message : 'No se pudo guardar el perfil.', 'error');
  } finally {
    setBusy(false);
  }
});

async function initialise() {
  if (!config?.authUrl || !config?.realm || !config?.webClientId) {
    showSession(false);
    showStatus('Falta configurar el proveedor de identidad para la web.', 'error');
    return;
  }
  if (!apiBaseUrl.startsWith('https://')) {
    showSession(false);
    showStatus('Falta configurar la API HTTPS del perfil compartido.', 'error');
    return;
  }

  try {
    keycloak = new Keycloak({
      url: config.authUrl,
      realm: config.realm,
      clientId: config.webClientId,
    });
    const authenticated = await keycloak.init({
      onLoad: 'check-sso',
      pkceMethod: 'S256',
      responseMode: 'fragment',
      flow: 'standard',
      checkLoginIframe: false,
      redirectUri: window.location.href,
    });
    apiReady = true;
    showSession(authenticated);
    if (authenticated) await loadProfile();
    else showStatus('Inicia sesión o crea una cuenta para sincronizar tu perfil.', 'info');
  } catch {
    showSession(false);
    showStatus('No se pudo conectar con el proveedor de identidad. Comprueba la configuración OIDC.', 'error');
  } finally {
    if (apiReady) setBusy(false);
  }

  if (keycloak) {
    keycloak.onAuthLogout = () => {
      showSession(false);
      fillForm(null);
      showStatus('Has cerrado la sesión.', 'info');
    };
    keycloak.onTokenExpired = async () => {
      try {
        await keycloak.updateToken(30);
      } catch {
        showStatus('La sesión ha caducado. Inicia sesión de nuevo.', 'error');
        showSession(false);
      }
    };
  }
}

void initialise();
