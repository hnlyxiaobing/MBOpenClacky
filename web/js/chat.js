// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Chat Module
// ═══════════════════════════════════════════════════════════════

const Chat = {
  messages: [],
  isStreaming: false,
  currentReader: null,
  streamingMessageEl: null,
  streamBuffer: '',
  _renderTimeout: null,

  /**
   * Initialize chat module
   */
  init() {
    const input = document.getElementById('chat-input');
    const sendBtn = document.getElementById('btn-send');
    const cancelBtn = document.getElementById('btn-cancel');

    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        this.handleSend();
      }
    });

    input.addEventListener('input', () => {
      this.autoResize(input);
      sendBtn.disabled = !input.value.trim() || this.isStreaming;
    });

    sendBtn.addEventListener('click', () => this.handleSend());
    cancelBtn.addEventListener('click', () => this.cancelGeneration());

    // Tool and cost buttons
    document.getElementById('btn-chat-tools').addEventListener('click', () => this.showTools());
    document.getElementById('btn-chat-cost').addEventListener('click', () => this.showCost());
  },

  /**
   * Handle send action
   */
  handleSend() {
    const input = document.getElementById('chat-input');
    const text = input.value.trim();
    if (!text || this.isStreaming || !App.currentSessionId) return;

    input.value = '';
    this.autoResize(input);
    document.getElementById('btn-send').disabled = true;

    this.sendMessage(text);
  },

  /**
   * Send message via SSE streaming
   */
  async sendMessage(text) {
    if (!App.currentSessionId) {
      App.showNotification(I18n.t('chat.no_active'), 'warning');
      return;
    }

    // Render user message
    this.addMessage({ role: 'user', content: text, timestamp: new Date().toISOString() });

    // Start streaming state
    this.setStreaming(true);

    // Create placeholder for assistant response
    this.streamBuffer = '';
    this.streamingMessageEl = this.createStreamingMessage();

    // Connect SSE
    this.currentReader = await WS.connectSSE(
      App.currentSessionId,
      text,
      (chunk) => this.handleStreamChunk(chunk),
      () => this.handleStreamDone(),
      (err) => this.handleStreamError(err)
    );
  },

  /**
   * Handle incoming SSE chunk
   */
  handleStreamChunk(chunk) {
    const type = chunk.type || '';

    switch (type) {
      case 'content_delta':
      case 'text_delta':
        if (chunk.content || chunk.text || chunk.delta) {
          this.appendStreamChunk(chunk.content || chunk.text || chunk.delta);
        }
        break;
      case 'tool_use_start':
      case 'tool_executing':
        this.renderToolCallInStream(chunk);
        break;
      case 'tool_result':
        this.updateToolResult(chunk);
        break;
      case 'message_complete':
      case 'assistant_message':
        if (chunk.content) {
          this.streamBuffer = chunk.content;
          this.updateStreamingMessage();
        }
        break;
      case 'error':
        this.handleStreamError(chunk);
        break;
      default:
        // Try to extract text content from any event
        if (chunk.content && typeof chunk.content === 'string') {
          this.appendStreamChunk(chunk.content);
        } else if (chunk.raw && typeof chunk.raw === 'string') {
          this.appendStreamChunk(chunk.raw);
        }
    }
  },

  /**
   * Append text chunk to streaming message (debounced rendering)
   */
  appendStreamChunk(text) {
    this.streamBuffer += text;
    // Debounce rendering at 150ms during streaming to reduce layout thrash
    if (this._renderTimeout) clearTimeout(this._renderTimeout);
    this._renderTimeout = setTimeout(() => {
      this.updateStreamingMessage();
      this.scrollToBottom();
    }, 150);
  },

  /**
   * Update the streaming message element with current buffer
   */
  updateStreamingMessage() {
    if (this.streamingMessageEl) {
      const contentEl = this.streamingMessageEl.querySelector('.message-text');
      if (contentEl) {
        contentEl.innerHTML = this.renderMarkdown(this.streamBuffer);
      }
    }
  },

  /**
   * Handle stream completion
   */
  handleStreamDone() {
    // Clear any pending debounced render
    if (this._renderTimeout) {
      clearTimeout(this._renderTimeout);
      this._renderTimeout = null;
    }

    // Do a final render with full content
    if (this.streamingMessageEl) {
      const contentEl = this.streamingMessageEl.querySelector('.message-text');
      if (contentEl && this.streamBuffer) {
        contentEl.innerHTML = this.renderMarkdown(this.streamBuffer);
      }
    }

    // Finalize the message
    if (this.streamBuffer) {
      this.messages.push({
        role: 'assistant',
        content: this.streamBuffer,
        timestamp: new Date().toISOString(),
      });
    }

    // Remove loading indicator
    if (this.streamingMessageEl) {
      const loader = this.streamingMessageEl.querySelector('.loading-dots');
      if (loader) loader.remove();
    }

    this.setStreaming(false);
    this.streamingMessageEl = null;
    this.scrollToBottom();
  },

  /**
   * Handle stream error
   */
  handleStreamError(err) {
    const message = err?.error || err?.message || 'Stream connection failed';
    App.showNotification(message, 'error');
    this.setStreaming(false);

    if (this.streamingMessageEl) {
      const contentEl = this.streamingMessageEl.querySelector('.message-text');
      if (contentEl && !this.streamBuffer) {
        contentEl.innerHTML = `<span style="color:var(--danger)">Error: ${this.escapeHtml(message)}</span>`;
      }
      const loader = this.streamingMessageEl.querySelector('.loading-dots');
      if (loader) loader.remove();
    }

    this.streamingMessageEl = null;
  },

  /**
   * Cancel current generation
   */
  async cancelGeneration() {
    if (!App.currentSessionId) return;

    try {
      await fetch(`/api/sessions/${App.currentSessionId}/cancel`, { method: 'POST' });
      this.setStreaming(false);
      App.showNotification(I18n.t('chat.cancelled'), 'info');
    } catch (err) {
      console.error('[Chat] Cancel failed:', err);
    }
  },

  /**
   * Set streaming state (toggle UI elements)
   */
  setStreaming(streaming) {
    this.isStreaming = streaming;
    const sendBtn = document.getElementById('btn-send');
    const cancelBtn = document.getElementById('btn-cancel');
    const input = document.getElementById('chat-input');
    const statusBadge = document.getElementById('chat-session-status');

    if (streaming) {
      sendBtn.classList.add('hidden');
      cancelBtn.classList.remove('hidden');
      input.disabled = true;
      statusBadge.textContent = I18n.t('chat.running');
      statusBadge.className = 'status-badge running';
    } else {
      sendBtn.classList.remove('hidden');
      cancelBtn.classList.add('hidden');
      input.disabled = false;
      input.focus();
      sendBtn.disabled = !input.value.trim();
      statusBadge.textContent = I18n.t('chat.idle');
      statusBadge.className = 'status-badge';
    }
  },

  /**
   * Load chat history for a session
   */
  async loadHistory(sessionId) {
    try {
      const res = await fetch(`/api/sessions/${sessionId}`);
      if (!res.ok) return;

      const data = await res.json();
      this.messages = data.messages || [];
      this.renderAllMessages();

      // Update header info
      document.getElementById('chat-session-name').textContent = data.name || sessionId;
    } catch (err) {
      console.error('[Chat] Failed to load history:', err);
    }
  },

  /**
   * Render all messages
   */
  renderAllMessages() {
    const container = document.getElementById('chat-messages');
    container.innerHTML = '';

    if (this.messages.length === 0) {
      container.innerHTML = `
        <div class="empty-state">
          <div class="empty-state-icon">&#128172;</div>
          <h3>${I18n.t('chat.start_convo')}</h3>
          <p>${I18n.t('chat.start_desc')}</p>
        </div>`;
      return;
    }

    for (const msg of this.messages) {
      if (msg.role === 'user' || msg.role === 'assistant') {
        this.renderMessage(msg, container);
      }
    }
    this.scrollToBottom();
  },

  /**
   * Add and render a new message
   */
  addMessage(msg) {
    this.messages.push(msg);
    const container = document.getElementById('chat-messages');

    // Remove empty state if present
    const emptyState = container.querySelector('.empty-state');
    if (emptyState) emptyState.remove();

    this.renderMessage(msg, container);
    this.scrollToBottom();
  },

  /**
   * Render a single message element
   */
  renderMessage(msg, container) {
    const el = document.createElement('div');
    el.className = `message ${msg.role}`;

    const avatar = msg.role === 'user' ? '&#9786;' : '&#9670;';
    const content = msg.role === 'user'
      ? this.escapeHtml(msg.content)
      : this.renderMarkdown(msg.content || '');

    const time = msg.timestamp ? this.formatTime(msg.timestamp) : '';

    el.innerHTML = `
      <div class="message-avatar">${avatar}</div>
      <div class="message-bubble">
        <div class="message-content">
          <div class="message-text">${content}</div>
        </div>
        ${time ? `<div class="message-timestamp">${time}</div>` : ''}
      </div>`;

    container.appendChild(el);
    return el;
  },

  /**
   * Create streaming message placeholder
   */
  createStreamingMessage() {
    const container = document.getElementById('chat-messages');
    const emptyState = container.querySelector('.empty-state');
    if (emptyState) emptyState.remove();

    const el = document.createElement('div');
    el.className = 'message assistant';
    el.innerHTML = `
      <div class="message-avatar">&#9670;</div>
      <div class="message-bubble">
        <div class="message-content">
          <div class="message-text"></div>
          <div class="loading-dots"><span></span><span></span><span></span></div>
        </div>
      </div>`;

    container.appendChild(el);
    this.scrollToBottom();
    return el;
  },

  /**
   * Render tool call in streaming message
   */
  renderToolCallInStream(toolCall) {
    if (!this.streamingMessageEl) return;
    const bubble = this.streamingMessageEl.querySelector('.message-content');

    const panel = document.createElement('div');
    panel.className = 'tool-call';
    panel.dataset.toolId = toolCall.id || '';
    panel.innerHTML = `
      <div class="tool-call-header" onclick="this.parentElement.classList.toggle('expanded')">
        <span class="tool-call-icon">&#9881;</span>
        <span class="tool-call-name">${this.escapeHtml(toolCall.name || toolCall.tool_name || 'Tool')}</span>
        <span class="tool-call-toggle">&#9654;</span>
      </div>
      <div class="tool-call-body">${this.escapeHtml(JSON.stringify(toolCall.input || toolCall.arguments || {}, null, 2))}</div>`;

    bubble.insertBefore(panel, bubble.querySelector('.loading-dots'));
  },

  /**
   * Update tool result panel
   */
  updateToolResult(result) {
    if (!this.streamingMessageEl) return;
    const toolId = result.tool_use_id || result.id || '';
    const panel = this.streamingMessageEl.querySelector(`[data-tool-id="${toolId}"]`);
    if (panel) {
      const body = panel.querySelector('.tool-call-body');
      if (body) {
        body.textContent += '\n\n--- Result ---\n' + (result.content || result.output || JSON.stringify(result));
      }
    }
  },

  /**
   * Show tools modal
   */
  async showTools() {
    if (!App.currentSessionId) return;
    try {
      const res = await fetch(`/api/sessions/${App.currentSessionId}/tools`);
      const data = await res.json();
      const tools = data.tools || [];

      const html = tools.length === 0
        ? `<p class="text-muted">${I18n.t('chat.no_tools')}</p>`
        : tools.map(t => `
            <div class="tool-call" style="margin-bottom:8px">
              <div class="tool-call-header" onclick="this.parentElement.classList.toggle('expanded')">
                <span class="tool-call-icon">&#9881;</span>
                <span class="tool-call-name">${this.escapeHtml(t.name)}</span>
                <span class="tool-call-toggle">&#9654;</span>
              </div>
              <div class="tool-call-body">${this.escapeHtml(t.description || I18n.t('chat.no_desc'))}</div>
            </div>`).join('');

      App.showModal(I18n.t('chat.tools'), html);
    } catch (err) {
      App.showNotification(I18n.t('chat.failed_tools'), 'error');
    }
  },

  /**
   * Show cost info modal
   */
  async showCost() {
    if (!App.currentSessionId) return;
    try {
      const res = await fetch(`/api/sessions/${App.currentSessionId}/cost`);
      const data = await res.json();
      const html = `
        <div class="stats-grid">
          <div class="stat-card">
            <div class="stat-card-value">$${(data.total_cost_usd || 0).toFixed(4)}</div>
            <div class="stat-card-label">${I18n.t('chat.total_cost')}</div>
          </div>
          <div class="stat-card">
            <div class="stat-card-value">${data.total_requests || 0}</div>
            <div class="stat-card-label">${I18n.t('chat.total_requests')}</div>
          </div>
          <div class="stat-card">
            <div class="stat-card-value">${data.cache_hit_requests || 0}</div>
            <div class="stat-card-label">${I18n.t('chat.cache_hits')}</div>
          </div>
        </div>`;
      App.showModal(I18n.t('chat.cost_info'), html);
    } catch (err) {
      App.showNotification(I18n.t('chat.failed_cost'), 'error');
    }
  },

  // ── Markdown Rendering ──────────────────────────────────────

  /**
   * Enhanced Markdown to HTML renderer using marked.js + highlight.js
   * Falls back to regex-based rendering if libraries are not available
   */
  renderMarkdown(text) {
    if (!text) return '';

    // Use marked.js if available
    if (typeof marked !== 'undefined') {
      // Configure marked with highlight.js support
      marked.setOptions({
        breaks: true,
        gfm: true,
        highlight: function(code, lang) {
          if (typeof hljs !== 'undefined') {
            if (lang && hljs.getLanguage(lang)) {
              try {
                return hljs.highlight(code, { language: lang }).value;
              } catch (e) { /* ignore */ }
            }
            try {
              return hljs.highlightAuto(code).value;
            } catch (e) { /* ignore */ }
          }
          return code;
        }
      });

      let html = marked.parse(text);

      // Add copy buttons and language labels to code blocks
      html = html.replace(/<pre><code(?:\s+class="language-(\w+)")?>([^]*)<\/code><\/pre>/g,
        (match, lang, code) => {
          const langLabel = lang || 'code';
          return `<div class="code-block-header"><span>${langLabel}</span><button class="btn-copy-code" onclick="Chat.copyCode(this)">${I18n.t('chat.copy')}</button></div><pre><code class="${lang ? 'language-' + lang : ''}">${code}</code></pre>`;
        });

      // KaTeX math rendering: $$...$$ for display, $...$ for inline
      if (typeof katex !== 'undefined') {
        html = html.replace(/\$\$([\s\S]+?)\$\$/g, (_, tex) => {
          try { return katex.renderToString(tex.trim(), { displayMode: true, throwOnError: false }); }
          catch (e) { return `<span style="color:var(--danger)">${this.escapeHtml(tex)}</span>`; }
        });
        html = html.replace(/\$([^$\n]+?)\$/g, (_, tex) => {
          try { return katex.renderToString(tex.trim(), { displayMode: false, throwOnError: false }); }
          catch (e) { return `<code>${this.escapeHtml(tex)}</code>`; }
        });
      }

      return html;
    }

    // ── Fallback: regex-based rendering ──
    let html = this.escapeHtml(text);

    // Code blocks (```) — must be before inline code
    html = html.replace(/```(\w*)\n([\s\S]*?)```/g, (_, lang, code) => {
      const langLabel = lang || 'code';
      return `<div class="code-block-header"><span>${langLabel}</span><button class="btn-copy-code" onclick="Chat.copyCode(this)">${I18n.t('chat.copy')}</button></div><pre><code>${code}</code></pre>`;
    });

    // Inline code
    html = html.replace(/`([^`]+)`/g, '<code>$1</code>');

    // Headers
    html = html.replace(/^######\s+(.+)$/gm, '<h6>$1</h6>');
    html = html.replace(/^#####\s+(.+)$/gm, '<h5>$1</h5>');
    html = html.replace(/^####\s+(.+)$/gm, '<h4>$1</h4>');
    html = html.replace(/^###\s+(.+)$/gm, '<h3>$1</h3>');
    html = html.replace(/^##\s+(.+)$/gm, '<h2>$1</h2>');
    html = html.replace(/^#\s+(.+)$/gm, '<h1>$1</h1>');

    // Bold & Italic
    html = html.replace(/\*\*\*(.+?)\*\*\*/g, '<strong><em>$1</em></strong>');
    html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
    html = html.replace(/\*(.+?)\*/g, '<em>$1</em>');

    // Links
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');

    // Blockquotes
    html = html.replace(/^&gt;\s+(.+)$/gm, '<blockquote>$1</blockquote>');

    // Unordered lists
    html = html.replace(/^[\s]*[-*]\s+(.+)$/gm, '<li>$1</li>');
    html = html.replace(/(<li>.*<\/li>)/s, '<ul>$1</ul>');

    // Ordered lists
    html = html.replace(/^\d+\.\s+(.+)$/gm, '<li>$1</li>');

    // Line breaks (double newline = paragraph)
    html = html.replace(/\n\n/g, '</p><p>');
    html = html.replace(/\n/g, '<br>');

    // Wrap in paragraph if needed
    if (!html.startsWith('<')) {
      html = '<p>' + html + '</p>';
    }

    return html;
  },

  /**
   * Copy code block content
   */
  copyCode(btn) {
    const codeBlock = btn.closest('.code-block-header')?.nextElementSibling?.querySelector('code');
    if (codeBlock) {
      navigator.clipboard.writeText(codeBlock.textContent).then(() => {
        btn.textContent = I18n.t('chat.copied');
        btn.classList.add('copied');
        setTimeout(() => {
          btn.textContent = I18n.t('chat.copy');
          btn.classList.remove('copied');
        }, 2000);
      });
    }
  },

  // ── Utilities ───────────────────────────────────────────────

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  },

  formatTime(isoString) {
    try {
      const d = new Date(isoString);
      return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } catch {
      return '';
    }
  },

  autoResize(textarea) {
    textarea.style.height = 'auto';
    textarea.style.height = Math.min(textarea.scrollHeight, 150) + 'px';
  },

  scrollToBottom() {
    const container = document.getElementById('chat-messages');
    requestAnimationFrame(() => {
      container.scrollTop = container.scrollHeight;
    });
  },

  /**
   * Clear chat display
   */
  clear() {
    this.messages = [];
    this.streamBuffer = '';
    this.streamingMessageEl = null;
    this.isStreaming = false;
    document.getElementById('chat-messages').innerHTML = `
      <div class="empty-state">
        <div class="empty-state-icon">&#128172;</div>
        <h3>${I18n.t('chat.no_conversation')}</h3>
        <p>${I18n.t('chat.empty_desc')}</p>
      </div>`;
    this.setStreaming(false);
  },
};

// Global copyCode function for code blocks rendered by marked.js
function copyCode(btn) {
  const code = btn.nextElementSibling;
  if (code) {
    const text = code.textContent;
    navigator.clipboard.writeText(text).then(() => {
      btn.textContent = '✓';
      setTimeout(() => { btn.textContent = '📋'; }, 2000);
    });
  }
}
