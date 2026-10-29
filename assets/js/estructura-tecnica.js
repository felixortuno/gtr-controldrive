/* Ventana flotante «Estructura técnica».
   Se añade a cualquier página con:
     <script src="assets/js/estructura-tecnica.js" defer></script>
   Pone un botón abajo a la derecha que abre estructura-tecnica.html en una ventana que se
   mueve por su barra, se amplía con doble clic y cambia de tamaño por la esquina.
   Cualquier elemento con data-estructura="bd" (o "fases", "arquitectura"…) la abre en esa sección. */
(function () {
  if (window.__estructuraTecnica) return;
  window.__estructuraTecnica = true;

  var script = document.currentScript;
  var PAGINA = new URL('../../estructura-tecnica.html', script ? script.src : location.href).href;
  var CLAVE = 'gtr-estructura-tecnica';
  var MOVIL = window.matchMedia('(max-width: 760px)');
  var MIN_W = 520, MIN_H = 380, MARGEN = 12;

  var css = '' +
    '.et-launch{position:fixed;right:max(20px,env(safe-area-inset-right));bottom:max(20px,env(safe-area-inset-bottom));z-index:1190;display:inline-flex;align-items:center;gap:10px;height:46px;padding:0 16px 0 7px;border:0;border-radius:999px;background:#121212;color:#fff;font:800 13.5px/1 Mulish,system-ui,sans-serif;letter-spacing:.01em;cursor:pointer;box-shadow:0 0 0 1px rgba(255,255,255,.08),0 14px 34px -12px rgba(0,0,0,.6);transition:transform .25s cubic-bezier(.22,.8,.24,1),box-shadow .25s}' +
    '.et-launch:hover{transform:translateY(-2px);box-shadow:0 0 0 1px rgba(253,218,0,.5),0 18px 40px -12px rgba(0,0,0,.65)}' +
    '.et-launch:focus-visible{outline:2px solid #FDDA00;outline-offset:3px}' +
    '.et-launch i{width:32px;height:32px;border-radius:50%;background:#FDDA00;display:grid;place-items:center;color:#121212}' +
    '.et-launch svg{width:17px;height:17px}' +
    '.et-launch[aria-expanded="true"]{display:none}' +
    '.et-launch.et-min::after{content:"";width:6px;height:6px;border-radius:50%;background:#FDDA00;margin-left:2px}' +
    '.et-win{position:fixed;z-index:1200;display:flex;flex-direction:column;background:#F6F6F6;border-radius:14px;overflow:hidden;box-shadow:0 0 0 1px rgba(253,218,0,.7),0 0 0 6px rgba(253,218,0,.09),0 40px 90px -24px rgba(0,0,0,.6);animation:et-in .28s cubic-bezier(.22,.8,.24,1)}' +
    '.et-win[hidden]{display:none}' +
    '.et-win:focus{outline:none}' +
    '.et-win.et-max{left:16px!important;top:16px!important;width:calc(100vw - 32px)!important;height:calc(100vh - 32px)!important}' +
    '.et-bar{height:42px;flex:none;display:flex;align-items:center;gap:12px;padding:0 8px 0 14px;background:linear-gradient(180deg,#25282d,#1c1e22);color:#c7ccd2;cursor:grab;user-select:none;-webkit-user-select:none;touch-action:none}' +
    '.et-win.et-drag .et-bar{cursor:grabbing}' +
    '.et-win.et-max .et-bar{cursor:default}' +
    '.et-dots{display:flex;gap:7px;flex:none}' +
    '.et-dots i{width:10px;height:10px;border-radius:50%}' +
    '.et-dots i:nth-child(1){background:#FDDA00}.et-dots i:nth-child(2){background:#209C8F}.et-dots i:nth-child(3){background:#EE7D4A}' +
    '.et-ttl{flex:1;min-width:0;display:flex;align-items:center;gap:8px;font:700 13px Mulish,system-ui,sans-serif;color:#eef0f2;white-space:nowrap;overflow:hidden}' +
    '.et-ttl svg{width:15px;height:15px;flex:none;color:#FDDA00}' +
    '.et-ttl small{font:600 12px Mulish,system-ui,sans-serif;color:#878c93;overflow:hidden;text-overflow:ellipsis}' +
    '.et-ctl{display:flex;gap:2px;flex:none}' +
    '.et-ctl a,.et-ctl button{width:32px;height:30px;border:0;border-radius:7px;background:transparent;color:#a3a9b0;display:grid;place-items:center;cursor:pointer;padding:0}' +
    '.et-ctl a:hover,.et-ctl button:hover{background:rgba(255,255,255,.1);color:#fff}' +
    '.et-ctl a:focus-visible,.et-ctl button:focus-visible{outline:2px solid #FDDA00;outline-offset:-2px}' +
    '.et-ctl svg{width:14px;height:14px}' +
    '.et-body{position:relative;flex:1;min-height:0;background:#F6F6F6}' +
    '.et-body iframe{display:block;width:100%;height:100%;border:0;background:#F6F6F6}' +
    '.et-win.et-drag iframe,.et-win.et-resizing iframe{pointer-events:none}' +
    '.et-cargando{position:absolute;inset:0;display:grid;place-items:center;font:600 14px Mulish,system-ui,sans-serif;color:#5D646C;background:#F6F6F6;transition:opacity .3s}' +
    '.et-win.et-listo .et-cargando{opacity:0;pointer-events:none}' +
    '.et-resize{position:absolute;right:0;bottom:0;width:18px;height:18px;cursor:nwse-resize;touch-action:none;background:linear-gradient(135deg,transparent 50%,rgba(18,18,18,.28) 50%,rgba(18,18,18,.28) 58%,transparent 58%,transparent 70%,rgba(18,18,18,.28) 70%,rgba(18,18,18,.28) 78%,transparent 78%)}' +
    '.et-win.et-max .et-resize{display:none}' +
    '.et-cta{margin-top:28px;display:flex;flex-wrap:wrap;gap:10px}' +
    '.et-cta button{cursor:pointer}' +
    '@keyframes et-in{from{opacity:0;transform:translateY(14px) scale(.985)}}' +
    '@media (max-width:760px){' +
      '.et-launch{height:42px;font-size:13px}' +
      '.et-win,.et-win.et-max{left:0!important;top:0!important;width:100%!important;height:100%!important;border-radius:0;box-shadow:none}' +
      '.et-bar{cursor:default;padding-top:env(safe-area-inset-top);height:calc(46px + env(safe-area-inset-top))}' +
      '.et-ttl small,.et-resize,.et-ctl [data-et="max"]{display:none}' +
    '}' +
    '@media (prefers-reduced-motion:reduce){.et-launch,.et-win{transition:none;animation:none}}' +
    '@media print{.et-launch,.et-win{display:none!important}}';

  var ICONO = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 7l9-4 9 4-9 4-9-4z"/><path d="M3 12l9 4 9-4"/><path d="M3 17l9 4 9-4"/></svg>';

  var estilo = document.createElement('style');
  estilo.textContent = css;
  document.head.appendChild(estilo);

  var boton = document.createElement('button');
  boton.type = 'button';
  boton.className = 'et-launch';
  boton.setAttribute('aria-expanded', 'false');
  boton.setAttribute('aria-controls', 'etWin');
  boton.innerHTML = '<i>' + ICONO + '</i>Estructura técnica';

  var ventana = document.createElement('section');
  ventana.className = 'et-win';
  ventana.id = 'etWin';
  ventana.hidden = true;
  ventana.tabIndex = -1;
  ventana.setAttribute('role', 'dialog');
  ventana.setAttribute('aria-label', 'Estructura técnica');
  ventana.innerHTML =
    '<div class="et-bar">' +
      '<span class="et-dots" aria-hidden="true"><i></i><i></i><i></i></span>' +
      '<span class="et-ttl">' + ICONO + '<b>Estructura técnica</b><small>Bases para construir la app</small></span>' +
      '<span class="et-ctl">' +
        '<a data-et="tab" href="' + PAGINA + '" target="_blank" rel="noopener" aria-label="Abrir en una pestaña nueva" title="Abrir en una pestaña nueva"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M9.5 2.5h4v4M13.5 2.5L7.5 8.5M12 9.5v3a1 1 0 0 1-1 1H3.5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1h3"/></svg></a>' +
        '<button type="button" data-et="min" aria-label="Minimizar" title="Minimizar"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M3.5 8h9"/></svg></button>' +
        '<button type="button" data-et="max" aria-label="Ampliar o restaurar" title="Ampliar o restaurar"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="3" y="3" width="10" height="10" rx="1.6"/></svg></button>' +
        '<button type="button" data-et="close" aria-label="Cerrar" title="Cerrar"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 4l8 8M12 4l-8 8"/></svg></button>' +
      '</span>' +
    '</div>' +
    '<div class="et-body"><iframe title="Estructura técnica de la app de conductores"></iframe><div class="et-cargando">Cargando la estructura técnica…</div></div>' +
    '<span class="et-resize" aria-hidden="true"></span>';

  document.body.appendChild(boton);
  document.body.appendChild(ventana);

  var marco = ventana.querySelector('iframe');
  var enlace = ventana.querySelector('[data-et="tab"]');
  var barra = ventana.querySelector('.et-bar');
  var esquina = ventana.querySelector('.et-resize');
  var cargado = false;
  var geo = leer();

  function leer() {
    try { return JSON.parse(localStorage.getItem(CLAVE)) || {}; } catch (e) { return {}; }
  }
  function guardar() {
    try { localStorage.setItem(CLAVE, JSON.stringify(geo)); } catch (e) {}
  }
  function porDefecto() {
    var vw = window.innerWidth, vh = window.innerHeight;
    var w = Math.min(1180, vw - 48), h = Math.min(800, vh - 104);
    return { x: vw - w - 24, y: Math.max(24, vh - h - 80), w: w, h: h, max: false };
  }
  function encajar() {
    var vw = window.innerWidth, vh = window.innerHeight;
    if (!(geo.w > 0)) geo = porDefecto();
    geo.w = Math.max(Math.min(geo.w, vw - MARGEN * 2), Math.min(MIN_W, vw - MARGEN * 2));
    geo.h = Math.max(Math.min(geo.h, vh - MARGEN * 2), Math.min(MIN_H, vh - MARGEN * 2));
    geo.x = Math.min(Math.max(geo.x, MARGEN), vw - geo.w - MARGEN);
    geo.y = Math.min(Math.max(geo.y, MARGEN), vh - geo.h - MARGEN);
  }
  function pintar() {
    encajar();
    ventana.style.left = geo.x + 'px';
    ventana.style.top = geo.y + 'px';
    ventana.style.width = geo.w + 'px';
    ventana.style.height = geo.h + 'px';
    ventana.classList.toggle('et-max', !!geo.max);
  }

  function abrir(seccion) {
    seccion = seccion || '';
    enlace.href = PAGINA + (seccion ? '#' + seccion : '');
    if (!cargado) {
      cargado = true;
      marco.src = PAGINA + (seccion ? '#' + seccion : '');
    } else if (seccion && marco.contentWindow) {
      marco.contentWindow.postMessage({ estructura: seccion }, '*');
    }
    pintar();
    ventana.hidden = false;
    boton.setAttribute('aria-expanded', 'true');
    boton.classList.remove('et-min');
    ventana.focus({ preventScroll: true });
  }
  function ocultar(minimizada) {
    ventana.hidden = true;
    boton.setAttribute('aria-expanded', 'false');
    boton.classList.toggle('et-min', !!minimizada);
    boton.focus({ preventScroll: true });
  }

  marco.addEventListener('load', function () { ventana.classList.add('et-listo'); });
  boton.addEventListener('click', function () { abrir(''); });

  ventana.addEventListener('click', function (e) {
    var b = e.target.closest('[data-et]');
    if (!b) return;
    var accion = b.getAttribute('data-et');
    if (accion === 'min') ocultar(true);
    else if (accion === 'close') ocultar(false);
    else if (accion === 'max') { geo.max = !geo.max; pintar(); guardar(); }
  });
  ventana.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') ocultar(true);
  });

  /* Mover por la barra */
  barra.addEventListener('dblclick', function (e) {
    if (e.target.closest('[data-et]') || MOVIL.matches) return;
    geo.max = !geo.max; pintar(); guardar();
  });
  barra.addEventListener('pointerdown', function (e) {
    if (e.button !== 0 || e.target.closest('[data-et]') || geo.max || MOVIL.matches) return;
    var dx = e.clientX - geo.x, dy = e.clientY - geo.y;
    barra.setPointerCapture(e.pointerId);
    ventana.classList.add('et-drag');
    function mover(ev) {
      geo.x = Math.min(Math.max(ev.clientX - dx, MARGEN), window.innerWidth - geo.w - MARGEN);
      geo.y = Math.min(Math.max(ev.clientY - dy, MARGEN), window.innerHeight - geo.h - MARGEN);
      ventana.style.left = geo.x + 'px';
      ventana.style.top = geo.y + 'px';
    }
    function soltar() {
      ventana.classList.remove('et-drag');
      barra.removeEventListener('pointermove', mover);
      barra.removeEventListener('pointerup', soltar);
      barra.removeEventListener('pointercancel', soltar);
      guardar();
    }
    barra.addEventListener('pointermove', mover);
    barra.addEventListener('pointerup', soltar);
    barra.addEventListener('pointercancel', soltar);
  });

  /* Cambiar de tamaño por la esquina */
  esquina.addEventListener('pointerdown', function (e) {
    if (e.button !== 0 || geo.max || MOVIL.matches) return;
    e.preventDefault();
    var x0 = e.clientX, y0 = e.clientY, w0 = geo.w, h0 = geo.h;
    esquina.setPointerCapture(e.pointerId);
    ventana.classList.add('et-resizing');
    function mover(ev) {
      geo.w = Math.min(Math.max(w0 + ev.clientX - x0, MIN_W), window.innerWidth - geo.x - MARGEN);
      geo.h = Math.min(Math.max(h0 + ev.clientY - y0, MIN_H), window.innerHeight - geo.y - MARGEN);
      ventana.style.width = geo.w + 'px';
      ventana.style.height = geo.h + 'px';
    }
    function soltar() {
      ventana.classList.remove('et-resizing');
      esquina.removeEventListener('pointermove', mover);
      esquina.removeEventListener('pointerup', soltar);
      esquina.removeEventListener('pointercancel', soltar);
      guardar();
    }
    esquina.addEventListener('pointermove', mover);
    esquina.addEventListener('pointerup', soltar);
    esquina.addEventListener('pointercancel', soltar);
  });

  window.addEventListener('resize', function () { if (!ventana.hidden) pintar(); });

  /* Enlaces de la página: <button data-estructura="bd">…</button> */
  document.addEventListener('click', function (e) {
    var t = e.target.closest('[data-estructura]');
    if (!t || ventana.contains(t)) return;
    e.preventDefault();
    abrir(t.getAttribute('data-estructura'));
  });
})();
