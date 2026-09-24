///| HTTP 响应保真回归（Spec A）——对应 docs/development-plan-2026-09-23.md 的 #1 与 #2。
///
/// 此前二者均为静默失真：`response_to_core` 把 5xx/429 回落成 200，
/// `HttpResponse::bad_request`/`not_found` 直接把 message 插值进 JSON 串。
/// 现存受害者：`/api/backup/download/:id` 的诚实 501 曾以 200 到达客户端。

///|
/// #1：`response_to_core` 必须保留真实状态码。
/// 现存受害者：`/api/backup/download/:id` 的诚实 501（handlers_backup.mbt:666）
/// 曾以 200 到达客户端（见计划 §5 风险表末行）。
test "plan_1a_response_to_core_preserves_status" {
  let cases : Array[(Int, Int)] = [
    (200, 200),
    (201, 201),
    (204, 204),
    (400, 400),
    (404, 404),
    (429, 429),
    (500, 500),
    (501, 501),
    (503, 503),
  ]
  for pair in cases {
    let mapped = response_to_core(HttpResponse::{
      status: pair.0,
      body: "{}",
      body_bytes: None,
      content_type: "application/json",
      headers: [],
    })
    @debug.assert_eq(mapped.status_code.to_int(), pair.1)
  }
}

///|
/// #2 复现：错误响应体必须对用户输入做 JSON 转义。
/// #2：错误响应体必须对用户输入做 JSON 转义。
/// 此前 `router.mbt:113/125` 直接插值 `"{\"error\":\"\{message}\"}"`，
/// message 含引号/花括号/换行时产出非法 JSON（调用面广：trash/backup/channels 等）。
test "plan_2a_error_body_is_valid_json" {
  let hostile = "a\"b{c}\nd"
  let bodies : Array[String] = [
    HttpResponse::not_found(hostile).body,
    HttpResponse::bad_request(hostile).body,
  ]
  for body in bodies {
    let parsed : Json = @json.parse(body) catch { _ => Json::null() }
    match parsed {
      Object(obj) => @debug.assert_eq(obj.get("error"), Some(hostile.to_json()))
      _ => assert_true(false, msg="error body is not valid JSON: \{body}")
    }
  }
}
