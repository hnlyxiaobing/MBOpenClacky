// ── dingtalk_supported_exts ─────────────────────────────────────────────────

///|
test "dingtalk_supported_exts" {
  let exts = dingtalk_supported_exts()
  assert_true(exts.contains("pdf"))
  assert_true(exts.contains("docx"))
  assert_true(exts.contains("xlsx"))
  assert_true(exts.contains("ppt"))
  assert_eq(exts.length(), 9)
}

// ── is_dingtalk_supported_ext ────────────────────────────────────────────────

///|
test "dingtalk_is_supported_ext_pdf" {
  assert_true(is_dingtalk_supported_ext("pdf"))
}

///|
test "dingtalk_is_supported_ext_docx" {
  assert_true(is_dingtalk_supported_ext("docx"))
}

///|
test "dingtalk_is_supported_ext_unsupported" {
  assert_false(is_dingtalk_supported_ext("mp4"))
  assert_false(is_dingtalk_supported_ext("txt"))
  assert_false(is_dingtalk_supported_ext(""))
}

// ── URL builders ─────────────────────────────────────────────────────────────

///|
test "dingtalk_access_token_url" {
  let client = DingTalkApiClient::new("key123", "secret456")
  assert_eq(
    client.access_token_url(),
    "https://api.dingtalk.com/v1.0/oauth2/accessToken",
  )
}

///|
test "dingtalk_build_oapi_token_request" {
  let client = DingTalkApiClient::new("key123", "secret456")
  assert_eq(
    client.build_oapi_token_request(),
    "https://oapi.dingtalk.com/gettoken?appkey=key123&appsecret=secret456",
  )
}

// ── build_access_token_request ──────────────────────────────────────────────

///|
test "dingtalk_build_access_token_request" {
  let client = DingTalkApiClient::new("key123", "secret456")
  let payload = client.build_access_token_request()
  match payload {
    Object(obj) => {
      match obj.get("appKey") {
        Some(String(s)) => assert_eq(s, "key123")
        _ => assert_true(false)
      }
      match obj.get("appSecret") {
        Some(String(s)) => assert_eq(s, "secret456")
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

// ── parse_token_response ──────────────────────────────────────────────────────

///|
test "dingtalk_parse_token_response_new_api" {
  let json_str = "{\"accessToken\":\"tok_abc\",\"expireIn\":7200}"
  let json = @json.parse(json_str) catch { _ => Json::object(Map([])) }
  let result = DingTalkApiClient::parse_token_response(json)
  match result {
    Ok((token, expire)) => {
      assert_eq(token, "tok_abc")
      assert_eq(expire, 7200)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "dingtalk_parse_token_response_new_api_default_expire" {
  let json_str = "{\"accessToken\":\"tok_def\"}"
  let json = @json.parse(json_str) catch { _ => Json::object(Map([])) }
  let result = DingTalkApiClient::parse_token_response(json)
  match result {
    Ok((token, expire)) => {
      assert_eq(token, "tok_def")
      assert_eq(expire, 7200)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "dingtalk_parse_token_response_oapi" {
  let json_str = "{\"access_token\":\"tok_xyz\",\"expires_in\":3600,\"errcode\":0,\"errmsg\":\"ok\"}"
  let json = @json.parse(json_str) catch { _ => Json::object(Map([])) }
  let result = DingTalkApiClient::parse_token_response(json)
  match result {
    Ok((token, expire)) => {
      assert_eq(token, "tok_xyz")
      assert_eq(expire, 3600)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "dingtalk_parse_token_response_oapi_error" {
  let json_str = "{\"access_token\":\"\",\"expires_in\":0,\"errcode\":-1,\"errmsg\":\"invalid appkey\"}"
  let json = @json.parse(json_str) catch { _ => Json::object(Map([])) }
  let result = DingTalkApiClient::parse_token_response(json)
  match result {
    Err(ChannelError(msg)) => assert_true(msg.contains("invalid appkey"))
    _ => assert_true(false)
  }
}

///|
test "dingtalk_parse_token_response_missing_token" {
  let json_str = "{\"other\":\"value\"}"
  let json = @json.parse(json_str) catch { _ => Json::object(Map([])) }
  let result = DingTalkApiClient::parse_token_response(json)
  assert_true(result is Err(_))
}

///|
test "dingtalk_parse_token_response_invalid_format" {
  let json = "42".to_json()
  let result = DingTalkApiClient::parse_token_response(json)
  assert_true(result is Err(_))
}

// ── build_webhook_payload ──────────────────────────────────────────────────────

///|
test "dingtalk_build_webhook_payload_text" {
  let payload = DingTalkApiClient::build_webhook_payload("Hello", "text")
  match payload {
    Object(obj) => {
      match obj.get("msgtype") {
        Some(String(s)) => assert_eq(s, "text")
        _ => assert_true(false)
      }
      match obj.get("text") {
        Some(Object(text_obj)) =>
          match text_obj.get("content") {
            Some(String(s)) => assert_eq(s, "Hello")
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "dingtalk_build_webhook_payload_markdown" {
  let payload = DingTalkApiClient::build_webhook_payload("**Bold**", "markdown")
  match payload {
    Object(obj) =>
      match obj.get("msgtype") {
        Some(String(s)) => assert_eq(s, "markdown")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "dingtalk_build_webhook_payload_default_to_text" {
  let payload = DingTalkApiClient::build_webhook_payload("test", "unknown_type")
  match payload {
    Object(obj) =>
      match obj.get("msgtype") {
        Some(String(s)) => assert_eq(s, "text")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

// ── build_send_msg_param ───────────────────────────────────────────────────────

///|
test "dingtalk_build_send_msg_param_sample_text" {
  let param_str = DingTalkApiClient::build_send_msg_param(
    "sampleText", "Hello World",
  )
  let json = @json.parse(param_str) catch { _ => Json::object(Map([])) }
  match json {
    Object(obj) =>
      match obj.get("content") {
        Some(String(s)) => assert_eq(s, "Hello World")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "dingtalk_build_send_msg_param_sample_markdown" {
  let param_str = DingTalkApiClient::build_send_msg_param(
    "sampleMarkdown", "# Title",
  )
  let json = @json.parse(param_str) catch { _ => Json::object(Map([])) }
  match json {
    Object(obj) => {
      match obj.get("title") {
        Some(String(s)) => assert_eq(s, "AI Assistant")
        _ => assert_true(false)
      }
      match obj.get("text") {
        Some(String(s)) => assert_eq(s, "# Title")
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "dingtalk_build_send_msg_param_sample_action_card" {
  let param_str = DingTalkApiClient::build_send_msg_param(
    "sampleActionCard", "Card content",
  )
  let json = @json.parse(param_str) catch { _ => Json::object(Map([])) }
  match json {
    Object(obj) => {
      match obj.get("title") {
        Some(String(s)) => assert_eq(s, "AI Assistant")
        _ => assert_true(false)
      }
      match obj.get("markdown") {
        Some(String(s)) => assert_eq(s, "Card content")
        _ => assert_true(false)
      }
      match obj.get("singleTitle") {
        Some(String(s)) => assert_eq(s, "查看详情")
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "dingtalk_build_send_msg_param_default" {
  let param_str = DingTalkApiClient::build_send_msg_param(
    "unknownKey", "Fallback",
  )
  let json = @json.parse(param_str) catch { _ => Json::object(Map([])) }
  match json {
    Object(obj) =>
      match obj.get("content") {
        Some(String(s)) => assert_eq(s, "Fallback")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

// ── build_upload_request ──────────────────────────────────────────────────────

///|
test "dingtalk_build_upload_request_file" {
  let payload = DingTalkApiClient::build_upload_request("report.pdf")
  match payload {
    Object(obj) => {
      match obj.get("filename") {
        Some(String(s)) => assert_eq(s, "report.pdf")
        _ => assert_true(false)
      }
      match obj.get("mediaType") {
        Some(String(s)) => assert_eq(s, "file")
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "dingtalk_build_upload_request_image" {
  let payload = DingTalkApiClient::build_upload_request("photo.jpg")
  match payload {
    Object(obj) =>
      match obj.get("mediaType") {
        Some(String(s)) => assert_eq(s, "image")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "dingtalk_build_upload_request_png_image" {
  let payload = DingTalkApiClient::build_upload_request("icon.png")
  match payload {
    Object(obj) =>
      match obj.get("mediaType") {
        Some(String(s)) => assert_eq(s, "image")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "dingtalk_build_upload_request_voice" {
  let payload = DingTalkApiClient::build_upload_request("audio.mp3")
  match payload {
    Object(obj) =>
      match obj.get("mediaType") {
        Some(String(s)) => assert_eq(s, "voice")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "dingtalk_build_upload_request_video" {
  let payload = DingTalkApiClient::build_upload_request("clip.mp4")
  match payload {
    Object(obj) =>
      match obj.get("mediaType") {
        Some(String(s)) => assert_eq(s, "video")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "dingtalk_build_upload_request_no_extension" {
  let payload = DingTalkApiClient::build_upload_request("noext")
  match payload {
    Object(obj) =>
      match obj.get("mediaType") {
        Some(String(s)) => assert_eq(s, "file")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}
