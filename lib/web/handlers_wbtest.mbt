///| 会话列表投影（计划 #4，复现用例 4a）。
///
/// 此前 `build_session_summary`（handlers.mbt）与 `handle_ws_list_sessions`
/// （handlers_ws.mbt）都投影 `sd.created_at`，导致 Web 会话列表的排序恒等于
/// 创建时间、活跃会话永不上浮（前端 sessions.js 按 updated_at 排序与显示相对时间）。

///|
/// `Agent::to_session_data` 每次快照都刷新 updated_at，因此真实值必然不同于
/// created_at——投影必须原样透出。
test "plan_4a_session_summary_projects_real_updated_at" {
  let base = wd_make_session("sess-4a", "/tmp/x")
  let sd : @agent.SessionData = {
    ..base,
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-09-23T10:00:00Z",
  }
  let summary = build_session_summary(sd, false, None, [])
  @debug.assert_eq(summary.created_at, "2026-01-01T00:00:00Z")
  @debug.assert_eq(summary.updated_at, "2026-09-23T10:00:00Z")
}

///|
/// 早于 updated_at 存在的旧会话文件回落到 created_at（与 @agent.list_sessions 同规则）。
test "plan_4a_legacy_session_falls_back_to_created_at" {
  let base = wd_make_session("sess-4a-legacy", "/tmp/x")
  let sd : @agent.SessionData = {
    ..base,
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "",
  }
  let summary = build_session_summary(sd, false, None, [])
  @debug.assert_eq(summary.updated_at, "2026-01-01T00:00:00Z")
}