///| journey_json_walk 的路径解析：对象键与数组下标混合（计划 §7.2 前置扩展 P-A）。
///
/// 引入数组下标是为了让列表类端点可断言（如 `sessions.0.id`——#4 复现用例
/// 依赖"最近活跃的会话排在首位"，而此前路径遍历只能走对象键）。

///|
fn walk_str(json : Json, path : String) -> String? {
  journey_json_walk(json, path).map(fn(v) { v.stringify() })
}

///|
test "journey_json_walk walks object keys" {
  let j : Json = @json.parse("{\"session\":{\"id\":\"s1\"}}") catch {
    _ => Json::null()
  }
  @debug.assert_eq(walk_str(j, "session.id"), Some("\"s1\""))
}

///|
test "journey_json_walk indexes into arrays" {
  let j : Json = @json.parse("{\"sessions\":[{\"id\":\"a\"},{\"id\":\"b\"}]}") catch {
    _ => Json::null()
  }
  @debug.assert_eq(walk_str(j, "sessions.0.id"), Some("\"a\""))
  @debug.assert_eq(walk_str(j, "sessions.1.id"), Some("\"b\""))
  @debug.assert_eq(walk_str(j, "sessions.1"), Some("{\"id\":\"b\"}"))
}

///|
test "journey_json_walk rejects out-of-range and mismatched segments" {
  let j : Json = @json.parse("{\"sessions\":[{\"id\":\"a\"}]}") catch {
    _ => Json::null()
  }
  // out of range
  @debug.assert_eq(walk_str(j, "sessions.9.id"), None)
  // non-numeric segment against an array
  @debug.assert_eq(walk_str(j, "sessions.x.id"), None)
  // leading sign is not a digit
  @debug.assert_eq(walk_str(j, "sessions.-1"), None)
  // numeric segment against an object
  @debug.assert_eq(walk_str(j, "0"), None)
  // missing key after a valid index
  @debug.assert_eq(walk_str(j, "sessions.0.missing"), None)
}
