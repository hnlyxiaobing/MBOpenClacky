///| White-box tests for Local Image Proxy handler.

///|
fn make_image_event(url : String) -> @crescent.Event {
  {
    req: @crescent.HttpRequest::http_request(Get, url, {}, raw_body=b""),
    res: @crescent.HttpResponse::http_response(status_code=OK),
    params: {},
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
  assert_eq(resp.status_code.to_int(), 400)
}

///|
test "local image proxy rejects path traversal" {
  let server_ref = make_image_server_ref()
  let event = make_image_event("/api/local-image?path=../secret.png")
  let resp = handle_local_image(server_ref, event)
  assert_eq(resp.status_code.to_int(), 403)
}

///|
test "local image proxy rejects unsupported extension" {
  let server_ref = make_image_server_ref()
  let event = make_image_event("/api/local-image?path=/tmp/data.exe")
  let resp = handle_local_image(server_ref, event)
  assert_eq(resp.status_code.to_int(), 403)
}

///|
test "local image proxy returns 404 for missing file" {
  let server_ref = make_image_server_ref()
  let event = make_image_event(
    "/api/local-image?path=/tmp/DefinitelyMissing.png",
  )
  let resp = handle_local_image(server_ref, event)
  assert_eq(resp.status_code.to_int(), 404)
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
  assert_eq(resp.status_code.to_int(), 200)
  assert_eq(resp.headers.get("Content-Type"), Some("image/png"))
  assert_eq(resp.headers.get("Cache-Control"), Some("public, max-age=3600"))
  assert_eq(resp.raw_body, @utf8.encode("fake-png-bytes"))
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
  assert_eq(resp.status_code.to_int(), 200)
  assert_eq(resp.headers.get("Content-Type"), Some("image/jpeg"))
  assert_eq(resp.raw_body, @utf8.encode("fake-jpg-bytes"))
  @fs.remove_file(tmp_path) catch {
    _ => ()
  }
}
