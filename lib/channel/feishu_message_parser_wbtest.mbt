///| Feishu message parser tests: text extraction, doc URL discovery, mention resolution.

// ── parse_feishu_text ──────────────────────────────────────────────────────

///|
test "feishu_parse_text_simple" {
  let result = parse_feishu_text("{\"text\":\"Hello World\"}")
  assert_eq(result, "Hello World")
}

///|
test "feishu_parse_text_with_mention" {
  let result = parse_feishu_text("{\"text\":\"Hello @_user_1\"}")
  assert_eq(result, "Hello @_user_1")
}

///|
test "feishu_parse_text_empty_string_field" {
  let result = parse_feishu_text("{\"text\":\"\"}")
  assert_eq(result, "")
}

///|
test "feishu_parse_text_empty_input" {
  let result = parse_feishu_text("")
  assert_eq(result, "")
}

///|
test "feishu_parse_text_invalid_json" {
  let result = parse_feishu_text("not json at all")
  assert_eq(result, "not json at all")
}

///|
test "feishu_parse_text_no_text_field" {
  let result = parse_feishu_text("{\"other\":\"value\"}")
  assert_eq(result, "{\"other\":\"value\"}")
}

///|
test "feishu_parse_text_unicode" {
  let result = parse_feishu_text("{\"text\":\"你好世界\"}")
  assert_eq(result, "你好世界")
}

///|
test "feishu_parse_text_array_not_object" {
  let result = parse_feishu_text("[1,2,3]")
  assert_eq(result, "[1,2,3]")
}

// ── extract_feishu_doc_urls ────────────────────────────────────────────────

///|
test "feishu_extract_urls_feishu_docs" {
  let urls = extract_feishu_doc_urls("See https://docs.feishu.cn/docx/abc123")
  assert_eq(urls.length(), 1)
  assert_true(urls[0].contains("docs.feishu.cn"))
}

///|
test "feishu_extract_urls_feishu_wiki" {
  let urls = extract_feishu_doc_urls("Link: https://feishu.cn/wiki/xyz456")
  assert_eq(urls.length(), 1)
  assert_true(urls[0].contains("wiki"))
}

///|
test "feishu_extract_urls_larksuite" {
  let urls = extract_feishu_doc_urls(
    "Doc: https://docs.larksuite.com/docx/test",
  )
  assert_eq(urls.length(), 1)
}

///|
test "feishu_extract_urls_no_urls" {
  let urls = extract_feishu_doc_urls("Hello World")
  assert_eq(urls.length(), 0)
}

///|
test "feishu_extract_urls_multiple" {
  let text = "https://docs.feishu.cn/docx/a https://feishu.cn/wiki/b"
  let urls = extract_feishu_doc_urls(text)
  assert_eq(urls.length(), 2)
}

///|
test "feishu_extract_urls_http_not_https" {
  let urls = extract_feishu_doc_urls("http://docs.feishu.cn/docx/test")
  assert_eq(urls.length(), 1)
}

///|
test "feishu_extract_urls_non_feishu_ignored" {
  let urls = extract_feishu_doc_urls("https://github.com/repo")
  assert_eq(urls.length(), 0)
}

///|
test "feishu_extract_urls_feishu_sheets" {
  let urls = extract_feishu_doc_urls("https://feishu.cn/sheets/abc")
  assert_eq(urls.length(), 1)
}

///|
test "feishu_extract_urls_feishu_base" {
  let urls = extract_feishu_doc_urls("https://feishu.cn/base/abc")
  assert_eq(urls.length(), 1)
}

///|
test "feishu_extract_urls_mixed_text" {
  let text = "Hello check https://docs.feishu.cn/docx/xyz thanks"
  let urls = extract_feishu_doc_urls(text)
  assert_eq(urls.length(), 1)
  assert_true(urls[0].contains("docs.feishu.cn"))
}

///|
test "feishu_extract_urls_empty_text" {
  let urls = extract_feishu_doc_urls("")
  assert_eq(urls.length(), 0)
}

// ── resolve_feishu_mentions ────────────────────────────────────────────────

///|
test "feishu_resolve_mentions_single" {
  let json = @json.parse("{\"key\":\"@_user_1\",\"name\":\"Alice\"}") catch {
    _ => Json::null()
  }
  let mentions : Array[Json] = [json]
  let result = resolve_feishu_mentions("Hello @_user_1", mentions)
  assert_eq(result, "Hello @Alice")
}

///|
test "feishu_resolve_mentions_multiple" {
  let json1 = @json.parse("{\"key\":\"@_user_1\",\"name\":\"Alice\"}") catch {
    _ => Json::null()
  }
  let json2 = @json.parse("{\"key\":\"@_user_2\",\"name\":\"Bob\"}") catch {
    _ => Json::null()
  }
  let mentions : Array[Json] = [json1, json2]
  let result = resolve_feishu_mentions("@_user_1 and @_user_2", mentions)
  assert_eq(result, "@Alice and @Bob")
}

///|
test "feishu_resolve_mentions_no_match" {
  let json = @json.parse("{\"key\":\"@_user_1\",\"name\":\"Alice\"}") catch {
    _ => Json::null()
  }
  let mentions : Array[Json] = [json]
  let result = resolve_feishu_mentions("Hello World", mentions)
  assert_eq(result, "Hello World")
}

///|
test "feishu_resolve_mentions_empty_mentions" {
  let mentions : Array[Json] = []
  let result = resolve_feishu_mentions("Hello @_user_1", mentions)
  assert_eq(result, "Hello @_user_1")
}

///|
test "feishu_resolve_mentions_missing_key" {
  let json = @json.parse("{\"name\":\"Alice\"}") catch { _ => Json::null() }
  let mentions : Array[Json] = [json]
  let result = resolve_feishu_mentions("Hello @_user_1", mentions)
  assert_eq(result, "Hello @_user_1")
}

///|
test "feishu_resolve_mentions_missing_name" {
  let json = @json.parse("{\"key\":\"@_user_1\"}") catch { _ => Json::null() }
  let mentions : Array[Json] = [json]
  let result = resolve_feishu_mentions("Hello @_user_1", mentions)
  assert_eq(result, "Hello @_user_1")
}

///|
test "feishu_resolve_mentions_non_object_entry" {
  let mentions : Array[Json] = ["not an object".to_json()]
  let result = resolve_feishu_mentions("Hello", mentions)
  assert_eq(result, "Hello")
}

// ── parse_feishu_message ───────────────────────────────────────────────────

///|
test "feishu_parse_message_text_type" {
  let msg : Map[String, Json] = {
    "message_type": "text".to_json(),
    "content": "{\"text\":\"Hello Feishu\"}".to_json(),
  }
  let result = parse_feishu_message(msg)
  match result {
    Ok(parsed) => {
      assert_eq(parsed.msg_type, "text")
      assert_eq(parsed.text, "Hello Feishu")
      assert_eq(parsed.attachments.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "feishu_parse_message_default_type" {
  let msg : Map[String, Json] = {
    "content": "{\"text\":\"Default\"}".to_json(),
  }
  let result = parse_feishu_message(msg)
  match result {
    Ok(parsed) => {
      assert_eq(parsed.msg_type, "text")
      assert_eq(parsed.text, "Default")
    }
    Err(_) => assert_true(false)
  }
}

///|
test "feishu_parse_message_with_doc_url" {
  let msg : Map[String, Json] = {
    "message_type": "text".to_json(),
    "content": "{\"text\":\"See https://docs.feishu.cn/docx/abc\"}".to_json(),
  }
  let result = parse_feishu_message(msg)
  match result {
    Ok(parsed) => {
      assert_eq(parsed.doc_urls.length(), 1)
      assert_true(parsed.doc_urls[0].contains("docs.feishu.cn"))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "feishu_parse_message_unknown_type" {
  let msg : Map[String, Json] = {
    "message_type": "interactive".to_json(),
    "content": "some content".to_json(),
  }
  let result = parse_feishu_message(msg)
  match result {
    Ok(parsed) => {
      assert_eq(parsed.msg_type, "interactive")
      assert_eq(parsed.text, "some content")
    }
    Err(_) => assert_true(false)
  }
}

///|
test "feishu_parse_message_empty_content" {
  let msg : Map[String, Json] = {
    "message_type": "text".to_json(),
    "content": "".to_json(),
  }
  let result = parse_feishu_message(msg)
  match result {
    Ok(parsed) => {
      assert_eq(parsed.msg_type, "text")
      assert_eq(parsed.text, "")
    }
    Err(_) => assert_true(false)
  }
}

///|
test "feishu_parse_message_image_type" {
  let msg : Map[String, Json] = {
    "message_type": "image".to_json(),
    "content": "{\"image_key\":\"img_abc123\"}".to_json(),
  }
  let result = parse_feishu_message(msg)
  match result {
    Ok(parsed) => {
      assert_eq(parsed.msg_type, "image")
      assert_eq(parsed.text, "[image]")
      assert_eq(parsed.attachments.length(), 1)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "feishu_parse_message_file_type" {
  let msg : Map[String, Json] = {
    "message_type": "file".to_json(),
    "content": "{\"file_key\":\"file_abc\",\"file_name\":\"doc.pdf\"}".to_json(),
  }
  let result = parse_feishu_message(msg)
  match result {
    Ok(parsed) => {
      assert_eq(parsed.msg_type, "file")
      assert_eq(parsed.text, "[file]")
      assert_eq(parsed.attachments.length(), 1)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "feishu_parse_message_post_type" {
  let post_content = "{\"zh_cn\":{\"title\":\"Title\",\"content\":[[{\"tag\":\"text\",\"text\":\"Hello\"}]]}}"
  let msg : Map[String, Json] = {
    "message_type": "post".to_json(),
    "content": post_content.to_json(),
  }
  let result = parse_feishu_message(msg)
  match result {
    Ok(parsed) => {
      assert_eq(parsed.msg_type, "post")
      assert_true(parsed.text.contains("Hello"))
    }
    Err(_) => assert_true(false)
  }
}
