// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Onboard Wizard
// ═══════════════════════════════════════════════════════════════

// ── OnboardStore: 引导状态管理 ──────────────────────────────
const OnboardStore = {
  step: 0,          // 当前步骤: 0=welcome, 1=configure, 2=complete
  completed: false,  // 是否已完成引导
  device_code: null, // 设备码（用于认证）

  /** 获取引导状态 — GET /api/onboard/status */
  async fetchOnboardStatus() {
    try {
      const data = await API.get('/api/onboard/status');
      this.completed = !!data.completed;
      this.step = data.step || 0;
      this.device_code = data.device_code || null;
      return data;
    } catch (err) {
      console.error('[OnboardStore] fetchOnboardStatus failed:', err);
      return null;
    }
  },

  /** 开始引导 — POST /api/onboard/start */
  async startOnboard() {
    try {
      const data = await API.post('/api/onboard/start', {});
      this.step = 1;
      this.device_code = data.device_code || null;
      return data;
    } catch (err) {
      console.error('[OnboardStore] startOnboard failed:', err);
      throw err;
    }
  },

  /** 完成引导 — POST /api/onboard/complete */
  async completeOnboard() {
    try {
      const data = await API.post('/api/onboard/complete', {});
      this.completed = true;
      this.step = 2;
      return data;
    } catch (err) {
      console.error('[OnboardStore] completeOnboard failed:', err);
      throw err;
    }
  },

  /** 跳过引导 — POST /api/onboard/skip */
  async skipOnboard() {
    try {
      const data = await API.post('/api/onboard/skip', {});
      this.completed = true;
      return data;
    } catch (err) {
      console.error('[OnboardStore] skipOnboard failed:', err);
      throw err;
    }
  },
};

// ── OnboardView: 引导向导渲染 ────────────────────────────────
const OnboardView = {
  /** 初始化 */
  init() {
    console.log('[OnboardView] initialized');
  },

  /** 加载并渲染 */
  async load() {
    const content = document.getElementById('onboard-content');
    if (!content) return;
    content.innerHTML = '<div class="text-center"><div class="spinner" style="margin:40px auto"></div></div>';

    await OnboardStore.fetchOnboardStatus();
    this.renderOnboardWizard();
  },

  /** 渲染引导向导 */
  renderOnboardWizard() {
    const container = document.getElementById('onboard-content');
    if (!container) return;

    if (OnboardStore.completed) {
      this._renderComplete(container);
      return;
    }

    switch (OnboardStore.step) {
      case 0: this._renderWelcome(container); break;
      case 1: this._renderConfigure(container); break;
      case 2: this._renderComplete(container); break;
      default: this._renderWelcome(container);
    }
  },

  /** 步骤 0: 欢迎页面 */
  _renderWelcome(container) {
    container.innerHTML = `
      <div class="onboard-wizard">
        <div class="onboard-step">
          <div class="onboard-step-icon" style="font-size:48px;margin-bottom:16px">&#128075;</div>
          <h2 style="font-size:22px;margin-bottom:8px;color:var(--text-primary)">${I18n.t('onboard.welcome')}</h2>
          <p style="color:var(--text-secondary);margin-bottom:24px;max-width:400px;line-height:1.6">
            ${I18n.t('onboard.subtitle')}
          </p>

          <div class="onboard-features" style="text-align:left;max-width:380px;margin:0 auto 24px">
            <div class="onboard-feature" style="display:flex;align-items:center;gap:10px;margin-bottom:12px">
              <span style="font-size:18px">&#128172;</span>
              <span style="font-size:13px;color:var(--text-secondary)">${I18n.t('onboard.feature_chat')}</span>
            </div>
            <div class="onboard-feature" style="display:flex;align-items:center;gap:10px;margin-bottom:12px">
              <span style="font-size:18px">&#128295;</span>
              <span style="font-size:13px;color:var(--text-secondary)">${I18n.t('onboard.feature_tools')}</span>
            </div>
            <div class="onboard-feature" style="display:flex;align-items:center;gap:10px;margin-bottom:12px">
              <span style="font-size:18px">&#128736;</span>
              <span style="font-size:13px;color:var(--text-secondary)">${I18n.t('onboard.feature_skills')}</span>
            </div>
            <div class="onboard-feature" style="display:flex;align-items:center;gap:10px;margin-bottom:12px">
              <span style="font-size:18px">&#128279;</span>
              <span style="font-size:13px;color:var(--text-secondary)">${I18n.t('onboard.feature_mcp')}</span>
            </div>
          </div>

          <div style="display:flex;gap:10px;justify-content:center">
            <button class="btn btn-primary" onclick="OnboardView.handleStart()" style="padding:10px 28px;font-size:14px">${I18n.t('onboard.get_started')}</button>
            <button class="btn btn-ghost" onclick="OnboardView.handleSkip()">${I18n.t('onboard.skip')}</button>
          </div>
        </div>

        <div class="onboard-progress" style="display:flex;gap:6px;justify-content:center;margin-top:32px">
          <div class="onboard-dot active"></div>
          <div class="onboard-dot"></div>
          <div class="onboard-dot"></div>
        </div>
      </div>`;
  },

  /** 步骤 1: 配置页面 */
  _renderConfigure(container) {
    const deviceCode = OnboardStore.device_code || '';

    container.innerHTML = `
      <div class="onboard-wizard">
        <div class="onboard-step">
          <div class="onboard-step-icon" style="font-size:48px;margin-bottom:16px">&#9881;</div>
          <h2 style="font-size:20px;margin-bottom:8px;color:var(--text-primary)">${I18n.t('onboard.config_title')}</h2>
          <p style="color:var(--text-secondary);margin-bottom:24px;max-width:400px;line-height:1.6">
            ${I18n.t('onboard.config_desc')}
          </p>

          <div style="max-width:420px;margin:0 auto;text-align:left">
            <div class="settings-field">
              <label for="onboard-api-key">${I18n.t('onboard.api_key')}</label>
              <input type="password" id="onboard-api-key" placeholder="sk-..." style="width:100%;padding:9px 12px;background:var(--bg-tertiary);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text-primary);font-size:13px;outline:none">
              <div class="help-text">${I18n.t('onboard.api_key_help')}</div>
            </div>

            <div class="settings-field">
              <label for="onboard-model">${I18n.t('onboard.preferred_model')}</label>
              <select id="onboard-model" style="width:100%;padding:9px 12px;background:var(--bg-tertiary);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text-primary);font-size:13px;outline:none;cursor:pointer">
                <option value="">${I18n.t('onboard.default')}</option>
                <option value="claude-sonnet-4-20250514">Claude Sonnet 4</option>
                <option value="gpt-4o">GPT-4o</option>
                <option value="gemini-2.0-flash">Gemini 2.0 Flash</option>
              </select>
              <div class="help-text">${I18n.t('onboard.model_help')}</div>
            </div>

            ${deviceCode ? `
              <div class="settings-field">
                <label>${I18n.t('onboard.device_code')}</label>
                <div style="font-family:var(--font-mono);font-size:14px;color:var(--accent);padding:8px 12px;background:var(--bg-tertiary);border-radius:var(--radius-sm);letter-spacing:2px">${this._esc(deviceCode)}</div>
                <div class="help-text">${I18n.t('onboard.device_code_help')}</div>
              </div>
            ` : ''}
          </div>

          <div style="display:flex;gap:10px;justify-content:center;margin-top:24px">
            <button class="btn btn-ghost" onclick="OnboardView.handleBack()">${I18n.t('onboard.back')}</button>
            <button class="btn btn-primary" onclick="OnboardView.handleConfigureNext()" style="padding:10px 28px">${I18n.t('onboard.next')}</button>
          </div>
        </div>

        <div class="onboard-progress" style="display:flex;gap:6px;justify-content:center;margin-top:32px">
          <div class="onboard-dot done"></div>
          <div class="onboard-dot active"></div>
          <div class="onboard-dot"></div>
        </div>
      </div>`;
  },

  /** 步骤 2: 完成页面 */
  _renderComplete(container) {
    container.innerHTML = `
      <div class="onboard-wizard">
        <div class="onboard-step">
          <div class="onboard-step-icon" style="font-size:48px;margin-bottom:16px">&#127881;</div>
          <h2 style="font-size:22px;margin-bottom:8px;color:var(--text-primary)">${I18n.t('onboard.all_set')}</h2>
          <p style="color:var(--text-secondary);margin-bottom:24px;max-width:400px;line-height:1.6">
            ${I18n.t('onboard.all_set_desc')}
          </p>

          <div style="display:flex;gap:10px;justify-content:center">
            <button class="btn btn-primary" onclick="OnboardView.handleFinish()" style="padding:10px 28px;font-size:14px">${I18n.t('onboard.start_coding')}</button>
          </div>
        </div>

        <div class="onboard-progress" style="display:flex;gap:6px;justify-content:center;margin-top:32px">
          <div class="onboard-dot done"></div>
          <div class="onboard-dot done"></div>
          <div class="onboard-dot done"></div>
        </div>
      </div>`;
  },

  /** 开始引导 */
  async handleStart() {
    try {
      await OnboardStore.startOnboard();
      this.renderOnboardWizard();
    } catch (err) {
      // 即使 API 失败也继续到下一步
      OnboardStore.step = 1;
      this.renderOnboardWizard();
    }
  },

  /** 返回上一步 */
  handleBack() {
    OnboardStore.step = Math.max(0, OnboardStore.step - 1);
    this.renderOnboardWizard();
  },

  /** 配置步骤：保存配置并进入下一步 */
  async handleConfigureNext() {
    const apiKey = document.getElementById('onboard-api-key')?.value.trim() || '';
    const model = document.getElementById('onboard-model')?.value || '';

    if (apiKey) {
      try {
        await API.put('/api/config', {
          api_key: apiKey,
          ...(model ? { current_model_id: model } : {}),
        });
      } catch (err) {
        App.showNotification(I18n.t('onboard.config_failed') + err.message, 'warning');
      }
    }

    OnboardStore.step = 2;
    this.renderOnboardWizard();
  },

  /** 跳过引导 */
  async handleSkip() {
    try {
      await OnboardStore.skipOnboard();
    } catch (e) { /* ignore */ }
    OnboardStore.completed = true;
    App.showView('chat');
    App.showNotification(I18n.t('onboard.skip_notice'), 'info');
  },

  /** 完成引导 */
  async handleFinish() {
    try {
      await OnboardStore.completeOnboard();
    } catch (e) { /* ignore */ }
    OnboardStore.completed = true;
    App.showView('chat');
    App.showNotification(I18n.t('onboard.welcome_notif'), 'success');
  },

  /** HTML 转义 */
  _esc(text) {
    const div = document.createElement('div');
    div.textContent = text || '';
    return div.innerHTML;
  },
};
