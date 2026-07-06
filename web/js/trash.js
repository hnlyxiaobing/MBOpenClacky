// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Trash Panel (Enhanced)
// ═══════════════════════════════════════════════════════════════

const Trash = {
  items: [],
  filteredItems: [],
  selectedIds: new Set(),
  currentFilter: 'all',
  searchQuery: '',
  stats: { total: 0, by_type: {} },
  isLoading: false,

  /**
   * Initialize trash panel
   */
  init() {
    this.bindEvents();
    console.log('[Trash] initialized');
  },

  /**
   * Bind static DOM events (called once)
   */
  bindEvents() {
    // Filter buttons
    document.addEventListener('click', (e) => {
      const btn = e.target.closest('.trash-filter-btn');
      if (btn) {
        this.setFilter(btn.dataset.filter);
      }
      // Batch action buttons
      if (e.target.closest('#trash-batch-restore')) {
        this.handleBatchRestore();
      }
      if (e.target.closest('#trash-batch-delete')) {
        this.handleBatchDelete();
      }
      if (e.target.closest('#trash-select-all')) {
        this.toggleSelectAll();
      }
    });

    // Search input
    document.addEventListener('input', (e) => {
      if (e.target.id === 'trash-search-input') {
        this.searchQuery = e.target.value.toLowerCase();
        this.applyFilters();
        this.renderList();
      }
    });
  },

  /**
   * Load trash data and render
   */
  async load() {
    this.isLoading = true;
    this.render();
    await Promise.all([this.loadTrash(), this.loadStats()]);
    this.isLoading = false;
    this.applyFilters();
    this.render();
  },

  /**
   * Fetch trash list from backend
   */
  async loadTrash() {
    try {
      const params = this.currentFilter !== 'all'
        ? `?type=${encodeURIComponent(this.currentFilter)}`
        : '';
      const data = await API.get('/api/trash' + params);
      this.items = Array.isArray(data) ? data : (data.items || []);
    } catch (err) {
      console.error('[Trash] Load failed:', err);
      App.showNotification('Failed to load trash: ' + err.message, 'error');
      this.items = [];
    }
  },

  /**
   * Fetch trash stats from backend
   */
  async loadStats() {
    try {
      const data = await API.get('/api/trash/stats');
      this.stats = data || { total: 0, by_type: {} };
    } catch {
      this.stats = { total: 0, by_type: {} };
    }
  },

  /**
   * Set active filter type
   */
  setFilter(type) {
    this.currentFilter = type;
    this.selectedIds.clear();
    this.load();
  },

  /**
   * Apply search filter to items
   */
  applyFilters() {
    if (!this.searchQuery) {
      this.filteredItems = [...this.items];
    } else {
      this.filteredItems = this.items.filter(item => {
        const name = (item.name || '').toLowerCase();
        const id = (item.id || '').toLowerCase();
        const type = (item.item_type || '').toLowerCase();
        return name.includes(this.searchQuery) ||
               id.includes(this.searchQuery) ||
               type.includes(this.searchQuery);
      });
    }
  },

  /**
   * Toggle select all checkbox
   */
  toggleSelectAll() {
    const checkbox = document.getElementById('trash-select-all');
    if (!checkbox) return;

    if (checkbox.checked) {
      this.filteredItems.forEach(item => this.selectedIds.add(item.id));
    } else {
      this.selectedIds.clear();
    }
    this.renderList();
  },

  /**
   * Toggle single item selection
   */
  toggleItemSelection(id) {
    if (this.selectedIds.has(id)) {
      this.selectedIds.delete(id);
    } else {
      this.selectedIds.add(id);
    }
    this.updateBatchButtons();
  },

  /**
   * Update batch action button states
   */
  updateBatchButtons() {
    const restoreBtn = document.getElementById('trash-batch-restore');
    const deleteBtn = document.getElementById('trash-batch-delete');
    const count = this.selectedIds.size;

    if (restoreBtn) {
      restoreBtn.disabled = count === 0;
      restoreBtn.textContent = count > 0 ? `↩ Restore (${count})` : '↩ Restore Selected';
    }
    if (deleteBtn) {
      deleteBtn.disabled = count === 0;
      deleteBtn.textContent = count > 0 ? `✕ Delete (${count})` : '✕ Delete Selected';
    }

    const selectAll = document.getElementById('trash-select-all');
    if (selectAll) {
      selectAll.checked = this.filteredItems.length > 0 &&
                          this.filteredItems.every(item => this.selectedIds.has(item.id));
    }
  },

  /**
   * Render the full trash panel
   */
  render() {
    const content = document.getElementById('trash-content');
    if (!content) return;

    if (this.isLoading) {
      content.innerHTML = `
        <div class="empty-state">
          <div class="spinner"></div>
          <p class="text-muted">Loading trash...</p>
        </div>`;
      return;
    }

    // Build header
    const header = document.querySelector('#view-trash .view-header');
    if (header) {
      header.innerHTML = '';

      const titleWrap = document.createElement('div');
      titleWrap.style.cssText = 'display:flex;align-items:center;gap:10px;';

      const h2 = document.createElement('h2');
      h2.textContent = 'Trash';
      titleWrap.appendChild(h2);

      const badge = document.createElement('span');
      badge.className = 'badge';
      badge.style.cssText = 'background:var(--bg-tertiary);color:var(--text-secondary);padding:2px 8px;border-radius:10px;font-size:12px;';
      badge.textContent = `${this.stats.total || this.items.length} item${(this.stats.total || this.items.length) !== 1 ? 's' : ''}`;
      titleWrap.appendChild(badge);

      header.appendChild(titleWrap);

      const emptyBtn = document.createElement('button');
      emptyBtn.className = 'btn btn-danger btn-sm';
      emptyBtn.textContent = '🗑 Empty Trash';
      emptyBtn.disabled = this.items.length === 0;
      emptyBtn.addEventListener('click', () => this.handleEmptyAll());
      header.appendChild(emptyBtn);
    }

    // Build toolbar
    content.innerHTML = '';
    const toolbar = this.buildToolbar();
    content.appendChild(toolbar);

    // Build list
    this.renderList();
  },

  /**
   * Build the filter/search toolbar
   */
  buildToolbar() {
    const toolbar = document.createElement('div');
    toolbar.className = 'trash-toolbar';
    toolbar.style.cssText = 'display:flex;align-items:center;gap:8px;padding:12px 0;border-bottom:1px solid var(--border-light);margin-bottom:8px;flex-wrap:wrap;';

    // Filter buttons
    const filterGroup = document.createElement('div');
    filterGroup.style.cssText = 'display:flex;gap:4px;';

    const filters = [
      { key: 'all', label: 'All' },
      { key: 'session', label: 'Sessions' },
      { key: 'config', label: 'Configs' },
      { key: 'schedule', label: 'Schedules' },
    ];

    filters.forEach(f => {
      const btn = document.createElement('button');
      btn.className = `btn btn-sm trash-filter-btn ${this.currentFilter === f.key ? 'btn-primary' : 'btn-ghost'}`;
      btn.dataset.filter = f.key;
      btn.textContent = f.label;
      const count = f.key === 'all'
        ? this.stats.total || 0
        : (this.stats.by_type && this.stats.by_type[f.key]) || 0;
      if (count > 0) {
        const countSpan = document.createElement('span');
        countSpan.style.cssText = 'margin-left:4px;opacity:0.7;font-size:11px;';
        countSpan.textContent = `(${count})`;
        btn.appendChild(countSpan);
      }
      filterGroup.appendChild(btn);
    });
    toolbar.appendChild(filterGroup);

    // Search input
    const searchInput = document.createElement('input');
    searchInput.type = 'text';
    searchInput.id = 'trash-search-input';
    searchInput.placeholder = 'Search trash...';
    searchInput.value = this.searchQuery;
    searchInput.style.cssText = 'flex:1;min-width:120px;padding:6px 10px;border:1px solid var(--border);border-radius:6px;background:var(--bg-secondary);color:var(--text-primary);font-size:13px;';
    toolbar.appendChild(searchInput);

    // Batch actions
    const batchGroup = document.createElement('div');
    batchGroup.style.cssText = 'display:flex;gap:4px;';

    const selectAllCb = document.createElement('input');
    selectAllCb.type = 'checkbox';
    selectAllCb.id = 'trash-select-all';
    selectAllCb.title = 'Select all';
    selectAllCb.style.cssText = 'cursor:pointer;width:16px;height:16px;';
    selectAllCb.checked = this.filteredItems.length > 0 &&
                            this.filteredItems.every(item => this.selectedIds.has(item.id));
    batchGroup.appendChild(selectAllCb);

    const restoreBtn = document.createElement('button');
    restoreBtn.id = 'trash-batch-restore';
    restoreBtn.className = 'btn btn-primary btn-sm';
    restoreBtn.textContent = '↩ Restore Selected';
    restoreBtn.disabled = this.selectedIds.size === 0;
    batchGroup.appendChild(restoreBtn);

    const deleteBtn = document.createElement('button');
    deleteBtn.id = 'trash-batch-delete';
    deleteBtn.className = 'btn btn-danger btn-sm';
    deleteBtn.textContent = '✕ Delete Selected';
    deleteBtn.disabled = this.selectedIds.size === 0;
    batchGroup.appendChild(deleteBtn);

    toolbar.appendChild(batchGroup);
    return toolbar;
  },

  /**
   * Render the trash items list into #trash-content (appends after toolbar)
   */
  renderList() {
    const content = document.getElementById('trash-content');
    if (!content) return;

    // Remove old list (keep toolbar)
    const oldList = content.querySelector('.trash-list');
    if (oldList) oldList.remove();

    const listContainer = document.createElement('div');
    listContainer.className = 'trash-list';

    if (this.filteredItems.length === 0) {
      const emptyMsg = this.searchQuery
        ? 'No items match your search.'
        : 'Trash is empty. Deleted items will appear here.';
      listContainer.innerHTML = `
        <div class="empty-state" style="padding:40px 0;">
          <div class="empty-state-icon" style="font-size:48px;opacity:0.3;">🗑</div>
          <h3 style="margin:12px 0 4px;color:var(--text-secondary);">
            ${this.searchQuery ? 'No Results' : 'Trash is Empty'}
          </h3>
          <p class="text-muted" style="font-size:13px;">${emptyMsg}</p>
        </div>`;
      content.appendChild(listContainer);
      return;
    }

    const table = document.createElement('table');
    table.style.cssText = 'width:100%;border-collapse:collapse;';

    // thead
    const thead = document.createElement('thead');
    const headRow = document.createElement('tr');
    headRow.style.cssText = 'border-bottom:1px solid var(--border);';

    const cols = [
      { text: '', style: 'width:30px;padding:8px 4px;' },
      { text: 'Name / ID', style: 'text-align:left;padding:8px 12px;font-size:12px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.5px;' },
      { text: 'Type', style: 'text-align:left;padding:8px 12px;font-size:12px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.5px;' },
      { text: 'Deleted', style: 'text-align:left;padding:8px 12px;font-size:12px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.5px;' },
      { text: 'Expires', style: 'text-align:left;padding:8px 12px;font-size:12px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.5px;' },
      { text: 'Actions', style: 'text-align:right;padding:8px 12px;font-size:12px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.5px;' },
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
    this.filteredItems.forEach(item => {
      const tr = document.createElement('tr');
      tr.style.cssText = 'border-bottom:1px solid var(--border-light);';
      if (this.selectedIds.has(item.id)) {
        tr.style.background = 'var(--bg-tertiary)';
      }

      // Checkbox cell
      const tdCb = document.createElement('td');
      tdCb.style.cssText = 'padding:8px 4px;';
      const cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = this.selectedIds.has(item.id);
      cb.style.cssText = 'cursor:pointer;width:14px;height:14px;';
      cb.addEventListener('change', () => this.toggleItemSelection(item.id));
      tdCb.appendChild(cb);
      tr.appendChild(tdCb);

      // Name cell
      const tdName = document.createElement('td');
      tdName.style.cssText = 'padding:8px 12px;font-size:13px;color:var(--text-primary);word-break:break-all;';
      tdName.textContent = item.name || item.id || '—';
      if (item.name && item.id) {
        const idSpan = document.createElement('div');
        idSpan.style.cssText = 'font-size:11px;color:var(--text-muted);font-family:var(--font-mono);margin-top:2px;';
        idSpan.textContent = item.id;
        tdName.appendChild(idSpan);
      }
      tr.appendChild(tdName);

      // Type cell
      const tdType = document.createElement('td');
      tdType.style.cssText = 'padding:8px 12px;font-size:12px;';
      const typeBadge = document.createElement('span');
      typeBadge.className = 'badge';
      typeBadge.style.cssText = 'background:var(--bg-tertiary);color:var(--text-secondary);padding:2px 8px;border-radius:4px;font-size:11px;text-transform:capitalize;';
      typeBadge.textContent = item.item_type || 'unknown';
      tdType.appendChild(typeBadge);
      tr.appendChild(tdType);

      // Deleted at cell
      const tdDate = document.createElement('td');
      tdDate.style.cssText = 'padding:8px 12px;font-size:12px;color:var(--text-muted);white-space:nowrap;';
      tdDate.textContent = this.formatTime(item.deleted_at);
      tr.appendChild(tdDate);

      // Expires cell
      const tdExpiry = document.createElement('td');
      tdExpiry.style.cssText = 'padding:8px 12px;font-size:12px;white-space:nowrap;';
      const expiryText = this.formatExpiry(item.expires_at);
      tdExpiry.textContent = expiryText.text;
      tdExpiry.style.color = expiryText.expired ? 'var(--color-danger, #f85149)' : 'var(--text-muted)';
      tr.appendChild(tdExpiry);

      // Actions cell
      const tdActions = document.createElement('td');
      tdActions.style.cssText = 'padding:8px 12px;text-align:right;white-space:nowrap;';

      const restoreBtn = document.createElement('button');
      restoreBtn.className = 'btn btn-primary btn-sm';
      restoreBtn.textContent = '↩';
      restoreBtn.title = 'Restore';
      restoreBtn.style.marginRight = '4px';
      restoreBtn.addEventListener('click', () => this.handleRestore(item.id));
      tdActions.appendChild(restoreBtn);

      const deleteBtn = document.createElement('button');
      deleteBtn.className = 'btn btn-danger btn-sm';
      deleteBtn.textContent = '✕';
      deleteBtn.title = 'Permanently delete';
      deleteBtn.addEventListener('click', () => this.handleDelete(item.id));
      tdActions.appendChild(deleteBtn);

      tr.appendChild(tdActions);
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);
    listContainer.appendChild(table);
    content.appendChild(listContainer);

    this.updateBatchButtons();
  },

  /**
   * Format expiry time with relative text
   */
  formatExpiry(expiresAt) {
    if (!expiresAt) return { text: '—', expired: false };
    try {
      // expires_at could be epoch seconds string or ISO date
      let expiryDate;
      if (/^\d+$/.test(expiresAt)) {
        expiryDate = new Date(parseInt(expiresAt) * 1000);
      } else {
        expiryDate = new Date(expiresAt);
      }
      const now = new Date();
      const diffMs = expiryDate - now;
      const diffDays = Math.ceil(diffMs / 86400000);

      if (diffDays < 0) {
        return { text: 'Expired', expired: true };
      } else if (diffDays === 0) {
        return { text: 'Expires today', expired: false };
      } else if (diffDays === 1) {
        return { text: '1 day left', expired: false };
      } else {
        return { text: `${diffDays} days left`, expired: false };
      }
    } catch {
      return { text: '—', expired: false };
    }
  },

  /**
   * Restore a trashed item
   */
  async handleRestore(id) {
    try {
      await API.post(`/api/trash/${id}/restore`);
      App.showNotification('Item restored successfully', 'success');
      this.selectedIds.delete(id);
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
      this.selectedIds.delete(id);
      await this.load();
    } catch (err) {
      App.showNotification('Failed to delete: ' + err.message, 'error');
    }
  },

  /**
   * Batch restore selected items
   */
  async handleBatchRestore() {
    if (this.selectedIds.size === 0) return;
    const count = this.selectedIds.size;
    if (!confirm(`Restore ${count} selected item${count !== 1 ? 's' : ''}?`)) return;
    try {
      await API.post('/api/trash/restore-batch', { ids: Array.from(this.selectedIds) });
      App.showNotification(`${count} item${count !== 1 ? 's' : ''} restored`, 'success');
      this.selectedIds.clear();
      await this.load();
    } catch (err) {
      App.showNotification('Batch restore failed: ' + err.message, 'error');
    }
  },

  /**
   * Batch delete selected items
   */
  async handleBatchDelete() {
    if (this.selectedIds.size === 0) return;
    const count = this.selectedIds.size;
    if (!confirm(`Permanently delete ${count} selected item${count !== 1 ? 's' : ''}? This cannot be undone.`)) return;
    try {
      // Delete items one by one (no batch delete endpoint yet)
      const promises = Array.from(this.selectedIds).map(id =>
        API.del(`/api/trash/${id}`).catch(() => null)
      );
      await Promise.all(promises);
      App.showNotification(`${count} item${count !== 1 ? 's' : ''} permanently deleted`, 'success');
      this.selectedIds.clear();
      await this.load();
    } catch (err) {
      App.showNotification('Batch delete failed: ' + err.message, 'error');
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
      this.selectedIds.clear();
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
   * Format epoch-seconds or ISO timestamp to relative or short date
   */
  formatTime(value) {
    if (!value) return '—';
    try {
      let date;
      if (/^\d+$/.test(value)) {
        date = new Date(parseInt(value) * 1000);
      } else {
        date = new Date(value);
      }
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
