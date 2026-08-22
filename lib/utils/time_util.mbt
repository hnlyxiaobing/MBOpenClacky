///| Shared time utilities (stubfix-04 decision 5: shared clock source).

///|
/// Current wall-clock time in milliseconds since the Unix epoch.
/// Shared clock source for MCP timestamps (started_at / last_used_at /
/// cleanup_idle) and other idle-tracking consumers (stubfix-05 scheduler).
pub fn now_ms() -> Int64 {
  @env.now().reinterpret_as_int64()
}

///|
/// Current wall-clock time in seconds since the Unix epoch.
pub fn now_seconds() -> Int {
  (now_ms() / 1000L).to_int()
}
