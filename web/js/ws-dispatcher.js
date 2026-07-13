// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI - WebSocket Dispatcher
// RenderTarget stack + phase grouping (subagent / thinking collapse)
// ═══════════════════════════════════════════════════════════════

const Dispatcher = {
  _stack: [],
  OUTER_ID: 'chat-messages',

  outer() {
    return document.getElementById(this.OUTER_ID);
  },

  current() {
    return this._stack.length ? this._stack[this._stack.length - 1] : this.outer();
  },

  push(el) {
    this._stack.push(el);
  },

  pop() {
    return this._stack.length ? this._stack.pop() : null;
  },

  reset() {
    this._stack = [];
  },

  _escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  },

  _createCard(icon, title, cardClass) {
    const card = document.createElement('div');
    card.className = 'phase-card ' + cardClass;
    card.style.cssText =
      'border:1px solid var(--border);border-radius:var(--radius);' +
      'margin:8px 0;overflow:hidden;background:var(--bg-tertiary)';

    const header = document.createElement('div');
    header.style.cssText =
      'display:flex;align-items:center;gap:8px;padding:8px 12px;' +
      'cursor:pointer;user-select:none;border-bottom:1px solid var(--border-light)';
    header.innerHTML =
      '<span style="font-size:16px">' + icon + '</span>' +
      '<span style="font-weight:600;flex:1;color:var(--text-primary)">' +
      this._escapeHtml(title) + '</span>' +
      '<span class="phase-toggle" style="font-size:12px;color:var(--text-muted)">\u25BC</span>';

    const body = document.createElement('div');
    body.className = 'phase-card-body';
    body.style.cssText = 'padding:4px 12px 12px';

    card.appendChild(header);
    card.appendChild(body);

    header.addEventListener('click', () => {
      const collapsed = body.style.display === 'none';
      body.style.display = collapsed ? '' : 'none';
      card.classList.toggle('collapsed', !collapsed);
      header.querySelector('.phase-toggle').textContent = collapsed ? '\u25BC' : '\u25B6';
    });

    this.outer().appendChild(card);
    this.push(body);
    return card;
  },

  createSubagentCard(name) {
    return this._createCard('&#129302;', 'Subagent: ' + (name || ''), 'subagent-card');
  },

  createThinkCard() {
    return this._createCard('&#128173;', 'Thinking', 'think-card');
  },

  closeCard() {
    const body = this.pop();
    if (body && body.parentElement) {
      body.parentElement.classList.add('completed');
      body.parentElement.style.opacity = '0.75';
    }
  },

  dispatch(event) {
    const type = event.type || '';
    switch (type) {
      case 'subagent_start':
        Chat.finalizeStream();
        this.createSubagentCard(event.agent);
        break;
      case 'subagent_end':
        Chat.finalizeStream();
        this.closeCard();
        break;
      case 'think_start':
        Chat.finalizeStream();
        this.createThinkCard();
        break;
      case 'think_end':
        Chat.finalizeStream();
        this.closeCard();
        break;
      case 'stream':
        if (event.chunk) {
          if (!Chat.streamingMessageEl || Chat.streamingMessageEl.parentElement !== this.current()) {
            Chat.streamBuffer = '';
            Chat.streamingMessageEl = Chat.createStreamingMessage();
          }
          Chat.appendStreamChunk(event.chunk);
        }
        break;
      case 'tool_executing':
        Chat.renderToolCallInStream(event);
        break;
      case 'tool_executed':
        Chat.updateToolResult(event);
        break;
      case 'message_added':
        break;
      case 'status':
        break;
      case 'done':
        break;
      case 'error':
        Chat.handleStreamError(event);
        break;
      case 'cost':
      case 'warning':
      case 'retry':
      case 'iteration':
      case 'after_iteration':
      case 'llm_start':
      case 'llm_end':
      case 'file':
      case 'session_start':
      case 'session_end':
        break;
      default:
        console.warn('[Dispatcher] Unrecognized event type:', type);
    }
  },
};
