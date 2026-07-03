// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Backups Panel
// ═══════════════════════════════════════════════════════════════

const Backups = {
  backups: [],

  /**
   * Initialize backups module
   */
  init() {
    console.log('[Backups] initialized');
  },

  /**
   * Load and render backups
   */
  async load() {
    await this.loadBackups();
    this.render();
  },

  /**
   * Fetch backups from API
   */
  async loadBackups() {
    try {
      this.backups = await API.get('/api/backups');
    } catch (err) {
      console.error('[Backups] Load failed:', err);
      App.showNotification(err.message || 'Failed to load backups', 'error');
      this.backups = [];
    }
  },

  /**
   * Render the backups panel
   */
  render() {
    const container = document.querySelector('#view-backups .view-content');
    if (!container) return;

    container.innerHTML = '';

    // Header with create button
    const header = document.createElement('div');
    header.style.cssText = 'display:flex;justify-content:space-between;align-items:center;margin-bottom:16px';
    header.innerHTML = '<h3 style="font-size:14px;color:var(--text-secondary)">Backup Archives</h3>';

    const createBtn = document.createElement('button');
    createBtn.className = 'btn btn-primary btn-sm';
    createBtn.id = 'btn-create-backup';
    createBtn.textContent = '+ Create Backup';
    createBtn.addEventListener('click', () => this.handleCreate());
    header.appendChild(createBtn);
    container.appendChild(header);

    if (this.backups.length === 0) {
      container.innerHTML += '<div class="empty-state"><div class="empty-state-icon">&#128451;</div><h3>No Backups</h3><p class="text-muted">Create a backup to protect your data.</p></div>';
      return;
    }

    // Backup list as table
    const table = document.createElement('table');
    table.style.cssText = 'width:100%;border-collapse:collapse;font-size:13px';

    // Table header
    const thead = document.createElement('thead');
    const headRow = document.createElement('tr');
    headRow.style.cssText = 'border-bottom:1px solid var(--border)';
    ['Created', 'Label', 'Size', 'Status', 'Actions'].forEach(col => {
      const th = document.createElement('th');
      th.style.cssText = 'padding:8px 12px;text-align:left;font-size:12px;font-weight:600;color:var(--text-muted);text-transform:uppercase;letter-spacing:0.5px';
      th.textContent = col;
      headRow.appendChild(th);
    });
    thead.appendChild(headRow);
    table.appendChild(thead);

    // Table body
    const tbody = document.createElement('tbody');
    this.backups.forEach(backup => {
      const row = this.renderRow(backup);
      tbody.appendChild(row);
    });
    table.appendChild(tbody);
    container.appendChild(table);
  },

  /**
   * Render a single backup row
   */
  renderRow(backup) {
    const id = backup.id || backup.backup_id;
    const tr = document.createElement('tr');
    tr.style.cssText = 'border-bottom:1px solid var(--border-light)';

    // Created
    const tdCreated = document.createElement('td');
    tdCreated.style.cssText = 'padding:10px 12px;color:var(--text-secondary)';
    tdCreated.textContent = this.formatTime(backup.created_at || backup.timestamp);
    tr.appendChild(tdCreated);

    // Label
    const tdLabel = document.createElement('td');
    tdLabel.style.cssText = 'padding:10px 12px;color:var(--text-primary);font-weight:500';
    tdLabel.textContent = backup.label || backup.name || '—';
    tr.appendChild(tdLabel);

    // Size
    const tdSize = document.createElement('td');
    tdSize.style.cssText = 'padding:10px 12px;color:var(--text-muted)';
    tdSize.textContent = this.formatSize(backup.size || backup.size_bytes);
    tr.appendChild(tdSize);

    // Status
    const tdStatus = document.createElement('td');
    tdStatus.style.cssText = 'padding:10px 12px';
    const statusBadge = document.createElement('span');
    const status = (backup.status || 'completed').toLowerCase();
    statusBadge.textContent = status;
    if (status === 'completed' || status === 'ok') {
      statusBadge.style.cssText = 'font-size:11px;padding:2px 8px;border-radius:10px;background:rgba(158,206,106,0.15);color:var(--success)';
    } else if (status === 'failed' || status === 'error') {
      statusBadge.style.cssText = 'font-size:11px;padding:2px 8px;border-radius:10px;background:rgba(247,118,142,0.15);color:var(--danger)';
    } else {
      statusBadge.style.cssText = 'font-size:11px;padding:2px 8px;border-radius:10px;background:var(--bg-tertiary);color:var(--text-secondary)';
    }
    tdStatus.appendChild(statusBadge);
    tr.appendChild(tdStatus);

    // Actions
    const tdActions = document.createElement('td');
    tdActions.style.cssText = 'padding:10px 12px;display:flex;gap:4px';

    const restoreBtn = document.createElement('button');
    restoreBtn.className = 'btn btn-ghost btn-sm';
    restoreBtn.textContent = 'Restore';
    restoreBtn.addEventListener('click', () => this.handleRestore(id));
    tdActions.appendChild(restoreBtn);

    const delBtn = document.createElement('button');
    delBtn.className = 'btn btn-danger btn-sm';
    delBtn.textContent = '&#128465;';
    delBtn.title = 'Delete';
    delBtn.addEventListener('click', () => this.handleDelete(id));
    tdActions.appendChild(delBtn);

    tr.appendChild(tdActions);
    return tr;
  },

  /**
   * Create a new backup
   */
  async handleCreate() {
    const btn = document.getElementById('btn-create-backup');
    if (btn) {
      btn.disabled = true;
      btn.textContent = 'Creating...';
    }

    try {
      await API.post('/api/backups');
      App.showNotification('Backup created successfully', 'success');
      await this.load();
    } catch (err) {
      App.showNotification(err.message || 'Failed to create backup', 'error');
      if (btn) {
        btn.disabled = false;
        btn.textContent = '+ Create Backup';
      }
    }
  },

  /**
   * Restore from a backup
   */
  async handleRestore(id) {
    if (!confirm('This will overwrite current data with this backup. Are you sure you want to continue?')) return;

    try {
      await API.post(`/api/backups/${id}/restore`);
      App.showNotification('Backup restored successfully', 'success');
    } catch (err) {
      App.showNotification(err.message || 'Failed to restore backup', 'error');
    }
  },

  /**
   * Delete a backup
   */
  async handleDelete(id) {
    if (!confirm('Delete this backup? This cannot be undone.')) return;

    try {
      await API.del(`/api/backups/${id}`);
      App.showNotification('Backup deleted', 'success');
      await this.load();
    } catch (err) {
      App.showNotification(err.message || 'Failed to delete backup', 'error');
    }
  },

  // ── Helpers ──────────────────────────────────────────────────

  formatTime(iso) {
    try {
      const d = new Date(iso);
      return d.toLocaleString();
    } catch {
      return iso || '—';
    }
  },

  formatSize(bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / 1048576).toFixed(1) + ' MB';
  },
};
