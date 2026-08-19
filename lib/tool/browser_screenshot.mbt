// ── Screenshot Pipeline ────────────────────────────────────────────────────

///|
/// Maximum screenshot width before downscaling (pixels) — Ruby SCREENSHOT_MAX_WIDTH.
let screenshot_max_width : Int = 800

///|
/// Maximum screenshot payload size after downscaling (bytes) — Ruby
/// SCREENSHOT_MAX_BASE64_BYTES. Images that still exceed this after resize
/// are rejected with a hint to use snapshot (aligned with Ruby browser.rb).
let screenshot_max_bytes : Int = 150 * 1024 // 150 KB

///|
/// Uploads directory name under the system temp dir — Ruby `clacky-uploads`.
let uploads_dir_name : String = "clacky-uploads"

///|
/// Synchronous shell runner via the C popen stub (see browser_popen.c).
/// Needed because @process.run is async while the browser tool chain is
/// synchronous, and MoonBit core has no image/zlib package for pure-MoonBit
/// PNG downscaling (Ruby uses the chunky_png gem instead).
#borrow(cmd)
extern "C" fn popen_run_ffi(cmd : String) -> Int64 = "mbopenclacky_popen_run"

///|
/// Run a shell command synchronously; true when the child exited 0.
/// Real output must be redirected to a file by the caller.
fn run_command_sync(command : String) -> Bool {
  popen_run_ffi(command) == 0L
}

///|
/// Get the system temporary directory (TEMP → TMPDIR → /tmp).
fn get_temp_dir_path() -> String {
  match @env.get_env_var("TEMP") {
    Some(d) => d
    None =>
      match @env.get_env_var("TMPDIR") {
        Some(d) => d
        None => "/tmp"
      }
  }
}

///|
/// Get the screenshot uploads directory `$TMPDIR/clacky-uploads/`
/// (Ruby `save_screenshot_to_disk` uses the same location).
fn get_screenshot_upload_dir() -> String {
  let dir = @path.Path(get_temp_dir_path())
    .join(@path.Path(uploads_dir_name))
    .to_string()
  if !@fs.path_exists(dir) {
    @fs.create_dir(dir) catch {
      _ => ()
    }
  }
  dir
}

///|
/// Screenshot filename `screenshot_{YYYYMMDD_HHMMSS}_{hex8}_{suffix}.png`
/// — Ruby `save_screenshot_to_disk` naming (hex 8 chars).
fn screenshot_filename(
  hex : String,
  suffix? : String = "",
  ext? : String = "png",
) -> String {
  let stamp = now_stamp().replace(old="-", new="_")
  let label = if suffix.is_empty() { "" } else { "_" + suffix }
  "screenshot_\{stamp}_\{hex}\{label}.\{ext}"
}

///|
/// Parse the PNG width from the IHDR chunk (bytes 16..20, big-endian).
/// Returns None for non-PNG data.
fn png_width(image : Bytes) -> Int? {
  if image.length() < 24 {
    return None
  }
  let sig : Array[Int] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
  let mut i = 0
  while i < 8 {
    if image[i].to_int() != sig[i] {
      return None
    }
    i = i + 1
  }
  // IHDR: length(4) + "IHDR"(4) + width(4 big-endian)
  let w = (image[16].to_int() << 24) |
    (image[17].to_int() << 16) |
    (image[18].to_int() << 8) |
    image[19].to_int()
  Some(w)
}

///|
/// Quote a path for embedding in a shell command line.
/// POSIX: single-quote wrapping (no injection); Windows: double-quote.
fn quote_shell_arg(arg : String, is_win : Bool) -> String {
  if is_win {
    "\"" + arg + "\""
  } else {
    "'" + arg.replace(old="'", new="'\\''") + "'"
  }
}

///|
/// Build candidate downscale commands (highest priority first).
/// magick/convert: ImageMagick; sips: macOS; python3(+PIL): fallback.
/// Each command reads `in_path`, writes `out_path`, exit 0 on success.
fn build_downscale_cmds(
  in_path : String,
  out_path : String,
  max_width : Int,
) -> Array[String] {
  let is_win = shell_is_windows()
  let in_q = quote_shell_arg(in_path, is_win)
  let out_q = quote_shell_arg(out_path, is_win)
  let cmds : Array[String] = []
  if is_win {
    cmds.push("magick \{in_q} -resize \{max_width}x -strip \{out_q}")
    cmds.push("convert \{in_q} -resize \{max_width}x -strip \{out_q}")
    // cmd.exe: outer double quotes, Python code uses single-quoted paths
    cmds.push(
      "python -c \"from PIL import Image; im=Image.open('\{in_path.replace(old="'", new="")}'); im.thumbnail((\{max_width},\{max_width})); im.save('\{out_path.replace(old="'", new="")}')\"",
    )
  } else {
    cmds.push("magick \{in_q} -resize \{max_width}x -strip \{out_q}")
    cmds.push("convert \{in_q} -resize \{max_width}x -strip \{out_q}")
    cmds.push("sips -Z \{max_width} \{in_q} --out \{out_q}")
    // shell single quotes around the whole -c program; paths inside use
    // double quotes (safe inside single quotes)
    cmds.push(
      "python3 -c 'from PIL import Image; im=Image.open(\"\{in_path}\"); im.thumbnail((\{max_width},\{max_width})); im.save(\"\{out_path}\")'",
    )
  }
  cmds
}

///|
/// Downscale PNG bytes so width ≤ max_width, mirroring Ruby
/// `downscale_png_chunky`: no-op when already within width, CLI resize
/// otherwise. Returns None when no tool is available or the input is not
/// a decodable PNG (caller keeps the original — Ruby fallback).
fn downscale_image_bytes(image : Bytes, max_width : Int) -> Bytes? {
  let w = match png_width(image) {
    Some(w) => w
    None => return None
  }
  if w <= max_width {
    return Some(image)
  }
  let tmp_dir = get_temp_dir_path()
  let ts = @env.now().reinterpret_as_int64()
  let in_path = @path.Path::join(
    tmp_dir,
    @path.Path("mbopenclacky_ds_in_\{ts}.png"),
  ).to_string()
  let out_path = @path.Path::join(
    tmp_dir,
    @path.Path("mbopenclacky_ds_out_\{ts}.png"),
  ).to_string()
  @fs.write_bytes_to_file(in_path, image) catch {
    _ => return None
  }
  let mut result : Bytes? = None
  let cmds = build_downscale_cmds(in_path, out_path, max_width)
  // while instead of for: a `for` in value position would be treated as a
  // yielding loop and demand an else branch
  let mut i = 0
  while i < cmds.length() && result is None {
    let cmd = cmds[i]
    if run_command_sync(cmd) {
      // catch recovers with an empty Bytes (catch must produce the error
      // carrier's success type, not an Option)
      let out = @fs.read_file_to_bytes(out_path) catch {
        _ => Bytes::makei(0, fn(_) { (0 : Int).to_byte() })
      }
      if out.length() > 0 {
        result = Some(out)
      }
    }
    i = i + 1
  }
  @fs.remove_file(in_path) catch {
    _ => ()
  }
  @fs.remove_file(out_path) catch {
    _ => ()
  }
  result
}

///|
/// Format a screenshot MCP response for LLM consumption.
///
/// Aligned with Ruby `browser.rb#format_result_for_llm` screenshot branch:
/// 1. original (full-resolution) PNG is saved to `$TMPDIR/clacky-uploads/`;
/// 2. the image is downscaled to `screenshot_max_width` px (800);
/// 3. if the downscaled payload still exceeds `screenshot_max_bytes`
///    (150KB) the result is rejected with a hint to use snapshot instead;
/// 4. the compressed PNG is saved with a `_compressed` suffix;
/// 5. the real base64 payload rides in the `[image_inject]` sidecar block
///    (consumed by B2 `extract_image_inject` → user image block).
///
/// `format` controls output mime: "jpeg" → image/jpeg, default "png" →
/// image/png. `save_path` optionally overrides the original save location
/// (MB extension, kept for backward compatibility).
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
      if png_bytes.length() == 0 {
        parts.push("")
        parts.push("[image_inject]")
        parts.push("mime_type: \{mime_type}")
        parts.push("base64_data: (\{b64.length()} chars)")
        parts.push("")
        parts.push("Note: Decoded image is empty. Raw data reference above.")
        return join_browser_parts(parts, "\n")
      }
      // 1. Save original (full-resolution) — Ruby save_screenshot_to_disk(suffix: "original")
      let upload_dir = get_screenshot_upload_dir()
      let hex = random_hex(8)
      let original_name = screenshot_filename(hex, suffix="original", ext~)
      let original_path = match save_path {
        Some(sp) => sp
        None =>
          @path.Path(upload_dir).join(@path.Path(original_name)).to_string()
      }
      @fs.write_bytes_to_file(original_path, png_bytes) catch {
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
      // 2. Downscale to 800px — Ruby downscale_png_chunky
      let downscaled = downscale_image_bytes(png_bytes, screenshot_max_width)
      let compressed_bytes = match downscaled {
        Some(b) => b
        None => png_bytes // no tool available — Ruby keeps original
      }
      // 3. Reject when still over the size budget after resize (Ruby does the
      //    same: `Screenshot too large after resize (XKB). Use action=snapshot instead.`)
      if compressed_bytes.length() > screenshot_max_bytes {
        let size_kb = compressed_bytes.length() / 1024
        return "Screenshot too large after resize (\{size_kb}KB). Use action=snapshot instead."
      }
      // 4. Save compressed (800px) for AI reference — suffix: "compressed"
      let compressed_name = screenshot_filename(hex, suffix="compressed", ext~)
      let compressed_path = @path.Path(upload_dir)
        .join(@path.Path(compressed_name))
        .to_string()
      @fs.write_bytes_to_file(compressed_path, compressed_bytes) catch {
        _ => {
          parts.push("")
          parts.push("[image_inject]")
          parts.push("mime_type: \{mime_type}")
          parts.push("base64_data: (\{b64.length()} chars)")
          parts.push("")
          parts.push(
            "Note: Failed to save compressed screenshot to disk. Image data returned inline.",
          )
          return join_browser_parts(parts, "\n")
        }
      }
      // 5. Compose Ruby-style result: content_string + real image_inject payload
      let compressed_b64 = @base64.encode(compressed_bytes.view())
      parts.push("")
      parts.push("Screenshot captured.")
      parts.push("- Original (full resolution): \{original_path}")
      parts.push(
        "- Compressed (\{screenshot_max_width}px, sent to AI): \{compressed_path}",
      )
      if downscaled is None {
        parts.push(
          "Note: no downscaling tool available (magick/convert/sips/python3-PIL) — saved original resolution.",
        )
      }
      parts.push("size: \{compressed_bytes.length()} bytes")
      parts.push("")
      parts.push("[image_inject]")
      parts.push("mime_type: \{mime_type}")
      parts.push("base64_data: \{compressed_b64}")
      parts.push("path: \{compressed_path}")
      join_browser_parts(parts, "\n")
    }
    None => {
      // MCP returned text-only output (no base64 image)
      parts.push("")
      parts.push(mcp_output)
      join_browser_parts(parts, "\n")
    }
  }
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
