// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Brand Configuration Panel
// ═══════════════════════════════════════════════════════════════

// ── BrandStore: 管理品牌状态 ─────────────────────────────────
const BrandStore = {
  license_status: null,   // 'active' | 'inactive' | 'trial'
  brand_config: null,     // 品牌配置对象
  installed_skills: [],   // 已安装的品牌技能

  /** 获取品牌状态 — GET /api/brand/status */
  async fetchBrandStatus() {
    try {
      const data = await API.get('/api/brand/status');
      this.license_status = data.license_status || data.status || 'inactive';
      this.brand_config = data.brand_config || data;
      return data;
    } catch (err) {
      console.error('[BrandStore] fetchBrandStatus failed:', err);
      this.license_status = 'inactive';
      return null;
    }
  },

  /** 激活许可证 — POST /api/brand */
  async activateLicense(key) {
    try {
      const data = await API.post('/api/brand', { license_key: key });
      if (data.ok || data.status === 'active') {
        this.license_status = 'active';
        this.brand_config = data.brand_config || data;
      }
      return data;
    } catch (err) {
      console.error('[BrandStore] activateLicense failed:', err);
      throw err;
    }
  },

  /** 停用许可证 — DELETE /api/brand/license */
  async deactivateLicense() {
    try {
      await API.del('/api/brand/license');
      this.license_status = 'inactive';
      this.brand_config = null;
      return true;
    } catch (err) {
      console.error('[BrandStore] deactivateLicense failed:', err);
      throw err;
    }
  },

  /** 获取品牌技能列表 — GET /api/brand/skills */
  async fetchBrandSkills() {
    try {
      const data = await API.get('/api/brand/skills');
      this.installed_skills = data.skills || data || [];
      return this.installed_skills;
    } catch (err) {
      console.error('[BrandStore] fetchBrandSkills failed:', err);
      this.installed_skills = [];
      return [];
    }
  },

  /** 安装品牌技能 — POST /api/brand/skills */
  async installBrandSkill(name) {
    try {
      const data = await API.post('/api/brand/skills', { name });
      await this.fetchBrandSkills();
      return data;
    } catch (err) {
      console.error('[BrandStore] installBrandSkill failed:', err);
      throw err;
    }
  },

  /** 删除品牌技能 — DELETE /api/brand/skills/:name */
  async deleteBrandSkill(name) {
    try {
      await API.del(`/api/brand/skills/${encodeURIComponent(name)}`);
      this.installed_skills = this.installed_skills.filter(s => (s.name || s) !== name);
      return true;
    } catch (err) {
      console.error('[BrandStore] deleteBrandSkill failed:', err);
      throw err;
    }
  },
};

// ── BrandView: 品牌管理面板渲染 ──────────────────────────────
const BrandView = {
  /** 初始化品牌面板 */
  init() {
    console.log('[BrandView] initialized');
  },

  /** 加载并渲染品牌面板 */
  async load() {
    const content = document.getElementById('brand-content');
    if (!content) return;
    content.innerHTML = '<div class="text-center"><div class="spinner" style="margin:40px auto"></div></div>';

    try {
      await Promise.all([
        BrandStore.fetchBrandStatus(),
        BrandStore.fetchBrandSkills(),
      ]);
      this.renderBrandPanel();
    } catch (err) {
      content.innerHTML = '<p class="text-muted text-center">Failed to load brand info</p>';
    }
  },

  /** 渲染品牌管理面板 */
  renderBrandPanel() {
    const container = document.getElementById('brand-content');
    if (!container) return;

    const status = BrandStore.license_status;
    const config = BrandStore.brand_config || {};
    const skills = BrandStore.installed_skills;

    const statusBadge = status === 'active'
      ? '<span class="brand-status-badge active">Active</span>'
      : status === 'trial'
        ? '<span class="brand-status-badge trial">Trial</span>'
        : '<span class="brand-status-badge inactive">Inactive</span>';

    const skillsHtml = skills.length === 0
      ? '<p class="text-muted" style="font-size:13px">No brand skills installed</p>'
      : skills.map(s => {
          const name = typeof s === 'string' ? s : (s.name || 'Unknown');
          const desc = typeof s === 'object' ? (s.description || '') : '';
          return `
            <div class="skill-card" style="margin-bottom:8px">
              <div style="display:flex;align-items:center;justify-content:space-between">
                <div>
                  <div class="skill-card-name">${this._esc(name)}</div>
                  ${desc ? `<div class="skill-card-desc">${this._esc(desc)}</div>` : ''}
                </div>
                <button class="btn btn-danger btn-sm" onclick="BrandView.handleDeleteSkill('${this._esc(name)}')">Delete</button>
              </div>
            </div>`;
        }).join('');

    container.innerHTML = `
      <div class="settings-group">
        <div class="settings-group-title" style="display:flex;align-items:center;justify-content:space-between">
          <span>License Status</span>
          ${statusBadge}
        </div>
        <div class="brand-info-card">
          <div class="settings-field">
            <label>Product Name</label>
            <div class="text-muted">${this._esc(config.product_name || 'MBOpenClacky')}</div>
          </div>
          ${status !== 'active' ? `
            <div class="settings-field">
              <label for="brand-license-key">License Key</label>
              <input type="text" id="brand-license-key" placeholder="Enter license key...">
              <div class="help-text">Enter your license key to activate branding</div>
            </div>
            <div style="display:flex;gap:8px;margin-top:8px">
              <button class="btn btn-primary" onclick="BrandView.handleActivate()">Activate</button>
            </div>
          ` : `
            <div style="margin-top:12px">
              <button class="btn btn-danger btn-sm" onclick="BrandView.handleDeactivate()">Deactivate License</button>
            </div>
          `}
        </div>
      </div>

      <div class="settings-group">
        <div class="settings-group-title" style="display:flex;align-items:center;justify-content:space-between">
          <span>Brand Skills (${skills.length})</span>
          <button class="btn btn-primary btn-sm" onclick="BrandView.handleInstallSkill()">+ Install Skill</button>
        </div>
        <div id="brand-skills-list">${skillsHtml}</div>
      </div>`;
  },

  /** 激活许可证 */
  async handleActivate() {
    const input = document.getElementById('brand-license-key');
    const key = input ? input.value.trim() : '';
    if (!key) {
      App.showNotification('Please enter a license key', 'warning');
      return;
    }
    try {
      const data = await BrandStore.activateLicense(key);
      if (data.ok || data.status === 'active') {
        App.showNotification('License activated successfully', 'success');
        this.renderBrandPanel();
      } else {
        App.showNotification(data.error || 'Activation failed', 'error');
      }
    } catch (err) {
      App.showNotification('Activation failed: ' + err.message, 'error');
    }
  },

  /** 停用许可证 */
  async handleDeactivate() {
    if (!confirm('Deactivate license? This will remove brand customization.')) return;
    try {
      await BrandStore.deactivateLicense();
      App.showNotification('License deactivated', 'info');
      this.renderBrandPanel();
    } catch (err) {
      App.showNotification('Deactivation failed: ' + err.message, 'error');
    }
  },

  /** 安装品牌技能 */
  async handleInstallSkill() {
    const html = `
      <div class="settings-field">
        <label for="brand-skill-name">Skill Name</label>
        <input type="text" id="brand-skill-name" placeholder="Enter skill name...">
        <div class="help-text">Name of the brand skill to install</div>
      </div>`;
    const footer = `
      <button class="btn btn-ghost" onclick="App.hideModal()">Cancel</button>
      <button class="btn btn-primary" onclick="BrandView.doInstallSkill()">Install</button>`;
    App.showModal('Install Brand Skill', html, footer);
    setTimeout(() => {
      const inp = document.getElementById('brand-skill-name');
      if (inp) inp.focus();
    }, 100);
  },

  /** 执行安装技能 */
  async doInstallSkill() {
    const input = document.getElementById('brand-skill-name');
    const name = input ? input.value.trim() : '';
    if (!name) { App.showNotification('Skill name is required', 'warning'); return; }
    try {
      await BrandStore.installBrandSkill(name);
      App.showNotification(`Skill "${name}" installed`, 'success');
      App.hideModal();
      this.renderBrandPanel();
    } catch (err) {
      App.showNotification('Install failed: ' + err.message, 'error');
    }
  },

  /** 删除品牌技能 */
  async handleDeleteSkill(name) {
    if (!confirm(`Delete brand skill "${name}"?`)) return;
    try {
      await BrandStore.deleteBrandSkill(name);
      App.showNotification(`Skill "${name}" deleted`, 'success');
      this.renderBrandPanel();
    } catch (err) {
      App.showNotification('Delete failed: ' + err.message, 'error');
    }
  },

  /** HTML 转义 */
  _esc(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  },
};
