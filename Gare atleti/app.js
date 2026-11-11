(() => {
  'use strict';

  const DATA_URL = './data/team-data.enc.json';
  const STORAGE_KEY = 'dinamica_swim_pw_v1';

  const STROKE_ORDER = ['stile libero', 'dorso', 'rana', 'farfalla', 'misti', 'mista'];

  const state = {
    envelope: null,
    realDataset: null,
    activeDataset: null,
    demoMode: false,
    currentView: 'athletes',
    selectedCategory: 'ALL',
    selectedGender: 'ALL',
    searchQuery: '',
    selectedAthleteId: null,
    selectedChartEvent: '',
    selectedChartPool: 'ALL',
    selectedSubtab: 'history'
  };

  const els = {
    authScreen: document.getElementById('auth-screen'),
    appShell: document.getElementById('app-shell'),
    authForm: document.getElementById('auth-form'),
    passwordInput: document.getElementById('team-password'),
    togglePwBtn: document.getElementById('toggle-pw-btn'),
    rememberPw: document.getElementById('remember-pw'),
    authError: document.getElementById('auth-error'),
    unlockBtn: document.getElementById('unlock-btn'),
    localFallback: document.getElementById('local-file-fallback'),
    manualEncFile: document.getElementById('manual-enc-file'),
    clubTitle: document.getElementById('club-title'),
    lastUpdatedText: document.getElementById('last-updated-text'),
    demoToggleBtn: document.getElementById('demo-toggle-btn'),
    logoutBtn: document.getElementById('logout-btn'),
    statusBanner: document.getElementById('status-banner'),
    navTabs: document.querySelectorAll('.nav-tab'),
    viewAthletes: document.getElementById('view-athletes'),
    viewDetail: document.getElementById('view-detail'),
    viewRanking: document.getElementById('view-ranking'),
    viewCoach: document.getElementById('view-coach'),
    athleteSearch: document.getElementById('athlete-search'),
    genderFilter: document.getElementById('gender-filter'),
    categoryPills: document.getElementById('category-pills'),
    athletesContainer: document.getElementById('athletes-container'),
    backToAthletes: document.getElementById('back-to-athletes'),
    athleteHeaderCard: document.getElementById('athlete-header-card'),
    athletePbList: document.getElementById('athlete-pb-list'),
    chartEventSelect: document.getElementById('chart-event-select'),
    chartPoolSelect: document.getElementById('chart-pool-select'),
    chartStatsRow: document.getElementById('chart-stats-row'),
    chartContainer: document.getElementById('chart-container'),
    chartPointDetail: document.getElementById('chart-point-detail'),
    subtabs: document.querySelectorAll('.subtab'),
    athleteHistoryPanel: document.getElementById('athlete-history-panel'),
    athleteEntriesPanel: document.getElementById('athlete-entries-panel'),
    rankEventSelect: document.getElementById('rank-event-select'),
    rankCategorySelect: document.getElementById('rank-category-select'),
    rankGenderSelect: document.getElementById('rank-gender-select'),
    rankPoolSelect: document.getElementById('rank-pool-select'),
    rankCountLabel: document.getElementById('rank-count-label'),
    rankingTableWrap: document.getElementById('ranking-table-wrap'),
    relaysBox: document.getElementById('relays-box'),
    manualCsvForm: document.getElementById('manual-csv-form'),
    athletesDatalist: document.getElementById('athletes-datalist'),
    csvOutputWrap: document.getElementById('csv-output-wrap'),
    csvOutputBox: document.getElementById('csv-output-box'),
    copyCsvBtn: document.getElementById('copy-csv-btn')
  };

  /* ==================== UTILITY FORMATTING ==================== */

  function escapeHtml(value) {
    return String(value ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function formatCentis(cs) {
    if (!Number.isFinite(cs) || cs <= 0) return '—';
    const totalCs = Math.round(cs);
    const min = Math.floor(totalCs / 6000);
    const rem = totalCs % 6000;
    const sec = Math.floor(rem / 100);
    const c = rem % 100;
    return `${String(min).padStart(2, '0')}'${String(sec).padStart(2, '0')}.${String(c).padStart(2, '0')}`;
  }

  function formatDelta(diffCs) {
    if (!Number.isFinite(diffCs)) return '';
    if (diffCs === 0) return '= PB';
    const sign = diffCs > 0 ? '+' : '-';
    return `${sign}${(Math.abs(diffCs) / 100).toFixed(2)}s`;
  }

  function formatDateIt(isoDate) {
    if (!isoDate) return '—';
    const m = String(isoDate).match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (!m) return isoDate;
    return `${m[3]}/${m[2]}/${m[1]}`;
  }

  function formatDateShort(isoDate) {
    if (!isoDate) return '';
    const m = String(isoDate).match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (!m) return isoDate;
    return `${m[3]}/${m[2]}/${m[1].slice(2)}`;
  }

  function formatDateTimeIt(isoString) {
    if (!isoString) return '—';
    const d = new Date(isoString);
    if (Number.isNaN(d.getTime())) return isoString;
    return d.toLocaleString('it-IT', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  }

  function parseSwimTimeInput(raw) {
    const s = String(raw || '').trim().toUpperCase().replace(/[’′]/g, "'").replace(',', '.');
    const m = s.match(/^(\d{1,2})[:'.](\d{1,2})[."'](\d{1,2})$/);
    if (m) {
      const min = parseInt(m[1], 10);
      const sec = parseInt(m[2], 10);
      const cs = parseInt(m[3].padEnd(2, '0'), 10);
      if (sec < 60) {
        return `${String(min).padStart(2, '0')}'${String(sec).padStart(2, '0')}.${String(cs).padStart(2, '0')}`;
      }
    }
    const sOnly = s.match(/^(\d{1,3})\.(\d{1,2})$/);
    if (sOnly) {
      const totalSec = parseInt(sOnly[1], 10);
      const cs = parseInt(sOnly[2].padEnd(2, '0'), 10);
      const min = Math.floor(totalSec / 60);
      const sec = totalSec % 60;
      return `${String(min).padStart(2, '0')}'${String(sec).padStart(2, '0')}.${String(cs).padStart(2, '0')}`;
    }
    return null;
  }

  function compareEvents(a, b) {
    const da = parseInt((a.match(/\d+/) || ['9999'])[0], 10);
    const db = parseInt((b.match(/\d+/) || ['9999'])[0], 10);
    if (da !== db) return da - db;
    const la = a.toLowerCase();
    const lb = b.toLowerCase();
    const sa = STROKE_ORDER.findIndex((s) => la.includes(s));
    const sb = STROKE_ORDER.findIndex((s) => lb.includes(s));
    if (sa !== sb) return (sa === -1 ? 99 : sa) - (sb === -1 ? 99 : sb);
    return a.localeCompare(b, 'it');
  }

  function initialsOf(name) {
    const parts = String(name || '').trim().split(/\s+/).filter(Boolean);
    if (parts.length === 0) return '?';
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
    return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
  }

  /* ==================== CRYPTO (AES-256-CBC + HMAC-SHA256) ==================== */

  function base64ToBytes(b64) {
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  async function decryptEnvelope(envelope, password) {
    if (!window.crypto || !window.crypto.subtle) {
      throw new Error('WebCrypto non disponibile: apri la pagina tramite HTTPS o localhost (avvia-app.bat).');
    }
    const enc = new TextEncoder();
    const salt = base64ToBytes(envelope.salt);
    const iv = base64ToBytes(envelope.iv);
    const mac = base64ToBytes(envelope.mac);
    const ciphertext = base64ToBytes(envelope.ciphertext);

    const baseKey = await crypto.subtle.importKey(
      'raw',
      enc.encode(password),
      { name: 'PBKDF2' },
      false,
      ['deriveBits']
    );

    const bits = await crypto.subtle.deriveBits(
      {
        name: 'PBKDF2',
        salt,
        iterations: envelope.iterations || 150000,
        hash: 'SHA-256'
      },
      baseKey,
      512
    );

    const derived = new Uint8Array(bits);
    const encKeyBytes = derived.slice(0, 32);
    const macKeyBytes = derived.slice(32, 64);

    const macKey = await crypto.subtle.importKey(
      'raw',
      macKeyBytes,
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['verify']
    );

    const macInput = new Uint8Array(iv.length + ciphertext.length);
    macInput.set(iv, 0);
    macInput.set(ciphertext, iv.length);

    const valid = await crypto.subtle.verify('HMAC', macKey, mac, macInput);
    if (!valid) {
      throw new Error('Password di squadra non corretta.');
    }

    const encKey = await crypto.subtle.importKey(
      'raw',
      encKeyBytes,
      { name: 'AES-CBC' },
      false,
      ['decrypt']
    );

    const plainBuf = await crypto.subtle.decrypt(
      { name: 'AES-CBC', iv },
      encKey,
      ciphertext
    );

    const jsonText = new TextDecoder('utf-8').decode(plainBuf);
    return JSON.parse(jsonText);
  }

  /* ==================== PB & STATS ENGINE ==================== */

  function computeAthletePBs(results, poolFilter = 'ALL') {
    const filtered = results.filter(
      (r) => Number.isFinite(r.timeCs) && r.timeCs > 0 && (poolFilter === 'ALL' || r.pool === poolFilter)
    );
    const byEvent = new Map();
    for (const r of filtered) {
      if (!byEvent.has(r.event)) byEvent.set(r.event, []);
      byEvent.get(r.event).push(r);
    }

    const pbs = [];
    for (const [event, list] of byEvent.entries()) {
      const sortedByDate = [...list].sort((a, b) => (a.date || '').localeCompare(b.date || ''));
      let best = sortedByDate[0];
      let prevBestBeforePb = null;
      for (const item of sortedByDate) {
        if (item.timeCs < best.timeCs) {
          prevBestBeforePb = best.timeCs;
          best = item;
        }
      }
      const latest = sortedByDate[sortedByDate.length - 1];
      pbs.push({
        event,
        pbResult: best,
        pbCs: best.timeCs,
        pbFormatted: formatCentis(best.timeCs),
        improvementCs: prevBestBeforePb ? best.timeCs - prevBestBeforePb : null,
        latestResult: latest,
        count: sortedByDate.length,
        series: sortedByDate
      });
    }

    pbs.sort((a, b) => compareEvents(a.event, b.event));
    return pbs;
  }

  function buildDemoDataset(baseDataset) {
    const cloned = JSON.parse(JSON.stringify(baseDataset));
    const sampleAthletes = [];
    const seenCats = new Set();
    for (const a of cloned.athletes || []) {
      if (!seenCats.has(a.category)) {
        seenCats.add(a.category);
        sampleAthletes.push(a);
      } else if (sampleAthletes.length < 10) {
        sampleAthletes.push(a);
      }
    }

    const demoMeets = [
      { date: '2026-01-18', meet: 'I Tappa Inverno (Demo)', city: 'Torino', pool: '25m' },
      { date: '2026-02-22', meet: 'II Tappa Regionale (Demo)', city: 'Pinerolo', pool: '25m' },
      { date: '2026-03-29', meet: 'III Tappa Primavera (Demo)', city: 'Cuneo', pool: '25m' },
      { date: '2026-05-17', meet: 'Trofeo Estivo (Demo)', city: 'Torino', pool: '50m' }
    ];

    const demoEvents = [
      { event: '50 m Stile libero', baseCs: 3380 },
      { event: '50 m Dorso', baseCs: 3940 },
      { event: '100 m Misti', baseCs: 8120 }
    ];

    const demoResults = [...(cloned.results || [])];
    sampleAthletes.forEach((athlete, idx) => {
      const catBoost = idx * 140;
      demoEvents.forEach((ev, evIdx) => {
        if (idx % 2 === 1 && evIdx === 2) return;
        demoMeets.forEach((m, mIdx) => {
          const longPoolPenalty = m.pool === '50m' ? 110 : 0;
          const progress = mIdx === 0 ? 180 : mIdx === 1 ? 85 : mIdx === 2 ? -35 : 40;
          const cs = Math.max(2450, ev.baseCs + catBoost + progress + longPoolPenalty);
          demoResults.push({
            athleteId: athlete.id,
            date: m.date,
            meet: m.meet,
            city: m.city,
            pool: m.pool,
            event: ev.event,
            category: athlete.category,
            gender: athlete.gender,
            time: formatCentis(cs),
            timeCs: cs,
            status: 'OK',
            position: String((idx + mIdx) % 6 + 1),
            notes: mIdx === 2 ? 'Demo PB' : '',
            sourceType: 'demo',
            isLive: false
          });
        });
      });
    });

    cloned.results = demoResults;
    return cloned;
  }

  /* ==================== RENDERING ==================== */

  function renderApp() {
    const ds = state.activeDataset;
    if (!ds) return;

    els.clubTitle.textContent = ds.clubName || 'Dinamica Sport s.s.d. a r.l.';
    els.lastUpdatedText.textContent = `Aggiornato: ${formatDateTimeIt(ds.generatedAt)}`;

    if (state.demoMode) {
      els.demoToggleBtn.textContent = 'Esci da Demo';
      els.demoToggleBtn.classList.add('active-demo');
      els.statusBanner.textContent = 'MODALITÀ DEMO ATTIVA: stai visualizzando tempi simulati per provare PB e grafici. Clicca "Esci da Demo" per tornare ai dati reali.';
      els.statusBanner.className = 'banner banner-demo';
    } else {
      els.demoToggleBtn.textContent = 'Anteprima Demo';
      els.demoToggleBtn.classList.remove('active-demo');
      const resCount = (ds.results || []).length;
      const entCount = (ds.entries || []).length;
      if (resCount === 0) {
        els.statusBanner.innerHTML =
          `Ancora nessun risultato ufficiale pubblicato su <strong>nuotopiemonte-uisp.it</strong>. Sono già caricati <strong>${(ds.athletes || []).length} atleti</strong> per categoria e <strong>${entCount} iscrizioni</strong> in startlist. Usa <strong>Anteprima Demo</strong> in alto per provare subito PB e grafici!`;
        els.statusBanner.className = 'banner';
      } else {
        els.statusBanner.className = 'banner hidden';
      }
    }

    renderCategoryPills();
    renderAthletesView();
    renderRankingFilters();
    renderRankingView();
    renderCoachView();

    if (state.currentView === 'detail' && state.selectedAthleteId) {
      renderAthleteDetail(state.selectedAthleteId);
    }
    switchView(state.currentView);
  }

  function switchView(viewName) {
    state.currentView = viewName;
    els.viewAthletes.classList.toggle('hidden', viewName !== 'athletes');
    els.viewDetail.classList.toggle('hidden', viewName !== 'detail');
    els.viewRanking.classList.toggle('hidden', viewName !== 'ranking');
    els.viewCoach.classList.toggle('hidden', viewName !== 'coach');

    els.navTabs.forEach((tab) => {
      const target = tab.dataset.view;
      const isActive = target === viewName || (viewName === 'detail' && target === 'athletes');
      tab.classList.toggle('active', isActive);
    });
  }

  function getOrderedCategories(athletes) {
    const order = state.activeDataset?.categoryOrder || [];
    const cats = Array.from(new Set((athletes || []).map((a) => a.category || 'Altro')));
    cats.sort((a, b) => {
      const ia = order.indexOf(a);
      const ib = order.indexOf(b);
      if (ia !== -1 || ib !== -1) {
        return (ia === -1 ? 999 : ia) - (ib === -1 ? 999 : ib);
      }
      return a.localeCompare(b, 'it');
    });
    return cats;
  }

  function renderCategoryPills() {
    const athletes = state.activeDataset.athletes || [];
    const cats = getOrderedCategories(athletes);
    const counts = new Map();
    for (const a of athletes) {
      counts.set(a.category, (counts.get(a.category) || 0) + 1);
    }

    const pills = [
      `<button type="button" class="cat-pill ${state.selectedCategory === 'ALL' ? 'active' : ''}" data-cat="ALL">Tutte (${athletes.length})</button>`,
      ...cats.map(
        (c) =>
          `<button type="button" class="cat-pill ${state.selectedCategory === c ? 'active' : ''}" data-cat="${escapeHtml(c)}">${escapeHtml(c)} (${counts.get(c) || 0})</button>`
      )
    ];

    els.categoryPills.innerHTML = pills.join('');
    els.categoryPills.querySelectorAll('.cat-pill').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.selectedCategory = btn.dataset.cat;
        renderCategoryPills();
        renderAthletesView();
      });
    });
  }

  function renderAthletesView() {
    const ds = state.activeDataset;
    const q = state.searchQuery.trim().toLowerCase();
    const filtered = (ds.athletes || []).filter((a) => {
      if (state.selectedCategory !== 'ALL' && a.category !== state.selectedCategory) return false;
      if (state.selectedGender !== 'ALL' && a.gender !== state.selectedGender) return false;
      if (q) {
        const hay = `${a.name} ${a.birthYear || ''} ${a.category}`.toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });

    if (filtered.length === 0) {
      els.athletesContainer.innerHTML = '<div class="card empty-state">Nessun atleta trovato con i filtri selezionati.</div>';
      return;
    }

    const resByAthlete = new Map();
    for (const r of ds.results || []) {
      if (!resByAthlete.has(r.athleteId)) resByAthlete.set(r.athleteId, []);
      resByAthlete.get(r.athleteId).push(r);
    }

    const entByAthlete = new Map();
    for (const e of ds.entries || []) {
      if (!entByAthlete.has(e.athleteId)) entByAthlete.set(e.athleteId, []);
      entByAthlete.get(e.athleteId).push(e);
    }

    const grouped = new Map();
    for (const cat of getOrderedCategories(filtered)) {
      grouped.set(cat, []);
    }
    for (const a of filtered) {
      grouped.get(a.category || 'Altro').push(a);
    }

    const htmlParts = [];
    for (const [cat, list] of grouped.entries()) {
      if (list.length === 0) continue;
      const cardsHtml = list
        .map((a) => {
          const aRes = resByAthlete.get(a.id) || [];
          const aEnt = entByAthlete.get(a.id) || [];
          const pbs = computeAthletePBs(aRes);
          const avatarCls = a.gender === 'F' ? 'avatar-F' : a.gender === 'M' ? 'avatar-M' : 'avatar-X';
          let summaryText = '';
          if (pbs.length > 0) {
            const topPb = pbs[0];
            summaryText = `${pbs.length} PB · ${topPb.event}: ${topPb.pbFormatted}`;
          } else if (aEnt.length > 0) {
            summaryText = `${aEnt.length} gar${aEnt.length === 1 ? 'a' : 'e'} in startlist`;
          } else {
            summaryText = 'Nessuna gara registrata';
          }
          const yearTxt = a.birthYear ? ` · ${a.birthYear}` : '';
          const sexTxt = a.gender ? ` · ${a.gender}` : '';
          return `
            <button type="button" class="athlete-card" data-athlete-id="${escapeHtml(a.id)}">
              <div class="avatar ${avatarCls}">${escapeHtml(initialsOf(a.name))}</div>
              <div class="athlete-info">
                <div class="athlete-name">${escapeHtml(a.name)}</div>
                <div class="athlete-meta">${escapeHtml(a.category)}${escapeHtml(yearTxt)}${escapeHtml(sexTxt)}</div>
                <div class="athlete-summary">${escapeHtml(summaryText)}</div>
              </div>
            </button>
          `;
        })
        .join('');

      htmlParts.push(`
        <section class="category-section">
          <div class="category-heading">
            <h2>${escapeHtml(cat)}</h2>
            <span class="count-pill">${list.length} atlet${list.length === 1 ? 'a' : 'i'}</span>
          </div>
          <div class="athletes-grid">${cardsHtml}</div>
        </section>
      `);
    }

    els.athletesContainer.innerHTML = htmlParts.join('');
    els.athletesContainer.querySelectorAll('.athlete-card').forEach((card) => {
      card.addEventListener('click', () => {
        openAthleteDetail(card.dataset.athleteId);
      });
    });
  }

  function openAthleteDetail(athleteId) {
    state.selectedAthleteId = athleteId;
    state.selectedChartEvent = '';
    state.selectedChartPool = 'ALL';
    state.selectedSubtab = 'history';
    renderAthleteDetail(athleteId);
    switchView('detail');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function renderAthleteDetail(athleteId) {
    const ds = state.activeDataset;
    const athlete = (ds.athletes || []).find((a) => a.id === athleteId);
    if (!athlete) {
      switchView('athletes');
      return;
    }

    const aRes = (ds.results || []).filter((r) => r.athleteId === athleteId);
    const aEnt = (ds.entries || []).filter((e) => e.athleteId === athleteId);
    const pbs = computeAthletePBs(aRes);

    const subMeta = [
      athlete.category,
      athlete.birthYear ? `Anno ${athlete.birthYear}` : '',
      athlete.gender === 'F' ? 'Femmine' : athlete.gender === 'M' ? 'Maschi' : athlete.gender,
      athlete.tessera ? `Tessera ${athlete.tessera}` : ''
    ]
      .filter(Boolean)
      .join(' · ');

    els.athleteHeaderCard.innerHTML = `
      <div class="hero-main">
        <div>
          <h2>${escapeHtml(athlete.name)}</h2>
          <div class="hero-sub">${escapeHtml(subMeta)}</div>
        </div>
      </div>
      <div class="kpi-strip">
        <div class="kpi-box">
          <div class="kpi-val">${aRes.length}</div>
          <div class="kpi-lbl">Gare ufficiali</div>
        </div>
        <div class="kpi-box">
          <div class="kpi-val">${pbs.length}</div>
          <div class="kpi-lbl">Personal Best</div>
        </div>
        <div class="kpi-box">
          <div class="kpi-val">${aEnt.length}</div>
          <div class="kpi-lbl">Iscrizioni startlist</div>
        </div>
      </div>
    `;

    // Selettore gara per grafico
    const availableEvents = pbs.map((p) => p.event);
    if (availableEvents.length === 0) {
      els.athletePbList.innerHTML = '<div class="empty-state">Nessun risultato ufficiale ancora registrato per questo atleta.</div>';
      els.chartEventSelect.innerHTML = '<option value="">Nessuna gara</option>';
      els.chartPoolSelect.innerHTML = '<option value="ALL">Tutte</option>';
      els.chartStatsRow.innerHTML = '';
      els.chartContainer.innerHTML = '<div class="empty-state">Il grafico apparirà non appena verrà registrato almeno un tempo ufficiale.</div>';
      els.chartPointDetail.classList.add('hidden');
    } else {
      if (!state.selectedChartEvent || !availableEvents.includes(state.selectedChartEvent)) {
        state.selectedChartEvent = availableEvents[0];
      }

      els.athletePbList.innerHTML = pbs
        .map((pb) => {
          const isSelected = pb.event === state.selectedChartEvent;
          const impTxt = pb.improvementCs !== null ? `<div class="delta-good">${escapeHtml(formatDelta(pb.improvementCs))} sul prec. PB</div>` : '';
          return `
            <button type="button" class="pb-row ${isSelected ? 'selected' : ''}" data-pb-event="${escapeHtml(pb.event)}">
              <div>
                <div class="pb-event">${escapeHtml(pb.event)}</div>
                <div class="pb-meta">${escapeHtml(formatDateIt(pb.pbResult.date))} · ${escapeHtml(pb.pbResult.meet)} (${escapeHtml(pb.pbResult.pool)})</div>
              </div>
              <div class="pb-right">
                <span class="time-badge">${escapeHtml(pb.pbFormatted)}</span>
                ${impTxt}
              </div>
            </button>
          `;
        })
        .join('');

      els.athletePbList.querySelectorAll('.pb-row').forEach((btn) => {
        btn.addEventListener('click', () => {
          state.selectedChartEvent = btn.dataset.pbEvent;
          renderAthleteDetail(athleteId);
        });
      });

      els.chartEventSelect.innerHTML = availableEvents
        .map((ev) => `<option value="${escapeHtml(ev)}" ${ev === state.selectedChartEvent ? 'selected' : ''}>${escapeHtml(ev)}</option>`)
        .join('');

      const poolsForEvent = Array.from(
        new Set(aRes.filter((r) => r.event === state.selectedChartEvent && r.timeCs).map((r) => r.pool || '25m'))
      );
      const poolOpts = ['ALL', ...poolsForEvent];
      if (!poolOpts.includes(state.selectedChartPool)) state.selectedChartPool = 'ALL';
      els.chartPoolSelect.innerHTML = poolOpts
        .map((p) => `<option value="${escapeHtml(p)}" ${p === state.selectedChartPool ? 'selected' : ''}>${p === 'ALL' ? 'Tutte le vasche' : 'Vasca ' + p}</option>`)
        .join('');

      renderProgressionChart(aRes, state.selectedChartEvent, state.selectedChartPool);
    }

    renderAthleteSubtabs(aRes, aEnt, pbs);
  }

  function renderProgressionChart(athleteResults, eventName, poolFilter) {
    const series = athleteResults
      .filter(
        (r) =>
          r.event === eventName &&
          Number.isFinite(r.timeCs) &&
          r.timeCs > 0 &&
          (poolFilter === 'ALL' || r.pool === poolFilter)
      )
      .sort((a, b) => (a.date || '').localeCompare(b.date || ''));

    if (series.length === 0) {
      els.chartStatsRow.innerHTML = '';
      els.chartContainer.innerHTML = '<div class="empty-state">Nessun tempo valido per questa selezione.</div>';
      els.chartPointDetail.classList.add('hidden');
      return;
    }

    const pbItem = series.reduce((best, cur) => (cur.timeCs < best.timeCs ? cur : best), series[0]);
    const latest = series[series.length - 1];
    const first = series[0];
    const avgCs = Math.round(series.reduce((acc, s) => acc + s.timeCs, 0) / series.length);
    const totalProg = series.length > 1 ? latest.timeCs - first.timeCs : null;

    els.chartStatsRow.innerHTML = `
      <span class="stat-chip">PB: <strong>${escapeHtml(formatCentis(pbItem.timeCs))}</strong></span>
      <span class="stat-chip">Ultimo: <strong>${escapeHtml(formatCentis(latest.timeCs))}</strong></span>
      <span class="stat-chip">Media: <strong>${escapeHtml(formatCentis(avgCs))}</strong></span>
      ${totalProg !== null ? `<span class="stat-chip">Variazione 1ª→Ultima: <strong>${escapeHtml(formatDelta(totalProg))}</strong></span>` : ''}
    `;

    // Dimensioni logiche SVG
    const W = 620;
    const H = 270;
    const padL = 68;
    const padR = 24;
    const padT = 22;
    const padB = 42;
    const plotW = W - padL - padR;
    const plotH = H - padT - padB;

    const times = series.map((s) => s.timeCs);
    let minCs = Math.min(...times);
    let maxCs = Math.max(...times);
    const span = maxCs - minCs;
    const margin = span < 120 ? 100 : Math.round(span * 0.18);
    minCs = Math.max(0, minCs - margin);
    maxCs = maxCs + margin;
    const yRange = Math.max(100, maxCs - minCs);

    const xFor = (idx) => {
      if (series.length === 1) return padL + plotW / 2;
      return padL + (idx / (series.length - 1)) * plotW;
    };
    // Tempo piu' basso in basso (scala crescente)
    const yFor = (cs) => padT + ((maxCs - cs) / yRange) * plotH;

    // Griglia Y (5 tacche)
    const yTicks = 4;
    const gridLines = [];
    for (let i = 0; i <= yTicks; i++) {
      const ratio = i / yTicks;
      const valCs = Math.round(minCs + ratio * yRange);
      const y = yFor(valCs);
      gridLines.push(`
        <line x1="${padL}" y1="${y.toFixed(1)}" x2="${W - padR}" y2="${y.toFixed(1)}" stroke="#e2e8f0" stroke-width="1" />
        <text x="${padL - 8}" y="${(y + 4).toFixed(1)}" text-anchor="end" font-size="11" fill="#64748b" font-family="ui-monospace, monospace">${escapeHtml(formatCentis(valCs))}</text>
      `);
    }

    // Linea riferimento PB
    const pbY = yFor(pbItem.timeCs);
    const pbLineHtml = `
      <line x1="${padL}" y1="${pbY.toFixed(1)}" x2="${W - padR}" y2="${pbY.toFixed(1)}" stroke="#16a34a" stroke-width="1.5" stroke-dasharray="5 4" />
      <text x="${W - padR}" y="${Math.max(14, pbY - 5).toFixed(1)}" text-anchor="end" font-size="11" font-weight="700" fill="#15803d">PB ${escapeHtml(formatCentis(pbItem.timeCs))}</text>
    `;

    // Polilinea + area morbida
    const coords = series.map((item, idx) => ({ x: xFor(idx), y: yFor(item.timeCs), item, idx }));
    const pathD = coords.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(' ');

    // Etichette asse X (evita sovrapposizioni se tante gare)
    const step = series.length > 7 ? Math.ceil(series.length / 6) : 1;
    const xLabels = coords
      .filter((_, i) => i === 0 || i === coords.length - 1 || i % step === 0)
      .map(
        (p) => `<text x="${p.x.toFixed(1)}" y="${H - 14}" text-anchor="middle" font-size="11" fill="#64748b">${escapeHtml(formatDateShort(p.item.date))}</text>`
      )
      .join('');

    const pointsHtml = coords
      .map((p) => {
        const isPb = p.item === pbItem;
        const fill = isPb ? '#16a34a' : '#0284c7';
        const r = isPb ? 6.5 : 5;
        return `
          <g class="chart-pt" data-pt-idx="${p.idx}" style="cursor:pointer;">
            <circle cx="${p.x.toFixed(1)}" cy="${p.y.toFixed(1)}" r="14" fill="transparent" />
            <circle cx="${p.x.toFixed(1)}" cy="${p.y.toFixed(1)}" r="${r}" fill="${fill}" stroke="#ffffff" stroke-width="2" />
          </g>
        `;
      })
      .join('');

    els.chartContainer.innerHTML = `
      <svg class="swim-chart-svg" viewBox="0 0 ${W} ${H}" role="img" aria-label="Grafico andamento ${escapeHtml(eventName)}">
        ${gridLines.join('')}
        ${pbLineHtml}
        ${series.length > 1 ? `<path d="${pathD}" fill="none" stroke="#0284c7" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" />` : ''}
        ${xLabels}
        ${pointsHtml}
      </svg>
    `;

    const showPointDetail = (idx) => {
      const pt = series[idx];
      if (!pt) return;
      const diff = pt.timeCs - pbItem.timeCs;
      const diffLabel = diff === 0 ? 'Record Personale (PB)!' : `${formatDelta(diff)} dal PB`;
      const posTxt = pt.position ? ` · ${pt.position}° posto` : '';
      els.chartPointDetail.innerHTML = `
        <strong>${escapeHtml(formatDateIt(pt.date))}</strong> · ${escapeHtml(pt.meet)} (${escapeHtml(pt.pool)})<br>
        Tempo: <strong class="mono-time">${escapeHtml(pt.time)}</strong> (${escapeHtml(diffLabel)})${escapeHtml(posTxt)}
      `;
      els.chartPointDetail.classList.remove('hidden');
    };

    showPointDetail(series.length - 1);
    els.chartContainer.querySelectorAll('.chart-pt').forEach((node) => {
      node.addEventListener('click', () => showPointDetail(parseInt(node.dataset.ptIdx, 10)));
      node.addEventListener('mouseenter', () => showPointDetail(parseInt(node.dataset.ptIdx, 10)));
    });
  }

  function renderAthleteSubtabs(aRes, aEnt, pbs) {
    const pbKeys = new Set(pbs.map((p) => `${p.event}|${p.pbResult.date}|${p.pbResult.timeCs}`));

    els.subtabs.forEach((b) => b.classList.toggle('active', b.dataset.subtab === state.selectedSubtab));
    els.athleteHistoryPanel.classList.toggle('hidden', state.selectedSubtab !== 'history');
    els.athleteEntriesPanel.classList.toggle('hidden', state.selectedSubtab !== 'entries');

    const sortedRes = [...aRes].sort((a, b) => (b.date || '').localeCompare(a.date || '') || compareEvents(a.event, b.event));
    if (sortedRes.length === 0) {
      els.athleteHistoryPanel.innerHTML = '<div class="empty-state">Nessun risultato ufficiale registrato.</div>';
    } else {
      const rows = sortedRes
        .map((r) => {
          const isPb = r.timeCs && pbKeys.has(`${r.event}|${r.date}|${r.timeCs}`);
          return `
            <tr>
              <td>${escapeHtml(formatDateIt(r.date))}</td>
              <td>${escapeHtml(r.meet)}</td>
              <td>${escapeHtml(r.event)}</td>
              <td>${escapeHtml(r.pool || '25m')}</td>
              <td class="mono-time">
                ${escapeHtml(r.time || '—')}
                ${isPb ? '<span class="tag-pb">PB</span>' : ''}
                ${r.isLive ? '<span class="tag-live">LIVE</span>' : ''}
              </td>
              <td>${escapeHtml(r.position || '—')}</td>
            </tr>
          `;
        })
        .join('');
      els.athleteHistoryPanel.innerHTML = `
        <div class="table-wrap">
          <table class="data-table">
            <thead>
              <tr><th>Data</th><th>Manifestazione</th><th>Gara</th><th>Vasca</th><th>Tempo</th><th>Pos</th></tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        </div>
      `;
    }

    const sortedEnt = [...aEnt].sort((a, b) => (a.date || '').localeCompare(b.date || '') || compareEvents(a.event, b.event));
    if (sortedEnt.length === 0) {
      els.athleteEntriesPanel.innerHTML = '<div class="empty-state">Nessuna iscrizione attiva nelle startlist pubbliche.</div>';
    } else {
      const rows = sortedEnt
        .map(
          (e) => `
          <tr>
            <td>${escapeHtml(formatDateIt(e.date))}</td>
            <td>${escapeHtml(e.meet)}</td>
            <td>${escapeHtml(e.event)}</td>
            <td>${escapeHtml(e.category)}</td>
            <td class="mono-time">${escapeHtml(e.entryTime || 'S.T.')}</td>
          </tr>
        `
        )
        .join('');
      els.athleteEntriesPanel.innerHTML = `
        <div class="table-wrap">
          <table class="data-table">
            <thead>
              <tr><th>Data</th><th>Manifestazione</th><th>Gara</th><th>Categoria</th><th>Tempo Iscrizione</th></tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        </div>
      `;
    }
  }

  /* ==================== RANKING VIEW ==================== */

  function renderRankingFilters() {
    const ds = state.activeDataset;
    const events = Array.from(new Set((ds.results || []).filter((r) => r.timeCs).map((r) => r.event))).sort(compareEvents);
    const prevEvent = els.rankEventSelect.value;
    if (events.length === 0) {
      els.rankEventSelect.innerHTML = '<option value="">Nessuna gara con tempi</option>';
    } else {
      els.rankEventSelect.innerHTML = events
        .map((ev) => `<option value="${escapeHtml(ev)}" ${ev === prevEvent ? 'selected' : ''}>${escapeHtml(ev)}</option>`)
        .join('');
    }

    const cats = getOrderedCategories(ds.athletes || []);
    const prevCat = els.rankCategorySelect.value || 'ALL';
    els.rankCategorySelect.innerHTML = [
      `<option value="ALL" ${prevCat === 'ALL' ? 'selected' : ''}>Tutte le categorie</option>`,
      ...cats.map((c) => `<option value="${escapeHtml(c)}" ${c === prevCat ? 'selected' : ''}>${escapeHtml(c)}</option>`)
    ].join('');
  }

  function renderRankingView() {
    const ds = state.activeDataset;
    const selectedEvent = els.rankEventSelect.value;
    const selectedCat = els.rankCategorySelect.value || 'ALL';
    const selectedGender = els.rankGenderSelect.value || 'ALL';
    const selectedPool = els.rankPoolSelect.value || 'ALL';

    if (!selectedEvent) {
      els.rankCountLabel.textContent = '0 atleti';
      els.rankingTableWrap.innerHTML = '<div class="empty-state">Nessun risultato ufficiale disponibile per la classifica PB.</div>';
      return;
    }

    const athleteMap = new Map((ds.athletes || []).map((a) => [a.id, a]));
    const bestByAthlete = new Map();

    for (const r of ds.results || []) {
      if (r.event !== selectedEvent || !Number.isFinite(r.timeCs) || r.timeCs <= 0) continue;
      if (selectedPool !== 'ALL' && r.pool !== selectedPool) continue;
      const athlete = athleteMap.get(r.athleteId);
      if (!athlete) continue;
      if (selectedCat !== 'ALL' && athlete.category !== selectedCat) continue;
      if (selectedGender !== 'ALL' && athlete.gender !== selectedGender) continue;

      const cur = bestByAthlete.get(athlete.id);
      if (!cur || r.timeCs < cur.result.timeCs) {
        bestByAthlete.set(athlete.id, { athlete, result: r });
      }
    }

    const ranked = Array.from(bestByAthlete.values()).sort((a, b) => a.result.timeCs - b.result.timeCs);
    els.rankCountLabel.textContent = `${ranked.length} atlet${ranked.length === 1 ? 'a' : 'i'}`;

    if (ranked.length === 0) {
      els.rankingTableWrap.innerHTML = '<div class="empty-state">Nessun tempo registrato per questa combinazione di filtri.</div>';
      return;
    }

    const rows = ranked
      .map(
        (item, idx) => `
        <tr>
          <td><strong>#${idx + 1}</strong></td>
          <td><button type="button" class="link-btn" data-rank-athlete="${escapeHtml(item.athlete.id)}">${escapeHtml(item.athlete.name)}</button></td>
          <td>${escapeHtml(item.athlete.category)}</td>
          <td>${escapeHtml(item.athlete.birthYear || '—')}</td>
          <td class="mono-time"><span class="time-badge">${escapeHtml(formatCentis(item.result.timeCs))}</span></td>
          <td>${escapeHtml(item.result.pool || '25m')}</td>
          <td>${escapeHtml(formatDateIt(item.result.date))} · ${escapeHtml(item.result.meet)}</td>
        </tr>
      `
      )
      .join('');

    els.rankingTableWrap.innerHTML = `
      <table class="data-table">
        <thead>
          <tr><th>#</th><th>Atleta</th><th>Categoria</th><th>Anno</th><th>Personal Best</th><th>Vasca</th><th>Gara</th></tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    `;

    els.rankingTableWrap.querySelectorAll('[data-rank-athlete]').forEach((btn) => {
      btn.addEventListener('click', () => openAthleteDetail(btn.dataset.rankAthlete));
    });
  }

  /* ==================== COACH VIEW ==================== */

  function renderCoachView() {
    const ds = state.activeDataset;
    els.athletesDatalist.innerHTML = (ds.athletes || [])
      .map((a) => `<option value="${escapeHtml(a.name)}">`)
      .join('');

    const relays = ds.relays || [];
    if (relays.length === 0) {
      els.relaysBox.innerHTML = '<p class="muted-small">Nessuna staffetta ufficiale registrata al momento.</p>';
    } else {
      els.relaysBox.innerHTML = `
        <h3>Staffette ufficiali</h3>
        <div class="table-wrap">
          <table class="data-table">
            <thead><tr><th>Data</th><th>Gara</th><th>Categoria</th><th>Formazione</th><th>Tempo</th></tr></thead>
            <tbody>
              ${relays
                .map(
                  (rel) => `
                <tr>
                  <td>${escapeHtml(formatDateIt(rel.date))}</td>
                  <td>${escapeHtml(rel.event)}</td>
                  <td>${escapeHtml(rel.category)}</td>
                  <td>${escapeHtml(rel.teamLabel)}</td>
                  <td class="mono-time">${escapeHtml(rel.time || '—')}</td>
                </tr>
              `
                )
                .join('')}
            </tbody>
          </table>
        </div>
      `;
    }
  }

  /* ==================== AUTH & INIT ==================== */

  function savePassword(pw) {
    try {
      if (els.rememberPw.checked) {
        localStorage.setItem(STORAGE_KEY, pw);
      } else {
        sessionStorage.setItem(STORAGE_KEY, pw);
      }
    } catch (_) {}
  }

  function loadSavedPassword() {
    try {
      return localStorage.getItem(STORAGE_KEY) || sessionStorage.getItem(STORAGE_KEY) || '';
    } catch (_) {
      return '';
    }
  }

  function clearSavedPassword() {
    try {
      localStorage.removeItem(STORAGE_KEY);
      sessionStorage.removeItem(STORAGE_KEY);
    } catch (_) {}
  }

  async function tryUnlock(password) {
    els.authError.classList.add('hidden');
    if (!state.envelope) {
      const resp = await fetch(`${DATA_URL}?ts=${Date.now()}`, { cache: 'no-store' });
      if (!resp.ok) throw new Error(`Impossibile caricare il file dati (${resp.status}).`);
      state.envelope = await resp.json();
    }

    const decrypted = await decryptEnvelope(state.envelope, password);
    state.realDataset = decrypted;
    state.activeDataset = decrypted;
    state.demoMode = false;
    savePassword(password);

    els.authScreen.classList.add('hidden');
    els.appShell.classList.remove('hidden');
    renderApp();
  }

  function showAuthError(msg) {
    els.authError.textContent = msg;
    els.authError.classList.remove('hidden');
  }

  function bindEvents() {
    els.togglePwBtn.addEventListener('click', () => {
      const isPw = els.passwordInput.type === 'password';
      els.passwordInput.type = isPw ? 'text' : 'password';
      els.togglePwBtn.textContent = isPw ? 'Nascondi' : 'Mostra';
    });

    els.authForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const pw = els.passwordInput.value;
      if (!pw) return;
      els.unlockBtn.disabled = true;
      els.unlockBtn.textContent = 'Verifica in corso...';
      try {
        await tryUnlock(pw);
      } catch (err) {
        showAuthError(err.message || 'Errore durante la verifica della password.');
        if (window.location.protocol === 'file:') {
          els.localFallback.classList.remove('hidden');
        }
      } finally {
        els.unlockBtn.disabled = false;
        els.unlockBtn.textContent = 'Accedi ai risultati';
      }
    });

    els.manualEncFile.addEventListener('change', async (e) => {
      const file = e.target.files?.[0];
      if (!file) return;
      try {
        state.envelope = JSON.parse(await file.text());
        els.authError.classList.add('hidden');
      } catch (_) {
        showAuthError('File JSON non valido.');
      }
    });

    els.logoutBtn.addEventListener('click', () => {
      clearSavedPassword();
      state.realDataset = null;
      state.activeDataset = null;
      state.demoMode = false;
      els.passwordInput.value = '';
      els.appShell.classList.add('hidden');
      els.authScreen.classList.remove('hidden');
    });

    els.demoToggleBtn.addEventListener('click', () => {
      if (!state.realDataset) return;
      state.demoMode = !state.demoMode;
      state.activeDataset = state.demoMode ? buildDemoDataset(state.realDataset) : state.realDataset;
      renderApp();
    });

    els.navTabs.forEach((tab) => {
      tab.addEventListener('click', () => {
        switchView(tab.dataset.view);
      });
    });

    els.athleteSearch.addEventListener('input', (e) => {
      state.searchQuery = e.target.value;
      renderAthletesView();
    });

    els.genderFilter.addEventListener('change', (e) => {
      state.selectedGender = e.target.value;
      renderAthletesView();
    });

    els.backToAthletes.addEventListener('click', () => switchView('athletes'));

    els.chartEventSelect.addEventListener('change', (e) => {
      state.selectedChartEvent = e.target.value;
      renderAthleteDetail(state.selectedAthleteId);
    });

    els.chartPoolSelect.addEventListener('change', (e) => {
      state.selectedChartPool = e.target.value;
      renderAthleteDetail(state.selectedAthleteId);
    });

    els.subtabs.forEach((btn) => {
      btn.addEventListener('click', () => {
        state.selectedSubtab = btn.dataset.subtab;
        renderAthleteDetail(state.selectedAthleteId);
      });
    });

    [els.rankEventSelect, els.rankCategorySelect, els.rankGenderSelect, els.rankPoolSelect].forEach((sel) => {
      sel.addEventListener('change', renderRankingView);
    });

    els.manualCsvForm.addEventListener('submit', (e) => {
      e.preventDefault();
      const nameRaw = document.getElementById('m-athlete').value.trim();
      const dateRaw = document.getElementById('m-date').value;
      const evRaw = document.getElementById('m-event').value.trim();
      const timeRaw = document.getElementById('m-time').value.trim();
      const meetRaw = document.getElementById('m-meet').value.trim();
      const poolRaw = document.getElementById('m-pool').value;

      const normTime = parseSwimTimeInput(timeRaw);
      if (!normTime) {
        alert("Formato tempo non valido. Usa il formato xx'xx.xx (es. 00'34.50 o 01'12.40).");
        return;
      }

      const matchedAthlete = (state.realDataset?.athletes || []).find(
        (a) => a.name.toLowerCase() === nameRaw.toLowerCase()
      );
      const year = matchedAthlete?.birthYear || '';
      const gender = matchedAthlete?.gender || '';
      const cat = matchedAthlete?.category || '';
      const tessera = matchedAthlete?.tessera || '';

      const row = `${nameRaw.toUpperCase()};${year};${gender};${cat};${tessera};${dateRaw};${meetRaw};;${poolRaw};${evRaw};${normTime};;`;
      els.csvOutputBox.value = row;
      els.csvOutputWrap.classList.remove('hidden');
    });

    els.copyCsvBtn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(els.csvOutputBox.value);
        els.copyCsvBtn.textContent = 'Copiata!';
        setTimeout(() => {
          els.copyCsvBtn.textContent = 'Copia negli appunti';
        }, 1500);
      } catch (_) {
        els.csvOutputBox.select();
      }
    });
  }

  async function init() {
    bindEvents();
    if (window.location.protocol === 'file:') {
      els.localFallback.classList.remove('hidden');
    }
    const saved = loadSavedPassword();
    if (saved) {
      els.passwordInput.value = saved;
      try {
        await tryUnlock(saved);
      } catch (_) {
        clearSavedPassword();
      }
    }
  }

  init();
})();

