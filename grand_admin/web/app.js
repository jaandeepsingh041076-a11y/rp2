/* resources/[grand_systems]/grand_admin/web/app.js
 * NUI controller for the Grand RP admin panel.
 *
 * Runs in two modes:
 *   1. FiveM NUI  — real callbacks over https://grand_admin/<name>
 *   2. Browser    — mock harness, triggered by ?preview=1 or by the absence
 *                   of window.GetParentResourceName. Used for design review.
 */

(function () {
  'use strict';

  const RESOURCE =
    typeof window.GetParentResourceName === 'function'
      ? window.GetParentResourceName()
      : 'grand_admin';

  const isBrowserPreview =
    typeof window.GetParentResourceName !== 'function' ||
    new URLSearchParams(window.location.search).has('preview');

  // ------------------------------------------------------------------------
  // State
  // ------------------------------------------------------------------------

  const state = {
    open: false,
    players: [],
    vehicles: {},
    selectedVehicle: null,
    vehicleCategory: 'Cars',
    spectating: null,
    fullAccess: false,
    adminName: 'Staff',
    noclipSpeed: 3,
    settings: {
      autoRefresh: true,
      notifications: true,
    },
  };

  // ------------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------------

  const $ = (id) => document.getElementById(id);

  function money(value) {
    const n = Math.floor(Number(value) || 0);
    return '$' + n.toLocaleString('en-US');
  }

  function pad(n) {
    return String(n).padStart(2, '0');
  }

  function clock(seconds) {
    const s = Math.max(0, Math.floor(seconds));
    return pad(Math.floor(s / 3600)) + ':' + pad(Math.floor((s % 3600) / 60)) + ':' + pad(s % 60);
  }

  function escapeHtml(value) {
    return String(value === undefined || value === null ? '' : value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  /** Posts a callback to the client script. No-ops in preview mode. */
  function post(name, payload) {
    if (isBrowserPreview) {
      return Promise.resolve(mockCallback(name, payload || {}));
    }

    return fetch(`https://${RESOURCE}/${name}`, {
      type: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(payload || {}),
    })
      .then((res) => (res.ok ? res.json() : null))
      .catch(() => null);
  }

  const LAW_JOBS = ['police', 'sheriff', 'ambulance', 'doc', 'fib', 'state', 'sa_hp', 'paramedic'];
  const ILLEGAL_JOBS = [
    'gang', 'gang2', 'gang3', 'gang4', 'gang5', 'scrap', 'drugdealer',
    'gunrunner', 'mechanic_black', 'tokyo', 'cartel', 'mobster',
  ];

  function jobClass(job) {
    const key = String(job || '').toLowerCase();
    if (LAW_JOBS.includes(key)) return 'grp-job-law';
    if (ILLEGAL_JOBS.includes(key)) return 'grp-job-illegal';
    return '';
  }

  // ------------------------------------------------------------------------
  // Toasts
  // ------------------------------------------------------------------------

  function toast(message, type) {
    if (!state.settings.notifications) return;

    const area = $('grp-notification-area');
    if (!area) return;

    const el = document.createElement('div');
    el.className = 'grp-toast grp-toast--' + (type || 'info');
    el.textContent = message;
    area.appendChild(el);

    setTimeout(() => {
      el.classList.add('hiding');
      setTimeout(() => el.remove(), 220);
    }, 3600);

    while (area.children.length > 5) {
      area.firstChild.remove();
    }
  }

  /** Unified result handler so every action reports the same way. */
  function handleResult(result, fallbackMessage) {
    if (!result) {
      toast(fallbackMessage || 'No response from server', 'error');
      return false;
    }

    if (result.success) {
      if (result.message) toast(result.message, 'success');
      return true;
    }

    toast(result.message || fallbackMessage || 'Action failed', 'error');
    return false;
  }

  // ------------------------------------------------------------------------
  // Player roster
  // ------------------------------------------------------------------------

  function renderPlayers() {
    const body = $('grp-players-list');
    if (!body) return;

    const term = ($('grp-player-search')?.value || '').toLowerCase().trim();

    const rows = state.players.filter((p) => {
      if (!term) return true;
      return (
        String(p.source).includes(term) ||
        (p.name || '').toLowerCase().includes(term) ||
        (p.citizenid || '').toLowerCase().includes(term) ||
        (p.job || '').toLowerCase().includes(term) ||
        (p.account || '').toLowerCase().includes(term)
      );
    });

    if (!rows.length) {
      body.innerHTML =
        '<tr><td colspan="8" class="grp-empty">No players match this filter</td></tr>';
    } else {
      body.innerHTML = rows
        .map((p) => {
          const src = Number(p.source);
          return `<tr>
            <td class="grp-cell-id">${pad(src)}</td>
            <td class="grp-cell-name">${escapeHtml(p.name || p.account || 'Unknown')}</td>
            <td class="grp-cell-citizen">${escapeHtml(p.citizenid || '—')}</td>
            <td><span class="grp-cell-job ${jobClass(p.job)}"><span>${escapeHtml(
            (p.job || 'unemployed').toUpperCase(),
          )}</span></span></td>
            <td class="grp-cell-level">${Number(p.level) || 1}</td>
            <td class="grp-cell-cash">${money(p.cash)}</td>
            <td class="grp-cell-bank">${money(p.bank)}</td>
            <td>
              <div class="grp-row-actions">
                <button class="grp-mini-btn" data-act="tp" data-id="${src}">TP</button>
                <button class="grp-mini-btn" data-act="bring" data-id="${src}">BRING</button>
                <button class="grp-mini-btn" data-act="spec" data-id="${src}">SPECTATE</button>
                <button class="grp-mini-btn grp-mini-danger" data-act="kick" data-id="${src}">KICK</button>
                <button class="grp-mini-btn grp-mini-danger" data-act="ban" data-id="${src}">BAN</button>
              </div>
            </td>
          </tr>`;
        })
        .join('');
    }

    const count = $('grp-player-count');
    if (count) count.textContent = String(state.players.length);

    syncPlayerSelects();
  }

  function syncPlayerSelects() {
    ['grp-spectate-player', 'grp-teleport-player'].forEach((id) => {
      const select = $(id);
      if (!select) return;

      const previous = select.value;
      select.innerHTML =
        '<option value="">' +
        (id === 'grp-teleport-player' ? 'Select Player' : 'Select Player to Spectate') +
        '</option>' +
        state.players
          .map(
            (p) =>
              `<option value="${Number(p.source)}">${pad(Number(p.source))} — ${escapeHtml(
                p.name || p.account || 'Unknown',
              )}</option>`,
          )
          .join('');

      if (previous) select.value = previous;
    });
  }

  function findPlayer(source) {
    const id = Number(source);
    return state.players.find((p) => Number(p.source) === id) || null;
  }

  // ------------------------------------------------------------------------
  // Vehicle spawner
  // ------------------------------------------------------------------------

  function vehicleName(model) {
    return String(model)
      .replace(/[_-]+/g, ' ')
      .replace(/\b\w/g, (c) => c.toUpperCase())
      .trim();
  }

  function renderVehicles() {
    const grid = $('grp-vehicle-grid');
    if (!grid) return;

    const term = ($('grp-vehicle-search')?.value || '').toLowerCase().trim();
    const list = state.vehicles[state.vehicleCategory] || [];

    const filtered = list.filter(
      (model) => !term || String(model).toLowerCase().includes(term),
    );

    if (!filtered.length) {
      grid.innerHTML = '<div class="grp-empty">No vehicles in this category</div>';
      return;
    }

    grid.innerHTML = filtered
      .map(
        (model) => `<button class="grp-vehicle-card grp-skew${
          state.selectedVehicle === model ? ' selected' : ''
        }" data-model="${escapeHtml(model)}">
            <span class="grp-vehicle-cat">${escapeHtml(state.vehicleCategory).toUpperCase()}</span>
            <span class="grp-vehicle-name">${escapeHtml(vehicleName(model))}</span>
            <span class="grp-vehicle-model">${escapeHtml(model)}</span>
          </button>`,
      )
      .join('');
  }

  // ------------------------------------------------------------------------
  // Admin state
  // ------------------------------------------------------------------------

  function applyState(payload) {
    if (!payload) return;

    if (payload.name) {
      state.adminName = payload.name;
      const label = $('grp-admin-name');
      if (label) label.textContent = payload.name;
    }

    if (typeof payload.full === 'boolean') state.fullAccess = payload.full;

    if (payload.godmode !== undefined) setStateIndicator('grp-godmode-indicator', payload.godmode);
    if (payload.noclip !== undefined) setStateIndicator('grp-noclip-indicator', payload.noclip);
    if (payload.spectating !== undefined)
      setStateIndicator('grp-spectate-indicator', Boolean(payload.spectating));

    if (payload.godmode !== undefined) setActionState('grp-toggle-godmode', payload.godmode);
    if (payload.noclip !== undefined) setActionState('grp-toggle-noclip', payload.noclip);

    if (payload.spectating !== undefined) {
      state.spectating = payload.spectating;
      const start = $('grp-start-spectate');
      const stop = $('grp-stop-spectate');
      if (start) start.disabled = Boolean(payload.spectating);
      if (stop) stop.disabled = !payload.spectating;
    }

    if (payload.noclipSpeed !== undefined) {
      state.noclipSpeed = Number(payload.noclipSpeed) || 3;
      const slider = $('grp-noclip-speed');
      const value = $('grp-noclip-speed-value');
      if (slider) slider.value = String(state.noclipSpeed);
      if (value) value.textContent = String(state.noclipSpeed);
    }
  }

  function setStateIndicator(id, on) {
    const el = $(id);
    if (el) el.dataset.status = on ? 'on' : 'off';
  }

  function setActionState(id, on) {
    const el = $(id);
    if (!el) return;
    el.dataset.state = on ? 'on' : 'off';
    const status = el.querySelector('.grp-action-status');
    if (status) status.textContent = on ? 'ON' : 'OFF';
  }

  // ------------------------------------------------------------------------
  // Tabs and modals
  // ------------------------------------------------------------------------

  function switchTab(tabId) {
    document.querySelectorAll('.grp-tab').forEach((tab) => {
      tab.classList.toggle('active', tab.id === tabId);
    });

    document.querySelectorAll('.grp-nav-btn').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.tab === tabId);
    });

    if (tabId === 'grp-players' || tabId === 'grp-vehicles') loadPlayers();
    if (tabId === 'grp-vehicles') loadVehicles();
    if (tabId === 'grp-settings') loadServerInfo();
  }

  function openModal(id) {
    const modal = $(id);
    if (modal) modal.classList.add('open');
  }

  function closeModals() {
    document.querySelectorAll('.grp-modal').forEach((m) => m.classList.remove('open'));
  }

  // ------------------------------------------------------------------------
  // Data loading
  // ------------------------------------------------------------------------

  function loadPlayers() {
    return post('getPlayers', {}).then((res) => {
      const list = (res && (res.data || res.players)) || [];
      if (Array.isArray(list)) {
        state.players = list;
        renderPlayers();
      }
    });
  }

  function loadVehicles() {
    return post('getVehicleCategories', {}).then((res) => {
      const data = (res && (res.data || res.categories)) || null;
      if (data && Object.keys(data).length) {
        state.vehicles = data;
        renderVehicles();
      }
    });
  }

  function loadServerInfo() {
    return post('getServerInfo', {}).then((res) => {
      const info = (res && res.data) || res || {};
      const count = $('grp-server-player-count');
      const uptime = $('grp-server-uptime');
      if (count && info.players !== undefined) count.textContent = String(info.players);
      if (uptime && info.uptime !== undefined) uptime.textContent = clock(info.uptime);
    });
  }

  // ------------------------------------------------------------------------
  // Message dispatcher (client -> NUI)
  // ------------------------------------------------------------------------

  const handlers = {
    open(payload) {
      state.open = true;
      document.querySelector('.grp-container').classList.add('visible');
      applyState(payload);
      loadPlayers();
      loadVehicles();
    },

    close() {
      state.open = false;
      document.querySelector('.grp-container').classList.remove('visible');
      closeModals();
    },

    players(payload) {
      if (Array.isArray(payload.data)) {
        state.players = payload.data;
        renderPlayers();
      }
    },

    vehicles(payload) {
      if (payload.data && Object.keys(payload.data).length) {
        state.vehicles = payload.data;
        renderVehicles();
      }
    },

    state(payload) {
      applyState(payload);
    },

    notify(payload) {
      toast(payload.message, payload.type || 'info');
    },

    spectateStopped() {
      applyState({ spectating: null });
      toast('Spectate target left the session', 'warning');
    },
  };

  window.addEventListener('message', (event) => {
    const data = event.data || {};
    const handler = handlers[data.action];
    if (handler) handler(data);
  });

  // Escape closes modals first, then the panel.
  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;

    if (document.querySelector('.grp-modal.open')) {
      closeModals();
      return;
    }

    if (state.open && !isBrowserPreview) post('closeMenu', {});
  });

  // ------------------------------------------------------------------------
  // Wiring
  // ------------------------------------------------------------------------

  function bind() {
    document.querySelectorAll('.grp-nav-btn').forEach((btn) => {
      btn.addEventListener('click', () => switchTab(btn.dataset.tab));
    });

    $('grp-close-menu')?.addEventListener('click', () => {
      if (isBrowserPreview) {
        document.querySelector('.grp-container').classList.remove('visible');
        setTimeout(() => document.querySelector('.grp-container').classList.add('visible'), 500);
        return;
      }
      post('closeMenu', {});
    });

    $('grp-player-search')?.addEventListener('input', renderPlayers);
    $('grp-vehicle-search')?.addEventListener('input', renderVehicles);

    $('grp-refresh-players')?.addEventListener('click', () => {
      loadPlayers();
      toast('Player list refreshed', 'info');
    });

    // Row actions are delegated because rows are rebuilt on every refresh.
    $('grp-players-list')?.addEventListener('click', (event) => {
      const btn = event.target.closest('[data-act]');
      if (!btn) return;

      const src = Number(btn.dataset.id);
      const player = findPlayer(src);
      const name = player ? player.name || player.account : 'Player ' + src;

      switch (btn.dataset.act) {
        case 'tp':
          post('teleportToPlayer', { target: src });
          break;
        case 'bring':
          post('bringPlayer', { target: src }).then((r) => handleResult(r, 'Could not bring player'));
          break;
        case 'spec':
          post('spectatePlayer', { target: src }).then((r) => {
            if (handleResult(r, 'Spectate failed')) applyState({ spectating: src });
          });
          break;
        case 'kick':
          $('grp-kick-player-name').textContent = pad(src) + ' — ' + name;
          $('grp-kick-reason').value = '';
          pendingTarget = { source: src, name };
          openModal('grp-kick-modal');
          break;
        case 'ban':
          $('grp-ban-player-name').textContent = pad(src) + ' — ' + name;
          $('grp-ban-reason').value = '';
          $('grp-ban-duration').value = '0';
          pendingTarget = { source: src, name };
          openModal('grp-ban-modal');
          break;
      }
    });

    // Vehicle selection
    $('grp-vehicle-grid')?.addEventListener('click', (event) => {
      const card = event.target.closest('[data-model]');
      if (!card) return;

      state.selectedVehicle = card.dataset.model;
      document.querySelectorAll('.grp-vehicle-card').forEach((c) => {
        c.classList.toggle('selected', c.dataset.model === state.selectedVehicle);
      });
    });

    $('grp-vehicle-category')?.addEventListener('change', (event) => {
      state.vehicleCategory = event.target.value;
      state.selectedVehicle = null;
      renderVehicles();
    });

    $('grp-spawn-vehicle')?.addEventListener('click', () => {
      if (!state.selectedVehicle) {
        toast('Select a vehicle first', 'warning');
        return;
      }

      post('spawnVehicle', { model: state.selectedVehicle }).then((res) => {
        if (!handleResult(res, 'Vehicle request sent')) return;
        if (isBrowserPreview) toast('Preview: ' + vehicleName(state.selectedVehicle) + ' spawned', 'success');
      });
    });

    $('grp-delete-vehicle')?.addEventListener('click', () => {
      post('deleteCurrentVehicle', {}).then((r) => handleResult(r, 'Nothing to delete'));
    });

    // Self actions
    $('grp-toggle-godmode')?.addEventListener('click', () => {
      post('toggleGodmode', {}).then((r) => handleResult(r, 'Godmode toggled'));
    });

    $('grp-toggle-noclip')?.addEventListener('click', () => {
      post('toggleNoclip', {}).then((r) => handleResult(r, 'Noclip toggled'));
    });

    $('grp-toggle-invisible')?.addEventListener('click', (event) => {
      const on = event.currentTarget.dataset.state !== 'on';
      event.currentTarget.dataset.state = on ? 'on' : 'off';
      post('setInvisible', { state: on }).then((r) => handleResult(r, 'Visibility updated'));
    });

    $('grp-heal-self')?.addEventListener('click', () => {
      post('healSelf', { armor: false }).then((r) => handleResult(r, 'Health restored'));
    });

    $('grp-armor-self')?.addEventListener('click', () => {
      post('healSelf', { armor: true }).then((r) => handleResult(r, 'Armour restored'));
    });

    $('grp-start-spectate')?.addEventListener('click', () => {
      const target = Number($('grp-spectate-player').value);
      if (!target) {
        toast('Choose a player to spectate', 'warning');
        return;
      }
      post('spectatePlayer', { target }).then((r) => {
        if (handleResult(r, 'Spectating')) applyState({ spectating: target });
      });
    });

    $('grp-stop-spectate')?.addEventListener('click', () => {
      post('stopSpectating', {}).then((r) => {
        if (handleResult(r, 'Stopped spectating')) applyState({ spectating: null });
      });
    });

    // Teleport
    $('grp-teleport-to-player')?.addEventListener('click', () => {
      const target = Number($('grp-teleport-player').value);
      if (!target) {
        toast('Choose a destination player', 'warning');
        return;
      }
      post('teleportToPlayer', { target }).then((r) => handleResult(r, 'Teleported'));
    });

    $('grp-teleport-to-coords')?.addEventListener('click', () => {
      const x = parseFloat($('grp-coord-x').value);
      const y = parseFloat($('grp-coord-y').value);
      const z = parseFloat($('grp-coord-z').value);

      if ([x, y, z].some((v) => Number.isNaN(v))) {
        toast('Enter all three coordinates', 'warning');
        return;
      }

      if (Math.abs(x) > 9999 || Math.abs(y) > 9999 || Math.abs(z) > 1200) {
        toast('Coordinates out of bounds', 'error');
        return;
      }

      post('teleportToCoords', { x, y, z }).then((r) => handleResult(r, 'Teleported'));
    });

    $('grp-teleport-to-waypoint')?.addEventListener('click', () => {
      post('teleportToWaypoint', {}).then((r) => handleResult(r, 'Teleported to waypoint'));
    });

    $('grp-teleport-to-pd')?.addEventListener('click', () => {
      post('teleportToCoords', { x: 453.38, y: -981.42, z: 29.69 }).then((r) =>
        handleResult(r, 'Teleported to Mission Row'),
      );
    });

    $('grp-teleport-to-hospital')?.addEventListener('click', () => {
      post('teleportToCoords', { x: 298.56, y: -584.81, z: 43.26 }).then((r) =>
        handleResult(r, 'Teleported to Pillbox'),
      );
    });

    // Settings
    $('grp-noclip-speed')?.addEventListener('input', (event) => {
      const value = Number(event.target.value);
      $('grp-noclip-speed-value').textContent = String(value);
      state.noclipSpeed = value;
    });

    $('grp-noclip-speed')?.addEventListener('change', () => {
      post('setNoclipSpeed', { value: state.noclipSpeed }).then((r) =>
        handleResult(r, 'Noclip speed set to ' + state.noclipSpeed),
      );
    });

    $('grp-auto-refresh')?.addEventListener('change', (event) => {
      state.settings.autoRefresh = event.target.checked;
    });

    $('grp-show-notifications')?.addEventListener('change', (event) => {
      state.settings.notifications = event.target.checked;
    });

    // Modals
    document.querySelectorAll('.grp-close-modal').forEach((btn) => {
      btn.addEventListener('click', closeModals);
    });

    document.querySelectorAll('.grp-modal').forEach((modal) => {
      modal.addEventListener('click', (event) => {
        if (event.target === modal) closeModals();
      });
    });

    $('grp-confirm-kick')?.addEventListener('click', () => {
      if (!pendingTarget) return;
      const reason = $('grp-kick-reason').value.trim() || 'No reason provided';

      post('kickPlayer', { target: pendingTarget.source, reason }).then((r) => {
        handleResult(r, 'Player kicked');
        closeModals();
        loadPlayers();
      });
    });

    $('grp-confirm-ban')?.addEventListener('click', () => {
      if (!pendingTarget) return;
      const reason = $('grp-ban-reason').value.trim() || 'No reason provided';
      const duration = Math.max(0, parseInt($('grp-ban-duration').value, 10) || 0);

      post('banPlayer', { target: pendingTarget.source, reason, duration }).then((r) => {
        handleResult(r, 'Player banned');
        closeModals();
        loadPlayers();
      });
    });
  }

  let pendingTarget = null;

  // ------------------------------------------------------------------------
  // Clock + auto refresh
  // ------------------------------------------------------------------------

  function startTimers() {
    const serverTime = $('grp-server-time');

    setInterval(() => {
      const now = new Date();
      const hhmmss = pad(now.getHours()) + ':' + pad(now.getMinutes()) + ':' + pad(now.getSeconds());

      if ($('grp-clock-time')) $('grp-clock-time').textContent = hhmmss;
      if (serverTime) serverTime.textContent = hhmmss;
    }, 1000);

    setInterval(() => {
      if (state.open && state.settings.autoRefresh) loadPlayers();
    }, 8000);
  }

  // ------------------------------------------------------------------------
  // Browser preview harness
  // ------------------------------------------------------------------------

  const PREVIEW_PLAYERS = [
    { source: 1, name: 'Aman Vlahovic', account: 'Aman', citizenid: 'GRI48KQ2A', job: 'police', level: 42, cash: 28450, bank: 1840200, ping: 24 },
    { source: 2, name: 'Eni Korica', account: 'eni', citizenid: 'GR77PLM1Q', job: 'ambulance', level: 31, cash: 120750, bank: 420900, ping: 31 },
    { source: 3, name: 'Dario Nikolov', account: 'dario', citizenid: 'GR91XZT4B', job: 'gang', level: 18, cash: 4020, bank: 88400, ping: 58 },
    { source: 4, name: 'Viktor Ilievski', account: 'viktor', citizenid: 'GR03QKD7C', job: 'taxi', level: 7, cash: 1980, bank: 12400, ping: 12 },
    { source: 5, name: 'Sara Petrovska', account: 'sara', citizenid: 'GR59JMR2D', job: 'realtor', level: 26, cash: 65300, bank: 1120000, ping: 45 },
    { source: 6, name: 'Stefan Ristic', account: 'stefan', citizenid: 'GR22BQW8E', job: 'mechanic', level: 14, cash: 8750, bank: 43200, ping: 200 },
    { source: 7, name: 'Marko Jovanovski', account: 'marko', citizenid: 'GR66TNV3F', job: 'lawyer', level: 51, cash: 210400, bank: 3480000, ping: 28 },
    { source: 8, name: 'Ilir Arisjanovi', account: 'ilir', citizenid: 'GR40HLC9G', job: 'truck', level: 11, cash: 3400, bank: 27600, ping: 74 },
    { source: 9, name: 'Filip Trajkov', account: 'filip', citizenid: 'GR85DKE1H', job: 'cardealer', level: 37, cash: 148900, bank: 2015400, ping: 19 },
    { source: 10, name: 'Nikola Stojanov', account: 'nikola', citizenid: 'GR17YPA6I', job: 'unemployed', level: 2, cash: 320, bank: 0, ping: 96 },
  ];

  const PREVIEW_VEHICLES = {
    Cars: ['adder', 'emerus', 'feveter', 'negasi', 'raiden', 'swift2', 'comet6', 'zentorno', 'tempesta', 'jester3', 's80', 'autarch'],
    SUVs: ['baller7', 'conturia', 'novice', 'granger', 'toros', 'rebla', 'issi4', 'habanero', 'dominator GTX'],
    Motorcycles: ['bati2', 'neron', 'akuma', 'carbonrs', 'rprotota', 'maneter', 'daemon2', 'vapid'],
  };

  function mockCallback(name, payload) {
    switch (name) {
      case 'getPlayers':
        return { data: PREVIEW_PLAYERS };
      case 'getVehicleCategories':
        return { data: PREVIEW_VEHICLES };
      case 'getState':
        return { data: { godmode: false, noclip: false, spectating: null } };
      case 'getServerInfo':
        return { data: { players: PREVIEW_PLAYERS.length, uptime: 172861, name: 'Grand RP | EN #1' } };
      case 'kickPlayer':
        state.players = state.players.filter((p) => p.source !== Number(payload.target));
        renderPlayers();
        return { success: true, message: 'Player kicked' };
      case 'banPlayer':
        state.players = state.players.filter((p) => p.source !== Number(payload.target));
        renderPlayers();
        return { success: true, message: 'Player banned' };
      case 'bringPlayer':
        return { success: true, message: 'Player brought to you' };
      case 'spawnVehicle':
        return { success: true, message: vehicleName(payload.model) + ' spawned' };
      case 'deleteCurrentVehicle':
        return { success: true, message: 'Vehicle deleted' };
      case 'toggleGodmode': {
        const on = $('grp-godmode-indicator').dataset.status !== 'on';
        applyState({ godmode: on });
        return { success: true, message: 'Godmode ' + (on ? 'enabled' : 'disabled') };
      }
      case 'toggleNoclip': {
        const on = $('grp-noclip-indicator').dataset.status !== 'on';
        applyState({ noclip: on });
        return { success: true, message: 'Noclip ' + (on ? 'enabled' : 'disabled') };
      }
      case 'spectatePlayer':
        return { success: true, message: 'Spectating player ' + payload.target };
      case 'stopSpectating':
        return { success: true, message: 'Stopped spectating' };
      case 'teleportToCoords':
        return { success: true, message: `Teleported to ${payload.x}, ${payload.y}, ${payload.z}` };
      case 'teleportToPlayer':
        return { success: true, message: 'Teleported to player ' + payload.target };
      case 'teleportToWaypoint':
        return { success: false, message: 'No waypoint set' };
      case 'setInvisible':
        return { success: true, message: payload.state ? 'Invisible' : 'Visible' };
      case 'healSelf':
        return { success: true, message: 'Health restored' };
      case 'setNoclipSpeed':
        return { success: true, message: 'Noclip speed set to ' + payload.value };
      default:
        return { success: true, message: 'Preview: ' + name };
    }
  }

  function startPreview() {
    document.body.classList.add('grp-preview');

    if (!document.querySelector('.grp-preview-tag')) {
      const tag = document.createElement('div');
      tag.className = 'grp-preview-tag';
      tag.textContent = 'Preview mode — mock data';
      document.body.appendChild(tag);
    }

    state.players = PREVIEW_PLAYERS.slice();
    state.vehicles = PREVIEW_VEHICLES;
    state.adminName = 'Aman (Admin)';

    handlers.open({
      name: 'Aman (Admin)',
      full: true,
      godmode: false,
      noclip: false,
      spectating: null,
      noclipSpeed: 3,
    });

    loadServerInfo();
    setTimeout(() => toast('Welcome to Grand RP Admin', 'primary'), 400);
    setTimeout(() => toast('Dario Nikolov is broadcasting on all channels', 'warning'), 2200);
  }

  // ------------------------------------------------------------------------
  // Boot
  // ------------------------------------------------------------------------

  bind();
  startTimers();
  renderPlayers();

  if (isBrowserPreview) {
    startPreview();
  } else {
    document.querySelector('.grp-container')?.classList.remove('visible');
  }
})();
