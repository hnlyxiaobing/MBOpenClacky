// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Version Management Panel
// ═══════════════════════════════════════════════════════════════

// ── VersionStore: 版本状态管理 ───────────────────────────────
const VersionStore = {
  current_version: null,
  available_update: null,
  changelog: '',

  /** 获取版本信息 — GET /api/version */
  async fetchVersion() {
    try {
      const data = await API.get('/api/version');
      this.current_version = data.current_version || data.version || null;
      this.available_update = data.available_update || data.update || null;
      this.changelog = data.changelog || '';
      return data;
    } catch (err) {
      console.error('[VersionStore] fetchVersion failed:', err);
      return null;
    }
  },

  /** 检查更新 — POST /api/version/check */
  async checkUpdate() {
    try {
      const data = await API.post('/api/version/check', {});
      this.available_update = data.available_update || data.update || null;
      return data;
    } catch (err) {
      console.error('[VersionStore] checkUpdate failed:', err);
      throw err;
    }
  },

  /** 应用更新 — POST /api/version/upgrade */
  async applyUpdate() {
    try {
      const data = await API.post('/api/version/upgrade', {});
      return data;
    } catch (err) {
      console.error('[VersionStore] applyUpdate failed:', err);
      throw err;
    }
  },
};

// ── VersionView: 版本管理面板渲染 ────────────────────────────
const VersionView = {
  /** 初始化 */
  init() {
    console.log('[VersionView] initialized');
  },

  /** 加载并渲染 */
  async load() {
    const content = document.getElementById('version-content');
    if (!content) return;
    content.innerHTML = '<div class="text-center"><div class="spinner" style="margin:40px auto"></div></div>';

    await VersionStore.fetchVersion();
    this.renderVersionPanel();
  },

  /** 渲染版本管理面板 */
  renderVersionPanel() {
    const container = document.getElementById('version-content');
    if (!container) return;

    const v = VersionStore;
    const hasUpdate = !!v.available_update;
    const updateVersion = hasUpdate ? (v.available_update.version || v.available_update) : '';

    container.innerHTML = `
      <div class="settings-group">
        <div class="settings-group-title">Current Version</div>
        <div class="version-info-card">
          <div style="display:flex;align-items:center;gap:12px;margin-bottom:16px">
            <div style="font-size:32px">&#128230;</div>
            <div>
              <div style="font-size:18px;font-weight:700;color:var(--accent)">${this._esc(v.current_version || 'Unknown')}</div>
              <div class="text-muted" style="font-size:12px">MBOpenClacky</div>
            </div>
          </div>
          <div style="display:flex;gap:8px">
            <button class="btn btn-ghost btn-sm" onclick="VersionView.handleCheckUpdate()">Check for Updates</button>
          </div>
        </div>
      </div>

      ${hasUpdate ? `
        <div class="settings-group">
          <div class="settings-group-title" style="color:var(--success)">Update Available</div>
          <div class="version-update-card">
            <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px">
              <div>
                <div style="font-size:15px;font-weight:600;color:var(--success)">Version ${this._esc(String(updateVersion))}</div>
                <div class="text-muted" style="font-size:12px">A new version is available</div>
              </div>
              <button class="btn btn-primary" onclick="VersionView.handleApplyUpdate()">Upgrade Now</button>
            </div>
            ${v.changelog ? `
              <div style="margin-top:8px">
                <div style="font-size:12px;font-weight:600;color:var(--text-secondary);margin-bottom:6px">Changelog:</div>
                <div style="font-size:12px;color:var(--text-muted);white-space:pre-wrap">${this._esc(v.changelog)}</div>
              </div>
            ` : ''}
          </div>
        </div>
      ` : `
        <div class="settings-group">
          <div id="version-check-result" class="text-muted" style="font-size:13px;padding:8px 0"></div>
        </div>
      `}`;
  },

  /** 检查更新 */
  async handleCheckUpdate() {
    const resultEl = document.getElementById('version-check-result');
    if (resultEl) resultEl.textContent = 'Checking for updates...';

    try {
      const data = await VersionStore.checkUpdate();
      if (data.available_update || data.update) {
        App.showNotification('Update available!', 'success');
      } else {
        if (resultEl) resultEl.textContent = 'You are running the latest version.';
        App.showNotification('No updates available', 'info');
      }
      this.renderVersionPanel();
    } catch (err) {
      if (resultEl) resultEl.textContent = 'Check failed: ' + err.message;
      App.showNotification('Update check failed: ' + err.message, 'error');
    }
  },

  /** 应用更新 */
  async handleApplyUpdate() {
    if (!confirm('Upgrade to the latest version? The server may restart.')) return;
    try {
      const data = await VersionStore.applyUpdate();
      App.showNotification(data.message || 'Upgrade initiated. Server may restart.', 'success');
    } catch (err) {
      App.showNotification('Upgrade failed: ' + err.message, 'error');
    }
  },

  /** HTML 转义 */
  _esc(text) {
    const div = document.createElement('div');
    div.textContent = text || '';
    return div.innerHTML;
  },
};
