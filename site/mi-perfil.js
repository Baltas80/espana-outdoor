import { createAuthClient } from 'https://esm.sh/@neondatabase/auth@0.7.0-beta';

const config = window.ESPANA_OUTDOOR_PROFILE_CONFIG;
const auth = createAuthClient(config.authUrl);
const dataApiUrl = String(config?.dataApiUrl || '').trim().replace(/\/$/, '');
const statusNode = document.querySelector('[data-profile-status]');
const signedOutPanel = document.querySelector('[data-profile-signed-out]');
const incompletePanel = document.querySelector('[data-profile-incomplete]');
const contentPanel = document.querySelector('[data-profile-content]');
const logoutButton = document.querySelector('[data-profile-logout]');

function showStatus(message, kind = 'info') {
  if (!statusNode) return;
  statusNode.textContent = message;
  statusNode.dataset.kind = kind;
}
function getSessionData(result) {
  return result?.data?.session || result?.data || result?.session || result || null;
}
function isJwt(value) {
  if (typeof value !== 'string') return false;
  const parts = value.trim().split('.');
  return parts.length === 3 && parts.every(part => part.length > 0);
}
async function getAccessToken(session) {
  const possibleTokens = [
    session?.access_token,
    session?.data?.access_token,
    session?.session?.access_token,
  ];
  const existing = possibleTokens.find(isJwt);
  if (existing) return existing.trim();

  const authBaseUrl = String(config?.authUrl || '').trim().replace(/\/+$/, '');
  if (!authBaseUrl.startsWith('https://')) {
    throw new Error('La URL de Neon Auth no está configurada correctamente.');
  }
  const response = await fetch(authBaseUrl + '/token', {
    method: 'GET',
    headers: { Accept: 'application/json' },
    credentials: 'include',
    cache: 'no-store',
  });
  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    const detail = typeof payload?.message === 'string' ? payload.message : '';
    throw new Error('Neon Auth no ha podido autorizar la lectura del perfil (HTTP ' + response.status + '). ' + detail);
  }
  const candidates = [
    payload?.token,
    payload?.data?.token,
    payload?.data?.access_token,
    payload?.access_token,
    payload?.session?.access_token,
    typeof payload?.data === 'string' ? payload.data : '',
  ];
  const token = candidates.find(isJwt);
  if (!token) throw new Error('Neon Auth no ha devuelto un JWT válido para mostrar el perfil.');
  return token.trim();
}
function showPanel(panel, visible) {
  if (panel) panel.hidden = !visible;
}
function formatDate(value) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return new Intl.DateTimeFormat('es-ES', { year: 'numeric', month: 'long' }).format(date);
}
function setText(selector, value) {
  const node = document.querySelector(selector);
  if (node) node.textContent = value || '';
}
function renderProfile(profile) {
  setText('[data-profile-name]', profile.display_name);
  setText('[data-profile-handle]', '@' + profile.username);
  setText('[data-profile-area]', profile.home_area);
  setText('[data-profile-bio]', profile.bio);
  setText('[data-profile-created]', formatDate(profile.created_at));
  const initials = String(profile.display_name || 'EO').trim().split(/\s+/).slice(0, 2).map(part => part.charAt(0)).join('').toLocaleUpperCase('es-ES');
  setText('[data-profile-avatar]', initials || 'EO');
  showPanel(document.querySelector('[data-profile-area-wrap]'), Boolean(profile.home_area));
  showPanel(document.querySelector('[data-profile-bio-wrap]'), Boolean(profile.bio));
  showPanel(contentPanel, true);
  showPanel(signedOutPanel, false);
  showPanel(incompletePanel, false);
  const saved = new URLSearchParams(window.location.search).get('guardado') === '1';
  showStatus(saved ? 'Perfil guardado correctamente.' : 'Este es tu perfil personal.', 'success');
}
async function load() {
  try {
    const result = await auth.getSession();
    const session = getSessionData(result);
    const user = session?.user || result?.data?.user;
    if (!session || !user) {
      showPanel(signedOutPanel, true);
      showPanel(incompletePanel, false);
      showPanel(contentPanel, false);
      showStatus('Inicia sesión para consultar tu perfil.', 'info');
      return;
    }
    if (!dataApiUrl.startsWith('https://')) throw new Error('No está configurada la URL de Neon Data API.');
    const token = await getAccessToken(session);
    const url = dataApiUrl + '/user_profiles?select=display_name,username,home_area,bio,created_at,updated_at&limit=1';
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
        'Accept-Profile': 'public',
        Authorization: 'Bearer ' + token,
      },
      cache: 'no-store',
      credentials: 'omit',
    });
    const payload = await response.json().catch(() => null);
    if (!response.ok) {
      throw new Error(response.status === 401 || response.status === 403
        ? 'Neon ha rechazado el acceso al perfil. Cierra sesión e inicia sesión de nuevo.'
        : 'No se ha podido cargar el perfil (HTTP ' + response.status + ').');
    }
    if (!Array.isArray(payload)) throw new Error('Neon devolvió una respuesta inesperada al cargar el perfil.');
    const profile = payload[0];
    if (!profile) {
      showPanel(signedOutPanel, false);
      showPanel(contentPanel, false);
      showPanel(incompletePanel, true);
      showStatus('Tu cuenta está activa, pero todavía no hay un perfil guardado.', 'info');
      return;
    }
    renderProfile(profile);
  } catch (error) {
    showPanel(signedOutPanel, false);
    showPanel(incompletePanel, false);
    showPanel(contentPanel, false);
    showStatus(error instanceof Error ? error.message : 'No se pudo cargar tu perfil.', 'error');
  }
}
logoutButton?.addEventListener('click', async () => {
  logoutButton.disabled = true;
  try {
    const result = await auth.signOut();
    if (result?.error) throw new Error(result.error.message || 'No se pudo cerrar la sesión.');
    window.location.href = './cuenta.html';
  } catch (error) {
    showStatus(error instanceof Error ? error.message : 'No se pudo cerrar la sesión.', 'error');
    logoutButton.disabled = false;
  }
});
void load();
