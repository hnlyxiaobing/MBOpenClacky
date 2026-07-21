///|
using @rabbita {new, cell_with_emit}

///|
fn main {

  // ── Bootstrap: generate sidebar + view containers before any mount ─
  js_set_inner_html("app", bootstrap_html())

  // ── Brand cell at #brand-content (Phase 1.1) ────────────────────
  let (emit, brand_cell) = build_brand_cell()
  let app = new(brand_cell)
  app.with_init(emit(Init))
  app.mount("brand-content")

  // ── Backups cell at #backups-content (Phase 2.1) ─────────────────
  let (backups_emit, backups_cell) = build_backups_cell()
  let backups_app = new(backups_cell)
  backups_app.with_init(backups_emit(Init))
  backups_app.mount("backups-content")

  // ── Version cell at #version-content (Phase 2.2) ─────────────────
  let (version_emit, version_cell) = build_version_cell()
  let version_app = new(version_cell)
  version_app.with_init(version_emit(Init))
  version_app.mount("version-content")

  // ── Profile cell at #profile-content (Phase 2.3) ─────────────────
  let (profile_emit, profile_cell) = build_profile_cell()
  let profile_app = new(profile_cell)
  profile_app.with_init(profile_emit(Init))
  profile_app.mount("profile-content")

  // ── Share cell at #share-content (Phase 2.4) ────────────────────
  let (share_emit, share_cell) = build_share_cell()
  let share_app = new(share_cell)
  share_app.with_init(share_emit(Init))
  share_app.mount("share-content")

  // ── Trash cell at #trash-content (Phase 2.5) ────────────────────
  let (trash_emit, trash_cell) = build_trash_cell()
  let trash_app = new(trash_cell)
  trash_app.with_init(trash_emit(Init))
  trash_app.mount("trash-content")

  // ── ModelTest cell at #model-test-content (Phase 2.6) ───────────
  let (model_test_emit, model_test_cell) = build_model_test_cell()
  let model_test_app = new(model_test_cell)
  model_test_app.with_init(model_test_emit(Init))
  model_test_app.mount("model-test-content")

  // ── Tasks cell at #tasks-content (Phase 2.7) ────────────────────
  let (tasks_emit, tasks_cell) = build_tasks_cell()
  let tasks_app = new(tasks_cell)
  tasks_app.with_init(tasks_emit(Init))
  tasks_app.mount("tasks-content")

  // ── Browser cell at #browser-content (Phase 2.8) ─────────────────
  let (browser_emit, browser_cell) = build_browser_cell()
  let browser_app = new(browser_cell)
  browser_app.with_init(browser_emit(Init))
  browser_app.mount("browser-content")

  // ── Meeting cell at #meeting-content (Phase 3.1) ────────────────
  let (meeting_emit, meeting_cell) = build_meeting_cell()
  let meeting_app = new(meeting_cell)
  meeting_app.with_init(meeting_emit(Init))
  meeting_app.mount("meeting-content")

  // ── Marketplace cell at #marketplace-content (Phase 3.1) ───────
  let (marketplace_emit, marketplace_cell) = build_marketplace_cell()
  let marketplace_app = new(marketplace_cell)
  marketplace_app.with_init(marketplace_emit(Init))
  marketplace_app.mount("marketplace-content")

  // ── Workspace cell at #workspace-content (Phase 3.1) ───────────
  let (workspace_emit, workspace_cell) = build_workspace_cell()
  let workspace_app = new(workspace_cell)
  workspace_app.with_init(workspace_emit(Init))
  workspace_app.mount("workspace-content")

  // ── Schedules cell at #schedules-content (Phase 3.2) ───────────
  let (schedules_emit, schedules_cell) = build_schedules_cell()
  let schedules_app = new(schedules_cell)
  schedules_app.with_init(schedules_emit(Init))
  schedules_app.mount("schedules-content")

  // ── Billing cell at #billing-content (Phase 3.2) ──────────────
  let (billing_emit, billing_cell) = build_billing_cell()
  let billing_app = new(billing_cell)
  billing_app.with_init(billing_emit(Init))
  billing_app.mount("billing-content")

  // ── Media cell at #media-content (Phase 3.2) ──────────────────
  let (media_emit, media_cell) = build_media_cell()
  let media_app = new(media_cell)
  media_app.with_init(media_emit(Init))
  media_app.mount("media-content")

  // ── Onboard cell at #onboard-content (Phase 3.2) ───────────────
  let (onboard_emit, onboard_cell) = build_onboard_cell()
  let onboard_app = new(onboard_cell)
  onboard_app.with_init(onboard_emit(Init))
  onboard_app.mount("onboard-content")

  // ── Creator cell at #creator-content (Phase 3.2) ───────────────
  let (creator_emit, creator_cell) = build_creator_cell()
  let creator_app = new(creator_cell)
  creator_app.with_init(creator_emit(Init))
  creator_app.mount("creator-content")

  // ── Git cell at #git-content (Phase 3.2) ───────────────────────
  let (git_emit, git_cell) = build_git_cell()
  let git_app = new(git_cell)
  git_app.with_init(git_emit(Init))
  git_app.mount("git-content")

  // ── Channels cell at #channels-content (Phase 3.2) ─────────────
  let (channels_emit, channels_cell) = build_channels_cell()
  let channels_app = new(channels_cell)
  channels_app.with_init(channels_emit(Init))
  channels_app.mount("channels-content")

  // ── MCP cell at #mcp-content (Phase 3.2) ───────────────────────
  let (mcp_emit, mcp_cell) = build_mcp_cell()
  let mcp_app = new(mcp_cell)
  mcp_app.with_init(mcp_emit(Init))
  mcp_app.mount("mcp-content")

  // ── Settings cell at #settings-content (Phase 3.3) ────────────
  let (settings_emit, settings_cell) = build_settings_cell()
  let settings_app = new(settings_cell)
  settings_app.with_init(settings_emit(Init))
  settings_app.mount("settings-content")

  // ── Skills cell at #skills-enhanced-content (Phase 3.3) ───────
  let (skills_emit, skills_cell) = build_skills_cell()
  let skills_app = new(skills_cell)
  skills_app.with_init(skills_emit(Init))
  skills_app.mount("skills-enhanced-content")

  // ── Sessions cell at #session-list (Phase 3.4) ────────────────
  let (sessions_emit, sessions_cell) = build_sessions_cell()
  let sessions_app = new(sessions_cell)
  sessions_app.with_init(sessions_emit(Init))
  sessions_app.mount("session-list")

  // ── Chat cell at #view-chat (Phase 3.4) ───────────────────────
  let (chat_emit, chat_cell) = build_chat_cell()
  let chat_app = new(chat_cell)
  chat_app.with_init(chat_emit(Init))
  chat_app.mount("view-chat")

  // ── Notification cell at #notifications-container (Phase 4-A) ─
  let (notif_emit, notif_cell) = build_notification_cell()
  let notif_app = new(notif_cell)
  notif_app.with_init(notif_emit(Init))
  notif_app.mount("notifications-container")

  // ── Stats cell at #stats-content (Phase 4-C) ─────────────────
  let (stats_emit, stats_cell) = build_stats_cell()
  let stats_app = new(stats_cell)
  stats_app.with_init(stats_emit(Init))
  stats_app.mount("stats-content")

  // ── Shell cell at #mb-root (Phase 4-E: view routing + keyboard) ─
  let (shell_emit, shell_cell) = build_shell_cell()
  let shell_app = new(shell_cell)
  shell_app.with_init(shell_emit(Init))
  shell_app.mount("mb-root")
}
