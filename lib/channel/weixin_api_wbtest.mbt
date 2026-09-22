// ── URL builders ─────────────────────────────────────────────────────────────

///|
test "weixin_api_get_updates_url" {
  let client = WeixinApiClient::new("tok", "uin123")
  assert_eq(
    client.get_updates_url(None),
    "https://ilinkai.weixin.qq.com/cgi-bin/mmfinderassistantbin/getupdates",
  )
}

///|
test "weixin_api_get_updates_url_trailing_slash" {
  let client = {
    token: "tok",
    uin: "uin",
    base_url: "https://example.com/",
    cdn_base: WEIXIN_CDN_BASE,
  }
  assert_eq(
    client.get_updates_url(None),
    "https://example.com/cgi-bin/mmfinderassistantbin/getupdates",
  )
}

///|
test "weixin_api_send_text_url" {
  let client = WeixinApiClient::new("tok", "uin")
  assert_eq(
    client.send_text_url(),
    "https://ilinkai.weixin.qq.com/cgi-bin/mmfinderassistantbin/sendmessage",
  )
}

///|
test "weixin_api_send_typing_url" {
  let client = WeixinApiClient::new("tok", "uin")
  assert_eq(
    client.send_typing_url(),
    "https://ilinkai.weixin.qq.com/cgi-bin/mmfinderassistantbin/sendtyping",
  )
}

///|
test "weixin_api_get_upload_url" {
  let client = WeixinApiClient::new("tok", "uin")
  assert_eq(
    client.get_upload_url(),
    "https://ilinkai.weixin.qq.com/cgi-bin/mmfinderassistantbin/getuploadurl",
  )
}

///|
test "weixin_api_download_media_url" {
  let client = WeixinApiClient::new("tok", "uin")
  assert_eq(
    client.download_media_url("file_abc"),
    "https://novac2c.cdn.weixin.qq.com/c2c/download/file_abc",
  )
}

///|
test "weixin_api_download_media_url_trailing_slash" {
  let client = {
    token: "tok",
    uin: "uin",
    base_url: WEIXIN_API_BASE,
    cdn_base: "https://cdn.example.com/",
  }
  assert_eq(
    client.download_media_url("f"),
    "https://cdn.example.com/download/f",
  )
}

// ── build_get_updates_request ────────────────────────────────────────────────

///|
test "weixin_api_build_get_updates_request_with_buf" {
  let client = WeixinApiClient::new("tok", "uin")
  let payload = client.build_get_updates_request(Some("cursor123"))
  match payload {
    Object(obj) => {
      match obj.get("timeout") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 40)
        _ => assert_true(false)
      }
      match obj.get("buf") {
        Some(String(s)) => assert_eq(s, "cursor123")
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "weixin_api_build_get_updates_request_no_buf" {
  let client = WeixinApiClient::new("tok", "uin")
  let payload = client.build_get_updates_request(None)
  match payload {
    Object(obj) =>
      match obj.get("buf") {
        Some(String(s)) => assert_eq(s, "")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

// ── build_send_text_request ──────────────────────────────────────────────────

///|
test "weixin_api_build_send_text_request" {
  let client = WeixinApiClient::new("tok", "uin")
  let payload = client.build_send_text_request("user1", "Hello", "ctx_token")
  match payload {
    Object(obj) => {
      match obj.get("to_user_name") {
        Some(String(s)) => assert_eq(s, "user1")
        _ => assert_true(false)
      }
      match obj.get("context_token") {
        Some(String(s)) => assert_eq(s, "ctx_token")
        _ => assert_true(false)
      }
      match obj.get("msg_type") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 1)
        _ => assert_true(false)
      }
      match obj.get("text_item") {
        Some(Object(ti)) =>
          match ti.get("text") {
            Some(String(s)) => assert_eq(s, "Hello")
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

// ── build_typing_request ──────────────────────────────────────────────────────

///|
test "weixin_api_build_typing_request" {
  let client = WeixinApiClient::new("tok", "uin")
  let payload = client.build_typing_request("user1", 1)
  match payload {
    Object(obj) => {
      match obj.get("to_user_name") {
        Some(String(s)) => assert_eq(s, "user1")
        _ => assert_true(false)
      }
      match obj.get("typing_status") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 1)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

// ── build_upload_request ─────────────────────────────────────────────────────

///|
test "weixin_api_build_upload_request" {
  let client = WeixinApiClient::new("tok", "uin")
  let payload = client.build_upload_request(1, 102400)
  match payload {
    Object(obj) => {
      match obj.get("media_type") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 1)
        _ => assert_true(false)
      }
      match obj.get("file_size") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 102400)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

// ── parse_get_updates_response ───────────────────────────────────────────────

///|
test "weixin_api_parse_get_updates_success" {
  let client = WeixinApiClient::new("tok", "uin")
  let json_str = "{\"ret\":0,\"item_list\":[{\"msg\":\"hello\"}],\"buf\":\"next_cursor\"}"
  let json = @json.parse(json_str) catch { _ => Json::object(Map([])) }
  let result = client.parse_get_updates_response(json)
  match result {
    Ok((messages, next_buf)) => {
      assert_eq(messages.length(), 1)
      assert_true(next_buf is Some("next_cursor"))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "weixin_api_parse_get_updates_empty_buf" {
  let client = WeixinApiClient::new("tok", "uin")
  let json_str = "{\"ret\":0,\"item_list\":[],\"buf\":\"\"}"
  let json = @json.parse(json_str) catch { _ => Json::object(Map([])) }
  let result = client.parse_get_updates_response(json)
  match result {
    Ok((messages, next_buf)) => {
      assert_eq(messages.length(), 0)
      assert_true(next_buf is None)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "weixin_api_parse_get_updates_no_buf" {
  let client = WeixinApiClient::new("tok", "uin")
  let json_str = "{\"ret\":0,\"item_list\":[]}"
  let json = @json.parse(json_str) catch { _ => Json::object(Map([])) }
  let result = client.parse_get_updates_response(json)
  match result {
    Ok((_, next_buf)) => assert_true(next_buf is None)
    Err(_) => assert_true(false)
  }
}

///|
test "weixin_api_parse_get_updates_error" {
  let client = WeixinApiClient::new("tok", "uin")
  let json_str = "{\"ret\":-1,\"errmsg\":\"Invalid token\"}"
  let json = @json.parse(json_str) catch { _ => Json::object(Map([])) }
  let result = client.parse_get_updates_response(json)
  match result {
    Err(ChannelError(msg)) => assert_true(msg.contains("Invalid token"))
    _ => assert_true(false)
  }
}

///|
test "weixin_api_parse_get_updates_invalid_format" {
  let client = WeixinApiClient::new("tok", "uin")
  let json = "not_object".to_json()
  let result = client.parse_get_updates_response(json)
  assert_true(result is Err(_))
}

// ── parse_send_response ──────────────────────────────────────────────────────

///|
test "weixin_api_parse_send_response_success" {
  let client = WeixinApiClient::new("tok", "uin")
  let json_str = "{\"ret\":0,\"msg_id\":\"msg_123\"}"
  let json = @json.parse(json_str) catch { _ => Json::object(Map([])) }
  let result = client.parse_send_response(json)
  match result {
    Ok((msg_id, ret_code)) => {
      assert_eq(msg_id, "msg_123")
      assert_eq(ret_code, 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "weixin_api_parse_send_response_error" {
  let client = WeixinApiClient::new("tok", "uin")
  let json_str = "{\"ret\":-2,\"msg_id\":\"\"}"
  let json = @json.parse(json_str) catch { _ => Json::object(Map([])) }
  let result = client.parse_send_response(json)
  match result {
    Ok((msg_id, ret_code)) => {
      assert_eq(msg_id, "")
      assert_eq(ret_code, -2)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "weixin_api_parse_send_response_invalid_format" {
  let client = WeixinApiClient::new("tok", "uin")
  let json = "42".to_json()
  let result = client.parse_send_response(json)
  assert_true(result is Err(_))
}

// ── detect_weixin_aes_mode ───────────────────────────────────────────────────

///|
test "weixin_aes_mode_short_header" {
  assert_eq(detect_weixin_aes_mode("ab"), Inbound)
}

///|
test "weixin_aes_mode_short_header_3" {
  assert_eq(detect_weixin_aes_mode("abc"), Inbound)
}

///|
test "weixin_aes_mode_long_header_non_image" {
  assert_eq(detect_weixin_aes_mode("Hello World!"), Inbound)
}

// ── build_weixin_aes_key ──────────────────────────────────────────────────────

///|
test "weixin_build_aes_key_long" {
  let aes_key = "0123456789abcdef0123456789abcdef"
  let (key_hex, iv_hex) = build_weixin_aes_key(aes_key)
  assert_eq(key_hex, "0123456789abcdef0123456789abcdef")
  assert_eq(iv_hex, "0123456789abcdef0123456789abcdef")
}

///|
test "weixin_build_aes_key_short" {
  let (key_hex, iv_hex) = build_weixin_aes_key("short")
  assert_eq(key_hex, "short")
  assert_eq(iv_hex, "")
}

///|
test "weixin_build_aes_key_empty" {
  let (key_hex, iv_hex) = build_weixin_aes_key("")
  assert_eq(key_hex, "")
  assert_eq(iv_hex, "")
}

// ── weixin_media_requires_encryption ─────────────────────────────────────────

///|
test "weixin_media_requires_encryption_non_empty" {
  assert_true(weixin_media_requires_encryption("some_key"))
}

///|
test "weixin_media_requires_encryption_empty" {
  assert_false(weixin_media_requires_encryption(""))
}

// ── AES-128-ECB (WP-1.4) ─────────────────────────────────────────────────────

///|
/// Hex-decode a test buffer literal of any even length, failing the test when
/// the literal is malformed. `raise` because `assert_true` can abort the test.
fn aes_test_bytes(hex : String) -> Bytes raise {
  if hex.length() % 2 != 0 {
    assert_true(false)
    return Bytes::from_array([])
  }
  let out : Array[Byte] = []
  let mut high = -1
  for c in hex {
    let digit = match hex_digit_value(c) {
      Some(d) => d
      None => {
        assert_true(false)
        return Bytes::from_array([])
      }
    }
    if high < 0 {
      high = digit
    } else {
      out.push((high * 16 + digit).to_byte())
      high = -1
    }
  }
  Bytes::from_array(out)
}

///|
/// AES key used by the FIPS-197 §C.1 vector.
fn aes_test_key() -> Bytes raise {
  aes_test_bytes("000102030405060708090a0b0c0d0e0f")
}

///|
/// FIPS-197 §C.1 AES-128 example vector, through the padding-free block path:
/// key 000102...0f, plaintext 00112233...ff -> ciphertext 69c4e0d8...c55a.
test "weixin_aes_ecb_fips197_vector" {
  let key = aes_test_key()
  let plain = aes_test_bytes("00112233445566778899aabbccddeeff")
  let cipher = match weixin_aes_ecb_encrypt(key, plain) {
    Ok(c) => c
    Err(_) => {
      assert_true(false)
      Bytes::from_array([])
    }
  }
  assert_eq(
    @crypto.bytes_to_hex_string(cipher),
    "69c4e0d86a7b0430d8cdb78070b4c55a",
  )
  let back = match weixin_aes_ecb_decrypt(key, cipher) {
    Ok(b) => b
    Err(_) => {
      assert_true(false)
      Bytes::from_array([])
    }
  }
  assert_eq(
    @crypto.bytes_to_hex_string(back),
    "00112233445566778899aabbccddeeff",
  )
}

///|
test "weixin_aes_key_from_hex_rejects_wrong_length" {
  assert_true(weixin_aes_key_from_hex("short") is Err(_))
  assert_true(weixin_aes_key_from_hex("") is Err(_))
  // 33 chars
  assert_true(
    weixin_aes_key_from_hex("000102030405060708090a0b0c0d0e0f00") is Err(_),
  )
}

///|
test "weixin_aes_key_from_hex_rejects_non_hex" {
  let result = weixin_aes_key_from_hex("zz0102030405060708090a0b0c0d0e0f")
  match result {
    Err(ChannelError(msg)) => assert_true(msg.contains("Invalid hex digit"))
    _ => assert_true(false)
  }
}

///|
test "weixin_aes_ecb_rejects_unaligned_data" {
  let key = aes_test_key()
  // 17 bytes: not a multiple of the AES block size
  let odd = aes_test_bytes("00112233445566778899aabbccddeeff00")
  assert_eq(odd.length(), 17)
  assert_true(weixin_aes_ecb_encrypt(key, odd) is Err(_))
}

///|
test "weixin_aes_ecb_rejects_short_key" {
  let short_key = aes_test_bytes("000102030405060708090a0b0c0d0e") // 15 bytes
  let block = aes_test_bytes("00112233445566778899aabbccddeeff")
  assert_true(weixin_aes_ecb_encrypt(short_key, block) is Err(_))
}

// ── PKCS#7 padding ───────────────────────────────────────────────────────────

///|
test "pkcs7_pad_appends_full_block_when_aligned" {
  let block = aes_test_bytes("00112233445566778899aabbccddeeff")
  let padded = pkcs7_pad(block)
  assert_eq(padded.length(), 32)
  assert_eq(padded[padded.length() - 1].to_int(), 16)
}

///|
test "pkcs7_pad_fills_partial_block" {
  let partial = aes_test_bytes("00112233445566778899aabbccddee") // 15 bytes
  let padded = pkcs7_pad(partial)
  assert_eq(padded.length(), 16)
  assert_eq(padded[15].to_int(), 1)
}

///|
test "pkcs7_unpad_round_trips" {
  let partial = aes_test_bytes("00112233445566778899aabbccddee")
  let back = match pkcs7_unpad(pkcs7_pad(partial)) {
    Ok(b) => b
    Err(_) => {
      assert_true(false)
      Bytes::from_array([])
    }
  }
  assert_eq(@crypto.bytes_to_hex_string(back), "00112233445566778899aabbccddee")
}

///|
test "pkcs7_unpad_rejects_malformed_padding" {
  // last byte claims 5 pad bytes but the preceding byte disagrees
  let bad = aes_test_bytes("00112233445566778899aabbccddee03")
  assert_true(pkcs7_unpad(bad) is Err(_))
  // pad length 0 is invalid
  let zero = aes_test_bytes("00112233445566778899aabbccddee00")
  assert_true(pkcs7_unpad(zero) is Err(_))
  // not block-aligned
  assert_true(pkcs7_unpad(aes_test_bytes("00112233")) is Err(_))
  assert_true(pkcs7_unpad(Bytes::from_array([])) is Err(_))
}

// ── AES round trip with padding ──────────────────────────────────────────────

///|
test "weixin_aes_encrypt_decrypt_round_trip" {
  let key = aes_test_key()
  let plain = @utf8.encode("weixin media payload crossing the block boundary")
  let cipher = match weixin_aes_encrypt(plain, key) {
    Ok(c) => c
    Err(_) => {
      assert_true(false)
      Bytes::from_array([])
    }
  }
  // PKCS#7 always adds padding, so the ciphertext is longer than the input
  assert_true(cipher.length() > plain.length())
  assert_eq(cipher.length() % 16, 0)
  let back = match weixin_aes_decrypt(cipher, key) {
    Ok(b) => b
    Err(_) => {
      assert_true(false)
      Bytes::from_array([])
    }
  }
  assert_eq(
    @utf8.decode_lossy(back),
    "weixin media payload crossing the block boundary",
  )
}

///|
test "weixin_aes_decrypt_rejects_non_multiple_ciphertext" {
  let key = aes_test_key()
  let truncated = aes_test_bytes("00112233445566778899aabbccddee")
  assert_true(weixin_aes_decrypt(truncated, key) is Err(_))
}
