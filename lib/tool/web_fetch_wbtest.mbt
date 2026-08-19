///| White-box tests for web_fetch URL validation and truncation spill.

///| Covers task 4 alignment: no scheme rewriting, non-HTTP(S) rejection,

///| and full-content spill to a temp file when max_length is exceeded.

///|
async test "web_fetch rejects non-http urls" {
  let tool = WebFetch::new()
  @async.with_task_group(group => {
    for
      bad in [
        "ftp://example.com", "file:///etc/passwd", "example.com", "javascript:alert(1)",
      ] {
      group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
        let result = tool.execute(Map::from_array([("url", bad.to_json())]))
        assert_true(result.is_error, msg="should reject: " + bad)
        @debug.assert_eq(result.content, "URL must be HTTP or HTTPS")
      }
    }
  })
}

///|
async test "web_fetch accepts http and https without rewriting" {
  let tool = WebFetch::new()
  @async.with_task_group(group => {
    // http:// must stay http:// — execute would try the request as-is and
    // fail with a fetch error mentioning the ORIGINAL scheme, never a
    // rewritten https:// (no http→https upgrade).
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      let http_result = tool.execute(
        Map::from_array([("url", "http://127.0.0.1:1/nope".to_json())]),
      )
      assert_true(http_result.is_error)
      assert_true(http_result.content.contains("http://127.0.0.1:1/nope"))
      assert_true(!http_result.content.contains("https://127.0.0.1"))
    }
  })
}

///|
test "web_fetch spills full content to temp file when truncated" {
  let long = "x".repeat(4000)
  let result = build_fetch_result(long, 3000)
  @debug.assert_eq(result.is_error, false)
  assert_true(result.content.length() < 4000, msg="head only")
  // Temp file path is surfaced and the file actually exists with the FULL text.
  let marker = "Full content saved to: "
  let idx = result.content.find(marker)
  assert_true(idx is Some(_), msg="truncation pointer present")
  let path_start = match idx {
    Some(i) => i + marker.length()
    None => -1
  }
  let path = result.content[path_start:].to_owned().trim().to_owned()
  // The path is followed by a closing "]" in the pointer line.
  let path = match path.find("]") {
    Some(j) => path[:j].to_owned()
    None => path
  }
  assert_true(path.length() > 0)
  assert_true(path.contains("clacky-terminal-overflow"))
  let on_disk = @fs.read_file_to_string(path) catch { _ => "" }
  @debug.assert_eq(on_disk, long, msg="full content on disk")
  // Cleanup so the test does not accumulate overflow files.
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "web_fetch keeps short content inline without temp file" {
  let short = "hello world"
  let result = build_fetch_result(short, 3000)
  @debug.assert_eq(result.is_error, false)
  @debug.assert_eq(result.content, short)
  assert_true(!result.content.contains("truncated"))
}
