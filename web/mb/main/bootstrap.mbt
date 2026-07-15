///|
/// Generate the sidebar + view containers + mount points as an HTML
/// string. Called from `main()` before any rabbita cell mounts so that
/// `app.mount(id)` finds the target element.
fn bootstrap_html() -> String {
  let nav_items = [
    ("btn-mcp", "mcp", "sidebar.mcp", "sidebar.mcp_title", "128268", "page.mcp"),
    ("btn-channels", "channels", "sidebar.channels", "sidebar.channels", "128225", "page.channels"),
    ("btn-schedules", "schedules", "sidebar.schedules", "sidebar.schedules", "128339", "page.schedules"),
    ("btn-backups", "backups", "sidebar.backups", "sidebar.backups", "128190", "page.backups"),
    ("btn-billing", "billing", "sidebar.billing", "sidebar.billing", "128179", "page.billing"),
    ("btn-browser", "browser", "sidebar.browser", "sidebar.browser_title", "127760", "page.browser"),
    ("btn-git", "git", "sidebar.git", "sidebar.git_title", "128579", "page.git"),
    ("btn-trash", "trash", "sidebar.trash", "sidebar.trash", "128465", "page.trash"),
    ("btn-brand", "brand", "sidebar.brand", "sidebar.brand", "127912", "page.brand"),
    ("btn-profile", "profile", "sidebar.profile", "sidebar.profile", "128100", "page.profile"),
    ("btn-share", "share", "sidebar.share", "sidebar.share", "128279", "page.share"),
    ("btn-model-test", "model-test", "sidebar.models", "sidebar.models_title", "9881", "page.model_test"),
    ("btn-workspace", "workspace", "sidebar.workspace", "sidebar.workspace", "128193", "page.workspace"),
    ("btn-creator", "creator", "sidebar.creator", "sidebar.creator", "128221", "page.creator"),
    ("btn-version", "version", "sidebar.version", "sidebar.version", "128230", "page.version"),
    ("btn-onboard", "onboard", "sidebar.onboard", "sidebar.onboard", "128640", "page.onboard"),
    ("btn-tasks", "tasks", "sidebar.tasks", "sidebar.tasks_title", "9745", "page.tasks"),
    ("btn-media", "media", "sidebar.media", "sidebar.media_title", "127912", "page.media"),
    ("btn-marketplace", "marketplace", "sidebar.marketplace", "sidebar.marketplace_title", "128722", "page.marketplace"),
    ("btn-meeting", "meeting", "sidebar.meeting", "sidebar.meeting_title", "128249", "page.meeting"),
  ]

  let buf = StringBuilder::new()
  buf.write_string("<aside id=\"sidebar\" class=\"sidebar\">")
  buf.write_string("<div class=\"sidebar-header\">")
  buf.write_string("<h1 class=\"logo\"><span class=\"logo-icon\">&#9670;</span> MBOpenClacky</h1>")
  buf.write_string("<button id=\"btn-new-session\" class=\"btn btn-primary btn-sm\" title=\"New Session\" data-i18n-title=\"sidebar.new_title\">")
  buf.write_string("<span class=\"icon\">+</span> <span data-i18n=\"sidebar.new\">New</span>")
  buf.write_string("</button>")
  buf.write_string("</div>")
  buf.write_string("<div class=\"sidebar-search\">")
  buf.write_string("<input type=\"text\" id=\"session-search\" placeholder=\"Search sessions...\" data-i18n-placeholder=\"chat.search_sessions\" autocomplete=\"off\">")
  buf.write_string("</div>")
  buf.write_string("<div id=\"session-list\" class=\"session-list\"></div>")
  buf.write_string("<div class=\"sidebar-footer\">")
  buf.write_string("<button id=\"btn-settings\" class=\"btn btn-ghost\" title=\"Settings\" data-i18n-title=\"sidebar.settings\">")
  buf.write_string("<span class=\"icon\">&#9881;</span> <span data-i18n=\"sidebar.settings\">Settings</span>")
  buf.write_string("</button>")
  buf.write_string("<button id=\"btn-stats\" class=\"btn btn-ghost\" title=\"Stats\" data-i18n-title=\"sidebar.stats\">")
  buf.write_string("<span class=\"icon\">&#9783;</span> <span data-i18n=\"sidebar.stats\">Stats</span>")
  buf.write_string("</button>")
  buf.write_string("</div>")
  buf.write_string("<div class=\"sidebar-nav\">")
  for item in nav_items {
    let (id, view, label_key, title_key, icon, page_key) = item
    buf.write_string("<button id=\"")
    buf.write_string(id)
    buf.write_string("\" class=\"btn btn-ghost btn-nav\" title=\"")
    buf.write_string(title_key)
    buf.write_string("\" data-i18n-title=\"")
    buf.write_string(title_key)
    buf.write_string("\"><span class=\"icon\">&#")
    buf.write_string(icon)
    buf.write_string(";</span> <span data-i18n=\"")
    buf.write_string(label_key)
    buf.write_string("\">")
    buf.write_string(label_key)
    buf.write_string("</span></button>")
  }
  buf.write_string("</div>")
  buf.write_string("</aside>")
  buf.write_string("<button id=\"sidebar-toggle\" class=\"sidebar-toggle\" aria-label=\"Toggle sidebar\">&#9776;</button>")
  buf.write_string("<main id=\"main-content\" class=\"main-content\">")
  buf.write_string("<div id=\"view-chat\" class=\"view active\"></div>")
  for item in nav_items {
    let (_, view, _, _, _, page_key) = item
    let content_id = view + "-content"
    buf.write_string("<div id=\"view-")
    buf.write_string(view)
    buf.write_string("\" class=\"view\"><div class=\"panel-header\"><h2 data-i18n=\"")
    buf.write_string(page_key)
    buf.write_string("\">")
    buf.write_string(page_key)
    buf.write_string("</h2><button class=\"btn btn-ghost btn-sm btn-close-panel\" data-view=\"chat\">&#10005;</button></div><div id=\"")
    buf.write_string(content_id)
    buf.write_string("\" class=\"panel-body\"></div></div>")
  }
  buf.write_string("<div id=\"view-settings\" class=\"view\"><div class=\"panel-header\"><h2 data-i18n=\"page.settings\">Settings</h2><button class=\"btn btn-ghost btn-sm btn-close-panel\" data-view=\"chat\">&#10005;</button></div><div id=\"settings-content\" class=\"panel-body\"></div></div>")
  buf.write_string("<div id=\"view-skills\" class=\"view\"><div class=\"panel-header\"><h2 data-i18n=\"page.skills\">Skills</h2><button class=\"btn btn-ghost btn-sm btn-close-panel\" data-view=\"chat\">&#10005;</button></div><div id=\"skills-content\" class=\"panel-body\"></div></div>")
  buf.write_string("<div id=\"view-skills-enhanced\" class=\"view\"><div class=\"panel-header\"><h2 data-i18n=\"page.skills_mgr\">Skills Manager</h2><button class=\"btn btn-ghost btn-sm btn-close-panel\" data-view=\"chat\">&#10005;</button></div><div id=\"skills-enhanced-content\" class=\"panel-body\"></div></div>")
  buf.write_string("<div id=\"view-stats\" class=\"view\"><div class=\"panel-header\"><h2 data-i18n=\"page.stats\">Statistics</h2><button class=\"btn btn-ghost btn-sm btn-close-panel\" data-view=\"chat\">&#10005;</button></div><div id=\"stats-content\" class=\"panel-body\"></div></div>")
  buf.write_string("</main>")
  buf.write_string("<div id=\"mb-root\"></div>")
  buf.to_string()
}
