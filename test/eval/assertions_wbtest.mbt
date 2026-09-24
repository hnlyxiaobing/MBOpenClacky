///| 断言词表的解析/序列化往返（计划 §7.2 前置扩展 P-B 新增的三种断言）。
///
/// 新增 `json_path_ne` / `stdout_not_contains` / `stderr_not_contains`
/// 是为了让复现用例可表达"必须变化"与"必须不出现在 stdout"这类负向条件。

///|
test "assertion_kind round-trips the new negations and json_path_ne" {
  let specs : Array[Json] = [
    Json::object({
      "type": "json_path_ne".to_json(),
      "path": "updated_at".to_json(),
      "value": "\"x\"".to_json(),
    }),
    Json::object({
      "type": "stdout_not_contains".to_json(),
      "text": "[stream-summary]".to_json(),
    }),
    Json::object({
      "type": "stderr_not_contains".to_json(),
      "text": "traceback".to_json(),
    }),
  ]
  for spec in specs {
    let parsed = parse_assertion_kind(spec)
    assert_true(parsed is Some(_), msg="not parsed: \{spec.stringify()}")
    let kind = match parsed {
      Some(k) => k
      None => continue
    }
    let again = parse_assertion_kind(assertion_kind_to_json(kind))
    @debug.assert_eq(
      again.map(fn(k) { assertion_kind_to_json(k).stringify() }),
      Some(assertion_kind_to_json(kind).stringify()),
    )
  }
}
