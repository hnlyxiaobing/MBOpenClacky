// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — MCP Servers Panel
// ═══════════════════════════════════════════════════════════════

const MCP = {
  servers: [],
  tools: [],

  /**
   * Initialize MCP module
   */
  init() {
    console.log('[MCP] initialized');
  },

  /**
   * Load data when view is shown
   */
  async load() {
    const content = document.getElementById('mcp-content');
    content.innerHTML = '<div class="text-center"><div class="spinner" style="margin:40px auto"></div></div>';
    try {
      await this.loadServers();
      await this.loadTools();
      this.render();
    } catch (err) {
      content.innerHTML = `<p class="text-muted text-center">${I18n.t('mcp.failed')}</p>`;
      App.showNotification(err.message, 'error');
    }
  },

  async loadServers() {
    this.servers = await API.get('/api/mcp/servers');
  },

  async loadTools() {
    this.tools = await API.get('/api/mcp/tools');
  },

  /**
   * Render the full MCP panel
   */
  render() {
    const content = document.getElementById('mcp-content');
    content.innerHTML = '';

    // ── Servers Section ──
    const serverSection = document.createElement('div');
    serverSection.style.marginBottom = '28px';

    const serverHeader = document.createElement('div');
    serverHeader.className = 'settings-group';
    serverHeader.innerHTML = `
      <div class="settings-group-title" style="display:flex;align-items:center;justify-content:space-between">
        <span>${I18n.t('mcp.servers')} (${this.servers.length})</span>
      </div>`;
    const addBtn = document.createElement('button');
    addBtn.className = 'btn btn-primary btn-sm';
    addBtn.textContent = I18n.t('mcp.add_server');
    addBtn.addEventListener('click', () => this.showAddForm());
    serverHeader.querySelector('.settings-group-title').appendChild(addBtn);
    serverSection.appendChild(serverHeader);

    // Server cards grid
    if (this.servers.length === 0) {
      const empty = document.createElement('p');
      empty.className = 'text-muted';
      empty.style.cssText = 'font-size:13px;padding:16px 0';
      empty.textContent = I18n.t('mcp.no_servers');
      serverSection.appendChild(empty);
    } else {
      const grid = document.createElement('div');
      grid.className = 'skills-grid';
      this.servers.forEach(server => {
        grid.appendChild(this.createServerCard(server));
      });
      serverSection.appendChild(grid);
    }
    content.appendChild(serverSection);

    // ── Tools Section ──
    const toolSection = document.createElement('div');
    const toolHeader = document.createElement('div');
    toolHeader.className = 'settings-group';
    toolHeader.innerHTML = `<div class="settings-group-title">${I18n.t('mcp.available_tools')} (${this.tools.length})</div>`;
    toolSection.appendChild(toolHeader);

    if (this.tools.length === 0) {
      const empty = document.createElement('p');
      empty.className = 'text-muted';
      empty.style.cssText = 'font-size:13px;padding:16px 0';
      empty.textContent = I18n.t('mcp.no_tools');
      toolSection.appendChild(empty);
    } else {
      const grid = document.createElement('div');
      grid.className = 'skills-grid';
      this.tools.forEach(tool => {
        grid.appendChild(this.createToolCard(tool));
      });
      toolSection.appendChild(grid);
    }
    content.appendChild(toolSection);
  },

  /**
   * Create a server card element
   */
  createServerCard(server) {
    const card = document.createElement('div');
    card.className = 'skill-card';

    const nameRow = document.createElement('div');
    nameRow.style.cssText = 'display:flex;align-items:center;justify-content:space-between;margin-bottom:6px';

    const nameEl = document.createElement('div');
    nameEl.className = 'skill-card-name';
    nameEl.textContent = server.name || server.id || I18n.t('mcp.unnamed');
    nameRow.appendChild(nameEl);

    const delBtn = document.createElement('button');
    delBtn.className = 'btn btn-danger btn-sm';
    delBtn.textContent = I18n.t('mcp.delete');
    delBtn.style.cssText = 'padding:3px 8px;font-size:11px';
    delBtn.addEventListener('click', () => this.handleDelete(server.id || server.name));
    nameRow.appendChild(delBtn);
    card.appendChild(nameRow);

    const transport = document.createElement('div');
    transport.className = 'skill-card-desc';
    const transportType = (server.transport || 'unknown').toUpperCase();
    transport.textContent = `${I18n.t('mcp.transport')} ${transportType}`;
    card.appendChild(transport);

    if (server.transport === 'stdio' && server.command) {
      const cmdEl = document.createElement('div');
      cmdEl.className = 'skill-card-desc';
      cmdEl.style.cssText = 'margin-top:4px;font-family:var(--font-mono);font-size:11px;color:var(--info)';
      cmdEl.textContent = server.command + (server.args ? ' ' + server.args.join(' ') : '');
      card.appendChild(cmdEl);
    }
    if (server.transport === 'http' && server.url) {
      const urlEl = document.createElement('div');
      urlEl.className = 'skill-card-desc';
      urlEl.style.cssText = 'margin-top:4px;font-family:var(--font-mono);font-size:11px;color:var(--info)';
      urlEl.textContent = server.url;
      card.appendChild(urlEl);
    }

    // Status indicator
    const status = document.createElement('div');
    status.style.cssText = 'margin-top:8px;display:flex;align-items:center;gap:6px;font-size:11px';
    const dot = document.createElement('span');
    dot.style.cssText = `width:8px;height:8px;border-radius:50%;display:inline-block;background:${server.status === 'error' ? 'var(--danger)' : 'var(--success)'}`;
    status.appendChild(dot);
    const statusText = document.createElement('span');
    statusText.className = 'text-muted';
    statusText.textContent = server.status || I18n.t('mcp.connected');
    status.appendChild(statusText);
    card.appendChild(status);

    return card;
  },

  /**
   * Create a tool card element
   */
  createToolCard(tool) {
    const card = document.createElement('div');
    card.className = 'skill-card';
    card.style.cursor = 'pointer';
    card.addEventListener('click', () => this.showToolExecutor(tool));

    const nameEl = document.createElement('div');
    nameEl.className = 'skill-card-name';
    nameEl.textContent = tool.name || I18n.t('mcp.unknown_tool');
    card.appendChild(nameEl);

    if (tool.description) {
      const descEl = document.createElement('div');
      descEl.className = 'skill-card-desc';
      descEl.textContent = tool.description;
      card.appendChild(descEl);
    }

    if (tool.server) {
      const srcEl = document.createElement('div');
      srcEl.className = 'skill-card-desc';
      srcEl.style.cssText = 'margin-top:6px;font-size:11px;color:var(--accent)';
      srcEl.textContent = I18n.t('mcp.source') + ' ' + tool.server;
      card.appendChild(srcEl);
    }

    return card;
  },

  /**
   * Show add server modal form
   */
  showAddForm() {
    const body = `
      <div class="settings-field">
        <label for="mcp-server-name">${I18n.t('mcp.server_name')}</label>
        <input type="text" id="mcp-server-name" placeholder="${I18n.t('mcp.server_placeholder')}" autofocus>
        <div class="help-text">${I18n.t('mcp.server_name_help')}</div>
      </div>
      <div class="settings-field">
        <label for="mcp-transport">${I18n.t('mcp.transport_type')}</label>
        <select id="mcp-transport" onchange="MCP.toggleTransportFields()">
          <option value="stdio">Stdio</option>
          <option value="http">HTTP</option>
        </select>
      </div>
      <div id="mcp-stdio-fields">
        <div class="settings-field">
          <label for="mcp-command">${I18n.t('mcp.command')}</label>
          <input type="text" id="mcp-command" placeholder="${I18n.t('mcp.command_placeholder')}">
          <div class="help-text">${I18n.t('mcp.command_help')}</div>
        </div>
        <div class="settings-field">
          <label for="mcp-args">${I18n.t('mcp.args')}</label>
          <input type="text" id="mcp-args" placeholder="${I18n.t('mcp.args_placeholder')}">
          <div class="help-text">${I18n.t('mcp.args_help')}</div>
        </div>
      </div>
      <div id="mcp-http-fields" style="display:none">
        <div class="settings-field">
          <label for="mcp-url">${I18n.t('mcp.server_url')}</label>
          <input type="text" id="mcp-url" placeholder="${I18n.t('mcp.url_placeholder')}">
          <div class="help-text">${I18n.t('mcp.url_help')}</div>
        </div>
      </div>`;

    const footer = `
      <button class="btn btn-ghost" onclick="App.hideModal()">${I18n.t('common.cancel')}</button>
      <button class="btn btn-primary" onclick="MCP.handleAdd()">${I18n.t('mcp.add_btn')}</button>`;

    App.showModal(I18n.t('mcp.add_server_title'), body, footer);
    setTimeout(() => {
      const input = document.getElementById('mcp-server-name');
      if (input) input.focus();
    }, 100);
  },

  /**
   * Toggle stdio/http fields visibility
   */
  toggleTransportFields() {
    const transport = document.getElementById('mcp-transport');
    const stdioFields = document.getElementById('mcp-stdio-fields');
    const httpFields = document.getElementById('mcp-http-fields');
    if (!transport) return;
    if (transport.value === 'http') {
      stdioFields.style.display = 'none';
      httpFields.style.display = 'block';
    } else {
      stdioFields.style.display = 'block';
      httpFields.style.display = 'none';
    }
  },

  /**
   * Handle add server form submit
   */
  async handleAdd() {
    const name = (document.getElementById('mcp-server-name')?.value || '').trim();
    const transport = document.getElementById('mcp-transport')?.value || 'stdio';

    if (!name) {
      App.showNotification(I18n.t('mcp.required_name'), 'error');
      return;
    }

    const payload = { name, transport };

    if (transport === 'stdio') {
      const command = (document.getElementById('mcp-command')?.value || '').trim();
      if (!command) {
        App.showNotification(I18n.t('mcp.required_command'), 'error');
        return;
      }
      payload.command = command;
      const argsRaw = (document.getElementById('mcp-args')?.value || '').trim();
      if (argsRaw) {
        payload.args = argsRaw.split(',').map(a => a.trim()).filter(Boolean);
      }
    } else {
      const url = (document.getElementById('mcp-url')?.value || '').trim();
      if (!url) {
        App.showNotification(I18n.t('mcp.required_url'), 'error');
        return;
      }
      payload.url = url;
    }

    try {
      await API.post('/api/mcp/servers', payload);
      App.showNotification(I18n.t('mcp.added'), 'success');
      App.hideModal();
      await this.loadServers();
      await this.loadTools();
      this.render();
    } catch (err) {
      App.showNotification(err.message, 'error');
    }
  },

  /**
   * Delete an MCP server
   */
  async handleDelete(id) {
    if (!confirm(I18n.t('mcp.delete_confirm', { name: id }))) return;
    try {
      await API.del(`/api/mcp/servers/${encodeURIComponent(id)}`);
      App.showNotification(I18n.t('mcp.deleted'), 'success');
      await this.loadServers();
      await this.loadTools();
      this.render();
    } catch (err) {
      App.showNotification(err.message, 'error');
    }
  },

  /**
   * Show tool execution modal
   */
  showToolExecutor(tool) {
    const toolName = tool.name || 'Unknown';
    const body = `
      <div style="margin-bottom:12px">
        <strong style="color:var(--accent)">${toolName}</strong>
        ${tool.description ? `<p class="text-muted" style="font-size:12px;margin-top:4px"></p>` : ''}
      </div>
      <div class="settings-field">
        <label for="mcp-tool-args">${I18n.t('mcp.arguments_json')}</label>
        <textarea id="mcp-tool-args" class="form-control" rows="6"
          style="width:100%;padding:10px;background:var(--bg-tertiary);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text-primary);font-family:var(--font-mono);font-size:12px;resize:vertical"
          placeholder='{"key": "value"}'>{}</textarea>
        <div class="help-text">${I18n.t('mcp.args_help2')}</div>
      </div>
      <div id="mcp-tool-result" style="display:none;margin-top:12px">
        <div class="settings-group-title" style="font-size:12px">${I18n.t('mcp.result')}</div>
        <pre style="padding:12px;background:var(--bg-primary);border:1px solid var(--border);border-radius:var(--radius-sm);font-family:var(--font-mono);font-size:12px;max-height:250px;overflow:auto;color:var(--text-secondary);white-space:pre-wrap"><code id="mcp-tool-result-text"></code></pre>
      </div>`;

    const footer = `
      <button class="btn btn-ghost" onclick="App.hideModal()">${I18n.t('mcp.close')}</button>
      <button class="btn btn-primary" id="btn-execute-tool" onclick="MCP.handleExecuteTool('${toolName}')">${I18n.t('mcp.execute')}</button>`;

    App.showModal(I18n.t('mcp.execute_tool'), body, footer);

    // Set description safely
    if (tool.description) {
      const descEl = document.querySelector('#modal-body .text-muted');
      if (descEl) descEl.textContent = tool.description;
    }
  },

  /**
   * Execute a tool and display the result
   */
  async handleExecuteTool(name) {
    const argsEl = document.getElementById('mcp-tool-args');
    const resultDiv = document.getElementById('mcp-tool-result');
    const resultText = document.getElementById('mcp-tool-result-text');
    const execBtn = document.getElementById('btn-execute-tool');

    let args;
    try {
      args = JSON.parse(argsEl?.value || '{}');
    } catch (e) {
      App.showNotification(I18n.t('mcp.invalid_json'), 'error');
      return;
    }

    execBtn.disabled = true;
    execBtn.textContent = I18n.t('mcp.executing');

    try {
      const result = await API.post(`/api/mcp/tools/${encodeURIComponent(name)}/execute`, { arguments: args });
      resultDiv.style.display = 'block';
      resultText.textContent = JSON.stringify(result, null, 2);
      App.showNotification(I18n.t('mcp.executed'), 'success');
    } catch (err) {
      resultDiv.style.display = 'block';
      resultText.textContent = 'Error: ' + err.message;
      resultText.style.color = 'var(--danger)';
      App.showNotification(err.message, 'error');
    } finally {
      execBtn.disabled = false;
      execBtn.textContent = I18n.t('mcp.execute');
    }
  },
};
