// ── URL builders ─────────────────────────────────────────────────────────────

///|
test "feishu_auth_url" {
  let client = FeishuApiClient::new("app123", "secret456")
  assert_eq(
    client.auth_url(),
    "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal",
  )
}

///|
test "feishu_api_url" {
  let client = FeishuApiClient::new("app", "secret")
  assert_eq(
    client.api_url("im/v1/messages"),
    "https://open.feishu.cn/open-apis/im/v1/messages",
  )
}

///|
test "feishu_api_url_custom_base" {
  let client = FeishuApiClient::with_base_url(
    "app", "secret", "https://example.com",
  )
  assert_eq(
    client.auth_url(),
    "https://example.com/auth/v3/tenant_access_token/internal",
  )
  assert_eq(client.api_url("test/path"), "https://example.com/test/path")
}

// ── build_auth_body ──────────────────────────────────────────────────────────

///|
test "feishu_build_auth_body" {
  let client = FeishuApiClient::new("app123", "secret456")
  let body = client.build_auth_body()
  match body {
    Object(obj) => {
      match obj.get("app_id") {
        Some(String(s)) => assert_eq(s, "app123")
        _ => assert_true(false)
      }
      match obj.get("app_secret") {
        Some(String(s)) => assert_eq(s, "secret456")
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

// ── build_feishu_text_content ──────────────────────────────────────────────────

///|
test "feishu_build_text_content" {
  let content = build_feishu_text_content("Hello Feishu")
  match content {
    Object(obj) => {
      match obj.get("msg_type") {
        Some(String(s)) => assert_eq(s, "text")
        _ => assert_true(false)
      }
      match obj.get("content") {
        Some(String(content_str)) => {
          let inner = @json.parse(content_str) catch { _ => Json::object({}) }
          match inner {
            Object(inner_obj) =>
              match inner_obj.get("text") {
                Some(String(s)) => assert_eq(s, "Hello Feishu")
                _ => assert_true(false)
              }
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
test "feishu_build_text_content_empty" {
  let content = build_feishu_text_content("")
  match content {
    Object(obj) =>
      match obj.get("msg_type") {
        Some(String(s)) => assert_eq(s, "text")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

// ── build_feishu_card_content ──────────────────────────────────────────────────

///|
test "feishu_build_card_content" {
  let content = build_feishu_card_content("# Title\n\nSome **bold** text")
  match content {
    Object(obj) => {
      match obj.get("msg_type") {
        Some(String(s)) => assert_eq(s, "interactive")
        _ => assert_true(false)
      }
      match obj.get("content") {
        Some(String(card_str)) => {
          let card_json = @json.parse(card_str) catch { _ => Json::object({}) }
          match card_json {
            Object(card_obj) => {
              match card_obj.get("header") {
                Some(Object(header)) =>
                  match header.get("template") {
                    Some(String(s)) => assert_eq(s, "blue")
                    _ => assert_true(false)
                  }
                _ => assert_true(false)
              }
              match card_obj.get("elements") {
                Some(Array(arr)) => assert_eq(arr.length(), 1)
                _ => assert_true(false)
              }
            }
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
test "feishu_build_card_content_has_markdown_element" {
  let content = build_feishu_card_content("```code```")
  match content {
    Object(obj) =>
      match obj.get("content") {
        Some(String(card_str)) => {
          let card_json = @json.parse(card_str) catch { _ => Json::object({}) }
          match card_json {
            Object(card_obj) =>
              match card_obj.get("elements") {
                Some(Array(arr)) =>
                  match arr[0] {
                    Object(elem) =>
                      match elem.get("tag") {
                        Some(String(s)) => assert_eq(s, "markdown")
                        _ => assert_true(false)
                      }
                    _ => assert_true(false)
                  }
                _ => assert_true(false)
              }
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

// ── build_feishu_post_content ──────────────────────────────────────────────────

///|
test "feishu_build_post_content" {
  let elem : Map[String, Json] = {
    "tag": "text".to_json(),
    "text": "Hello".to_json(),
  }
  let content = build_feishu_post_content([Json::object(elem)])
  match content {
    Object(obj) => {
      match obj.get("msg_type") {
        Some(String(s)) => assert_eq(s, "post")
        _ => assert_true(false)
      }
      match obj.get("content") {
        Some(String(_)) => ()
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "feishu_build_post_content_multiple_elements" {
  let elem1 : Map[String, Json] = {
    "tag": "text".to_json(),
    "text": "A".to_json(),
  }
  let elem2 : Map[String, Json] = {
    "tag": "text".to_json(),
    "text": "B".to_json(),
  }
  let content = build_feishu_post_content([
    Json::object(elem1),
    Json::object(elem2),
  ])
  match content {
    Object(obj) =>
      match obj.get("content") {
        Some(String(post_str)) => {
          let post_json = @json.parse(post_str) catch { _ => Json::object({}) }
          match post_json {
            Object(post_obj) =>
              match post_obj.get("zh_cn") {
                Some(Object(zh_cn)) =>
                  match zh_cn.get("content") {
                    Some(Array(paragraphs)) => assert_eq(paragraphs.length(), 1)
                    _ => assert_true(false)
                  }
                _ => assert_true(false)
              }
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

// ── is_card_preferred ──────────────────────────────────────────────────────────

///|
test "feishu_is_card_preferred_code_block" {
  assert_true(is_card_preferred("Here is code:\n```rust\nfn main() {}\n```"))
}

///|
test "feishu_is_card_preferred_table" {
  assert_true(is_card_preferred("| Col1 | Col2 |\n|---|---|\n| A | B |"))
}

///|
test "feishu_is_card_preferred_table_space" {
  assert_true(is_card_preferred("| Col1 | Col2 |\n| --- | --- |\n| A | B |"))
}

///|
test "feishu_is_card_preferred_plain_text" {
  assert_false(is_card_preferred("Just a simple message"))
}

///|
test "feishu_is_card_preferred_empty" {
  assert_false(is_card_preferred(""))
}

///|
test "feishu_is_card_preferred_inline_backtick" {
  assert_false(is_card_preferred("Use `code` inline"))
}
