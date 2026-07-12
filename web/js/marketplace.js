// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Extension Marketplace Panel
// ═══════════════════════════════════════════════════════════════

// ── MarketplaceStore: 市场状态管理 ─────────────────────────────
const MarketplaceStore = {
  items: [],
  search_query: '',
  active_category: 'all',
  loading: false,

  /** 获取商店技能/扩展列表 — GET /api/store/skills */
  async fetchItems() {
    this.loading = true;
    try {
      const data = await API.get('/api/store/skills');
      this.items = data.skills || data || [];
      return this.items;
    } catch (err) {
      console.error('[MarketplaceStore] fetchItems failed:', err);
      this.items = [];
      return [];
    } finally {
      this.loading = false;
    }
  },

  /** 安装扩展 — POST /api/skills/install */
  async install(name) {
    try {
      const data = await API.post('/api/skills/install', { name });
      return data;
    } catch (err) {
      console.error('[MarketplaceStore] install failed:', err);
      throw err;
    }
  },

  /** 卸载扩展 — DELETE /api/skills/:name */
  async uninstall(name) {
    try {
      await API.del(`/api/skills/${encodeURIComponent(name)}`);
      return true;
    } catch (err) {
      console.error('[MarketplaceStore] uninstall failed:', err);
      throw err;
    }
  },

  /** 搜索过滤 */
  getFiltered() {
    let items = this.items;
    if (this.active_category !== 'all') {
      items = items.filter(i => (i.category || i.tags?.[0] || 'other') === this.active_category);
    }
    if (this.search_query) {
      const q = this.search_query.toLowerCase();
      items = items.filter(i =>
        (i.name || '').toLowerCase().includes(q) ||
        (i.description || '').toLowerCase().includes(q) ||
        (i.author || '').toLowerCase().includes(q)
      );
    }
    return items;
  },

  /** 获取所有分类 */
  getCategories() {
    const cats = new Set();
    this.items.forEach(i => {
      const cat = i.category || i.tags?.[0] || 'other';
      cats.add(cat);
    });
    return ['all', ...cats];
  },
};

// ── MarketplaceView: 市场面板渲染 ──────────────────────────────
const MarketplaceView = {
  init() {
    console.log('[MarketplaceView] initialized');
  },

  async load() {
    await MarketplaceStore.fetchItems();
    this.renderMarketplacePanel();
  },

  renderMarketplacePanel() {
    const container = document.getElementById('marketplace-content');
    if (!container) return;

    const items = MarketplaceStore.getFiltered();
    const categories = MarketplaceStore.getCategories();

    const categoryHtml = categories.map(c => {
      const label = c === 'all' ? I18n.t('marketplace.cat_all') : c;
      return `<button class="skills-tab ${MarketplaceStore.active_category === c ? 'active' : ''}" onclick="MarketplaceView.setCategory('${c}')">${label}</button>`;
    }).join('');

    const itemsHtml = items.length === 0
      ? `<div class="empty-state" style="padding:32px">
          <div class="empty-state-icon">&#128722;</div>
          <h3>${I18n.t('marketplace.empty')}</h3>
          <p class="text-muted">${I18n.t('marketplace.empty_desc')}</p>
        </div>`
      : `<div class="skills-grid">${items.map(item => this._renderCard(item)).join('')}</div>`;

    container.innerHTML = `
      <div class="settings-group">
        <div class="settings-group-title" style="display:flex;align-items:center;justify-content:space-between">
          <span>${I18n.t('marketplace.title')} (${items.length})</span>
          <button class="btn btn-ghost btn-sm" onclick="MarketplaceView.refresh()" title="${I18n.t('marketplace.refresh')}">&#8635;</button>
        </div>
        <div class="settings-field">
          <input type="text" id="marketplace-search" placeholder="${I18n.t('marketplace.search_placeholder')}"
            value="${this._esc(MarketplaceStore.search_query)}"
            oninput="MarketplaceView.handleSearch(this.value)"
            style="width:100%;padding:9px 12px;background:var(--bg-tertiary);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text-primary);font-size:13px;outline:none">
        </div>
        <div class="skills-tabs" style="margin-bottom:12px">${categoryHtml}</div>
        ${itemsHtml}
      </div>`;
  },

  _renderCard(item) {
    const name = item.name || 'Unknown';
    const desc = item.description || I18n.t('marketplace.no_desc');
    const author = item.author || '';
    const version = item.version || '';
    const downloads = item.downloads || 0;
    const category = item.category || item.tags?.[0] || '';

    return `
      <div class="skill-card">
        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px">
          <div class="skill-card-name">${this._esc(name)}</div>
          ${category ? `<span class="brand-status-badge active" style="font-size:10px">${this._esc(category)}</span>` : ''}
        </div>
        ${author ? `<div class="skill-card-desc" style="color:var(--accent);font-size:11px">${I18n.t('marketplace.by')} ${this._esc(author)}</div>` : ''}
        <div class="skill-card-desc">${this._esc(desc.slice(0, 120))}</div>
        <div style="display:flex;align-items:center;justify-content:space-between;margin-top:10px">
          <div style="font-size:11px;color:var(--text-muted)">
            ${version ? `v${this._esc(version)}` : ''}
            ${downloads > 0 ? ` &middot; ${downloads} ${I18n.t('marketplace.downloads')}` : ''}
          </div>
          <button class="btn btn-primary btn-sm" onclick="MarketplaceView.handleInstall('${this._esc(name)}')">${I18n.t('marketplace.install')}</button>
        </div>
      </div>`;
  },

  handleSearch(query) {
    MarketplaceStore.search_query = query;
    this.renderMarketplacePanel();
    // Restore focus and cursor position
    const input = document.getElementById('marketplace-search');
    if (input) { input.focus(); input.setSelectionRange(query.length, query.length); }
  },

  setCategory(cat) {
    MarketplaceStore.active_category = cat;
    this.renderMarketplacePanel();
  },

  async refresh() {
    await MarketplaceStore.fetchItems();
    this.renderMarketplacePanel();
  },

  async handleInstall(name) {
    try {
      await MarketplaceStore.install(name);
      App.showNotification(`${I18n.t('marketplace.installed')}: ${name}`, 'success');
    } catch (err) {
      App.showNotification(`${I18n.t('marketplace.install_failed')}: ${err.message}`, 'error');
    }
  },

  _esc(text) {
    const div = document.createElement('div');
    div.textContent = text || '';
    return div.innerHTML;
  },
};
