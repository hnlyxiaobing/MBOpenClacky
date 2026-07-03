// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Share Panel
// ═══════════════════════════════════════════════════════════════

// ── ShareStore: 分享状态管理 ─────────────────────────────────
const ShareStore = {
  session_id: null,
  share_url: null,
  exported: false,

  /**
   * 导出会话 — GET /api/sessions/:id/export?format=md|json
   * @param {string} id — 会话 ID
   * @param {string} format — 导出格式: 'md' | 'json'
   */
  async exportSession(id, format = 'md') {
    try {
      const res = await fetch(`/api/sessions/${encodeURIComponent(id)}/export?format=${format}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);

      if (format === 'json') {
        const data = await res.json();
        this.exported = true;
        return data;
      } else {
        const text = await res.text();
        this.exported = true;
        return text;
      }
    } catch (err) {
      console.error('[ShareStore] exportSession failed:', err);
      throw err;
    }
  },
};

// ── ShareView: 分享面板渲染 ──────────────────────────────────
const ShareView = {
  /** 初始化 */
  init() {
    console.log('[ShareView] initialized');
  },

  /** 加载并渲染 */
  async load() {
    const content = document.getElementById('share-content');
    if (!content) return;

    ShareStore.session_id = App.currentSessionId;
    ShareStore.share_url = null;
    ShareStore.exported = false;

    this.renderSharePanel();
  },

  /** 渲染分享面板 */
  renderSharePanel() {
    const container = document.getElementById('share-content');
    if (!container) return;

    const hasSession = !!ShareStore.session_id;

    container.innerHTML = `
      <div class="settings-group">
        <div class="settings-group-title">Export Session</div>
        ${!hasSession ? '<p class="text-muted" style="padding:8px 0">Select a session first to export.</p>' : `
          <div class="settings-field">
            <label>Session</label>
            <div class="text-muted" style="font-size:13px">${this._esc(ShareStore.session_id)}</div>
          </div>
          <div class="settings-field">
            <label for="share-format">Export Format</label>
            <select id="share-format">
              <option value="md">Markdown (.md)</option>
              <option value="json">JSON (.json)</option>
            </select>
            <div class="help-text">Choose the format for exporting the conversation</div>
          </div>
          <div style="display:flex;gap:8px;margin-top:12px">
            <button class="btn btn-primary" onclick="ShareView.handleExport()">Export</button>
            <button class="btn btn-ghost" onclick="ShareView.handleCopyLink()">Copy Share Link</button>
          </div>
        `}
      </div>

      <div id="share-result" class="settings-group" style="display:none">
        <div class="settings-group-title">Export Result</div>
        <div id="share-result-content" style="max-height:400px;overflow:auto"></div>
      </div>`;
  },

  /** 导出会话 */
  async handleExport() {
    const id = ShareStore.session_id;
    if (!id) { App.showNotification('No session selected', 'warning'); return; }

    const format = document.getElementById('share-format')?.value || 'md';

    try {
      const result = await ShareStore.exportSession(id, format);
      const resultGroup = document.getElementById('share-result');
      const resultContent = document.getElementById('share-result-content');

      if (resultGroup) resultGroup.style.display = '';

      if (format === 'json') {
        if (resultContent) {
          resultContent.innerHTML = `<pre style="background:var(--bg-tertiary);padding:12px;border-radius:var(--radius-sm);font-size:12px;font-family:var(--font-mono);overflow-x:auto;white-space:pre-wrap">${this._esc(JSON.stringify(result, null, 2))}</pre>
            <div style="margin-top:8px"><button class="btn btn-ghost btn-sm" onclick="ShareView.downloadExport('json')">Download JSON</button></div>`;
        }
      } else {
        if (resultContent) {
          resultContent.innerHTML = `<pre style="background:var(--bg-tertiary);padding:12px;border-radius:var(--radius-sm);font-size:12px;font-family:var(--font-mono);overflow-x:auto;white-space:pre-wrap">${this._esc(String(result))}</pre>
            <div style="margin-top:8px"><button class="btn btn-ghost btn-sm" onclick="ShareView.downloadExport('md')">Download Markdown</button></div>`;
        }
      }

      App.showNotification('Session exported', 'success');
    } catch (err) {
      App.showNotification('Export failed: ' + err.message, 'error');
    }
  },

  /** 下载导出文件 */
  downloadExport(format) {
    const content = document.getElementById('share-result-content')?.querySelector('pre')?.textContent || '';
    const mime = format === 'json' ? 'application/json' : 'text/markdown';
    const ext = format === 'json' ? 'json' : 'md';
    const blob = new Blob([content], { type: mime });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `session-${ShareStore.session_id}.${ext}`;
    a.click();
    URL.revokeObjectURL(url);
  },

  /** 复制分享链接 */
  handleCopyLink() {
    const id = ShareStore.session_id;
    if (!id) return;
    const url = `${window.location.origin}/share/${id}`;
    navigator.clipboard.writeText(url).then(() => {
      App.showNotification('Share link copied to clipboard', 'success');
      ShareStore.share_url = url;
    }).catch(() => {
      App.showNotification('Failed to copy link', 'error');
    });
  },

  /** HTML 转义 */
  _esc(text) {
    const div = document.createElement('div');
    div.textContent = text || '';
    return div.innerHTML;
  },
};
