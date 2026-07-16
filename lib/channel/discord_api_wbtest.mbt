///|
test "discord_api_url_default_base" {
  let client = DiscordApiClient::new("token123")
  let url = client.api_url("/channels/123/messages")
  assert_eq(url, "https://discord.com/api/v10/channels/123/messages")
}

///|
test "discord_api_url_path_without_slash" {
  let client = DiscordApiClient::new("token123")
  let url = client.api_url("channels/456/messages")
  assert_eq(url, "https://discord.com/api/v10/channels/456/messages")
}

///|
test "discord_api_url_custom_base_no_trailing_slash" {
  let client = DiscordApiClient::with_base_url(
    "tok", "https://custom.example.com/api",
  )
  let url = client.api_url("/users/@me")
  assert_eq(url, "https://custom.example.com/api/users/@me")
}

///|
test "discord_api_url_custom_base_with_trailing_slash" {
  let client = DiscordApiClient::with_base_url(
    "tok", "https://custom.example.com/api/",
  )
  let url = client.api_url("/users/@me")
  assert_eq(url, "https://custom.example.com/api/users/@me")
}

///|
test "discord_api_url_strips_leading_slash_from_path" {
  let client = DiscordApiClient::with_base_url("tok", "https://example.com")
  let url = client.api_url("/gateway")
  assert_eq(url, "https://example.com/gateway")
}

// ── build_discord_send_payload ─────────────────────────────────────────────

///|
test "discord_send_payload_no_reply" {
  let payload = build_discord_send_payload("Hello Discord", None)
  match payload {
    Object(obj) => {
      match obj.get("content") {
        Some(String(s)) => assert_eq(s, "Hello Discord")
        _ => assert_true(false)
      }
      assert_true(obj.get("message_reference") is None)
    }
    _ => assert_true(false)
  }
}

///|
test "discord_send_payload_with_reply" {
  let payload = build_discord_send_payload("Reply text", Some("msg123"))
  match payload {
    Object(obj) => {
      match obj.get("content") {
        Some(String(s)) => assert_eq(s, "Reply text")
        _ => assert_true(false)
      }
      match obj.get("message_reference") {
        Some(Object(ref_obj)) =>
          match ref_obj.get("message_id") {
            Some(String(id)) => assert_eq(id, "msg123")
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "discord_send_payload_empty_content" {
  let payload = build_discord_send_payload("", None)
  match payload {
    Object(obj) =>
      match obj.get("content") {
        Some(String(s)) => assert_eq(s, "")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "discord_send_payload_unicode_content" {
  let payload = build_discord_send_payload("你好 🎉", None)
  match payload {
    Object(obj) =>
      match obj.get("content") {
        Some(String(s)) => assert_eq(s, "你好 🎉")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

// ── build_discord_edit_payload ──────────────────────────────────────────────

///|
test "discord_edit_payload_basic" {
  let payload = build_discord_edit_payload("Edited content")
  match payload {
    Object(obj) =>
      match obj.get("content") {
        Some(String(s)) => assert_eq(s, "Edited content")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "discord_edit_payload_has_only_content" {
  let payload = build_discord_edit_payload("test")
  match payload {
    Object(obj) => {
      assert_true(obj.get("content") is Some(_))
      assert_true(obj.get("message_reference") is None)
    }
    _ => assert_true(false)
  }
}

///|
test "discord_edit_payload_empty_content" {
  let payload = build_discord_edit_payload("")
  match payload {
    Object(obj) =>
      match obj.get("content") {
        Some(String(s)) => assert_eq(s, "")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}
