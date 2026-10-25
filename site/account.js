import { createAuthClient } from 'https://esm.sh/@neondatabase/auth@0.7.0-beta';

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
const dataApiUrl = String(config?.dataApiUrl || '').trim().replace(/\/$/, '');
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
  // Con el cliente Better Auth predeterminado de Neon, el JWT de Data API
  // se obtiene con auth.token(); session.token es solo el identificador
  // opaco de la cookie y no debe enviarse como Bearer.
  const result = await auth.token();
  if (result?.error) {
    throw new Error(result.error.message || 'Neon Auth no ha podido emitir el token de acceso al perfil.');
  }
  const token = typeof result?.data?.token === 'string'
    ? result.data.token.trim()
    : typeof result?.token === 'string'
      ? result.token.trim()
      : '';
  const parts = token.split('.');
  if (parts.length !== 3 || parts.some(part => !part)) {
    throw new Error('Neon Auth no ha devuelto un JWT válido para acceder al perfil. Vuelve a iniciar sesión.');
  }
  return token;
}
function mapApiProfile(row) {
  if (!row) return null;
  return {
    displayName: row.display_name || '',
    username: row.username || '',
    homeArea: row.home_area || '',
    bio: row.bio || '',
    createdAt: row.created_at || '',
    updatedAt: row.updated_at || '',
  };
}
async function apiRequest(method, body) {
  if (!currentSession) throw new Error('Inicia sesión para acceder a tu perfil.');
  if (!dataApiUrl.startsWith('https://')) {
    throw new Error('Falta configurar la URL de Neon Data API. Hay que habilitar Data API en la rama de producción y añadir su URL a profile-config.js.');
  }
  const token = await getAccessToken();
  if (!token) throw new Error('La sesión de Neon Auth está activa, pero no se ha podido obtener el token para la base de datos.');
  const isRead = method === 'GET';
  const url = isRead
    ? dataApiUrl + '/user_profiles?select=display_name,username,home_area,bio,created_at,updated_at&limit=1'
    : dataApiUrl + '/user_profiles?on_conflict=user_id';
  const response = await fetch(url, {
    method: isRead ? 'GET' : 'POST',
    headers: {
      Accept: 'application/json',
      'Accept-Profile': 'public',
      Authorization: 'Bearer ' + token,
      ...(isRead ? {} : {
        'Content-Type': 'application/json',
        'Content-Profile': 'public',
        Prefer: 'resolution=merge-duplicates,return=representation',
      }),
    },
    ...(!isRead ? {
      body: JSON.stringify({
        display_name: body.displayName,
        username: body.username,
        home_area: body.homeArea,
        bio: body.bio,
      }),
    } : {}),
    cache: 'no-store',
    credentials: 'omit',
  });
  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    const serverMessage = typeof payload?.message === 'string' ? payload.message : '';
    const serverError = typeof payload?.error === 'string' ? payload.error : '';
    const code = typeof payload?.code === 'string' ? payload.code : '';
    if (response.status === 409 || code === '23505') throw new Error('Ese alias ya está en uso. Elige otro.');
    if (response.status === 400 && (code === '23514' || /check constraint|display_name|username/i.test(serverMessage + ' ' + serverError))) {
      throw new Error('Revisa el nombre visible y el alias; alguno no cumple las reglas del perfil.');
    }
    if (response.status === 401 || response.status === 403) {
      throw new Error('Neon ha rechazado el acceso a los datos. Comprueba que Data API use Neon Auth y que estén instaladas las políticas RLS del perfil.');
    }
    if (response.status === 404) {
      throw new Error('Neon Data API devuelve 404. Comprueba que la URL copiada sea la de Data API y que exista la tabla public.user_profiles.');
    }
    throw new Error('Neon Data API no ha podido ' + (isRead ? 'leer' : 'guardar') + ' el perfil. ' + (serverMessage || serverError || ('HTTP ' + response.status)));
  }
  if (isRead) {
    if (!Array.isArray(payload)) throw new Error('Neon Data API devolvió una respuesta inesperada al cargar el perfil.');
    return mapApiProfile(payload[0] || null);
  }
  if (!Array.isArray(payload) || !payload[0]) {
    throw new Error('Neon Data API no devolvió el perfil guardado. Comprueba los permisos RLS de INSERT y UPDATE.');
  }
  return mapApiProfile(payload[0]);
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
    const message = error instanceof Error ? error.message : 'No se pudo cerrar la sesión.';
    if (/invalid origin|invalid domain/i.test(message)) {
      showStatus('Neon Auth rechaza el dominio de esta web (' + window.location.origin + '). Añade ese origen, sin barra final, a los dominios de confianza de la rama de Neon Auth configurada en profile-config.js.', 'error');
    } else {
      showStatus(message, 'error');
    }
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
