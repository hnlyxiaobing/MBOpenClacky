///|
test "telegram_api_url" {
  let client = TelegramApiClient::new("tok123")
  assert_eq(client.api_url("getMe"), "https://api.telegram.org/bottok123/getMe")
}

///|
test "telegram_get_me_url" {
  let client = TelegramApiClient::new("tok123")
  assert_eq(client.get_me_url(), "https://api.telegram.org/bottok123/getMe")
}

///|
test "telegram_get_updates_url" {
  let client = TelegramApiClient::new("tok456")
  assert_eq(
    client.get_updates_url(),
    "https://api.telegram.org/bottok456/getUpdates",
  )
}

///|
test "telegram_send_message_url" {
  let client = TelegramApiClient::new("tok789")
  assert_eq(
    client.send_message_url(),
    "https://api.telegram.org/bottok789/sendMessage",
  )
}

///|
test "telegram_edit_message_url" {
  let client = TelegramApiClient::new("tok111")
  assert_eq(
    client.edit_message_url(),
    "https://api.telegram.org/bottok111/editMessageText",
  )
}

///|
test "telegram_get_file_url" {
  let client = TelegramApiClient::new("tok222")
  assert_eq(client.get_file_url(), "https://api.telegram.org/bottok222/getFile")
}

///|
test "telegram_delete_message_url" {
  let client = TelegramApiClient::new("tok333")
  assert_eq(
    client.delete_message_url(),
    "https://api.telegram.org/bottok333/deleteMessage",
  )
}

// ── get_updates_payload ────────────────────────────────────────────────────

///|
test "telegram_get_updates_payload" {
  let client = TelegramApiClient::new("tok")
  let payload = client.get_updates_payload(100, 30)
  match payload {
    Object(obj) => {
      match obj.get("offset") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 100)
        _ => assert_true(false)
      }
      match obj.get("timeout") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 30)
        _ => assert_true(false)
      }
      match obj.get("allowed_updates") {
        Some(Array(arr)) => assert_eq(arr.length(), 0)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

// ── parse_updates_response ──────────────────────────────────────────────────

///|
test "telegram_parse_updates_success" {
  let json_str = "{\"ok\":true,\"result\":[{\"update_id\":1},{\"update_id\":2}]}"
  let json = @json.parse(json_str) catch { _ => Json::object({}) }
  let result = TelegramApiClient::parse_updates_response(json)
  match result {
    Ok(arr) => assert_eq(arr.length(), 2)
    Err(_) => assert_true(false)
  }
}

///|
test "telegram_parse_updates_empty_result" {
  let json_str = "{\"ok\":true,\"result\":[]}"
  let json = @json.parse(json_str) catch { _ => Json::object({}) }
  let result = TelegramApiClient::parse_updates_response(json)
  match result {
    Ok(arr) => assert_eq(arr.length(), 0)
    Err(_) => assert_true(false)
  }
}

///|
test "telegram_parse_updates_api_error" {
  let json_str = "{\"ok\":false,\"description\":\"Unauthorized\"}"
  let json = @json.parse(json_str) catch { _ => Json::object({}) }
  let result = TelegramApiClient::parse_updates_response(json)
  match result {
    Err(ChannelError(msg)) => assert_eq(msg, "Unauthorized")
    _ => assert_true(false)
  }
}

///|
test "telegram_parse_updates_invalid_format" {
  let json = "not_an_object".to_json()
  let result = TelegramApiClient::parse_updates_response(json)
  assert_true(result is Err(_))
}

// ── parse_send_response ─────────────────────────────────────────────────────

///|
test "telegram_parse_send_response_success" {
  let json_str = "{\"ok\":true,\"result\":{\"message_id\":42}}"
  let json = @json.parse(json_str) catch { _ => Json::object({}) }
  let result = TelegramApiClient::parse_send_response(json)
  match result {
    Ok(sr) => {
      assert_eq(sr.message_id, "42")
      assert_true(sr.success)
      assert_true(sr.error is None)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "telegram_parse_send_response_api_error" {
  let json_str = "{\"ok\":false,\"description\":\"Chat not found\"}"
  let json = @json.parse(json_str) catch { _ => Json::object({}) }
  let result = TelegramApiClient::parse_send_response(json)
  match result {
    Err(ChannelError(msg)) => assert_eq(msg, "Chat not found")
    _ => assert_true(false)
  }
}

///|
test "telegram_parse_send_response_invalid_format" {
  let json = "42".to_json()
  let result = TelegramApiClient::parse_send_response(json)
  assert_true(result is Err(_))
}

// ── parse_ok_response ───────────────────────────────────────────────────────

///|
test "telegram_parse_ok_response_success" {
  let json_str = "{\"ok\":true}"
  let json = @json.parse(json_str) catch { _ => Json::object({}) }
  let result = TelegramApiClient::parse_ok_response(json)
  match result {
    Ok(b) => assert_true(b)
    Err(_) => assert_true(false)
  }
}

///|
test "telegram_parse_ok_response_error" {
  let json_str = "{\"ok\":false,\"description\":\"Bad request\"}"
  let json = @json.parse(json_str) catch { _ => Json::object({}) }
  let result = TelegramApiClient::parse_ok_response(json)
  match result {
    Err(ChannelError(msg)) => assert_eq(msg, "Bad request")
    _ => assert_true(false)
  }
}

///|
test "telegram_parse_ok_response_invalid_format" {
  let json = "42".to_json()
  let result = TelegramApiClient::parse_ok_response(json)
  assert_true(result is Err(_))
}

// ── extract_update_id ───────────────────────────────────────────────────────

///|
test "telegram_extract_update_id" {
  let update : Map[String, Json] = { "update_id": (12345).to_json() }
  assert_eq(extract_update_id(update), 12345)
}

///|
test "telegram_extract_update_id_missing_returns_zero" {
  let update : Map[String, Json] = Map([])
  assert_eq(extract_update_id(update), 0)
}

///|
test "telegram_extract_update_id_non_number_returns_zero" {
  let update : Map[String, Json] = { "update_id": "abc".to_json() }
  assert_eq(extract_update_id(update), 0)
}

// ── detect_chat_type ────────────────────────────────────────────────────────

///|
test "telegram_detect_chat_type_private" {
  let chat : Map[String, Json] = { "type": "private".to_json() }
  let msg : Map[String, Json] = { "chat": Json::object(chat) }
  assert_eq(detect_chat_type(msg), Direct)
}

///|
test "telegram_detect_chat_type_group" {
  let chat : Map[String, Json] = { "type": "group".to_json() }
  let msg : Map[String, Json] = { "chat": Json::object(chat) }
  assert_eq(detect_chat_type(msg), Group)
}

///|
test "telegram_detect_chat_type_supergroup" {
  let chat : Map[String, Json] = { "type": "supergroup".to_json() }
  let msg : Map[String, Json] = { "chat": Json::object(chat) }
  assert_eq(detect_chat_type(msg), Group)
}

///|
test "telegram_detect_chat_type_no_chat_field" {
  let msg : Map[String, Json] = Map([])
  assert_eq(detect_chat_type(msg), Direct)
}

///|
test "telegram_detect_chat_type_no_type_field" {
  let chat : Map[String, Json] = Map([])
  let msg : Map[String, Json] = { "chat": Json::object(chat) }
  assert_eq(detect_chat_type(msg), Direct)
}

// ── build_telegram_send_request ─────────────────────────────────────────────

///|
test "telegram_build_send_request_basic" {
  let payload = build_telegram_send_request("123", "Hello", None, None)
  match payload {
    Object(obj) => {
      match obj.get("chat_id") {
        Some(String(s)) => assert_eq(s, "123")
        _ => assert_true(false)
      }
      match obj.get("text") {
        Some(String(s)) => assert_eq(s, "Hello")
        _ => assert_true(false)
      }
      assert_true(obj.get("reply_to_message_id") is None)
      assert_true(obj.get("parse_mode") is None)
    }
    _ => assert_true(false)
  }
}

///|
test "telegram_build_send_request_with_reply" {
  let payload = build_telegram_send_request("456", "Reply", Some("100"), None)
  match payload {
    Object(obj) =>
      match obj.get("reply_to_message_id") {
        Some(String(s)) => assert_eq(s, "100")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "telegram_build_send_request_with_parse_mode" {
  let payload = build_telegram_send_request(
    "789",
    "**Bold**",
    None,
    Some("Markdown"),
  )
  match payload {
    Object(obj) =>
      match obj.get("parse_mode") {
        Some(String(s)) => assert_eq(s, "Markdown")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "telegram_build_send_request_full" {
  let payload = build_telegram_send_request(
    "999",
    "text",
    Some("50"),
    Some("HTML"),
  )
  match payload {
    Object(obj) => {
      assert_true(obj.get("chat_id") is Some(_))
      assert_true(obj.get("text") is Some(_))
      assert_true(obj.get("reply_to_message_id") is Some(_))
      assert_true(obj.get("parse_mode") is Some(_))
    }
    _ => assert_true(false)
  }
}

// ── build_telegram_edit_request ──────────────────────────────────────────────

///|
test "telegram_build_edit_request" {
  let payload = build_telegram_edit_request("123", "456", "Edited text")
  match payload {
    Object(obj) => {
      match obj.get("chat_id") {
        Some(String(s)) => assert_eq(s, "123")
        _ => assert_true(false)
      }
      match obj.get("message_id") {
        Some(String(s)) => assert_eq(s, "456")
        _ => assert_true(false)
      }
      match obj.get("text") {
        Some(String(s)) => assert_eq(s, "Edited text")
        _ => assert_true(false)
      }
      match obj.get("parse_mode") {
        Some(String(s)) => assert_eq(s, "Markdown")
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}
