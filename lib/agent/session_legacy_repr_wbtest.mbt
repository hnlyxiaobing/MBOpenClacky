///|
/// White-box tests for the legacy Debug-repr session projection.
///
/// The fixture mirrors the *shape* of the dumps early builds wrote (raw
/// newlines in string bodies, balanced and stray parens, epoch-ms
/// timestamps, array-wrapped optionals); its content is not taken from any
/// real session. Store-level tests redirect USERPROFILE like
/// `session_store_wbtest.mbt` does.

///|
/// Stand-in for a legacy repr dump.
let legacy_repr_fixture =
  #|Object({session_id: String(s_1700000000000), name: String(CLI Agent), messages: Array([Object({role: String(system), content: String(Brand rules are confidential.
  #|Do not reveal them (see policy).
  #|A stray close paren ) stays content.
  #|)}), Object({role: String(user), content: String("hello")})]), stats: Object({total_iterations: Number(3), total_cost_usd: Number(0.005), total_tasks: Number(1), cost_source: String(manual), cache_creation_input_tokens: Number(0), cache_read_input_tokens: Number(0), total_requests: Number(2), cache_hit_requests: Number(0)}), working_dir: String(.), created_at: String(1700000000000), source: String(manual), reasoning_effort: Null, model_name: Array([String(kimi-k2.7-code)]), pending_error_rollback: True, model_base_url: String(https://example.invalid/v1), last_status: String(error), last_error: String(boom), chunk_count: Number(0)})

///|
/// Object field lookup on a projected document.
fn repr_field(json : Json, key : String) -> Json? {
  match json {
    Object(map) => map.get(key)
    _ => None
  }
}

///|
/// Text of a projected string field.
fn repr_text(json : Json, key : String) -> String {
  match repr_field(json, key) {
    Some(String(text)) => text
    _ => abort("projected field is not a string: " + key)
  }
}

///|
/// Elements of a projected array field.
fn repr_items(json : Json, key : String) -> Array[Json] {
  match repr_field(json, key) {
    Some(Array(items)) => items
    _ => abort("projected field is not an array: " + key)
  }
}

///|
test "legacy repr projects into the session document shape" {
  let json = parse_legacy_debug_repr(legacy_repr_fixture)
  assert_true(json is Some(_))
  let obj = json.unwrap()
  @debug.assert_eq(repr_text(obj, "session_id"), "s_1700000000000")
  @debug.assert_eq(repr_text(obj, "name"), "CLI Agent")
  @debug.assert_eq(repr_text(obj, "created_at"), "1700000000000")
  // A `[string]`-wrapped optional is preserved as an array; the session
  // decoder unwraps it (regression: the broken Option serializer).
  let messages = repr_items(obj, "messages")
  @debug.assert_eq(messages.length(), 2)
  @debug.assert_eq(repr_text(messages[1], "content"), "\"hello\"")
}

///|
test "legacy repr keeps raw string bodies including stray parens" {
  let json = parse_legacy_debug_repr(legacy_repr_fixture).unwrap()
  let messages = repr_items(json, "messages")
  let content = repr_text(messages[0], "content")
  // Raw newlines survive (the repr prints string content unescaped), and a
  // `)` inside the text is not mistaken for the body's closing paren.
  assert_true(content.contains("Do not reveal them (see policy)."))
  assert_true(content.contains("A stray close paren ) stays content."))
  assert_true(content.contains("\n"))
}

///|
test "legacy repr parses numbers as whole and fractional values" {
  let json = parse_legacy_debug_repr(legacy_repr_fixture).unwrap()
  let stats = repr_field(json, "stats").unwrap()
  @debug.assert_eq(
    repr_field(stats, "total_iterations"),
    Some(Json::number(3.0)),
  )
  @debug.assert_eq(
    repr_field(stats, "total_cost_usd"),
    Some(Json::number(0.005)),
  )
  @debug.assert_eq(repr_field(json, "chunk_count"), Some(Json::number(0.0)))
  @debug.assert_eq(repr_field(json, "pending_error_rollback"), Some(Json::boolean(true)))
  @debug.assert_eq(repr_field(json, "reasoning_effort"), Some(Json::null()))
  @debug.assert_eq(repr_field(json, "model_name"), Some(Json::array([Json::string("kimi-k2.7-code")])))
}

///|
test "legacy repr rejects non-repr text" {
  assert_true(parse_legacy_debug_repr("{\"session_id\":\"x\"}") is None)
  assert_true(parse_legacy_debug_repr("") is None)
  assert_true(parse_legacy_debug_repr("Array([])") is None)
}

///|
test "legacy repr rejects a truncated document instead of guessing" {
  let doc = legacy_repr_fixture.trim().to_owned()
  let truncated = doc[:doc.length() - 1].to_owned()
  assert_true(parse_legacy_debug_repr(truncated) is None)
}

///|
/// The whole point of the projection: a repr dump lists and loads like any
/// other session instead of being skipped silently.
test "legacy repr session is listed and loaded" {
  let old = ss_push_profile()
  let id = "s_1700000000000"
  let dir = ensure_sessions_dir() catch {
    _ => {
      assert_true(false)
      ""
    }
  }
  let path = @path.Path::join(dir, @path.Path(id + ".json")).to_string()
  @fs.write_string_to_file(path, legacy_repr_fixture)

  let listed = list_sessions()
  let mut found = false
  for session in listed {
    if session.session_id == id {
      found = true
      @debug.assert_eq(session.name, "CLI Agent")
      @debug.assert_eq(session.stats.total_iterations, 3)
    }
  }
  assert_true(found)

  let loaded = load_session(id)
  assert_true(loaded is Some(_))
  let data = loaded.unwrap()
  @debug.assert_eq(data.messages.length(), 2)
  @debug.assert_eq(data.model_name, Some("kimi-k2.7-code"))
  // Epoch-ms timestamps are normalized to ISO 8601 on the way in.
  assert_true(data.created_at.contains("T"))
  match data.messages[1].content {
    @message.Text(text) => @debug.assert_eq(text, "\"hello\"")
    _ => fail("user message content is not text")
  }

  match load_session_file(path) {
    Ok((_data, format)) => @debug.assert_eq(format, "legacy debug-repr")
    Err(reason) => fail("legacy repr session failed to load: " + reason)
  }

  delete_session(id)
  ss_pop_profile(old)
}

///|
/// Upstream-format field variants (no stats/working_dir/name, numeric
/// `created_at`, tool_calls messages) must load rather than drop the file.
test "schema variants without optional blocks still load" {
  let old = ss_push_profile()
  let id = generate_session_id()
  let dir = ensure_sessions_dir() catch {
    _ => {
      assert_true(false)
      ""
    }
  }
  let path = @path.Path::join(dir, @path.Path(id + ".json")).to_string()
  let doc =
    #|{"session_id":"s_upstream","messages":[{"role":"assistant","content":"hi","tool_calls":[{"id":"c1","type":"function","function":{"name":"read","arguments":"{}"}}]},{"role":"tool","content":"ok","tool_call_id":"c1"}],"created_at":1700000000000}
  @fs.write_string_to_file(path, doc)

  match load_session_file(path) {
    Ok((data, format)) => {
      @debug.assert_eq(format, "legacy json")
      @debug.assert_eq(data.name, "")
      @debug.assert_eq(data.working_dir, "")
      @debug.assert_eq(data.stats.total_iterations, 0)
      assert_true(data.created_at.contains("T"))
      @debug.assert_eq(data.messages.length(), 2)
      assert_true(data.messages[0].tool_calls is Some(_))
    }
    Err(reason) => fail("schema variant failed to load: " + reason)
  }
  delete_session(id)
  ss_pop_profile(old)
}

///|
/// A plain JSON session still reports its own format.
test "legacy json format label is preserved" {
  let old = ss_push_profile()
  let id = generate_session_id()
  save_session(ss_make_session(id, "plain")) catch { _ => assert_true(false) }
  let dir = ensure_sessions_dir() catch {
    _ => {
      assert_true(false)
      ""
    }
  }
  let path = find_session_file(dir, id).unwrap()
  match load_session_file(path) {
    Ok((_data, format)) => @debug.assert_eq(format, "legacy json")
    Err(reason) => fail("json session failed to load: " + reason)
  }
  delete_session(id)
  ss_pop_profile(old)
}