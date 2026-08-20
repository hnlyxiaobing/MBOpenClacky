///| White-box tests for proxy_config.mbt (P2-4 coverage expansion).
///
/// Proxy configuration with explicit-parameter install (no environment
/// dependency). Behavior is deterministic.

///|
test "proxy_config: new is empty and disabled" {
  let p = ProxyConfig::new()
  @debug.assert_eq(p.proxy_url(), "")
  @debug.assert_eq(p.current_epoch(), 0)
  assert_false(p.is_enabled())
}

///|
test "proxy_config: install with explicit url enables proxy" {
  let p = ProxyConfig::install(proxy_url=Some("http://proxy:8080"))
  @debug.assert_eq(p.proxy_url(), "http://proxy:8080")
  assert_true(p.is_enabled())
  @debug.assert_eq(p.current_epoch(), 1)
}

///|
test "proxy_config: should_bypass false when no no_proxy list" {
  let p = ProxyConfig::install(
    proxy_url=Some("http://proxy:8080"),
    no_proxy=Some(""),
  )
  assert_false(p.should_bypass("localhost"))
}

///|
test "proxy_config: should_bypass matches listed host" {
  let p = ProxyConfig::install(
    proxy_url=Some("http://proxy:8080"),
    no_proxy=Some("localhost,127.0.0.1"),
  )
  assert_true(p.should_bypass("localhost"))
  assert_true(p.should_bypass("127.0.0.1"))
}

///|
test "proxy_config: should_bypass false for unlisted host" {
  let p = ProxyConfig::install(
    proxy_url=Some("http://proxy:8080"),
    no_proxy=Some("localhost"),
  )
  assert_false(p.should_bypass("example.com"))
}

///|
test "proxy_config: should_bypass is case-insensitive" {
  let p = ProxyConfig::install(
    proxy_url=Some("http://proxy:8080"),
    no_proxy=Some("localhost"),
  )
  assert_true(p.should_bypass("LOCALHOST"))
}

///|
test "proxy_config: reset clears url and bumps epoch" {
  let p = ProxyConfig::install(proxy_url=Some("http://proxy:8080"))
  let r = p.reset()
  @debug.assert_eq(r.proxy_url(), "")
  assert_false(r.is_enabled())
  @debug.assert_eq(r.current_epoch(), 2)
}

///|
test "proxy_config: install with empty url stays disabled" {
  let p = ProxyConfig::install(proxy_url=Some(""))
  assert_false(p.is_enabled())
  @debug.assert_eq(p.proxy_url(), "")
}

// ── p6: CLACKY_NO_PROXY_ENV escape hatch ─────────────────────────────────────

///|
test "proxy_config: CLACKY_NO_PROXY_ENV ignores ambient proxy vars" {
  @env.set_env_var("HTTPS_PROXY", "http://corp-proxy:8080")
  @env.set_env_var("HTTP_PROXY", "http://corp-proxy:8080")
  @env.set_env_var("CLACKY_NO_PROXY_ENV", "1")
  // No explicit parameter -> ambient env ignored entirely
  let p = ProxyConfig::install()
  @debug.assert_eq(p.proxy_url(), "")
  assert_false(p.is_enabled())
  // Explicit parameter still wins over the escape hatch
  let explicit = ProxyConfig::install(proxy_url=Some("http://explicit:1"))
  @debug.assert_eq(explicit.proxy_url(), "http://explicit:1")
  @env.unset_env_var("CLACKY_NO_PROXY_ENV")
  // Without the hatch, ambient HTTPS_PROXY is honored again
  let ambient = ProxyConfig::install()
  @debug.assert_eq(ambient.proxy_url(), "http://corp-proxy:8080")
  // Cleanup
  @env.unset_env_var("HTTPS_PROXY")
  @env.unset_env_var("HTTP_PROXY")
}
