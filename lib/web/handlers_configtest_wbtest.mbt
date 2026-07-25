///| White-box tests for handlers_configtest.mbt.
///
/// Covers the field-name-presence regression: missing-field 400 responses
/// must say WHICH field is missing, not a generic "required" message.
/// Tests focus on the short-circuit branch (validation), not the live
/// HTTP probe — that branch is exercised by the web UI / curl.

///|
/// POST /api/config/test with an empty body must return 400.
async test "config test rejects empty body" {
  let resp = handle_config_test(
    ex_make_server_ref(),
    ex_make_event(Post, "/api/config/test", body="{}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

///|
/// When api_key is missing the response must name it, not lump it with
/// base_url. The frontend uses this message to highlight the bad field.
async test "config test reports missing api_key by name" {
  let resp = handle_config_test(
    ex_make_server_ref(),
    ex_make_event(
      Post,
      "/api/config/test",
      body="{\"model\":\"m\",\"base_url\":\"https://api.x.com\"}",
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let body = ex_response_json(resp)
  let msg = ex_str_field(body, "message")
  assert_true(msg.contains("api_key"))
  assert_true(!msg.contains("base_url"))
}

///|
/// When base_url is missing the response must name only base_url.
async test "config test reports missing base_url by name" {
  let resp = handle_config_test(
    ex_make_server_ref(),
    ex_make_event(
      Post,
      "/api/config/test",
      body="{\"model\":\"m\",\"api_key\":\"k\"}",
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let msg = ex_str_field(ex_response_json(resp), "message")
  assert_true(msg.contains("base_url"))
  assert_true(!msg.contains("api_key"))
}

///|
/// When both are missing, both should appear in the message.
async test "config test lists all missing fields" {
  let resp = handle_config_test(
    ex_make_server_ref(),
    ex_make_event(Post, "/api/config/test", body="{\"model\":\"m\"}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let msg = ex_str_field(ex_response_json(resp), "message")
  assert_true(msg.contains("base_url"))
  assert_true(msg.contains("api_key"))
}

///|
/// Malformed JSON must still surface as a 400, not bypass the validator.
async test "config test rejects malformed JSON" {
  let resp = handle_config_test(
    ex_make_server_ref(),
    ex_make_event(Post, "/api/config/test", body="not json"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

///|
/// `has_version_suffix` is the heuristic that decides whether to append
/// `/v1/models` or just `/models` to a base URL. Volces Ark Coding Plan
/// uses `/api/coding/v3` (no /v1), and a naïve `has_suffix("/v1")` would
/// double the version segment. Coverage: positive, negative, edge.
test "has_version_suffix recognises /v1 /v3 /v10 with or without slash" {
  assert_true(has_version_suffix("https://api.x.com/v1"))
  assert_true(has_version_suffix("https://api.x.com/v3"))
  assert_true(has_version_suffix("https://api.x.com/v10"))
  assert_true(has_version_suffix("https://api.x.com/v1/"))
  assert_true(
    has_version_suffix("https://ark.cn-beijing.volces.com/api/coding/v3"),
  )
  assert_true(
    has_version_suffix("https://ark.cn-beijing.volces.com/api/coding/v3/"),
  )
  assert_true(has_version_suffix("https://api.deepseek.com/v1"))
  // capital V should also be recognised (some providers use it)
  assert_true(has_version_suffix("https://api.x.com/V2"))
}

///|
/// Negative cases for has_version_suffix: bare host, version-like
/// substring in the path, or a non-digit after the v.
test "has_version_suffix rejects non-version endings" {
  assert_false(has_version_suffix("https://api.x.com"))
  assert_false(has_version_suffix("https://api.x.com/"))
  assert_false(has_version_suffix("https://api.x.com/v1beta")) // not just digits
  assert_false(has_version_suffix("https://api.x.com/version")) // v + word
  assert_false(has_version_suffix("https://api.x.com/models")) // wrong segment
  assert_false(has_version_suffix("https://api.x.com/v")) // missing digit
  assert_false(has_version_suffix(""))
}

///|
/// strip_trailing_slash normalises URLs so we don't produce accidental
/// `//` segments when appending paths.
test "strip_trailing_slash removes single trailing slash" {
  assert_eq(strip_trailing_slash("https://x.com"), "https://x.com")
  assert_eq(strip_trailing_slash("https://x.com/"), "https://x.com")
  // Multiple trailing slashes are NOT all stripped — only one. That's
  // intentional: collapsing `//` is the upstream's job, and silently
  // fixing it could mask a misconfigured base URL.
  assert_eq(strip_trailing_slash("https://x.com//"), "https://x.com/")
}
