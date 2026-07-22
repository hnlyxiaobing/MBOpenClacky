/**
 * MBOpenClacky Web UI — skeleton bootstrap script.
 * P0 scope: theme toggle, i18n base, session list probe, sidebar toggle.
 * Interaction (chat, WS) is P1+.
 */
(function () {
  "use strict";

  // ── Theme ──────────────────────────────────────────────────────
  var THEME_KEY = "clacky-theme";
  function applyTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme);
  }
  function initTheme() {
    var saved = localStorage.getItem(THEME_KEY);
    applyTheme(saved === "light" || saved === "dark" ? saved : "dark");
  }
  initTheme();

  var themeBtn = document.getElementById("theme-toggle");
  if (themeBtn) {
    themeBtn.addEventListener("click", function () {
      var current = document.documentElement.getAttribute("data-theme");
      var next = current === "dark" ? "light" : "dark";
      localStorage.setItem(THEME_KEY, next);
      applyTheme(next);
    });
  }

  // ── i18n (minimal: data-i18n attribute replacement) ────────────
  var LANG_KEY = "clacky-lang";
  var STRINGS = {
    zh: {
      "New Session": "新会话",
      "Search...": "搜索...",
      "Type a message...": "输入消息...",
      "Send": "发送",
      "No sessions yet": "暂无会话",
      "AI Agent CLI — Web Interface": "AI Agent CLI — Web 界面",
      "Toggle sidebar": "切换侧栏",
      "Toggle theme": "切换主题",
      "Share": "分享",
    },
    en: {},
  };

  function applyI18n() {
    var lang = localStorage.getItem(LANG_KEY) || "en";
    if (lang === "en") return; // English is the base language
    var dict = STRINGS[lang] || {};
    document.querySelectorAll("[data-i18n]").forEach(function (el) {
      var key = el.getAttribute("data-i18n");
      if (dict[key]) el.textContent = dict[key];
    });
    // Also translate placeholder attributes
    var searchInput = document.getElementById("search-input");
    if (searchInput && dict["Search..."]) searchInput.placeholder = dict["Search..."];
    var msgInput = document.getElementById("message-input");
    if (msgInput && dict["Type a message..."]) msgInput.placeholder = dict["Type a message..."];
    // Translate static text nodes
    document.querySelectorAll("#new-session-btn").forEach(function (el) {
      if (dict["New Session"]) el.textContent = "+ " + dict["New Session"];
    });
    document.querySelectorAll(".empty-msg").forEach(function (el) {
      if (dict["No sessions yet"]) el.textContent = dict["No sessions yet"];
    });
    document.querySelectorAll(".welcome-screen p").forEach(function (el) {
      if (dict["AI Agent CLI — Web Interface"]) el.textContent = dict["AI Agent CLI — Web Interface"];
    });
  }
  applyI18n();

  // ── Sidebar toggle ─────────────────────────────────────────────
  var sidebarToggle = document.getElementById("sidebar-toggle");
  var sidebar = document.getElementById("sidebar");
  if (sidebarToggle && sidebar) {
    sidebarToggle.addEventListener("click", function () {
      sidebar.classList.toggle("open");
    });
  }

  // ── Auth probe & session list (mirrors openclacky auth.js) ─────
  function fetchSessions() {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", "/api/sessions?limit=20", true);
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== 4) return;
      if (xhr.status === 200) {
        try {
          var data = JSON.parse(xhr.responseText);
          renderSessionList(data.sessions || []);
        } catch (_) {
          // parse error — leave empty state
        }
      }
      // 401 / 404 / other: leave empty state (P1+ handles auth dialog)
    };
    xhr.send();
  }

  function renderSessionList(sessions) {
    var list = document.getElementById("session-list");
    if (!list) return;
    if (!sessions || sessions.length === 0) return; // keep "No sessions yet"
    list.innerHTML = "";
    sessions.forEach(function (s) {
      var li = document.createElement("li");
      li.className = "session-item";
      li.textContent = s.name || s.id || "Untitled";
      li.setAttribute("data-session-id", s.id || "");
      list.appendChild(li);
    });
  }

  // Kick off session probe once DOM is ready
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", fetchSessions);
  } else {
    fetchSessions();
  }
})();
