// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Billing Panel
// ═══════════════════════════════════════════════════════════════

const Billing = {
  status: null,
  usage: null,

  init() {
    console.log('[Billing] initialized');
  },

  async load() {
    const content = document.querySelector('#view-billing .view-content');
    if (content) {
      content.innerHTML = '<div class="text-center"><div class="spinner" style="margin:40px auto"></div></div>';
    }
    await Promise.all([this.loadStatus(), this.loadUsage()]);
    this.render();
  },

  async loadStatus() {
    try {
      this.status = await API.get('/api/billing/status');
    } catch (err) {
      console.error('[Billing] Status load failed:', err);
      this.status = { active: false, error: err.message };
    }
  },

  async loadUsage() {
    try {
      this.usage = await API.get('/api/billing/usage');
    } catch (err) {
      console.error('[Billing] Usage load failed:', err);
      this.usage = null;
    }
  },

  render() {
    const content = document.querySelector('#view-billing .view-content');
    if (!content) return;

    content.innerHTML = '';

    // Status Overview Card
    content.appendChild(this.renderStatusCard());

    // Activate Section (only if not active)
    if (!this.status || !this.status.active) {
      content.appendChild(this.renderActivateSection());
    }

    // Usage Statistics
    if (this.usage) {
      content.appendChild(this.renderUsageSection());
    }
  },

  renderStatusCard() {
    const card = document.createElement('div');
    card.className = 'stat-card';
    card.style.marginBottom = '20px';
    card.style.textAlign = 'left';
    card.style.padding = '20px';

    const isActive = this.status && this.status.active;
    const statusText = isActive ? I18n.t('billing.active') : I18n.t('billing.inactive');
    const statusColor = isActive ? 'var(--success)' : 'var(--danger)';
    const plan = (this.status && this.status.plan) || 'N/A';
    const expires = (this.status && this.status.expires_at) || 'N/A';

    card.innerHTML = `
      <div class="settings-group-title">${I18n.t('billing.subscription')}</div>
      <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:16px;align-items:center">
        <div>
          <div style="font-size:11px;color:var(--text-muted);text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px">${I18n.t('billing.status')}</div>
          <span class="status-badge${isActive ? ' running' : ''}" style="${!isActive ? 'background:rgba(247,118,142,0.15);color:var(--danger)' : ''}">${statusText}</span>
        </div>
        <div>
          <div style="font-size:11px;color:var(--text-muted);text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px">${I18n.t('billing.plan')}</div>
          <div style="font-size:14px;font-weight:600;color:var(--text-primary)"></div>
        </div>
        <div>
          <div style="font-size:11px;color:var(--text-muted);text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px">${I18n.t('billing.expires')}</div>
          <div style="font-size:14px;color:var(--text-secondary)"></div>
        </div>
      </div>`;

    // Use textContent for user-generated data (XSS prevention)
    const values = card.querySelectorAll('div > div:nth-child(2)');
    if (values[0]) values[0].textContent = plan;
    if (values[1]) values[1].textContent = expires;

    return card;
  },

  renderActivateSection() {
    const section = document.createElement('div');
    section.className = 'stat-card';
    section.style.marginBottom = '20px';
    section.style.textAlign = 'left';
    section.style.padding = '20px';

    section.innerHTML = `
      <div class="settings-group-title">${I18n.t('billing.activate')}</div>
      <div class="settings-field">
        <label for="billing-plan">${I18n.t('billing.plan')}</label>
        <select id="billing-plan">
          <option value="monthly">${I18n.t('billing.monthly')}</option>
          <option value="yearly">${I18n.t('billing.yearly')}</option>
          <option value="pro">${I18n.t('billing.pro')}</option>
        </select>
      </div>
      <div class="settings-field">
        <label for="billing-key">${I18n.t('billing.license_key')}</label>
        <input type="text" id="billing-key" placeholder="${I18n.t('billing.license_placeholder')}">
      </div>
      <button class="btn btn-primary" id="btn-billing-activate">${I18n.t('billing.activate_btn')}</button>`;

    const btn = section.querySelector('#btn-billing-activate');
    btn.addEventListener('click', () => {
      const plan = section.querySelector('#billing-plan').value;
      const key = section.querySelector('#billing-key').value.trim();
      this.handleActivate({ plan, key });
    });

    return section;
  },

  async handleActivate(data) {
    try {
      await API.post('/api/billing/activate', data);
      App.showNotification(I18n.t('billing.activated'), 'success');
      await this.load();
    } catch (err) {
      App.showNotification(err.message || I18n.t('billing.activation_failed'), 'error');
    }
  },

  renderUsageSection() {
    const section = document.createElement('div');
    section.style.marginBottom = '20px';

    // Total tokens stat card
    const totalTokens = this.usage.total_tokens || 0;
    const statsHtml = `
      <div class="stats-grid" style="margin-bottom:20px">
        <div class="stat-card">
          <div class="stat-card-value">${this.formatNumber(totalTokens)}</div>
          <div class="stat-card-label">${I18n.t('billing.total_tokens')}</div>
        </div>
        <div class="stat-card">
          <div class="stat-card-value">${this.usage.by_model ? Object.keys(this.usage.by_model).length : 0}</div>
          <div class="stat-card-label">${I18n.t('billing.models_used')}</div>
        </div>
        <div class="stat-card">
          <div class="stat-card-value">${this.usage.by_day ? Object.keys(this.usage.by_day).length : 0}</div>
          <div class="stat-card-label">${I18n.t('billing.active_days')}</div>
        </div>
      </div>`;

    section.innerHTML = statsHtml;

    // Per-model breakdown table
    if (this.usage.by_model && Object.keys(this.usage.by_model).length > 0) {
      section.appendChild(this.renderModelTable());
    }

    // Daily usage chart
    if (this.usage.by_day && Object.keys(this.usage.by_day).length > 0) {
      section.appendChild(this.renderUsageChart(this.usage.by_day));
    }

    return section;
  },

  renderModelTable() {
    const card = document.createElement('div');
    card.className = 'stat-card';
    card.style.marginBottom = '20px';
    card.style.textAlign = 'left';
    card.style.padding = '20px';

    const header = document.createElement('div');
    header.className = 'settings-group-title';
    header.textContent = I18n.t('billing.cost_by_model');
    card.appendChild(header);

    const table = document.createElement('table');
    table.style.cssText = 'width:100%;border-collapse:collapse;font-size:13px';

    const thead = document.createElement('thead');
    const headerRow = document.createElement('tr');
    [I18n.t('billing.model'), I18n.t('billing.tokens'), I18n.t('billing.est_cost')].forEach(text => {
      const th = document.createElement('th');
      th.textContent = text;
      th.style.cssText = 'text-align:left;padding:8px 12px;border-bottom:1px solid var(--border);color:var(--text-secondary);font-size:11px;text-transform:uppercase;letter-spacing:0.5px';
      headerRow.appendChild(th);
    });
    thead.appendChild(headerRow);
    table.appendChild(thead);

    const tbody = document.createElement('tbody');
    for (const [model, data] of Object.entries(this.usage.by_model)) {
      const row = document.createElement('tr');
      const tokens = typeof data === 'object' ? (data.tokens || 0) : data;
      const cost = typeof data === 'object' ? (data.cost || 0) : 0;

      const cells = [
        { text: model, style: 'padding:8px 12px;color:var(--text-primary);font-weight:500' },
        { text: this.formatNumber(tokens), style: 'padding:8px 12px;color:var(--text-secondary)' },
        { text: `$${Number(cost).toFixed(4)}`, style: 'padding:8px 12px;color:var(--accent)' },
      ];
      cells.forEach(({ text, style }) => {
        const td = document.createElement('td');
        td.textContent = text;
        td.style.cssText = style;
        row.appendChild(td);
      });
      tbody.appendChild(row);
    }
    table.appendChild(tbody);
    card.appendChild(table);

    return card;
  },

  renderUsageChart(byDay) {
    const card = document.createElement('div');
    card.className = 'stat-card';
    card.style.textAlign = 'left';
    card.style.padding = '20px';

    const header = document.createElement('div');
    header.className = 'settings-group-title';
    header.textContent = I18n.t('billing.daily_usage');
    card.appendChild(header);

    const entries = Object.entries(byDay).sort((a, b) => a[0].localeCompare(b[0]));
    const maxVal = Math.max(...entries.map(([, v]) => (typeof v === 'object' ? (v.tokens || 0) : v)), 1);

    const chart = document.createElement('div');
    chart.style.cssText = 'display:flex;align-items:flex-end;gap:4px;height:120px;padding-top:8px';

    entries.forEach(([day, val]) => {
      const tokens = typeof val === 'object' ? (val.tokens || 0) : val;
      const pct = Math.max((tokens / maxVal) * 100, 2);

      const col = document.createElement('div');
      col.style.cssText = `flex:1;display:flex;flex-direction:column;align-items:center;gap:4px`;

      const bar = document.createElement('div');
      bar.style.cssText = `width:100%;min-width:8px;height:${pct}%;background:var(--accent);border-radius:3px 3px 0 0;transition:height 0.3s ease`;
      bar.title = `${day}: ${this.formatNumber(tokens)} tokens`;

      const label = document.createElement('div');
      label.style.cssText = 'font-size:9px;color:var(--text-muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%';
      label.textContent = day.slice(5); // Show MM-DD only

      col.appendChild(bar);
      col.appendChild(label);
      chart.appendChild(col);
    });

    card.appendChild(chart);
    return card;
  },

  formatNumber(n) {
    if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
    if (n >= 1_000) return (n / 1_000).toFixed(1) + 'K';
    return String(n);
  },
};
