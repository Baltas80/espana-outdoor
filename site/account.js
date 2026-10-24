import { createAuthClient } from 'https://esm.sh/@neondatabase/auth@latest';

const config = window.ESPANA_OUTDOOR_PROFILE_CONFIG;
const auth = createAuthClient(config.authUrl);
const statusNode = document.querySelector('[data-account-status]');
const signedOutPanel = document.querySelector('[data-account-signed-out]');
const signedInPanel = document.querySelector('[data-account-signed-in]');
const form = document.querySelector('[data-account-form]');
const authForm = document.querySelector('[data-auth-form]');
const loginButton = document.querySelector('[data-account-login]');
const registerButton = document.querySelector('[data-account-register]');
const logoutButton = document.querySelector('[data-account-logout]');
const saveButton = document.querySelector('[data-account-save]');
const emailInput = document.querySelector('#account-email');
const passwordInput = document.querySelector('#account-password');
const nameInput = document.querySelector('#account-auth-name');
const nameLabel = document.querySelector('[data-auth-name-label]');
const displayName = document.querySelector('#account-display-name');
const username = document.querySelector('#account-username');
const homeArea = document.querySelector('#account-home-area');
const bio = document.querySelector('#account-bio');
const apiBaseUrl = String(config?.apiBaseUrl || '').replace(/\/$/, '');
let currentSession = null;
let authMode = 'login';

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
function setAuthMode(mode) {
  authMode = mode;
  const registering = mode === 'register';
  if (nameInput) {
    nameInput.hidden = !registering;
    nameInput.required = registering;
  }
  if (nameLabel) nameLabel.hidden = !registering;
  if (passwordInput) passwordInput.autocomplete = registering ? 'new-password' : 'current-password';
  if (loginButton) loginButton.textContent = registering ? 'Crear cuenta' : 'Iniciar sesión';
  if (registerButton) registerButton.textContent = registering ? 'Ya tengo cuenta' : 'Crear cuenta';
}
function getSessionData(result) {
  return result?.data?.session || result?.data || result?.session || result || null;
}
async function getAccessToken() {
  if (typeof auth.getJWTToken === 'function') return await auth.getJWTToken();
  return null;
}
async function apiRequest(method, body) {
  if (!currentSession) throw new Error('Inicia sesión para acceder a tu perfil.');
  if (!apiBaseUrl.startsWith('https://')) throw new Error('La API de perfiles no tiene una URL HTTPS válida.');
  const token = await getAccessToken();
  if (!token) throw new Error('Neon Auth ha iniciado sesión, pero falta un token para conectar la API de perfiles. El backend debe configurarse para validar Neon Auth.');
  const response = await fetch(apiBaseUrl + '/v1/me/profile', {
    method,
    headers: {
      Accept: 'application/json',
      Authorization: 'Bearer ' + token,
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
    cache: 'no-store',
    credentials: 'omit',
  });
  if (response.status === 404 && method === 'GET') return null;
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    if (response.status === 409) throw new Error('Ese alias ya está en uso. Elige otro.');
    if (response.status === 401) throw new Error('La API todavía no acepta el token de Neon Auth. Hay que adaptar su validación en el servidor.');
    if (response.status === 400 && payload.error) {
      const messages = {
        'displayName must contain between 2 and 50 characters': 'El nombre visible debe tener entre 2 y 50 caracteres.',
        'username must be 3-20 lowercase letters, numbers, dots, hyphens or underscores': 'El alias debe tener entre 3 y 20 caracteres válidos.',
        'homeArea must contain at most 80 characters': 'La zona habitual admite un máximo de 80 caracteres.',
        'bio must contain at most 160 characters': 'La presentación admite un máximo de 160 caracteres.',
      };
      throw new Error(messages[payload.error] || 'Revisa los datos del perfil e inténtalo de nuevo.');
    }
    throw new Error('El servicio de perfiles no está disponible. Inténtalo más tarde.');
  }
  return payload;
}
async function loadProfile() {
  try {
    const profile = await apiRequest('GET');
    fillForm(profile);
    showStatus(profile
      ? 'Sesión iniciada. El perfil del servidor se ha cargado.'
      : 'Sesión iniciada. Completa el perfil y guárdalo.', 'success');
  } catch (error) {
    fillForm(null);
    showStatus(error instanceof Error ? error.message : 'La sesión funciona, pero no se pudo cargar el perfil.', 'error');
  }
}
authForm?.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!authForm.reportValidity()) return;
  setBusy(true);
  try {
    let result;
    if (authMode === 'register') {
      result = await auth.signUp.email({
        name: nameInput.value.trim(),
        email: emailInput.value.trim(),
        password: passwordInput.value,
      });
    } else {
      result = await auth.signIn.email({
        email: emailInput.value.trim(),
        password: passwordInput.value,
      });
    }
    if (result?.error) throw new Error(result.error.message || 'Neon Auth ha rechazado la operación.');
    const sessionResult = await auth.getSession();
    currentSession = getSessionData(sessionResult);
    const user = currentSession?.user || sessionResult?.data?.user;
    if (!currentSession || !user) {
      showSession(false);
      showStatus(authMode === 'register'
        ? 'Solicitud de registro enviada. Revisa tu correo si Neon solicita verificar la dirección y vuelve a iniciar sesión después.'
        : 'Inicio de sesión enviado, pero Neon no ha devuelto una sesión activa. Comprueba la verificación del correo.', 'info');
      return;
    }
    showSession(true);
    await loadProfile();
  } catch (error) {
    showStatus(error instanceof Error ? error.message : 'No se pudo completar la autenticación con Neon.', 'error');
  } finally {
    setBusy(false);
  }
});
registerButton?.addEventListener('click', () => {
  setAuthMode(authMode === 'register' ? 'login' : 'register');
});
logoutButton?.addEventListener('click', async () => {
  setBusy(true);
  try {
    const result = await auth.signOut();
    if (result?.error) throw new Error(result.error.message || 'No se pudo cerrar la sesión.');
    currentSession = null;
    fillForm(null);
    showSession(false);
    showStatus('Has cerrado la sesión.', 'success');
  } catch (error) {
    showStatus(error instanceof Error ? error.message : 'No se pudo cerrar la sesión.', 'error');
  } finally {
    setBusy(false);
  }
});
form?.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!form.reportValidity()) return;
  const profile = readForm();
  if (profile.displayName.length < 2 || profile.displayName.length > 50) {
    showStatus('El nombre visible debe tener entre 2 y 50 caracteres.', 'error'); return;
  }
  if (!/^[a-z0-9][a-z0-9._-]{2,19}$/.test(profile.username)) {
    showStatus('El alias debe tener entre 3 y 20 caracteres válidos.', 'error'); return;
  }
  if (profile.homeArea.length > 80 || profile.bio.length > 160) {
    showStatus('La zona o la presentación supera la longitud permitida.', 'error'); return;
  }
  setBusy(true);
  try {
    const saved = await apiRequest('PUT', profile);
    fillForm(saved);
    showStatus('Perfil guardado en el servidor.', 'success');
  } catch (error) {
    showStatus(error instanceof Error ? error.message : 'No se pudo guardar el perfil.', 'error');
  } finally {
    setBusy(false);
  }
});
async function initialise() {
  setAuthMode('login');
  try {
    const result = await auth.getSession();
    currentSession = getSessionData(result);
    const user = currentSession?.user || result?.data?.user;
    if (user) {
      showSession(true);
      await loadProfile();
    } else {
      currentSession = null;
      showSession(false);
      showStatus('Inicia sesión o crea una cuenta con Neon Auth.', 'info');
    }
  } catch {
    showSession(false);
    showStatus('No se pudo conectar con Neon Auth. Comprueba la URL y los dominios de confianza.', 'error');
  } finally {
    setBusy(false);
  }
}
void initialise();
