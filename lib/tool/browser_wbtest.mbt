///| White-box tests for browser form interaction enhancements.

///| Tests scroll native dispatch, fallback, fill focus/blur, and graceful degradation.

// ── Screenshot Pipeline Tests (Task #2) ─────────────────────────────────────

///|
/// Test: jpeg format produces image/jpeg mime_type instead of image/png.
test "screenshot_format_switch_png_to_jpeg" {
  // Construct a fake MCP response with a valid base64 payload (4 bytes)
  let fake_b64 = "dGVzdA==" // base64("test") = 4 bytes
  let mcp_output = "data:image/png;base64,\{fake_b64}"
  // Default (png) — should use image/png
  let result_png = format_screenshot_result(mcp_output)
  assert_true(result_png.find("mime_type: image/png") is Some(_))
  assert_true(result_png.find("format: png") is Some(_))
  // jpeg format — should use image/jpeg
  let result_jpeg = format_screenshot_result(mcp_output, format=Some("jpeg"))
  assert_true(result_jpeg.find("mime_type: image/jpeg") is Some(_))
  assert_true(result_jpeg.find("format: jpeg") is Some(_))
}

///|
/// Test: save_path parameter is passed through and appears in output.
test "screenshot_custom_save_path_appears_in_output" {
  let fake_b64 = "dGVzdA==" // 4 bytes
  let mcp_output = "data:image/png;base64,\{fake_b64}"
  let custom_path = "/tmp/my_custom_screenshot.png"
  let result = format_screenshot_result(mcp_output, save_path=Some(custom_path))
  // save_path should be used as the file path (if write succeeds or fails the
  // path string still appears in the output on success, or the error note on failure).
  // On Windows /tmp may not exist; either way the function should not panic.
  // Check that the result contains either the path or a save-failure note.
  let has_path = result.find(custom_path) is Some(_)
  let has_fail_note = result.find("Failed to save") is Some(_)
  assert_true(has_path || has_fail_note)
}

///|
/// Test: build_mcp_screenshot_args transparently passes format and quality.
test "build_mcp_screenshot_args_passes_format_and_quality" {
  let args : Map[String, Json] = {
    "format": "jpeg".to_json(),
    "quality": (80).to_json(),
    "full_page": true.to_json(),
  }
  let result = build_mcp_screenshot_args(args)
  let s = result.stringify()
  assert_true(s.find("format") is Some(_))
  assert_true(s.find("jpeg") is Some(_))
  assert_true(s.find("quality") is Some(_))
  assert_true(s.find("80") is Some(_))
  assert_true(s.find("full_page") is Some(_))
}

///|
/// Test: build_mcp_screenshot_args without format/quality omits them.
test "build_mcp_screenshot_args_omits_format_when_absent" {
  let args : Map[String, Json] = {}
  let result = build_mcp_screenshot_args(args)
  let s = result.stringify()
  assert_eq(s, "{}")
}

///|
/// Test: Browser parameters() schema includes new screenshot params.
test "browser_parameters_schema_includes_screenshot_params" {
  let browser = Browser::new()
  let params = browser.parameters()
  let s = params.stringify()
  // Verify all new screenshot parameters appear in the schema
  assert_true(s.find("\"format\"") is Some(_))
  assert_true(s.find("\"quality\"") is Some(_))
  assert_true(s.find("\"save_path\"") is Some(_))
  assert_true(s.find("\"max_width\"") is Some(_))
  assert_true(s.find("\"max_height\"") is Some(_))
}

///|
/// Test: format_screenshot_result includes size info and format line.
test "screenshot_result_includes_size_and_format" {
  let fake_b64 = "dGVzdA==" // 4 bytes
  let mcp_output = "data:image/png;base64,\{fake_b64}"
  let result = format_screenshot_result(mcp_output)
  // format line should always be present
  assert_true(result.find("format: png") is Some(_))
  // size line should be present on successful save
  let has_size = result.find("size:") is Some(_)
  // If save failed (e.g. no temp dir write perms), the fail note appears instead
  let has_fail_note = result.find("Failed to save") is Some(_)
  assert_true(has_size || has_fail_note)
}

// ── build_mcp_scroll_args Tests ─────────────────────────────────────────────

///|
test "build_mcp_scroll_args_with_direction_and_amount" {
  let args : Map[String, Json] = {
    "direction": "down".to_json(),
    "amount": (500).to_json(),
  }
  let result = build_mcp_scroll_args(args)
  let s = result.stringify()
  assert_true(s.find("direction") is Some(_))
  assert_true(s.find("down") is Some(_))
  assert_true(s.find("amount") is Some(_))
  assert_true(s.find("500") is Some(_))
}

///|
test "build_mcp_scroll_args_direction_only" {
  let args : Map[String, Json] = { "direction": "up".to_json() }
  let result = build_mcp_scroll_args(args)
  let s = result.stringify()
  assert_true(s.find("direction") is Some(_))
  assert_true(s.find("up") is Some(_))
  assert_true(s.find("amount") is None)
}

///|
test "build_mcp_scroll_args_empty" {
  let args : Map[String, Json] = {}
  let result = build_mcp_scroll_args(args)
  let s = result.stringify()
  assert_eq(s, "{}")
}

///|
test "build_mcp_args_routes_scroll_page" {
  let args : Map[String, Json] = {
    "direction": "down".to_json(),
    "amount": (300).to_json(),
  }
  let result = build_mcp_args("scroll_page", args)
  let s = result.stringify()
  assert_true(s.find("direction") is Some(_))
  assert_true(s.find("amount") is Some(_))
}

// ── escape_js_string Tests ──────────────────────────────────────────────────

///|
test "escape_js_string_no_special_chars" {
  assert_eq(escape_js_string("e1"), "e1")
  assert_eq(escape_js_string("hello"), "hello")
}

///|
test "escape_js_string_with_backslash" {
  let result = escape_js_string("a\\b")
  assert_eq(result, "a\\\\b")
}

///|
test "escape_js_string_with_single_quote" {
  let result = escape_js_string("it's")
  assert_eq(result, "it\\'s")
}

///|
test "escape_js_string_with_double_quote" {
  let result = escape_js_string("a\"b")
  assert_eq(result, "a\\\"b")
}

///|
test "escape_js_string_with_control_chars" {
  assert_eq(escape_js_string("a\nb"), "a\\nb")
  assert_eq(escape_js_string("a\rb"), "a\\rb")
  assert_eq(escape_js_string("a\tb"), "a\\tb")
}

// ── Scroll Dispatch Tests ───────────────────────────────────────────────────

///|
test "scroll_dispatch_attempts_native_then_fallback" {
  // Without MCP, both native scroll_page and evaluate_script fallback fail.
  // Verifies the dispatch chain executes without panicking.
  let browser = Browser::new()
  let args : Map[String, Json] = {
    "direction": "down".to_json(),
    "amount": (300).to_json(),
  }
  let result = browser.dispatch_act("scroll", args)
  assert_true(result.is_error)
  assert_true(
    result.content.find("MCP") is Some(_) ||
    result.content.find("not connected") is Some(_),
  )
}

///|
test "scroll_fallback_produces_evaluate_script_args" {
  // Verify that the evaluate_script fallback builds correct scrollBy JS
  let args : Map[String, Json] = {
    "direction": "down".to_json(),
    "amount": (500).to_json(),
  }
  let result = build_mcp_evaluate_args(args)
  let s = result.stringify()
  assert_true(s.find("scrollBy") is Some(_))
  assert_true(s.find("500") is Some(_))
}

///|
test "scroll_up_produces_negative_offset" {
  let args : Map[String, Json] = {
    "direction": "up".to_json(),
    "amount": (200).to_json(),
  }
  let result = build_mcp_evaluate_args(args)
  let s = result.stringify()
  assert_true(s.find("scrollBy") is Some(_))
  assert_true(s.find("-200") is Some(_) || s.find("- 200") is Some(_))
}

// ── Fill Enhancement Tests ──────────────────────────────────────────────────

///|
test "fill_dispatch_degrades_gracefully_without_mcp" {
  // Without MCP, fill fails but focus/blur failures are silently ignored.
  // The fill result itself should be an error (MCP not connected).
  let browser = Browser::new()
  let args : Map[String, Json] = {
    "action": "act".to_json(),
    "kind": "fill".to_json(),
    "ref": "e5".to_json(),
    "text": "hello".to_json(),
  }
  let result = browser.dispatch_act("fill", args)
  assert_true(result.is_error)
  assert_true(
    result.content.find("MCP") is Some(_) ||
    result.content.find("not connected") is Some(_),
  )
}

///|
test "type_alias_uses_fill_enhanced_dispatch" {
  // type is an alias for fill — should use the same enhanced dispatch path.
  let browser = Browser::new()
  let args : Map[String, Json] = {
    "action": "act".to_json(),
    "kind": "type".to_json(),
    "ref": "e3".to_json(),
    "text": "test input".to_json(),
  }
  let result = browser.dispatch_act("type", args)
  assert_true(result.is_error)
  assert_true(
    result.content.find("MCP") is Some(_) ||
    result.content.find("not connected") is Some(_),
  )
}

///|
test "fill_without_ref_skips_focus_blur" {
  // Without ref, focus/blur enhancement is skipped entirely.
  // fill still fails due to no MCP, but no crash from missing ref.
  let browser = Browser::new()
  let args : Map[String, Json] = { "text": "hello".to_json() }
  let result = browser.dispatch_fill_enhanced(args)
  assert_true(result.is_error)
}

// ── Snapshot Compression Threshold & Logging Tests (Task #4) ────────────────

///|
/// Helper: build a large snapshot string exceeding the 150KB threshold.
fn build_large_snapshot(line_count : Int) -> String {
  let parts : Array[String] = []
  let mut i = 0
  while i < line_count {
    // Each line ~80 chars: mix of StaticText and noise to exercise both stages
    if i % 3 == 0 {
      parts.push(
        "  StaticText: Lorem ipsum dolor sit amet consectetur adipiscing elit sed do",
      )
    } else if i % 3 == 1 {
      parts.push(
        "  StaticText: eiusmod tempor incididunt ut labore et dolore magna aliqua ut",
      )
    } else {
      parts.push("  ()")
    }
    i = i + 1
  }
  join_browser_parts(parts, "\n")
}

///|
/// Test: snapshots below the 150KB threshold skip two-stage compression.
test "compress_snapshot_below_threshold_skips_compression" {
  // Build a small snapshot well under 150KB (153600 chars)
  let small = "line1\nline2\nline3\n  StaticText: hello\n  StaticText: world"
  let result = compress_snapshot(small)
  // Should NOT contain the compression log marker
  assert_true(result.find("[snapshot-compress]") is None)
  // Result should be equivalent to plain truncation (small input won't be truncated)
  let expected = truncate_browser_output(small, max_snapshot_chars)
  assert_eq(result, expected)
}

///|
/// Test: snapshots above the 150KB threshold trigger two-stage compression.
test "compress_snapshot_above_threshold_triggers_compression" {
  // Build a snapshot > 150KB: ~3500 lines * ~53 chars avg = ~185KB
  let large = build_large_snapshot(3500)
  // Confirm input exceeds threshold
  assert_true(large.length() > snapshot_compress_threshold)
  let result = compress_snapshot(large)
  // Should contain the compression log marker
  assert_true(result.find("[snapshot-compress]") is Some(_))
}

///|
/// Test: compression log format includes three-stage sizes and ratio.
test "compress_snapshot_log_format" {
  let large = build_large_snapshot(3500)
  let result = compress_snapshot(large)
  // Log should be on the first line as a comment
  let first_newline = result.find("\n")
  assert_true(first_newline is Some(_))
  // Extract the first line (the log comment)
  let log_line = match first_newline {
    Some(pos) => result[:pos].to_owned()
    None => result
  }
  // Verify log format markers
  assert_true(log_line.has_prefix("// [snapshot-compress]"))
  assert_true(log_line.find("original=") is Some(_))
  assert_true(log_line.find("stage1=") is Some(_))
  assert_true(log_line.find("stage2=") is Some(_))
  assert_true(log_line.find("ratio=") is Some(_))
  assert_true(log_line.find("kb") is Some(_))
  // Verify ratio ends with %)
  assert_true(log_line.find("%)") is Some(_))
}

///|
/// Test: compression actually reduces size for large snapshots with noise.
test "compress_snapshot_reduces_size" {
  let large = build_large_snapshot(3500)
  let result = compress_snapshot(large)
  // The result (including log line) should be significantly smaller than input
  // because noise lines "()" are removed and StaticText lines are merged
  // Note: result is also truncated to max_snapshot_chars (8000)
  assert_true(result.length() < large.length())
}
