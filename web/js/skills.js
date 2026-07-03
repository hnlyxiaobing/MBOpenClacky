// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Skills Module
// ═══════════════════════════════════════════════════════════════

const Skills = {
  skills: [],

  /**
   * Initialize skills module
   */
  init() {
    // Skills view can be accessed from chat tools panel or future nav
  },

  /**
   * Load available skills/tools for current session
   */
  async loadSkills() {
    if (!App.currentSessionId) {
      this.skills = [];
      this.renderSkillsList();
      return;
    }

    try {
      const res = await fetch(`/api/sessions/${App.currentSessionId}/tools`);
      if (!res.ok) throw new Error('Failed to load skills');

      const data = await res.json();
      this.skills = data.tools || [];
      this.renderSkillsList();
    } catch (err) {
      console.error('[Skills] Load failed:', err);
      this.skills = [];
      this.renderSkillsList();
    }
  },

  /**
   * Render the skills list/grid
   */
  renderSkillsList() {
    const container = document.getElementById('skills-content');

    if (this.skills.length === 0) {
      container.innerHTML = `
        <div class="empty-state">
          <div class="empty-state-icon">&#128736;</div>
          <h3>${I18n.t('skills.no_skills')}</h3>
          <p>${I18n.t('skills.no_skills_desc')}</p>
        </div>`;
      return;
    }

    const cards = this.skills.map(skill => this.renderSkillCard(skill)).join('');
    container.innerHTML = `
      <div style="margin-bottom:16px">
        <p class="text-muted" style="font-size:12px">${this.skills.length} ${I18n.t('skills.tools_available')}</p>
      </div>
      <div class="skills-grid">${cards}</div>`;
  },

  /**
   * Render a single skill card
   */
  renderSkillCard(skill) {
    const name = skill.name || 'Unknown';
    const description = skill.description || I18n.t('skills.no_description');
    const icon = this.getSkillIcon(name);

    return `
      <div class="skill-card" data-skill="${Chat.escapeHtml(name)}">
        <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px">
          <span style="font-size:20px">${icon}</span>
          <div class="skill-card-name">${Chat.escapeHtml(name)}</div>
        </div>
        <div class="skill-card-desc">${Chat.escapeHtml(description.slice(0, 150))}${description.length > 150 ? '...' : ''}</div>
      </div>`;
  },

  /**
   * Get an icon for a skill based on its name
   */
  getSkillIcon(name) {
    const lower = name.toLowerCase();
    if (lower.includes('file') || lower.includes('read')) return '&#128196;';
    if (lower.includes('write') || lower.includes('edit')) return '&#9998;';
    if (lower.includes('search') || lower.includes('grep') || lower.includes('glob')) return '&#128269;';
    if (lower.includes('web') || lower.includes('fetch')) return '&#127760;';
    if (lower.includes('terminal') || lower.includes('bash') || lower.includes('exec')) return '&#128187;';
    if (lower.includes('git')) return '&#128194;';
    if (lower.includes('test')) return '&#9989;';
    return '&#9881;';
  },

  /**
   * Invoke a skill (send as chat message with tool hint)
   */
  async invokeSkill(name) {
    if (!App.currentSessionId) {
      App.showNotification(I18n.t('skills.no_active'), 'warning');
      return;
    }

    // Prompt user for input
    const html = `
      <div class="settings-field">
        <label for="skill-input">${I18n.t('skills.command_for')} ${Chat.escapeHtml(name)}</label>
        <textarea id="skill-input" rows="3" placeholder="${I18n.t('skills.input_placeholder')}" style="width:100%;padding:9px 12px;background:var(--bg-tertiary);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text-primary);font-size:13px;resize:vertical;outline:none;font-family:var(--font-mono)"></textarea>
      </div>`;

    const footer = `
      <button class="btn btn-ghost" onclick="App.hideModal()">${I18n.t('common.cancel')}</button>
      <button class="btn btn-primary" onclick="Skills.executeSkill('${Chat.escapeHtml(name)}')">${I18n.t('skills.execute')}</button>`;

    App.showModal(`${I18n.t('skills.invoke')} ${name}`, html, footer);

    setTimeout(() => {
      const input = document.getElementById('skill-input');
      if (input) input.focus();
    }, 100);
  },

  /**
   * Execute a skill command
   */
  executeSkill(name) {
    const input = document.getElementById('skill-input');
    const text = input ? input.value.trim() : '';
    App.hideModal();

    // Send as a chat message mentioning the tool
    const message = text ? `Use the ${name} tool: ${text}` : `Use the ${name} tool`;
    Chat.sendMessage(message);
  },
};
