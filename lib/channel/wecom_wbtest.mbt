///|
test "verify_hex_escape_length" {
  let s = "\xFF"
  assert_true(s.length() == 1)
}

///|
test "verify_hex_escape_value" {
  let s = "\xFF\xD8\xFF\x00"
  assert_true(s[0].to_int() == 255)
  assert_true(s[1].to_int() == 216)
  assert_true(s[2].to_int() == 255)
}

// ── needs_aes_decrypt ──────────────────────────────────────────────────────

///|
test "needs_aes_decrypt_jpeg" {
  assert_false(needs_aes_decrypt("\xFF\xD8\xFF\x00"))
}

///|
test "needs_aes_decrypt_png" {
  assert_false(needs_aes_decrypt("\x89PNG\x00\x00\x00"))
}

///|
test "needs_aes_decrypt_gif" {
  assert_false(needs_aes_decrypt("GIF89a"))
}

///|
test "needs_aes_decrypt_bmp" {
  assert_false(needs_aes_decrypt("BM\x00\x00"))
}

///|
test "needs_aes_decrypt_riff_webp" {
  assert_false(needs_aes_decrypt("RIFF\x00\x00\x00\x00WEBP"))
}

///|
test "needs_aes_decrypt_unknown_returns_true" {
  assert_true(needs_aes_decrypt("test\x00"))
}

///|
test "needs_aes_decrypt_short_string_returns_true" {
  assert_true(needs_aes_decrypt("ab"))
  assert_true(needs_aes_decrypt(""))
  assert_true(needs_aes_decrypt("abc"))
}

// ── detect_mime_type ───────────────────────────────────────────────────────

///|
test "detect_mime_type_jpeg" {
  assert_eq(detect_mime_type("\xFF\xD8\xFF\xE0"), "image/jpeg")
}

///|
test "detect_mime_type_png" {
  assert_eq(detect_mime_type("\x89PNG\r\n\x1a\n"), "image/png")
}

///|
test "detect_mime_type_gif" {
  assert_eq(detect_mime_type("GIF89a"), "image/gif")
}

///|
test "detect_mime_type_bmp" {
  assert_eq(detect_mime_type("BM\x00"), "image/bmp")
}

///|
test "detect_mime_type_webp" {
  assert_eq(detect_mime_type("RIFF\x00\x00\x00\x00WEBP"), "image/webp")
}

///|
test "detect_mime_type_riff_not_webp" {
  assert_eq(
    detect_mime_type("RIFF\x00\x00\x00\x00XXXX"),
    "application/octet-stream",
  )
}

///|
test "detect_mime_type_pdf" {
  assert_eq(detect_mime_type("%PDF-1.4"), "application/pdf")
}

///|
test "detect_mime_type_unknown" {
  assert_eq(detect_mime_type("test\x00\x00"), "application/octet-stream")
}

///|
test "detect_mime_type_short_string" {
  assert_eq(detect_mime_type("a"), "application/octet-stream")
  assert_eq(detect_mime_type(""), "application/octet-stream")
}

// ── parse_wecom_text ───────────────────────────────────────────────────────

///|
test "parse_wecom_text_pascal_case" {
  let msg : Map[String, Json] = { "Content": "Hello WeCom".to_json() }
  assert_eq(parse_wecom_text(msg), "Hello WeCom")
}

///|
test "parse_wecom_text_snake_case" {
  let msg : Map[String, Json] = { "content": "Hello snake".to_json() }
  assert_eq(parse_wecom_text(msg), "Hello snake")
}

///|
test "parse_wecom_text_nested_json" {
  let inner : Map[String, Json] = { "content": "Nested text".to_json() }
  let msg : Map[String, Json] = { "text": Json::object(inner) }
  assert_eq(parse_wecom_text(msg), "Nested text")
}

///|
test "parse_wecom_text_empty_msg" {
  let msg : Map[String, Json] = Map([])
  assert_eq(parse_wecom_text(msg), "")
}

///|
test "parse_wecom_text_non_string_value" {
  let msg : Map[String, Json] = { "Content": (42).to_json() }
  assert_eq(parse_wecom_text(msg), "")
}

// ── detect_wecom_chat_type ─────────────────────────────────────────────────

///|
test "detect_chat_type_group_string" {
  let msg : Map[String, Json] = { "ChatType": "group".to_json() }
  assert_eq(detect_wecom_chat_type(msg), Group)
}

///|
test "detect_chat_type_group_numeric_string" {
  let msg : Map[String, Json] = { "ChatType": "2".to_json() }
  assert_eq(detect_wecom_chat_type(msg), Group)
}

///|
test "detect_chat_type_direct_string" {
  let msg : Map[String, Json] = { "ChatType": "single".to_json() }
  assert_eq(detect_wecom_chat_type(msg), Direct)
}

///|
test "detect_chat_type_snake_case_group" {
  let msg : Map[String, Json] = { "chat_type": "group".to_json() }
  assert_eq(detect_wecom_chat_type(msg), Group)
}

///|
test "detect_chat_type_numeric_type_field" {
  let msg : Map[String, Json] = { "Type": (2).to_json() }
  assert_eq(detect_wecom_chat_type(msg), Group)
}

///|
test "detect_chat_type_chat_id_with_at" {
  let msg : Map[String, Json] = { "ChatId": "wrXXXXX@im".to_json() }
  assert_eq(detect_wecom_chat_type(msg), Group)
}

///|
test "detect_chat_type_default_direct" {
  let msg : Map[String, Json] = Map([])
  assert_eq(detect_wecom_chat_type(msg), Direct)
}

// ── wecom_is_mentioned ──────────────────────────────────────────────────────

///|
test "wecom_is_mentioned_at_list_match" {
  let at_obj : Map[String, Json] = { "userid": "bot123".to_json() }
  let msg : Map[String, Json] = {
    "at_list": Json::array([Json::object(at_obj)]),
  }
  assert_true(wecom_is_mentioned(msg, "bot123"))
}

///|
test "wecom_is_mentioned_at_list_no_match" {
  let at_obj : Map[String, Json] = { "userid": "other_user".to_json() }
  let msg : Map[String, Json] = {
    "at_list": Json::array([Json::object(at_obj)]),
  }
  assert_false(wecom_is_mentioned(msg, "bot123"))
}

///|
test "wecom_is_mentioned_content_pascal" {
  let msg : Map[String, Json] = { "Content": "Hello @bot123".to_json() }
  assert_true(wecom_is_mentioned(msg, "bot123"))
}

///|
test "wecom_is_mentioned_content_snake" {
  let msg : Map[String, Json] = { "content": "Hey @bot123".to_json() }
  assert_true(wecom_is_mentioned(msg, "bot123"))
}

///|
test "wecom_is_mentioned_no_mention" {
  let msg : Map[String, Json] = { "Content": "Just a message".to_json() }
  assert_false(wecom_is_mentioned(msg, "bot123"))
}

///|
test "wecom_is_mentioned_empty_msg" {
  let msg : Map[String, Json] = Map([])
  assert_false(wecom_is_mentioned(msg, "bot123"))
}
