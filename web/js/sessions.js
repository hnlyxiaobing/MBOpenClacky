// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Sessions Module
// ═══════════════════════════════════════════════════════════════

const Sessions = {
  sessions: [],
  searchFilter: '',

  /**
   * Initialize sessions module
   */
  init() {
    document.getElementById('btn-new-session').addEventListener('click', () => this.showNewSessionDialog());

    document.getElementById('session-search').addEventListener('input', (e) => {
      this.searchFilter = e.target.value.toLowerCase();
      this.renderSessionList();
    });

    this.loadSessions();
  },

  /**
   * Load all sessions from server
   */
  async loadSessions() {
    try {
      const res = await fetch('/api/sessions');
      if (!res.ok) throw new Error('Failed to load sessions');

      const data = await res.json();
      this.sessions = data.sessions || [];
      this.renderSessionList();
    } catch (err) {
      console.error('[Sessions] Load failed:', err);
      App.showNotification(I18n.t('sessions.failed_load'), 'error');
    }
  },

  /**
   * Create a new session
   */
  async createSession(name) {
    try {
      const res = await fetch('/api/sessions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: name || I18n.t('sessions.new') }),
      });

      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.error || 'Failed to create session');
      }

      const session = await res.json();
      this.sessions.unshift(session);
      this.renderSessionList();
      this.switchSession(session.session_id || session.id);
      App.showNotification(I18n.t('sessions.created'), 'success');
      App.hideModal();
    } catch (err) {
      App.showNotification(err.message, 'error');
    }
  },

  /**
   * Delete a session
   */
  async deleteSession(id) {
    if (!confirm(I18n.t('sessions.delete_confirm'))) return;

    try {
      const res = await fetch(`/api/sessions/${id}`, { method: 'DELETE' });
      if (!res.ok && res.status !== 204) throw new Error('Delete failed');

      this.sessions = this.sessions.filter(s => (s.session_id || s.id) !== id);
      this.renderSessionList();

      if (App.currentSessionId === id) {
        App.currentSessionId = null;
        Chat.clear();
        document.getElementById('chat-session-name').textContent = I18n.t('sessions.select_session');
        document.getElementById('chat-input').disabled = true;
      }

      App.showNotification(I18n.t('sessions.deleted'), 'info');
    } catch (err) {
      App.showNotification(I18n.t('sessions.failed_delete'), 'error');
    }
  },

  /**
   * Switch to a session
   */
  async switchSession(id) {
    App.currentSessionId = id;

    // Update sidebar active state
    document.querySelectorAll('.session-item').forEach(el => {
      el.classList.toggle('active', el.dataset.id === id);
    });

    // Enable input
    document.getElementById('chat-input').disabled = false;
    document.getElementById('btn-send').disabled = false;

    // Load chat history
    await Chat.loadHistory(id);

    // Connect WebSocket for live updates
    WS.connect(id);

    // Update cost display
    this.updateCostDisplay(id);

    // Close mobile sidebar
    document.getElementById('sidebar').classList.remove('open');
  },

  /**
   * Update cost display in footer
   */
  async updateCostDisplay(id) {
    try {
      const res = await fetch(`/api/sessions/${id}/cost`);
      if (res.ok) {
        const data = await res.json();
        document.getElementById('chat-cost-display').textContent =
          I18n.t('common.cost', { cost: (data.total_cost_usd || 0).toFixed(4) });
      }
    } catch (e) { /* ignore */ }
  },

  /**
   * Render the session list in sidebar
   */
  renderSessionList() {
    const container = document.getElementById('session-list');
    const filtered = this.searchFilter
      ? this.sessions.filter(s => (s.name || '').toLowerCase().includes(this.searchFilter))
      : this.sessions;

    if (filtered.length === 0) {
      container.innerHTML = `
        <div class="empty-state" style="padding:20px">
          <p class="text-muted" style="font-size:12px">
            ${this.searchFilter ? I18n.t('sessions.no_matching') : I18n.t('sessions.no_sessions')}
          </p>
        </div>`;
      return;
    }

    container.innerHTML = filtered.map(session => this.renderSessionItem(session)).join('');
  },

  /**
   * Render a single session item
   */
  renderSessionItem(session) {
    const id = session.session_id || session.id;
    const name = session.name || I18n.t('sessions.unnamed');
    const isActive = id === App.currentSessionId;
    const msgCount = session.messages ? session.messages.length : (session.stats?.total_iterations || 0);
    const cost = session.stats?.total_cost_usd;
    const meta = [];

    if (msgCount) meta.push(`${msgCount} ${I18n.t('sessions.msgs')}`);
    if (cost) meta.push(`$${cost.toFixed(4)}`);
    if (session.updated_at || session.created_at) {
      meta.push(this.formatRelativeTime(session.updated_at || session.created_at));
    }

    return `
      <div class="session-item ${isActive ? 'active' : ''}" data-id="${id}" onclick="Sessions.switchSession('${id}')">
        <div class="session-item-info">
          <div class="session-item-name">${Chat.escapeHtml(name)}</div>
          ${meta.length ? `<div class="session-item-meta">${meta.join(' · ')}</div>` : ''}
        </div>
        <button class="session-item-delete" onclick="event.stopPropagation(); Sessions.deleteSession('${id}')" title="${I18n.t('common.delete')}">&#128465;</button>
      </div>`;
  },

  /**
   * Show new session dialog
   */
  showNewSessionDialog() {
    const html = `
      <div class="settings-field">
        <label for="new-session-name">${I18n.t('sessions.name')}</label>
        <input type="text" id="new-session-name" placeholder="${I18n.t('sessions.name_placeholder')}" autofocus>
        <div class="help-text">${I18n.t('sessions.name_help')}</div>
      </div>`;

    const footer = `
      <button class="btn btn-ghost" onclick="App.hideModal()">${I18n.t('common.cancel')}</button>
      <button class="btn btn-primary" onclick="Sessions.handleCreateSession()">${I18n.t('sessions.create')}</button>`;

    App.showModal(I18n.t('sessions.new'), html, footer);

    // Focus input after modal renders
    setTimeout(() => {
      const input = document.getElementById('new-session-name');
      if (input) {
        input.focus();
        input.addEventListener('keydown', (e) => {
          if (e.key === 'Enter') this.handleCreateSession();
        });
      }
    }, 100);
  },

  /**
   * Handle create session form submit
   */
  handleCreateSession() {
    const input = document.getElementById('new-session-name');
    const name = input ? input.value.trim() : '';
    this.createSession(name || I18n.t('sessions.new'));
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

      if (diffMin < 1) return I18n.t('sessions.just_now');
      if (diffMin < 60) return `${diffMin}${I18n.t('sessions.m_ago')}`;
      if (diffHr < 24) return `${diffHr}${I18n.t('sessions.h_ago')}`;
      if (diffDay < 7) return `${diffDay}${I18n.t('sessions.d_ago')}`;
      return date.toLocaleDateString();
    } catch {
      return '';
    }
  },
};
