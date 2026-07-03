// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Model Test Panel
// ═══════════════════════════════════════════════════════════════

// ── ModelTestStore: 模型测试状态管理 ─────────────────────────
const ModelTestStore = {
  models: [],
  test_results: {},
  testing: false,

  /** 测试模型 — POST /api/config/test */
  async testModel(model_id) {
    this.testing = true;
    this.test_results[model_id] = { status: 'testing', message: 'Testing...' };
    try {
      const data = await API.post('/api/config/test', { model_id });
      this.test_results[model_id] = {
        status: data.ok ? 'success' : 'error',
        message: data.ok ? 'Connection successful' : (data.error || 'Test failed'),
        latency_ms: data.latency_ms || null,
      };
      return data;
    } catch (err) {
      this.test_results[model_id] = {
        status: 'error',
        message: err.message || 'Test failed',
      };
      throw err;
    } finally {
      this.testing = false;
    }
  },

  /** 测试媒体模型 — POST /api/config/media/test */
  async testMediaModel(kind) {
    this.testing = true;
    try {
      const data = await API.post('/api/config/media/test', { kind });
      return data;
    } catch (err) {
      console.error('[ModelTestStore] testMediaModel failed:', err);
      throw err;
    } finally {
      this.testing = false;
    }
  },
};

// ── ModelTestView: 模型测试面板渲染 ──────────────────────────
const ModelTestView = {
  /** 初始化 */
  init() {
    console.log('[ModelTestView] initialized');
  },

  /** 加载并渲染 */
  async load() {
    const content = document.getElementById('model-test-content');
    if (!content) return;
    content.innerHTML = '<div class="text-center"><div class="spinner" style="margin:40px auto"></div></div>';

    try {
      const res = await fetch('/api/config/models');
      if (res.ok) {
        const data = await res.json();
        ModelTestStore.models = data.models || [];
      }
      this.renderModelTestPanel();
    } catch (err) {
      content.innerHTML = '<p class="text-muted text-center">Failed to load models</p>';
    }
  },

  /** 渲染模型测试面板 */
  renderModelTestPanel() {
    const container = document.getElementById('model-test-content');
    if (!container) return;

    const models = ModelTestStore.models;
    const results = ModelTestStore.test_results;

    const modelsHtml = models.length === 0
      ? '<p class="text-muted" style="padding:8px 0">No models configured. Add models in Settings.</p>'
      : models.map(m => {
          const id = m.id || m.name || '';
          const label = m.name || m.model || id;
          const result = results[id];
          const statusIcon = !result ? '' :
            result.status === 'testing' ? '<span class="spinner" style="width:14px;height:14px;border-width:2px;display:inline-block;vertical-align:middle"></span>' :
            result.status === 'success' ? '<span style="color:var(--success)">&#10003;</span>' :
            '<span style="color:var(--danger)">&#10007;</span>';
          const statusText = !result ? '' :
            result.status === 'testing' ? ' Testing...' :
            `${result.message}${result.latency_ms ? ` (${result.latency_ms}ms)` : ''}`;

          return `
            <div class="skill-card" style="margin-bottom:8px">
              <div style="display:flex;align-items:center;justify-content:space-between">
                <div>
                  <div class="skill-card-name">${this._esc(label)}</div>
                  <div class="skill-card-desc">${this._esc(id)}</div>
                  ${statusText ? `<div style="font-size:11px;margin-top:4px;display:flex;align-items:center;gap:4px">${statusIcon} ${this._esc(statusText)}</div>` : ''}
                </div>
                <button class="btn btn-primary btn-sm" onclick="ModelTestView.handleTest('${this._esc(id)}')" ${ModelTestStore.testing ? 'disabled' : ''}>Test</button>
              </div>
            </div>`;
        }).join('');

    container.innerHTML = `
      <div class="settings-group">
        <div class="settings-group-title" style="display:flex;align-items:center;justify-content:space-between">
          <span>Models (${models.length})</span>
          <button class="btn btn-ghost btn-sm" onclick="ModelTestView.handleTestAll()">Test All</button>
        </div>
        <div id="model-test-list">${modelsHtml}</div>
      </div>

      <div class="settings-group">
        <div class="settings-group-title">Media Models</div>
        <div style="display:flex;gap:8px;flex-wrap:wrap">
          <button class="btn btn-ghost btn-sm" onclick="ModelTestView.handleTestMedia('image')">Test Image Generation</button>
          <button class="btn btn-ghost btn-sm" onclick="ModelTestView.handleTestMedia('audio')">Test Audio</button>
          <button class="btn btn-ghost btn-sm" onclick="ModelTestView.handleTestMedia('video')">Test Video</button>
        </div>
        <div id="media-test-result" style="margin-top:8px;font-size:12px" class="text-muted"></div>
      </div>`;
  },

  /** 测试单个模型 */
  async handleTest(model_id) {
    try {
      await ModelTestStore.testModel(model_id);
      this.renderModelTestPanel();
    } catch (err) {
      this.renderModelTestPanel();
      App.showNotification('Test failed: ' + err.message, 'error');
    }
  },

  /** 测试所有模型 */
  async handleTestAll() {
    const models = ModelTestStore.models;
    if (models.length === 0) return;

    for (const m of models) {
      const id = m.id || m.name || '';
      try {
        await ModelTestStore.testModel(id);
        this.renderModelTestPanel();
      } catch (err) {
        this.renderModelTestPanel();
      }
    }
    App.showNotification('All model tests complete', 'info');
  },

  /** 测试媒体模型 */
  async handleTestMedia(kind) {
    const resultEl = document.getElementById('media-test-result');
    if (resultEl) resultEl.textContent = `Testing ${kind} model...`;
    try {
      const data = await ModelTestStore.testMediaModel(kind);
      if (resultEl) resultEl.textContent = data.ok ? `${kind} model OK` : (`Failed: ${data.error || 'unknown'}`);
      App.showNotification(`${kind} model test ${data.ok ? 'passed' : 'failed'}`, data.ok ? 'success' : 'error');
    } catch (err) {
      if (resultEl) resultEl.textContent = `Error: ${err.message}`;
      App.showNotification('Media test failed: ' + err.message, 'error');
    }
  },

  /** HTML 转义 */
  _esc(text) {
    const div = document.createElement('div');
    div.textContent = text || '';
    return div.innerHTML;
  },
};
