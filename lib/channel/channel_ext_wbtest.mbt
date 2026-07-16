///| Extended channel tests: DingTalk API client, token parsing, supported extensions.

// ── dingtalk_supported_exts Tests ──────────────────────────────────────────

///|
test "ext_dingtalk_supported_exts_count" {
  let exts = dingtalk_supported_exts()
  assert_eq(exts.length(), 9)
}

///|
test "ext_dingtalk_supported_exts_contains" {
  let exts = dingtalk_supported_exts()
  assert_true(exts.contains("pdf"))
  assert_true(exts.contains("docx"))
  assert_true(exts.contains("xlsx"))
  assert_true(exts.contains("zip"))
  assert_true(exts.contains("rar"))
}

///|
test "ext_dingtalk_supported_exts_not_contains" {
  let exts = dingtalk_supported_exts()
  assert_false(exts.contains("exe"))
  assert_false(exts.contains("mp4"))
}

// ── DingTalkApiClient Construction Tests ───────────────────────────────────

///|
test "ext_dingtalk_client_new" {
  let client = DingTalkApiClient::new("app-key-123", "app-secret-456")
  assert_eq(client.app_key, "app-key-123")
  assert_eq(client.app_secret, "app-secret-456")
}

///|
test "ext_dingtalk_client_new_empty" {
  let client = DingTalkApiClient::new("", "")
  assert_eq(client.app_key, "")
  assert_eq(client.app_secret, "")
}

// ── access_token_url Tests ─────────────────────────────────────────────────

///|
test "ext_dingtalk_access_token_url" {
  let client = DingTalkApiClient::new("key", "secret")
  let url = client.access_token_url()
  assert_true(url.contains("accessToken"))
  assert_true(url.contains("oauth2"))
}

// ── build_oapi_token_request Tests ─────────────────────────────────────────

///|
test "ext_dingtalk_oapi_token_request_contains_credentials" {
  let client = DingTalkApiClient::new("my-key", "my-secret")
  let url = client.build_oapi_token_request()
  assert_true(url.contains("appkey=my-key"))
  assert_true(url.contains("appsecret=my-secret"))
}

///|
test "ext_dingtalk_oapi_token_request_contains_endpoint" {
  let client = DingTalkApiClient::new("k", "s")
  let url = client.build_oapi_token_request()
  assert_true(url.contains("gettoken"))
}

// ── build_access_token_request Tests ────────────────────────────────────────

///|
test "ext_dingtalk_build_access_token_request" {
  let client = DingTalkApiClient::new("k", "s")
  let json = client.build_access_token_request()
  match json {
    Object(obj) => {
      assert_eq(obj.get("appKey"), Some("k".to_json()))
      assert_eq(obj.get("appSecret"), Some("s".to_json()))
    }
    _ => assert_true(false)
  }
}

// ── parse_token_response Tests ──────────────────────────────────────────────

///|
test "ext_dingtalk_parse_token_new_api" {
  let json = @json.parse("{\"accessToken\":\"token123\",\"expireIn\":3600}") catch {
    _ => Json::object({})
  }
  let result = DingTalkApiClient::parse_token_response(json)
  match result {
    Ok((token, expire)) => {
      assert_eq(token, "token123")
      assert_eq(expire, 3600)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "ext_dingtalk_parse_token_oapi" {
  let json_str = "{\"access_token\":\"tok456\",\"expires_in\":7200,\"errcode\":0}"
  let json = @json.parse(json_str) catch { _ => Json::object({}) }
  let result = DingTalkApiClient::parse_token_response(json)
  match result {
    Ok((token, expire)) => {
      assert_eq(token, "tok456")
      assert_eq(expire, 7200)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "ext_dingtalk_parse_token_default_expire" {
  let json = @json.parse("{\"accessToken\":\"tok789\"}") catch {
    _ => Json::object({})
  }
  let result = DingTalkApiClient::parse_token_response(json)
  match result {
    Ok((_, expire)) => assert_eq(expire, 7200)
    Err(_) => assert_true(false)
  }
}

///|
test "ext_dingtalk_parse_token_invalid_json" {
  let json = @json.parse("123") catch { _ => Json::object({}) }
  let result = DingTalkApiClient::parse_token_response(json)
  assert_true(result is Err(_))
}

///|
test "ext_dingtalk_parse_token_missing_token" {
  let json = @json.parse("{\"foo\":\"bar\"}") catch { _ => Json::object({}) }
  let result = DingTalkApiClient::parse_token_response(json)
  assert_true(result is Err(_))
}

///|
test "ext_dingtalk_parse_token_empty_object" {
  let json = Json::object({})
  let result = DingTalkApiClient::parse_token_response(json)
  assert_true(result is Err(_))
}

// ── Additional dingtalk_supported_exts Tests ────────────────────────────────

///|
test "ext_dingtalk_exts_all_nonempty" {
  for ext in dingtalk_supported_exts() {
    assert_true(ext.length() > 0)
  }
}

///|
test "ext_dingtalk_exts_no_duplicates" {
  let exts = dingtalk_supported_exts()
  let seen : Array[String] = []
  for ext in exts {
    assert_false(seen.contains(ext))
    seen.push(ext)
  }
}

// ── Additional DingTalkApiClient Tests ───────────────────────────────────────

///|
test "ext_dingtalk_client_special_chars" {
  let client = DingTalkApiClient::new("key-with-dash", "secret!@#")
  assert_eq(client.app_key, "key-with-dash")
}

///|
test "ext_dingtalk_client_long_credentials" {
  let long_key = "a".repeat(100)
  let client = DingTalkApiClient::new(long_key, "secret")
  assert_eq(client.app_key, long_key)
}

///|
test "ext_dingtalk_access_token_url_format" {
  let client = DingTalkApiClient::new("k", "s")
  let url = client.access_token_url()
  assert_true(url.has_prefix("http"))
}

///|
test "ext_dingtalk_oapi_request_full_check" {
  let client = DingTalkApiClient::new("key1", "secret1")
  let url = client.build_oapi_token_request()
  assert_true(url.contains("http"))
  assert_true(url.contains("gettoken"))
  assert_true(url.contains("appkey=key1"))
  assert_true(url.contains("appsecret=secret1"))
}

// ── Additional parse_token_response Tests ──────────────────────────────────

///|
test "ext_dingtalk_parse_token_with_errcode" {
  let json_str = "{\"access_token\":\"tok\",\"expires_in\":3600,\"errcode\":0,\"errmsg\":\"ok\"}"
  let json = @json.parse(json_str) catch { _ => Json::object({}) }
  let result = DingTalkApiClient::parse_token_response(json)
  match result {
    Ok((token, _)) => assert_eq(token, "tok")
    Err(_) => assert_true(false)
  }
}

///|
test "ext_dingtalk_parse_token_string_value" {
  let json = @json.parse("\"just a string\"") catch { _ => Json::object({}) }
  assert_true(DingTalkApiClient::parse_token_response(json) is Err(_))
}

///|
test "ext_dingtalk_parse_token_array_value" {
  let json = @json.parse("[1,2,3]") catch { _ => Json::object({}) }
  assert_true(DingTalkApiClient::parse_token_response(json) is Err(_))
}

///|
test "ext_dingtalk_parse_token_null_value" {
  let json = @json.parse("null") catch { _ => Json::object({}) }
  assert_true(DingTalkApiClient::parse_token_response(json) is Err(_))
}
