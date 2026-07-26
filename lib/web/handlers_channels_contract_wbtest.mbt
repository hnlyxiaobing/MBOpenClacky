///| White-box tests for channels platform-specific fields (web-ui2-05).

///|
test "channels list: platform-specific fields present for each platform" {
  let req = HttpRequest::new(GET, "/api/channels")
  let resp = handle_channels_list(req)
  @debug.assert_eq(resp.status, 200)
  let parsed = @json.parse(resp.body)
  match parsed {
    Object(top) =>
      match top.get("channels") {
        Some(Array(items)) => {
          @debug.assert_eq(items.length(), 6)
          for item in items {
            match item {
              Object(o) => {
                let platform = match o.get("platform") {
                  Some(String(s)) => s
                  _ => panic()
                }
                // Base fields preserved for every platform.
                assert_true(o.get("enabled") is Some(_))
                assert_true(o.get("running") is Some(_))
                assert_true(o.get("has_config") is Some(_))
                // Platform-specific field keys.
                match platform {
                  "feishu" => {
                    assert_true(o.get("app_id") is Some(_))
                    assert_true(o.get("domain") is Some(_))
                    assert_true(o.get("allowed_users") is Some(_))
                  }
                  "wecom" => assert_true(o.get("bot_id") is Some(_))
                  "weixin" => {
                    assert_true(o.get("base_url") is Some(_))
                    assert_true(o.get("has_token") is Some(_))
                    assert_true(o.get("token_updated_at") is Some(_))
                  }
                  "discord" => {
                    assert_true(o.get("allowed_users") is Some(_))
                    assert_true(o.get("has_token") is Some(_))
                  }
                  "telegram" => {
                    assert_true(o.get("allowed_users") is Some(_))
                    assert_true(o.get("has_token") is Some(_))
                  }
                  "dingtalk" => {
                    assert_true(o.get("allowed_users") is Some(_))
                    assert_true(o.get("has_token") is Some(_))
                  }
                  _ => panic()
                }
              }
              _ => panic()
            }
          }
        }
        _ => panic()
      }
    _ => panic()
  }
}

///|
test "channels list: has_token is boolean, never plaintext token key" {
  let req = HttpRequest::new(GET, "/api/channels")
  let resp = handle_channels_list(req)
  let body = resp.body
  // No plaintext "token":"..." key — only has_token booleans.
  assert_false(body.contains("\"token\":"))
  // has_token must be a JSON boolean, not a string.
  let parsed = @json.parse(body)
  match parsed {
    Object(top) =>
      match top.get("channels") {
        Some(Array(items)) =>
          for item in items {
            match item {
              Object(o) =>
                match o.get("has_token") {
                  Some(True) => ()
                  Some(False) => ()
                  None => ()
                  _ => panic()
                }
              _ => panic()
            }
          }
        _ => panic()
      }
    _ => panic()
  }
}

///|
test "channels list: allowed_users is an array for feishu/discord/telegram" {
  let req = HttpRequest::new(GET, "/api/channels")
  let resp = handle_channels_list(req)
  let parsed = @json.parse(resp.body)
  match parsed {
    Object(top) =>
      match top.get("channels") {
        Some(Array(items)) =>
          for item in items {
            match item {
              Object(o) => {
                let platform = match o.get("platform") {
                  Some(String(s)) => s
                  _ => panic()
                }
                match platform {
                  "feishu" | "discord" | "telegram" | "dingtalk" =>
                    match o.get("allowed_users") {
                      Some(Array(_)) => ()
                      _ => panic()
                    }
                  _ => ()
                }
              }
              _ => panic()
            }
          }
        _ => panic()
      }
    _ => panic()
  }
}
