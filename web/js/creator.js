// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Creator Panel
// ═══════════════════════════════════════════════════════════════

// ── CreatorStore: 创建者状态管理 ─────────────────────────────
const CreatorStore = {
  my_skills: [],
  publishing: false,

  /** 获取我的技能列表 — GET /api/creator/skills */
  async fetchMySkills() {
    try {
      const data = await API.get('/api/creator/skills');
      this.my_skills = data.skills || data || [];
      return this.my_skills;
    } catch (err) {
      console.error('[CreatorStore] fetchMySkills failed:', err);
      this.my_skills = [];
      return [];
    }
  },

  /** 发布技能 — POST /api/my-skills/:name/publish */
  async publishSkill(name) {
    this.publishing = true;
    try {
      const data = await API.post(`/api/my-skills/${encodeURIComponent(name)}/publish`, {});
      // 更新本地状态
      const skill = this.my_skills.find(s => (s.name || s) === name);
      if (skill && typeof skill === 'object') skill.published = true;
      return data;
    } catch (err) {
      console.error('[CreatorStore] publishSkill failed:', err);
      throw err;
    } finally {
      this.publishing = false;
    }
  },
};

// ── CreatorView: 创建者面板渲染 ──────────────────────────────
const CreatorView = {
  /** 初始化 */
  init() {
    console.log('[CreatorView] initialized');
  },

  /** 加载并渲染 */
  async load() {
    const content = document.getElementById('creator-content');
    if (!content) return;
    content.innerHTML = '<div class="text-center"><div class="spinner" style="margin:40px auto"></div></div>';

    await CreatorStore.fetchMySkills();
    this.renderCreatorPanel();
  },

  /** 渲染创建者面板 */
  renderCreatorPanel() {
    const container = document.getElementById('creator-content');
    if (!container) return;

    const skills = CreatorStore.my_skills;
    const publishing = CreatorStore.publishing;

    const skillsHtml = skills.length === 0
      ? `
        <div class="empty-state" style="padding:32px">
          <div class="empty-state-icon">&#128221;</div>
          <h3>No Skills Created</h3>
          <p>Create skills using the skill editor to publish them to the store.</p>
        </div>`
      : `<div class="skills-grid">${skills.map(s => {
          const name = typeof s === 'string' ? s : (s.name || 'Unknown');
          const desc = typeof s === 'object' ? (s.description || '') : '';
          const published = typeof s === 'object' ? s.published : false;
          const downloads = typeof s === 'object' ? (s.downloads || 0) : 0;
          const version = typeof s === 'object' ? (s.version || '') : '';

          return `
            <div class="skill-card">
              <div style="display:flex;align-items:center;gap:8px;margin-bottom:6px">
                <div class="skill-card-name">${this._esc(name)}</div>
                ${published
                  ? '<span class="brand-status-badge active">Published</span>'
                  : '<span class="brand-status-badge inactive">Draft</span>'}
              </div>
              ${desc ? `<div class="skill-card-desc">${this._esc(desc.slice(0, 100))}</div>` : ''}
              ${version ? `<div class="skill-card-desc" style="font-size:11px">v${this._esc(version)}</div>` : ''}
              ${published ? `<div class="skill-card-desc" style="font-size:11px;color:var(--text-muted)">${downloads} downloads</div>` : ''}
              <div style="display:flex;gap:6px;margin-top:10px">
                ${!published ? `<button class="btn btn-primary btn-sm" onclick="CreatorView.handlePublish('${this._esc(name)}')" ${publishing ? 'disabled' : ''}>Publish</button>` : ''}
                <button class="btn btn-ghost btn-sm" onclick="SkillEditorView.openEditor('${this._esc(name)}')">Edit</button>
              </div>
            </div>`;
        }).join('')}</div>`;

    container.innerHTML = `
      <div class="settings-group">
        <div class="settings-group-title" style="display:flex;align-items:center;justify-content:space-between">
          <span>My Skills (${skills.length})</span>
          <button class="btn btn-primary btn-sm" onclick="CreatorView.handleCreateSkill()">+ Create Skill</button>
        </div>
        <div id="creator-skills-list">${skillsHtml}</div>
      </div>

      <div class="settings-group">
        <div class="settings-group-title">Creator Guidelines</div>
        <div style="font-size:13px;color:var(--text-secondary);line-height:1.6;padding:8px 0">
          <ul style="padding-left:20px">
            <li>Skills must include a valid SKILL.md manifest</li>
            <li>Test your skill thoroughly before publishing</li>
            <li>Follow the skill naming conventions</li>
            <li>Provide clear descriptions and usage examples</li>
          </ul>
        </div>
      </div>`;
  },

  /** 发布技能 */
  async handlePublish(name) {
    if (!confirm(`Publish skill "${name}" to the store?`)) return;
    try {
      const data = await CreatorStore.publishSkill(name);
      if (data.ok || data.published) {
        App.showNotification(`Skill "${name}" published successfully!`, 'success');
        await CreatorStore.fetchMySkills();
        this.renderCreatorPanel();
      } else {
        App.showNotification(data.error || 'Publish failed', 'error');
      }
    } catch (err) {
      App.showNotification('Publish failed: ' + err.message, 'error');
    }
  },

  /** 创建新技能 */
  handleCreateSkill() {
    const html = `
      <div class="settings-field">
        <label for="new-skill-name">Skill Name</label>
        <input type="text" id="new-skill-name" placeholder="my-awesome-skill">
        <div class="help-text">Use lowercase with hyphens (e.g., my-skill-name)</div>
      </div>
      <div class="settings-field">
        <label for="new-skill-desc">Description</label>
        <textarea id="new-skill-desc" rows="3" placeholder="What does this skill do?" style="width:100%;padding:9px 12px;background:var(--bg-tertiary);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text-primary);font-size:13px;resize:vertical;outline:none"></textarea>
      </div>`;
    const footer = `
      <button class="btn btn-ghost" onclick="App.hideModal()">Cancel</button>
      <button class="btn btn-primary" onclick="CreatorView.doCreateSkill()">Create</button>`;
    App.showModal('Create New Skill', html, footer);
    setTimeout(() => {
      const inp = document.getElementById('new-skill-name');
      if (inp) inp.focus();
    }, 100);
  },

  /** 执行创建技能 */
  async doCreateSkill() {
    const nameInput = document.getElementById('new-skill-name');
    const descInput = document.getElementById('new-skill-desc');
    const name = nameInput ? nameInput.value.trim() : '';
    const desc = descInput ? descInput.value.trim() : '';

    if (!name) { App.showNotification('Skill name is required', 'warning'); return; }
    if (!/^[a-z0-9][a-z0-9-]*$/.test(name)) {
      App.showNotification('Name must be lowercase with hyphens only', 'warning');
      return;
    }

    try {
      await API.post('/api/creator/skills', { name, description: desc });
      App.showNotification(`Skill "${name}" created`, 'success');
      App.hideModal();
      await CreatorStore.fetchMySkills();
      this.renderCreatorPanel();
    } catch (err) {
      App.showNotification('Create failed: ' + err.message, 'error');
    }
  },

  /** HTML 转义 */
  _esc(text) {
    const div = document.createElement('div');
    div.textContent = text || '';
    return div.innerHTML;
  },
};
