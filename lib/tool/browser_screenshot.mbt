// ── Screenshot Pipeline ────────────────────────────────────────────────────

///|
/// Maximum screenshot width before downscaling (pixels).
/// TODO: used when libpng FFI is available for downscaling.
let _max_screenshot_width : Int = 800

///|
/// Maximum screenshot file size (bytes). Images above this are noted as oversized.
let max_screenshot_bytes : Int = 150 * 1024 // 150 KB

///|
/// Get the system temporary directory for saving screenshots.
fn get_screenshot_temp_dir() -> String {
  let dir = match @sys.get_env_var("TEMP") {
    Some(d) => d
    None =>
      match @sys.get_env_var("TMPDIR") {
        Some(d) => d
        None => "/tmp"
      }
  }
  let subdir = @path.Path(dir).join(@path.Path("mbopenclacky_screenshots"))
  let subdir_str = subdir.to_string()
  if !@fs.path_exists(subdir_str) {
    @fs.create_dir(subdir_str) catch {
      _ => ()
    }
  }
  subdir_str
}

///|
/// Generate a unique screenshot filename using timestamp.
/// Fix: [H1] 截图文件计数器并发不安全 — 改用时间戳确保文件名唯一性
fn next_screenshot_filename(ext? : String = "png") -> String {
  let ts = @async.now()
  "screenshot_\{ts}.\{ext}"
}

///|
/// Format a screenshot MCP response for LLM consumption.
/// Saves the raw image to a temp directory (or custom save_path), checks the
/// 150KB size limit, and returns a structured `{ content_string, image_inject }` payload.
/// `format` controls output mime: "jpeg" → image/jpeg, default "png" → image/png.
/// `save_path` optionally overrides the default temp-dir save location.
/// TODO: 800px downscaling requires libpng FFI — currently skipped.
pub fn format_screenshot_result(
  mcp_output : String,
  ref_param? : String? = None,
  format? : String? = None,
  save_path? : String? = None,
) -> String {
  // Resolve output format: mime type and file extension
  let fmt = match format {
    Some("jpeg") => "jpeg"
    Some("jpg") => "jpeg"
    _ => "png"
  }
  let mime_type = if fmt == "jpeg" { "image/jpeg" } else { "image/png" }
  let ext = if fmt == "jpeg" { "jpg" } else { "png" }
  let parts : Array[String] = []
  // Determine if this was an element-level or full-page screenshot
  let caption = match ref_param {
    Some(r) => "Screenshot captured for element ref=\{r}"
    None => "Full-page screenshot captured"
  }
  parts.push(caption)
  parts.push("format: \{fmt}")
  // Attempt to extract base64 image data and save to disk
  let base64_data = extract_base64_image(mcp_output)
  match base64_data {
    Some(b64) => {
      let png_bytes = @base64.decode(b64.view()) catch {
        _ => {
          // Base64 decode failed — return inline reference without saving to disk
          parts.push("")
          parts.push("[image_inject]")
          parts.push("mime_type: \{mime_type}")
          parts.push("base64_data: (\{b64.length()} chars, decode failed)")
          parts.push("")
          parts.push("Note: Base64 decoding failed. Raw data reference above.")
          return join_browser_parts(parts, "\n")
        }
      }
      let byte_len = png_bytes.length()
      if byte_len == 0 {
        parts.push("")
        parts.push("[image_inject]")
        parts.push("mime_type: \{mime_type}")
        parts.push("base64_data: (\{b64.length()} chars)")
        parts.push("")
        parts.push("Note: Decoded image is empty. Raw data reference above.")
        return join_browser_parts(parts, "\n")
      }
      // Resolve save location: custom save_path or temp directory
      let filepath = match save_path {
        Some(sp) => sp
        None => {
          let temp_dir = get_screenshot_temp_dir()
          let filename = next_screenshot_filename(ext~)
          @path.Path(temp_dir).join(@path.Path(filename)).to_string()
        }
      }
      @fs.write_bytes_to_file(filepath, png_bytes) catch {
        _ => {
          parts.push("")
          parts.push("[image_inject]")
          parts.push("mime_type: \{mime_type}")
          parts.push("base64_data: (\{b64.length()} chars)")
          parts.push("")
          parts.push(
            "Note: Failed to save screenshot to disk. Image data returned inline.",
          )
          return join_browser_parts(parts, "\n")
        }
      }
      parts.push("")
      parts.push("[image_inject]")
      parts.push("mime_type: \{mime_type}")
      parts.push("base64_data: (\{b64.length()} chars)")
      parts.push("path: \{filepath}")
      parts.push("size: \{byte_len} bytes")
      // Size limit check
      if byte_len > max_screenshot_bytes {
        parts.push("")
        parts.push(
          "⚠ Screenshot is \{byte_len / 1024}KB (limit \{max_screenshot_bytes / 1024}KB). Consider using snapshot instead for text-heavy pages.",
        )
      }
      // TODO: downscale to max_screenshot_width px — requires libpng FFI
      // TODO: maxWidth/maxHeight enforcement requires MCP clip or libpng FFI
    }
    None => {
      // MCP returned text-only output (no base64 image)
      parts.push("")
      parts.push(mcp_output)
    }
  }
  join_browser_parts(parts, "\n")
}

///|
/// Try to extract a base64 image payload from the MCP screenshot response.
/// Looks for common patterns: data URI prefix or raw base64 block.
fn extract_base64_image(mcp_output : String) -> String? {
  // Pattern 1: data URI — "data:image/png;base64,<data>"
  match mcp_output.find("base64,") {
    Some(idx) => {
      let start = idx + 7
      if start < mcp_output.length() {
        return Some(mcp_output[start:].to_owned().trim().to_owned())
      }
      return None
    }
    None => ()
  }
  // Pattern 2: line starting with a long base64 string (>100 chars, only [A-Za-z0-9+/=])
  for sv in mcp_output.split("\n") {
    let line = sv.trim().to_owned()
    if line.length() > 100 && is_base64_like(line) {
      return Some(line)
    }
  }
  None
}

///|
/// Heuristic check: does the string look like base64 (only valid chars)?
fn is_base64_like(s : String) -> Bool {
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    let valid = (c >= 'A' && c <= 'Z') ||
      (c >= 'a' && c <= 'z') ||
      (c >= '0' && c <= '9') ||
      c == '+' ||
      c == '/' ||
      c == '='
    if !valid {
      return false
    }
    i = i + 1
  }
  true
}
