// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Meeting Panel (Placeholder)
// ═══════════════════════════════════════════════════════════════

// ── MeetingView: 会议面板渲染（占位） ──────────────────────────
const MeetingView = {
  active_tab: 'upcoming',

  init() {
    console.log('[MeetingView] initialized (placeholder)');
  },

  async load() {
    this.renderMeetingPanel();
  },

  renderMeetingPanel() {
    const container = document.getElementById('meeting-content');
    if (!container) return;

    const tabs = [
      { key: 'upcoming', label: I18n.t('meeting.tab_upcoming') },
      { key: 'history', label: I18n.t('meeting.tab_history') },
      { key: 'calendar', label: I18n.t('meeting.tab_calendar') },
    ];

    const tabHtml = tabs.map(t =>
      `<button class="skills-tab ${this.active_tab === t.key ? 'active' : ''}" onclick="MeetingView.switchTab('${t.key}')">${t.label}</button>`
    ).join('');

    container.innerHTML = `
      <div class="skills-tabs" style="margin-bottom:16px">${tabHtml}</div>
      <div id="meeting-tab-body">${this._renderTabContent()}</div>`;
  },

  switchTab(tab) {
    this.active_tab = tab;
    this.renderMeetingPanel();
  },

  _renderTabContent() {
    // Placeholder content for all tabs
    return `
      <div class="settings-group">
        <div class="empty-state" style="padding:48px 24px">
          <div class="empty-state-icon">&#128249;</div>
          <h3>${I18n.t('meeting.placeholder_title')}</h3>
          <p class="text-muted" style="max-width:400px;margin:8px auto 0">
            ${I18n.t('meeting.placeholder_desc')}
          </p>
          <div style="margin-top:24px;padding:16px;background:var(--bg-tertiary);border-radius:var(--radius);border:1px dashed var(--border)">
            <div style="font-size:12px;color:var(--text-muted);line-height:1.8">
              <div><strong>${I18n.t('meeting.planned_features')}</strong></div>
              <ul style="padding-left:20px;margin-top:4px">
                <li>${I18n.t('meeting.feature_1')}</li>
                <li>${I18n.t('meeting.feature_2')}</li>
                <li>${I18n.t('meeting.feature_3')}</li>
                <li>${I18n.t('meeting.feature_4')}</li>
              </ul>
            </div>
          </div>
          <div style="margin-top:16px;font-size:11px;color:var(--text-muted)">
            ${I18n.t('meeting.depends_on')} P1-3
          </div>
        </div>
      </div>`;
  },
};
