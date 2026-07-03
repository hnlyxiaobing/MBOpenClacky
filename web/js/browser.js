// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Browser Control Panel
// ═══════════════════════════════════════════════════════════════

const BrowserControl = {
  status: null,
  autoRefreshInterval: null,

  init() {
    console.log('[BrowserControl] initialized');
  },

  async load() {
    const content = document.querySelector('#view-browser .view-content');
    if (content) {
      content.innerHTML = '<div class="text-center"><div class="spinner" style="margin:40px auto"></div></div>';
    }
    await this.loadStatus();
    this.render();
  },

  async loadStatus() {
    try {
      this.status = await API.get('/api/browser/status');
    } catch (err) {
      console.error('[BrowserControl] Status load failed:', err);
      this.status = { running: false, error: err.message };
    }
  },

  render() {
    const content = document.querySelector('#view-browser .view-content');
    if (!content) return;

    content.innerHTML = '';

    // Status card
    content.appendChild(this.renderStatusCard());

    // Controls card
    content.appendChild(this.renderControlsCard());

    // Screenshot section
    content.appendChild(this.renderScreenshotSection());
  },

  renderStatusCard() {
    const card = document.createElement('div');
    card.className = 'stat-card';
    card.style.marginBottom = '20px';
    card.style.textAlign = 'left';
    card.style.padding = '20px';

    const isRunning = this.status && this.status.running;
    const statusText = isRunning ? 'Running' : 'Stopped';
    const statusClass = isRunning ? 'running' : '';
    const url = (this.status && this.status.url) || '';

    card.innerHTML = `
      <div class="settings-group-title">Browser Status</div>
      <div style="display:flex;align-items:center;gap:16px;margin-bottom:12px">
        <span class="status-badge ${statusClass}" id="browser-status-badge"
              style="${!isRunning ? 'background:rgba(247,118,142,0.15);color:var(--danger)' : ''}">
          ${statusText}
        </span>
      </div>
      <div id="browser-url-display" style="font-size:12px;color:var(--text-muted)"></div>`;

    const urlDisplay = card.querySelector('#browser-url-display');
    if (url) {
      urlDisplay.textContent = `URL: ${url}`;
    }

    return card;
  },

  renderControlsCard() {
    const card = document.createElement('div');
    card.className = 'stat-card';
    card.style.marginBottom = '20px';
    card.style.textAlign = 'left';
    card.style.padding = '20px';

    const isRunning = this.status && this.status.running;

    card.innerHTML = `
      <div class="settings-group-title">Controls</div>
      <div style="display:flex;gap:8px;margin-bottom:16px">
        <button class="btn btn-primary" id="btn-browser-start" ${isRunning ? 'disabled' : ''}>Start</button>
        <button class="btn btn-danger" id="btn-browser-stop" ${!isRunning ? 'disabled' : ''}>Stop</button>
      </div>
      <div class="settings-group-title" style="margin-top:16px">Navigate</div>
      <div style="display:flex;gap:8px">
        <input type="text" id="browser-url-input" class="form-control"
               placeholder="https://example.com"
               style="flex:1;padding:9px 12px;background:var(--bg-tertiary);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text-primary);font-size:13px;outline:none">
        <button class="btn btn-primary" id="btn-browser-navigate" ${!isRunning ? 'disabled' : ''}>Go</button>
      </div>`;

    const startBtn = card.querySelector('#btn-browser-start');
    const stopBtn = card.querySelector('#btn-browser-stop');
    const navBtn = card.querySelector('#btn-browser-navigate');
    const urlInput = card.querySelector('#browser-url-input');

    startBtn.addEventListener('click', () => this.handleStart());
    stopBtn.addEventListener('click', () => this.handleStop());
    navBtn.addEventListener('click', () => this.handleNavigate());

    urlInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') this.handleNavigate();
    });

    return card;
  },

  renderScreenshotSection() {
    const card = document.createElement('div');
    card.className = 'stat-card';
    card.style.textAlign = 'left';
    card.style.padding = '20px';

    const isRunning = this.status && this.status.running;
    const autoActive = this.autoRefreshInterval !== null;

    card.innerHTML = `
      <div class="settings-group-title">Screenshot</div>
      <div style="display:flex;gap:8px;align-items:center;margin-bottom:16px">
        <button class="btn btn-primary" id="btn-browser-screenshot" ${!isRunning ? 'disabled' : ''}>Take Screenshot</button>
        <div class="toggle-wrapper" style="flex:1">
          <label style="font-size:13px;color:var(--text-primary)">Auto-refresh (5s)</label>
          <div class="toggle ${autoActive ? 'active' : ''}" id="toggle-auto-refresh"></div>
        </div>
      </div>
      <div id="browser-screenshot-preview"
           style="min-height:200px;background:var(--bg-tertiary);border:1px solid var(--border);border-radius:var(--radius);display:flex;align-items:center;justify-content:center;overflow:hidden">
        <span class="text-muted">No screenshot yet</span>
      </div>
      <div id="browser-screenshot-actions" style="margin-top:8px;display:none">
        <button class="btn btn-ghost btn-sm" id="btn-browser-download">Download</button>
      </div>`;

    const ssBtn = card.querySelector('#btn-browser-screenshot');
    const toggle = card.querySelector('#toggle-auto-refresh');
    const downloadBtn = card.querySelector('#btn-browser-download');

    ssBtn.addEventListener('click', () => this.handleScreenshot());
    toggle.addEventListener('click', () => this.toggleAutoRefresh());
    downloadBtn.addEventListener('click', () => this.downloadScreenshot());

    return card;
  },

  async handleStart() {
    const btn = document.getElementById('btn-browser-start');
    if (btn) { btn.disabled = true; btn.textContent = 'Starting...'; }
    try {
      await API.post('/api/browser/start');
      App.showNotification('Browser started', 'success');
      await this.loadStatus();
      this.render();
    } catch (err) {
      App.showNotification(err.message || 'Failed to start browser', 'error');
      if (btn) { btn.disabled = false; btn.textContent = 'Start'; }
    }
  },

  async handleStop() {
    const btn = document.getElementById('btn-browser-stop');
    if (btn) { btn.disabled = true; btn.textContent = 'Stopping...'; }
    try {
      await API.post('/api/browser/stop');
      App.showNotification('Browser stopped', 'success');
      if (this.autoRefreshInterval) this.toggleAutoRefresh();
      await this.loadStatus();
      this.render();
    } catch (err) {
      App.showNotification(err.message || 'Failed to stop browser', 'error');
      if (btn) { btn.disabled = false; btn.textContent = 'Stop'; }
    }
  },

  async handleNavigate() {
    const input = document.getElementById('browser-url-input');
    if (!input) return;
    let url = input.value.trim();
    if (!url) {
      App.showNotification('Please enter a URL', 'warning');
      return;
    }
    // Auto-add https:// if no protocol
    if (!/^https?:\/\//i.test(url)) url = 'https://' + url;
    // Basic URL validation
    try { new URL(url); } catch {
      App.showNotification('Invalid URL format', 'warning');
      return;
    }
    try {
      await API.post('/api/browser/navigate', { url });
      App.showNotification(`Navigated to ${url}`, 'success');
    } catch (err) {
      App.showNotification(err.message || 'Navigation failed', 'error');
    }
  },

  async handleScreenshot() {
    const preview = document.getElementById('browser-screenshot-preview');
    if (!preview) return;

    try {
      // Fix: [C1] screenshot路由方法不匹配前端 — 后端已添加GET路由匹配此调用
      const data = await API.get('/api/browser/screenshot');
      const imgSrc = data.image || data.data || data;
      preview.innerHTML = `<img src="data:image/png;base64,${imgSrc}" style="max-width:100%;height:auto;display:block" alt="Screenshot">`;

      const actions = document.getElementById('browser-screenshot-actions');
      if (actions) actions.style.display = 'block';
    } catch (err) {
      App.showNotification(err.message || 'Screenshot failed', 'error');
    }
  },

  downloadScreenshot() {
    const img = document.querySelector('#browser-screenshot-preview img');
    if (!img) return;
    const a = document.createElement('a');
    a.href = img.src;
    a.download = `screenshot-${Date.now()}.png`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
  },

  toggleAutoRefresh() {
    const toggle = document.getElementById('toggle-auto-refresh');
    if (this.autoRefreshInterval) {
      clearInterval(this.autoRefreshInterval);
      this.autoRefreshInterval = null;
      if (toggle) toggle.classList.remove('active');
    } else {
      this.autoRefreshInterval = setInterval(() => {
        if (this.status && this.status.running) {
          this.handleScreenshot();
        }
      }, 5000);
      if (toggle) toggle.classList.add('active');
      // Take one immediately
      this.handleScreenshot();
    }
  },
};
