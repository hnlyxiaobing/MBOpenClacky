// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Main Application
// ═══════════════════════════════════════════════════════════════

// ── Unified API Wrapper ───────────────────────────────────────
const API = {
  async get(path) {
    try {
      const res = await fetch(path);
      if (!res.ok) {
        const err = new Error(`HTTP ${res.status}`);
        err.status = res.status;
        try { const body = await res.json(); err.message = body.error || err.message; } catch (e) {}
        throw err;
      }
      return res.json();
    } catch (err) {
      if (err.name === 'TypeError') {
        throw new Error('Network error. Please check your connection.');
      }
      throw err;
    }
  },

  async post(path, body) {
    const res = await fetch(path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = new Error(`HTTP ${res.status}`);
      err.status = res.status;
      try { const b = await res.json(); err.message = b.error || err.message; } catch (e) {}
      throw err;
    }
    if (res.status === 204) return null;
    return res.json();
  },

  async put(path, body) {
    const res = await fetch(path, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = new Error(`HTTP ${res.status}`);
      err.status = res.status;
      try { const b = await res.json(); err.message = b.error || err.message; } catch (e) {}
      throw err;
    }
    return res.json();
  },

  async del(path) {
    const res = await fetch(path, { method: 'DELETE' });
    if (!res.ok) {
      const err = new Error(`HTTP ${res.status}`);
      err.status = res.status;
      throw err;
    }
    if (res.status === 204) return null;
    return res.json().catch(() => null);
  },
};

const App = {
  currentSessionId: null,
  config: null,

  /**
   * Initialize the application
   */
  async init() {
    console.log('[App] Initializing MBOpenClacky Web UI...');

    // Initialize i18n first
    if (typeof I18n !== 'undefined') {
      I18n.init();
    }

    // Initialize core modules
    Chat.init();
    Sessions.init();
    Settings.init();
    Skills.init();

    // Initialize notification manager
    if (typeof NotificationManager !== 'undefined') NotificationManager.init();

    // Initialize management panel modules
    if (typeof MCP !== 'undefined') MCP.init();
    if (typeof Channels !== 'undefined') Channels.init();
    if (typeof Schedules !== 'undefined') Schedules.init();
    if (typeof Backups !== 'undefined') Backups.init();
    if (typeof Billing !== 'undefined') Billing.init();
    if (typeof BrowserControl !== 'undefined') BrowserControl.init();
    if (typeof GitPanel !== 'undefined') GitPanel.init();
    if (typeof Trash !== 'undefined') Trash.init();

    // Initialize new feature modules
    if (typeof SkillEditorView !== 'undefined') SkillEditorView.init();
    if (typeof ProfileView !== 'undefined') ProfileView.init();
    if (typeof ShareView !== 'undefined') ShareView.init();
    if (typeof ModelTestView !== 'undefined') ModelTestView.init();
    if (typeof VersionView !== 'undefined') VersionView.init();
    if (typeof WorkspaceView !== 'undefined') WorkspaceView.init();
    if (typeof CreatorView !== 'undefined') CreatorView.init();
    if (typeof OnboardView !== 'undefined') OnboardView.init();
    if (typeof TaskView !== 'undefined') TaskView.init();
    if (typeof MediaView !== 'undefined') MediaView.init();
    if (typeof MarketplaceView !== 'undefined') MarketplaceView.init();
    if (typeof MeetingView !== 'undefined') MeetingView.init();

    // Bind global UI events
    this.bindEvents();

    // Load initial config
    await this.loadConfig();

    // Set up WebSocket event listeners
    this.setupWSListeners();

    console.log('[App] Initialization complete');
  },

  /**
   * Bind global UI event handlers
   */
  bindEvents() {
    // Sidebar toggle for mobile
    document.getElementById('sidebar-toggle').addEventListener('click', () => {
      document.getElementById('sidebar').classList.toggle('open');
    });

    // Close sidebar when clicking outside on mobile
    document.getElementById('main-content').addEventListener('click', () => {
      document.getElementById('sidebar').classList.remove('open');
    });

    // Modal close handlers
    document.getElementById('modal-overlay').addEventListener('click', (e) => {
      if (e.target === e.currentTarget) this.hideModal();
    });
    document.querySelector('.modal-close').addEventListener('click', () => this.hideModal());

    // Close panel buttons
    document.querySelectorAll('.btn-close-panel').forEach(btn => {
      btn.addEventListener('click', () => {
        this.showView(btn.dataset.view || 'chat');
      });
    });

    // Stats button
    document.getElementById('btn-stats').addEventListener('click', () => {
      this.showView('stats');
      this.loadStats();
    });

    // Management panel navigation buttons
    const navModules = [
      { btn: 'btn-mcp', view: 'mcp', module: 'MCP' },
      { btn: 'btn-channels', view: 'channels', module: 'Channels' },
      { btn: 'btn-schedules', view: 'schedules', module: 'Schedules' },
      { btn: 'btn-backups', view: 'backups', module: 'Backups' },
      { btn: 'btn-billing', view: 'billing', module: 'Billing' },
      { btn: 'btn-browser', view: 'browser', module: 'BrowserControl' },
      { btn: 'btn-git', view: 'git', module: 'GitPanel' },
      { btn: 'btn-trash', view: 'trash', module: 'Trash' },
      // New feature modules
      { btn: 'btn-profile', view: 'profile', module: 'ProfileView' },
      { btn: 'btn-share', view: 'share', module: 'ShareView' },
      { btn: 'btn-model-test', view: 'model-test', module: 'ModelTestView' },
      { btn: 'btn-workspace', view: 'workspace', module: 'WorkspaceView' },
      { btn: 'btn-creator', view: 'creator', module: 'CreatorView' },
      { btn: 'btn-version', view: 'version', module: 'VersionView' },
      { btn: 'btn-onboard', view: 'onboard', module: 'OnboardView' },
      { btn: 'btn-tasks', view: 'tasks', module: 'TaskView' },
      { btn: 'btn-media', view: 'media', module: 'MediaView' },
      { btn: 'btn-marketplace', view: 'marketplace', module: 'MarketplaceView' },
      { btn: 'btn-meeting', view: 'meeting', module: 'MeetingView' },
    ];
    navModules.forEach(({ btn, view, module }) => {
      const el = document.getElementById(btn);
      if (el) {
        el.addEventListener('click', () => {
          this.showView(view);
          const mod = window[module];
          if (mod && typeof mod.load === 'function') mod.load();
        });
      }
    });

    // Keyboard shortcuts
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        this.hideModal();
        document.getElementById('sidebar').classList.remove('open');
      }
      // Ctrl+N: new session
      if ((e.ctrlKey || e.metaKey) && e.key === 'n') {
        e.preventDefault();
        Sessions.showNewSessionDialog();
      }
    });
  },

  /**
   * Load application configuration
   */
  async loadConfig() {
    try {
      const res = await fetch('/api/config');
      if (res.ok) {
        this.config = await res.json();
        this.updateModelDisplay();
      }
    } catch (err) {
      console.warn('[App] Config load failed:', err);
    }
  },

  /**
   * Update model display in chat footer
   */
  updateModelDisplay() {
    const el = document.getElementById('chat-model-display');
    if (el && this.config) {
      el.textContent = this.config.current_model_id || '';
    }
  },

  /**
   * Set up WebSocket event listeners
   */
  setupWSListeners() {
    WS.on('status_update', (data) => {
      const badge = document.getElementById('chat-session-status');
      if (badge && data.status) {
        badge.textContent = data.status;
        badge.className = 'status-badge' + (data.status === 'running' ? ' running' : '');
      }
    });

    WS.on('generation_complete', () => {
      Chat.handleStreamDone();
      // Refresh cost
      if (this.currentSessionId) {
        Sessions.updateCostDisplay(this.currentSessionId);
      }
    });

    WS.on('generation_error', (data) => {
      Chat.handleStreamError(data);
    });

    WS.on('disconnected', () => {
      this.showNotification(I18n.t('ws.disconnected'), 'warning');
    });
  },

  /**
   * Switch between views
   */
  showView(viewName) {
    document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
    const view = document.getElementById(`view-${viewName}`);
    if (view) view.classList.add('active');
  },

  /**
   * Load and display statistics
   */
  async loadStats() {
    const container = document.getElementById('stats-content');
    container.innerHTML = '<div class="text-center"><div class="spinner" style="margin:40px auto"></div></div>';

    try {
      const res = await fetch('/api/stats');
      if (!res.ok) throw new Error('Failed to load stats');

      const stats = await res.json();
      container.innerHTML = `
        <div class="stats-grid">
          <div class="stat-card">
            <div class="stat-card-value">${stats.total_sessions || 0}</div>
            <div class="stat-card-label">${I18n.t('stats.total_sessions')}</div>
          </div>
          <div class="stat-card">
            <div class="stat-card-value">$${(stats.total_cost_usd || 0).toFixed(4)}</div>
            <div class="stat-card-label">${I18n.t('stats.total_cost')}</div>
          </div>
          <div class="stat-card">
            <div class="stat-card-value">${stats.total_iterations || 0}</div>
            <div class="stat-card-label">${I18n.t('stats.total_iterations')}</div>
          </div>
          <div class="stat-card">
            <div class="stat-card-value">${stats.total_tasks || 0}</div>
            <div class="stat-card-label">${I18n.t('stats.total_tasks')}</div>
          </div>
        </div>`;
    } catch (err) {
      container.innerHTML = `<p class="text-muted text-center">${I18n.t('stats.failed_load')}</p>`;
    }
  },

  // ── UI Helpers ──────────────────────────────────────────────

  /**
   * Show notification toast (delegates to NotificationManager if available)
   */
  showNotification(message, type = 'info') {
    if (typeof NotificationManager !== 'undefined' && NotificationManager.container) {
      return NotificationManager.notify(message, type);
    }
    // Fallback: original inline notification
    const container = document.getElementById('notifications-container')
      || document.getElementById('notifications');
    if (!container) return;
    const el = document.createElement('div');
    el.className = `notification ${type}`;
    el.textContent = message;
    container.appendChild(el);
    setTimeout(() => {
      el.style.opacity = '0';
      el.style.transform = 'translateX(20px)';
      setTimeout(() => el.remove(), 300);
    }, 4000);
  },

  /**
   * Show modal dialog
   */
  showModal(title, bodyHtml, footerHtml) {
    document.getElementById('modal-title').textContent = title;
    document.getElementById('modal-body').innerHTML = bodyHtml;
    document.getElementById('modal-footer').innerHTML = footerHtml || '';
    document.getElementById('modal-overlay').classList.remove('hidden');
  },

  /**
   * Hide modal dialog
   */
  hideModal() {
    document.getElementById('modal-overlay').classList.add('hidden');
  },
};

// ── Bootstrap ─────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => App.init());
