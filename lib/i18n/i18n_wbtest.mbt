///|
/// Backend i18n dictionary tests.
test "en resolves key" {
  assert_eq(t("en", "error.invalid_json"), "Invalid JSON body")
}

///|
test "zh resolves key" {
  assert_eq(t("zh", "error.invalid_json"), "无效的 JSON 请求体")
}

///|
test "unsupported locale falls back to default" {
  assert_eq(t("fr", "error.not_found"), "Not found")
}

///|
test "missing key returns the raw key" {
  assert_eq(t("en", "no.such.key"), "no.such.key")
}

///|
test "param substitution en" {
  let s = t_with_params("en", "error.file_not_found", { "path": "/tmp/x" })
  assert_eq(s, "File not found: /tmp/x")
}

///|
test "param substitution zh" {
  let s = t_with_params("zh", "session.created", { "id": "abc" })
  assert_eq(s, "会话已创建：abc")
}

///|
test "locale resolution priority: channel > session > default" {
  assert_eq(resolve_locale(Some("zh"), None), "zh")
  assert_eq(resolve_locale(None, Some("zh")), "zh")
  assert_eq(resolve_locale(None, None), "en")
  assert_eq(resolve_locale(Some("fr"), None), "en")
}

///|
test "has reports membership" {
  assert_true(has("error.internal"))
  assert_false(has("definitely.not.a.key"))
}
