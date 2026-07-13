// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — WebSocket & SSE Real-time Communication
// ═══════════════════════════════════════════════════════════════

const WS = {
  socket: null,
  reconnectAttempts: 0,
  maxReconnectAttempts: 5,
  reconnectDelay: 1000,
  sessionId: null,
  eventHandlers: {},

  /**
   * Connect WebSocket to a session
   */
  connect(sessionId) {
    this.disconnect();
    this.sessionId = sessionId;
    this.reconnectAttempts = 0;

    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const url = `${protocol}//${location.host}/ws/sessions/${sessionId}`;

    try {
      this.socket = new WebSocket(url);
      this.socket.onopen = () => this.onOpen();
      this.socket.onmessage = (event) => this.onMessage(event);
      this.socket.onclose = (event) => this.onClose(event);
      this.socket.onerror = (event) => this.onError(event);
    } catch (err) {
      console.warn('[WS] Connection failed:', err);
    }
  },

  /**
   * Disconnect WebSocket
   */
  disconnect() {
    if (this.socket) {
      this.socket.onclose = null; // prevent reconnect
      this.socket.close();
      this.socket = null;
    }
    this.sessionId = null;
  },

  /**
   * Handle connection opened
   */
  onOpen() {
    console.log('[WS] Connected to session:', this.sessionId);
    this.reconnectAttempts = 0;
    this.emit('connected', { sessionId: this.sessionId });
  },

  /**
   * Handle incoming message
   */
  onMessage(event) {
    try {
      const data = JSON.parse(event.data);
      this.handleEvent(data);
    } catch (e) {
      // May be SSE-formatted text from the server
      this.handleRawEvent(event.data);
    }
  },

  /**
   * Handle connection close with reconnect logic
   */
  onClose(event) {
    console.log('[WS] Disconnected:', event.code, event.reason);
    this.socket = null;

    if (this.sessionId && this.reconnectAttempts < this.maxReconnectAttempts) {
      this.reconnectAttempts++;
      const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1);
      console.log(`[WS] Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})`);
      setTimeout(() => {
        if (this.sessionId) {
          this.connect(this.sessionId);
        }
      }, delay);
    } else {
      this.emit('disconnected', { sessionId: this.sessionId });
    }
  },

  /**
   * Handle connection error
   */
  onError(event) {
    console.error('[WS] Error:', event);
  },

  /**
   * Dispatch parsed event to handlers
   */
  handleEvent(data) {
    const type = data.type || data.event || 'unknown';
    this.emit(type, data);

    // Route common events
    switch (type) {
      case 'connected':
        break;
      case 'done':
        this.emit('generation_complete', data);
        break;
      case 'error':
        this.emit('generation_error', data);
        break;
      case 'status':
        this.emit('status_update', data);
        break;
      case 'message_added':
        this.emit('new_message', data);
        break;
      case 'tool_executing':
      case 'tool_executed':
        this.emit('tool_event', data);
        break;
    }
  },

  /**
   * Handle raw SSE-like event text
   */
  handleRawEvent(text) {
    const lines = text.split('\n');
    let eventType = '';
    let eventData = '';

    for (const line of lines) {
      if (line.startsWith('event: ')) {
        eventType = line.slice(7).trim();
      } else if (line.startsWith('data: ')) {
        eventData = line.slice(6);
      }
    }

    if (eventType && eventData) {
      try {
        const parsed = JSON.parse(eventData);
        this.handleEvent({ type: eventType, ...parsed });
      } catch (e) {
        this.emit(eventType, { raw: eventData });
      }
    }
  },

  /**
   * Send message through WebSocket
   */
  send(data) {
    if (this.socket && this.socket.readyState === WebSocket.OPEN) {
      this.socket.send(typeof data === 'string' ? data : JSON.stringify(data));
      return true;
    }
    return false;
  },

  // ── SSE Streaming for Chat ──────────────────────────────────

  /**
   * Connect SSE for streaming chat response
   * Uses fetch + ReadableStream for POST-based SSE
   */
  async connectSSE(sessionId, messageText, onChunk, onDone, onError) {
    const url = `/api/sessions/${sessionId}/chat/stream`;

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: messageText }),
      });

      if (!response.ok) {
        const err = await response.json().catch(() => ({ error: 'Request failed' }));
        if (onError) onError(err);
        return null;
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';

      const read = async () => {
        while (true) {
          const { done, value } = await reader.read();
          if (done) {
            // Process remaining buffer
            if (buffer.trim()) {
              this.processSSEBuffer(buffer, onChunk);
            }
            if (onDone) onDone();
            break;
          }

          buffer += decoder.decode(value, { stream: true });
          // Process complete SSE events (separated by double newline)
          const parts = buffer.split('\n\n');
          buffer = parts.pop() || '';

          for (const part of parts) {
            if (part.trim()) {
              this.processSSEBuffer(part, onChunk);
            }
          }
        }
      };

      read().catch((err) => {
        if (err.name !== 'AbortError') {
          if (onError) onError(err);
        }
      });

      return reader;
    } catch (err) {
      if (onError) onError(err);
      return null;
    }
  },

  /**
   * Process a single SSE event buffer
   */
  processSSEBuffer(buffer, onChunk) {
    const lines = buffer.split('\n');
    let eventType = 'message';
    let data = '';

    for (const line of lines) {
      if (line.startsWith('event: ')) {
        eventType = line.slice(7).trim();
      } else if (line.startsWith('data: ')) {
        data += (data ? '\n' : '') + line.slice(6);
      } else if (line === 'data:') {
        data += '\n';
      }
    }

    if (data) {
      try {
        const parsed = JSON.parse(data);
        if (onChunk) onChunk({ type: eventType, ...parsed });
      } catch (e) {
        if (onChunk) onChunk({ type: eventType, raw: data });
      }
    }
  },

  // ── Event Emitter ───────────────────────────────────────────

  on(event, handler) {
    if (!this.eventHandlers[event]) {
      this.eventHandlers[event] = [];
    }
    this.eventHandlers[event].push(handler);
  },

  off(event, handler) {
    if (this.eventHandlers[event]) {
      this.eventHandlers[event] = this.eventHandlers[event].filter(h => h !== handler);
    }
  },

  emit(event, data) {
    if (this.eventHandlers[event]) {
      for (const handler of this.eventHandlers[event]) {
        try { handler(data); } catch (e) { console.error('[WS] Handler error:', e); }
      }
    }
  },
};
