///| White-box tests for Local Image Proxy handler.

///|
fn make_image_event(url : String) -> @crescent.Event {
  {
    req: @crescent.HttpRequest::HttpRequest(Get, url, Map([]), raw_body=b""),
    res: @crescent.HttpResponse::HttpResponse(status_code=OK),
    params: Map([]),
  }
}

///|
fn make_image_server_ref() -> Ref[WebServer] {
  Ref(WebServer::new(@config.AgentConfig::default(), None))
}

///|
test "local image proxy requires path" {
  let server_ref = make_image_server_ref()
  let event = make_image_event("/api/local-image")
  let resp = handle_local_image(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

///|
test "local image proxy rejects path traversal" {
  let server_ref = make_image_server_ref()
  let event = make_image_event("/api/local-image?path=../secret.png")
  let resp = handle_local_image(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 403)
}

///|
test "local image proxy rejects unsupported extension" {
  let server_ref = make_image_server_ref()
  let event = make_image_event("/api/local-image?path=/tmp/data.exe")
  let resp = handle_local_image(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 403)
}

///|
test "local image proxy returns 404 for missing file" {
  let server_ref = make_image_server_ref()
  let event = make_image_event(
    "/api/local-image?path=/tmp/DefinitelyMissing.png",
  )
  let resp = handle_local_image(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 404)
  // web-ui2-10 BUG-015: lowercase error, no path leakage.
  let j = @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => fail("expected JSON error body")
  }
  guard j is Object(obj)
  @debug.assert_eq(obj.get("error"), Some("file not found".to_json()))
  assert_false(obj.contains("path"))
}

///|
test "local image proxy serves png with correct mime and cache header" {
  let server_ref = make_image_server_ref()
  let tmp_path = "_build/test_local_image.png"
  @fs.write_string_to_file(tmp_path, "fake-png-bytes") catch {
    _ => fail("Failed to create temp image file")
  }
  let event = make_image_event("/api/local-image?path=" + tmp_path)
  let resp = handle_local_image(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 200)
  @debug.assert_eq(resp.headers.get("Content-Type"), Some("image/png"))
  @debug.assert_eq(
    resp.headers.get("Cache-Control"),
    Some("public, max-age=3600"),
  )
  @debug.assert_eq(resp.raw_body, @utf8.encode("fake-png-bytes"))
  @fs.remove_file(tmp_path) catch {
    _ => ()
  }
}

///|
test "local image proxy strips file protocol prefix" {
  let server_ref = make_image_server_ref()
  let tmp_path = "_build/test_local_image2.jpg"
  @fs.write_string_to_file(tmp_path, "fake-jpg-bytes") catch {
    _ => fail("Failed to create temp image file")
  }
  let event = make_image_event("/api/local-image?path=file:///" + tmp_path)
  let resp = handle_local_image(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 200)
  @debug.assert_eq(resp.headers.get("Content-Type"), Some("image/jpeg"))
  @debug.assert_eq(resp.raw_body, @utf8.encode("fake-jpg-bytes"))
  @fs.remove_file(tmp_path) catch {
    _ => ()
  }
}
