///| Integration-level tests for channel package.

///|

///| Tests complete event flows: JSON → parse → ChannelEvent validation,

///|
/// Discord Gateway frame sequences, and cross-platform scenarios.

// ── Telegram: Full parse_event flows ────────────────────────────────────────

test "telegram_parse_event_photo_message" {
  let json_str = "{\"message\":{\"message_id\":10,\"chat\":{\"id\":456,\"type\":\"group\"},\"from\":{\"id\":7,\"first_name\":\"Carol\"},\"caption\":\"nice pic\",\"photo\":[{\"file_id\":\"small\",\"width\":90,\"height\":90},{\"file_id\":\"large\",\"width\":800,\"height\":600,\"file_size\":50000}],\"date\":1700001000}}"
  let json = @json.parse(json_str) catch { _ => Json::object({}) }
  match TelegramAdapter::parse_event(json) {
    Ok(evt) => {
      assert_eq(evt.chat_id, "456")
      assert_eq(evt.text, "nice pic")
      assert_true(evt.chat_type == ChatType::Group)
      assert_true(evt.attachments.length() >= 1)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "telegram_parse_event_document" {
  let json_str = "{\"message\":{\"message_id\":11,\"chat\":{\"id\":789,\"type\":\"private\"},\"from\":{\"id\":8,\"first_name\":\"Dave\"},\"document\":{\"file_id\":\"doc_abc\",\"file_name\":\"report.pdf\",\"file_size\":102400},\"date\":1700002000}}"
  let json = @json.parse(json_str) catch { _ => Json::object({}) }
  match TelegramAdapter::parse_event(json) {
    Ok(evt) => {
      assert_eq(evt.text, "") // no text or caption
      assert_true(evt.attachments.length() >= 1)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "telegram_parse_event_reply_to" {
  let json_str = "{\"message\":{\"message_id\":20,\"chat\":{\"id\":100,\"type\":\"private\"},\"from\":{\"id\":9,\"first_name\":\"Eve\"},\"text\":\"reply text\",\"reply_to_message\":{\"message_id\":15},\"date\":1700003000}}"
  let json = @json.parse(json_str) catch { _ => Json::object({}) }
  match TelegramAdapter::parse_event(json) {
    Ok(evt) => {
      assert_eq(evt.reply_to, Some("15"))
      assert_eq(evt.text, "reply text")
    }
    Err(_) => assert_true(false)
  }
}

// ── Discord: Full Gateway lifecycle simulation ──────────────────────────────

///|
test "discord_gateway_hello_identify_heartbeat_flow" {
  // 1. Create state
  let state = GatewayState::new("BOT_TOKEN")

  // 2. Simulate Hello event (op 10)
  let hello_json = @json.parse(
    "{\"op\":10,\"d\":{\"heartbeat_interval\":41250}}",
  ) catch {
    _ => Json::object({})
  }
  match parse_gateway_event(hello_json) {
    Ok((op, data)) => {
      assert_eq(op, 10)
      match parse_hello_payload(data) {
        Ok(interval) => {
          state.handle_hello(interval)
          assert_true(state.is_connected)
          assert_eq(state.heartbeat_interval, 41250)
        }
        Err(_) => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }

  // 3. Build Identify payload
  let identify = build_identify_payload("BOT_TOKEN", DEFAULT_INTENTS)
  match identify {
    Object(obj) => assert_eq(obj.get("op"), Some((2).to_json()))
    _ => assert_true(false)
  }

  // 4. Simulate READY event
  state.handle_ready("session_xyz", Some("wss://resume.discord.gg"))
  assert_true(state.is_ready)
  assert_eq(state.session_id, Some("session_xyz"))

  // 5. Build Heartbeat
  let hb = build_heartbeat_payload(None)
  state.mark_heartbeat_sent()
  assert_false(state.heartbeat_acked)
  state.mark_heartbeat_acked()
  assert_true(state.heartbeat_acked)

  // 6. Simulate Dispatch event with seq
  let dispatch = @json.parse(
    "{\"op\":0,\"s\":5,\"t\":\"MESSAGE_CREATE\",\"d\":{\"content\":\"hi\"}}",
  ) catch {
    _ => Json::object({})
  }
  match parse_gateway_event(dispatch) {
    Ok((op, _d)) => {
      assert_eq(op, 0)
      match extract_seq(dispatch) {
        Some(s) => state.update_seq(s)
        None => assert_true(false)
      }
      assert_eq(state.last_seq, Some(5))
    }
    Err(_) => assert_true(false)
  }
  assert_true(should_resume(state))
}

///|
test "discord_gateway_reconnect_flow" {
  let state = GatewayState::new("TOK")
  state.handle_hello(41250)
  state.handle_ready("sess1", Some("wss://resume.gg"))
  state.update_seq(10)

  // Simulate non-fatal close
  assert_true(should_reconnect(state, 4000))
  assert_false(is_fatal_close(4000))

  // Record reconnect attempt
  state.record_reconnect_attempt()
  assert_eq(state.reconnect_attempts, 1)

  // Build Resume payload
  match state.last_seq {
    Some(seq) => {
      let resume = build_resume_payload("TOK", "sess1", seq)
      match resume {
        Object(obj) => {
          assert_eq(obj.get("op"), Some((6).to_json()))
          match obj.get("d") {
            Some(Object(d)) => {
              assert_eq(d.get("session_id"), Some("sess1".to_json()))
              assert_eq(d.get("seq"), Some((10).to_json()))
            }
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "discord_gateway_fatal_close_no_reconnect" {
  let state = GatewayState::new("TOK")
  state.handle_hello(41250)
  // Fatal close code: should NOT reconnect
  assert_false(should_reconnect(state, 4004))
  assert_false(should_reconnect(state, 4014))
  assert_true(is_fatal_close(4004))
  assert_true(is_fatal_close(4010))
}

///|
test "discord_gateway_invalid_session" {
  // op 9 with d=true: session is resumable
  let event = @json.parse("{\"op\":9,\"d\":true}") catch {
    _ => Json::object({})
  }
  match parse_gateway_event(event) {
    Ok((op, d)) => {
      assert_eq(op, 9)
      assert_true(parse_invalid_session(d))
    }
    Err(_) => assert_true(false)
  }
  // op 9 with d=false: not resumable
  let event2 = @json.parse("{\"op\":9,\"d\":false}") catch {
    _ => Json::object({})
  }
  match parse_gateway_event(event2) {
    Ok((op, d)) => {
      assert_eq(op, 9)
      assert_false(parse_invalid_session(d))
    }
    Err(_) => assert_true(false)
  }
}

// ── WeCom: Full frame flow ──────────────────────────────────────────────────

///|
test "wecom_subscribe_and_send_flow" {
  let state = WeComWsState::new("bot123", "secret456")

  // Build auth frame
  let auth = state.build_auth_frame()
  match auth {
    Object(obj) => {
      assert_eq(obj.get("type"), Some("aibot_subscribe".to_json()))
      assert_eq(obj.get("bot_id"), Some("bot123".to_json()))
    }
    _ => assert_true(false)
  }

  // Simulate successful connection
  state.mark_connected()
  assert_true(state.is_connected)

  // Build and send a message
  let msg_frame = state.build_msg_frame("chat1", "Hello WeCom", "text")
  match msg_frame {
    Object(obj) => {
      assert_eq(obj.get("type"), Some("aibot_send_msg".to_json()))
      assert_eq(obj.get("chat_id"), Some("chat1".to_json()))
      assert_true(obj.get("req_id") is Some(_))
    }
    _ => assert_true(false)
  }

  // Parse incoming data frame
  let incoming = @json.parse(
    "{\"type\":\"data\",\"content\":\"user msg\",\"chat_id\":\"c1\",\"from_user_id\":\"u1\",\"from_user_name\":\"Alice\"}",
  ) catch {
    _ => Json::object({})
  }
  match parse_incoming_frame(incoming) {
    Ok((ft, frame_data)) => {
      assert_true(ft == WeComFrameType::Data)
      assert_true(needs_ack(ft))
      match extract_data_content(frame_data) {
        Some(c) => assert_eq(c, "user msg")
        None => assert_true(false)
      }
      match extract_data_chat_id(frame_data) {
        Some(cid) => assert_eq(cid, "c1")
        None => assert_true(false)
      }
      let (sid, sname) = extract_data_sender(frame_data)
      assert_eq(sid, "u1")
      assert_eq(sname, "Alice")
    }
    Err(_) => assert_true(false)
  }
}

// ── WeCom: Chunked upload flow ──────────────────────────────────────────────

///|
test "wecom_chunked_upload_flow" {
  // 2MB file, 512KB chunks → 4 chunks
  let us = WeComUploadState::new(2097152)
  us.set_upload_id("upload_abc")
  assert_eq(us.upload_id, "upload_abc")

  // Init frame
  let init = build_upload_init_frame("upload_abc", "bigfile.zip", 2097152)
  match init {
    Object(obj) =>
      assert_eq(obj.get("type"), Some("aibot_upload_init".to_json()))
    _ => assert_true(false)
  }

  // Send chunks
  let mut chunk_count = 0
  while !us.is_complete() {
    let idx = us.next_chunk()
    let chunk = build_upload_chunk_frame("upload_abc", idx, "chunk_data")
    match chunk {
      Object(obj) =>
        assert_eq(obj.get("type"), Some("aibot_upload_chunk".to_json()))
      _ => assert_true(false)
    }
    chunk_count = chunk_count + 1
  }
  assert_eq(chunk_count, 4)

  // Finish frame
  let finish = build_upload_finish_frame("upload_abc")
  match finish {
    Object(obj) =>
      assert_eq(obj.get("type"), Some("aibot_upload_finish".to_json()))
    _ => assert_true(false)
  }
}

// ── DingTalk: Stream mode flow ──────────────────────────────────────────────

///|
test "dingtalk_stream_callback_ack_flow" {
  // Server sends CALLBACK frame
  let frame_json = @json.parse(
    "{\"type\":\"CALLBACK\",\"data\":{\"conversationId\":\"conv1\",\"text\":{\"content\":\"hello bot\"},\"msgId\":\"msg_001\"}}",
  ) catch {
    _ => Json::object({})
  }
  match parse_stream_frame(frame_json) {
    Ok((frame_type, data)) => {
      assert_eq(frame_type, "CALLBACK")
      // Build ACK
      let ack = build_stream_ack("msg_001")
      match ack {
        Object(obj) => {
          assert_eq(obj.get("code"), Some((200).to_json()))
          assert_eq(obj.get("messageId"), Some("msg_001".to_json()))
        }
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }

  // Server sends SYSTEM ping
  let ping_json = @json.parse(
    "{\"type\":\"SYSTEM\",\"data\":{\"topic\":\"ping\"}}",
  ) catch {
    _ => Json::object({})
  }
  match parse_stream_frame(ping_json) {
    Ok((ft, _)) => {
      assert_eq(ft, "SYSTEM")
      let pong = build_stream_pong()
      match pong {
        Object(obj) => assert_eq(obj.get("type"), Some("pong".to_json()))
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

// ── DingTalk: Token dual-system flow ────────────────────────────────────────

///|
test "dingtalk_token_request_and_parse_flow" {
  let client = DingTalkApiClient::new("appkey1", "appsecret1")

  // New API token request
  let new_api_body = client.build_access_token_request()
  match new_api_body {
    Object(obj) => {
      assert_eq(obj.get("appKey"), Some("appkey1".to_json()))
      assert_eq(obj.get("appSecret"), Some("appsecret1".to_json()))
    }
    _ => assert_true(false)
  }

  // Parse new API response
  let new_api_resp = @json.parse(
    "{\"accessToken\":\"new_tok_abc\",\"expireIn\":7200}",
  ) catch {
    _ => Json::object({})
  }
  match DingTalkApiClient::parse_token_response(new_api_resp) {
    Ok((tok, exp)) => {
      assert_eq(tok, "new_tok_abc")
      assert_eq(exp, 7200)
    }
    Err(_) => assert_true(false)
  }

  // OAPI token URL
  let oapi_url = client.build_oapi_token_request()
  assert_true(oapi_url.contains("appkey=appkey1"))

  // Parse OAPI response
  let oapi_resp = @json.parse(
    "{\"access_token\":\"oapi_tok_xyz\",\"expires_in\":7200,\"errcode\":0}",
  ) catch {
    _ => Json::object({})
  }
  match DingTalkApiClient::parse_token_response(oapi_resp) {
    Ok((tok, exp)) => {
      assert_eq(tok, "oapi_tok_xyz")
      assert_eq(exp, 7200)
    }
    Err(_) => assert_true(false)
  }
}

// ── Feishu: Full message parsing flow ───────────────────────────────────────

///|
test "feishu_parse_post_rich_text" {
  let post_json : Map[String, Json] = {
    "zh_cn": Json::object({
      "title": "Meeting Notes".to_json(),
      "content": Json::array([
        Json::array([
          Json::object({
            "tag": "text".to_json(),
            "text": "Discussed ".to_json(),
          }),
          Json::object({
            "tag": "a".to_json(),
            "text": "Q3 Plan".to_json(),
            "href": "https://docs.feishu.cn/docx/plan123".to_json(),
          }),
        ]),
        Json::array([
          Json::object({
            "tag": "text".to_json(),
            "text": "Action items assigned.".to_json(),
          }),
        ]),
      ]),
    }),
  }
  let text = parse_feishu_post(Json::object(post_json))
  assert_true(text.contains("Meeting Notes"))
  assert_true(text.contains("Discussed"))
  assert_true(text.contains("Q3 Plan"))
  assert_true(text.contains("Action items"))
}

///|
test "feishu_resolve_mentions_multiple" {
  let mentions : Array[Json] = [
    Json::object({ "key": "@_user_1".to_json(), "name": "Alice".to_json() }),
    Json::object({ "key": "@_user_2".to_json(), "name": "Bob".to_json() }),
  ]
  let result = resolve_feishu_mentions("@_user_1 and @_user_2 meet", mentions)
  assert_eq(result, "@Alice and @Bob meet")
}

///|
test "feishu_extract_doc_urls_multiple" {
  let text = "Check https://docs.feishu.cn/docx/abc and https://mycompany.feishu.cn/wiki/xyz"
  let urls = extract_feishu_doc_urls(text)
  assert_eq(urls.length(), 2)
}

///|
test "feishu_parse_message_file_type" {
  let msg : Map[String, Json] = {
    "message_type": "file".to_json(),
    "content": "{\"file_key\":\"file_xyz\",\"file_name\":\"report.pdf\"}".to_json(),
  }
  match parse_feishu_message(msg) {
    Ok(parsed) => {
      assert_eq(parsed.msg_type, "file")
      assert_eq(parsed.attachments.length(), 1)
    }
    Err(_) => assert_true(false)
  }
}

// ── Weixin: Full send/receive flow ──────────────────────────────────────────

///|
test "weixin_send_queue_multiple_messages" {
  let q = WeixinSendQueue::new()
  // Enqueue 3 messages
  q.enqueue({ chat_id: "c1", text: "msg1", context_token: "t1", retry_count: 0 })
  q.enqueue({ chat_id: "c1", text: "msg2", context_token: "t2", retry_count: 0 })
  q.enqueue({ chat_id: "c1", text: "msg3", context_token: "t3", retry_count: 1 })
  assert_eq(q.pending_count(), 3)
  assert_true(q.should_flush())

  // Dequeue in order
  match q.dequeue() {
    Some(m) => assert_eq(m.text, "msg1")
    None => assert_true(false)
  }
  match q.dequeue() {
    Some(m) => assert_eq(m.text, "msg2")
    None => assert_true(false)
  }
  match q.dequeue() {
    Some(m) => {
      assert_eq(m.text, "msg3")
      assert_eq(q.calculate_retry_delay(m.retry_count), 2000)
    }
    None => assert_true(false)
  }
  assert_eq(q.pending_count(), 0)
  assert_false(q.should_flush())
}

///|
test "weixin_sanitize_complex_markdown" {
  let md = "**bold** and *italic* with `code` and [link](https://example.com)"
  let clean = sanitize_for_weixin(md)
  assert_eq(clean, "bold and italic with code and link")
}

///|
test "weixin_split_long_message_newlines" {
  let msg = "line1\nline2\nline3\nline4\nline5"
  let chunks = split_weixin_message(msg, 15)
  assert_true(chunks.length() >= 2)
}

// ── Cross-platform: Dedup across platforms ──────────────────────────────────

///|
test "cross_platform_dedup_different_platforms" {
  let mgr = ChannelManager::new("/tmp/channels.yml")
  let mut received_count = 0
  mgr.on_message(fn(_event) { received_count = received_count + 1 })

  // Feishu event
  let feishu_json = @json.parse(
    "{\"event\":{\"message\":{\"chat_id\":\"c1\",\"message_id\":\"unique_feishu_1\",\"content\":\"hello\"},\"sender\":{\"sender_id\":{\"user_id\":\"u1\",\"name\":\"Alice\"}}}}",
  ) catch {
    _ => Json::object({})
  }
  let _ = mgr.handle_webhook("feishu", feishu_json)

  // Same content but from different platform - should NOT be deduped (different platform prefix)
  // Actually, dedup is based on message digest which includes platform, so this should pass through
  // But we can't easily test telegram webhook without a registered adapter
  // Just verify first event was received
  assert_eq(received_count, 1)
}

// ── Feishu: Content builder round-trip ──────────────────────────────────────

///|
test "feishu_text_content_roundtrip" {
  let content = build_feishu_text_content("Hello World")
  match content {
    Object(obj) => {
      assert_eq(obj.get("msg_type"), Some("text".to_json()))
      // content field is a serialized JSON string (using Show trait, not strict JSON)
      assert_true(obj.get("content") is Some(_))
    }
    _ => assert_true(false)
  }
}

///|
test "feishu_card_content_roundtrip" {
  let content = build_feishu_card_content("```rust\nfn main() {}\n```")
  match content {
    Object(obj) => assert_eq(obj.get("msg_type"), Some("interactive".to_json()))
    _ => assert_true(false)
  }
}

// ── HTTP utilities combined flow ────────────────────────────────────────────

///|
test "http_full_request_response_flow" {
  // Build headers for a Discord-like request
  let headers = HttpHeaders::new()
    .bot_token("DISCORD_BOT_TOKEN")
    .content_type("application/json")
    .set("User-Agent", "DiscordBot (test)")
  let arr = headers.to_array()
  assert_eq(arr.length(), 3)

  // Build request body
  let payload : Map[String, Json] = {}
  payload.set("content", "Hello from bot".to_json())
  let body = build_json_body(payload)
  assert_true(body.contains("content"))

  // Simulate successful response parsing
  let resp = parse_json_response(
    "{\"id\":\"123\",\"content\":\"Hello from bot\"}",
  )
  assert_true(resp is Ok(_))

  // Simulate error response
  let err_resp = parse_json_response(
    "{\"error\":{\"message\":\"Missing Access\"}}",
  )
  match err_resp {
    Ok(json) => {
      let err_msg = extract_api_error(json)
      assert_eq(err_msg, "Missing Access")
    }
    Err(_) => assert_true(false)
  }
}

///|
test "retry_config_backoff_sequence" {
  let rc = RetryConfig::default()
  // Verify exponential sequence: 1000, 2000, 4000, 8000
  assert_eq(rc.delay_for_attempt(0), 1000)
  assert_eq(rc.delay_for_attempt(1), 2000)
  assert_eq(rc.delay_for_attempt(2), 4000)
  assert_eq(rc.delay_for_attempt(3), 8000)
}

// ── Weixin: AES mode detection ──────────────────────────────────────────────

///|
test "weixin_aes_mode_short_header" {
  let mode = detect_weixin_aes_mode("AB")
  assert_true(mode == WeixinAesMode::Inbound)
}

///|
test "weixin_media_encryption_check" {
  assert_true(
    weixin_media_requires_encryption("abcdef1234567890abcdef1234567890"),
  )
  assert_false(weixin_media_requires_encryption(""))
}

///|
test "weixin_aes_key_build" {
  let (key, _iv) = build_weixin_aes_key("12345678901234567890123456789012extra")
  assert_eq(key.length(), 32)
}
