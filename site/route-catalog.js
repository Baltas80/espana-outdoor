(() => {
  const results = document.querySelector('[data-route-results]');
  const place = document.querySelector('[data-route-place]');
  const source = document.querySelector('[data-route-source]');
  const type = document.querySelector('[data-route-type]');
  const loop = document.querySelector('[data-route-loop]');
  const count = document.querySelector('[data-route-count]');
  const countLabel = document.querySelector('[data-route-count-label]');
  const searchButton = document.querySelector('[data-route-search]');
  if (!results) return;

  let routes = [];
  const searchParams = new URLSearchParams(window.location.search);
  const initialPlace = searchParams.get('localidad') || searchParams.get('q') || '';
  if (place && initialPlace) place.value = initialPlace;
  const normalize = (value) => String(value || '').toLocaleLowerCase('es-ES').normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  const escapeHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'
  }[char]));
  const typeLabel = (route) => ({
    GR:'GR — Gran Recorrido',
    PR:'PR — Pequeño Recorrido',
    SL:'SL — Sendero Local',
    CN:'Camino Natural',
    PN:'Parque Nacional'
  }[route.type] || route.type_label || 'Ruta oficial');

  const metric = (value, suffix = '') => {
    if (value === null || value === undefined || value === '') return '<strong>—</strong><span>dato oficial</span>';
    return \`<strong>\${escapeHtml(value)}\${suffix}</strong>\`;
  };

  const render = () => {
    const q = normalize(place?.value);
    const sourceValue = source?.value || 'all';
    const typeValue = type?.value || 'all';
    const loopValue = loop?.value || 'all';

    const filtered = routes.filter((route) => {
      const haystack = normalize([
        route.name, route.code, route.locality, route.province,
        route.community, route.source_name, route.type_label
      ].join(' '));
      const placeOk = !q || haystack.includes(q);
      const sourceOk = sourceValue === 'all' || route.source_id === sourceValue;
      const typeOk = typeValue === 'all' || route.type === typeValue;
      const loopOk = loopValue === 'all' || route.loop === loopValue;
      return placeOk && sourceOk && typeOk && loopOk;
    });

    if (count) count.textContent = String(filtered.length);
    if (countLabel) countLabel.textContent = filtered.length === 1 ? 'ruta disponible' : 'rutas disponibles';

    results.innerHTML = filtered.length ? filtered.slice(0, 180).map((route) => {
      const loopText = route.loop === 'circular' ? 'Circular' : route.loop === 'lineal' ? 'Lineal' : 'Tipo de recorrido en ficha';
      const sourceText = route.source_name || 'Fuente oficial';
      return \`
      <article class="route-result-card">
        <div class="route-result-top">
          <span class="route-code">\${escapeHtml(route.code || 'Ruta oficial')}</span>
          <span class="route-kind">\${escapeHtml(typeLabel(route))}</span>
        </div>
        <h3>\${escapeHtml(route.name || route.code || 'Ruta sin nombre')}</h3>
        <p class="route-location">\${escapeHtml([route.locality, route.province, route.community].filter(Boolean).join(' · ') || 'Ubicación en ficha oficial')}</p>
        <div class="route-metrics">
          <div>\${metric(route.distance_km, ' km')}<span>distancia</span></div>
          <div>\${metric(route.ascent_m, ' m')}<span>desnivel +</span></div>
          <div>\${metric(route.duration)}<span>duración</span></div>
        </div>
        <div class="route-result-meta"><span>\${escapeHtml(loopText)}</span><span>\${escapeHtml(sourceText)}</span></div>
        <div class="route-result-footer">
          <a href="./ruta.html?id=\${encodeURIComponent(route.id)}">Abrir ficha →</a>
          <a href="\${escapeHtml(route.catalog_url || route.source_url || '#')}" target="_blank" rel="noopener noreferrer">Fuente oficial ↗</a>
          \${route.download_url ? \`<a href="\${escapeHtml(route.download_url)}" target="_blank" rel="noopener noreferrer">KML ↗</a>\` : ''}
        </div>
      </article>\`;
    }).join('') : '<div class="route-empty"><strong>No hay coincidencias.</strong><span>Prueba otra localidad o cambia los filtros.</span></div>';

    if (filtered.length > 180) {
      results.insertAdjacentHTML('beforeend',
        '<div class="route-data-note"><strong>Vista limitada a 180 resultados.</strong> Afina la búsqueda por localidad o fuente para trabajar con una selección más manejable.</div>');
    }
  };

  fetch('./data/routes-catalog.json', { cache: 'no-store' })
    .then((response) => response.ok ? response.json() : Promise.reject(new Error('route catalog unavailable')))
    .then((payload) => {
      routes = Array.isArray(payload.routes) ? payload.routes : [];
      render();
    })
    .catch(() => {
      if (count) count.textContent = '—';
      if (countLabel) countLabel.textContent = 'catálogo no disponible';
      results.innerHTML = '<div class="route-empty"><strong>No se ha podido cargar el catálogo.</strong><span>El catálogo oficial CNIG / FEDME sigue disponible como fuente externa. Comprueba la conexión o accede a las fuentes oficiales.</span></div>';
    });

  searchButton?.addEventListener('click', render);
  [place, source, type, loop].forEach((field) => {
    field?.addEventListener('input', render);
    field?.addEventListener('change', render);
  });
  place?.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') render();
  });
})();