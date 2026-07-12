// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Tasks Panel (Client-side Todo Manager)
// ═══════════════════════════════════════════════════════════════

// ── TaskStore: 客户端任务状态管理 ──────────────────────────────
const TaskStore = {
  tasks: [],
  next_id: 1,

  /** 加载任务（localStorage 持久化） */
  load() {
    try {
      const raw = localStorage.getItem('mbopenclacky_tasks');
      if (raw) {
        const data = JSON.parse(raw);
        this.tasks = data.tasks || [];
        this.next_id = data.next_id || 1;
      }
    } catch (e) {
      this.tasks = [];
      this.next_id = 1;
    }
  },

  /** 保存任务到 localStorage */
  save() {
    try {
      localStorage.setItem('mbopenclacky_tasks', JSON.stringify({
        tasks: this.tasks,
        next_id: this.next_id,
      }));
    } catch (e) {
      console.error('[TaskStore] save failed:', e);
    }
  },

  /** 添加任务 */
  add(title, priority = 'normal') {
    const task = {
      id: this.next_id++,
      title,
      priority,   // 'low' | 'normal' | 'high'
      done: false,
      created_at: new Date().toISOString(),
      completed_at: null,
    };
    this.tasks.unshift(task);
    this.save();
    return task;
  },

  /** 切换完成状态 */
  toggle(id) {
    const task = this.tasks.find(t => t.id === id);
    if (task) {
      task.done = !task.done;
      task.completed_at = task.done ? new Date().toISOString() : null;
      this.save();
    }
    return task;
  },

  /** 删除任务 */
  remove(id) {
    this.tasks = this.tasks.filter(t => t.id !== id);
    this.save();
  },

  /** 更新任务 */
  update(id, updates) {
    const task = this.tasks.find(t => t.id === id);
    if (task) {
      Object.assign(task, updates);
      this.save();
    }
    return task;
  },

  /** 清除已完成 */
  clearCompleted() {
    this.tasks = this.tasks.filter(t => !t.done);
    this.save();
  },

  /** 按过滤获取 */
  getFiltered(filter) {
    switch (filter) {
      case 'active': return this.tasks.filter(t => !t.done);
      case 'completed': return this.tasks.filter(t => t.done);
      default: return this.tasks;
    }
  },

  /** 统计 */
  stats() {
    const total = this.tasks.length;
    const done = this.tasks.filter(t => t.done).length;
    return { total, active: total - done, completed: done };
  },
};

// ── TaskView: 任务面板渲染 ─────────────────────────────────────
const TaskView = {
  filter: 'all', // 'all' | 'active' | 'completed'

  init() {
    TaskStore.load();
    console.log('[TaskView] initialized');
  },

  async load() {
    this.renderTaskPanel();
  },

  renderTaskPanel() {
    const container = document.getElementById('tasks-content');
    if (!container) return;

    const stats = TaskStore.stats();
    const tasks = TaskStore.getFiltered(this.filter);

    const filterBtns = ['all', 'active', 'completed'].map(f => {
      const label = I18n.t(`tasks.filter_${f}`) || f;
      const count = f === 'all' ? stats.total : (f === 'active' ? stats.active : stats.completed);
      return `<button class="skills-tab ${this.filter === f ? 'active' : ''}" onclick="TaskView.setFilter('${f}')">${label} (${count})</button>`;
    }).join('');

    const tasksHtml = tasks.length === 0
      ? `<div class="empty-state" style="padding:32px">
          <div class="empty-state-icon">&#9745;</div>
          <h3>${I18n.t('tasks.empty')}</h3>
          <p class="text-muted">${I18n.t('tasks.empty_desc')}</p>
        </div>`
      : tasks.map(t => this._renderTaskItem(t)).join('');

    container.innerHTML = `
      <div class="settings-group">
        <div class="settings-group-title" style="display:flex;align-items:center;justify-content:space-between">
          <span>${I18n.t('tasks.title')} (${stats.active} ${I18n.t('tasks.remaining')})</span>
          <div style="display:flex;gap:6px">
            ${stats.completed > 0 ? `<button class="btn btn-ghost btn-sm" onclick="TaskView.handleClearCompleted()">${I18n.t('tasks.clear_done')}</button>` : ''}
            <button class="btn btn-primary btn-sm" onclick="TaskView.handleAdd()">+ ${I18n.t('tasks.add')}</button>
          </div>
        </div>
        <div class="skills-tabs" style="margin-bottom:12px">${filterBtns}</div>
        <div class="task-list" id="task-list">${tasksHtml}</div>
      </div>`;
  },

  _renderTaskItem(task) {
    const priorityColors = { high: 'var(--danger)', normal: 'var(--accent)', low: 'var(--text-muted)' };
    const priorityLabels = { high: I18n.t('tasks.priority_high'), normal: I18n.t('tasks.priority_normal'), low: I18n.t('tasks.priority_low') };
    const color = priorityColors[task.priority] || priorityColors.normal;
    const doneStyle = task.done ? 'text-decoration:line-through;opacity:0.5' : '';

    return `
      <div class="task-item skill-card" style="padding:12px 16px;margin-bottom:8px;display:flex;align-items:center;gap:12px;${doneStyle}">
        <div class="toggle ${task.done ? 'active' : ''}" onclick="TaskView.handleToggle(${task.id})" style="flex-shrink:0"></div>
        <div style="flex:1;min-width:0">
          <div style="font-size:13px;font-weight:500;color:var(--text-primary);overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${this._esc(task.title)}</div>
          <div style="font-size:11px;color:var(--text-muted);margin-top:2px">
            <span style="color:${color}">${priorityLabels[task.priority] || task.priority}</span>
            ${task.completed_at ? ` &middot; ${I18n.t('tasks.completed_at')} ${this._formatTime(task.completed_at)}` : ''}
          </div>
        </div>
        <div style="display:flex;gap:4px;flex-shrink:0">
          <button class="btn btn-ghost btn-sm" onclick="TaskView.handleEdit(${task.id})" title="${I18n.t('common.edit')}">&#9998;</button>
          <button class="btn btn-ghost btn-sm" onclick="TaskView.handlePriority(${task.id})" title="${I18n.t('tasks.priority')}" style="color:${color}">&#9873;</button>
          <button class="btn btn-danger btn-sm" onclick="TaskView.handleDelete(${task.id})" title="${I18n.t('common.delete')}">&#128465;</button>
        </div>
      </div>`;
  },

  setFilter(f) {
    this.filter = f;
    this.renderTaskPanel();
  },

  handleAdd() {
    const html = `
      <div class="settings-field">
        <label for="task-title">${I18n.t('tasks.task_name')}</label>
        <input type="text" id="task-title" placeholder="${I18n.t('tasks.task_placeholder')}">
      </div>
      <div class="settings-field">
        <label for="task-priority">${I18n.t('tasks.priority')}</label>
        <select id="task-priority">
          <option value="low">${I18n.t('tasks.priority_low')}</option>
          <option value="normal" selected>${I18n.t('tasks.priority_normal')}</option>
          <option value="high">${I18n.t('tasks.priority_high')}</option>
        </select>
      </div>`;
    const footer = `
      <button class="btn btn-ghost" onclick="App.hideModal()">${I18n.t('common.cancel')}</button>
      <button class="btn btn-primary" onclick="TaskView.doAdd()">${I18n.t('tasks.add')}</button>`;
    App.showModal(I18n.t('tasks.add_task'), html, footer);
    setTimeout(() => document.getElementById('task-title')?.focus(), 100);
  },

  doAdd() {
    const title = document.getElementById('task-title')?.value.trim();
    const priority = document.getElementById('task-priority')?.value || 'normal';
    if (!title) { App.showNotification(I18n.t('tasks.required_title'), 'warning'); return; }
    TaskStore.add(title, priority);
    App.hideModal();
    this.renderTaskPanel();
  },

  handleToggle(id) {
    TaskStore.toggle(id);
    this.renderTaskPanel();
  },

  handleDelete(id) {
    if (!confirm(I18n.t('tasks.delete_confirm'))) return;
    TaskStore.remove(id);
    this.renderTaskPanel();
  },

  handleEdit(id) {
    const task = TaskStore.tasks.find(t => t.id === id);
    if (!task) return;
    const html = `
      <div class="settings-field">
        <label for="task-edit-title">${I18n.t('tasks.task_name')}</label>
        <input type="text" id="task-edit-title" value="${this._esc(task.title)}">
      </div>`;
    const footer = `
      <button class="btn btn-ghost" onclick="App.hideModal()">${I18n.t('common.cancel')}</button>
      <button class="btn btn-primary" onclick="TaskView.doEdit(${id})">${I18n.t('common.save')}</button>`;
    App.showModal(I18n.t('tasks.edit_task'), html, footer);
    setTimeout(() => document.getElementById('task-edit-title')?.focus(), 100);
  },

  doEdit(id) {
    const title = document.getElementById('task-edit-title')?.value.trim();
    if (!title) { App.showNotification(I18n.t('tasks.required_title'), 'warning'); return; }
    TaskStore.update(id, { title });
    App.hideModal();
    this.renderTaskPanel();
  },

  handlePriority(id) {
    const task = TaskStore.tasks.find(t => t.id === id);
    if (!task) return;
    const cycle = { low: 'normal', normal: 'high', high: 'low' };
    TaskStore.update(id, { priority: cycle[task.priority] || 'normal' });
    this.renderTaskPanel();
  },

  handleClearCompleted() {
    if (!confirm(I18n.t('tasks.clear_confirm'))) return;
    TaskStore.clearCompleted();
    this.renderTaskPanel();
  },

  _formatTime(iso) {
    try { return new Date(iso).toLocaleString(); } catch { return ''; }
  },

  _esc(text) {
    const div = document.createElement('div');
    div.textContent = text || '';
    return div.innerHTML;
  },
};
