///| White-box tests for /api/file-action display-path translation.

///|
test "mnt_path_to_win converts mounted drive paths" {
  @debug.assert_eq(mnt_path_to_win("/mnt/c/Users/x"), Some("C:\\Users\\x"))
  @debug.assert_eq(mnt_path_to_win("/mnt/d/"), Some("D:\\"))
  @debug.assert_eq(mnt_path_to_win("/mnt/z/a/b/c"), Some("Z:\\a\\b\\c"))
}

///|
test "mnt_path_to_win rejects non-mounted or malformed paths" {
  @debug.assert_eq(mnt_path_to_win("/home/user"), None)
  @debug.assert_eq(mnt_path_to_win("C:\\already"), None)
  @debug.assert_eq(mnt_path_to_win("/mnt/"), None)
  @debug.assert_eq(mnt_path_to_win("/mnt/d"), None)
  @debug.assert_eq(mnt_path_to_win("/mnt/cd/x"), None)
  @debug.assert_eq(mnt_path_to_win("/mnt/1/x"), None)
}

///|
fn fa_make_event(body : String) -> @crescent.Event {
  {
    req: @crescent.HttpRequest::HttpRequest(
      Post,
      "/api/file-action",
      Map([]),
      raw_body=@utf8.encode(body),
    ),
    res: @crescent.HttpResponse::HttpResponse(status_code=OK),
    params: Map([]),
  }
}

///|
fn fa_make_server_ref() -> Ref[WebServer] {
  Ref(WebServer::new(@config.AgentConfig::default(), None))
}

///|
fn fa_response_json(resp : @core.HttpResponse) -> Json {
  @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => Json::object(Map([]))
  }
}

///|
test "file-action display-path returns 200 with path passthrough off-WSL" {
  let resp = handle_file_action_bridge(
    fa_make_server_ref(),
    fa_make_event("{\"action\":\"display-path\",\"path\":\"/tmp/foo\"}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  guard! fa_response_json(resp) is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  // /tmp/foo is not a /mnt path, so it passes through unchanged on any host.
  @debug.assert_eq(obj.get("path"), Some("/tmp/foo".to_json()))
}

///|
test "file-action other actions stay unimplemented in headless mode" {
  let resp = handle_file_action_bridge(
    fa_make_server_ref(),
    fa_make_event("{\"action\":\"open\",\"path\":\"/tmp/foo\"}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 501)
}

///|
test "file-action requires action and path" {
  let resp = handle_file_action_bridge(
    fa_make_server_ref(),
    fa_make_event("{\"action\":\"display-path\"}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
}
