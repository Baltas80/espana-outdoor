const header = document.querySelector('[data-header]');
const menu = document.querySelector('[data-menu]');
const nav = document.querySelector('#main-nav');
const year = document.querySelector('[data-year]');

const onScroll = () => {
  header?.classList.toggle('scrolled', window.scrollY > 24);
};
window.addEventListener('scroll', onScroll, { passive: true });
onScroll();

// Tienda integrada en la navegación global de España Outdoor.
if (nav && !nav.querySelector('a[href="./tienda.html"]')) {
  const storeLink = document.createElement('a');
  storeLink.href = './tienda.html';
  storeLink.textContent = 'Tienda';
  const appLink = Array.from(nav.querySelectorAll('a[href]')).find((link) => link.getAttribute('href') === './app.html');
  if (appLink) nav.insertBefore(storeLink, appLink);
  else nav.appendChild(storeLink);
}

// Cuenta compartida entre la web y la aplicación Android.
if (nav && !nav.querySelector('a[href="./cuenta.html"]')) {
  const accountLink = document.createElement('a');
  accountLink.href = './cuenta.html';
  accountLink.textContent = 'Mi cuenta';
  const downloadLink = nav.querySelector('.nav-download');
  if (downloadLink) nav.insertBefore(accountLink, downloadLink);
  else nav.appendChild(accountLink);
}

// Acceso directo al perfil personal.
if (nav && !nav.querySelector('a[href="./mi-perfil.html"]')) {
  const profileLink = document.createElement('a');
  profileLink.href = './mi-perfil.html';
  profileLink.textContent = 'Mi perfil';
  const accountLink = nav.querySelector('a[href="./cuenta.html"]');
  const downloadLink = nav.querySelector('.nav-download');
  if (accountLink) accountLink.after(profileLink);
  else if (downloadLink) nav.insertBefore(profileLink, downloadLink);
  else nav.appendChild(profileLink);
}

const footerLinks = document.querySelector('.footer-links');
if (footerLinks && !footerLinks.querySelector('a[href="./tienda.html"]')) {
  const storeFooterLink = document.createElement('a');
  storeFooterLink.href = './tienda.html';
  storeFooterLink.textContent = 'Tienda';
  footerLinks.appendChild(storeFooterLink);
}

const current = window.location.pathname.split('/').pop() || 'index.html';
nav?.querySelectorAll('a[href]').forEach((link) => {
  const href = link.getAttribute('href') || '';
  if (href.endsWith(current)) {
    link.setAttribute('aria-current', 'page');
  }
  link.addEventListener('click', () => {
    nav.classList.remove('open');
    menu?.setAttribute('aria-expanded', 'false');
  });
});

menu?.addEventListener('click', () => {
  const open = nav?.classList.toggle('open') ?? false;
  menu.setAttribute('aria-expanded', String(open));
});

if (footerLinks && !footerLinks.querySelector('a[href="./cuenta.html"]')) {
  const accountFooterLink = document.createElement('a');
  accountFooterLink.href = './cuenta.html';
  accountFooterLink.textContent = 'Mi cuenta';
  footerLinks.appendChild(accountFooterLink);
}

if (footerLinks && !footerLinks.querySelector('a[href="./mi-perfil.html"]')) {
  const profileFooterLink = document.createElement('a');
  profileFooterLink.href = './mi-perfil.html';
  profileFooterLink.textContent = 'Mi perfil';
  footerLinks.appendChild(profileFooterLink);
}

if (year) year.textContent = new Date().getFullYear();
