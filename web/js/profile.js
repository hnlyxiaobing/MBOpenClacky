// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Profile Panel
// ═══════════════════════════════════════════════════════════════

// ── ProfileStore: 用户资料状态管理 ───────────────────────────
const ProfileStore = {
  name: '',
  email: '',
  preferences: {},
  theme: 'dark',

  /** 获取用户资料 — GET /api/profile */
  async fetchProfile() {
    try {
      const data = await API.get('/api/profile');
      this.name = data.name || data.user?.name || '';
      this.email = data.email || data.user?.email || '';
      this.preferences = data.preferences || {};
      this.theme = data.theme || data.preferences?.theme || 'dark';
      return data;
    } catch (err) {
      console.error('[ProfileStore] fetchProfile failed:', err);
      return null;
    }
  },

  /** 保存用户资料 — PUT /api/profile */
  async saveProfile(data) {
    try {
      const result = await API.put('/api/profile', data);
      if (data.name !== undefined) this.name = data.name;
      if (data.email !== undefined) this.email = data.email;
      if (data.preferences) this.preferences = { ...this.preferences, ...data.preferences };
      if (data.theme) this.theme = data.theme;
      return result;
    } catch (err) {
      console.error('[ProfileStore] saveProfile failed:', err);
      throw err;
    }
  },
};

// ── ProfileView: 个人资料面板渲染 ────────────────────────────
const ProfileView = {
  /** 初始化 */
  init() {
    console.log('[ProfileView] initialized');
  },

  /** 加载并渲染 */
  async load() {
    const content = document.getElementById('profile-content');
    if (!content) return;
    content.innerHTML = '<div class="text-center"><div class="spinner" style="margin:40px auto"></div></div>';

    await ProfileStore.fetchProfile();
    this.renderProfilePanel();
  },

  /** 渲染个人资料面板 */
  renderProfilePanel() {
    const container = document.getElementById('profile-content');
    if (!container) return;

    const p = ProfileStore;
    container.innerHTML = `
      <div class="settings-group">
        <div class="settings-group-title">${I18n.t('profile.personal_info')}</div>
        <div class="settings-field">
          <label for="profile-name">${I18n.t('profile.display_name')}</label>
          <input type="text" id="profile-name" value="${this._esc(p.name)}" placeholder="${I18n.t('profile.name_placeholder')}">
          <div class="help-text">${I18n.t('profile.display_name_help')}</div>
        </div>
        <div class="settings-field">
          <label for="profile-email">${I18n.t('profile.email')}</label>
          <input type="text" id="profile-email" value="${this._esc(p.email)}" placeholder="${I18n.t('profile.email_placeholder')}">
          <div class="help-text">${I18n.t('profile.email_help')}</div>
        </div>
      </div>

      <div class="settings-group">
        <div class="settings-group-title">${I18n.t('profile.preferences')}</div>
        <div class="settings-field">
          <label for="profile-theme">${I18n.t('profile.theme')}</label>
          <select id="profile-theme">
            <option value="dark" ${p.theme === 'dark' ? 'selected' : ''}>${I18n.t('profile.dark')}</option>
            <option value="light" ${p.theme === 'light' ? 'selected' : ''}>${I18n.t('profile.light')}</option>
            <option value="auto" ${p.theme === 'auto' ? 'selected' : ''}>${I18n.t('profile.system_default')}</option>
          </select>
          <div class="help-text">${I18n.t('profile.theme_help')}</div>
        </div>
        <div class="settings-field">
          <label for="profile-language">${I18n.t('profile.language')}</label>
          <select id="profile-language">
            <option value="en" ${(p.preferences.language || I18n.getLocale()) === 'en' ? 'selected' : ''}>English</option>
            <option value="zh" ${(p.preferences.language || I18n.getLocale()) === 'zh' ? 'selected' : ''}>中文</option>
            <option value="ja" ${p.preferences.language === 'ja' ? 'selected' : ''}>日本語</option>
          </select>
          <div class="help-text">${I18n.t('profile.language_help')}</div>
        </div>
        <div class="settings-field">
          <div class="toggle-wrapper">
            <label>${I18n.t('profile.email_notifications')}</label>
            <div class="toggle ${p.preferences.email_notifications ? 'active' : ''}" id="toggle-email-notif" onclick="this.classList.toggle('active')"></div>
          </div>
          <div class="help-text">${I18n.t('profile.email_notif_help')}</div>
        </div>
      </div>

      <div style="padding-top:12px;display:flex;gap:8px">
        <button class="btn btn-primary" onclick="ProfileView.handleSave()">${I18n.t('profile.save')}</button>
        <button class="btn btn-ghost" onclick="ProfileView.load()">${I18n.t('profile.reset')}</button>
      </div>`;
  },

  /** 保存个人资料 */
  async handleSave() {
    const name = document.getElementById('profile-name')?.value.trim() || '';
    const email = document.getElementById('profile-email')?.value.trim() || '';
    const theme = document.getElementById('profile-theme')?.value || 'dark';
    const language = document.getElementById('profile-language')?.value || 'en';
    const emailNotif = document.getElementById('toggle-email-notif')?.classList.contains('active') || false;

    try {
      await ProfileStore.saveProfile({
        name,
        email,
        theme,
        preferences: {
          language,
          email_notifications: emailNotif,
        },
      });
      // Apply language change immediately via i18n
      if (typeof I18n !== 'undefined' && I18n.getLocale() !== language) {
        I18n.setLocale(language);
      }
      App.showNotification(I18n.t('profile.saved'), 'success');
    } catch (err) {
      App.showNotification(I18n.t('profile.save_failed') + err.message, 'error');
    }
  },

  /** HTML 转义 */
  _esc(text) {
    const div = document.createElement('div');
    div.textContent = text || '';
    return div.innerHTML;
  },
};
