// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Trash Panel
// ═══════════════════════════════════════════════════════════════

const Trash = {
  items: [],

  /**
   * Initialize trash panel — no static DOM bindings needed
   */
  init() {
    console.log('[Trash] initialized');
  },

  /**
   * Load trash data and render
   */
  async load() {
    await this.loadTrash();
    this.render();
  },

  /**
   * Fetch trash list from backend
   */
  async loadTrash() {
    try {
      const data = await API.get('/api/trash');
      this.items = Array.isArray(data) ? data : (data.items || []);
    } catch (err) {
      console.error('[Trash] Load failed:', err);
      App.showNotification('Failed to load trash: ' + err.message, 'error');
      this.items = [];
    }
  },

  /**
   * Render the trash panel into #trash-content
   */
  render() {
    const content = document.getElementById('trash-content');
    if (!content) return;

    const count = this.items.length;

    // Build header
    const header = document.querySelector('#view-trash .view-header');
    if (header) {
      header.innerHTML = '';

      const titleWrap = document.createElement('div');
      titleWrap.style.display = 'flex';
      titleWrap.style.alignItems = 'center';
      titleWrap.style.gap = '10px';

      const h2 = document.createElement('h2');
      h2.textContent = 'Trash';
      titleWrap.appendChild(h2);

      const badge = document.createElement('span');
      badge.className = 'badge';
      badge.style.cssText = 'background:var(--bg-tertiary);color:var(--text-secondary);padding:2px 8px;border-radius:10px;font-size:12px;';
      badge.textContent = `${count} item${count !== 1 ? 's' : ''}`;
      titleWrap.appendChild(badge);

      header.appendChild(titleWrap);

      const emptyBtn = document.createElement('button');
      emptyBtn.className = 'btn btn-danger btn-sm';
      emptyBtn.textContent = '🗑 Empty Trash';
      emptyBtn.disabled = count === 0;
      emptyBtn.addEventListener('click', () => this.handleEmptyAll());
      header.appendChild(emptyBtn);
    }

    // Build body
    content.innerHTML = '';

    if (count === 0) {
      content.innerHTML = `
        <div class="empty-state">
          <div class="empty-state-icon">🗑</div>
          <h3>Trash is Empty</h3>
          <p class="text-muted">Deleted files will appear here.</p>
        </div>`;
      return;
    }

    const table = document.createElement('table');
    table.style.cssText = 'width:100%;border-collapse:collapse;';

    // thead
    const thead = document.createElement('thead');
    const headRow = document.createElement('tr');
    headRow.style.cssText = 'border-bottom:1px solid var(--border);';

    const cols = [
      { text: 'Original Path', style: 'text-align:left;padding:10px 12px;font-size:12px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.5px;' },
      { text: 'Deleted At', style: 'text-align:left;padding:10px 12px;font-size:12px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.5px;' },
      { text: 'Size', style: 'text-align:right;padding:10px 12px;font-size:12px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.5px;' },
      { text: 'Actions', style: 'text-align:right;padding:10px 12px;font-size:12px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.5px;' },
    ];
    cols.forEach(c => {
      const th = document.createElement('th');
      th.style.cssText = c.style;
      th.textContent = c.text;
      headRow.appendChild(th);
    });
    thead.appendChild(headRow);
    table.appendChild(thead);

    // tbody
    const tbody = document.createElement('tbody');
    this.items.forEach(item => {
      const tr = document.createElement('tr');
      tr.style.cssText = 'border-bottom:1px solid var(--border-light);';

      // Path cell
      const tdPath = document.createElement('td');
      tdPath.style.cssText = 'padding:10px 12px;font-size:13px;font-family:var(--font-mono);color:var(--text-primary);word-break:break-all;';
      tdPath.textContent = item.path || '—';
      tr.appendChild(tdPath);

      // Deleted at cell
      const tdDate = document.createElement('td');
      tdDate.style.cssText = 'padding:10px 12px;font-size:12px;color:var(--text-muted);white-space:nowrap;';
      tdDate.textContent = this.formatTime(item.deleted_at);
      tr.appendChild(tdDate);

      // Size cell
      const tdSize = document.createElement('td');
      tdSize.style.cssText = 'padding:10px 12px;font-size:12px;color:var(--text-secondary);text-align:right;white-space:nowrap;';
      tdSize.textContent = this.formatSize(item.size);
      tr.appendChild(tdSize);

      // Actions cell
      const tdActions = document.createElement('td');
      tdActions.style.cssText = 'padding:10px 12px;text-align:right;white-space:nowrap;';

      const restoreBtn = document.createElement('button');
      restoreBtn.className = 'btn btn-primary btn-sm';
      restoreBtn.textContent = '↩ Restore';
      restoreBtn.style.marginRight = '6px';
      restoreBtn.addEventListener('click', () => this.handleRestore(item.id));
      tdActions.appendChild(restoreBtn);

      const deleteBtn = document.createElement('button');
      deleteBtn.className = 'btn btn-danger btn-sm';
      deleteBtn.textContent = '✕ Delete';
      deleteBtn.addEventListener('click', () => this.handleDelete(item.id));
      tdActions.appendChild(deleteBtn);

      tr.appendChild(tdActions);
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);
    content.appendChild(table);
  },

  /**
   * Restore a trashed item
   */
  async handleRestore(id) {
    try {
      await API.post(`/api/trash/${id}/restore`);
      App.showNotification('Item restored successfully', 'success');
      await this.load();
    } catch (err) {
      App.showNotification('Failed to restore: ' + err.message, 'error');
    }
  },

  /**
   * Permanently delete a trashed item
   */
  async handleDelete(id) {
    if (!confirm('Permanently delete this item? This cannot be undone.')) return;
    try {
      await API.del(`/api/trash/${id}`);
      App.showNotification('Item permanently deleted', 'success');
      await this.load();
    } catch (err) {
      App.showNotification('Failed to delete: ' + err.message, 'error');
    }
  },

  /**
   * Empty the entire trash bin
   */
  async handleEmptyAll() {
    if (!confirm('Empty entire trash? All items will be permanently deleted. This cannot be undone.')) return;
    try {
      await API.del('/api/trash');
      App.showNotification('Trash emptied', 'success');
      await this.load();
    } catch (err) {
      App.showNotification('Failed to empty trash: ' + err.message, 'error');
    }
  },

  /**
   * Format byte size to human-readable string
   */
  formatSize(bytes) {
    if (bytes == null || isNaN(bytes)) return '—';
    if (bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
    return `${(bytes / Math.pow(1024, i)).toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
  },

  /**
   * Format ISO timestamp to relative or short date
   */
  formatTime(iso) {
    if (!iso) return '—';
    try {
      const date = new Date(iso);
      const now = new Date();
      const diffMs = now - date;
      const diffMin = Math.floor(diffMs / 60000);
      const diffHr = Math.floor(diffMs / 3600000);
      const diffDay = Math.floor(diffMs / 86400000);

      if (diffMin < 1) return 'just now';
      if (diffMin < 60) return `${diffMin}m ago`;
      if (diffHr < 24) return `${diffHr}h ago`;
      if (diffDay < 7) return `${diffDay}d ago`;
      return date.toLocaleDateString();
    } catch {
      return '—';
    }
  },
};
