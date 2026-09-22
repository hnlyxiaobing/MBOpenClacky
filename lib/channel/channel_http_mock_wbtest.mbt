///| Mock HTTP server for the DingTalk / WeCom / Weixin REST paths (WP-1.2~1.4).
///
/// A single server routes on the request path, so one instance can stand in
/// for several platforms at once and the wired clients can be exercised over a
/// real socket without hitting the public APIs. Shutdown and body reading reuse
/// the primitives documented in feishu_mock_wbtest.mbt.

///|
/// Path fragments that belong to the DingTalk new API, whose failures are
/// reported with an HTTP status rather than a 200 + business code.
fn is_dingtalk_path(path : String) -> Bool {
  path.contains("oauth2/accessToken") ||
  path.contains("gateway/connections") ||
  path.contains("messageFiles/download")
}

///|
struct MockPlatformServer {
  listener : @socket.TcpServer
  // Recorded requests: ("METHOD path", body)
  requests : Array[(String, String)]
  mut fail_mode : Bool
  mut stopped : Bool
}

///|
async fn MockPlatformServer::new() -> MockPlatformServer {
  let listener = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  { listener, requests: [], fail_mode: false, stopped: false, }
}

///|
fn MockPlatformServer::port(self : MockPlatformServer) -> Int {
  self.listener.addr.port()
}

///|
fn MockPlatformServer::base_url(self : MockPlatformServer) -> String {
  "http://127.0.0.1:\{self.port()}"
}

///|
/// Count recorded requests whose "METHOD path" contains the fragment.
fn MockPlatformServer::count(
  self : MockPlatformServer,
  fragment : String,
) -> Int {
  let mut n = 0
  for req in self.requests {
    let (line, _body) = req
    if line.contains(fragment) {
      n = n + 1
    }
  }
  n
}

///|
/// Body of the first recorded request whose "METHOD path" contains the fragment.
fn MockPlatformServer::first_body(
  self : MockPlatformServer,
  fragment : String,
) -> String {
  for req in self.requests {
    let (line, body) = req
    if line.contains(fragment) {
      return body
    }
  }
  ""
}

///|
async fn MockPlatformServer::shutdown(self : MockPlatformServer) -> Unit {
  self.stopped = true
  let conn = Some(@socket.Tcp::connect(self.listener.addr)) catch { _ => None }
  match conn {
    Some(_) => ()
    None => self.listener.close()
  }
}

///|
async fn MockPlatformServer::serve(self : MockPlatformServer) -> Unit {
  for ;; {
    let (conn, _) = self.listener.accept() catch { _ => break }
    if self.stopped {
      conn.close()
      break
    }
    mock_platform_handle_conn(self, conn) catch {
      _ => ()
    }
    conn.close()
  }
  self.listener.close()
}

///|
async fn mock_platform_handle_conn(
  server : MockPlatformServer,
  conn : @socket.Tcp,
) -> Unit {
  let request_line = match conn.read_until("\r\n") {
    Some(line) => line
    None => return
  }
  let parts = request_line.split(" ").collect()
  if parts.length() < 2 {
    return
  }
  let http_method = parts[0].to_owned()
  let path = parts[1].to_owned()
  let headers : Map[String, String] = Map([])
  for ;; {
    match conn.read_until("\r\n") {
      Some("") => break
      Some(line) => {
        let segs = line.split(":").map(fn(s) { s.to_owned() }).collect()
        if segs.length() >= 2 {
          headers[segs[0].to_lower()] = segs[1].trim().to_owned()
        }
      }
      None => return
    }
  }
  let has_body = http_method == "POST" || http_method == "PATCH"
  let body = if has_body { mock_http_read_body(conn, headers) } else { "" }
  server.requests.push((http_method + " " + path, body))
  if server.fail_mode {
    // DingTalk fails via HTTP status; WeCom/Weixin fail via 200 + business code.
    if is_dingtalk_path(path) {
      mock_http_send(
        conn, 401, "{\"code\":\"InvalidCredential\",\"message\":\"invalid app credentials\"}",
      )
    } else if path.contains("gettoken") {
      mock_http_send(
        conn, 200, "{\"errcode\":40013,\"errmsg\":\"invalid corpid\"}",
      )
    } else if path.contains("message/send") {
      mock_http_send(
        conn, 200, "{\"errcode\":81013,\"errmsg\":\"user not found\"}",
      )
    } else if path.contains("sendmessage") {
      mock_http_send(conn, 200, "{\"ret\":-2,\"errmsg\":\"send too fast\"}")
    } else {
      mock_http_send(conn, 500, "{\"message\":\"mock failure\"}")
    }
    return
  }
  if path.contains("oauth2/accessToken") {
    mock_http_send(
      conn, 200, "{\"accessToken\":\"dt-token\",\"expireIn\":7200}",
    )
  } else if path.contains("gateway/connections/open") {
    mock_http_send(
      conn, 200, "{\"endpoint\":\"wss://mock.example/stream\",\"ticket\":\"tk-1\"}",
    )
  } else if path.contains("messageFiles/download") {
    mock_http_send(
      conn, 200, "{\"downloadUrl\":\"https://mock.example/dl/file-1\"}",
    )
  } else if path.contains("gettoken") {
    mock_http_send(
      conn, 200, "{\"errcode\":0,\"errmsg\":\"ok\",\"access_token\":\"wecom-token\",\"expires_in\":7200}",
    )
  } else if path.contains("message/send") {
    mock_http_send(
      conn, 200, "{\"errcode\":0,\"errmsg\":\"ok\",\"msgid\":\"wecom-msg-1\"}",
    )
  } else if path.contains("sendmessage") {
    mock_http_send(conn, 200, "{\"ret\":0,\"msg_id\":\"wx_msg_1\"}")
  } else {
    mock_http_send(conn, 404, "{\"message\":\"not found\"}")
  }
}

// ── DingTalk: gateway + file download (WP-1.2) ────────────────────────────────

///|
async test "dingtalk_stream_and_download_mock_round_trip" {
  let server = MockPlatformServer::new()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let client = DingTalkApiClient::with_base_url(
      "key",
      "sec",
      server.base_url(),
    )
    // open_stream_connection
    match client.open_stream_connection("key", "sec") {
      Ok((endpoint, ticket)) => {
        assert_eq(endpoint, "wss://mock.example/stream")
        assert_eq(ticket, "tk-1")
      }
      Err(_) => assert_true(false)
    }
    // download_file_url needs the new-API token first (header auth)
    match client.download_file_url("dl-code", "robot-1") {
      Ok(url) => assert_eq(url, "https://mock.example/dl/file-1")
      Err(_) => assert_true(false)
    }
    // The token endpoint must have been hit exactly once (cached afterwards)
    assert_eq(server.count("oauth2/accessToken"), 1)
    assert_eq(server.count("gateway/connections/open"), 1)
    assert_eq(server.count("messageFiles/download"), 1)
    server.shutdown()
  })
}

///|
async test "dingtalk_stream_connection_error_surfaces" {
  let server = MockPlatformServer::new()
  server.fail_mode = true
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let client = DingTalkApiClient::with_base_url(
      "key",
      "sec",
      server.base_url(),
    )
    match client.open_stream_connection("key", "sec") {
      Ok(_) => assert_true(false)
      Err(ChannelError(msg)) =>
        assert_true(msg.contains("invalid app credentials"))
    }
    server.shutdown()
  })
}

// ── WeCom: token + message/send (WP-1.3) ──────────────────────────────────────

///|
fn wecom_test_config(api_base : String) -> ChannelConfig {
  {
    platform: Platform::WeCom,
    enabled: true,
    settings: {
      "corp_id": "corp1",
      "agent_id": "agent1",
      "secret": "sec1",
      "api_base": api_base,
    },
  }
}

///|
async test "wecom_send_mock_round_trip_caches_token" {
  let server = MockPlatformServer::new()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let adapter = match
      WeComAdapter::new(wecom_test_config(server.base_url())) {
      Ok(a) => a
      Err(_) => {
        assert_true(false)
        return
      }
    }
    let _ = adapter.start(fn(_e) { () })
    match adapter.send_text("user1", "hello wecom", None) {
      Ok(r) => {
        assert_true(r.success)
        assert_eq(r.message_id, "wecom-msg-1")
      }
      Err(_) => assert_true(false)
    }
    // A second send reuses the cached access_token
    let _ = adapter.send_text("user1", "hello again", None)
    assert_eq(server.count("gettoken"), 1)
    assert_eq(server.count("message/send"), 2)
    // The body carries the agentid and the text content
    let body = server.first_body("message/send")
    assert_true(body.contains("agent1"))
    assert_true(body.contains("hello wecom"))
    server.shutdown()
  })
}

///|
async test "wecom_send_business_error_surfaces" {
  let server = MockPlatformServer::new()
  server.fail_mode = true
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let adapter = match
      WeComAdapter::new(wecom_test_config(server.base_url())) {
      Ok(a) => a
      Err(_) => {
        assert_true(false)
        return
      }
    }
    let _ = adapter.start(fn(_e) { () })
    // Seed the token so the failure comes from message/send, not gettoken.
    adapter.api_client.token_cache.set("seeded", 7200_000)
    match adapter.send_text("user1", "hi", None) {
      Ok(_) => assert_true(false)
      Err(ChannelError(msg)) => assert_true(msg.contains("user not found"))
    }
    server.shutdown()
  })
}

///|
async test "wecom_token_error_surfaces" {
  let server = MockPlatformServer::new()
  server.fail_mode = true
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let adapter = match
      WeComAdapter::new(wecom_test_config(server.base_url())) {
      Ok(a) => a
      Err(_) => {
        assert_true(false)
        return
      }
    }
    let _ = adapter.start(fn(_e) { () })
    match adapter.send_text("user1", "hi", None) {
      Ok(_) => assert_true(false)
      Err(ChannelError(msg)) => assert_true(msg.contains("invalid corpid"))
    }
    server.shutdown()
  })
}

// ── Weixin: sendmessage (WP-1.4) ──────────────────────────────────────────────

///|
fn weixin_test_config(api_base : String) -> ChannelConfig {
  {
    platform: Platform::Weixin,
    enabled: true,
    settings: {
      "app_id": "wx_app",
      "app_secret": "wx_sec",
      "token": "wx_tok",
      "uin": "uin-1",
      "api_base": api_base,
    },
  }
}

///|
async test "weixin_send_mock_round_trip_sanitizes" {
  let server = MockPlatformServer::new()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let adapter = match
      WeixinAdapter::new(weixin_test_config(server.base_url())) {
      Ok(a) => a
      Err(_) => {
        assert_true(false)
        return
      }
    }
    let _ = adapter.start(fn(_e) { () })
    match adapter.send_text("user1", "**bold** text", None) {
      Ok(r) => {
        assert_true(r.success)
        assert_eq(r.message_id, "wx_msg_1")
      }
      Err(_) => assert_true(false)
    }
    assert_eq(server.count("sendmessage"), 1)
    let body = server.first_body("sendmessage")
    // Markdown is stripped before sending; the recipient is carried through.
    assert_true(body.contains("bold text"))
    assert_false(body.contains("**"))
    assert_true(body.contains("user1"))
    server.shutdown()
  })
}

///|
async test "weixin_send_rate_limit_surfaces" {
  let server = MockPlatformServer::new()
  server.fail_mode = true
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let adapter = match
      WeixinAdapter::new(weixin_test_config(server.base_url())) {
      Ok(a) => a
      Err(_) => {
        assert_true(false)
        return
      }
    }
    let _ = adapter.start(fn(_e) { () })
    match adapter.send_text("user1", "hi", None) {
      Ok(_) => assert_true(false)
      Err(ChannelError(msg)) => {
        assert_true(msg.contains("send too fast"))
        assert_true(msg.contains("rate limited"))
      }
    }
    server.shutdown()
  })
}

///|
async test "weixin_send_without_uin_reports_missing_client" {
  let config : ChannelConfig = {
    platform: Platform::Weixin,
    enabled: true,
    settings: { "app_id": "wx_app", "app_secret": "wx_sec", "token": "wx_tok" },
  }
  let adapter = match WeixinAdapter::new(config) {
    Ok(a) => a
    Err(_) => {
      assert_true(false)
      return
    }
  }
  let _ = adapter.start(fn(_e) { () })
  match adapter.send_text("user1", "hi", None) {
    Ok(_) => assert_true(false)
    Err(ChannelError(msg)) => assert_true(msg.contains("no api_client"))
  }
}
