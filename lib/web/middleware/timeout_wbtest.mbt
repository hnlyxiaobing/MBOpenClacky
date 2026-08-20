///| White-box tests for the timeout middleware route resolution.
/// spec 2026-08-18_17 decision 6: resolve must use precise prefix/suffix
/// matching only — the previous `contains` fallback matched any URL
/// containing the substring "/chat" (e.g. /api/skills/chat-export),
/// incorrectly applying the 120s chat timeout to unrelated routes.

///|
/// Chat stream route matches the 300s streaming timeout.
test "timeout resolve: /chat/stream suffix hits 300s" {
  let cfg = default_timeout_config()
  // Full /api/sessions/:id/chat/stream URL — the /chat/stream suffix
  // should match.
  @debug.assert_eq(cfg.resolve("/api/sessions/abc-123/chat/stream"), 300000)
}

///|
/// Plain chat route matches the 120s non-streaming timeout.
test "timeout resolve: /chat suffix hits 120s" {
  let cfg = default_timeout_config()
  @debug.assert_eq(cfg.resolve("/api/sessions/abc-123/chat"), 120000)
}

///|
/// Prefix-style routes still match via has_prefix (e.g. /api/brand/*).
test "timeout resolve: /api/brand/ prefix hits 90s" {
  let cfg = default_timeout_config()
  @debug.assert_eq(cfg.resolve("/api/brand/status"), 90000)
  @debug.assert_eq(cfg.resolve("/api/brand/skills"), 90000)
}

///|
/// Regression: a URL containing the substring "/chat" but NOT ending
/// in /chat or /chat/stream must not inherit the chat timeout. The
/// previous `contains` implementation matched /api/skills/chat-export
/// at 120s; it should now fall through to the default 30s.
test "timeout resolve: /chat substring no longer matches (spec-17 d6)" {
  let cfg = default_timeout_config()
  @debug.assert_eq(cfg.resolve("/api/skills/chat-export"), 30000)
  @debug.assert_eq(cfg.resolve("/api/skills/my-chat-tool"), 30000)
}

///|
/// Unrelated routes fall through to the default 30s.
test "timeout resolve: default fallback" {
  let cfg = default_timeout_config()
  @debug.assert_eq(cfg.resolve("/api/sessions/abc-123/status"), 30000)
  @debug.assert_eq(cfg.resolve("/api/config"), 30000)
}
