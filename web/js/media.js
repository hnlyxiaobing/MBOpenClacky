// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Media Generation Panel
// ═══════════════════════════════════════════════════════════════

// ── MediaStore: 媒体生成状态管理 ───────────────────────────────
const MediaStore = {
  active_tab: 'image',
  generating: false,
  results: {},

  /** 图像生成 — POST /api/media/image */
  async generateImage(params) {
    this.generating = true;
    try {
      const data = await API.post('/api/media/image', params);
      this.results.image = data;
      return data;
    } catch (err) {
      console.error('[MediaStore] generateImage failed:', err);
      throw err;
    } finally {
      this.generating = false;
    }
  },

  /** 视频生成 — POST /api/media/video */
  async generateVideo(params) {
    this.generating = true;
    try {
      const data = await API.post('/api/media/video', params);
      this.results.video = data;
      return data;
    } catch (err) {
      console.error('[MediaStore] generateVideo failed:', err);
      throw err;
    } finally {
      this.generating = false;
    }
  },

  /** 语音合成 — POST /api/media/audio/speech */
  async generateSpeech(params) {
    this.generating = true;
    try {
      const data = await API.post('/api/media/audio/speech', params);
      this.results.speech = data;
      return data;
    } catch (err) {
      console.error('[MediaStore] generateSpeech failed:', err);
      throw err;
    } finally {
      this.generating = false;
    }
  },

  /** 音频转录 — POST /api/media/audio/transcriptions */
  async transcribe(params) {
    this.generating = true;
    try {
      const data = await API.post('/api/media/audio/transcriptions', params);
      this.results.transcription = data;
      return data;
    } catch (err) {
      console.error('[MediaStore] transcribe failed:', err);
      throw err;
    } finally {
      this.generating = false;
    }
  },
};

// ── MediaView: 媒体生成面板渲染 ────────────────────────────────
const MediaView = {
  init() {
    console.log('[MediaView] initialized');
  },

  async load() {
    this.renderMediaPanel();
  },

  renderMediaPanel() {
    const container = document.getElementById('media-content');
    if (!container) return;

    const tabs = [
      { key: 'image', label: I18n.t('media.tab_image'), icon: '&#127912;' },
      { key: 'video', label: I18n.t('media.tab_video'), icon: '&#127909;' },
      { key: 'speech', label: I18n.t('media.tab_speech'), icon: '&#128264;' },
      { key: 'transcription', label: I18n.t('media.tab_transcribe'), icon: '&#128221;' },
    ];

    const tabHtml = tabs.map(t =>
      `<button class="skills-tab ${MediaStore.active_tab === t.key ? 'active' : ''}" onclick="MediaView.switchTab('${t.key}')">${t.icon} ${t.label}</button>`
    ).join('');

    container.innerHTML = `
      <div class="skills-tabs" style="margin-bottom:16px">${tabHtml}</div>
      <div id="media-tab-body">${this._renderTabContent()}</div>`;
  },

  switchTab(tab) {
    MediaStore.active_tab = tab;
    this.renderMediaPanel();
  },

  _renderTabContent() {
    switch (MediaStore.active_tab) {
      case 'image': return this._renderImageForm();
      case 'video': return this._renderVideoForm();
      case 'speech': return this._renderSpeechForm();
      case 'transcription': return this._renderTranscribeForm();
      default: return '';
    }
  },

  _renderImageForm() {
    const result = MediaStore.results.image;
    return `
      <div class="settings-group">
        <div class="settings-group-title">${I18n.t('media.image_title')}</div>
        <div class="settings-field">
          <label for="media-image-prompt">${I18n.t('media.prompt')}</label>
          <textarea id="media-image-prompt" rows="3" placeholder="${I18n.t('media.image_placeholder')}"
            style="width:100%;padding:9px 12px;background:var(--bg-tertiary);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text-primary);font-size:13px;outline:none;resize:vertical;font-family:var(--font-sans)"></textarea>
        </div>
        <div style="display:flex;gap:8px;align-items:center">
          <div class="settings-field" style="flex:1">
            <label for="media-image-size">${I18n.t('media.size')}</label>
            <select id="media-image-size">
              <option value="1024x1024">1024 x 1024</option>
              <option value="512x512">512 x 512</option>
              <option value="1792x1024">1792 x 1024</option>
            </select>
          </div>
          <div class="settings-field" style="flex:1">
            <label for="media-image-quality">${I18n.t('media.quality')}</label>
            <select id="media-image-quality">
              <option value="standard">${I18n.t('media.quality_standard')}</option>
              <option value="hd">${I18n.t('media.quality_hd')}</option>
            </select>
          </div>
        </div>
        <button class="btn btn-primary" onclick="MediaView.handleGenerateImage()" ${MediaStore.generating ? 'disabled' : ''}>
          ${MediaStore.generating ? I18n.t('media.generating') : I18n.t('media.generate')}
        </button>
      </div>
      ${result ? this._renderResult('image', result) : ''}`;
  },

  _renderVideoForm() {
    const result = MediaStore.results.video;
    return `
      <div class="settings-group">
        <div class="settings-group-title">${I18n.t('media.video_title')}</div>
        <div class="settings-field">
          <label for="media-video-prompt">${I18n.t('media.prompt')}</label>
          <textarea id="media-video-prompt" rows="3" placeholder="${I18n.t('media.video_placeholder')}"
            style="width:100%;padding:9px 12px;background:var(--bg-tertiary);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text-primary);font-size:13px;outline:none;resize:vertical;font-family:var(--font-sans)"></textarea>
        </div>
        <div class="settings-field">
          <label for="media-video-duration">${I18n.t('media.duration')}</label>
          <input type="number" id="media-video-duration" value="5" min="1" max="60">
          <div class="help-text">${I18n.t('media.duration_help')}</div>
        </div>
        <button class="btn btn-primary" onclick="MediaView.handleGenerateVideo()" ${MediaStore.generating ? 'disabled' : ''}>
          ${MediaStore.generating ? I18n.t('media.generating') : I18n.t('media.generate')}
        </button>
      </div>
      ${result ? this._renderResult('video', result) : ''}`;
  },

  _renderSpeechForm() {
    const result = MediaStore.results.speech;
    return `
      <div class="settings-group">
        <div class="settings-group-title">${I18n.t('media.speech_title')}</div>
        <div class="settings-field">
          <label for="media-speech-text">${I18n.t('media.speech_text')}</label>
          <textarea id="media-speech-text" rows="4" placeholder="${I18n.t('media.speech_placeholder')}"
            style="width:100%;padding:9px 12px;background:var(--bg-tertiary);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text-primary);font-size:13px;outline:none;resize:vertical;font-family:var(--font-sans)"></textarea>
        </div>
        <div class="settings-field">
          <label for="media-speech-voice">${I18n.t('media.voice')}</label>
          <select id="media-speech-voice">
            <option value="alloy">Alloy</option>
            <option value="echo">Echo</option>
            <option value="fable">Fable</option>
            <option value="onyx">Onyx</option>
            <option value="nova">Nova</option>
            <option value="shimmer">Shimmer</option>
          </select>
        </div>
        <button class="btn btn-primary" onclick="MediaView.handleGenerateSpeech()" ${MediaStore.generating ? 'disabled' : ''}>
          ${MediaStore.generating ? I18n.t('media.generating') : I18n.t('media.generate_speech')}
        </button>
      </div>
      ${result ? this._renderResult('speech', result) : ''}`;
  },

  _renderTranscribeForm() {
    const result = MediaStore.results.transcription;
    return `
      <div class="settings-group">
        <div class="settings-group-title">${I18n.t('media.transcribe_title')}</div>
        <div class="settings-field">
          <label for="media-transcribe-file">${I18n.t('media.audio_file')}</label>
          <input type="file" id="media-transcribe-file" accept="audio/*" style="padding:8px;background:var(--bg-tertiary);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text-primary);font-size:13px">
          <div class="help-text">${I18n.t('media.audio_file_help')}</div>
        </div>
        <button class="btn btn-primary" onclick="MediaView.handleTranscribe()" ${MediaStore.generating ? 'disabled' : ''}>
          ${MediaStore.generating ? I18n.t('media.generating') : I18n.t('media.transcribe_btn')}
        </button>
      </div>
      ${result ? this._renderResult('transcription', result) : ''}`;
  },

  _renderResult(type, result) {
    if (result.message && !result.ok) {
      return `<div class="settings-group">
        <div class="settings-group-title">${I18n.t('media.result')}</div>
        <div style="padding:16px;text-align:center;color:var(--text-muted)">
          <div style="font-size:24px;margin-bottom:8px">&#128679;</div>
          <p>${this._esc(result.message || I18n.t('media.coming_soon'))}</p>
        </div>
      </div>`;
    }
    const content = typeof result === 'string' ? result : JSON.stringify(result, null, 2);
    return `<div class="settings-group">
      <div class="settings-group-title">${I18n.t('media.result')}</div>
      <pre style="background:var(--bg-tertiary);padding:12px;border-radius:var(--radius-sm);font-size:12px;font-family:var(--font-mono);overflow-x:auto;white-space:pre-wrap;max-height:300px">${this._esc(content)}</pre>
    </div>`;
  },

  async handleGenerateImage() {
    const prompt = document.getElementById('media-image-prompt')?.value.trim();
    if (!prompt) { App.showNotification(I18n.t('media.prompt_required'), 'warning'); return; }
    const size = document.getElementById('media-image-size')?.value || '1024x1024';
    const quality = document.getElementById('media-image-quality')?.value || 'standard';
    try {
      await MediaStore.generateImage({ prompt, size, quality });
      this.renderMediaPanel();
    } catch (err) {
      App.showNotification(err.message, 'error');
      this.renderMediaPanel();
    }
  },

  async handleGenerateVideo() {
    const prompt = document.getElementById('media-video-prompt')?.value.trim();
    if (!prompt) { App.showNotification(I18n.t('media.prompt_required'), 'warning'); return; }
    const duration = parseInt(document.getElementById('media-video-duration')?.value) || 5;
    try {
      await MediaStore.generateVideo({ prompt, duration });
      this.renderMediaPanel();
    } catch (err) {
      App.showNotification(err.message, 'error');
      this.renderMediaPanel();
    }
  },

  async handleGenerateSpeech() {
    const text = document.getElementById('media-speech-text')?.value.trim();
    if (!text) { App.showNotification(I18n.t('media.text_required'), 'warning'); return; }
    const voice = document.getElementById('media-speech-voice')?.value || 'alloy';
    try {
      await MediaStore.generateSpeech({ input: text, voice });
      this.renderMediaPanel();
    } catch (err) {
      App.showNotification(err.message, 'error');
      this.renderMediaPanel();
    }
  },

  async handleTranscribe() {
    const fileInput = document.getElementById('media-transcribe-file');
    if (!fileInput || !fileInput.files.length) { App.showNotification(I18n.t('media.file_required'), 'warning'); return; }
    App.showNotification(I18n.t('media.coming_soon'), 'info');
  },

  _esc(text) {
    const div = document.createElement('div');
    div.textContent = text || '';
    return div.innerHTML;
  },
};
