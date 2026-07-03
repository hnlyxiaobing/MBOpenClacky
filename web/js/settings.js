// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Settings Module
// ═══════════════════════════════════════════════════════════════

const Settings = {
  config: null,
  models: [],

  /**
   * Initialize settings module
   */
  init() {
    document.getElementById('btn-settings').addEventListener('click', () => {
      App.showView('settings');
      this.loadSettings();
    });
  },

  /**
   * Load current configuration
   */
  async loadSettings() {
    try {
      const [configRes, modelsRes] = await Promise.all([
        fetch('/api/config'),
        fetch('/api/config/models'),
      ]);

      if (configRes.ok) {
        this.config = await configRes.json();
      }
      if (modelsRes.ok) {
        const data = await modelsRes.json();
        this.models = data.models || [];
      }

      this.renderSettingsPanel();
    } catch (err) {
      console.error('[Settings] Load failed:', err);
      App.showNotification(I18n.t('settings.failed_load'), 'error');
    }
  },

  /**
   * Save configuration
   */
  async saveSettings(config) {
    try {
      const res = await fetch('/api/config', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(config),
      });

      if (!res.ok) throw new Error('Save failed');

      this.config = await res.json();
      App.showNotification(I18n.t('settings.saved'), 'success');
      this.renderSettingsPanel();
    } catch (err) {
      App.showNotification(I18n.t('settings.failed'), 'error');
    }
  },

  /**
   * Render the settings panel
   */
  renderSettingsPanel() {
    const container = document.getElementById('settings-content');
    if (!this.config) {
      container.innerHTML = '<div class="text-center text-muted"><div class="spinner" style="margin:40px auto"></div></div>';
      return;
    }

    container.innerHTML = `
      <div class="settings-group">
        <div class="settings-group-title">${I18n.t('settings.model_config')}</div>
        ${this.renderModelSelector()}
      </div>

      <div class="settings-group">
        <div class="settings-group-title">${I18n.t('settings.permissions')}</div>
        ${this.renderPermissionMode()}
      </div>

      <div class="settings-group">
        <div class="settings-group-title">${I18n.t('settings.generation')}</div>
        <div class="settings-field">
          <label for="setting-max-tokens">${I18n.t('settings.max_tokens')}</label>
          <input type="number" id="setting-max-tokens" value="${this.config.max_tokens || 4096}" min="256" max="200000" step="256">
          <div class="help-text">${I18n.t('settings.max_tokens_help')}</div>
        </div>
        <div class="settings-field">
          <div class="toggle-wrapper">
            <label>${I18n.t('settings.verbose_mode')}</label>
            <div class="toggle ${this.config.verbose ? 'active' : ''}" id="toggle-verbose" onclick="Settings.toggleVerbose()"></div>
          </div>
          <div class="help-text">${I18n.t('settings.verbose_help')}</div>
        </div>
      </div>

      <div class="settings-group">
        <div class="settings-group-title">${I18n.t('settings.server_info')}</div>
        <div id="settings-server-info" class="text-muted" style="font-size:12px">${I18n.t('settings.loading')}</div>
      </div>

      <div style="padding-top:12px">
        <button class="btn btn-primary" onclick="Settings.handleSave()">${I18n.t('settings.save')}</button>
      </div>`;

    // Load server info
    this.loadServerInfo();
  },

  /**
   * Render model selector
   */
  renderModelSelector() {
    if (this.models.length === 0) {
      return `
        <div class="settings-field">
          <label>${I18n.t('settings.current_model')}</label>
          <input type="text" value="${this.config.current_model_id || I18n.t('settings.not_configured')}" readonly>
          <div class="help-text">${I18n.t('settings.no_models')}</div>
        </div>`;
    }

    const options = this.models.map(m => {
      const id = m.id || m.name || '';
      const label = m.name || m.model || id;
      const selected = id === this.config.current_model_id ? 'selected' : '';
      return `<option value="${id}" ${selected}>${Chat.escapeHtml(label)}</option>`;
    }).join('');

    return `
      <div class="settings-field">
        <label for="setting-model">${I18n.t('settings.active_model')}</label>
        <select id="setting-model">${options}</select>
        <div class="help-text">${I18n.t('settings.select_model')}</div>
      </div>`;
  },

  /**
   * Render permission mode selector
   */
  renderPermissionMode() {
    const modes = [
      { value: 'auto_approve', label: I18n.t('settings.auto_approve'), desc: I18n.t('settings.auto_approve_desc') },
      { value: 'confirm_safes', label: I18n.t('settings.confirm_safe'), desc: I18n.t('settings.confirm_safe_desc') },
      { value: 'confirm_all', label: I18n.t('settings.confirm_all'), desc: I18n.t('settings.confirm_all_desc') },
    ];

    const options = modes.map(m => {
      const selected = m.value === this.config.permission_mode ? 'selected' : '';
      return `<option value="${m.value}" ${selected}>${m.label}</option>`;
    }).join('');

    const currentDesc = modes.find(m => m.value === this.config.permission_mode)?.desc || '';

    return `
      <div class="settings-field">
        <label for="setting-permission">${I18n.t('settings.permission_mode')}</label>
        <select id="setting-permission">${options}</select>
        <div class="help-text">${currentDesc}</div>
      </div>`;
  },

  /**
   * Toggle verbose mode
   */
  toggleVerbose() {
    const toggle = document.getElementById('toggle-verbose');
    toggle.classList.toggle('active');
  },

  /**
   * Handle save button click
   */
  handleSave() {
    const config = {};

    const maxTokens = document.getElementById('setting-max-tokens');
    if (maxTokens) config.max_tokens = parseInt(maxTokens.value) || 4096;

    const permission = document.getElementById('setting-permission');
    if (permission) config.permission_mode = permission.value;

    const verbose = document.getElementById('toggle-verbose');
    if (verbose) config.verbose = verbose.classList.contains('active');

    this.saveSettings(config);
  },

  /**
   * Load and display server info
   */
  async loadServerInfo() {
    try {
      const res = await fetch('/api/info');
      if (!res.ok) return;

      const info = await res.json();
      const el = document.getElementById('settings-server-info');
      if (el) {
        const uptime = this.formatUptime(info.uptime_seconds || 0);
        el.innerHTML = `
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">
            <div><strong>Version:</strong> ${info.version || 'unknown'}</div>
            <div><strong>Uptime:</strong> ${uptime}</div>
            <div><strong>Active Sessions:</strong> ${info.active_sessions || 0}</div>
            <div><strong>Name:</strong> ${info.name || 'MBOpenClacky'}</div>
          </div>`;
      }
    } catch (e) { /* ignore */ }
  },

  /**
   * Format uptime seconds to readable string
   */
  formatUptime(seconds) {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    if (h > 0) return `${h}h ${m}m`;
    if (m > 0) return `${m}m ${s}s`;
    return `${s}s`;
  },
};
