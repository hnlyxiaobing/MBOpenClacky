// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Workspace Panel
// ═══════════════════════════════════════════════════════════════

// ── WorkspaceStore: 工作区状态管理 ───────────────────────────
const WorkspaceStore = {
  current_dir: '',
  recent_dirs: [],
  files: [],

  /** 获取目录列表 — GET /api/dirs?path= */
  async fetchDirs(path) {
    try {
      const data = await API.get(`/api/dirs?path=${encodeURIComponent(path || '')}`);
      this.files = data.files || data.dirs || data || [];
      if (path) this.current_dir = path;
      return this.files;
    } catch (err) {
      console.error('[WorkspaceStore] fetchDirs failed:', err);
      this.files = [];
      return [];
    }
  },

  /** 创建目录 — POST /api/dirs/mkdir */
  async createDir(path, name) {
    try {
      const data = await API.post('/api/dirs/mkdir', { path, name });
      return data;
    } catch (err) {
      console.error('[WorkspaceStore] createDir failed:', err);
      throw err;
    }
  },

  /** 设置工作目录 — PATCH /api/sessions/:id/working_dir */
  async setWorkingDir(dir) {
    if (!App.currentSessionId) throw new Error('No active session');
    try {
      const data = await API.post(`/api/sessions/${App.currentSessionId}/working_dir`, { working_dir: dir });
      this.current_dir = dir;
      // 添加到最近目录
      this.recent_dirs = [dir, ...this.recent_dirs.filter(d => d !== dir)].slice(0, 10);
      return data;
    } catch (err) {
      console.error('[WorkspaceStore] setWorkingDir failed:', err);
      throw err;
    }
  },
};

// ── WorkspaceView: 工作区面板渲染 ────────────────────────────
const WorkspaceView = {
  /** 初始化 */
  init() {
    console.log('[WorkspaceView] initialized');
  },

  /** 加载并渲染 */
  async load() {
    const content = document.getElementById('workspace-content');
    if (!content) return;
    content.innerHTML = '<div class="text-center"><div class="spinner" style="margin:40px auto"></div></div>';

    await WorkspaceStore.fetchDirs(WorkspaceStore.current_dir || '');
    this.renderWorkspacePanel();
  },

  /** 渲染工作区面板 */
  renderWorkspacePanel() {
    const container = document.getElementById('workspace-content');
    if (!container) return;

    const ws = WorkspaceStore;
    const files = ws.files;

    const filesHtml = files.length === 0
      ? '<p class="text-muted" style="padding:8px 0;font-size:13px">Empty directory</p>'
      : files.map(f => {
          const name = typeof f === 'string' ? f : (f.name || f.path || '');
          const isDir = typeof f === 'object' ? (f.is_dir || f.type === 'dir') : !name.includes('.');
          const icon = isDir ? '&#128193;' : '&#128196;';
          return `
            <div class="workspace-file-item" ${isDir ? `onclick="WorkspaceView.navigateTo('${this._esc(name)}')"` : ''} style="${isDir ? 'cursor:pointer' : ''}">
              <span class="workspace-file-icon">${icon}</span>
              <span class="workspace-file-name">${this._esc(name)}</span>
            </div>`;
        }).join('');

    const recentHtml = ws.recent_dirs.length === 0
      ? '<p class="text-muted" style="font-size:12px">No recent directories</p>'
      : ws.recent_dirs.map(d => `
          <div class="workspace-recent-item" onclick="WorkspaceView.setDir('${this._esc(d)}')" style="cursor:pointer;padding:4px 0;font-size:12px;color:var(--accent)">
            ${this._esc(d)}
          </div>`).join('');

    container.innerHTML = `
      <div class="settings-group">
        <div class="settings-group-title">Current Working Directory</div>
        <div class="settings-field">
          <div style="display:flex;gap:8px;align-items:center">
            <input type="text" id="workspace-path-input" value="${this._esc(ws.current_dir)}" placeholder="/path/to/project" style="flex:1;padding:9px 12px;background:var(--bg-tertiary);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text-primary);font-size:13px;font-family:var(--font-mono);outline:none">
            <button class="btn btn-primary btn-sm" onclick="WorkspaceView.handleSetDir()">Set</button>
          </div>
          <div class="help-text">Working directory for the current session</div>
        </div>
      </div>

      <div class="settings-group">
        <div class="settings-group-title" style="display:flex;align-items:center;justify-content:space-between">
          <span>Directory Browser</span>
          <div style="display:flex;gap:6px">
            <button class="btn btn-ghost btn-sm" onclick="WorkspaceView.navigateUp()">Up</button>
            <button class="btn btn-ghost btn-sm" onclick="WorkspaceView.handleMkdir()">+ New Folder</button>
          </div>
        </div>
        <div class="workspace-file-list">${filesHtml}</div>
      </div>

      <div class="settings-group">
        <div class="settings-group-title">Recent Directories</div>
        <div id="workspace-recent-list">${recentHtml}</div>
      </div>`;
  },

  /** 导航到子目录 */
  async navigateTo(name) {
    const current = WorkspaceStore.current_dir;
    const newPath = current ? `${current}/${name}` : name;
    await WorkspaceStore.fetchDirs(newPath);
    this.renderWorkspacePanel();
  },

  /** 导航到父目录 */
  async navigateUp() {
    const current = WorkspaceStore.current_dir;
    if (!current || current === '/' || current === '.') return;
    const parent = current.split('/').slice(0, -1).join('/') || '/';
    await WorkspaceStore.fetchDirs(parent);
    this.renderWorkspacePanel();
  },

  /** 设置工作目录 */
  async setDir(path) {
    const input = document.getElementById('workspace-path-input');
    if (input) input.value = path;
    await WorkspaceStore.fetchDirs(path);
    this.renderWorkspacePanel();
  },

  /** 确认设置工作目录 */
  async handleSetDir() {
    const input = document.getElementById('workspace-path-input');
    const path = input ? input.value.trim() : '';
    if (!path) { App.showNotification('Please enter a directory path', 'warning'); return; }

    try {
      await WorkspaceStore.setWorkingDir(path);
      App.showNotification(`Working directory set to: ${path}`, 'success');
      this.renderWorkspacePanel();
    } catch (err) {
      App.showNotification('Failed to set directory: ' + err.message, 'error');
    }
  },

  /** 创建新文件夹 */
  async handleMkdir() {
    const html = `
      <div class="settings-field">
        <label for="mkdir-name">Folder Name</label>
        <input type="text" id="mkdir-name" placeholder="new-folder">
      </div>`;
    const footer = `
      <button class="btn btn-ghost" onclick="App.hideModal()">Cancel</button>
      <button class="btn btn-primary" onclick="WorkspaceView.doMkdir()">Create</button>`;
    App.showModal('Create Folder', html, footer);
    setTimeout(() => {
      const inp = document.getElementById('mkdir-name');
      if (inp) inp.focus();
    }, 100);
  },

  /** 执行创建文件夹 */
  async doMkdir() {
    const nameInput = document.getElementById('mkdir-name');
    const name = nameInput ? nameInput.value.trim() : '';
    if (!name) { App.showNotification('Folder name is required', 'warning'); return; }

    try {
      await WorkspaceStore.createDir(WorkspaceStore.current_dir, name);
      App.showNotification(`Folder "${name}" created`, 'success');
      App.hideModal();
      await WorkspaceStore.fetchDirs(WorkspaceStore.current_dir);
      this.renderWorkspacePanel();
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
