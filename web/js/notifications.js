// ═══════════════════════════════════════════════════════════════
// MBOpenClacky Web UI — Notification Manager
// ═══════════════════════════════════════════════════════════════

const NotificationManager = {
  notifications: [],
  nextId: 1,

  /** 初始化通知系统 */
  init() {
    this.container = document.getElementById('notifications-container')
      || document.getElementById('notifications');
    if (!this.container) {
      this.container = document.createElement('div');
      this.container.id = 'notifications-container';
      this.container.className = 'notifications';
      document.body.appendChild(this.container);
    }
  },

  /**
   * 显示通知
   * @param {string} message — 通知消息
   * @param {string} type — 类型: 'success'|'error'|'warning'|'info'
   * @returns {number} 通知 ID
   */
  notify(message, type = 'info') {
    const id = this.nextId++;
    const el = document.createElement('div');
    el.className = `notification ${type}`;
    el.dataset.id = id;

    const iconMap = {
      success: '&#10003;',
      error: '&#10007;',
      warning: '&#9888;',
      info: '&#8505;',
    };

    el.innerHTML = `
      <span class="notification-icon">${iconMap[type] || iconMap.info}</span>
      <span class="notification-message">${this._escapeHtml(message)}</span>
      <button class="notification-close" onclick="NotificationManager.dismiss(${id})" title="Close">&#10005;</button>`;

    this.container.appendChild(el);
    this.notifications.push({ id, el, type });

    // success/info 3秒自动消失, error/warning 需手动关闭
    if (type === 'success' || type === 'info') {
      setTimeout(() => this.dismiss(id), 3000);
    }

    return id;
  },

  /**
   * 关闭通知
   * @param {number} id — 通知 ID
   */
  dismiss(id) {
    const idx = this.notifications.findIndex(n => n.id === id);
    if (idx === -1) return;

    const { el } = this.notifications[idx];
    el.style.opacity = '0';
    el.style.transform = 'translateX(20px)';
    setTimeout(() => el.remove(), 300);
    this.notifications.splice(idx, 1);
  },

  /** 清空所有通知 */
  clearAll() {
    this.notifications.forEach(n => n.el.remove());
    this.notifications = [];
  },

  /** HTML 转义 */
  _escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  },
};

/** 通知视图渲染辅助 */
const NotificationView = {
  /** 渲染通知容器（如果需要动态插入） */
  renderNotifications() {
    let container = document.getElementById('notifications-container');
    if (!container) {
      container = document.createElement('div');
      container.id = 'notifications-container';
      container.className = 'notifications';
      document.body.appendChild(container);
    }
    return container;
  },
};
