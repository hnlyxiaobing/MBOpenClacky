/**
 * MBOpenClacky i18n Framework
 * Lightweight internationalization with dictionary lookup and DOM translation.
 */
const I18n = {
  currentLocale: 'en',
  dictionaries: {},

  /**
   * Initialize i18n: detect locale, load dictionaries.
   */
  init() {
    // Try to load saved preference
    const saved = localStorage.getItem('mbopenclacky_locale');
    if (saved && (saved === 'en' || saved === 'zh')) {
      this.currentLocale = saved;
    } else {
      // Detect from browser
      const lang = (navigator.language || navigator.userLanguage || 'en').toLowerCase();
      this.currentLocale = lang.startsWith('zh') ? 'zh' : 'en';
    }
    // Register dictionaries (loaded by locale files)
    if (typeof I18nEn !== 'undefined') this.dictionaries['en'] = I18nEn;
    if (typeof I18nZh !== 'undefined') this.dictionaries['zh'] = I18nZh;
    // Apply translations to static DOM
    this.translateDOM();
  },

  /**
   * Translate a key with optional parameter substitution.
   * @param {string} key - Translation key (e.g., 'sidebar.settings')
   * @param {Object} params - Optional params: name -> value
   * @returns {string} Translated text, or key if not found
   */
  t(key, params) {
    const dict = this.dictionaries[this.currentLocale] || this.dictionaries['en'] || {};
    const fallback = this.dictionaries['en'] || {};
    let text = dict[key] || fallback[key] || key;
    if (params) {
      Object.entries(params).forEach(([k, v]) => {
        text = text.replace(new RegExp(`\\{\\{${k}\\}\\}`, 'g'), String(v));
      });
    }
    return text;
  },

  /**
   * Switch locale and re-render all translated elements.
   */
  setLocale(locale) {
    if (!this.dictionaries[locale]) return;
    this.currentLocale = locale;
    localStorage.setItem('mbopenclacky_locale', locale);
    this.translateDOM();
    // Dispatch event for modules to listen
    window.dispatchEvent(new CustomEvent('i18n:locale-changed', { detail: { locale } }));
  },

  /**
   * Get current locale.
   */
  getLocale() {
    return this.currentLocale;
  },

  /**
   * Translate all DOM elements with data-i18n and data-i18n-placeholder attributes.
   */
  translateDOM() {
    document.querySelectorAll('[data-i18n]').forEach(el => {
      const key = el.getAttribute('data-i18n');
      if (key) el.textContent = this.t(key);
    });
    document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
      const key = el.getAttribute('data-i18n-placeholder');
      if (key) el.placeholder = this.t(key);
    });
    document.querySelectorAll('[data-i18n-title]').forEach(el => {
      const key = el.getAttribute('data-i18n-title');
      if (key) el.title = this.t(key);
    });
    // Update html lang attribute
    document.documentElement.lang = this.currentLocale;
  }
};
