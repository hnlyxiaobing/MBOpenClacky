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
    } else if path.contains("getupdates") {
      mock_http_send(conn, 200, "{\"ret\":-1,\"errmsg\":\"invalid token\"}")
    } else if path.contains("getUpdates") {
      mock_http_send(conn, 500, "{\"ok\":false,\"description\":\"mock outage\"}")
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
  } else if path.contains("getupdates") {
    mock_http_send(conn, 200, "{\"ret\":0,\"item_list\":[],\"buf\":\"\"}")
  } else if path.contains("editMessageText") {
    mock_http_send(conn, 200, "{\"ok\":true,\"result\":{\"message_id\":7}}")
  } else if path.contains("deleteMessage") {
    mock_http_send(conn, 200, "{\"ok\":true,\"result\":true}")
  } else if path.contains("users/@me") {
    mock_http_send(
      conn, 200, "{\"id\":\"bot-1\",\"username\":\"mbbot\",\"bot\":true}",
    )
  } else if http_method == "PATCH" && path.contains("/messages/") {
    mock_http_send(conn, 200, "{\"id\":\"msg-1\",\"content\":\"edited\"}")
  } else if http_method == "DELETE" && path.contains("/messages/") {
    // Discord answers 204 No Content on message deletion.
    mock_http_send(conn, 204, "")
  } else if http_method == "POST" && path.contains("/channels/") {
    // Discord send and multipart upload share this endpoint.
    mock_http_send(conn, 200, "{\"id\":\"msg-9\"}")
  } else if http_method == "GET" && path.contains("/attachments/") {
    mock_http_send(conn, 200, "attachment-bytes")
  } else if path.contains("getUpdates") {
    // Telegram long poll (#7): serve one scripted inbound update on the first
    // call, then an empty result so the loop has nothing left to dispatch.
    if server.count("getUpdates") == 1 {
      mock_http_send(
        conn, 200, "{\"ok\":true,\"result\":[{\"update_id\":101,\"message\":{\"message_id\":5,\"text\":\"hi from telegram\",\"chat\":{\"id\":123,\"type\":\"private\"},\"from\":{\"id\":7,\"first_name\":\"Ada\"}}}]}",
      )
    } else {
      mock_http_send(conn, 200, "{\"ok\":true,\"result\":[]}")
    }
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
/// The connectivity probe must be cheap: one getupdates round trip carrying the
/// 1s long-poll timeout, not the 40s used by the receive loop.
async test "weixin_probe_connectivity_mock_round_trip" {
  let server = MockPlatformServer::new()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let client = WeixinApiClient::with_base_url(
      "tok",
      "uin-1",
      server.base_url(),
    )
    match client.probe_connectivity() {
      Ok(_) => ()
      Err(_) => assert_true(false)
    }
    assert_eq(server.count("getupdates"), 1)
    let body = @json.parse(server.first_body("getupdates")) catch {
      _ => Json::object(Map([]))
    }
    match body {
      Object(obj) =>
        match obj.get("timeout") {
          Some(Number(n, ..)) => assert_eq(n.to_int(), 1)
          _ => assert_true(false)
        }
      _ => assert_true(false)
    }
    server.shutdown()
  })
}

///|
async test "weixin_probe_connectivity_surfaces_token_error" {
  let server = MockPlatformServer::new()
  server.fail_mode = true
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let client = WeixinApiClient::with_base_url(
      "bad",
      "uin-1",
      server.base_url(),
    )
    match client.probe_connectivity() {
      Ok(_) => assert_true(false)
      Err(ChannelError(msg)) => assert_true(msg.contains("invalid token"))
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

// ── Telegram / Discord edit + delete (WP-1.6) ────────────────────────────────
//
// Adapters are built as struct literals so their API client can point at the
// mock server (Telegram/Discord have no `api_base` setting).

///|
fn telegram_test_adapter(api_base : String) -> TelegramAdapter {
  {
    bot_token: "tok",
    is_running: true,
    message_callback: None,
    last_update_id: 0,
    poll_backoff_ms: 1000,
    poll_idle_ms: 200,
    api_client: TelegramApiClient::with_base_url("tok", api_base),
  }
}

///|
fn discord_test_adapter(api_base : String) -> DiscordAdapter {
  {
    bot_token: "tok",
    application_id: None,
    api_client: DiscordApiClient::with_base_url("tok", api_base),
    gateway_state: None,
    bot_user_id: None,
    is_running: true,
    message_callback: None,
    ws_client: WsClient::new(),
  }
}

///|
/// Edited and deleted through `AnyAdapter`, which also exercises the trait
/// dispatch added with the delete method.
async test "telegram_edit_and_delete_mock_round_trip" {
  let server = MockPlatformServer::new()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let any : AnyAdapter = AnyAdapter::Telegram(
      telegram_test_adapter(server.base_url()),
    )
    match any.update_message("chat1", "msg7", "edited text") {
      Ok(_) => ()
      Err(_) => assert_true(false)
    }
    assert_eq(server.count("editMessageText"), 1)
    let edit_body = server.first_body("editMessageText")
    assert_true(edit_body.contains("chat1"))
    assert_true(edit_body.contains("msg7"))
    assert_true(edit_body.contains("edited text"))
    match any.delete_message("chat1", "msg7") {
      Ok(_) => ()
      Err(_) => assert_true(false)
    }
    assert_eq(server.count("deleteMessage"), 1)
    assert_true(server.first_body("deleteMessage").contains("msg7"))
    server.shutdown()
  })
}

///|
async test "telegram_edit_error_surfaces" {
  let server = MockPlatformServer::new()
  server.fail_mode = true
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let adapter = telegram_test_adapter(server.base_url())
    match adapter.update_message("chat1", "msg7", "edited") {
      Ok(_) => assert_true(false)
      Err(ChannelError(msg)) => {
        assert_true(msg.contains("Internal Server Error"))
        assert_false(msg.contains("not implemented"))
      }
    }
    server.shutdown()
  })
}

///|
async test "discord_edit_and_delete_mock_round_trip" {
  let server = MockPlatformServer::new()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let adapter = discord_test_adapter(server.base_url())
    match adapter.update_message("chan1", "msg7", "edited text") {
      Ok(_) => ()
      Err(_) => assert_true(false)
    }
    assert_eq(server.count("PATCH /channels/chan1/messages/msg7"), 1)
    assert_true(server.first_body("PATCH /channels/").contains("edited text"))
    // DELETE answers 204 with no body: success is status-only.
    match adapter.delete_message("chan1", "msg7") {
      Ok(_) => ()
      Err(_) => assert_true(false)
    }
    assert_eq(server.count("DELETE /channels/chan1/messages/msg7"), 1)
    server.shutdown()
  })
}

///|
async test "discord_delete_error_surfaces" {
  let server = MockPlatformServer::new()
  server.fail_mode = true
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let adapter = discord_test_adapter(server.base_url())
    match adapter.delete_message("chan1", "msg7") {
      Ok(_) => assert_true(false)
      Err(ChannelError(msg)) => {
        assert_true(msg.contains("Internal Server Error"))
        assert_false(msg.contains("not implemented"))
      }
    }
    server.shutdown()
  })
}

///|
async test "discord_get_current_user_mock_round_trip" {
  let server = MockPlatformServer::new()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let client = DiscordApiClient::with_base_url("tok", server.base_url())
    match client.get_current_user() {
      Ok(json) =>
        match json {
          Object(obj) =>
            assert_eq(obj.get("id"), Some("bot-1".to_json()))
          _ => assert_true(false)
        }
      Err(_) => assert_true(false)
    }
    assert_eq(server.count("GET /users/@me"), 1)
    server.shutdown()
  })
}

///|
async test "discord_upload_file_mock_round_trip" {
  let server = MockPlatformServer::new()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let client = DiscordApiClient::with_base_url("tok", server.base_url())
    match client.upload_file("chan1", "report.txt", "file-content") {
      Ok(json) =>
        match json {
          Object(obj) => assert_eq(obj.get("id"), Some("msg-9".to_json()))
          _ => assert_true(false)
        }
      Err(_) => assert_true(false)
    }
    assert_eq(server.count("POST /channels/chan1/messages"), 1)
    let body = server.first_body("POST /channels/chan1/messages")
    assert_true(body.contains("payload_json"))
    assert_true(body.contains("filename=\"report.txt\""))
    assert_true(body.contains("file-content"))
    server.shutdown()
  })
}

///|
async test "discord_download_attachment_mock_round_trip" {
  let server = MockPlatformServer::new()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let client = DiscordApiClient::with_base_url("tok", server.base_url())
    match client.download_attachment(
      server.base_url() + "/attachments/1/report.txt",
    ) {
      Ok(body) => assert_eq(body, "attachment-bytes")
      Err(_) => assert_true(false)
    }
    assert_eq(server.count("GET /attachments/"), 1)
    server.shutdown()
  })
}

// ── Telegram receive side (plan #7) ──────────────────────────────────────────

///|
/// #7：长轮询必须把入站消息真正投递到回调；空轮询后循环继续存活，`stop()`
/// 能结束它（此前 start() 是 TODO，接收侧完全没接线）。
async test "telegram_long_poll_delivers_inbound_messages" {
  let server = MockPlatformServer::new()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let adapter = telegram_test_adapter(server.base_url())
    adapter.poll_idle_ms = 10
    adapter.poll_backoff_ms = 10
    let received : Array[String] = []
    adapter.message_callback = Some(fn(event) { received.push(event.text) })
    group.spawn_bg(no_wait=true, allow_failure=true, async fn() {
      adapter.run_long_poll_loop()
    })
    let mut waited = 0
    while received.length() == 0 && waited < 150 {
      @async.sleep(20)
      waited = waited + 1
    }
    match adapter.stop() {
      _ => ()
    }
    assert_true(received.length() >= 1, msg="no inbound event was delivered")
    assert_eq(received[0], "hi from telegram")
    assert_true(server.count("getUpdates") >= 1)
    assert_eq(adapter.last_update_id, 101)
    server.shutdown()
  })
}

///|
/// #7：上游故障时循环必须退避重连而不是崩溃/退出（连续失败仍继续轮询）。
async test "telegram_long_poll_survives_a_failing_upstream" {
  let server = MockPlatformServer::new()
  server.fail_mode = true
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let adapter = telegram_test_adapter(server.base_url())
    adapter.poll_idle_ms = 10
    adapter.poll_backoff_ms = 10
    adapter.message_callback = Some(fn(_event) { () })
    group.spawn_bg(no_wait=true, allow_failure=true, async fn() {
      adapter.run_long_poll_loop()
    })
    let mut waited = 0
    while server.count("getUpdates") < 3 && waited < 150 {
      @async.sleep(20)
      waited = waited + 1
    }
    match adapter.stop() {
      _ => ()
    }
    assert_true(
      server.count("getUpdates") >= 2,
      msg="loop stopped retrying after a failed poll",
    )
    server.shutdown()
  })
}

// ── WeCom WebSocket receive side (plan #8) ───────────────────────────────────

///|
/// #8：帧分类必须把 ping 答成心跳、data 帧 ACK 后投递、凭据被拒时判致命
/// （此前 WS 收发全是 stub，接收侧没有接线）。
test "wecom_frame_classification_drives_the_receive_loop" {
  let ping : Json = @json.parse("{\"type\":\"ping\"}") catch { _ => Json::null() }
  assert_eq(classify_ws_frame(ping), WsInboundAction::SendPong)
  let data : Json = @json.parse(
    "{\"type\":\"data\",\"req_id\":\"r1\",\"chat_id\":\"c1\",\"content\":\"hi\",\"msg_type\":\"text\",\"from_user_id\":\"u1\"}",
  ) catch {
    _ => Json::null()
  }
  match classify_ws_frame(data) {
    WsInboundAction::Dispatch(req_id~, data=payload) => {
      assert_eq(req_id, "r1")
      // 同一个 data 帧必须能解析成可投递的 ChannelEvent
      match WeComAdapter::parse_event(payload) {
        Ok(event) => {
          assert_eq(event.chat_id, "c1")
          assert_eq(event.text, "hi")
        }
        Err(_) => assert_true(false, msg="data frame did not parse into an event")
      }
    }
    _ => assert_true(false, msg="data frame was not classified as a dispatch")
  }
  let auth_err : Json = @json.parse(
    "{\"type\":\"auth_error\",\"errcode\":40001}",
  ) catch {
    _ => Json::null()
  }
  match classify_ws_frame(auth_err) {
    WsInboundAction::Fatal(_) => ()
    _ => assert_true(false, msg="auth error must be fatal")
  }
  let unknown : Json = @json.parse("{\"type\":\"whatever\"}") catch {
    _ => Json::null()
  }
  assert_eq(classify_ws_frame(unknown), WsInboundAction::Ignore)
}

///|
/// #8：端点不可达时必须退避重连且循环不崩，`stop()` 能结束它。
async test "wecom_ws_loop_backs_off_on_a_dead_endpoint" {
  let config : ChannelConfig = {
    platform: Platform::WeCom,
    enabled: true,
    settings: {
      "corp_id": "cid",
      "agent_id": "aid",
      "secret": "sec",
      "ws_url": "ws://127.0.0.1:1",
    },
  }
  let adapter = match WeComAdapter::new(config) {
    Ok(a) => a
    Err(_) => {
      assert_true(false, msg="adapter construction failed")
      return
    }
  }
  @async.with_task_group(async fn(group) {
    match adapter.start(fn(_event) { () }) {
      _ => ()
    }
    group.spawn_bg(no_wait=true, allow_failure=true, async fn() {
      adapter.run_ws_loop()
    })
    // Wait for the failed-connect path to bump the backoff (the connect itself
    // may take a moment on some platforms); then ask the loop to stop.
    let mut waited = 0
    while adapter.ws_backoff_ms == 1000 && waited < 250 {
      @async.sleep(20)
      waited = waited + 1
    }
    match adapter.stop() {
      _ => ()
    }
    assert_true(
      adapter.ws_backoff_ms > 1000,
      msg="backoff did not grow after a failed connect (\{adapter.ws_backoff_ms}ms)",
    )
  })
}

// ── DingTalk Stream Mode receive side (plan #9) ──────────────────────────────

///|
/// #9：Stream Mode 帧分类——SYSTEM/ping 答 pong、CALLBACK 按 messageId ACK 后
/// 投递、其它帧忽略（此前 WS 循环是独立工作项，接收侧未接线）。
test "dingtalk_stream_frame_classification_drives_the_loop" {
  let ping : Json = @json.parse(
    "{\"type\":\"SYSTEM\",\"data\":{\"topic\":\"ping\"}}",
  ) catch {
    _ => Json::null()
  }
  assert_eq(classify_stream_frame(ping), StreamInboundAction::SendPong)
  let other_system : Json = @json.parse(
    "{\"type\":\"SYSTEM\",\"data\":{\"topic\":\"connected\"}}",
  ) catch {
    _ => Json::null()
  }
  assert_eq(classify_stream_frame(other_system), StreamInboundAction::Ignore)
  let callback : Json = @json.parse(
    "{\"type\":\"CALLBACK\",\"data\":{\"headers\":{\"messageId\":\"m-1\"},\"msgtype\":\"text\",\"text\":{\"content\":\"hi\"},\"senderStaffId\":\"u1\",\"conversationId\":\"c1\"}}",
  ) catch {
    _ => Json::null()
  }
  match classify_stream_frame(callback) {
    StreamInboundAction::AckAndDispatch(message_id~, data~) => {
      assert_eq(message_id, "m-1")
      match DingTalkAdapter::parse_event(data) {
        Ok(event) => assert_true(
          !event.chat_id.is_empty() || event.text.contains("hi"),
          msg="callback frame did not yield a usable event",
        )
        Err(_) => assert_true(false, msg="callback frame did not parse")
      }
    }
    _ => assert_true(false, msg="CALLBACK was not classified as a dispatch")
  }
  // ACK frame carries the messageId so the gateway can correlate it
  let ack = build_stream_ack("m-1").stringify()
  assert_true(ack.contains("m-1"), msg="ack lost the messageId: " + ack)
}

///|
/// #9：网关不可达时必须退避重连且循环不崩，`stop()` 能结束它。
async test "dingtalk_stream_loop_backs_off_on_a_dead_gateway" {
  let config : ChannelConfig = {
    platform: Platform::DingTalk,
    enabled: true,
    settings: {
      "access_token": "tok",
      "app_secret": "sec",
      "stream_url": "ws://127.0.0.1:1",
    },
  }
  let adapter = match DingTalkAdapter::new(config) {
    Ok(a) => a
    Err(_) => {
      assert_true(false, msg="adapter construction failed")
      return
    }
  }
  @async.with_task_group(async fn(group) {
    match adapter.start(fn(_event) { () }) {
      _ => ()
    }
    group.spawn_bg(no_wait=true, allow_failure=true, async fn() {
      adapter.run_stream_loop()
    })
    let mut waited = 0
    while adapter.stream_backoff_ms == 1000 && waited < 250 {
      @async.sleep(20)
      waited = waited + 1
    }
    match adapter.stop() {
      _ => ()
    }
    assert_true(
      adapter.stream_backoff_ms > 1000,
      msg="backoff did not grow after a failed connect (\{adapter.stream_backoff_ms}ms)",
    )
  })
}
