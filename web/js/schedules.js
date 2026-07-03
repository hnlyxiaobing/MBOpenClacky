// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Schedules Panel
// ═══════════════════════════════════════════════════════════════

const Schedules = {
  schedules: [],

  init() {
    console.log('[Schedules] initialized');
  },

  async load() {
    await this.loadSchedules();
    this.render();
  },

  async loadSchedules() {
    try {
      this.schedules = await API.get('/api/schedules');
    } catch (err) {
      console.error('[Schedules] Load failed:', err);
      App.showNotification(err.message || 'Failed to load schedules', 'error');
      this.schedules = [];
    }
  },

  render() {
    const container = document.querySelector('#view-schedules .view-content');
    if (!container) return;
    container.innerHTML = '';

    const header = document.createElement('div');
    header.innerHTML = '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px"><h3 style="font-size:14px;color:var(--text-secondary)">Scheduled Tasks</h3><button class="btn btn-primary btn-sm" id="btn-add-schedule">+ New Schedule</button></div>';
    container.appendChild(header);
    header.querySelector('#btn-add-schedule').addEventListener('click', () => this.showForm());

    if (this.schedules.length === 0) {
      container.insertAdjacentHTML('beforeend', '<div class="empty-state"><div class="empty-state-icon">&#128336;</div><h3>No Schedules</h3><p class="text-muted">Create a scheduled task to get started.</p></div>');
      return;
    }

    const list = document.createElement('div');
    list.style.cssText = 'display:flex;flex-direction:column;gap:12px';
    this.schedules.forEach(s => list.appendChild(this.renderCard(s)));
    container.appendChild(list);
  },

  renderCard(schedule) {
    const id = schedule.id || schedule.schedule_id;
    const card = document.createElement('div');
    card.className = 'skill-card';
    card.style.padding = '16px';

    const enabledClass = schedule.enabled !== false ? 'status-badge running' : 'status-badge';
    const enabledText = schedule.enabled !== false ? 'Enabled' : 'Disabled';
    const cronCode = `<code style="background:var(--bg-tertiary);padding:2px 5px;border-radius:3px;color:var(--info);font-size:12px">${this.esc(schedule.cron_expression || '—')}</code>`;
    const nextRun = schedule.next_execution ? `<div style="margin-bottom:4px"><strong>Next run: </strong>${this.esc(this.formatTime(schedule.next_execution))}</div>` : '';
    const msgLine = schedule.message ? `<div style="color:var(--text-muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${this.esc(schedule.message)}</div>` : '';

    card.innerHTML = `
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:8px">
        <div style="font-size:14px;font-weight:600;color:var(--text-primary)">${this.esc(schedule.name || 'Unnamed')}</div>
        <div style="display:flex;gap:4px;align-items:center">
          <span class="${enabledClass}" data-action="toggle" style="font-size:10px;padding:2px 8px;border-radius:10px;cursor:pointer">${enabledText}</span>
          <button class="btn btn-ghost btn-sm" data-action="trigger" title="Trigger now">&#9654;</button>
          <button class="btn btn-ghost btn-sm" data-action="history">History</button>
          <button class="btn btn-ghost btn-sm" data-action="edit">Edit</button>
          <button class="btn btn-danger btn-sm" data-action="delete" title="Delete">&#128465;</button>
        </div>
      </div>
      <div style="font-size:12px;color:var(--text-secondary)">
        <div style="margin-bottom:4px"><strong>Cron: </strong>${cronCode}</div>
        ${nextRun}
        ${msgLine}
      </div>
      <div class="schedule-history" style="display:none;margin-top:12px;border-top:1px solid var(--border);padding-top:12px"></div>`;

    // Bind actions via delegation
    card.addEventListener('click', (e) => {
      const action = e.target.closest('[data-action]')?.dataset.action;
      if (action === 'toggle') this.toggleEnabled(id, schedule);
      else if (action === 'trigger') this.handleTrigger(id);
      else if (action === 'history') this.showHistory(id, card);
      else if (action === 'edit') this.showForm(schedule);
      else if (action === 'delete') this.handleDelete(id);
    });

    return card;
  },

  showForm(schedule) {
    const isEdit = !!schedule;
    const id = schedule ? (schedule.id || schedule.schedule_id) : null;
    const activeClass = (!isEdit || schedule.enabled !== false) ? 'active' : '';

    const body = `
      <div class="settings-field">
        <label for="schedule-name">Name</label>
        <input type="text" id="schedule-name" placeholder="Daily Summary" value="${isEdit ? this.escAttr(schedule.name) : ''}">
      </div>
      <div class="settings-field">
        <label for="schedule-message">Message</label>
        <textarea id="schedule-message" rows="3" placeholder="Enter the prompt or message to send"
          style="width:100%;padding:9px 12px;background:var(--bg-tertiary);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text-primary);font-size:13px;outline:none;resize:vertical;font-family:var(--font-sans)">${isEdit ? this.esc(schedule.message || '') : ''}</textarea>
      </div>
      <div class="settings-field">
        <label for="schedule-cron">Cron Expression</label>
        <input type="text" id="schedule-cron" placeholder="0 9 * * *" value="${isEdit ? this.escAttr(schedule.cron_expression) : ''}">
        <div class="help-text">Standard cron format: minute hour day month weekday (e.g. "0 9 * * *" = daily at 9am)</div>
      </div>
      <div class="settings-field">
        <div class="toggle-wrapper">
          <label>Enabled</label>
          <div class="toggle ${activeClass}" id="schedule-enabled-toggle" onclick="this.classList.toggle('active')"></div>
        </div>
      </div>`;

    const footer = `
      <button class="btn btn-ghost" onclick="App.hideModal()">Cancel</button>
      <button class="btn btn-primary" onclick="Schedules.handleSave(${isEdit ? `'${id}'` : 'null'})">${isEdit ? 'Update' : 'Create'}</button>`;

    App.showModal(isEdit ? 'Edit Schedule' : 'New Schedule', body, footer);
    setTimeout(() => document.getElementById('schedule-name')?.focus(), 100);
  },

  async handleSave(id) {
    const name = document.getElementById('schedule-name')?.value.trim();
    const message = document.getElementById('schedule-message')?.value.trim();
    const cron = document.getElementById('schedule-cron')?.value.trim();
    const enabled = document.getElementById('schedule-enabled-toggle')?.classList.contains('active') ?? true;

    if (!name) { App.showNotification('Name is required', 'error'); return; }
    if (!cron) { App.showNotification('Cron expression is required', 'error'); return; }

    const data = { name, message, cron_expression: cron, enabled };
    try {
      if (id) {
        await API.put(`/api/schedules/${id}`, data);
        App.showNotification('Schedule updated', 'success');
      } else {
        await API.post('/api/schedules', data);
        App.showNotification('Schedule created', 'success');
      }
      App.hideModal();
      await this.load();
    } catch (err) {
      App.showNotification(err.message || 'Failed to save schedule', 'error');
    }
  },

  async toggleEnabled(id, schedule) {
    try {
      const updated = { name: schedule.name, message: schedule.message, cron_expression: schedule.cron_expression, enabled: schedule.enabled === false };
      await API.put(`/api/schedules/${id}`, updated);
      App.showNotification(updated.enabled ? 'Schedule enabled' : 'Schedule disabled', 'success');
      await this.load();
    } catch (err) {
      App.showNotification(err.message || 'Failed to toggle schedule', 'error');
    }
  },

  async handleDelete(id) {
    if (!confirm('Delete this schedule? This cannot be undone.')) return;
    try {
      await API.del(`/api/schedules/${id}`);
      App.showNotification('Schedule deleted', 'success');
      await this.load();
    } catch (err) {
      App.showNotification(err.message || 'Failed to delete schedule', 'error');
    }
  },

  async handleTrigger(id) {
    try {
      await API.post(`/api/schedules/${id}/trigger`);
      App.showNotification('Schedule triggered successfully', 'success');
    } catch (err) {
      App.showNotification(err.message || 'Failed to trigger schedule', 'error');
    }
  },

  async showHistory(id, cardEl) {
    const section = cardEl.querySelector('.schedule-history');
    if (!section) return;

    if (section.style.display !== 'none' && section.innerHTML !== '') {
      section.style.display = 'none';
      section.innerHTML = '';
      return;
    }

    section.style.display = 'block';
    section.innerHTML = '<div class="spinner" style="margin:12px auto"></div>';

    try {
      const history = await API.get(`/api/schedules/${id}/history`);
      if (!history || history.length === 0) {
        section.innerHTML = '<p class="text-muted" style="font-size:12px">No execution history</p>';
        return;
      }

      let html = '<div style="font-size:12px;font-weight:600;color:var(--text-secondary);margin-bottom:8px">Execution History</div>';
      history.forEach(entry => {
        const ok = entry.status === 'success';
        const icon = ok ? '\u2713' : '\u2717';
        const color = ok ? 'var(--success)' : 'var(--danger)';
        const time = this.esc(this.formatTime(entry.executed_at || entry.timestamp));
        const output = entry.output ? `<span style="color:var(--text-secondary);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;flex:1" title="${this.escAttr(entry.output)}">${this.esc(entry.output)}</span>` : '';
        html += `<div style="display:flex;align-items:center;gap:8px;padding:6px 0;border-bottom:1px solid var(--border-light);font-size:12px"><span style="color:${color}">${icon}</span><span class="text-muted">${time}</span>${output}</div>`;
      });
      section.innerHTML = html;
    } catch (err) {
      section.innerHTML = `<p class="text-muted" style="font-size:12px">Failed to load history</p>`;
    }
  },

  // ── Helpers ──────────────────────────────────────────────────
  formatTime(iso) { try { return new Date(iso).toLocaleString(); } catch { return iso || '—'; } },
  esc(s) { const d = document.createElement('div'); d.textContent = s || ''; return d.innerHTML; },
  escAttr(s) { return (s || '').replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); },
};
