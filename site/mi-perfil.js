import { createAuthClient } from 'https://esm.sh/@neondatabase/auth@0.7.0-beta';

const config = window.ESPANA_OUTDOOR_PROFILE_CONFIG;
const auth = createAuthClient(config.authUrl);
const dataApiUrl = String(config?.dataApiUrl || '').trim().replace(/\/$/, '');
const statusNode = document.querySelector('[data-profile-status]');
const signedOutPanel = document.querySelector('[data-profile-signed-out]');
const incompletePanel = document.querySelector('[data-profile-incomplete]');
const contentPanel = document.querySelector('[data-profile-content]');
const logoutButton = document.querySelector('[data-profile-logout]');
const photoInput = document.querySelector('[data-profile-photo-input]');
const photoSaveButton = document.querySelector('[data-profile-photo-save]');
const photoRemoveButton = document.querySelector('[data-profile-photo-remove]');
const photoImage = document.querySelector('[data-profile-avatar-image]');
const photoInitials = document.querySelector('[data-profile-avatar-initials]');
let currentSession = null;
let currentProfile = null;
let pendingAvatarData = null;

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
function showProfilePhoto(value) {
  const valid = typeof value === 'string' &&
    value.startsWith('data:image/jpeg;base64,') &&
    value.length <= 360000;
  if (photoImage) {
    photoImage.hidden = !valid;
    if (valid && photoImage.src !== value) photoImage.src = value;
    if (!valid) photoImage.removeAttribute('src');
  }
  if (photoInitials) photoInitials.hidden = valid;
}
async function optimizeProfileImage(file) {
  if (!file || !['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
    throw new Error('Selecciona una imagen JPEG, PNG o WebP.');
  }
  if (file.size > 8 * 1024 * 1024) {
    throw new Error('La imagen original no puede superar los 8 MB.');
  }
  if (typeof createImageBitmap !== 'function') {
    throw new Error('Este navegador no permite procesar la foto. Actualiza el navegador e inténtalo de nuevo.');
  }
  const bitmap = await createImageBitmap(file);
  try {
    const side = Math.min(bitmap.width, bitmap.height);
    const canvas = document.createElement('canvas');
    canvas.width = 384;
    canvas.height = 384;
    const context = canvas.getContext('2d');
    if (!context) throw new Error('No se pudo preparar la imagen seleccionada.');
    context.drawImage(bitmap, (bitmap.width - side) / 2, (bitmap.height - side) / 2, side, side, 0, 0, 384, 384);
    let data = '';
    for (const quality of [0.84, 0.76, 0.68, 0.60, 0.52]) {
      data = canvas.toDataURL('image/jpeg', quality);
      if (data.length <= 360000) break;
    }
    if (!data.startsWith('data:image/jpeg;base64,') || data.length > 360000) {
      throw new Error('La foto ocupa demasiado incluso después de optimizarla. Elige otra imagen.');
    }
    return data;
  } finally {
    bitmap.close?.();
  }
}
async function saveProfilePhoto() {
  if (!currentSession || !currentProfile || pendingAvatarData === null) return;
  photoSaveButton.disabled = true;
  photoRemoveButton.disabled = true;
  try {
    const token = await getAccessToken(currentSession);
    const response = await fetch(dataApiUrl + '/user_profiles?on_conflict=user_id', {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Accept-Profile': 'public',
        'Content-Profile': 'public',
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + token,
        Prefer: 'resolution=merge-duplicates,return=representation',
      },
      body: JSON.stringify({
        display_name: currentProfile.display_name,
        username: currentProfile.username,
        home_area: currentProfile.home_area || '',
        bio: currentProfile.bio || '',
        avatar_data: pendingAvatarData,
      }),
      cache: 'no-store',
      credentials: 'omit',
    });
    const payload = await response.json().catch(() => null);
    if (!response.ok) {
      const detail = typeof payload?.message === 'string' ? payload.message : '';
      throw new Error('Neon no ha podido guardar la foto (HTTP ' + response.status + '). ' + detail);
    }
    currentProfile = { ...currentProfile, avatar_data: pendingAvatarData };
    pendingAvatarData = null;
    showProfilePhoto(currentProfile.avatar_data);
    photoSaveButton.hidden = true;
    photoSaveButton.textContent = 'Guardar foto';
    photoRemoveButton.hidden = !currentProfile.avatar_data;
    showStatus(currentProfile.avatar_data ? 'Foto de perfil guardada.' : 'Foto de perfil eliminada.', 'success');
  } catch (error) {
    showStatus(error instanceof Error ? error.message : 'No se pudo guardar la foto.', 'error');
  } finally {
    photoSaveButton.disabled = false;
    photoRemoveButton.disabled = false;
  }
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
  setText('[data-profile-avatar-initials]', initials || 'EO');
  showProfilePhoto(profile.avatar_data || '');
  currentProfile = profile;
  pendingAvatarData = null;
  if (photoSaveButton) {
    photoSaveButton.hidden = true;
    photoSaveButton.textContent = 'Guardar foto';
  }
  if (photoRemoveButton) photoRemoveButton.hidden = !profile.avatar_data;
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
    currentSession = session;
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
    const url = dataApiUrl + '/user_profiles?select=display_name,username,home_area,bio,avatar_data,created_at,updated_at&limit=1';
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
photoInput?.addEventListener('change', async () => {
  const file = photoInput.files?.[0];
  if (!file) return;
  try {
    showStatus('Preparando la foto…', 'info');
    pendingAvatarData = await optimizeProfileImage(file);
    showProfilePhoto(pendingAvatarData);
    photoSaveButton.hidden = false;
    photoSaveButton.textContent = 'Guardar foto';
    photoRemoveButton.hidden = false;
    showStatus('Vista previa lista. Guarda la foto para conservarla en tu perfil.', 'info');
  } catch (error) {
    pendingAvatarData = null;
    showProfilePhoto(currentProfile?.avatar_data || '');
    photoSaveButton.hidden = true;
    photoRemoveButton.hidden = !currentProfile?.avatar_data;
    showStatus(error instanceof Error ? error.message : 'No se pudo preparar la foto.', 'error');
  } finally {
    photoInput.value = '';
  }
});
photoSaveButton?.addEventListener('click', () => void saveProfilePhoto());
photoRemoveButton?.addEventListener('click', () => {
  if (!currentProfile?.avatar_data) {
    pendingAvatarData = null;
    showProfilePhoto('');
    photoSaveButton.hidden = true;
    photoRemoveButton.hidden = true;
    showStatus('Se ha cancelado la foto seleccionada.', 'info');
    return;
  }
  pendingAvatarData = '';
  showProfilePhoto('');
  photoSaveButton.hidden = false;
  photoSaveButton.textContent = 'Eliminar foto';
  showStatus('Pulsa «Eliminar foto» para confirmar.', 'info');
});
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
