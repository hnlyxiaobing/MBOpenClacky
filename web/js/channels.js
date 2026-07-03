// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Channels Panel
// ═══════════════════════════════════════════════════════════════

const Channels = {
  channels: [],

  /** Platform display metadata */
  platforms: {
    feishu:   { label: 'Feishu',   icon: '\u{1F4AC}' },
    wecom:    { label: 'WeCom',    icon: '\u{1F4BC}' },
    telegram: { label: 'Telegram', icon: '\u{2708}'  },
    discord:  { label: 'Discord',  icon: '\u{1F3AE}' },
    dingtalk: { label: 'DingTalk', icon: '\u{1F514}' },
    weixin:   { label: 'WeChat',   icon: '\u{1F4F1}' },
  },

  /**
   * Initialize channels module
   */
  init() {
    console.log('[Channels] initialized');
  },

  /**
   * Load data when view is shown
   */
  async load() {
    const content = document.getElementById('channels-content');
    content.innerHTML = '<div class="text-center"><div class="spinner" style="margin:40px auto"></div></div>';
    try {
      await this.loadChannels();
      this.render();
    } catch (err) {
      content.innerHTML = `<p class="text-muted text-center">${I18n.t('channels.failed_load')}</p>`;
      App.showNotification(err.message, 'error');
    }
  },

  /**
   * Fetch all channels from backend
   */
  async loadChannels() {
    this.channels = await API.get('/api/channels');
  },

  /**
   * Render the channels panel
   */
  render() {
    const content = document.getElementById('channels-content');
    content.innerHTML = '';

    // ── Header with Add button ──
    const headerSection = document.createElement('div');
    headerSection.className = 'settings-group';
    headerSection.innerHTML = `
      <div class="settings-group-title" style="display:flex;align-items:center;justify-content:space-between">
        <span>${I18n.t('channels.title')} (${this.channels.length})</span>
      </div>`;
    const addBtn = document.createElement('button');
    addBtn.className = 'btn btn-primary btn-sm';
    addBtn.textContent = I18n.t('channels.add');
    addBtn.addEventListener('click', () => this.showForm());
    headerSection.querySelector('.settings-group-title').appendChild(addBtn);
    content.appendChild(headerSection);

    // ── Channel list ──
    if (this.channels.length === 0) {
      const empty = document.createElement('p');
      empty.className = 'text-muted';
      empty.style.cssText = 'font-size:13px;padding:16px 0';
      empty.textContent = I18n.t('channels.no_channels');
      content.appendChild(empty);
      return;
    }

    const grid = document.createElement('div');
    grid.className = 'skills-grid';
    this.channels.forEach(ch => {
      grid.appendChild(this.createChannelCard(ch));
    });
    content.appendChild(grid);
  },

  /**
   * Create a single channel card element
   */
  createChannelCard(ch) {
    const card = document.createElement('div');
    card.className = 'skill-card';

    const platform = this.platforms[ch.platform] || { label: ch.platform || 'Unknown', icon: '\u{1F4E1}' };
    const chId = ch.id || ch.channel_id || '';
    const isConnected = ch.status === 'connected' || ch.status === 'active';

    // Header row: icon + name + status dot
    const headerRow = document.createElement('div');
    headerRow.style.cssText = 'display:flex;align-items:center;gap:8px;margin-bottom:8px';

    const iconSpan = document.createElement('span');
    iconSpan.style.fontSize = '18px';
    iconSpan.textContent = platform.icon;
    headerRow.appendChild(iconSpan);

    const nameEl = document.createElement('div');
    nameEl.className = 'skill-card-name';
    nameEl.style.marginBottom = '0';
    nameEl.textContent = ch.name || platform.label;
    headerRow.appendChild(nameEl);

    // Status dot
    const dot = document.createElement('span');
    dot.style.cssText = `width:8px;height:8px;border-radius:50%;display:inline-block;margin-left:auto;flex-shrink:0;background:${isConnected ? 'var(--success)' : 'var(--text-muted)'}`;
    dot.title = isConnected ? I18n.t('channels.connected') : I18n.t('channels.disconnected');
    headerRow.appendChild(dot);

    card.appendChild(headerRow);

    // Platform label
    const platLabel = document.createElement('div');
    platLabel.className = 'skill-card-desc';
    platLabel.textContent = platform.label;
    card.appendChild(platLabel);

    // Status text
    const statusText = document.createElement('div');
    statusText.className = 'skill-card-desc';
    statusText.style.cssText = 'margin-top:2px;font-size:11px';
    statusText.textContent = isConnected ? I18n.t('channels.connected') : (ch.status || I18n.t('channels.disconnected'));
    statusText.style.color = isConnected ? 'var(--success)' : 'var(--text-muted)';
    card.appendChild(statusText);

    // Last activity
    if (ch.last_activity || ch.updated_at) {
      const activityEl = document.createElement('div');
      activityEl.className = 'skill-card-desc';
      activityEl.style.cssText = 'margin-top:4px;font-size:11px;color:var(--text-muted)';
      activityEl.textContent = I18n.t('channels.last') + this.formatRelativeTime(ch.last_activity || ch.updated_at);
      card.appendChild(activityEl);
    }

    // Action buttons row
    const actions = document.createElement('div');
    actions.style.cssText = 'display:flex;gap:6px;margin-top:12px;flex-wrap:wrap';

    const editBtn = document.createElement('button');
    editBtn.className = 'btn btn-ghost btn-sm';
    editBtn.textContent = I18n.t('common.edit');
    editBtn.style.cssText = 'padding:3px 8px;font-size:11px';
    editBtn.addEventListener('click', () => this.showForm(ch));
    actions.appendChild(editBtn);

    const testBtn = document.createElement('button');
    testBtn.className = 'btn btn-ghost btn-sm';
    testBtn.textContent = I18n.t('channels.test');
    testBtn.style.cssText = 'padding:3px 8px;font-size:11px;color:var(--info)';
    testBtn.addEventListener('click', () => this.handleTest(chId));
    actions.appendChild(testBtn);

    const statusBtn = document.createElement('button');
    statusBtn.className = 'btn btn-ghost btn-sm';
    statusBtn.textContent = I18n.t('channels.status');
    statusBtn.style.cssText = 'padding:3px 8px;font-size:11px';
    statusBtn.addEventListener('click', () => this.handleStatus(chId, dot, statusText));
    actions.appendChild(statusBtn);

    const delBtn = document.createElement('button');
    delBtn.className = 'btn btn-danger btn-sm';
    delBtn.textContent = I18n.t('common.delete');
    delBtn.style.cssText = 'padding:3px 8px;font-size:11px';
    delBtn.addEventListener('click', () => this.handleDelete(chId));
    actions.appendChild(delBtn);

    card.appendChild(actions);
    return card;
  },

  /**
   * Show add/edit channel modal form
   */
  showForm(channel) {
    const isEdit = !!channel;
    const ch = channel || {};
    const cfg = ch.config || {};

    const platformOptions = Object.entries(this.platforms).map(([key, meta]) => {
      const selected = ch.platform === key ? 'selected' : '';
      return `<option value="${key}" ${selected}>${meta.icon} ${meta.label}</option>`;
    }).join('');

    const body = `
      <div class="settings-field">
        <label for="ch-platform">${I18n.t('channels.platform')}</label>
        <select id="ch-platform">${platformOptions}</select>
        <div class="help-text">${I18n.t('channels.platform_help')}</div>
      </div>
      <div class="settings-field">
        <label for="ch-name">${I18n.t('channels.name')}</label>
        <input type="text" id="ch-name" placeholder="${I18n.t('channels.name_placeholder')}" value="">
        <div class="help-text">${I18n.t('channels.name_help')}</div>
      </div>
      <div class="settings-field">
        <label for="ch-webhook">${I18n.t('channels.webhook')}</label>
        <input type="text" id="ch-webhook" placeholder="https://...">
        <div class="help-text">${I18n.t('channels.webhook_help')}</div>
      </div>
      <div class="settings-field">
        <label for="ch-apikey">${I18n.t('channels.apikey')}</label>
        <input type="text" id="ch-apikey" placeholder="Optional">
        <div class="help-text">${I18n.t('channels.apikey_help')}</div>
      </div>
      <div class="settings-field">
        <label for="ch-secret">${I18n.t('channels.secret')}</label>
        <input type="password" id="ch-secret" placeholder="Optional">
        <div class="help-text">${I18n.t('channels.secret_help')}</div>
      </div>`;

    const footer = `
      <button class="btn btn-ghost" onclick="App.hideModal()">${I18n.t('common.cancel')}</button>
      <button class="btn btn-primary" onclick="Channels.handleSave(${isEdit ? `'${ch.id || ch.channel_id}'` : 'null'})">${isEdit ? I18n.t('channels.update') : I18n.t('channels.create')}</button>`;

    App.showModal(isEdit ? I18n.t('channels.edit') : I18n.t('channels.add_title'), body, footer);

    // Populate fields safely after render
    setTimeout(() => {
      const nameInput = document.getElementById('ch-name');
      if (nameInput && ch.name) nameInput.value = ch.name;

      const webhookInput = document.getElementById('ch-webhook');
      if (webhookInput && cfg.webhook_url) webhookInput.value = cfg.webhook_url;

      const apikeyInput = document.getElementById('ch-apikey');
      if (apikeyInput && cfg.api_key) apikeyInput.value = cfg.api_key;

      const secretInput = document.getElementById('ch-secret');
      if (secretInput && cfg.secret) secretInput.value = cfg.secret;
    }, 50);
  },

  /**
   * Handle save (create or update) channel
   */
  async handleSave(id) {
    const platform = document.getElementById('ch-platform')?.value || '';
    const name = (document.getElementById('ch-name')?.value || '').trim();
    const webhookUrl = (document.getElementById('ch-webhook')?.value || '').trim();
    const apiKey = (document.getElementById('ch-apikey')?.value || '').trim();
    const secret = (document.getElementById('ch-secret')?.value || '').trim();

    if (!platform) {
      App.showNotification(I18n.t('channels.required_platform'), 'error');
      return;
    }
    if (!name) {
      App.showNotification(I18n.t('channels.required_name'), 'error');
      return;
    }

    const config = {};
    if (webhookUrl) config.webhook_url = webhookUrl;
    if (apiKey) config.api_key = apiKey;
    if (secret) config.secret = secret;

    const payload = { platform, name, config };

    try {
      if (id) {
        await API.put(`/api/channels/${encodeURIComponent(id)}`, payload);
        App.showNotification(I18n.t('channels.updated'), 'success');
      } else {
        await API.post('/api/channels', payload);
        App.showNotification(I18n.t('channels.created'), 'success');
      }
      App.hideModal();
      await this.loadChannels();
      this.render();
    } catch (err) {
      App.showNotification(err.message, 'error');
    }
  },

  /**
   * Delete a channel
   */
  async handleDelete(id) {
    if (!confirm(I18n.t('sessions.delete_confirm'))) return;
    try {
      await API.del(`/api/channels/${encodeURIComponent(id)}`);
      App.showNotification(I18n.t('channels.deleted'), 'success');
      await this.loadChannels();
      this.render();
    } catch (err) {
      App.showNotification(err.message, 'error');
    }
  },

  /**
   * Send a test message to a channel
   */
  async handleTest(id) {
    try {
      await API.post(`/api/channels/${encodeURIComponent(id)}/test`);
      App.showNotification(I18n.t('channels.test_sent'), 'success');
    } catch (err) {
      App.showNotification(I18n.t('channels.test_failed') + err.message, 'error');
    }
  },

  /**
   * Check and update channel status
   */
  async handleStatus(id, dotEl, statusEl) {
    try {
      const data = await API.get(`/api/channels/${encodeURIComponent(id)}/status`);
      const isConnected = data.status === 'connected' || data.status === 'active';
      if (dotEl) {
        dotEl.style.background = isConnected ? 'var(--success)' : 'var(--text-muted)';
        dotEl.title = isConnected ? I18n.t('channels.connected') : I18n.t('channels.disconnected');
      }
      if (statusEl) {
        statusEl.textContent = data.status || I18n.t('channels.status_unknown');
        statusEl.style.color = isConnected ? 'var(--success)' : 'var(--text-muted)';
      }
      App.showNotification(`${I18n.t('common.status')}: ${data.status || I18n.t('channels.status_unknown')}`, isConnected ? 'success' : 'info');
    } catch (err) {
      App.showNotification(I18n.t('channels.status_check_failed') + err.message, 'error');
    }
  },

  /**
   * Format relative time
   */
  formatRelativeTime(isoString) {
    try {
      const date = new Date(isoString);
      const now = new Date();
      const diffMs = now - date;
      const diffMin = Math.floor(diffMs / 60000);
      const diffHr = Math.floor(diffMs / 3600000);
      const diffDay = Math.floor(diffMs / 86400000);

      if (diffMin < 1) return 'just now';
      if (diffMin < 60) return `${diffMin}m ago`;
      if (diffHr < 24) return `${diffHr}h ago`;
      if (diffDay < 7) return `${diffDay}d ago`;
      return date.toLocaleDateString();
    } catch (e) {
      return '';
    }
  },
};
