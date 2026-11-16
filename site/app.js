const header = document.querySelector('[data-header]');
const menu = document.querySelector('[data-menu]');
const nav = document.querySelector('#main-nav');
const menuLabel = menu?.querySelector('.sr-only');
const year = document.querySelector('[data-year]');

const onScroll = () => {
  header?.classList.toggle('scrolled', window.scrollY > 24);
};
window.addEventListener('scroll', onScroll, { passive: true });
onScroll();

// Cuenta compartida entre la web y Android.
if (nav && !nav.querySelector('a[href="./cuenta.html"]')) {
  const accountLink = document.createElement('a');
  accountLink.href = './cuenta.html';
  accountLink.textContent = 'Mi cuenta';
  const appLink = Array.from(nav.querySelectorAll('a[href]')).find((link) => link.getAttribute('href') === './app.html');
  if (appLink) nav.insertBefore(accountLink, appLink);
  else nav.appendChild(accountLink);
}

// Tienda integrada en la navegación global de España Outdoor.
if (nav && !nav.querySelector('a[href="./tienda.html"]')) {
  const storeLink = document.createElement('a');
  storeLink.href = './tienda.html';
  storeLink.textContent = 'Tienda';
  const appLink = Array.from(nav.querySelectorAll('a[href]')).find((link) => link.getAttribute('href') === './app.html');
  if (appLink) nav.insertBefore(storeLink, appLink);
  else nav.appendChild(storeLink);
}

const footerLinks = document.querySelector('.footer-links');
if (footerLinks && !footerLinks.querySelector('a[href="./cuenta.html"]')) {
  const accountFooterLink = document.createElement('a');
  accountFooterLink.href = './cuenta.html';
  accountFooterLink.textContent = 'Mi cuenta';
  footerLinks.appendChild(accountFooterLink);
}

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
    if (menuLabel) menuLabel.textContent = 'Abrir menú';
  });
});

menu?.addEventListener('click', () => {
  const open = nav?.classList.toggle('open') ?? false;
  menu.setAttribute('aria-expanded', String(open));
  if (menuLabel) menuLabel.textContent = open ? 'Cerrar menú' : 'Abrir menú';
  if (open) nav?.querySelector('a[href]')?.focus();
});

document.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape' || !nav?.classList.contains('open')) return;
  nav.classList.remove('open');
  menu?.setAttribute('aria-expanded', 'false');
  if (menuLabel) menuLabel.textContent = 'Abrir menú';
  menu?.focus();
});

if (year) year.textContent = new Date().getFullYear();
