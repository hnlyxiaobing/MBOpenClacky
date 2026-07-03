// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Git Panel
// ═══════════════════════════════════════════════════════════════

const GitPanel = {
  status: null,
  diff: null,
  committing: false,

  /**
   * Initialize git panel
   */
  init() {
    console.log('[GitPanel] initialized');
  },

  /**
   * Load git data and render
   */
  async load() {
    await this.loadStatus();
    await this.loadDiff();
    this.render();
  },

  /**
   * Fetch git status from backend
   */
  async loadStatus() {
    try {
      this.status = await API.get('/api/git/status');
    } catch (err) {
      console.error('[GitPanel] Status load failed:', err);
      this.status = null;
    }
  },

  /**
   * Fetch git diff from backend
   */
  async loadDiff() {
    try {
      const data = await API.get('/api/git/diff');
      this.diff = typeof data === 'string' ? data : (data.diff || '');
    } catch (err) {
      console.warn('[GitPanel] Diff load failed:', err);
      this.diff = null;
    }
  },

  /**
   * Render the git panel into #git-content
   */
  render() {
    const content = document.getElementById('git-content');
    if (!content) return;

    // Build header
    const header = document.querySelector('#view-git .view-header');
    if (header) {
      header.innerHTML = '';

      const titleWrap = document.createElement('div');
      titleWrap.style.cssText = 'display:flex;align-items:center;gap:10px;';

      const h2 = document.createElement('h2');
      h2.textContent = 'Git';
      titleWrap.appendChild(h2);

      if (this.status && this.status.branch) {
        const branchBadge = document.createElement('span');
        branchBadge.style.cssText = 'background:var(--accent-dim);color:var(--accent);padding:3px 10px;border-radius:10px;font-size:12px;font-weight:600;';
        branchBadge.textContent = `⎇ ${this.status.branch}`;
        titleWrap.appendChild(branchBadge);
      }

      header.appendChild(titleWrap);

      // Refresh button
      const refreshBtn = document.createElement('button');
      refreshBtn.className = 'btn btn-ghost btn-sm';
      refreshBtn.textContent = '↻ Refresh';
      refreshBtn.addEventListener('click', () => this.load());
      header.appendChild(refreshBtn);
    }

    // Build body
    content.innerHTML = '';

    if (!this.status) {
      content.innerHTML = `
        <div class="empty-state">
          <div class="empty-state-icon">⎇</div>
          <h3>No Git Data</h3>
          <p class="text-muted">Could not retrieve git status.</p>
        </div>`;
      return;
    }

    // ── Changes Section ──────────────────────────────────────
    const changesSection = document.createElement('div');
    changesSection.style.cssText = 'margin-bottom:24px;';

    const changesTitle = document.createElement('h3');
    changesTitle.style.cssText = 'font-size:13px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.8px;margin-bottom:12px;padding-bottom:8px;border-bottom:1px solid var(--border);';
    changesTitle.textContent = 'Changed Files';
    changesSection.appendChild(changesTitle);

    const files = this.extractFiles();
    if (files.length === 0) {
      const noChanges = document.createElement('p');
      noChanges.className = 'text-muted';
      noChanges.style.cssText = 'font-size:13px;padding:16px 0;';
      noChanges.textContent = 'No changes detected. Working tree is clean.';
      changesSection.appendChild(noChanges);
    } else {
      const fileList = document.createElement('div');
      fileList.style.cssText = 'display:flex;flex-direction:column;gap:2px;';

      files.forEach(file => {
        const row = document.createElement('div');
        row.style.cssText = 'display:flex;align-items:center;justify-content:space-between;padding:8px 12px;border-radius:var(--radius-sm);transition:background var(--transition);';
        row.addEventListener('mouseenter', () => { row.style.background = 'var(--bg-hover)'; });
        row.addEventListener('mouseleave', () => { row.style.background = 'transparent'; });

        const leftWrap = document.createElement('div');
        leftWrap.style.cssText = 'display:flex;align-items:center;gap:10px;min-width:0;flex:1;';

        // Status badge
        const statusBadge = document.createElement('span');
        statusBadge.style.cssText = this.getStatusBadgeStyle(file.status);
        statusBadge.textContent = this.getStatusLabel(file.status);
        leftWrap.appendChild(statusBadge);

        // File path
        const pathEl = document.createElement('span');
        pathEl.style.cssText = 'font-size:13px;font-family:var(--font-mono);color:var(--text-primary);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;';
        pathEl.textContent = file.path;
        leftWrap.appendChild(pathEl);

        row.appendChild(leftWrap);

        // Staged indicator
        if (file.staged) {
          const stagedEl = document.createElement('span');
          stagedEl.style.cssText = 'font-size:11px;color:var(--success);font-weight:500;white-space:nowrap;margin-left:8px;';
          stagedEl.textContent = '● staged';
          row.appendChild(stagedEl);
        }

        fileList.appendChild(row);
      });

      changesSection.appendChild(fileList);
    }
    content.appendChild(changesSection);

    // ── Diff Section ─────────────────────────────────────────
    if (this.diff) {
      const diffSection = document.createElement('div');
      diffSection.style.cssText = 'margin-bottom:24px;';

      const diffTitle = document.createElement('h3');
      diffTitle.style.cssText = 'font-size:13px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.8px;margin-bottom:12px;padding-bottom:8px;border-bottom:1px solid var(--border);';
      diffTitle.textContent = 'Diff';
      diffSection.appendChild(diffTitle);

      const diffContainer = document.createElement('div');
      diffContainer.style.cssText = 'background:var(--bg-primary);border:1px solid var(--border);border-radius:var(--radius);overflow:auto;max-height:400px;font-family:var(--font-mono);font-size:12px;line-height:1.6;';
      this.renderDiff(this.diff, diffContainer);
      diffSection.appendChild(diffContainer);

      content.appendChild(diffSection);
    }

    // ── Commit Section ───────────────────────────────────────
    const commitSection = document.createElement('div');
    commitSection.style.cssText = 'margin-top:8px;';

    const commitTitle = document.createElement('h3');
    commitTitle.style.cssText = 'font-size:13px;font-weight:600;color:var(--text-secondary);text-transform:uppercase;letter-spacing:0.8px;margin-bottom:12px;padding-bottom:8px;border-bottom:1px solid var(--border);';
    commitTitle.textContent = 'Commit';
    commitSection.appendChild(commitTitle);

    const formGroup = document.createElement('div');
    formGroup.style.cssText = 'margin-bottom:12px;';

    const textarea = document.createElement('textarea');
    textarea.id = 'git-commit-message';
    textarea.placeholder = 'Enter commit message...';
    textarea.style.cssText = 'width:100%;min-height:80px;padding:10px 12px;background:var(--bg-tertiary);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text-primary);font-size:13px;font-family:var(--font-sans);resize:vertical;outline:none;transition:border-color var(--transition);';
    textarea.addEventListener('focus', () => { textarea.style.borderColor = 'var(--accent)'; });
    textarea.addEventListener('blur', () => { textarea.style.borderColor = 'var(--border)'; });
    formGroup.appendChild(textarea);
    commitSection.appendChild(formGroup);

    const commitBtn = document.createElement('button');
    commitBtn.className = 'btn btn-primary';
    commitBtn.textContent = '✓ Commit';
    commitBtn.disabled = files.length === 0 || this.committing;
    commitBtn.addEventListener('click', () => this.handleCommit());
    commitSection.appendChild(commitBtn);

    content.appendChild(commitSection);
  },

  /**
   * Render diff text with syntax coloring
   */
  renderDiff(diffText, container) {
    const lines = diffText.split('\n');
    const table = document.createElement('table');
    table.style.cssText = 'width:100%;border-collapse:collapse;';

    lines.forEach((line, i) => {
      if (!line && i === lines.length - 1) return; // skip trailing empty line

      const tr = document.createElement('tr');
      const td = document.createElement('td');
      td.style.cssText = 'padding:2px 12px;white-space:pre;';

      if (line.startsWith('+++') || line.startsWith('---')) {
        td.style.cssText += 'background:var(--bg-tertiary);color:var(--text-secondary);font-weight:600;';
      } else if (line.startsWith('@@')) {
        td.style.cssText += 'background:rgba(122,162,247,0.1);color:var(--info);';
      } else if (line.startsWith('+')) {
        td.style.cssText += 'background:rgba(158,206,106,0.12);color:var(--success);';
      } else if (line.startsWith('-')) {
        td.style.cssText += 'background:rgba(247,118,142,0.12);color:var(--danger);';
      } else if (line.startsWith('diff ') || line.startsWith('index ')) {
        td.style.cssText += 'background:var(--bg-tertiary);color:var(--text-muted);font-weight:500;';
      } else {
        td.style.cssText += 'color:var(--text-secondary);';
      }

      td.textContent = line || ' ';
      tr.appendChild(td);
      table.appendChild(tr);
    });

    container.appendChild(table);
  },

  /**
   * Extract file list from status data
   */
  extractFiles() {
    if (!this.status) return [];
    const files = [];

    // Handle different response shapes
    const changed = this.status.files || this.status.changed_files || this.status.changes || [];

    if (Array.isArray(changed)) {
      changed.forEach(f => {
        if (typeof f === 'string') {
          files.push({ path: f, status: 'modified', staged: false });
        } else {
          files.push({
            path: f.path || f.file || f.name || 'unknown',
            status: (f.status || f.state || f.type || 'modified').toLowerCase(),
            staged: !!f.staged,
          });
        }
      });
    }

    // Also handle separate staged/unstaged arrays
    if (this.status.staged && Array.isArray(this.status.staged)) {
      this.status.staged.forEach(f => {
        const path = typeof f === 'string' ? f : (f.path || f.file || '');
        const existing = files.find(x => x.path === path);
        if (existing) {
          existing.staged = true;
        } else {
          files.push({
            path,
            status: (typeof f === 'object' ? (f.status || f.state || 'modified') : 'modified').toLowerCase(),
            staged: true,
          });
        }
      });
    }

    if (this.status.unstaged && Array.isArray(this.status.unstaged)) {
      this.status.unstaged.forEach(f => {
        const path = typeof f === 'string' ? f : (f.path || f.file || '');
        const existing = files.find(x => x.path === path);
        if (!existing) {
          files.push({
            path,
            status: (typeof f === 'object' ? (f.status || f.state || 'modified') : 'modified').toLowerCase(),
            staged: false,
          });
        }
      });
    }

    return files;
  },

  /**
   * Get CSS style string for file status badge
   */
  getStatusBadgeStyle(status) {
    const base = 'display:inline-block;width:20px;height:20px;border-radius:var(--radius-sm);font-size:11px;font-weight:700;text-align:center;line-height:20px;flex-shrink:0;';
    switch (status) {
      case 'added':
      case 'new':
      case 'untracked':
        return base + 'background:rgba(158,206,106,0.15);color:var(--success);';
      case 'deleted':
      case 'removed':
        return base + 'background:rgba(247,118,142,0.15);color:var(--danger);';
      case 'renamed':
        return base + 'background:rgba(224,175,104,0.15);color:var(--warning);';
      default: // modified
        return base + 'background:rgba(122,162,247,0.15);color:var(--accent);';
    }
  },

  /**
   * Get display label for file status
   */
  getStatusLabel(status) {
    switch (status) {
      case 'added':
      case 'new':
      case 'untracked':
        return 'A';
      case 'deleted':
      case 'removed':
        return 'D';
      case 'renamed':
        return 'R';
      default:
        return 'M';
    }
  },

  /**
   * Handle commit action
   */
  async handleCommit() {
    const textarea = document.getElementById('git-commit-message');
    const message = textarea ? textarea.value.trim() : '';
    if (!message) {
      App.showNotification('Please enter a commit message', 'error');
      if (textarea) textarea.focus();
      return;
    }

    this.committing = true;
    try {
      await API.post('/api/git/commit', { message });
      App.showNotification('Committed successfully', 'success');
      if (textarea) textarea.value = '';
      await this.load();
    } catch (err) {
      App.showNotification('Commit failed: ' + err.message, 'error');
    } finally {
      this.committing = false;
    }
  },
};
