///|
/// Tests for PlatformHttpClient logic (no actual HTTP calls).
test "PlatformHttpConfig new defaults" {
  let cfg = PlatformHttpConfig::new(primary_host="https://api.anthropic.com")
  @debug.debug_inspect(
    cfg.primary_host,
    content=(
      #|"https://api.anthropic.com"
    ),
  )
  @debug.debug_inspect(
    cfg.secondary_host,
    content=(
      #|""
    ),
  )
  @debug.debug_inspect(
    cfg.fallback_host,
    content=(
      #|""
    ),
  )
  @debug.debug_inspect(cfg.open_timeout_ms, content="8000")
  @debug.debug_inspect(cfg.read_timeout_ms, content="15000")
  @debug.debug_inspect(cfg.max_retries, content="2")
  @debug.debug_inspect(cfg.initial_backoff_ms, content="500")
  @debug.debug_inspect(
    cfg.proxy_url,
    content=(
      #|""
    ),
  )
}

///|
test "PlatformHttpConfig new with all params" {
  let cfg = PlatformHttpConfig::new(
    primary_host="https://api.example.com",
    secondary_host="https://api-cdn.example.com",
    fallback_host="https://api-backup.example.com",
    open_timeout_ms=5000,
    read_timeout_ms=10000,
    max_retries=3,
    initial_backoff_ms=1000,
    proxy_url="http://proxy:8080",
  )
  @debug.debug_inspect(
    cfg.primary_host,
    content=(
      #|"https://api.example.com"
    ),
  )
  @debug.debug_inspect(
    cfg.secondary_host,
    content=(
      #|"https://api-cdn.example.com"
    ),
  )
  @debug.debug_inspect(
    cfg.fallback_host,
    content=(
      #|"https://api-backup.example.com"
    ),
  )
  @debug.debug_inspect(cfg.open_timeout_ms, content="5000")
  @debug.debug_inspect(cfg.read_timeout_ms, content="10000")
  @debug.debug_inspect(cfg.max_retries, content="3")
  @debug.debug_inspect(cfg.initial_backoff_ms, content="1000")
  @debug.debug_inspect(
    cfg.proxy_url,
    content=(
      #|"http://proxy:8080"
    ),
  )
}

///|
test "calculate_backoff exponential" {
  let cfg = PlatformHttpConfig::new(
    primary_host="https://api.example.com",
    initial_backoff_ms=500,
  )
  let client = PlatformHttpClient::new(cfg)
  // 500 * 2^0 = 500
  @debug.debug_inspect(client.calculate_backoff(0), content="500")
  // 500 * 2^1 = 1000
  @debug.debug_inspect(client.calculate_backoff(1), content="1000")
  // 500 * 2^2 = 2000
  @debug.debug_inspect(client.calculate_backoff(2), content="2000")
  // 500 * 2^3 = 4000
  @debug.debug_inspect(client.calculate_backoff(3), content="4000")
  // 500 * 2^4 = 8000
  @debug.debug_inspect(client.calculate_backoff(4), content="8000")
  // 500 * 2^5 = 16000
  @debug.debug_inspect(client.calculate_backoff(5), content="16000")
  // 500 * 2^6 = 32000 → capped at 30000
  @debug.debug_inspect(client.calculate_backoff(6), content="30000")
  // 500 * 2^7 = 64000 → capped at 30000
  @debug.debug_inspect(client.calculate_backoff(7), content="30000")
}

///|
test "should_failover on timeout" {
  let cfg = PlatformHttpConfig::new(
    primary_host="https://api.example.com",
    fallback_host="https://backup.example.com",
  )
  let client = PlatformHttpClient::new(cfg)
  @debug.debug_inspect(
    client.should_failover(Timeout("read timeout")),
    content="true",
  )
}

///|
test "should_failover on server_error" {
  let cfg = PlatformHttpConfig::new(
    primary_host="https://api.example.com",
    fallback_host="https://backup.example.com",
  )
  let client = PlatformHttpClient::new(cfg)
  @debug.debug_inspect(
    client.should_failover(ServerError(502, "bad gateway")),
    content="true",
  )
}

///|
test "should_failover on client_error" {
  let cfg = PlatformHttpConfig::new(
    primary_host="https://api.example.com",
    fallback_host="https://backup.example.com",
  )
  let client = PlatformHttpClient::new(cfg)
  @debug.debug_inspect(
    client.should_failover(ClientError(401, "unauthorized")),
    content="false",
  )
}

///|
test "should_failover without fallback host" {
  let cfg = PlatformHttpConfig::new(primary_host="https://api.example.com")
  let client = PlatformHttpClient::new(cfg)
  // No fallback_host configured, should not failover even on timeout
  @debug.debug_inspect(
    client.should_failover(Timeout("timeout")),
    content="false",
  )
}

///|
test "is_retryable checks" {
  @debug.debug_inspect(is_retryable(Timeout("timeout")), content="true")
  @debug.debug_inspect(
    is_retryable(ConnectionFailed("refused")),
    content="true",
  )
  @debug.debug_inspect(
    is_retryable(ServerError(500, "internal")),
    content="true",
  )
  @debug.debug_inspect(
    is_retryable(ClientError(400, "bad request")),
    content="false",
  )
  @debug.debug_inspect(
    is_retryable(ClientError(401, "unauthorized")),
    content="false",
  )
  @debug.debug_inspect(
    is_retryable(AllHostsFailed("exhausted")),
    content="false",
  )
}

///|
test "do_failover switches host" {
  let cfg = PlatformHttpConfig::new(
    primary_host="https://primary.example.com",
    fallback_host="https://fallback.example.com",
  )
  let client = PlatformHttpClient::new(cfg)
  @debug.debug_inspect(
    client.active_host(),
    content=(
      #|"https://primary.example.com"
    ),
  )
  client.do_failover()
  @debug.debug_inspect(
    client.active_host(),
    content=(
      #|"https://fallback.example.com"
    ),
  )
  // Failover again should switch back to primary
  client.do_failover()
  @debug.debug_inspect(
    client.active_host(),
    content=(
      #|"https://primary.example.com"
    ),
  )
}

///|
test "do_failover no-op without fallback" {
  let cfg = PlatformHttpConfig::new(primary_host="https://primary.example.com")
  let client = PlatformHttpClient::new(cfg)
  client.do_failover()
  // Should remain on primary since no fallback configured
  @debug.debug_inspect(
    client.active_host(),
    content=(
      #|"https://primary.example.com"
    ),
  )
}

///|
test "do_failover three-domain chain order" {
  let cfg = PlatformHttpConfig::new(
    primary_host="https://primary.example.com",
    secondary_host="https://secondary.example.com",
    fallback_host="https://fallback.example.com",
  )
  let client = PlatformHttpClient::new(cfg)
  // primary -> secondary -> fallback, then wrap back to primary
  client.do_failover()
  @debug.debug_inspect(
    client.active_host(),
    content=(
      #|"https://secondary.example.com"
    ),
  )
  client.do_failover()
  @debug.debug_inspect(
    client.active_host(),
    content=(
      #|"https://fallback.example.com"
    ),
  )
  client.do_failover()
  @debug.debug_inspect(
    client.active_host(),
    content=(
      #|"https://primary.example.com"
    ),
  )
}

///|
test "do_failover empty secondary skips to fallback" {
  let cfg = PlatformHttpConfig::new(
    primary_host="https://primary.example.com",
    fallback_host="https://fallback.example.com",
  )
  let client = PlatformHttpClient::new(cfg)
  client.do_failover()
  @debug.debug_inspect(
    client.active_host(),
    content=(
      #|"https://fallback.example.com"
    ),
  )
}

///|
test "should_failover with secondary host" {
  // secondary alone (no fallback) still offers a failover target
  let cfg = PlatformHttpConfig::new(
    primary_host="https://api.example.com",
    secondary_host="https://secondary.example.com",
  )
  let client = PlatformHttpClient::new(cfg)
  @debug.debug_inspect(
    client.should_failover(Timeout("timeout")),
    content="true",
  )
}

///|
test "failover_chain skips empty hosts" {
  let cfg = PlatformHttpConfig::new(
    primary_host="https://primary.example.com",
    fallback_host="https://fallback.example.com",
  )
  let client = PlatformHttpClient::new(cfg)
  @debug.debug_inspect(
    client.failover_chain(),
    content=(
      #|["https://primary.example.com", "https://fallback.example.com"]
    ),
  )
}

///|
test "reset_failover returns to primary" {
  let cfg = PlatformHttpConfig::new(
    primary_host="https://primary.example.com",
    fallback_host="https://fallback.example.com",
  )
  let client = PlatformHttpClient::new(cfg)
  client.do_failover()
  @debug.debug_inspect(
    client.active_host(),
    content=(
      #|"https://fallback.example.com"
    ),
  )
  client.reset_failover()
  @debug.debug_inspect(
    client.active_host(),
    content=(
      #|"https://primary.example.com"
    ),
  )
  @debug.debug_inspect(client.consecutive_failures, content="0")
  @debug.debug_inspect(client.last_failover_epoch, content="0")
}

///|
async test "execute_with_retry exhausts retries" {
  let cfg = PlatformHttpConfig::new(
    primary_host="https://primary.example.com",
    fallback_host="https://fallback.example.com",
    max_retries=1,
  )
  let client = PlatformHttpClient::new(cfg)
  // send_request always returns ConnectionFailed, so all retries exhaust
  let result = client.get("/v1/test")
  match result {
    Err(AllHostsFailed(_)) => () // expected
    _ => fail("Expected AllHostsFailed error")
  }
}
