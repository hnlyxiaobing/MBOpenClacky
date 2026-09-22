///| Mock Feishu Open API server for HTTP-path tests.
/// Mirrors test/e2e/mock_llm_server.mbt shutdown semantics (self-connect
/// wakeup, keep-open) — see that file for the accept-race rationale.

///|
struct MockFeishuServer {
  listener : @socket.TcpServer
  // Recorded requests: ("METHOD path", body)
  requests : Array[(String, String)]
  mut fail_mode : Bool
  mut stopped : Bool
}

///|
async fn MockFeishuServer::new() -> MockFeishuServer {
  let listener = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  { listener, requests: [], fail_mode: false, stopped: false, }
}

///|
fn MockFeishuServer::port(self : MockFeishuServer) -> Int {
  self.listener.addr.port()
}

///|
async fn MockFeishuServer::shutdown(self : MockFeishuServer) -> Unit {
  self.stopped = true
  let conn = Some(@socket.Tcp::connect(self.listener.addr)) catch { _ => None }
  match conn {
    Some(_) => ()
    None => self.listener.close()
  }
}

///|
async fn MockFeishuServer::serve(self : MockFeishuServer) -> Unit {
  for ;; {
    let (conn, _) = self.listener.accept() catch { _ => break }
    if self.stopped {
      conn.close()
      break
    }
    mock_feishu_handle_conn(self, conn) catch {
      _ => ()
    }
    conn.close()
  }
  self.listener.close()
}

///|
/// Write a single HTTP/1.1 response. Shared with the other channel mock tests
/// (channel_http_mock_wbtest.mbt).
async fn mock_http_send(
  conn : @socket.Tcp,
  status : Int,
  body : String,
) -> Unit {
  conn.write(
    "HTTP/1.1 \{status} OK\r\nContent-Type: application/json\r\nContent-Length: \{body.length()}\r\nConnection: close\r\n\r\n\{body}",
  )
}

///|
async fn mock_feishu_handle_conn(
  server : MockFeishuServer,
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
  // Business-failure injection: Feishu returns HTTP 200 with code != 0.
  if server.fail_mode {
    mock_http_send(conn, 200, "{\"code\":99991663,\"msg\":\"token expired\"}")
    return
  }
  if path.contains("tenant_access_token/internal") {
    mock_http_send(
      conn, 200, "{\"code\":0,\"msg\":\"success\",\"tenant_access_token\":\"t-mock\",\"expire\":7200}",
    )
  } else if http_method == "POST" &&
    path.contains("im/v1/messages?receive_id_type") {
    mock_http_send(
      conn, 200, "{\"code\":0,\"msg\":\"success\",\"data\":{\"message_id\":\"om_mock123\"}}",
    )
  } else if http_method == "PATCH" && path.contains("im/v1/messages/") {
    mock_http_send(conn, 200, "{\"code\":0,\"msg\":\"success\",\"data\":{}}")
  } else if http_method == "DELETE" && path.contains("im/v1/messages/") {
    mock_http_send(conn, 200, "{\"code\":0,\"msg\":\"success\",\"data\":{}}")
  } else if http_method == "POST" && path.contains("im/v1/images") {
    mock_http_send(
      conn, 200, "{\"code\":0,\"msg\":\"success\",\"data\":{\"image_key\":\"img_v2_mock\"}}",
    )
  } else if http_method == "POST" && path.contains("im/v1/files") {
    mock_http_send(
      conn, 200, "{\"code\":0,\"msg\":\"success\",\"data\":{\"file_key\":\"file_v2_mock\"}}",
    )
  } else if http_method == "GET" && path.contains("/resources/") {
    mock_http_send(conn, 200, "hello-bytes")
  } else if http_method == "GET" && path.contains("container_id_type=chat") {
    mock_http_send(
      conn, 200, "{\"code\":0,\"msg\":\"success\",\"data\":{\"items\":[]}}",
    )
  } else {
    mock_http_send(conn, 404, "{\"code\":99991672,\"msg\":\"not found\"}")
  }
}

///|
/// Read a request body (Content-Length or chunked; the MoonBit HTTP client
/// sends chunked). Same byte-accumulation rationale as the e2e mock server.
/// Shared with the other channel mock tests (channel_http_mock_wbtest.mbt).
async fn mock_http_read_body(
  conn : @socket.Tcp,
  headers : Map[String, String],
) -> String {
  let chunked = match headers.get("transfer-encoding") {
    Some(te) => te.to_lower().contains("chunked")
    None => false
  }
  if chunked {
    let chunks : Array[Bytes] = []
    let mut total = 0
    for ;; {
      let size_line = match conn.read_until("\r\n") {
        Some(l) => l.trim().to_owned()
        None => break
      }
      let size_hex = match size_line.split(";").collect() {
        [h, ..] => h.to_owned()
        _ => size_line
      }
      let size = mock_http_parse_hex(size_hex)
      if size <= 0 {
        for ;; {
          match conn.read_until("\r\n") {
            Some("") => break
            Some(_) => continue
            None => break
          }
        }
        break
      }
      let data = conn.read_exactly(size)
      chunks.push(data)
      total = total + size
      let _crlf = conn.read_exactly(2)
    }
    let buf : FixedArray[Byte] = FixedArray::make(total, b'\x00')
    let mut off = 0
    for c in chunks {
      for i in 0..<c.length() {
        buf[off + i] = c[i]
      }
      off = off + c.length()
    }
    return @utf8.decode(buf.unsafe_reinterpret_as_bytes()[:]) catch { _ => "" }
  }
  let length = match headers.get("content-length") {
    Some(v) => @string.parse_int(v) catch { _ => 0 }
    None => 0
  }
  if length <= 0 {
    return ""
  }
  let data = conn.read_exactly(length)
  @utf8.decode(data[:]) catch {
    _ => ""
  }
}

///|
fn mock_http_parse_hex(s : String) -> Int {
  let mut n = 0
  for c in s {
    let d = match c {
      '0'..='9' => c.to_int() - '0'.to_int()
      'a'..='f' => c.to_int() - 'a'.to_int() + 10
      'A'..='F' => c.to_int() - 'A'.to_int() + 10
      _ => return n
    }
    n = n * 16 + d
  }
  n
}

// ── Unit tests ────────────────────────────────────────────────────────────────

///|
async test "feishu_build_send_request_payload_shape" {
  let client = FeishuApiClient::with_base_url(
    "app", "secret", "https://open.feishu.cn/open-apis",
  )
  // Pre-seed the token cache so building requests never touches the network.
  client.token_cache.set("t-test", 7200_000)
  let (url, headers, body) = match
    client.build_send_request("oc_chat", "plain hello", None) {
    Ok(r) => r
    Err(_) => ("", [], "")
  }
  assert_true(
    url ==
    "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=chat_id",
  )
  assert_true(headers.length() >= 2)
  let json = @json.parse(body) catch {
    _ => {
      assert_true(false)
      Json::null()
    }
  }
  match json {
    Object(obj) => {
      assert_true(obj.get("receive_id") == Some("oc_chat".to_json()))
      assert_true(obj.get("msg_type") == Some("text".to_json()))
      // content must be a stringified JSON, not a nested object
      match obj.get("content") {
        Some(String(s)) => {
          let inner = @json.parse(s) catch {
            _ => {
              assert_true(false)
              Json::null()
            }
          }
          match inner {
            Object(io) =>
              assert_true(io.get("text") == Some("plain hello".to_json()))
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
async test "feishu_build_update_request_payload_shape" {
  let client = FeishuApiClient::with_base_url("app", "secret", FEISHU_API_BASE)
  client.token_cache.set("t-test", 7200_000)
  let (url, _headers, body) = match
    client.build_update_request("om_1", "edited") {
    Ok(r) => r
    Err(_) => ("", [], "")
  }
  assert_true(url == FEISHU_API_BASE + "/im/v1/messages/om_1")
  let json = @json.parse(body) catch {
    _ => {
      assert_true(false)
      Json::null()
    }
  }
  match json {
    Object(obj) =>
      match obj.get("content") {
        Some(String(s)) =>
          assert_true(s.contains("edited") && s.contains("text"))
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
async test "feishu_build_send_request_card_shape" {
  let client = FeishuApiClient::with_base_url("app", "secret", FEISHU_API_BASE)
  client.token_cache.set("t-test", 7200_000)
  let (_, _, body) = match
    client.build_send_request("oc_chat", "```code```", None) {
    Ok(r) => r
    Err(_) => ("", [], "")
  }
  let json = @json.parse(body) catch {
    _ => {
      assert_true(false)
      Json::null()
    }
  }
  match json {
    Object(obj) =>
      assert_true(obj.get("msg_type") == Some("interactive".to_json()))
    _ => assert_true(false)
  }
}

///|
test "feishu_multipart_body_preserves_binary" {
  let payload : Bytes = Bytes::from_array([b'\x89', b'P', b'N', b'G', 0, 1, 2])
  let body = build_feishu_multipart_body(
    "bnd",
    [("image_type", "message")],
    "image",
    "img.png",
    "application/octet-stream",
    payload,
  )
  let s = @utf8.decode_lossy(body)
  assert_true(s.contains("--bnd"))
  assert_true(s.contains("name=\"image_type\""))
  assert_true(s.contains("name=\"image\"; filename=\"img.png\""))
  // binary bytes survive byte-for-byte
  let mut found = false
  for i = 0; i <= body.length() - payload.length(); i = i + 1 {
    let mut ok = true
    for j = 0; j < payload.length(); j = j + 1 {
      if body[i + j] != payload[j] {
        ok = false
        break
      }
    }
    if ok {
      found = true
      break
    }
  }
  assert_true(found)
  assert_true(s.has_suffix("--bnd--\r\n"))
}

// ── Mock HTTP round-trip tests ────────────────────────────────────────────────

///|
async test "feishu_api_mock_round_trip_all_methods" {
  let server = MockFeishuServer::new()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let base = "http://127.0.0.1:\{server.port()}"
    let client = FeishuApiClient::with_base_url("app", "secret", base)
    // send_message
    let sent = client.send_message("oc_chat", "hello feishu", None)
    match sent {
      Ok(json) =>
        assert_true(extract_feishu_message_id(json) == Some("om_mock123"))
      Err(_) => assert_true(false)
    }
    // update_message
    match client.update_message("om_mock123", "edited") {
      Ok(_) => ()
      Err(_) => assert_true(false)
    }
    // delete_message (recall)
    match client.delete_message("om_mock123") {
      Ok(_) => ()
      Err(_) => assert_true(false)
    }
    // upload_image
    let img : Bytes = Bytes::from_array([b'\x89', b'P', b'N', b'G'])
    match client.upload_image("message", img) {
      Ok(key) => assert_true(key == "img_v2_mock")
      Err(_) => assert_true(false)
    }
    // upload_file
    match
      client.upload_file(
        "pdf",
        "doc.pdf",
        Bytes::from_array([b'P', b'D', b'F']),
      ) {
      Ok(key) => assert_true(key == "file_v2_mock")
      Err(_) => assert_true(false)
    }
    // download_resource (binary -> base64 round trip)
    match client.download_resource("om_mock123", "file_1", "image") {
      Ok(b64) => {
        let decoded = @base64.decode(b64) catch {
          _ => {
            assert_true(false)
            Bytes::from_array([])
          }
        }
        assert_true(@utf8.decode_lossy(decoded) == "hello-bytes")
      }
      Err(_) => assert_true(false)
    }
    // fetch_chat_history
    match client.fetch_chat_history("oc_chat", 20) {
      Ok(json) =>
        match json {
          Object(obj) =>
            match obj.get("data") {
              Some(_) => ()
              _ => assert_true(false)
            }
          _ => assert_true(false)
        }
      Err(_) => assert_true(false)
    }
    server.shutdown()
  })
  // auth + 7 API calls
  assert_true(server.requests.length() >= 8)
}

///|
async test "feishu_api_mock_business_error_surfaces" {
  let server = MockFeishuServer::new()
  server.fail_mode = true
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let base = "http://127.0.0.1:\{server.port()}"
    let client = FeishuApiClient::with_base_url("app", "secret", base)
    match client.send_message("oc_chat", "hi", None) {
      Ok(_) => assert_true(false)
      Err(ChannelError(msg)) => assert_true(msg.contains("token expired"))
    }
    server.shutdown()
  })
}

///|
/// WP-1.6: the adapter's recall path reaches the mock over a real socket.
async test "feishu_adapter_delete_message_mock_round_trip" {
  let server = MockFeishuServer::new()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let base = "http://127.0.0.1:\{server.port()}"
    let adapter : FeishuAdapter = {
      bot_id: "id",
      bot_secret: "secret",
      webhook_url: None,
      api_client: Some(FeishuApiClient::with_base_url("app", "secret", base)),
      is_running: true,
      message_callback: None,
    }
    match adapter.delete_message("oc_chat", "om_delete_1") {
      Ok(_) => ()
      Err(_) => assert_true(false)
    }
    assert_eq(server.requests.length(), 2) // auth + delete
    let (delete_line, _) = server.requests[1]
    assert_true(delete_line.contains("DELETE /im/v1/messages/om_delete_1"))
    server.shutdown()
  })
}
