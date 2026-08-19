///| White-box tests for browser form interaction enhancements.

///| Tests scroll native dispatch, fallback, fill focus/blur, and graceful degradation.

///|
/// Extract the value of a `marker`-prefixed line (e.g. "base64_data: ...").
fn extract_marked_line(result : String, marker : String) -> String? {
  for sv in result.split("\n") {
    let line = sv.trim().to_owned()
    if line.starts_with(marker) {
      return Some(line[marker.length():].to_owned().trim().to_owned())
    }
  }
  None
}

///|
/// Test: PNG wider than 800px is downscaled to 800px (via python3+PIL when
/// available) — Ruby downscale_png_chunky alignment. Verifies dual file
/// saves (original + compressed) and a real base64 payload in image_inject.
test "screenshot_downscale_real_png_via_pil" {
  let has_pil = run_command_sync("python3 -c 'import PIL'")
  if !has_pil {
    println("SKIP: python3+PIL not available")
    return
  }
  let tmp_dir = get_temp_dir_path()
  let src = @path.Path::join(tmp_dir, @path.Path("mbopenclacky_test_1000.png")).to_string()
  let gen = "python3 -c 'from PIL import Image; im=Image.new(\"RGB\",(1000,600),(255,0,0)); im.save(\"\{src}\")'"
  assert_true(run_command_sync(gen), msg="PIL PNG generation should succeed")
  let png_bytes = @fs.read_file_to_bytes(src) catch {
    _ => Bytes::makei(0, fn(_) { (0 : Int).to_byte() })
  }
  @fs.remove_file(src) catch {
    _ => ()
  }
  assert_true(png_bytes.length() > 0, msg="test PNG should be non-empty")
  // Original width must be 1000 (> 800 → triggers downscale)
  assert_eq(png_width(png_bytes), Some(1000))
  let b64 = @base64.encode(png_bytes.view())
  let result = format_screenshot_result("data:image/png;base64,\{b64}")
  assert_true(result.find("Screenshot captured.") is Some(_))
  assert_true(result.find("- Original (full resolution):") is Some(_))
  assert_true(result.find("- Compressed (800px, sent to AI):") is Some(_))
  // The injected payload must be real base64 of an 800px image (not a placeholder)
  match extract_marked_line(result, "base64_data: ") {
    Some(b64_data) => {
      assert_true(
        b64_data != "(\{b64.length()} chars)",
        msg="must be real payload",
      )
      let decoded = @base64.decode(b64_data.view()) catch {
        _ => Bytes::makei(0, fn(_) { (0 : Int).to_byte() })
      }
      assert_eq(png_width(decoded), Some(800))
    }
    None => assert_true(false, msg="image_inject base64_data missing")
  }
  // Both files must exist on disk under $TMPDIR/clacky-uploads/
  match extract_marked_line(result, "path: ") {
    Some(p) =>
      assert_true(@fs.path_exists(p), msg="compressed file should exist")
    None => assert_true(false, msg="image_inject path missing")
  }
}

///|
/// Test: PNG already ≤ 800px is returned as-is (no tool invocation) and
/// still produces a successful result with real payload.
test "screenshot_small_png_kept_as_is" {
  let has_pil = run_command_sync("python3 -c 'import PIL'")
  if !has_pil {
    println("SKIP: python3+PIL not available")
    return
  }
  let tmp_dir = get_temp_dir_path()
  let src = @path.Path::join(tmp_dir, @path.Path("mbopenclacky_test_600.png")).to_string()
  let gen = "python3 -c 'from PIL import Image; im=Image.new(\"RGB\",(600,400),(0,128,255)); im.save(\"\{src}\")'"
  assert_true(run_command_sync(gen))
  let png_bytes = @fs.read_file_to_bytes(src) catch {
    _ => Bytes::makei(0, fn(_) { (0 : Int).to_byte() })
  }
  @fs.remove_file(src) catch {
    _ => ()
  }
  assert_eq(png_width(png_bytes), Some(600))
  let b64 = @base64.encode(png_bytes.view())
  let result = format_screenshot_result("data:image/png;base64,\{b64}")
  assert_true(result.find("Screenshot captured.") is Some(_))
  // No downscale note should appear (kept original resolution)
  assert_true(result.find("no downscaling tool") is None)
  // size must equal the original bytes length
  match extract_marked_line(result, "size: ") {
    Some(sz) => {
      let expected = png_bytes.length().to_string()
      assert_true(sz.starts_with(expected), msg="size should be original bytes")
    }
    None => assert_true(false, msg="size line missing")
  }
}

///|
/// Test: screenshot that stays over 150KB after downscaling is rejected with
/// the Ruby-aligned hint (Use action=snapshot instead).
test "screenshot_too_large_rejected_after_resize" {
  let has_pil = run_command_sync("python3 -c 'import PIL'")
  if !has_pil {
    println("SKIP: python3+PIL not available")
    return
  }
  let tmp_dir = get_temp_dir_path()
  let src = @path.Path::join(tmp_dir, @path.Path("mbopenclacky_test_noise.png")).to_string()
  // 1600x1600 random noise → downscale to 800x800 still ≫ 150KB
  let gen = "python3 -c 'import random; from PIL import Image; im=Image.new(\"RGB\",(1600,1600)); im.putdata([(random.randint(0,255),random.randint(0,255),random.randint(0,255)) for _ in range(1600*1600)]); im.save(\"\{src}\")'"
  assert_true(run_command_sync(gen))
  let png_bytes = @fs.read_file_to_bytes(src) catch {
    _ => Bytes::makei(0, fn(_) { (0 : Int).to_byte() })
  }
  @fs.remove_file(src) catch {
    _ => ()
  }
  assert_true(
    png_bytes.length() > 150 * 1024,
    msg="noise PNG should exceed 150KB already",
  )
  let b64 = @base64.encode(png_bytes.view())
  let result = format_screenshot_result("data:image/png;base64,\{b64}")
  assert_true(
    result.find("Screenshot too large after resize") is Some(_),
    msg="should reject oversized screenshot",
  )
  assert_true(result.find("Use action=snapshot instead") is Some(_))
}

///|
/// Test: PNG without PIL support (non-PNG data) — no crash, decode fallback
/// keeps original payload as placeholder reference.
test "screenshot_invalid_png_bytes_no_crash" {
  // 4 random bytes — valid base64, invalid PNG
  let fake_b64 = "dGVzdA=="
  let result = format_screenshot_result("data:image/png;base64,\{fake_b64}")
  assert_true(result.find("mime_type: image/png") is Some(_))
  assert_true(result.find("format: png") is Some(_))
  // decodes to 4 bytes → not a PNG → png_width None → downscale skipped,
  // still within size budget → success with real payload
  assert_true(result.find("Screenshot captured.") is Some(_))
  assert_true(result.find("base64_data: dGVzdA==") is Some(_))
}

///|
/// Test: save_path overrides original file location (MB extension).
test "screenshot_save_path_override" {
  let fake_b64 = "dGVzdA=="
  let custom = @path.Path(get_temp_dir_path())
    .join(@path.Path("mbopenclacky_custom_screenshot.png"))
    .to_string()
  let result = format_screenshot_result(
    "data:image/png;base64,\{fake_b64}",
    save_path=Some(custom),
  )
  let has_path = result.find(custom) is Some(_)
  let has_fail_note = result.find("Failed to save") is Some(_)
  assert_true(has_path || has_fail_note)
  // clean up if written
  @fs.remove_file(custom) catch {
    _ => ()
  }
}

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
  let args : Map[String, Json] = Map([])
  let result = build_mcp_screenshot_args(args)
  let s = result.stringify()
  @debug.assert_eq(s, "{}")
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
  let args : Map[String, Json] = Map([])
  let result = build_mcp_scroll_args(args)
  let s = result.stringify()
  @debug.assert_eq(s, "{}")
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
  @debug.assert_eq(escape_js_string("e1"), "e1")
  @debug.assert_eq(escape_js_string("hello"), "hello")
}

///|
test "escape_js_string_with_backslash" {
  let result = escape_js_string("a\\b")
  @debug.assert_eq(result, "a\\\\b")
}

///|
test "escape_js_string_with_single_quote" {
  let result = escape_js_string("it's")
  @debug.assert_eq(result, "it\\'s")
}

///|
test "escape_js_string_with_double_quote" {
  let result = escape_js_string("a\"b")
  @debug.assert_eq(result, "a\\\"b")
}

///|
test "escape_js_string_with_control_chars" {
  @debug.assert_eq(escape_js_string("a\nb"), "a\\nb")
  @debug.assert_eq(escape_js_string("a\rb"), "a\\rb")
  @debug.assert_eq(escape_js_string("a\tb"), "a\\tb")
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
  @debug.assert_eq(result, expected)
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
