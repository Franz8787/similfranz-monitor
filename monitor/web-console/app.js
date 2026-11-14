// similFranz Controller (web) — servito da similFranz Monitor, same-origin, nessuna dipendenza esterna.
// v3: in alto i valori VERI del paziente (sempre visibili) con la riga "monitor:" per ciò che vede il discente;
//     a sinistra il paziente stilizzato (testa-ginocchia) solo per i sensori; al centro i controlli in una scheda unica.
(function () {
  'use strict';
  if (window.SF_PHONE) return;     // su telefoni e tablet la console non parte (vedi index.html)
  var RHYTHMS = {
    sinus: 'Sinusale', sinus_tachycardia: 'Tachicardia sinusale', sinus_bradycardia: 'Bradicardia sinusale',
    afib: 'Fibrillazione atriale', vt_pulse: 'TV con polso', vt: 'TV senza polso', vf: 'Fibrillazione ventricolare',
    asystole: 'Asistolia', pea: 'PEA'
  };
  var ARREST = ['vt_pulse', 'vt', 'vf', 'asystole', 'pea'];
  // sensori: nome, colore (come sul monitor), scheda dei controlli da evidenziare, posizione predefinita
  var SENS = {
    ecg:   { name: 'ECG',     full: 'Elettrodi ECG',          color: '#3cff6e', panel: 'patient', card: 'card_rhythm', def: 'chest' },
    spo2:  { name: 'SpO₂',    full: 'Sonda SpO₂',             color: '#3cdcff', panel: 'patient', card: 'card_resp',   def: 'finger_l2' },
    nibp:  { name: 'NIBP',    full: 'Bracciale NIBP',         color: '#f0557a', panel: 'patient', card: 'card_bp',     def: 'upper_arm_r' },
    art:   { name: 'ART',     full: 'Linea arteriosa',        color: '#ff3b30', panel: 'patient', card: 'card_bp',     def: 'radial_l' },
    etco2: { name: 'EtCO₂',   full: 'Capnografia',            color: '#f2e05a', panel: 'patient', card: 'card_resp',   def: 'airway' },
    temp:  { name: 'Temp',    full: 'Sonda temperatura',      color: '#cc9eff', panel: 'patient', card: 'card_exam',   def: 'forehead' },
    pads:  { name: 'Piastre', full: 'Piastre defibrillatore', color: '#ff7a1a', panel: 'defib',   card: null,          def: 'chest' },
    oxi:   { name: 'Satur.',  full: 'Sensore del saturimetro', color: '#8fd6ff', panel: 'patient', card: 'panel_oxi',   def: 'finger_r2' }
  };
  var ORDER = ['ecg', 'spo2', 'nibp', 'art', 'etco2', 'temp', 'pads', 'oxi'];
  var FINGERS = ['pollice', 'indice', 'medio', 'anulare', 'mignolo'];
  // parametri regolabili: le transizioni ("in N s") valgono per quelli senza "now"
  var P = {
    heart_rate_bpm:       { l: 'FC', u: 'bpm', min: 0, max: 250, step: 1, q: [40, 60, 80, 100, 130, 160], c: 'hr' },
    spo2_percent:         { l: 'SpO₂', u: '%', min: 0, max: 100, step: 1, q: [75, 85, 90, 94, 98], c: 'spo2' },
    systolic_mmhg:        { l: 'Sistolica', u: 'mmHg', min: 40, max: 260, step: 1, c: 'art' },
    diastolic_mmhg:       { l: 'Diastolica', u: 'mmHg', min: 20, max: 160, step: 1, c: 'art' },
    respiratory_rate_rpm: { l: 'FR', u: 'atti/min', min: 0, max: 50, step: 1, q: [0, 8, 12, 16, 24, 32], c: 'co2' },
    etco2_mmhg:           { l: 'EtCO₂', u: 'mmHg', min: 0, max: 100, step: 1, q: [10, 20, 35, 45, 60], c: 'co2' },
    temperature_c:        { l: 'Temperatura', u: '°C · subito', min: 30, max: 43, step: 0.1, c: 'temp', now: 'set_temperature', dec: 1, q: [34, 35.5, 36.8, 38.5, 40] },
    crt_s:                { l: 'Refill capillare', u: 's · subito', min: 0.5, max: 8, step: 0.5, c: 'temp', now: 'set_crt', q: [1, 2, 3, 4, 6] }
  };
  var PNAME = { heart_rate_bpm: 'FC', spo2_percent: 'SpO₂', systolic_mmhg: 'PAs', diastolic_mmhg: 'PAd',
                respiratory_rate_rpm: 'FR', etco2_mmhg: 'EtCO₂' };
  var BPQ = [['Shock', 70, 40], ['Ipotesa', 90, 55], ['Normale', 120, 80], ['Ipertesa', 170, 100], ['Crisi', 220, 125]];
  var DCFG_NUM = ['shocks_to_convert', 'min_energy_j', 'cv_shocks_to_convert', 'cv_min_energy_j', 'capture_threshold_ma', 'aed_energy_j', 'aed_cpr_s'];
  var DCFG_BOOL = ['unsync_shock_vf', 'sync_stays_on', 'capture_possible', 'mechanical_capture', 'voice_prompts'];
  var DCFG_RHY = ['post_shock_rhythm', 'cv_post_rhythm'];
  var DMODE = { off: 'spento', aed: 'DAE', manual: 'manuale', pacer: 'pacer' };
  var LIMITS = ['hr_low', 'hr_high', 'spo2_low', 'sys_low', 'sys_high', 'rr_low', 'rr_high', 'etco2_low', 'etco2_high'];
  // pannelli della plancia: card dei parametri + pannelli secondari
  var CARDS = ['card_rhythm', 'card_bp', 'card_resp', 'card_exam', 'card_physio', 'panel_defib', 'panel_monitor', 'panel_oxi', 'panel_alarms'];

  var $ = function (id) { return document.getElementById(id); };
  var all = function (sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); };
  var token = sessionStorage.getItem('sf_token') || '';
  // collegamento con PIN già nel link: http://IP:porta/#pin=XXXXXX  (il frammento resta nel browser, non viaggia in rete)
  (function () {
    var m = /[#&]pin=([^&]+)/.exec(location.hash || '');
    if (!m) return;
    token = decodeURIComponent(m[1]);
    try { sessionStorage.setItem('sf_token', token); history.replaceState(null, '', location.pathname); } catch (e) {}
  })();
  // identità di questo controller: il monitor accetta i comandi di UN controller alla volta
  var clientId = '';
  try { clientId = localStorage.getItem('sf_client') || ''; } catch (e) {}
  if (!clientId) {
    clientId = 'web-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 10);
    try { localStorage.setItem('sf_client', clientId); } catch (e) {}
  }
  var clientName = 'Web app · ' + (function () {
    var u = navigator.userAgent || '';
    if (/iPad/.test(u) || (/Macintosh/.test(u) && navigator.maxTouchPoints > 1)) return 'iPad';
    if (/iPhone|iPod/.test(u)) return 'iPhone';
    if (/Android/.test(u)) return 'Android';
    if (/Macintosh/.test(u)) return 'Mac';
    if (/Windows/.test(u)) return 'PC Windows';
    if (/Linux/.test(u)) return 'PC Linux';
    return 'browser';
  })();
  var ctlMine = false;      // diventa vero quando il monitor dice che comandiamo noi
  var state = null, pollTimer = null, failures = 0, editing = {}, limitsDirty = false, dcfgDirty = false;
  var mode = 0, pending = {}, pendingRhythm = null, cmdSeq = 0, POLL_MS = 500;
  var card = sessionStorage.getItem('sf_card') || 'card_rhythm', selSensor = null;
  if (CARDS.indexOf(card) < 0) card = 'card_rhythm';

  // ---------- rete ----------
  function api(method, path, body) {
    var opt = { method: method, headers: { 'X-SimulaFranz-Token': token, 'X-SimulaFranz-Client': clientId,
      'X-SimulaFranz-Client-Name': encodeURIComponent(clientName), 'X-SimulaFranz-Client-Kind': 'web' }, cache: 'no-store' };
    if (body !== undefined) { opt.headers['Content-Type'] = 'application/json'; opt.body = JSON.stringify(body); }
    return fetch(path, opt).then(function (r) {
      return r.json().catch(function () { return { ok: false, error: 'HTTP ' + r.status }; })
        .then(function (j) { j._status = r.status; return j; });
    });
  }
  // fetch senza risposta (iPad uscito dal Wi-Fi) non deve bloccare il ciclo di lettura
  function withTimeout(p, ms) {
    return new Promise(function (ok, ko) {
      var t = setTimeout(function () { ko(new Error('timeout')); }, ms);
      p.then(function (v) { clearTimeout(t); ok(v); }, function (e) { clearTimeout(t); ko(e); });
    });
  }
  function command(name, value) {
    cmdSeq++;
    var body = { command: name };
    if (state) body.device_id = state.device_id;
    if (value !== undefined) body.value = value;
    return api('POST', '/api/v1/command', body).then(handle);
  }
  function handle(j) {
    if (!j) return;
    if (j._status === 401) { token = ''; sessionStorage.removeItem('sf_token'); showLogin('PIN non valido'); return; }
    if (j._status === 429) { showLogin('Troppi tentativi: riprova tra qualche secondo'); return; }
    if (j.controller) showControl(j.controller);
    if (j.scenarios) setScenarios(j.scenarios);
    if (j.scenario) onScenario(j.scenario);
    if (j.log_next !== undefined) logSync(j.log_next, j.log_session);
    if (j._status === 423) { msg('Comando non eseguito: il monitor è comandato da un altro controller'); return; }
    if (!j.ok) { msg('Errore: ' + (j.error || 'sconosciuto')); return; }
    if (!/adeguata/.test($('msg').textContent)) msg('');
    if (j.state) render(j.state);
  }
  // Un solo controller alla volta (regole sul monitor, SFControl): leggere non prende il comando, il primo comando sì;
  // chi comanda attivamente è protetto, chi è fermo da più di un minuto cede al primo comando di un altro.
  // Qui si vede sempre chi comanda, con che cosa e da dove; chi perde il comando sa a chi è passato.
  var KIND = { web: 'web app', ipad: 'iPad', ipod: 'iPod' };
  function ago(s) { s = s || 0; return s < 90 ? s + ' s' : Math.round(s / 60) + ' min'; }
  function showControl(c) {
    var other = !!(c.active && !c.mine), idle = other && c.protected === false;
    if (other) {
      $('busyName').textContent = c.name || 'un altro controller';
      $('busyVia').textContent = ' (' + (KIND[c.kind] || 'controller') + ', ' + (c.transport === 'direct' ? 'collegamento diretto' : 'Wi-Fi') + ')';
      $('busyHow').textContent = idle ? ', fermo da ' + ago(c.action_idle_s) + ': il tuo primo comando prende il controllo.'
                                      : ': da qui puoi solo osservare.';
      $('takeCtl').textContent = c.lost_to ? 'Riprendi il controllo' : 'Prendi il controllo';
    }
    $('busy').hidden = !other;
    $('busy').classList.toggle('idle', idle);
    document.body.classList.toggle('observer', other && !idle);
    if (other && ctlMine) msg(c.lost_to ? '«' + c.lost_to + '» ha preso il controllo' : 'Il comando è passato a un altro controller');
    ctlMine = !!c.mine;
  }
  function takeControl() {
    api('POST', '/api/v1/control', { action: 'take' }).then(function (j) {
      handle(j); if (j && j.ok) { msg('Ora comandi tu'); poll(); }
    });
  }
  function poll() {
    clearTimeout(pollTimer);
    var seqAtStart = cmdSeq;
    withTimeout(api('GET', '/api/v1/state'), 4000).then(function (j) {
      failures = 0; setConn(true, 'collegato a similFranz Monitor');
      if (seqAtStart !== cmdSeq) return;        // nel frattempo è partito un comando: lettura superata
      handle(j);
    }).catch(function () {
      failures++; setConn(false, 'monitor non raggiungibile');
    }).then(function () {
      clearTimeout(pollTimer);                  // un solo ciclo di lettura, anche se poll() è partito due volte
      if (!$('console').hidden) pollTimer = setTimeout(poll, failures ? Math.min(5000, POLL_MS * (failures + 1)) : POLL_MS);
    });
  }

  // ---------- utilità ----------
  function setConn(on, text) {
    ['conn', 'conn2'].forEach(function (id) { var c = $(id); c.className = 'conn ' + (on ? 'on' : 'off'); c.textContent = text; });
  }
  function msg(t) { $('msg').textContent = t || ''; }
  function showLogin(err) { $('console').hidden = true; $('login').hidden = false; $('loginErr').textContent = err || ''; clearTimeout(pollTimer); }
  function showConsole() { $('login').hidden = true; $('console').hidden = false; poll(); loadScenarios(); }
  function esc(t) { var d = document.createElement('div'); d.textContent = t; return d.innerHTML; }
  function isPending() { return pendingRhythm !== null || Object.keys(pending).length > 0; }
  function on(k) { return !!(state && state.sensors && state.sensors[k]); }
  function siteOf(k) { return (state && state.sensor_sites && state.sensor_sites[k]) || SENS[k].def; }
  function siteLabel(site) {
    if (!site) return '';
    var m = /^finger_([rl])(\d)$/.exec(site);
    if (m) return FINGERS[+m[2] - 1] + (m[1] === 'r' ? ' destro' : ' sinistro');
    var lab = { chest: 'torace', pads_r: 'sottoclaveare destra', pads_l: 'apice (ascellare sinistra)', airway: 'naso e bocca', forehead: 'fronte',
      upper_arm_r: 'braccio destro', upper_arm_l: 'braccio sinistro',
      radial_r: 'polso destro (radiale)', radial_l: 'polso sinistro (radiale)',
      femoral_r: 'inguine destro (femorale)', femoral_l: 'inguine sinistro (femorale)' };
    return lab[site] || site;
  }
  function siteSensor(site) {
    if (/^upper_arm_/.test(site)) return 'nibp';
    if (/^(radial|femoral)_/.test(site)) return 'art';
    if (/^finger_/.test(site)) {
      if (selSensor === 'oxi') return 'oxi';
      if (on('oxi') && siteOf('oxi') === site && !(on('spo2') && siteOf('spo2') === site)) return 'oxi';
      return 'spo2';
    }
    if (site === 'airway') return 'etco2';
    if (site === 'forehead') return 'temp';
    if (site === 'chest') return 'ecg';
    if (/^pads_/.test(site)) return 'pads';
    return null;
  }
  function sideOf(site) { var m = /_([rl])\d?$/.exec(site || ''); return m ? m[1] : null; }

  // =====================================================================
  // PAZIENTE (SVG): sagoma stilizzata, supina, dalla testa alle ginocchia
  // =====================================================================
  var CX = 180;
  function f1(x) { return Math.round(x * 10) / 10; }
  function nrm(x, y) { var m = Math.hypot(x, y) || 1; return [x / m, y / m]; }
  function cr(P2, closed) {                         // Catmull-Rom -> Bézier
    var n = P2.length, d = 'M' + f1(P2[0][0]) + ' ' + f1(P2[0][1]), last = closed ? n : n - 1;
    for (var i = 0; i < last; i++) {
      var p0 = P2[(i - 1 + n) % n], p1 = P2[i], p2 = P2[(i + 1) % n], p3 = P2[(i + 2) % n];
      if (!closed) { if (i === 0) p0 = p1; if (i + 2 >= n) p3 = p2; }
      d += 'C' + f1(p1[0] + (p2[0] - p0[0]) / 6) + ' ' + f1(p1[1] + (p2[1] - p0[1]) / 6) + ' ' +
           f1(p2[0] - (p3[0] - p1[0]) / 6) + ' ' + f1(p2[1] - (p3[1] - p1[1]) / 6) + ' ' + f1(p2[0]) + ' ' + f1(p2[1]);
    }
    return d + (closed ? 'Z' : '');
  }
  function limb(cl, pad) {                          // linea mediana [x,y,raggio] -> contorno chiuso con estremi arrotondati
    pad = pad || 0;
    var L = [], R = [], n = cl.length, i;
    for (i = 0; i < n; i++) {
      var a = cl[Math.max(0, i - 1)], b = cl[Math.min(n - 1, i + 1)], t = nrm(b[0] - a[0], b[1] - a[1]), r = cl[i][2] + pad;
      L.push([cl[i][0] - t[1] * r, cl[i][1] + t[0] * r]); R.push([cl[i][0] + t[1] * r, cl[i][1] - t[0] * r]);
    }
    var e = cl[n - 1], te = nrm(e[0] - cl[n - 2][0], e[1] - cl[n - 2][1]), re = e[2] + pad;
    var s = cl[0], ts = nrm(s[0] - cl[1][0], s[1] - cl[1][1]), rs = s[2] + pad;
    return cr(L.concat([[e[0] + te[0] * re * 0.9, e[1] + te[1] * re * 0.9]], R.reverse(), [[s[0] + ts[0] * rs * 0.9, s[1] + ts[1] * rs * 0.9]]), true);
  }
  function mir(p) { return [2 * CX - p[0], p[1]].concat(p.slice(2)); }

  // Il corpo è /body.svg ("Male front 3d-shaded human illustration" di Goran tek-en,
  // Wikimedia Commons, CC BY-SA 4.0), ritagliato testa-ginocchia e reso "manichino"
  // dal filtro CSS. Lato destro del paziente = sinistra dello schermo. viewBox 0 0 360 620.
  var IMG = { x: 15, y: 6, w: 330 }; IMG.h = IMG.w * 946.13 / 402.94;
  // coordinate dei punti sul corpo (calibrate sull'immagine resa, viewBox 0 0 360 620)
  var G = {
    forehead: [180, 32], airway: [180, 72],
    chest: [[128, 146], [232, 146], [240, 190], [238, 250], [230, 308], [180, 322], [130, 308], [122, 250], [120, 190]],
    ecg: [['R', 146, 160, '#e53935'], ['L', 214, 160, '#fdd835'], ['C', 194, 228, '#f4f4f4'], ['N', 152, 290, '#1d1d1d'], ['F', 208, 290, '#43a047']],
    padR: [143, 170, -12, 40, 50], padL: [230, 235, -25, 42, 54],
    cuffA: [104, 206, 14], cuffB: [102, 240, 15],     // omero: ascella ~195, gomito ~257 -> bracciale centrato (bordi braccio: 87..118)
    armHot: [[104, 196, 13], [103, 222, 14], [102, 246, 15]],
    radial: [63, 359], forearmDir: [-0.35, 0.93], femoral: [140, 400], femAngR: -115,
    fingers: [                                      // destro, pollice..mignolo: [punta x, punta y, direzione x, direzione y]
      [23, 399, -0.47, 0.88], [31, 438, -0.33, 0.95], [43, 447, -0.20, 0.98],
      [52, 444, -0.25, 0.97], [66, 437, -0.05, 1]
    ],
    cpr: [180, 225], breath: [180, 222, 64, 76], touch: [116, 160], fadeY: 572, clipY: 612
  };
  function handGeo(side) {                          // mani aperte, dita a ventaglio verso i piedi
    var g = { radial: side === 'r' ? G.radial.slice() : mir(G.radial),
              dir: side === 'r' ? nrm(G.forearmDir[0], G.forearmDir[1]) : nrm(-G.forearmDir[0], G.forearmDir[1]),
              fingers: [] };
    G.fingers.forEach(function (f, i) {
      var tip = [f[0], f[1]], dir = nrm(f[2], f[3]);
      if (side === 'l') { tip = mir(tip); dir = [-dir[0], dir[1]]; }
      g.fingers.push({ n: i + 1, tip: tip, dir: dir, site: 'finger_' + side + (i + 1),
        cl: [[tip[0] - dir[0] * 24, tip[1] - dir[1] * 24, 5], [tip[0], tip[1], 4.5]] });
    });
    return g;
  }
  var HAND, FINGER_BY_SITE, MARKS;
  function buildGeo() {
    HAND = { r: handGeo('r'), l: handGeo('l') };
    FINGER_BY_SITE = {};
    ['r', 'l'].forEach(function (s) { HAND[s].fingers.forEach(function (fg) { FINGER_BY_SITE[fg.site] = fg; }); });
    MARKS = [['forehead', G.forehead[0], G.forehead[1]], ['airway', G.airway[0], G.airway[1]],
             ['chest', G.ecg[2][1], G.ecg[2][2]], ['pads_r', G.padR[0], G.padR[1]], ['pads_l', G.padL[0], G.padL[1]],
             ['upper_arm_r', G.armHot[1][0], G.armHot[1][1]], ['upper_arm_l', mir(G.armHot[1])[0], G.armHot[1][1]],
             ['radial_r', G.radial[0], G.radial[1]], ['radial_l', mir(G.radial)[0], G.radial[1]],
             ['femoral_r', G.femoral[0], G.femoral[1]], ['femoral_l', mir(G.femoral)[0], G.femoral[1]],
             ['finger_r3', G.fingers[2][0], G.fingers[2][1]], ['finger_l3', mir(G.fingers[2])[0], G.fingers[2][1]]];
  }
  buildGeo();
  var hoverSite = null;
  function T(x, y, attrs, txt) { return '<text x="' + x + '" y="' + y + '" ' + attrs + '>' + txt + '</text>'; }

  function buildFigure() {
    var hot = [];
    hot.push(['chest', '<path d="' + cr(G.chest, true) + '"/>']);
    [['pads_r', G.padR], ['pads_l', G.padL]].forEach(function (pq) {
      var q = pq[1];
      hot.push([pq[0], '<ellipse cx="' + q[0] + '" cy="' + q[1] + '" rx="' + (q[3] / 2 + 5) + '" ry="' + (q[4] / 2 + 5) + '" transform="rotate(' + q[2] + ' ' + q[0] + ' ' + q[1] + ')"/>']);
    });
    hot.push(['airway', '<ellipse cx="' + G.airway[0] + '" cy="' + G.airway[1] + '" rx="16" ry="13"/>']);
    hot.push(['forehead', '<ellipse cx="' + G.forehead[0] + '" cy="' + G.forehead[1] + '" rx="22" ry="11"/>']);
    ['r', 'l'].forEach(function (s) {
      var mk = s === 'r' ? function (p) { return p; } : mir, h = HAND[s];
      hot.push(['upper_arm_' + s, '<path d="' + limb(G.armHot.map(mk), 5) + '"/>']);
      hot.push(['radial_' + s, '<circle cx="' + f1(h.radial[0]) + '" cy="' + f1(h.radial[1]) + '" r="12"/>']);
      hot.push(['femoral_' + s, '<ellipse cx="' + mk(G.femoral)[0] + '" cy="' + G.femoral[1] + '" rx="14" ry="12"/>']);
      h.fingers.forEach(function (fg) { hot.push([fg.site, '<path d="' + limb(fg.cl, 3) + '"/>']); });
    });
    var hots = hot.map(function (h) { return h[1].replace(/^<(\w+)/, '<$1 class="hot" data-site="' + h[0] + '"'); }).join('');
    var marks = MARKS.map(function (m) {
      return '<g class="mark" data-site="' + m[0] + '" transform="translate(' + m[1] + ',' + m[2] + ')"><circle class="ring" r="8"/><circle class="dot" r="2.2"/></g>';
    }).join('');
    var la = 'font-size="14" font-weight="700" fill="#7f91a4" text-anchor="middle"';
    return '<svg viewBox="0 0 360 620" preserveAspectRatio="xMidYMid meet" xmlns="http://www.w3.org/2000/svg">' +
      '<defs>' +
      '<linearGradient id="bedG" x1="0" x2="1"><stop offset="0" stop-color="#151d27"/><stop offset=".5" stop-color="#1b2531"/><stop offset="1" stop-color="#151d27"/></linearGradient>' +
      '<linearGradient id="fadeG" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0a0e13" stop-opacity="0"/><stop offset=".85" stop-color="#0a0e13" stop-opacity=".97"/><stop offset="1" stop-color="#0a0e13"/></linearGradient>' +
      '<radialGradient id="breathG"><stop offset="0" stop-color="#ffffff" stop-opacity=".5"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient>' +
      '<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur in="SourceAlpha" stdDeviation="3.5" result="b"/>' +
      '<feFlood flood-color="#3cdcff" flood-opacity=".95"/><feComposite in2="b" operator="in" result="g"/><feMerge><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge></filter>' +
      '<filter id="led" x="-200%" y="-200%" width="500%" height="500%"><feGaussianBlur stdDeviation="2"/></filter>' +
      '<clipPath id="bodyClip"><rect x="0" y="0" width="360" height="' + G.clipY + '"/></clipPath>' +
      '</defs>' +
      '<rect x="16" y="4" width="328" height="616" rx="26" fill="url(#bedG)" stroke="#273546" stroke-width="2"/>' +
      '<rect x="28" y="16" width="304" height="596" rx="20" fill="none" stroke="#1f2b38" stroke-width="1.5"/>' +
      '<rect x="118" y="10" width="124" height="104" rx="38" fill="#1e2935" stroke="#2b3a4b"/>' +
      T(52, 28, la, 'DX') + T(308, 28, la, 'SX') +
      '<g id="bodyAll" clip-path="url(#bodyClip)">' +
      '<image id="bodyImg" class="body" href="/body.svg" x="' + IMG.x + '" y="' + IMG.y + '" width="' + f1(IMG.w) + '" height="' + f1(IMG.h) + '"/>' +
      '<ellipse id="breath" cx="' + G.breath[0] + '" cy="' + G.breath[1] + '" rx="' + G.breath[2] + '" ry="' + G.breath[3] + '" fill="url(#breathG)" opacity="0"/>' +
      '<g id="devs"></g><g id="fx"></g>' +
      '</g>' +
      '<rect x="0" y="' + G.fadeY + '" width="360" height="' + (620 - G.fadeY) + '" fill="url(#fadeG)" pointer-events="none"/>' +
      '<g id="marks">' + marks + '</g>' +
      '<g id="hots">' + hots + '</g>' +
      '</svg>';
  }

  // ---------- disegno dei sensori applicati ----------
  function rot(p, ang, inner) { return '<g transform="translate(' + f1(p[0]) + ',' + f1(p[1]) + ') rotate(' + f1(ang) + ')">' + inner + '</g>'; }
  function deg(d) { return Math.atan2(d[1], d[0]) * 180 / Math.PI; }
  function drawSensor(k, site, s) {
    var out = '';
    if (k === 'ecg') {
      G.ecg.forEach(function (e) {
        out += '<circle cx="' + e[1] + '" cy="' + e[2] + '" r="8.5" fill="#eef1f4" stroke="#9aa7b4" stroke-width="1.1"/>' +
               '<circle cx="' + e[1] + '" cy="' + e[2] + '" r="3.8" fill="' + e[3] + '" stroke="#2b2b2b" stroke-width=".8"/>';
      });
    } else if (k === 'pads') {
      var pad = function (q) {
        var w = q[3], h = q[4];
        return rot(q, q[2], '<rect x="' + (-w / 2) + '" y="' + (-h / 2) + '" width="' + w + '" height="' + h + '" rx="8" fill="#f3f5f7" stroke="#b9c3cd" stroke-width="1.3"/>' +
          '<rect x="' + (-w / 2 + 5) + '" y="' + (-h / 2 + 5) + '" width="' + (w - 10) + '" height="' + (h - 10) + '" rx="5" fill="#ffe8d6" stroke="#ff7a1a" stroke-width="1" opacity=".9"/>' +
          '<rect x="' + (-w / 2 + 5) + '" y="' + (-h / 2 - 1) + '" width="' + (w - 10) + '" height="4" rx="2" fill="#ff7a1a"/>');
      };
      out += pad(G.padR) + pad(G.padL);
    } else if (k === 'spo2') {
      var fg = FINGER_BY_SITE[site] || FINGER_BY_SITE[SENS.spo2.def];
      var ctr = [fg.tip[0] - fg.dir[0] * 6, fg.tip[1] - fg.dir[1] * 6];
      out += rot(ctr, deg(fg.dir), '<rect x="-12" y="-7.5" width="22" height="15" rx="6" fill="#28313b" stroke="#0b0f13" stroke-width="1.1"/>' +
        '<rect x="-12" y="-7.5" width="7" height="15" rx="3.5" fill="#3a4552"/>' +
        '<circle cx="2" cy="0" r="4" fill="#ff2a2a" filter="url(#led)"/><circle cx="2" cy="0" r="1.6" fill="#ffd0d0"/>');
    } else if (k === 'oxi') {
      var fo = FINGER_BY_SITE[site] || FINGER_BY_SITE[SENS.oxi.def];
      var co = [fo.tip[0] - fo.dir[0] * 7, fo.tip[1] - fo.dir[1] * 7];
      out += rot(co, deg(fo.dir), '<rect x="-13" y="-8" width="23" height="16" rx="5" fill="#50607a" stroke="#1c2430" stroke-width="1.1"/>' +
        '<rect x="-13" y="-8" width="8" height="16" rx="4" fill="#6b7d9b"/><line x1="-13" y1="0" x2="-26" y2="0" stroke="#6a5acd" stroke-width="2.2" stroke-linecap="round"/>' +
        '<circle cx="3" cy="0" r="3.6" fill="#8fd6ff" filter="url(#led)"/><circle cx="3" cy="0" r="1.4" fill="#ffffff"/>');
    } else if (k === 'nibp') {
      var sd = sideOf(site) || 'r', A = G.cuffA.slice(), B = G.cuffB.slice();
      if (sd === 'l') { A = mir(A); B = mir(B); }
      var t = nrm(B[0] - A[0], B[1] - A[1]), n = [-t[1], t[0]];
      var q = [[A[0] + n[0] * A[2], A[1] + n[1] * A[2]], [B[0] + n[0] * B[2], B[1] + n[1] * B[2]], [B[0] - n[0] * B[2], B[1] - n[1] * B[2]], [A[0] - n[0] * A[2], A[1] - n[1] * A[2]]];
      var poly = q.map(function (p) { return f1(p[0]) + ',' + f1(p[1]); }).join(' ');
      var stripes = [0.35, 0.65].map(function (u) {
        var a = [A[0] + (B[0] - A[0]) * u, A[1] + (B[1] - A[1]) * u], r = A[2] + (B[2] - A[2]) * u - 3;
        return '<line x1="' + f1(a[0] + n[0] * r) + '" y1="' + f1(a[1] + n[1] * r) + '" x2="' + f1(a[0] - n[0] * r) + '" y2="' + f1(a[1] - n[1] * r) + '" stroke="#36577c" stroke-width="2"/>';
      }).join('');
      var meas = s.nibp_status === 'measuring';
      out += '<g class="cuff' + (meas ? ' inflating' : '') + '"><polygon points="' + poly + '" fill="#1f3a5a" stroke="' + (meas ? '#f0557a' : '#0e1a28') + '" stroke-width="' + (meas ? 2.5 : 1.3) + '" stroke-linejoin="round"/>' + stripes + '</g>';
    } else if (k === 'art') {
      var pt, ang;
      if (/^radial/.test(site)) { var h = HAND[sideOf(site) || 'l']; pt = h.radial; ang = deg(h.dir) + 180; }
      else { pt = sideOf(site) === 'r' ? G.femoral : mir(G.femoral); ang = sideOf(site) === 'r' ? G.femAngR : -180 - G.femAngR; }
      out += rot(pt, ang, '<rect x="-11" y="-8" width="22" height="16" rx="4" fill="rgba(225,238,248,.30)" stroke="rgba(235,245,255,.75)" stroke-width="1.1"/>' +
        '<line x1="-6" y1="0" x2="6" y2="0" stroke="#eef3f7" stroke-width="2.2" stroke-linecap="round"/><rect x="5" y="-3.4" width="7" height="6.8" rx="1.8" fill="#d32f2f"/>');
    } else if (k === 'etco2') {
      var a = G.airway;
      out += '<path d="M' + (a[0] - 22) + ' ' + (a[1] - 9) + 'Q' + (a[0] - 11) + ' ' + (a[1] + 4) + ' ' + a[0] + ' ' + a[1] +
             'Q' + (a[0] + 11) + ' ' + (a[1] + 4) + ' ' + (a[0] + 22) + ' ' + (a[1] - 9) + '" fill="none" stroke="#dfe7ee" stroke-width="2.3" stroke-linecap="round" opacity=".95"/>' +
             '<path d="M' + (a[0] - 4) + ' ' + a[1] + 'l0 -4M' + (a[0] + 4) + ' ' + a[1] + 'l0 -4" stroke="#dfe7ee" stroke-width="2" stroke-linecap="round"/>';
    } else if (k === 'temp') {
      var fh = G.forehead;
      out += '<rect x="' + (fh[0] - 14) + '" y="' + (fh[1] - 6) + '" width="28" height="12" rx="4" fill="rgba(245,242,230,.55)" stroke="rgba(200,190,170,.7)"/>' +
             '<circle cx="' + fh[0] + '" cy="' + fh[1] + '" r="5" fill="#e6dcf7" stroke="#8a72b8" stroke-width="1.4"/>';
    }
    return '<g class="dev' + (selSensor === k ? ' sel' : '') + '" data-k="' + k + '">' + out + '</g>';
  }
  var devSig = '';
  function renderFigure(s) {
    var sig = JSON.stringify([s.sensors, s.sensor_sites, selSensor, s.nibp_status, s.cpr_active, s.operator_touch, s.patient_motion, s.spo2_percent < 85 || !s.pulse_present]);
    if (sig === devSig) return;
    devSig = sig;
    var devs = '';
    ORDER.forEach(function (k) { if (on(k)) devs += drawSensor(k, siteOf(k), s); });
    $('devs').innerHTML = devs;
    var fx = '';
    if (s.cpr_active) fx += '<g class="cprmark"><circle class="r1" cx="' + G.cpr[0] + '" cy="' + G.cpr[1] + '" r="8" stroke-width="3"/>' +
      '<ellipse cx="' + G.cpr[0] + '" cy="' + G.cpr[1] + '" rx="19" ry="14" fill="rgba(255,107,107,.22)" stroke="#ff6b6b" stroke-width="2"/>' +
      T(G.cpr[0], G.cpr[1] + 34, 'text-anchor="middle" font-size="12" font-weight="700" fill="#ff8b8b"', 'RCP') + '</g>';
    if (s.operator_touch) fx += '<g class="touchmark"><circle cx="' + G.touch[0] + '" cy="' + G.touch[1] + '" r="17" fill="rgba(127,178,255,.22)" stroke="#7fb2ff" stroke-width="2"/>' +
      T(G.touch[0], G.touch[1] + 30, 'text-anchor="middle" font-size="11" font-weight="700" fill="#9cc4ff"', 'tocco') + '</g>';
    $('fx').innerHTML = fx;
    $('bodyAll').setAttribute('class', s.patient_motion === 'strong' ? 'm2' : s.patient_motion === 'light' ? 'm1' : '');
    var cyan = s.spo2_percent < 85 || !s.pulse_present;   // cianosi: il corpo vira al blu (filtro CSS)
    $('bodyImg').setAttribute('class', 'body' + (cyan ? ' cyan' : ''));
    var hasSite = function (ds) {
      var tg = hotTarget(ds);
      return !!(tg && on(tg.k) && siteOf(tg.k) === tg.site);
    };
    all('.hot').forEach(function (h) { h.setAttribute('class', 'hot' + (hasSite(h.dataset.site) ? ' has' : '')); });
    all('.mark').forEach(function (m) {
      var ds = m.dataset.site, tg = hotTarget(ds);
      var hide = hasSite(ds) || (tg && /^finger_/.test(ds) && on(tg.k));   // nasconde il segnaposto del dito se la SpO₂ è già applicata
      m.setAttribute('class', 'mark' + (hide ? ' has' : ''));
    });
  }
  // torace che si alza con il respiro (FR del paziente)
  function breathLoop(t) {
    var el = $('breath');
    if (el && state) {
      var rr = state.respiratory_rate_rpm || 0, o = 0;
      if (rr > 0 && state.simulation_running && !state.cpr_active) o = 0.26 * (0.5 - 0.5 * Math.cos(2 * Math.PI * (t / 1000) * rr / 60));
      el.setAttribute('opacity', o.toFixed(3));
    }
    requestAnimationFrame(breathLoop);
  }

  // ---------- interazione sul paziente ----------
  // un clic = sensore posizionato + monitor avvisato (traccia/valore attivi) + scheda del parametro evidenziata
  function hotTarget(hs) {
    var k = siteSensor(hs); if (!k) return null;
    return { k: k, site: k === 'pads' ? 'chest' : hs };
  }
  function hotInfo(hs) {
    var tg = hotTarget(hs); if (!tg) return '';
    var k = tg.k, head = '<b>' + SENS[k].full + ' · ' + siteLabel(hs) + '</b>';
    if (!on(k)) return head + '<small>clicca: applica e mostra i controlli</small>';
    if (siteOf(k) === tg.site) return head + '<small>applicato · clicca per i controlli</small>';
    return head + '<small>clicca per spostarlo qui (ora: ' + siteLabel(siteOf(k)) + ')</small>';
  }
  function apply(k, site) {
    if (!on(k)) return command('set_sensor', { sensor: k, connected: true, site: site });
    if (siteOf(k) === site) return Promise.resolve();
    if (k === 'spo2' || k === 'nibp') {              // sonda/bracciale tolti e rimessi: il monitor riparte da capo
      return command('set_sensor', { sensor: k, connected: false }).then(function () {
        return command('set_sensor', { sensor: k, connected: true, site: site });
      });
    }
    return command('set_sensor', { sensor: k, connected: true, site: site });
  }
  function place(k, site) {                          // comando al monitor, poi subito disegno e scheda
    var was = on(k) ? siteOf(k) : null;
    var pr = apply(k, site);                         // (prima il comando: legge lo stato attuale del sensore)
    if (state) {
      state.sensors[k] = true;
      state.sensor_sites = state.sensor_sites || {}; state.sensor_sites[k] = site;
    }
    select(k);
    return pr;
  }
  function detach(k) {
    if (selSensor === k) selSensor = null;
    return command('set_sensor', { sensor: k, connected: false });
  }
  function stagePos(e) { var r = $('stage').getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; }
  function wireFigure() {
    var fig = $('figure'), tip = $('tip');
    fig.addEventListener('mousemove', function (e) {
      var h = e.target.closest && e.target.closest('.hot');
      if (!h || !state) { tip.hidden = true; hoverSite = null; return; }
      hoverSite = h.dataset.site;
      tip.innerHTML = hotInfo(hoverSite); tip.hidden = false;
      var p = stagePos(e); tip.style.left = (p[0] + 16) + 'px'; tip.style.top = (p[1] + 14) + 'px';
    });
    fig.addEventListener('mouseleave', function () { tip.hidden = true; hoverSite = null; });
    fig.addEventListener('click', function (e) {
      var h = e.target.closest && e.target.closest('.hot');
      if (!h || !state) return;
      var tg = hotTarget(h.dataset.site); if (!tg) return;
      var was = on(tg.k) && siteOf(tg.k) !== tg.site;
      place(tg.k, tg.site);
      if (was && (tg.k === 'spo2' || tg.k === 'nibp')) msg(SENS[tg.k].full + ' spostato: il monitor riparte con la misura');
      $('tip').innerHTML = hotInfo(h.dataset.site);
    });
  }

  // ---------- registro della sessione (debriefing) ----------
  // Il registro sta SUL MONITOR (/api/v1/log): lo scrivono il monitor stesso (ciò che fanno i partecipanti sul
  // dispositivo, ritmi, arresto/ROSC, RCP, pause, timer, fasi dello scenario, comandi dell'istruttore), questa pagina
  // (stati one-tap, osservazioni da menu rapido, note) e l'app controller per iPad: tutti vedono le stesse voci.
  var LOGE = [], logNext = 0, logSum = {}, logBusy = false, logAgain = false, qCount = {}, qMode = null, dbFilter = 'key';
  // sessioni del registro: una per simulazione (il monitor ne apre una nuova all'avvio di uno scenario o all'azzeramento)
  var logSess = null, logSessions = [], dbSess = null, dbPast = null, dbSessSig = '';      // dbSess null = sessione in corso
  var KIND = {                     // etichetta corta + nome per esteso: la categoria non è mai solo colore
    phase: ['SCEN', 'Scenario'], patient: ['PAZ', 'Paziente'], monitor: ['MON', 'Monitor'], electric: ['ELETTR', 'Terapia elettrica'],
    timer: ['TIMER', 'Timer'], action: ['AZIONE', 'Azione dei partecipanti'], drug: ['FARM', 'Farmaco'],
    plus: ['FORZA', 'Punto di forza'], minus: ['DISCUT', 'Da discutere'], note: ['NOTA', 'Nota']
  };
  // menu rapido delle osservazioni dell'istruttore: lo stesso catalogo dell'app controller per iPad
  var QCAT = [
    { g: 'Riconoscimento', it: [
      { k: 'action', t: "Riconosciuto l'arresto cardiaco", tag: 'ac' },
      { k: 'action', t: 'Chiamato aiuto / attivato il team', tag: 'help' },
      { k: 'action', t: 'Valutazione ABCDE' }, { k: 'action', t: 'Valutato il ritmo' } ] },
    { g: 'RCP', it: [
      { k: 'action', t: 'Iniziate le compressioni', tag: 'cpr_start' },
      { k: 'action', t: "Cambio dell'operatore alle compressioni" }, { k: 'action', t: 'Ventilazioni' } ] },
    { g: 'Vie aeree e accessi', it: [
      { k: 'action', t: 'Ossigeno' }, { k: 'action', t: 'Presidio sovraglottico' }, { k: 'action', t: 'Intubazione' },
      { k: 'action', t: 'Accesso venoso' }, { k: 'action', t: 'Accesso intraosseo' } ] },
    { g: 'Farmaci', it: [
      { k: 'drug', t: 'Adrenalina 1 mg' }, { k: 'drug', t: 'Amiodarone 300 mg' }, { k: 'drug', t: 'Amiodarone 150 mg' },
      { k: 'drug', t: 'Atropina 0,5 mg' }, { k: 'drug', t: 'Liquidi 500 ml' },
      { k: 'drug', t: 'Altro farmaco…', ask: 'Farmaco e dose' } ] },
    { g: 'Debriefing', it: [
      { k: 'plus', t: 'Punto di forza…', ask: 'Che cosa è andato bene' },
      { k: 'minus', t: 'Da discutere…', ask: 'Che cosa riprendere nel debriefing' },
      { k: 'note', t: 'Nota libera…', ask: 'Annotazione libera…' } ] }
  ];
  var QFLAT = [];
  QCAT.forEach(function (g) { g.it.forEach(function (it) { it.i = QFLAT.length; QFLAT.push(it); }); });

  function fmtMMSS(sec) {
    if (sec === null || sec === undefined || isNaN(sec)) return '--:--';
    sec = Math.max(0, Math.floor(sec));
    var m = Math.floor(sec / 60);
    return (m < 100 ? ('0' + m).slice(-2) : m) + ':' + ('0' + (sec % 60)).slice(-2);
  }
  function fmtDur(sec) {            // durata leggibile: "45 s", "2 min 05 s"
    if (sec === null || sec === undefined || isNaN(sec)) return '—';
    sec = Math.max(0, Math.round(sec));
    return sec < 60 ? sec + ' s' : Math.floor(sec / 60) + ' min ' + ('0' + (sec % 60)).slice(-2) + ' s';
  }
  // legge dal monitor le voci nuove (a blocchi finché ce ne sono); lo chiama handle() quando log_next cresce
  function loadLog() {
    if (logBusy) { logAgain = true; return; }
    logBusy = true; logAgain = false;
    api('GET', '/api/v1/log?since=' + logNext).then(function (j) {
      logBusy = false;
      if (!j || !j.ok) return;
      takeLog(j, false);
      if (j.more || logAgain) loadLog();
    }).catch(function () { logBusy = false; });
  }
  function takeLog(j, replace) {
    if (replace) LOGE = [];
    (j.log || []).forEach(function (e) { if (!LOGE.length || e.i > LOGE[LOGE.length - 1].i) LOGE.push(e); });
    if (j.next !== undefined) logNext = j.next;
    if (j.summary) logSum = j.summary;
    if (j.sessions) logSessions = j.sessions;
    if (j.current_session !== undefined) logSess = j.current_session;
    renderLog(); renderDebrief();
  }
  function logSync(n, sid) {        // n = log_next dello stato, sid = log_session (sessione in corso)
    if (sid !== undefined && sid !== null && sid !== logSess) {      // sessione nuova: registro e contatori ripartono da lì
      logSess = sid; LOGE = []; logNext = 0; logSum = {}; qCount = {}; renderQuick(); renderLog(); loadLog(); return;
    }
    if (n === undefined || n === null || n === logNext) return;
    var last = LOGE.length ? LOGE[LOGE.length - 1].i : -1;
    if (n <= last) { LOGE = []; logNext = 0; qCount = {}; renderQuick(); }      // registro svuotato (da qui o da un altro controller)
    loadLog();
  }
  // scrive una voce sul monitor (permesso anche quando comanda un altro controller: un secondo istruttore può annotare)
  function logAdd(txt, kind, tag) {
    var body = { action: 'add', kind: kind || 'note', text: txt };
    if (tag) body.tag = tag;
    return api('POST', '/api/v1/log', body).then(function (j) {
      if (j && j._status === 401) { handle(j); return false; }
      if (!j || !j.ok) { msg('Voce non registrata: ' + ((j && j.error) || 'il monitor non risponde')); return false; }
      LOGE = []; logNext = 0; takeLog(j, true);
      if (j.more) loadLog();
      return true;
    }).catch(function () { msg('Voce non registrata: il monitor non risponde'); return false; });
  }
  function logLine(e, big) {
    var k = KIND[e.k] || KIND.note, hh = new Date((e.w || 0) * 1000);
    var w = ('0' + hh.getHours()).slice(-2) + ':' + ('0' + hh.getMinutes()).slice(-2) + (big ? ':' + ('0' + hh.getSeconds()).slice(-2) : '');
    var extra = e.tag === 'shock' && e.energy_j ? ' <em>' + esc(String(e.energy_j)) + ' J</em>' : '';
    return '<li class="k-' + esc(e.k || 'note') + '"><b>' + fmtMMSS(e.t) + '</b><i title="' + esc(k[1]) + '">' + (big ? esc(k[1]) : k[0]) + '</i>' +
           '<span>' + esc(e.text || '') + extra + (e.by ? ' <u>' + esc(e.by) + '</u>' : '') + '</span><small>' + w + '</small></li>';
  }
  function renderLog() {
    var ol = $('sessLog'); if (!ol) return;
    ol.innerHTML = LOGE.slice(-150).reverse().map(function (e) { return logLine(e, false); }).join('') ||
      '<li class="empty"><span>Ancora nessuna voce: il registro si riempie da solo con quello che fanno i partecipanti e l\'istruttore.</span></li>';
  }
  function renderQuick() {
    var el = $('ivGrid'); if (!el) return;
    el.innerHTML = QCAT.map(function (g) {
      return '<h4>' + esc(g.g) + '</h4><div class="qrow">' + g.it.map(function (it) {
        var c = qCount[it.i] || 0;
        return '<button data-q="' + it.i + '" class="q-' + it.k + (qMode === it.i ? ' active' : '') + '" title="Registra: ' + esc(it.t) + '">' +
               esc(it.t) + (c ? '<i>' + c + '</i>' : '') + '</button>';
      }).join('') + '</div>';
    }).join('');
  }
  function setAsk(i) {              // i = voce che chiede un testo (null = nota libera)
    qMode = i;
    var it = i === null ? null : QFLAT[i];
    var k = it ? it.k : 'note';
    $('askKind').textContent = (KIND[k] || KIND.note)[1];
    $('askKind').className = 'askkind k-' + k;
    $('comment').placeholder = it ? it.ask : 'Annotazione libera…';
    renderQuick();
    if (it) $('comment').focus();
  }
  function quickTap(i, btn) {
    var it = QFLAT[i]; if (!it) return;
    if (it.ask) { setAsk(qMode === i ? null : i); return; }
    logAdd(it.t, it.k, it.tag).then(function (ok) {
      if (!ok) return;
      qCount[i] = (qCount[i] || 0) + 1; renderQuick();
      var b = $('ivGrid').querySelector('button[data-q="' + i + '"]');
      if (b) { b.classList.add('done'); setTimeout(function () { b.classList.remove('done'); }, 900); }
      msg('Registrato: ' + it.t);
    });
  }
  function askSubmit() {
    var t = $('comment').value.trim();
    var it = qMode === null ? null : QFLAT[qMode];
    if (!t) { msg(it && it.k !== 'note' ? 'Scrivi il testo prima di registrare' : ''); $('comment').focus(); return; }
    var i = qMode;
    logAdd(t, it ? it.k : 'note', it ? it.tag : undefined).then(function (ok) {
      if (!ok) return;
      $('comment').value = '';
      if (i !== null) qCount[i] = (qCount[i] || 0) + 1;
      setAsk(null);
      msg('Registrato' + (it ? ': ' + (KIND[it.k] || KIND.note)[1].toLowerCase() : ''));
    });
  }
  function downloadLog() {          // testo completo preparato dal monitor
    var opt = { headers: { 'X-SimulaFranz-Token': token, 'X-SimulaFranz-Client': clientId,
      'X-SimulaFranz-Client-Name': encodeURIComponent(clientName), 'X-SimulaFranz-Client-Kind': 'web' }, cache: 'no-store' };
    var sid = !$('debrief').hidden && dbSess !== null ? dbSess : logSess;      // dal debriefing: la sessione che si sta guardando
    fetch('/api/v1/log?format=text' + (sid !== null ? '&session=' + sid : ''), opt).then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.text(); }).then(function (txt) {
      var a = document.createElement('a');
      a.href = URL.createObjectURL(new Blob([txt], { type: 'text/plain;charset=utf-8' }));
      a.download = 'registro_similfranz_' + new Date().toISOString().slice(0, 16).replace(/[T:]/g, '-') + '.txt';
      document.body.appendChild(a); a.click();
      setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 500);
    }).catch(function () { msg('Registro non scaricato: il monitor non risponde'); });
  }

  // ---------- piano di debriefing: riepilogo + tutta la storia dello scenario ----------
  // "Punti chiave" (vista di partenza): ciò che serve per discutere — fasi, arresto e ROSC, azioni osservate, scariche,
  // farmaci, punti segnati. Il resto (ogni parametro ritoccato, sonde, timer) sta negli altri filtri e in "Tutto".
  var DBF = [['key', 'Punti chiave', 'KEY'], ['part', 'Partecipanti', ['monitor', 'electric', 'action']], ['el', 'Terapia elettrica', ['electric']],
             ['drug', 'Farmaci', ['drug']], ['istr', 'Istruttore', ['patient', 'phase', 'timer']], ['deb', 'Debriefing', ['plus', 'minus', 'note']],
             ['all', 'Tutto', null]];
  var KEYK = ['phase', 'action', 'drug', 'plus', 'minus', 'note'], KEYT = ['arrest', 'rosc', 'shock', 'monitor_on'];
  function dbMatch(f, e) {
    if (!f[2]) return true;
    if (f[2] === 'KEY') return KEYK.indexOf(e.k) >= 0 || (e.tag && KEYT.indexOf(e.tag) >= 0);
    return f[2].indexOf(e.k) >= 0;
  }
  var MESI = ['gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic'];
  function sessLabel(m) {
    var d = new Date((m.w || 0) * 1000);
    return (m.current ? 'In corso · ' : '') + d.getDate() + ' ' + MESI[d.getMonth()] + ' ' + ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2) +
           ' · ' + (m.title || 'Sessione') + ' · ' + fmtMMSS(m.duration_s) + ' · ' + (m.entries || 0) + ' voci';
  }
  // una sessione precedente: si legge tutta (a blocchi) e si mostra in sola lettura
  function loadPast(sid) {
    var all = [];
    function step(since) {
      api('GET', '/api/v1/log?session=' + sid + '&since=' + since).then(function (j) {
        if (dbSess !== sid) return;
        if (!j || !j.ok) { $('dbErr').textContent = 'Sessione non letta: ' + ((j && j.error) || 'il monitor non risponde'); return; }
        all = all.concat(j.log || []);
        if (j.sessions) logSessions = j.sessions;
        if (j.more) { step(j.next); return; }
        dbPast = { entries: all, summary: j.summary || {} }; renderDebrief();
      }).catch(function () { if (dbSess === sid) $('dbErr').textContent = 'Sessione non letta: il monitor non risponde'; });
    }
    step(0);
  }
  function showSession(sid) {       // null = quella in corso (dal vivo)
    dbSess = sid; dbPast = null; $('dbErr').textContent = '';
    if (sid !== null) loadPast(sid);
    renderDebrief();
  }
  var dbClearArm = 0;
  function openDebrief() { $('debrief').hidden = false; $('dbErr').textContent = ''; dbSess = null; dbPast = null; dbSessSig = ''; renderDebrief(); loadLog(); $('dbClose').focus(); }
  function closeDebrief() { $('debrief').hidden = true; }
  function renderDebrief() {
    var box = $('debrief'); if (!box || box.hidden) return;
    // elenco delle sessioni (più recenti in alto; le sessioni vuote non in corso non si mostrano)
    var list = logSessions.filter(function (m) { return m.current || m.entries > 0; }).slice().reverse();
    if (dbSess !== null && !list.some(function (m) { return m.id === dbSess && !m.current; })) { dbSess = null; dbPast = null; }
    var sig = list.map(function (m) { return m.id + '|' + sessLabel(m); }).join('\n') + '#' + dbSess;
    if (sig !== dbSessSig && document.activeElement !== $('dbSess')) {      // non si ricostruisce il menu mentre è aperto
      dbSessSig = sig;
      $('dbSess').innerHTML = list.map(function (m) {
        var sel = m.current ? dbSess === null : dbSess === m.id;
        return '<option value="' + (m.current ? '' : m.id) + '"' + (sel ? ' selected' : '') + '>' + esc(sessLabel(m)) + '</option>';
      }).join('') || '<option value="">In corso</option>';
    }
    var past = dbSess !== null, ENT = past ? (dbPast ? dbPast.entries : []) : LOGE;
    $('dbPastNote').hidden = !past;
    var sm = (past ? (dbPast ? dbPast.summary : {}) : logSum) || {}, tiles = [];
    function tile(lab, val, sub, cls) { tiles.push('<div class="dbtile' + (cls ? ' ' + cls : '') + '"><span>' + esc(lab) + '</span><b>' + esc(val) + '</b>' + (sub ? '<small>' + esc(sub) + '</small>' : '') + '</div>'); }
    tile('Durata', fmtMMSS(sm.duration_s), (sm.entries || 0) + ' voci nel registro');
    if (sm.arrest_at_s !== undefined) {
      tile('Arresto cardiaco', fmtMMSS(sm.arrest_at_s), 'tempo di scenario', 'arr');
      [['to_recognition_s', 'Riconoscimento'], ['to_help_s', 'Chiamata di aiuto'], ['to_cpr_s', 'Prime compressioni'],
       ['to_first_shock_s', 'Prima scarica'], ['to_rosc_s', 'ROSC']].forEach(function (m) {
        tile(m[1], sm[m[0]] !== undefined ? fmtDur(sm[m[0]]) : '—', sm[m[0]] !== undefined ? "dall'arresto" : 'non registrato', sm[m[0]] !== undefined ? '' : 'miss');
      });
    }
    var sh = sm.shocks || [], dr = sm.drugs || [];
    tile('Scariche', String(sh.length), sh.length ? sh.map(function (x) { return x.energy_j + ' J a ' + fmtMMSS(x.t); }).join(' · ') : 'nessuna');
    tile('Farmaci', String(dr.length), dr.length ? dr.map(function (x) { return x.text + ' a ' + fmtMMSS(x.t); }).join(' · ') : 'nessuno');
    tile('Punti di forza', String(sm.plus || 0), '', 'plus');
    tile('Da discutere', String(sm.minus || 0), '', 'minus');
    $('dbTiles').innerHTML = tiles.join('');
    var f = DBF.filter(function (x) { return x[0] === dbFilter; })[0] || DBF[0];
    $('dbFilters').innerHTML = DBF.map(function (x) {
      var n = ENT.filter(function (e) { return dbMatch(x, e); }).length;
      return '<button data-f="' + x[0] + '"' + (x[0] === f[0] ? ' class="active" aria-pressed="true"' : ' aria-pressed="false"') + '>' + x[1] + ' <small>' + n + '</small></button>';
    }).join('');
    var rows = ENT.filter(function (e) { return dbMatch(f, e); });
    $('dbList').innerHTML = rows.map(function (e) { return logLine(e, true); }).join('') ||
      '<li class="empty"><span>' + (past && !dbPast ? 'Lettura della sessione…' : 'Nessuna voce in questa vista.') + '</span></li>';
  }
  function initLog() {
    renderQuick(); renderLog(); setAsk(null);
    $('ivGrid').addEventListener('click', function (e) {
      var b = e.target.closest('button[data-q]'); if (b) quickTap(parseInt(b.dataset.q, 10), b);
    });
    $('commentAdd').onclick = askSubmit;
    $('comment').addEventListener('keydown', function (e) {
      if (e.key === 'Enter') askSubmit();
      else if (e.key === 'Escape' && qMode !== null) { e.stopPropagation(); setAsk(null); }
    });
    $('logSave').onclick = downloadLog;
    $('dbSave').onclick = downloadLog;
    $('logDebrief').onclick = openDebrief;
    $('dbClose').onclick = closeDebrief;
    $('dbFilters').addEventListener('click', function (e) {
      var b = e.target.closest('button[data-f]'); if (!b) return;
      dbFilter = b.dataset.f; renderDebrief();
    });
    $('dbSess').onchange = function () { var v = $('dbSess').value; showSession(v === '' ? null : parseInt(v, 10)); };
    $('dbNew').onclick = function () {                 // chiude la sessione in corso e ne apre una nuova (quella chiusa resta nell'elenco)
      api('POST', '/api/v1/log', { action: 'new_session' }).then(function (j) {
        if (j && j.controller) showControl(j.controller);
        if (j && j._status === 423) { $('dbErr').textContent = 'Sessione non aperta: il monitor è comandato da un altro controller. Prendi il controllo e riprova.'; return; }
        if (!j || !j.ok) { $('dbErr').textContent = 'Sessione non aperta: ' + ((j && j.error) || 'il monitor non risponde'); return; }
        $('dbErr').textContent = ''; dbSess = null; dbPast = null; qCount = {}; renderQuick(); LOGE = []; logNext = 0; takeLog(j, true);
      }).catch(function () { $('dbErr').textContent = 'Sessione non aperta: il monitor non risponde'; });
    };
    $('dbClear').onclick = function () {               // doppio tocco: svuota il registro sul monitor (tutte le sessioni)
      var b = $('dbClear');
      if (dbClearArm && Date.now() - dbClearArm < 4000) {
        dbClearArm = 0; b.textContent = 'Elimina tutte le sessioni'; b.classList.remove('armed');
        api('POST', '/api/v1/log', { action: 'clear' }).then(function (j) {
          if (j && j.controller) showControl(j.controller);
          if (j && j._status === 423) { $('dbErr').textContent = 'Registro non svuotato: il monitor è comandato da un altro controller. Prendi il controllo e riprova.'; return; }
          if (!j || !j.ok) { $('dbErr').textContent = 'Registro non svuotato: ' + ((j && j.error) || 'il monitor non risponde'); return; }
          $('dbErr').textContent = ''; dbSess = null; dbPast = null; qCount = {}; renderQuick(); LOGE = []; logNext = 0; takeLog(j, true);
        });
        return;
      }
      dbClearArm = Date.now(); b.textContent = 'Tocca di nuovo: elimina tutto'; b.classList.add('armed');
      setTimeout(function () { if (dbClearArm) { dbClearArm = 0; b.textContent = 'Elimina tutte le sessioni'; b.classList.remove('armed'); } }, 4000);
    };
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && !$('debrief').hidden) closeDebrief(); });
  }

  // ---------- stati del paziente (pacchetti one-tap) ----------
  var PRESET_STATES = [
    { n: 'Sano',                  d: 10, r: 'sinus',             p: { heart_rate_bpm: 80,  systolic_mmhg: 120, diastolic_mmhg: 80, spo2_percent: 98, respiratory_rate_rpm: 14, etco2_mmhg: 38 }, now: { crt_s: 2 } },
    { n: 'Ipoteso',               d: 30, r: 'sinus',             p: { heart_rate_bpm: 105, systolic_mmhg: 90,  diastolic_mmhg: 55, spo2_percent: 95, respiratory_rate_rpm: 20, etco2_mmhg: 32 }, now: { crt_s: 3 } },
    { n: 'Shock',                 d: 60, r: 'sinus_tachycardia', p: { heart_rate_bpm: 135, systolic_mmhg: 75,  diastolic_mmhg: 45, spo2_percent: 90, respiratory_rate_rpm: 28, etco2_mmhg: 25 }, now: { crt_s: 5 } },
    { n: 'Insuff. respiratoria',  d: 60, r: 'sinus_tachycardia', p: { heart_rate_bpm: 120, systolic_mmhg: 135, diastolic_mmhg: 85, spo2_percent: 82, respiratory_rate_rpm: 32, etco2_mmhg: 55 } },
    { n: 'Bradicardia instabile', d: 30, r: 'sinus_bradycardia', p: { heart_rate_bpm: 38,  systolic_mmhg: 80,  diastolic_mmhg: 50, spo2_percent: 91, respiratory_rate_rpm: 10, etco2_mmhg: 30 }, now: { crt_s: 4 } },
    { n: 'TV con polso',          d: 10, r: 'vt_pulse',          p: { heart_rate_bpm: 180, systolic_mmhg: 85,  diastolic_mmhg: 55, spo2_percent: 92, respiratory_rate_rpm: 22 } },
    { n: 'Arresto in FV',         d: 0,  r: 'vf',                p: {} },
    { n: 'Post-ROSC',             d: 30, r: 'sinus_tachycardia', p: { heart_rate_bpm: 110, systolic_mmhg: 95,  diastolic_mmhg: 60, spo2_percent: 94, respiratory_rate_rpm: 12, etco2_mmhg: 40 }, now: { crt_s: 3 } }
  ];
  var customStates = [];
  try { customStates = JSON.parse(localStorage.getItem('sf_states') || '[]'); } catch (e) {}
  var lastState = null;
  try { lastState = JSON.parse(sessionStorage.getItem('sf_last_state') || 'null'); } catch (e) {}
  var selState = null, savingState = false;          // selState: indice nello elenco completo
  function allStates() { return PRESET_STATES.concat(customStates); }
  function describeState(st) {
    var parts = [];
    if (st.r) parts.push(RHYTHMS[st.r] || st.r);
    Object.keys(st.p || {}).forEach(function (k) { parts.push(PNAME[k] + ' → ' + st.p[k]); });
    Object.keys(st.now || {}).forEach(function (k) { parts.push(P[k].l + ' → ' + st.now[k]); });
    return parts.join(' · ') || '—';
  }
  function renderStates() {
    var sts = allStates();
    $('stateChips').innerHTML = sts.map(function (st, i) {
      var isLast = lastState && lastState.n === st.n;
      return '<button class="stchip' + (isLast ? ' last' : '') + (i === selState ? ' open' : '') + (i >= PRESET_STATES.length ? ' custom' : '') + '" data-i="' + i + '"' +
             ' title="' + esc(describeState(st)) + '">' + (isLast ? '<u>▸</u>' : '') + esc(st.n) +
             '<small>' + (st.d > 0 ? st.d + ' s' : 'subito') + '</small></button>';
    }).join('');
    var exp = $('stateExp');
    if (savingState) return;                         // il pannello sta mostrando il salvataggio
    if (selState === null || !sts[selState]) { exp.hidden = true; exp.innerHTML = ''; return; }
    var st = sts[selState];
    exp.hidden = false;
    exp.innerHTML = '<div class="sxhead"><b>' + esc(st.n) + '</b><span>' + esc(describeState(st)) + '</span></div>' +
      '<div class="sxrow"><span class="tlab">Transizione</span><span class="seg" id="sxDur">' +
      [0, 10, 30, 60, 120].map(function (t) { return '<button data-t="' + t + '"' + (t === st.d ? ' class="active"' : '') + '>' + (t ? (t === 120 ? '2 min' : t + ' s') : 'subito') + '</button>'; }).join('') +
      '</span><span class="spacer"></span>' +
      (selState >= PRESET_STATES.length ? '<button class="ghost small danger" id="sxDel">Elimina</button>' : '') +
      '<button class="ghost small" id="sxClose">Chiudi</button>' +
      '<button class="primary" id="sxGo">Attiva lo stato</button></div>';
    var dur = st.d;
    all('#sxDur button').forEach(function (b) {
      b.onclick = function () { dur = parseInt(b.dataset.t, 10); all('#sxDur button').forEach(function (x) { x.className = x === b ? 'active' : ''; }); };
    });
    $('sxClose').onclick = function () { selState = null; renderStates(); };
    if ($('sxDel')) $('sxDel').onclick = function () {
      customStates.splice(selState - PRESET_STATES.length, 1);
      localStorage.setItem('sf_states', JSON.stringify(customStates));
      selState = null; renderStates();
    };
    $('sxGo').onclick = function () { activateState(st, dur); };
  }
  function activateState(st, dur) {
    var hasTr = (st.p && Object.keys(st.p).length > 0) || st.r;
    if (hasTr) {
      var val = { params: st.p || {}, duration_s: dur };
      if (st.r) val.rhythm = st.r;
      command('transition', val);
    }
    Object.keys(st.now || {}).forEach(function (k) { command(P[k].now, st.now[k]); });
    lastState = { n: st.n, scen: state && state.scenario_time_s !== undefined ? state.scenario_time_s : null, w: Date.now() };
    try { sessionStorage.setItem('sf_last_state', JSON.stringify(lastState)); } catch (e) {}
    logAdd('Stato «' + st.n + '» attivato · ' + (dur > 0 ? dur + ' s' : 'subito'), 'phase');
    msg('Stato «' + st.n + '» attivato');
    selState = null; clearPending(); renderStates();
  }
  function saveStateUI() {                           // fotografa i valori veri correnti in un nuovo stato
    if (!state) return;
    savingState = true; selState = null;
    var exp = $('stateExp'); exp.hidden = false;
    exp.innerHTML = '<div class="sxrow"><span class="tlab">Nome del nuovo stato</span>' +
      '<input type="text" id="sxName" maxlength="28" placeholder="es. Dopo il carico di fluidi">' +
      '<span class="spacer"></span><button class="ghost small" id="sxNCancel">Annulla</button>' +
      '<button class="primary" id="sxNSave">Salva</button></div>' +
      '<p class="hint">Verranno salvati: ' + esc(describeState(snapState('…'))) + '</p>';
    $('sxName').focus();
    var close = function () { savingState = false; renderStates(); };
    $('sxNCancel').onclick = close;
    var save = function () {
      var n = $('sxName').value.trim(); if (!n) { $('sxName').focus(); return; }
      customStates.push(snapState(n));
      try { localStorage.setItem('sf_states', JSON.stringify(customStates)); } catch (e) {}
      close();
    };
    $('sxNSave').onclick = save;
    $('sxName').addEventListener('keydown', function (e) { if (e.key === 'Enter') save(); });
  }
  function snapState(n) {
    var s = state;
    return { n: n, d: 30, r: s.rhythm,
      p: { heart_rate_bpm: s.heart_rate_bpm, systolic_mmhg: s.systolic_mmhg, diastolic_mmhg: s.diastolic_mmhg,
           spo2_percent: s.spo2_percent, respiratory_rate_rpm: s.respiratory_rate_rpm, etco2_mmhg: s.etco2_mmhg },
      now: { temperature_c: Number(s.temperature_c), crt_s: s.crt_s } };
  }


  // =====================================================================
  // SCENARI A FASI (salvati sul monitor: li vedono anche gli altri controller)
  // Uno scenario = fasi in ordine; ogni fase = blocco di parametri + tempo di transizione + nota.
  // Le fasi NON avanzano da sole: decide l'istruttore. I controlli manuali restano attivi in parallelo.
  // =====================================================================
  var scenarios = null, scRun = { active: false }, scSel = null, scJump = null, scStopArm = 0, scBusy = false, scSig = '';
  var railMode = 'states';
  try { railMode = sessionStorage.getItem('sf_rail') === 'scen' ? 'scen' : 'states'; } catch (e) {}
  var SC_KEYS = [['heart_rate_bpm', 'FC', 'bpm', 0, 300], ['systolic_mmhg', 'PA sist.', 'mmHg', 0, 300], ['diastolic_mmhg', 'PA diast.', 'mmHg', 0, 200],
                 ['spo2_percent', 'SpO₂', '%', 0, 100], ['respiratory_rate_rpm', 'FR', 'atti/min', 0, 60], ['etco2_mmhg', 'EtCO₂', 'mmHg', 0, 150]];
  var SC_MAXPH = 24;

  function setRail(m) {
    railMode = m === 'scen' ? 'scen' : 'states';
    try { sessionStorage.setItem('sf_rail', railMode); } catch (e) {}
    all('#railSw button').forEach(function (b) {
      var onb = b.dataset.v === railMode; b.className = onb ? 'active' : ''; b.setAttribute('aria-selected', onb ? 'true' : 'false');
    });
    $('railStates').hidden = railMode !== 'states';
    $('railScen').hidden = railMode !== 'scen';
    if (railMode === 'scen') { if (scenarios === null) loadScenarios(); scSig = ''; renderScen(); }
  }
  function scenById(id) { return (scenarios || []).filter(function (s) { return s.id === id; })[0] || null; }
  function durTxt(t) { t = +t || 0; return !t ? 'subito' : (t % 60 === 0 ? (t / 60) + ' min' : t + ' s'); }
  function describePhase(ph) {
    var parts = [];
    if (ph.rhythm) parts.push(RHYTHMS[ph.rhythm] || ph.rhythm);
    var p = ph.params || {};
    if (p.heart_rate_bpm !== undefined) parts.push('FC ' + p.heart_rate_bpm);
    if (p.systolic_mmhg !== undefined || p.diastolic_mmhg !== undefined)
      parts.push('PA ' + (p.systolic_mmhg !== undefined ? p.systolic_mmhg : '·') + '/' + (p.diastolic_mmhg !== undefined ? p.diastolic_mmhg : '·'));
    if (p.spo2_percent !== undefined) parts.push('SpO₂ ' + p.spo2_percent);
    if (p.respiratory_rate_rpm !== undefined) parts.push('FR ' + p.respiratory_rate_rpm);
    if (p.etco2_mmhg !== undefined) parts.push('EtCO₂ ' + p.etco2_mmhg);
    if (ph.temperature_c !== undefined) parts.push('Temp ' + Number(ph.temperature_c).toFixed(1));
    if (ph.crt_s !== undefined) parts.push('Refill ' + ph.crt_s + ' s');
    return parts.join(' · ') || '—';
  }
  function loadScenarios() {
    return api('GET', '/api/v1/scenarios').then(function (j) {
      if (!j || !j.ok) { if (scenarios === null) scenarios = []; scSig = ''; renderScen(); return; }
      scenarios = j.scenarios || [];
      if (j.scenario) onScenario(j.scenario);
      scSig = ''; renderScen();
    }).catch(function () {});
  }
  function setScenarios(list) { scenarios = list || []; scSig = ''; renderScen(); }
  // stato della conduzione, presente in ogni risposta del monitor
  function onScenario(r) {
    var prev = '';
    try { prev = sessionStorage.getItem('sf_sc_prev') || ''; } catch (e) {}
    var cur = r.active ? r.id + '#' + r.phase : '';
    if (cur !== prev) {
      try { sessionStorage.setItem('sf_sc_prev', cur); } catch (e) {}
      scJump = null;
      if (r.active && !scenById(r.id)) loadScenarios();       // avviato da un altro controller: serve l'elenco aggiornato
    }
    scRun = r;
    $('railSwDot').hidden = !r.active;
    renderScen();
  }
  function scPost(body) {
    if (scBusy) return Promise.resolve(null);
    scBusy = true; cmdSeq++;
    return api('POST', '/api/v1/scenarios', body).then(function (j) {
      scBusy = false;
      if (j && !j.ok && j._status !== 401 && j._status !== 423 && j._status !== 429) { msg('Scenario: ' + (j.error || 'errore')); return j; }
      handle(j); return j;
    }).catch(function () { scBusy = false; msg('Monitor non raggiungibile'); return null; });
  }
  function renderScen() {
    var box = $('railScen');
    if (!box || railMode !== 'scen') return;
    var run = scRun && scRun.active ? scRun : null, sc = run ? scenById(run.id) : null;
    var sig = [run ? run.id + '#' + run.phase + '#' + run.phases : '-', scSel, scJump, scenarios === null ? 'n' : scenarios.length, sc ? sc.phases.length : 0, scStopArm ? 1 : 0].join('|');
    if (sig === scSig) { var t = $('scT'); if (t && run) t.textContent = fmtMMSS(run.phase_time_s); return; }
    scSig = sig;
    var h = '';
    if (run) {
      h += '<div class="rhead"><h3>Scenario in corso</h3></div>' +
           '<div class="scname"><b>' + esc(run.name) + '</b><span>fase ' + (run.phase + 1) + ' di ' + run.phases + '</span></div>' +
           '<div class="statechips scphases">';
      var phs = sc ? sc.phases : [];
      for (var i = 0; i < run.phases; i++) {
        var ph = phs[i] || { name: i === run.phase ? run.phase_name : 'Fase ' + (i + 1) }, isCur = i === run.phase;
        h += '<button class="stchip scph' + (isCur ? ' last' : (i < run.phase ? ' done' : '')) + (i === scJump ? ' open' : '') + '" data-i="' + i + '"' +
             (isCur ? ' aria-current="step"' : '') + ' title="' + esc(describePhase(ph)) + '">' +
             '<em>' + (isCur ? '▸' : (i + 1)) + '</em><span>' + esc(ph.name) + (isCur ? '<i>in corso</i>' : '') + '</span>' +
             '<small' + (isCur ? ' id="scT"' : '') + '>' + (isCur ? fmtMMSS(run.phase_time_s) : durTxt(ph.duration_s)) + '</small></button>';
      }
      h += '</div>';
      if (scJump !== null && phs[scJump] && scJump !== run.phase) {
        h += '<div class="stateexp"><div class="sxhead"><b>' + (scJump + 1) + ' · ' + esc(phs[scJump].name) + '</b><span>' + esc(describePhase(phs[scJump])) +
             ' · transizione: ' + durTxt(phs[scJump].duration_s) + '</span>' + (phs[scJump].note ? '<span class="scnote">' + esc(phs[scJump].note) + '</span>' : '') + '</div>' +
             '<div class="sxrow"><button class="ghost small" id="scJumpNo">Annulla</button><button class="primary" id="scJumpGo">Vai a questa fase</button></div></div>';
      } else if (run.phase_note) {
        h += '<div class="scnotebox"><span class="tlab">Nota per l\'istruttore</span>' + esc(run.phase_note) + '</div>';
      }
      h += run.next_name ? '<button class="primary scnext" id="scNext"><small>Fase successiva</small>' + esc(run.next_name) + '</button>'
                         : '<p class="railhint sclast">Ultima fase: lo scenario resta qui finché non lo termini.</p>';
      h += '<div class="railfoot"><button id="scEditRun" class="ghost small wide">Modifica lo scenario</button>' +
           '<button id="scStop" class="ghost small wide danger' + (scStopArm ? ' armed' : '') + '">' + (scStopArm ? 'Tocca di nuovo: termina' : 'Termina scenario') + '</button></div>';
    } else {
      h += '<div class="rhead"><h3>Scenari</h3></div>' +
           '<p class="railhint">Fasi già pronte, che fai avanzare tu. Durante lo scenario i controlli manuali restano attivi.</p>';
      if (scenarios === null) h += '<p class="railhint">Lettura dal monitor…</p>';
      else if (!scenarios.length) h += '<p class="railhint">Nessuno scenario salvato sul monitor.</p>';
      else {
        h += '<div class="statechips">' + scenarios.map(function (s) {
          return '<button class="stchip scitem' + (s.id === scSel ? ' open' : '') + '" data-id="' + esc(s.id) + '"><span>' + esc(s.name) + '</span><small>' +
                 s.phases.length + (s.phases.length === 1 ? ' fase' : ' fasi') + '</small></button>';
        }).join('') + '</div>';
        var sel = scSel ? scenById(scSel) : null;
        if (sel) {
          h += '<div class="stateexp scprev"><div class="sxhead"><b>' + esc(sel.name) + '</b>' + (sel.notes ? '<span>' + esc(sel.notes) + '</span>' : '') + '</div>' +
               '<ol class="scplist">' + sel.phases.map(function (ph) {
                 return '<li><b>' + esc(ph.name) + '</b><span>' + esc(describePhase(ph)) + ' · ' + durTxt(ph.duration_s) + '</span></li>';
               }).join('') + '</ol>' +
               '<div class="sxrow"><button class="ghost small" id="scSelNo">Chiudi</button><button class="ghost small" id="scSelEdit">Modifica</button>' +
               '<button class="primary" id="scSelGo">Avvia lo scenario</button></div></div>';
        }
      }
      h += '<div class="railfoot"><button id="scNew" class="ghost small wide">+ Nuovo scenario</button></div>';
    }
    box.innerHTML = h;
    all('.scitem', box).forEach(function (b) { b.onclick = function () { scSel = scSel === b.dataset.id ? null : b.dataset.id; renderScen(); }; });
    all('.scph', box).forEach(function (b) {
      b.onclick = function () { var i = parseInt(b.dataset.i, 10); scJump = (i === scRun.phase || i === scJump) ? null : i; renderScen(); };
    });
    var bind = function (id, fn) { var el = $(id); if (el) el.onclick = fn; };
    bind('scSelNo', function () { scSel = null; renderScen(); });
    bind('scSelEdit', function () { openBuilder(scenById(scSel)); });
    bind('scSelGo', function () {
      var id = scSel; scSel = null;
      scPost({ action: 'start', id: id, phase: 0 }).then(function (j) { if (j && j.ok) { clearPending(); msg('Scenario avviato'); } });
    });
    bind('scNew', function () { openBuilder(null); });
    bind('scJumpNo', function () { scJump = null; renderScen(); });
    bind('scJumpGo', function () { var n = scJump; scPost({ action: 'goto', phase: n }).then(function (j) { if (j && j.ok) clearPending(); }); });
    bind('scNext', function () { scPost({ action: 'next' }).then(function (j) { if (j && j.ok) clearPending(); }); });
    bind('scEditRun', function () { var s = scenById(scRun.id); if (s) openBuilder(s); else loadScenarios(); });
    bind('scStop', function () {
      if (scStopArm && Date.now() - scStopArm < 4000) { scStopArm = 0; scPost({ action: 'stop' }); return; }
      scStopArm = Date.now(); renderScen();
      setTimeout(function () { if (scStopArm && Date.now() - scStopArm >= 3900) { scStopArm = 0; renderScen(); } }, 4000);
    });
  }

  // ---------- costruzione dello scenario ----------
  var bd = null, bdDirty = false, bdCloseArm = 0, bdDelArm = 0;
  function bdPhase(src) {                              // fase della bozza: i campi vuoti significano "non cambia"
    var ph = { name: '', note: '', duration_s: 0, rhythm: '', v: {}, temp: '', crt: '' };
    if (!src) return ph;
    ph.name = src.name || ''; ph.note = src.note || ''; ph.duration_s = +src.duration_s || 0; ph.rhythm = src.rhythm || '';
    SC_KEYS.forEach(function (k) { if (src.params && src.params[k[0]] !== undefined) ph.v[k[0]] = String(src.params[k[0]]); });
    if (src.temperature_c !== undefined) ph.temp = String(src.temperature_c);
    if (src.crt_s !== undefined) ph.crt = String(src.crt_s);
    return ph;
  }
  function openBuilder(sc) {
    bd = { id: sc ? sc.id : null, name: sc ? sc.name : '', notes: sc ? (sc.notes || '') : '', phases: sc ? sc.phases.map(bdPhase) : [bdPhase(null)] };
    bdDirty = false; bdCloseArm = 0; bdDelArm = 0;
    $('scbErr').textContent = '';
    $('scBuilder').hidden = false;
    renderBuilder();
    var n = $('scbName'); if (n && !sc) n.focus();
  }
  function closeBuilder() { $('scBuilder').hidden = true; bd = null; bdDirty = false; scSig = ''; renderScen(); }
  function bdErr(t) { $('scbErr').textContent = t || ''; }
  function renderBuilder() {
    if (!bd) return;
    $('scbTitle').textContent = bd.id ? 'Modifica scenario' : 'Nuovo scenario';
    $('scbDel').hidden = !bd.id; $('scbDup').hidden = !bd.id;
    $('scbDel').textContent = 'Elimina scenario'; $('scbDel').classList.remove('armed');
    $('scbClose').textContent = 'Chiudi';
    $('scbAdd').disabled = $('scbSnap').disabled = bd.phases.length >= SC_MAXPH;
    var DUR = [0, 10, 30, 60, 120];
    var h = '<div class="scbmeta"><label>Nome dello scenario<input type="text" id="scbName" maxlength="60" placeholder="es. Dolore toracico, arresto, ROSC" value="' + esc(bd.name) + '"></label>' +
            '<label>Paziente, contesto, obiettivi<textarea id="scbNotes" maxlength="600" rows="2" placeholder="Chi è il paziente, dove siamo, che cosa deve imparare il gruppo">' + esc(bd.notes) + '</textarea></label></div>' +
            '<p class="hint">Ogni fase è un quadro clinico: i campi vuoti non cambiano il paziente. Le fasi non avanzano da sole, le fai avanzare tu durante lo scenario. Massimo ' + SC_MAXPH + ' fasi.</p>';
    h += bd.phases.map(function (ph, i) {
      var custom = DUR.indexOf(ph.duration_s) < 0;
      return '<section class="scbph" data-i="' + i + '"><div class="scbphhead"><em>' + (i + 1) + '</em>' +
        '<input type="text" data-f="name" maxlength="40" placeholder="Nome della fase (es. Peggiora)" value="' + esc(ph.name) + '" aria-label="Nome della fase ' + (i + 1) + '">' +
        '<button class="ghost small" data-a="up" title="Sposta prima" aria-label="Sposta la fase prima"' + (i === 0 ? ' disabled' : '') + '>↑</button>' +
        '<button class="ghost small" data-a="down" title="Sposta dopo" aria-label="Sposta la fase dopo"' + (i === bd.phases.length - 1 ? ' disabled' : '') + '>↓</button>' +
        '<button class="ghost small" data-a="dup"' + (bd.phases.length >= SC_MAXPH ? ' disabled' : '') + '>Duplica</button>' +
        '<button class="ghost small danger" data-a="del"' + (bd.phases.length <= 1 ? ' disabled' : '') + '>Elimina</button></div>' +
        '<div class="scbgrid"><label class="wide2">Ritmo<select data-f="rhythm"><option value="">non cambia</option>' +
        Object.keys(RHYTHMS).map(function (r) { return '<option value="' + r + '"' + (r === ph.rhythm ? ' selected' : '') + '>' + RHYTHMS[r] + '</option>'; }).join('') + '</select></label>' +
        SC_KEYS.map(function (k) {
          return '<label>' + k[1] + ' <small>' + k[2] + '</small><input type="number" data-k="' + k[0] + '" min="' + k[3] + '" max="' + k[4] + '" step="1" placeholder="—" value="' + esc(ph.v[k[0]] || '') + '"></label>';
        }).join('') +
        '<label>Temp. <small>°C</small><input type="number" data-f="temp" min="25" max="45" step="0.1" placeholder="—" value="' + esc(ph.temp) + '"></label>' +
        '<label>Refill <small>s</small><input type="number" data-f="crt" min="0.5" max="10" step="0.5" placeholder="—" value="' + esc(ph.crt) + '"></label></div>' +
        '<div class="scbrow"><span class="tlab">Arriva a questi valori</span><span class="seg scbdur">' +
        DUR.map(function (t) { return '<button data-t="' + t + '"' + (t === ph.duration_s ? ' class="active"' : '') + '>' + (t ? (t === 120 ? '2 min' : (t === 60 ? '1 min' : t + ' s')) : 'Subito') + '</button>'; }).join('') +
        '</span><label class="custom">altro <input type="number" data-f="dur" min="1" max="3600" placeholder="s" value="' + (custom ? ph.duration_s : '') + '"> s</label></div>' +
        '<label class="scbnote">Nota per l\'istruttore: quando avanzare<input type="text" data-f="note" maxlength="200" placeholder="es. Avanzare quando hanno somministrato ossigeno" value="' + esc(ph.note) + '"></label></section>';
    }).join('');
    $('scbBody').innerHTML = h;
    $('scbName').oninput = function () { bd.name = this.value; bdDirty = true; };
    $('scbNotes').oninput = function () { bd.notes = this.value; bdDirty = true; };
    all('.scbph', $('scbBody')).forEach(function (sec) {
      var i = parseInt(sec.dataset.i, 10), ph = bd.phases[i];
      all('input, select', sec).forEach(function (el) {
        el.oninput = el.onchange = function () {
          bdDirty = true; bdErr('');
          if (el.dataset.k) ph.v[el.dataset.k] = el.value.trim();
          else if (el.dataset.f === 'dur') {
            var t = parseInt(el.value, 10);
            if (!isNaN(t)) { ph.duration_s = Math.max(0, Math.min(3600, t)); all('.scbdur button', sec).forEach(function (x) { x.className = ''; }); }
          } else ph[el.dataset.f] = el.dataset.f === 'rhythm' ? el.value : el.value;
        };
      });
      all('.scbdur button', sec).forEach(function (b) {
        b.onclick = function () {
          ph.duration_s = parseInt(b.dataset.t, 10); bdDirty = true;
          all('.scbdur button', sec).forEach(function (x) { x.className = x === b ? 'active' : ''; });
          sec.querySelector('input[data-f="dur"]').value = '';
        };
      });
      all('button[data-a]', sec).forEach(function (b) {
        b.onclick = function () {
          var a = b.dataset.a; bdDirty = true; bdErr('');
          if (a === 'up' && i > 0) { bd.phases.splice(i - 1, 0, bd.phases.splice(i, 1)[0]); }
          else if (a === 'down' && i < bd.phases.length - 1) { bd.phases.splice(i + 1, 0, bd.phases.splice(i, 1)[0]); }
          else if (a === 'dup' && bd.phases.length < SC_MAXPH) { bd.phases.splice(i + 1, 0, JSON.parse(JSON.stringify(ph))); }
          else if (a === 'del' && bd.phases.length > 1) { bd.phases.splice(i, 1); }
          renderBuilder();
        };
      });
    });
  }
  function bdAdd(fromState) {
    if (!bd || bd.phases.length >= SC_MAXPH) return;
    var ph = bdPhase(null);
    if (fromState) {
      if (!state) { bdErr('Valori del paziente non ancora letti dal monitor.'); return; }
      ph.rhythm = state.rhythm || '';
      SC_KEYS.forEach(function (k) { if (state[k[0]] !== undefined && state[k[0]] !== null) ph.v[k[0]] = String(state[k[0]]); });
      if (state.temperature_c !== undefined) ph.temp = String(Number(state.temperature_c).toFixed(1));
      if (state.crt_s !== undefined) ph.crt = String(state.crt_s);
      ph.duration_s = 30;
    }
    bd.phases.push(ph); bdDirty = true; bdErr('');
    renderBuilder();
    var secs = all('.scbph', $('scbBody')), last = secs[secs.length - 1];
    if (last) { last.scrollIntoView({ block: 'nearest' }); var inp = last.querySelector('input[data-f="name"]'); if (inp) inp.focus(); }
  }
  // dalla bozza al formato del monitor; ritorna null (con messaggio) se un campo non è un numero valido
  function bdBuild() {
    var name = bd.name.trim();
    if (!name) { bdErr('Dai un nome allo scenario.'); $('scbName').focus(); return null; }
    var out = { name: name, notes: bd.notes.trim(), phases: [] }, bad = null;
    if (bd.id) out.id = bd.id;
    bd.phases.forEach(function (ph, i) {
      if (bad) return;
      var o = { name: ph.name.trim() || ('Fase ' + (i + 1)), note: ph.note.trim(), duration_s: ph.duration_s || 0, params: {} };
      if (ph.rhythm) o.rhythm = ph.rhythm;
      SC_KEYS.forEach(function (k) {
        var raw = ph.v[k[0]]; if (raw === undefined || raw === '') return;
        var n = Number(raw);
        if (isNaN(n) || n < k[3] || n > k[4]) { bad = 'Fase ' + (i + 1) + ': ' + k[1] + ' deve essere fra ' + k[3] + ' e ' + k[4] + '.'; return; }
        o.params[k[0]] = Math.round(n);
      });
      if (ph.temp !== '') { var t = Number(ph.temp); if (isNaN(t) || t < 25 || t > 45) bad = bad || 'Fase ' + (i + 1) + ': la temperatura deve essere fra 25 e 45 °C.'; else o.temperature_c = t; }
      if (ph.crt !== '') { var c = Number(ph.crt); if (isNaN(c) || c < 0.5 || c > 10) bad = bad || 'Fase ' + (i + 1) + ': il refill deve essere fra 0,5 e 10 s.'; else o.crt_s = c; }
      if (!bad && o.params.systolic_mmhg !== undefined && o.params.diastolic_mmhg !== undefined && o.params.diastolic_mmhg >= o.params.systolic_mmhg)
        bad = 'Fase ' + (i + 1) + ': la diastolica deve essere più bassa della sistolica.';
      if (!bad && !o.rhythm && !Object.keys(o.params).length && o.temperature_c === undefined && o.crt_s === undefined)
        bad = 'Fase ' + (i + 1) + ' vuota: scegli un ritmo o almeno un parametro.';
      out.phases.push(o);
    });
    if (bad) { bdErr(bad); return null; }
    return out;
  }
  function bdServerError(j) {
    if (!j) return 'Monitor non raggiungibile: lo scenario non è stato salvato.';
    if (j._status === 423) { if (j.controller) showControl(j.controller); return 'Il monitor è comandato da un altro controller: prendi il controllo e salva di nuovo.'; }
    if (j._status === 401) return 'PIN non più valido: esci e rientra.';
    if (j._status === 413) return 'Scenario troppo lungo per il monitor: accorcia le note o togli qualche fase.';
    var e = String(j.error || 'errore sconosciuto');
    return 'Il monitor non ha accettato lo scenario. ' + e.replace(/^phase (\d+)/, 'Fase $1') + '.';
  }
  function bdSave() {
    var sc = bdBuild(); if (!sc) return;
    var body = { action: 'save', scenario: sc };
    if (unescape(encodeURIComponent(JSON.stringify(body))).length > 15000) { bdErr('Scenario troppo lungo per il monitor: accorcia le note o togli qualche fase.'); return; }
    $('scbSave').disabled = true; cmdSeq++;
    api('POST', '/api/v1/scenarios', body).then(function (j) {
      $('scbSave').disabled = false;
      if (!j || !j.ok) { bdErr(bdServerError(j)); return; }
      if (j.saved) scSel = j.saved.id;
      closeBuilder(); handle(j); msg('Scenario salvato sul monitor');
    }).catch(function () { $('scbSave').disabled = false; bdErr(bdServerError(null)); });
  }
  function initScen() {
    all('#railSw button').forEach(function (b) { b.onclick = function () { setRail(b.dataset.v); }; });
    $('scbAdd').onclick = function () { bdAdd(false); };
    $('scbSnap').onclick = function () { bdAdd(true); };
    $('scbSave').onclick = bdSave;
    $('scbClose').onclick = function () {
      if (!bdDirty || (bdCloseArm && Date.now() - bdCloseArm < 4000)) { closeBuilder(); return; }
      bdCloseArm = Date.now(); $('scbClose').textContent = 'Tocca di nuovo: chiudi senza salvare';
      setTimeout(function () { if (bd && bdCloseArm && Date.now() - bdCloseArm >= 3900) { bdCloseArm = 0; $('scbClose').textContent = 'Chiudi'; } }, 4000);
    };
    $('scbDup').onclick = function () {
      if (!bd) return;
      bd.id = null; bd.name = (bd.name.trim() + ' (copia)').slice(0, 60); bdDirty = true; bdErr('');
      renderBuilder(); $('scbName').focus();
    };
    $('scbDel').onclick = function () {
      if (!bd || !bd.id) return;
      if (bdDelArm && Date.now() - bdDelArm < 4000) {
        var id = bd.id, nm = bd.name; cmdSeq++;
        api('POST', '/api/v1/scenarios', { action: 'delete', id: id }).then(function (j) {
          if (!j || !j.ok) { bdErr(bdServerError(j).replace('non ha accettato lo scenario', 'non ha eliminato lo scenario').replace('salva di nuovo', 'riprova')); return; }
          if (scSel === id) scSel = null;
          closeBuilder(); handle(j); msg('Scenario eliminato');
        }).catch(function () { bdErr('Monitor non raggiungibile: lo scenario non è stato eliminato.'); });
        return;
      }
      bdDelArm = Date.now(); $('scbDel').textContent = 'Tocca di nuovo: elimina'; $('scbDel').classList.add('armed');
      setTimeout(function () { if (bd && bdDelArm && Date.now() - bdDelArm >= 3900) { bdDelArm = 0; $('scbDel').textContent = 'Elimina scenario'; $('scbDel').classList.remove('armed'); } }, 4000);
    };
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && bd && !bdDirty) closeBuilder(); });
    setRail(railMode);
  }

  // ---------- evidenza dei valori fuori range sulle tessere ----------
  function markTile(id, w) {
    var t = $(id); while (t && !t.classList.contains('tile')) t = t.parentElement;
    if (t) t.classList.toggle('warn', !!w);
  }
  function warnTiles(s) {
    var L = s.alarm_limits || {};
    markTile('v_rhythm', !s.pulse_present);
    markTile('v_hr', s.heart_rate_bpm < L.hr_low || s.heart_rate_bpm > L.hr_high);
    markTile('v_bp', s.systolic_mmhg < L.sys_low || s.systolic_mmhg > L.sys_high);
    markTile('v_spo2', s.spo2_percent < L.spo2_low);
    markTile('v_co2', s.respiratory_rate_rpm < L.rr_low || s.respiratory_rate_rpm > L.rr_high ||
                      s.etco2_mmhg < L.etco2_low || s.etco2_mmhg > L.etco2_high);
    markTile('v_temp', Number(s.temperature_c) < 35 || Number(s.temperature_c) > 38.5 || s.crt_s > 3);
  }
  function renderClock(s) {
    if (s.scenario_time_s !== undefined)
      $('clock').textContent = fmtMMSS(s.scenario_time_s) + (s.simulation_running ? '' : ' · PAUSA');
    var it = $('inState');
    if (lastState) {
      var el = lastState.scen !== null && s.scenario_time_s !== undefined
        ? s.scenario_time_s - lastState.scen : (Date.now() - lastState.w) / 1000;
      it.textContent = 'in «' + lastState.n + '» da ' + fmtMMSS(el);
    } else it.textContent = '';
  }

  // ---------- schede e navigazione ----------
  function flashCard(id) {
    if (!id) return;
    var el = $(id); if (!el) return;
    el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    el.classList.remove('flash'); void el.offsetWidth; el.classList.add('flash');
  }
  function select(k) {
    selSensor = k; devSig = '';
    showCard(SENS[k].card || 'panel_defib', true);
    flashCard(SENS[k].card || 'panel_defib');
    if (state) render(state);
  }
  function showCard(id, keepSensor) {
    card = id; sessionStorage.setItem('sf_card', id);
    if (!keepSensor) { selSensor = id === 'panel_defib' ? 'pads' : null; devSig = ''; }
    all('.pcard').forEach(function (p) { p.classList.toggle('show', p.id === id); });
    all('#pnav button').forEach(function (b) { b.className = b.dataset.card === id ? 'active' : ''; });
    if (state) renderFigure(state);
    if (id === 'panel_monitor') checkUpdates(false);
  }

  // ---------- aggiornamento delle app (monitor, controller iPad, iPod Pocket) ----------
  // Gli iPad/iPod non parlano più con GitHub (iOS troppo vecchio); il browser sì. La pagina chiede al monitor che
  // versioni ha, cerca l'ultima Release del repository da cui il monitor è stato compilato, scarica i pacchetti nuovi
  // (copia sulle Pages, leggibile dal browser) e li passa al monitor. Prima quelli dei controller (restano sul monitor),
  // per ultimo il monitor stesso, che si reinstalla e si riapre. Versione privata (senza repository): solo file a mano.
  var UPD_NAMES = { 'it.simulafranz.monitor': 'Monitor (questo iPad)', 'it.simulafranz.controller': 'Controller iPad', 'it.simulafranz.pocket': 'Pocket (iPod)' };
  var upd = { checked: 0, todo: [], busy: false };
  function vcmp(a, b) { a = String(a || 0).split('.'); b = String(b || 0).split('.'); for (var i = 0; i < Math.max(a.length, b.length); i++) { var x = parseInt(a[i] || 0, 10), y = parseInt(b[i] || 0, 10); if (x !== y) return x < y ? -1 : 1; } return 0; }
  function updText(t) { $('updText').innerHTML = t; }
  function fetchT(url, opt, ms) {          // fetch con limite di tempo (mentre il monitor si riavvia una connessione può restare appesa)
    var ctl = window.AbortController ? new AbortController() : null; opt = opt || {}; if (ctl) opt.signal = ctl.signal;
    var t = setTimeout(function () { if (ctl) ctl.abort(); }, ms || 8000);
    return fetch(url, opt).then(function (r) { clearTimeout(t); return r; });
  }
  function upHeaders() { return { 'X-SimulaFranz-Token': token, 'X-SimulaFranz-Client': clientId, 'Content-Type': 'application/octet-stream' }; }
  function checkUpdates(force) {
    if (upd.busy || (!force && Date.now() - upd.checked < 15 * 60 * 1000)) return;
    upd.checked = Date.now(); updText('Controllo degli aggiornamenti…');
    api('GET', '/api/v1/update').then(function (me) {
      if (!me.ok) { updText('Il monitor non risponde.'); return; }
      var have = { 'it.simulafranz.monitor': me.version }; Object.keys(me.packages || {}).forEach(function (k) { have[k] = me.packages[k]; });
      if (!me.repo) { updText('Questo monitor (' + me.version + ') non conosce un repository delle versioni: si aggiorna con un pacchetto scelto a mano.'); return; }
      var owner = me.repo.split('/')[0], name = me.repo.split('/')[1];
      fetchT('https://api.github.com/repos/' + me.repo + '/releases/latest', { cache: 'no-store' }).then(function (r) { return r.ok ? r.json() : null; }).then(function (rel) {
        if (!rel) { updText('Nessuna versione pubblicata su ' + me.repo + '.'); return; }
        upd.todo = []; var rows = [], priv = me.edition === 'privata', monNew = null;
        (rel.assets || []).forEach(function (a) {
          var m = /^(it\.simulafranz\.[a-z]+)_([0-9.]+)_iphoneos-arm\.deb$/.exec(a.name); if (!m || !UPD_NAMES[m[1]]) return;
          var newer = vcmp(m[2], have[m[1]]) > 0;
          if (newer && priv && m[1] === 'it.simulafranz.monitor') {     // edizione privata: il pacchetto pubblico toglierebbe i layout aggiuntivi
            monNew = m[2];
            rows.push('<li class="new"><span>' + UPD_NAMES[m[1]] + '</span><span>ha ' + have[m[1]] + ' → <b>' + m[2] + '</b> · edizione privata</span></li>');
            return;
          }
          if (newer) upd.todo.push({ pkg: m[1], ver: m[2], url: 'https://' + owner.toLowerCase() + '.github.io/' + name + '/aggiornamenti/' + a.name, manual: a.browser_download_url });
          rows.push('<li class="' + (newer ? 'new' : '') + '"><span>' + UPD_NAMES[m[1]] + '</span><span>' + (have[m[1]] ? 'ha ' + have[m[1]] : 'non ancora sul monitor') + (newer ? ' → <b>' + m[2] + '</b>' : ' · aggiornato') + '</span></li>');
        });
        upd.todo.sort(function (a, b) { return a.pkg === 'it.simulafranz.monitor' ? 1 : b.pkg === 'it.simulafranz.monitor' ? -1 : 0; });   // il monitor per ultimo
        $('updList').innerHTML = rows.join(''); $('updList').hidden = !rows.length;
        $('updGo').hidden = !upd.todo.length || !me.installer;
        $('updGo').textContent = upd.todo.length === 1 ? 'Aggiorna (' + UPD_NAMES[upd.todo[0].pkg] + ')' : 'Aggiorna tutto (' + upd.todo.length + ')';
        var privNote = monNew ? ' <b>Monitor in edizione privata</b>: la ' + monNew + ' pubblica gli toglierebbe i layout aggiuntivi, quindi non la installo. '
          + 'Aggiornalo con il pacchetto privato della stessa versione (caricalo qui sotto).' : '';
        updText(upd.todo.length ? 'È disponibile la versione <b>' + rel.tag_name.replace(/^v/, '') + '</b> pubblicata su ' + me.repo + '.'
          + (me.installer ? '' : ' Questo monitor non sa ancora aggiornarsi da solo: aggiornalo una volta dal computer (aggiorna.sh).') + privNote
          : (monNew ? 'Controller e Pocket aggiornati alla versione ' + rel.tag_name.replace(/^v/, '') + '.' + privNote
                    : 'Tutto aggiornato alla versione ' + rel.tag_name.replace(/^v/, '') + '.'));
      }).catch(function () { updText('Per cercare aggiornamenti questo computer deve avere internet.'); });
    });
  }
  function sendPackage(buf) {
    return fetchT('/api/v1/update', { method: 'POST', headers: upHeaders(), body: buf }, 90000)
      .then(function (r) { return r.json().then(function (j) { j._status = r.status; return j; }); });
  }
  function waitMonitor(ver) {
    var t0 = Date.now();
    (function again() {
      fetchT('/api/v1/health?t=' + Date.now(), { cache: 'no-store' }, 4000).then(function (r) { return r.json(); }).then(function (h) {
        if (h.version === ver) { upd.busy = false; updText('Fatto: il monitor ora ha la versione <b>' + ver + '</b>.'); upd.checked = 0; checkUpdates(true); }
        else if (Date.now() - t0 < 120000) setTimeout(again, 2000); else { upd.busy = false; updText('Il monitor non conferma la nuova versione: riapri l\'app sull\'iPad.'); }
      }).catch(function () { if (Date.now() - t0 < 120000) setTimeout(again, 2000); else { upd.busy = false; updText('Il monitor non risponde: riapri l\'app sull\'iPad.'); } });
    })();
  }
  $('updGo').onclick = function () {
    if (upd.busy || !upd.todo.length) return;
    upd.busy = true; $('updGo').hidden = true;
    var list = upd.todo.slice();
    (function next() {
      var it = list.shift();
      if (!it) { upd.busy = false; updText('Fatto. Controller e iPod vedono l\'aggiornamento al prossimo collegamento.'); upd.checked = 0; checkUpdates(true); return; }
      updText('Scarico ' + UPD_NAMES[it.pkg] + ' ' + it.ver + ' da GitHub…');
      fetchT(it.url, { cache: 'no-store' }, 60000).then(function (r) { if (!r.ok) throw 0; return r.arrayBuffer(); }).then(function (buf) {
        updText('Passo ' + UPD_NAMES[it.pkg] + ' ' + it.ver + ' al monitor…');
        return sendPackage(buf).then(function (j) {
          if (j._status === 202) { updText('Il monitor si sta aggiornando alla ' + j.to + ': si chiude e si riapre da solo…'); waitMonitor(j.to); return; }
          if (!j.ok) throw j.error || ('errore ' + j._status);
          next();
        });
      }).catch(function (e) {
        upd.busy = false; $('updGo').hidden = false;
        updText('<span style="color:#ff8a8a">' + UPD_NAMES[it.pkg] + ': ' + (typeof e === 'string' ? e : 'download non riuscito') + '.</span> <a href="' + it.manual + '" target="_blank" rel="noopener">Scarica il pacchetto</a> e caricalo qui sotto.');
      });
    })();
  };
  $('updFile').onchange = function () {
    var f = this.files && this.files[0]; if (!f) return; this.value = '';
    var rd = new FileReader();
    rd.onload = function () {
      upd.busy = true; updText('Passo il pacchetto al monitor…');
      sendPackage(rd.result).then(function (j) {
        if (j._status === 202) { updText('Il monitor si sta aggiornando alla ' + j.to + '…'); waitMonitor(j.to); return; }
        upd.busy = false;
        updText(j.ok ? 'Pacchetto ' + (UPD_NAMES[j.package] || j.package) + ' ' + j.stored + ' conservato sul monitor: i controller lo vedono al prossimo collegamento.'
                     : '<span style="color:#ff8a8a">Non accettato: ' + (j.error || ('errore ' + j._status)) + '</span>');
      }).catch(function () { upd.busy = false; updText('<span style="color:#ff8a8a">Invio non riuscito.</span>'); });
    };
    rd.readAsArrayBuffer(f);
  };

  // ---------- controlli a cursore ----------
  function fmt(k, v) { return P[k].dec ? Number(v).toFixed(P[k].dec) : v; }
  function cur(k) { return pending[k] !== undefined ? pending[k] : (state ? state[k] : 0); }
  function buildCtl(el) {
    var k = el.dataset.p, d = P[k];
    el.className = 'ctl c-' + d.c;
    el.innerHTML = '<label>' + d.l + ' <output></output> <small>' + d.u + '</small> <span class="pend"></span></label>' +
      '<div class="srow"><button type="button" data-d="-1">−</button><input type="range" min="' + d.min + '" max="' + d.max + '" step="' + d.step + '"><button type="button" data-d="1">+</button></div>' +
      (d.q ? '<div class="quickv">' + d.q.map(function (v) { return '<button type="button" data-v="' + v + '">' + v + '</button>'; }).join('') + '</div>' : '');
    var inp = el.querySelector('input');
    inp.addEventListener('input', function () {
      editing[k] = true;
      if (d.now || mode === 0) el.querySelector('output').textContent = fmt(k, inp.value);
      else { var pe = el.querySelector('.pend'); pe.className = 'pend wait'; pe.textContent = '→ ' + inp.value; }
    });
    inp.addEventListener('change', function () { commit(k, parseFloat(inp.value)); });
    all('.srow button', el).forEach(function (b) {
      b.onclick = function () {
        var st = d.step, v = Math.round((parseFloat(inp.value) + (+b.dataset.d) * st) / st) * st;
        inp.value = Math.max(d.min, Math.min(d.max, v)); commit(k, parseFloat(inp.value));
      };
    });
    all('.quickv button', el).forEach(function (b) { b.onclick = function () { inp.value = b.dataset.v; commit(k, parseFloat(b.dataset.v)); }; });
  }
  function commit(k, v) {
    var d = P[k], done = function () { editing[k] = false; if (state) render(state); };
    editing[k] = true;
    var pr = d.now ? command(d.now, v) : change(k, d.dec ? v : Math.round(v));
    return Promise.resolve(pr).then(done, done);
  }
  // PA: la diastolica resta almeno 10 mmHg sotto la sistolica
  function bpPair(k, v) {
    var sys = k === 'systolic_mmhg' ? v : cur('systolic_mmhg'), dia = k === 'diastolic_mmhg' ? v : cur('diastolic_mmhg');
    if (k === 'systolic_mmhg' && dia > sys - 10) { dia = Math.max(20, sys - 10); msg('Diastolica adeguata a ' + dia + ' mmHg (deve restare sotto la sistolica)'); }
    if (k === 'diastolic_mmhg' && sys < dia + 10) { sys = Math.min(260, dia + 10); msg('Sistolica adeguata a ' + sys + ' mmHg (deve restare sopra la diastolica)'); }
    return [sys, dia];
  }
  function change(k, v) {
    if (k === 'systolic_mmhg' || k === 'diastolic_mmhg') {
      var bp = bpPair(k, v);
      if (mode === 0) return command('set_bp', { systolic: bp[0], diastolic: bp[1] });
      pending.systolic_mmhg = bp[0]; pending.diastolic_mmhg = bp[1]; renderPending(); return Promise.resolve();
    }
    if (mode === 0) { var p = {}; p[k] = v; return command('transition', { params: p, duration_s: 0 }); }
    pending[k] = v; renderPending(); return Promise.resolve();
  }
  function setBp(sys, dia) {
    if (mode === 0) return command('set_bp', { systolic: sys, diastolic: dia });
    pending.systolic_mmhg = sys; pending.diastolic_mmhg = dia; renderPending(); if (state) render(state);
  }
  function renderCtls(s) {
    Object.keys(P).forEach(function (k) {
      var els = all('.ctl[data-p="' + k + '"]'), val = s[k];
      if (val === undefined) return;
      var tr = s.transitions && s.transitions[k];
      els.forEach(function (el) {
        var pe = el.querySelector('.pend');
        if (pending[k] !== undefined) { pe.className = 'pend wait'; pe.textContent = '→ ' + pending[k] + ' (in attesa)'; }
        else if (tr) {
          pe.className = 'pend run';
          pe.innerHTML = '→ ' + tr.to + ' · ' + tr.remaining_s + ' s <button class="stop1" title="Interrompi">■</button>';
          pe.querySelector('button').onclick = function (e) { e.preventDefault(); command('cancel_transitions', [k]); };
        } else if (!editing[k]) { pe.className = 'pend'; pe.textContent = ''; }
        if (editing[k]) return;
        el.querySelector('output').textContent = fmt(k, val);
        el.querySelector('input').value = pending[k] !== undefined ? pending[k] : val;
      });
    });
  }

  // ---------- modalità di applicazione e modifiche in attesa ----------
  function setMode(t) {
    mode = t;
    all('#modes .mode').forEach(function (b) { b.className = 'mode' + (parseInt(b.dataset.t, 10) === t ? ' active' : ''); });
    $('customT').className = (t > 0 && [10, 20, 30, 60, 120].indexOf(t) < 0) ? 'active' : '';
    if (t === 0 && isPending()) applyNow();
    renderPending();
  }
  function changeRhythm(r) {
    if (mode === 0) return command('set_rhythm', r);
    pendingRhythm = r; renderPending(); renderRhythms();
  }
  function currentStep() {
    var st = { params: JSON.parse(JSON.stringify(pending)), duration_s: mode };
    if (pendingRhythm) st.rhythm = pendingRhythm;
    return st;
  }
  function clearPending() { pending = {}; pendingRhythm = null; renderPending(); renderRhythms(); if (state) render(state); }
  function applyNow() {
    if (!isPending()) return;
    var st = currentStep(), saved = { p: pending, r: pendingRhythm };
    pending = {}; pendingRhythm = null; renderPending(); renderRhythms();
    cmdSeq++;
    api('POST', '/api/v1/command', { device_id: state && state.device_id, command: 'transition', value: st })
      .then(function (j) {
        if (!j.ok) { pending = saved.p; pendingRhythm = saved.r; renderPending(); renderRhythms(); }
        handle(j);
      }, function () { pending = saved.p; pendingRhythm = saved.r; renderPending(); msg('monitor non raggiungibile'); });
  }
  function describe(st) {
    var parts = Object.keys(st.params || {}).map(function (k) { return PNAME[k] + ' → ' + st.params[k]; });
    if (st.rhythm) parts.unshift(RHYTHMS[st.rhythm]);
    return parts.join(', ') || '—';
  }
  function renderPending() {
    var running = state && state.transitions ? Object.keys(state.transitions) : [];
    $('stopbar').hidden = running.length === 0;
    if (running.length) $('runSummary').textContent = 'In corso: ' + running.map(function (k) {
      return (PNAME[k] || k) + ' → ' + state.transitions[k].to + ' (' + state.transitions[k].remaining_s + ' s)'; }).join(' · ');
    var show = mode > 0 && isPending();
    $('gobar').hidden = !show;
    if (show) { $('pendSummary').textContent = describe(currentStep()); $('go').textContent = '▶ Avvia (' + mode + ' s)'; }
  }
  function renderRhythms() {
    all('.rhythms button[data-r]').forEach(function (b) {
      var r = b.dataset.r;
      b.className = (state && r === state.rhythm ? 'active' : '') + (r === pendingRhythm ? ' pending' : '');
    });
  }

  // ---------- chip dei sensori ----------
  function renderChips(s) {
    var chips = $('chips'), sig = JSON.stringify([s.sensors, s.sensor_sites, selSensor]);
    if (chips.dataset.sig === sig) return;
    chips.dataset.sig = sig;
    chips.innerHTML = ORDER.map(function (k) {
      var o = on(k);
      return '<span class="chip' + (o ? ' on' : '') + (selSensor === k ? ' sel' : '') + '" data-k="' + k + '" style="color:' + SENS[k].color + '"' +
        ' title="' + (o ? SENS[k].full + ' · ' + esc(siteLabel(siteOf(k))) : 'Applica ' + SENS[k].full + ' (' + esc(siteLabel(SENS[k].def)) + ')') + '">' +
        '<i></i><b>' + SENS[k].name + '</b><em>' + (o ? esc(siteLabel(siteOf(k))) : 'applica') + '</em>' +
        (o ? '<button class="x" title="Togli ' + SENS[k].full + ' dal paziente">×</button>' : '') + '</span>';
    }).join('');
  }

  // ---------- saturimetro palmare (SimulaFranz_Saturimetro) ----------
  // che cosa mostra il saturimetro (stessa logica del dispositivo: sensore, ritardo, segnale, polso, bassa perfusione)
  function oxiShown(s) {
    var o = s.oximeter; if (!o || !o.power) return '';
    if (!o.sensor_connected) return '---';
    var since = o.sensor_since_s || 0, d = s.spo2_delay_s || 0;
    if (since < d) return since < d / 2 ? 'ricerca' : '---';
    if (!s.spo2_signal_valid || o.cuff_occluded || !s.pulse_present) return '---';
    return s.spo2_percent + (s.spo2_low_perfusion || s.spo2_low_perfusion_flag ? '?' : '') + ' · ' + s.pulse_rate_bpm;
  }
  var OXI_L = ['spo2_low', 'spo2_high', 'pr_low', 'pr_high'], oxiLimitsDirty = false;
  function renderOxi(s) {
    var o = s.oximeter; if (!o) return;
    var badge = $('oxiBadge'); badge.hidden = !o.online; badge.textContent = o.power ? 'on' : 'off';
    $('oxiLink').textContent = o.online ? 'in linea' : 'non in linea (nessuna richiesta da 6 s)';
    $('oxiLink').className = 'hint ' + (o.online ? 'ok' : 'warn');
    var shown = oxiShown(s);
    $('oxiStatus').textContent = (o.power ? 'Acceso' : 'Spento') + ' · sensore ' + (o.sensor_connected ? 'applicato (' + siteLabel(o.site || SENS.oxi.def) + ')' : 'non applicato') +
      (o.power ? ' · mostra: ' + (shown || '—') : '') + (o.muted_remaining_s ? ' · allarmi silenziati ' + fmtMMSS(o.muted_remaining_s) : '');
    var p = $('oxiPower'); p.className = 'toggle ' + (o.power ? 'on' : 'off'); p.textContent = o.power ? 'Acceso' : 'Spento';
    var sb = $('oxiSensor'); sb.textContent = o.sensor_connected ? 'Togli il sensore' : 'Applica il sensore (' + siteLabel(SENS.oxi.def) + ')';
    $('oxiMute').disabled = !o.power;
    if (!oxiLimitsDirty && o.alarm_limits) OXI_L.forEach(function (k) { var i = $('ol_' + k); if (document.activeElement !== i) i.value = o.alarm_limits[k]; });
    if (!editing.oxiVolume) { $('oxiVolume').value = o.volume; $('o_oxiVolume').textContent = o.volume; }
  }

  // ---------- defibrillatore ----------
  function renderDefib(s) {
    var d = s.defib; if (!d) return;
    var phase = { pads: 'applicare le piastre', analyzing: 'analisi', charging: 'carica', ready: 'pronto allo shock', cpr: 'RCP' };
    var main = DMODE[d.mode] || d.mode;
    var sub = 'shock ' + d.shock_count + (d.shock_count ? ' (ultimo ' + d.last_shock_energy_j + ' J)' : '');
    if (d.mode === 'aed') sub = phase[d.aed_phase] + (d.aed_remaining_s ? ' ' + d.aed_remaining_s + ' s' : '') + ' · ' + sub;
    if (d.mode === 'pacer') sub = (d.pacer.running ? d.pacer.rate_ppm + ' ppm ' + d.pacer.output_ma + ' mA · ' +
      (d.pacer.capture ? (d.pacer.mechanical_capture ? 'CATTURA + polso' : 'cattura elettrica, senza polso') : (d.pacer.active ? 'NESSUNA CATTURA' : 'inibito')) : 'fermo') + ' · ' + sub;
    $('v_defib').textContent = main + (d.pads_connected ? '' : ' · piastre no');
    $('v_defib_sub').textContent = sub;
    $('d_status').innerHTML = esc(d.message || '') + '<small>' + esc('Modalità ' + main + ' · piastre ' + (d.pads_connected ? 'applicate' : 'NON applicate') +
      ' · energia ' + d.energy_j + ' J · ' + ({ none: 'scarico', charging: 'in carica', ready: 'carico' }[d.charge] || d.charge) + (d.sync ? ' · SYNC' : '') + ' · ' + sub) + '</small>';
    if (document.activeElement !== $('d_mode')) $('d_mode').value = d.mode;
    var om = (d.config && d.config.outcome_mode) || 'instructor';
    all('#d_outcome button').forEach(function (b) { b.className = b.dataset.v === om ? 'active' : ''; });
    $('d_rules').className = 'dcfg' + (om === 'instructor' ? ' disabled' : '');
    $('dcfgHint').textContent = om === 'instructor' ? 'Modalità "decido io": le regole di conversione sono ignorate.' : '';
    $('d_decide').hidden = !d.outcome_pending;
    $('tabDefibBadge').hidden = !d.outcome_pending;
    if (d.outcome_pending) $('d_decide_text').textContent = (d.outcome_sync ? 'Cardioversione sincronizzata' : 'Scarica') + ' n. ' + d.outcome_shock +
      (d.outcome_energy_j ? ' (' + d.outcome_energy_j + ' J)' : '') + ' erogata su ' + (RHYTHMS[d.outcome_from] || d.outcome_from) + ': che cosa succede adesso?';
    $('d_dec_stay').textContent = 'Resta in ' + (RHYTHMS[d.outcome_from] || 'ritmo pre-scarica');
    if (!dcfgDirty && d.config) {
      DCFG_NUM.forEach(function (k) { if (document.activeElement !== $('c_' + k)) $('c_' + k).value = d.config[k]; });
      DCFG_BOOL.forEach(function (k) { $('c_' + k).checked = !!d.config[k]; });
      DCFG_RHY.forEach(function (k) { if (document.activeElement !== $('c_' + k)) $('c_' + k).value = d.config[k]; });
    }
    var log = $('d_log'), ev = d.events || [], last = ev.length ? ev[ev.length - 1].time + ev[ev.length - 1].text : '';
    if (log.dataset.n !== String(ev.length) || log.dataset.last !== last) {
      log.dataset.n = String(ev.length); log.dataset.last = last;
      log.innerHTML = ev.map(function (e) { return '<li class="' + (e.instructor ? 'instr' : '') + '">' + esc(e.time + '  (' + e.elapsed + ')  ' + e.text) + '</li>'; }).join('');
      log.scrollTop = log.scrollHeight;
    }
  }

  // ---------- rendering generale ----------
  function setMon(id, txt) {                        // riga "monitor:" delle tessere
    var el = $(id); if (!el) return;
    el.textContent = 'monitor: ' + (txt || '--');
    el.classList.toggle('none', !txt);
  }
  function render(s) {
    if (!s) return;
    state = s;
    $('device').textContent = '→ ' + s.device_id + ' · v' + s.version;
    // tessere: in grande i valori VERI del paziente, sotto ciò che il discente vede sul monitor
    $('v_rhythm').textContent = RHYTHMS[s.rhythm] || s.rhythm;
    var vp = $('v_pulse');
    vp.textContent = (s.pulse_present ? 'polso presente' : 'SENZA POLSO') + (s.cpr_active ? ' · RCP' : '');
    vp.classList.toggle('none', !!s.pulse_present && !s.cpr_active);
    $('v_hr').textContent = s.heart_rate_bpm;
    var codes = { vt: 'TV', vt_pulse: 'TV', vf: 'FV', asystole: 'Asy' };
    setMon('m_hr', (s.sensors.ecg && codes[s.rhythm]) || (s.displayed_heart_rate_bpm === null ? '' : String(s.displayed_heart_rate_bpm)));
    $('v_bp').textContent = s.systolic_mmhg + '/' + s.diastolic_mmhg;
    var nibpTxt = s.nibp_last_systolic_mmhg !== null ? s.nibp_last_systolic_mmhg + '/' + s.nibp_last_diastolic_mmhg
      : (s.nibp_status === 'error' && s.nibp_error === 'no_pulse' ? '?/?' : '---/---');
    var bpParts = [];
    if (s.art_displayed_systolic_mmhg !== null) bpParts.push('ART ' + s.art_displayed_systolic_mmhg + '/' + s.art_displayed_diastolic_mmhg);
    if (s.nibp_status === 'measuring') bpParts.push('NIBP in corso…');
    else if (s.nibp_last_systolic_mmhg !== null) bpParts.push('NIBP ' + nibpTxt);
    setMon('m_bp', bpParts.join(' · '));
    $('v_spo2').textContent = s.spo2_percent;
    var oxiTxt = oxiShown(s);
    setMon('m_spo2', (s.spo2_displayed === null ? '' : s.spo2_displayed + (s.spo2_low_perfusion ? '?' : '')) + (oxiTxt ? (s.spo2_displayed === null ? '' : ' · ') + 'sat. ' + oxiTxt : ''));
    renderOxi(s);
    $('v_co2').textContent = s.respiratory_rate_rpm + ' · ' + s.etco2_mmhg;
    setMon('m_co2', s.etco2_displayed === null ? '' : 'EtCO₂ ' + s.etco2_displayed);
    $('v_temp').textContent = Number(s.temperature_c).toFixed(1) + '° · ' + (s.crt_s !== undefined ? s.crt_s + ' s' : '--');
    setMon('m_temp', s.temperature_displayed === null || s.temperature_displayed === undefined ? '' : s.temperature_displayed.toFixed(1) + ' °C');
    // NIBP nella scheda pressione
    $('n_last').textContent = nibpTxt;
    var nibpSt = { idle: 'nessuna misura', measuring: 'misura in corso…', complete: 'mmHg',
                   error: s.nibp_error === 'cuff' ? 'bracciale non collegato / perdita' : s.nibp_error === 'motion' ? 'misura fallita: movimenti' : 'nessun polso rilevato' };
    $('n_state').textContent = nibpSt[s.nibp_status] || '';
    var cp = $('cpr'); cp.className = 'act danger' + (s.cpr_active ? ' on' : ''); cp.textContent = s.cpr_active ? '■ Ferma RCP' : '▶ RCP';
    var vb = $('vent'); vb.disabled = !s.ventilation_manual;
    vb.textContent = s.ventilation_manual ? 'Ventila' + (s.breaths_last_min ? ' · ' + s.breaths_last_min + '/min' : '') : 'Ventila (respira da solo)';
    if (document.activeElement !== $('nibpInterval')) $('nibpInterval').value = String(s.nibp_interval_min);
    $('nibpNext').textContent = s.nibp_interval_min > 0 && s.nibp_next_in_s !== null
      ? 'Prossima misura tra ' + Math.floor(s.nibp_next_in_s / 60) + ':' + ('0' + (s.nibp_next_in_s % 60)).slice(-2) : 'Solo misure manuali.';
    $('nibpStart').disabled = $('nibpStart2').disabled = s.nibp_status === 'measuring';
    if (s.alarm_enabled) Object.keys(s.alarm_enabled).forEach(function (k) {
      var c = $('ae_' + k); if (c && document.activeElement !== c) c.checked = !!s.alarm_enabled[k];
    });
    // SpO2
    var g = $('signalSw'); g.querySelector('input').checked = !!s.spo2_signal_valid;
    var lp = $('lowPerfSw'), lpOn = !!s.spo2_low_perfusion_flag;
    lp.querySelector('input').checked = lpOn; lp.className = 'sw flag' + (lpOn ? ' warn' : '');
    if (document.activeElement !== $('spo2Delay') && s.spo2_delay_s !== undefined) $('spo2Delay').value = String(s.spo2_delay_s);
    $('spo2Acq').textContent = s.spo2_acquiring ? 'acquisizione in corso…' : '';
    var sameArm = on('spo2') && on('nibp') && sideOf(siteOf('spo2')) && sideOf(siteOf('spo2')) === sideOf(siteOf('nibp')) && /^finger/.test(siteOf('spo2'));
    $('spo2Note').textContent = s.spo2_cuff_occluded ? 'Bracciale in misura sullo stesso braccio: SpO₂ persa finché non si sgonfia.'
      : sameArm ? 'Sonda e bracciale sullo stesso braccio: durante ogni misura NIBP la SpO₂ si perde.' : '';
    var artSame = on('art') && on('nibp') && /^(radial|ulnar|brachial)/.test(siteOf('art')) && sideOf(siteOf('art')) && sideOf(siteOf('art')) === sideOf(siteOf('nibp'));
    $('artNote').textContent = s.art_cuff_occluded ? 'Bracciale in misura sullo stesso braccio della linea arteriosa: curva smorzata finché non si sgonfia.'
      : artSame ? 'Linea arteriosa e bracciale sullo stesso braccio: durante ogni misura NIBP la curva arteriosa si smorza.' : '';
    // monitor
    // elenco dei layout dal monitor (id + nome): qui non è scritto nessun nome
    var lays = s.layouts || [], laySig = lays.map(function (l) { return l.id + '=' + l.name; }).join('|');
    if ($('layoutSeg').dataset.sig !== laySig) {
      $('layoutSeg').dataset.sig = laySig;
      $('layoutSeg').innerHTML = lays.map(function (l) { return '<button data-v="' + esc(l.id) + '">' + esc(l.name) + '</button>'; }).join('');
        }
    all('#layoutSeg button').forEach(function (b) { b.className = b.dataset.v === (s.layout || 'generic_icu') ? 'active' : ''; });
    if (!editing.volume) { $('volume').value = s.volume_percent; $('o_volume').textContent = s.volume_percent; }
    var b = $('beep'); b.className = 'toggle ' + (s.qrs_beep_enabled ? 'on' : 'off'); b.textContent = s.qrs_beep_enabled ? 'Bip attivo' : 'Bip disattivato';
    all('.autoPhysio').forEach(function (ap) {
      ap.className = 'toggle wide autoPhysio ' + (s.auto_physiology ? 'on' : 'off');
      ap.textContent = s.auto_physiology ? 'Fisiologia automatica: ON' : 'Fisiologia automatica: OFF';
    });
    // azioni rapide
    all('#motionSeg button').forEach(function (bt) {
      bt.className = bt.dataset.v === (s.patient_motion || 'off') ? 'active' : '';
      bt.disabled = bt.dataset.v !== 'off' && !s.pulse_present;
    });
    $('touch').className = 'act touch' + (s.operator_touch ? ' on' : '');
    $('motionLeft').textContent = s.patient_motion && s.patient_motion !== 'off' && s.patient_motion_remaining_s > 0 ? s.patient_motion_remaining_s + ' s' : '';
    $('mute').textContent = s.alarms_muted ? 'Silenziato ' + (s.alarms_muted_remaining_s || 0) + ' s · riattiva' : 'Silenzia 20 s';
    $('pause').textContent = s.simulation_running ? 'II Pausa' : '▶ Riprendi';
    if (!limitsDirty && s.alarm_limits) LIMITS.forEach(function (k) {
      if (document.activeElement !== $('l_' + k)) $('l_' + k).value = s.alarm_limits[k];
    });
    if (hoverSite && !$('tip').hidden) $('tip').innerHTML = hotInfo(hoverSite);
    warnTiles(s); renderClock(s);
    renderCtls(s); renderRhythms(); renderPending(); renderDefib(s); renderChips(s); renderFigure(s);
  }

  // =====================================================================
  // costruzione e collegamenti
  // =====================================================================
  $('figure').innerHTML = buildFigure();
  wireFigure();
  requestAnimationFrame(breathLoop);
  all('.ctl[data-p]').forEach(buildCtl);
  all('.rhythmbox').forEach(function (box) {
    box.innerHTML = '<div><div class="rlab">Sinusali e sopraventricolari</div><div class="rhythms"></div></div>' +
                    '<div><div class="rlab">Ventricolari e arresto</div><div class="rhythms danger"></div></div>';
    var grp = box.querySelectorAll('.rhythms');
    Object.keys(RHYTHMS).forEach(function (r) {
      var bt = document.createElement('button'); bt.textContent = RHYTHMS[r]; bt.dataset.r = r;
      bt.onclick = function () { changeRhythm(r); };
      grp[ARREST.indexOf(r) >= 0 ? 1 : 0].appendChild(bt);
    });
  });
  all('.bpq').forEach(function (box) {
    BPQ.forEach(function (q) {
      var bt = document.createElement('button'); bt.type = 'button'; bt.textContent = q[0] + ' ' + q[1] + '/' + q[2];
      bt.onclick = function () { setBp(q[1], q[2]); };
      box.appendChild(bt);
    });
  });
  $('chips').addEventListener('click', function (e) {           // chip: applica, mostra i controlli, o toglie (×)
    var c = e.target.closest('.chip'); if (!c) return;
    var k = c.dataset.k;
    if (e.target.closest('.x')) { detach(k); return; }
    if (on(k)) select(k); else place(k, SENS[k].def);
  });
  all('.tile[data-card]').forEach(function (t) {
    t.onclick = function () { showCard(t.dataset.card); flashCard(t.dataset.card); };
  });
  all('#pnav button').forEach(function (bt) { bt.onclick = function () { showCard(bt.dataset.card); }; });

  $('spo2Delay').innerHTML = [0, 3, 5, 8, 10, 15, 20, 30, 45, 60, 90].map(function (v) {
    return '<option value="' + v + '">' + (v ? v + ' s' : 'nessuno') + '</option>'; }).join('');
  $('spo2Delay').onchange = function () { command('set_spo2_delay', parseInt($('spo2Delay').value, 10)); };
  $('signalSw').querySelector('input').onchange = function (e) { command('set_spo2_signal_valid', e.target.checked); };
  $('lowPerfSw').querySelector('input').onchange = function (e) { command('set_spo2_low_perfusion', e.target.checked); };

  DCFG_RHY.forEach(function (k) {
    $('c_' + k).innerHTML = Object.keys(RHYTHMS).map(function (r) { return '<option value="' + r + '">' + RHYTHMS[r] + '</option>'; }).join('');
  });
  DCFG_NUM.concat(DCFG_BOOL, DCFG_RHY).forEach(function (k) {
    var mark = function () { dcfgDirty = true; $('defibCfgApply').classList.add('dirty'); $('defibCfgApply').textContent = 'Applica impostazioni (modificate)'; };
    $('c_' + k).addEventListener('input', mark); $('c_' + k).addEventListener('change', mark);
  });
  $('defibCfgApply').onclick = function () {
    var v = {};
    DCFG_NUM.forEach(function (k) { v[k] = parseInt($('c_' + k).value, 10); });
    DCFG_BOOL.forEach(function (k) { v[k] = $('c_' + k).checked; });
    DCFG_RHY.forEach(function (k) { v[k] = $('c_' + k).value; });
    command('set_defib_config', v).then(function () {
      dcfgDirty = false; $('defibCfgApply').classList.remove('dirty'); $('defibCfgApply').textContent = 'Applica impostazioni';
    });
  };
  $('d_mode').onchange = function () { command('defib_mode', $('d_mode').value); };
  all('#d_outcome button').forEach(function (bt) { bt.onclick = function () { command('set_defib_config', { outcome_mode: bt.dataset.v }); }; });
  $('d_dec_other').innerHTML = Object.keys(RHYTHMS).map(function (r) { return '<option value="' + r + '">' + RHYTHMS[r] + '</option>'; }).join('');
  $('d_dec_sinus').onclick = function () { command('defib_outcome', 'sinus'); };
  $('d_dec_stay').onclick = function () { command('defib_outcome', 'stay'); };
  $('d_dec_other_go').onclick = function () { command('defib_outcome', $('d_dec_other').value); };

  $('touch').onclick = function () { command('patient_touch', 3); };
  all('#motionSeg button').forEach(function (bt) {
    bt.onclick = function () {
      var d = parseInt($('motionDur').value, 10) || 0;
      command('set_patient_motion', bt.dataset.v === 'off' ? 'off' : { level: bt.dataset.v, duration_s: d });
    };
  });
  all('.crtAssess').forEach(function (b) { b.onclick = function () { command('assess_crt'); msg('Refill: valutazione in corso sul monitor'); }; });
  all('.autoPhysio').forEach(function (ap) { ap.onclick = function () { command('set_auto_physiology', !state.auto_physiology); }; });
  all('#modes .mode').forEach(function (bt) { bt.onclick = function () { $('customT').value = ''; setMode(parseInt(bt.dataset.t, 10)); }; });
  $('customT').addEventListener('change', function () { var t = parseInt($('customT').value, 10); if (t > 0 && t <= 3600) setMode(t); });
  $('go').onclick = applyNow;
  $('pendCancel').onclick = clearPending;
  $('trCancel').onclick = function () { command('cancel_transitions'); };
  $('volume').addEventListener('input', function () { editing.volume = true; $('o_volume').textContent = $('volume').value; });
  $('volume').addEventListener('change', function () { command('set_volume', parseInt($('volume').value, 10)).then(function () { editing.volume = false; }); });
  LIMITS.forEach(function (k) { $('l_' + k).addEventListener('input', function () { limitsDirty = true; }); });
  $('limitsApply').onclick = function () {
    var v = {}; LIMITS.forEach(function (k) { v[k] = parseInt($('l_' + k).value, 10); });
    command('set_alarm_limits', v).then(function () { limitsDirty = false; });
  };
  $('limitsReset').onclick = function () { limitsDirty = false; command('reset_alarm_limits'); };
  ['hr', 'spo2', 'art', 'nibp', 'rr', 'etco2'].forEach(function (k) {
    var c = $('ae_' + k); if (c) c.onchange = function () { command('set_alarm_enabled', { param: k, enabled: c.checked }); };
  });
  $('beep').onclick = function () { command('set_qrs_beep', !state.qrs_beep_enabled); };
  $('oxiPower').onclick = function () { if (!state || !state.oximeter) return; var on_ = !state.oximeter.power; logAdd('Saturimetro ' + (on_ ? 'acceso' : 'spento') + ' dal controller', 'monitor'); command('set_oximeter', { power: on_ }); };
  $('oxiSensor').onclick = function () { if (!state) return; if (on('oxi')) detach('oxi'); else place('oxi', SENS.oxi.def); };
  $('oxiMute').onclick = function () { logAdd('Saturimetro: allarmi silenziati 2 min (controller)', 'monitor'); command('set_oximeter', { mute_s: 120 }); };
  OXI_L.forEach(function (k) { $('ol_' + k).addEventListener('input', function () { oxiLimitsDirty = true; }); });
  $('oxiLimitsApply').onclick = function () {
    var lim = {}; OXI_L.forEach(function (k) { var v = parseInt($('ol_' + k).value, 10); if (!isNaN(v)) lim[k] = v; });
    command('set_oximeter', { alarm_limits: lim }).then(function () { oxiLimitsDirty = false; logAdd('Saturimetro: limiti di allarme cambiati', 'monitor'); });
  };
  $('oxiLimitsReset').onclick = function () { command('set_oximeter', { alarm_limits: { spo2_low: 85, spo2_high: 100, pr_low: 30, pr_high: 170 } }).then(function () { oxiLimitsDirty = false; }); };
  $('oxiVolume').addEventListener('input', function () { editing.oxiVolume = true; $('o_oxiVolume').textContent = $('oxiVolume').value; });
  $('oxiVolume').addEventListener('change', function () { command('set_oximeter', { volume: parseInt($('oxiVolume').value, 10) }).then(function () { editing.oxiVolume = false; }); });
  $('mute').onclick = function () { command('mute_alarms', !state.alarms_muted); };
  $('pause').onclick = function () {
    command('set_simulation_running', !state.simulation_running);
  };
  var resetArm = 0, resetT = null;
  function resetDisarm() { resetArm = 0; $('reset').textContent = 'Reset scenario'; $('reset').classList.remove('armed'); }
  $('reset').onclick = function () {                 // doppio tocco entro 4 s: niente finestre di conferma
    if (resetArm && Date.now() - resetArm < 4000) {
      clearTimeout(resetT); resetDisarm(); clearPending();
      command('reset_scenario').then(function () {
        lastState = null; sessionStorage.removeItem('sf_last_state');
        renderStates();
      });
    } else {
      resetArm = Date.now();
      $('reset').textContent = 'Tocca di nuovo per azzerare'; $('reset').classList.add('armed');
      resetT = setTimeout(resetDisarm, 4000);
    }
  };
  var nibpGo = function () { api('POST', '/api/v1/nibp/start', {}).then(handle); };
  $('nibpStart').onclick = nibpGo; $('nibpStart2').onclick = nibpGo;
  $('cpr').onclick = function () {
    command('set_cpr', !state.cpr_active);
  };
  $('vent').onclick = function () { command('ventilate'); };      // una insufflazione dei partecipanti = un'onda di CO2
  $('nibpInterval').onchange = function () { command('set_nibp_interval', parseInt($('nibpInterval').value, 10)); };
  $('logout').onclick = function () {
    if (ctlMine && token) api('POST', '/api/v1/control', { action: 'release' }).catch(function () {});   // lascia libero il comando
    token = ''; sessionStorage.removeItem('sf_token'); showLogin('');
  };
  $('takeCtl').onclick = takeControl;
  var clockArm = 0;                                   // orologio di scenario: azzeramento a doppio tocco
  $('clockReset').onclick = function () {
    var b = $('clockReset');
    if (clockArm && Date.now() - clockArm < 4000) { clockArm = 0; b.textContent = 'Azzera'; b.classList.remove('armed'); command('reset_clock'); return; }
    clockArm = Date.now(); b.textContent = 'Tocca di nuovo'; b.classList.add('armed');
    setTimeout(function () { if (clockArm) { clockArm = 0; b.textContent = 'Azzera'; b.classList.remove('armed'); } }, 4000);
  };
  $('loginForm').addEventListener('submit', function (e) {
    e.preventDefault();
    token = $('pin').value.trim();
    api('GET', '/api/v1/state').then(function (j) {
      if (j.ok) { sessionStorage.setItem('sf_token', token); $('pin').value = ''; showConsole(); render(j.state); }
      else handle(j);
    }).catch(function () { $('loginErr').textContent = 'monitor non raggiungibile'; });
  });

  // stati, interventi e registro
  renderStates();
  initScen();
  $('stateChips').addEventListener('click', function (e) {
    var b = e.target.closest('.stchip'); if (!b) return;
    var i = parseInt(b.dataset.i, 10);
    savingState = false; selState = selState === i ? null : i;
    renderStates();
    if (selState !== null) $('stateExp').scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  });
  $('saveState').onclick = saveStateUI;
  initLog();
  // figura in miniatura <-> espansa (per piazzare le sonde con precisione)
  function figOpen() { document.body.classList.add('figbig'); $('figBack').hidden = false; $('figClose').hidden = false; }
  function figShut() { document.body.classList.remove('figbig'); $('figBack').hidden = true; $('figClose').hidden = true; }
  $('miniShield').onclick = figOpen;
  $('figExpand').onclick = figOpen;
  $('figClose').onclick = figShut;
  $('figBack').onclick = figShut;
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') figShut(); });

  setMode(0);
  showCard(card);
  api('GET', '/api/v1/health').then(function (h) {
    setConn(true, 'monitor raggiungibile'); $('device').textContent = '→ ' + h.device_id + (h.version && h.version !== '?' ? ' · v' + h.version : '');
  }).catch(function () { setConn(false, 'monitor non raggiungibile'); });
  if (token) showConsole(); else showLogin('');
})();
