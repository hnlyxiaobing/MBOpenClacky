// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Enhanced Skills Manager
// ═══════════════════════════════════════════════════════════════

// ── SkillEditorStore: 技能编辑器状态管理 ─────────────────────
const SkillEditorStore = {
  current_skill: null,    // 当前选中的技能名
  content: '',            // 技能内容（代码）
  modified: false,        // 是否有未保存的修改
  skills_list: [],        // 所有技能列表
  store_skills: [],       // 技能商店列表
  creator_skills: [],     // 创建者技能列表

  /** 获取技能内容 — GET /api/skills/:name/content */
  async fetchSkillContent(name) {
    try {
      const data = await API.get(`/api/skills/${encodeURIComponent(name)}/content`);
      this.current_skill = name;
      this.content = data.content || data.text || '';
      this.modified = false;
      return this.content;
    } catch (err) {
      console.error('[SkillEditorStore] fetchSkillContent failed:', err);
      throw err;
    }
  },

  /** 保存技能内容 — PUT /api/skills/:name/content */
  async saveSkillContent(name, content) {
    try {
      const data = await API.put(`/api/skills/${encodeURIComponent(name)}/content`, { content });
      this.content = content;
      this.modified = false;
      return data;
    } catch (err) {
      console.error('[SkillEditorStore] saveSkillContent failed:', err);
      throw err;
    }
  },

  /** 切换技能启用状态 — PATCH /api/skills/:name/toggle */
  async toggleSkill(name, enabled) {
    try {
      const data = await API.post(`/api/skills/${encodeURIComponent(name)}/toggle`, { enabled });
      return data;
    } catch (err) {
      console.error('[SkillEditorStore] toggleSkill failed:', err);
      throw err;
    }
  },

  /** 删除技能 — DELETE /api/skills/:name */
  async deleteSkill(name) {
    try {
      await API.del(`/api/skills/${encodeURIComponent(name)}`);
      this.skills_list = this.skills_list.filter(s => (s.name || s) !== name);
      if (this.current_skill === name) {
        this.current_skill = null;
        this.content = '';
        this.modified = false;
      }
      return true;
    } catch (err) {
      console.error('[SkillEditorStore] deleteSkill failed:', err);
      throw err;
    }
  },

  /** 获取技能商店列表 — GET /api/store/skills */
  async fetchStoreSkills() {
    try {
      const data = await API.get('/api/store/skills');
      this.store_skills = data.skills || data || [];
      return this.store_skills;
    } catch (err) {
      console.error('[SkillEditorStore] fetchStoreSkills failed:', err);
      this.store_skills = [];
      return [];
    }
  },

  /** 获取创建者技能列表 — GET /api/creator/skills */
  async fetchCreatorSkills() {
    try {
      const data = await API.get('/api/creator/skills');
      this.creator_skills = data.skills || data || [];
      return this.creator_skills;
    } catch (err) {
      console.error('[SkillEditorStore] fetchCreatorSkills failed:', err);
      this.creator_skills = [];
      return [];
    }
  },
};

// ── SkillEditorView: 增强版技能管理视图 ──────────────────────
const SkillEditorView = {
  activeTab: 'installed', // 'installed' | 'store' | 'creator'

  /** 初始化 */
  init() {
    console.log('[SkillEditorView] initialized');
  },

  /** 加载数据并渲染 */
  async load() {
    const content = document.getElementById('skills-enhanced-content');
    if (!content) return;
    content.innerHTML = '<div class="text-center"><div class="spinner" style="margin:40px auto"></div></div>';

    try {
      const [storeSkills, creatorSkills, installed] = await Promise.all([
        SkillEditorStore.fetchStoreSkills(),
        SkillEditorStore.fetchCreatorSkills(),
        API.get('/api/skills').catch(() => null),
      ]);
      SkillEditorStore.skills_list = (installed && installed.skills) || (typeof Skills !== 'undefined' ? Skills.skills : []) || [];      this.renderSkillPanel();
    } catch (err) {
      content.innerHTML = '<p class="text-muted text-center">Failed to load skills</p>';
    }
  },

  /** 渲染技能面板 */
  renderSkillPanel() {
    const container = document.getElementById('skills-enhanced-content');
    if (!container) return;

    container.innerHTML = `
      <div class="skills-tabs">
        <button class="skills-tab ${this.activeTab === 'installed' ? 'active' : ''}" data-tab="installed" onclick="SkillEditorView.switchTab('installed')">Installed</button>
        <button class="skills-tab ${this.activeTab === 'store' ? 'active' : ''}" data-tab="store" onclick="SkillEditorView.switchTab('store')">Store</button>
        <button class="skills-tab ${this.activeTab === 'creator' ? 'active' : ''}" data-tab="creator" onclick="SkillEditorView.switchTab('creator')">My Skills</button>
      </div>
      <div class="skills-tab-body">
        <div id="skills-pane-installed" style="display:${this.activeTab === 'installed' ? '' : 'none'}">${this._renderInstalled()}</div>
        <div id="skills-pane-store" style="display:${this.activeTab === 'store' ? '' : 'none'}">${this._renderStore()}</div>
        <div id="skills-pane-creator" style="display:${this.activeTab === 'creator' ? '' : 'none'}">${this._renderCreator()}</div>
      </div>
      <div id="skill-editor-area" class="skill-editor-area" style="display:none">
        <div class="skill-editor-header">
          <span id="skill-editor-title" class="skill-editor-title"></span>
          <div class="skill-editor-actions">
            <button class="btn btn-primary btn-sm" onclick="SkillEditorView.handleSave()" id="btn-skill-save">Save</button>
            <button class="btn btn-ghost btn-sm" onclick="SkillEditorView.closeEditor()">Close</button>
          </div>
        </div>
        <textarea id="skill-editor-textarea" class="skill-editor-textarea" spellcheck="false"></textarea>
      </div>`;

    // 绑定编辑器 change 事件
    const textarea = document.getElementById('skill-editor-textarea');
    if (textarea) {
      textarea.addEventListener('input', () => {
        SkillEditorStore.modified = true;
        const saveBtn = document.getElementById('btn-skill-save');
        if (saveBtn) saveBtn.disabled = false;
      });
    }
  },

  /** 切换标签 */
  switchTab(tab) {
    this.activeTab = tab;
    this.renderSkillPanel();
  },

  /** 渲染已安装技能 */
  _renderInstalled() {
    const skills = SkillEditorStore.skills_list;
    if (skills.length === 0) {
      return '<p class="text-muted" style="padding:16px 0">No skills installed. Browse the store to find skills.</p>';
    }
    return `<div class="skills-grid">${skills.map(s => {
      const name = s.name || (typeof s === 'string' ? s : 'Unknown');
      const desc = s.description || 'No description';
      const enabled = s.enabled !== false;
      return `
        <div class="skill-card">
          <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:8px">
            <div class="skill-card-name">${this._esc(name)}</div>
            <div class="toggle ${enabled ? 'active' : ''}" onclick="SkillEditorView.handleToggle('${this._esc(name)}', this)"></div>
          </div>
          <div class="skill-card-desc">${this._esc(desc.slice(0, 120))}</div>
          <div style="display:flex;gap:6px;margin-top:10px">
            <button class="btn btn-ghost btn-sm" onclick="SkillEditorView.openEditor('${this._esc(name)}')">Edit</button>
            <button class="btn btn-danger btn-sm" onclick="SkillEditorView.handleDelete('${this._esc(name)}')">Delete</button>
          </div>
        </div>`;
    }).join('')}</div>`;
  },

  /** 渲染技能商店 */
  _renderStore() {
    const skills = SkillEditorStore.store_skills;
    if (skills.length === 0) {
      return '<p class="text-muted" style="padding:16px 0">No skills available in the store.</p>';
    }
    return `<div class="skills-grid">${skills.map(s => {
      const name = s.name || 'Unknown';
      const desc = s.description || '';
      const author = s.author || '';
      return `
        <div class="skill-card">
          <div class="skill-card-name">${this._esc(name)}</div>
          ${author ? `<div class="skill-card-desc" style="color:var(--accent)">by ${this._esc(author)}</div>` : ''}
          <div class="skill-card-desc">${this._esc(desc.slice(0, 120))}</div>
          <button class="btn btn-primary btn-sm" style="margin-top:10px" onclick="SkillEditorView.handleInstallFromStore('${this._esc(name)}')">Install</button>
        </div>`;
    }).join('')}</div>`;
  },

  /** 渲染创建者技能 */
  _renderCreator() {
    const skills = SkillEditorStore.creator_skills;
    if (skills.length === 0) {
      return '<p class="text-muted" style="padding:16px 0">You haven\'t created any skills yet.</p>';
    }
    return `<div class="skills-grid">${skills.map(s => {
      const name = s.name || 'Unknown';
      const desc = s.description || '';
      const published = s.published || false;
      return `
        <div class="skill-card">
          <div style="display:flex;align-items:center;gap:8px;margin-bottom:6px">
            <div class="skill-card-name">${this._esc(name)}</div>
            ${published ? '<span class="brand-status-badge active">Published</span>' : '<span class="brand-status-badge inactive">Draft</span>'}
          </div>
          <div class="skill-card-desc">${this._esc(desc.slice(0, 120))}</div>
          <div style="display:flex;gap:6px;margin-top:10px">
            <button class="btn btn-ghost btn-sm" onclick="SkillEditorView.openEditor('${this._esc(name)}')">Edit</button>
          </div>
        </div>`;
    }).join('')}</div>`;
  },

  /** 打开编辑器 */
  async openEditor(name) {
    try {
      const content = await SkillEditorStore.fetchSkillContent(name);
      const editorArea = document.getElementById('skill-editor-area');
      const textarea = document.getElementById('skill-editor-textarea');
      const title = document.getElementById('skill-editor-title');
      if (editorArea) editorArea.style.display = '';
      if (textarea) textarea.value = content;
      if (title) title.textContent = name;
    } catch (err) {
      App.showNotification('Failed to load skill content: ' + err.message, 'error');
    }
  },

  /** 关闭编辑器 */
  closeEditor() {
    if (SkillEditorStore.modified) {
      if (!confirm('You have unsaved changes. Discard?')) return;
    }
    const editorArea = document.getElementById('skill-editor-area');
    if (editorArea) editorArea.style.display = 'none';
    SkillEditorStore.current_skill = null;
    SkillEditorStore.content = '';
    SkillEditorStore.modified = false;
  },

  /** 保存技能内容 */
  async handleSave() {
    const textarea = document.getElementById('skill-editor-textarea');
    const content = textarea ? textarea.value : '';
    const name = SkillEditorStore.current_skill;
    if (!name) return;
    try {
      await SkillEditorStore.saveSkillContent(name, content);
      App.showNotification(`Skill "${name}" saved`, 'success');
      const saveBtn = document.getElementById('btn-skill-save');
      if (saveBtn) saveBtn.disabled = true;
    } catch (err) {
      App.showNotification('Save failed: ' + err.message, 'error');
    }
  },

  /** 切换技能启用 */
  async handleToggle(name, toggleEl) {
    const enabled = !toggleEl.classList.contains('active');
    try {
      await SkillEditorStore.toggleSkill(name, enabled);
      toggleEl.classList.toggle('active', enabled);
      App.showNotification(`Skill "${name}" ${enabled ? 'enabled' : 'disabled'}`, 'info');
    } catch (err) {
      App.showNotification('Toggle failed: ' + err.message, 'error');
    }
  },

  /** 删除技能 */
  async handleDelete(name) {
    if (!confirm(`Delete skill "${name}"? This cannot be undone.`)) return;
    try {
      await SkillEditorStore.deleteSkill(name);
      App.showNotification(`Skill "${name}" deleted`, 'success');
      this.renderSkillPanel();
    } catch (err) {
      App.showNotification('Delete failed: ' + err.message, 'error');
    }
  },

  /** 从商店安装技能 */
  async handleInstallFromStore(name) {
    try {
      await API.post('/api/skills/install', { name });
      App.showNotification(`Skill "${name}" installed from store`, 'success');
      await SkillEditorStore.fetchStoreSkills();
      this.renderSkillPanel();
    } catch (err) {
      App.showNotification('Install failed: ' + err.message, 'error');
    }
  },

  /** HTML 转义 */
  _esc(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  },
};
