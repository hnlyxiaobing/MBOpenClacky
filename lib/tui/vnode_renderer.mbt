///|
/// VNode-based terminal renderer.
///
/// Replaces the imperative ScreenBuffer + LayoutManager rendering approach
/// with mizchi/tui's declarative VNode tree and diff-based rendering engine.

///|

///|
/// Query terminal size, falling back to 80x24 on error.
fn query_size_safe(tty : @tty.Tty) -> (Int, Int) {
  try tty.window_size() catch {
    _ => (80, 24)
  } noraise {
    size =>
      (
        if size.cols < 1 {
          80
        } else {
          size.cols
        },
        if size.rows < 1 {
          24
        } else {
          size.rows
        },
      )
  }
}

///|
/// Renderer that wraps a VNodeApp and tty handle for screen rendering.
struct VNodeRenderer {
  tty : @tty.Tty
  app : @tui.VNodeApp
}

///|
/// Create a new VNodeRenderer from a Tty handle.
fn VNodeRenderer::new(tty : @tty.Tty) -> VNodeRenderer {
  let (width, height) = query_size_safe(tty)
  { tty, app: @tui.VNodeApp::new(width, height) }
}

///|
/// Update terminal dimensions on resize.
fn VNodeRenderer::resize(
  self : VNodeRenderer,
  width : Int,
  height : Int,
) -> Unit {
  self.app.resize(width, height)
}

///|
/// Render a VNode tree to the terminal.
///
/// On first call, writes the full screen. On subsequent calls, uses
/// VNodeApp's diff engine to write only changed cells.
async fn VNodeRenderer::render(
  self : VNodeRenderer,
  node : @tui.TuiNode,
) -> Unit {
  let output = self.app.render_frame(node)
  self.tty.write_string(output)
}

// ── ANSI-to-VNode Parser ─────────────────────────────────────────────────────

///|
/// A text segment with ANSI-derived style information.
priv struct AnsiSegment {
  text : String
  fg : String?
  bold : Bool
  dim : Bool
}

///|
/// Mutable style state tracked while parsing ANSI escape codes.
priv struct AnsiStyleState {
  mut fg : String?
  mut bold : Bool
  mut dim : Bool
}

///|
/// Parse a string with ANSI escape codes into styled text segments.
///
/// Handles SGR sequences (ESC[...m) for foreground colors, bold, and dim.
/// Non-SGR escape sequences (cursor positioning, OSC, etc.) are stripped.
fn parse_ansi_segments(s : String) -> Array[AnsiSegment] {
  let segments : Array[AnsiSegment] = []
  let current = StringBuilder::new()
  let state = AnsiStyleState::{ fg: None, bold: false, dim: false }
  // Parse state: 0=normal, 1=after_esc, 2=in_csi, 3=in_osc, 4=osc_after_esc
  let mut parse_state = 0
  let csi_buf = StringBuilder::new()
  for c in s.iter() {
    match parse_state {
      0 =>
        if c == '\u{1b}' {
          // Flush current text segment
          flush_segment(segments, current, state)
          parse_state = 1
        } else {
          current.write_char(c)
        }
      1 =>
        if c == '[' {
          csi_buf.reset()
          parse_state = 2
        } else if c == ']' {
          parse_state = 3
        } else {
          // Other escape: flush and return to normal
          parse_state = 0
        }
      2 =>
        // Collect CSI parameters until terminator
        if c.to_int() >= 0x40 && c.to_int() <= 0x7E {
          // Terminator found
          if c == 'm' {
            apply_sgr(state, csi_buf.to_string())
          }
          // For non-SGR sequences, just discard
          parse_state = 0
        } else {
          csi_buf.write_char(c)
        }
      3 =>
        if c == '\u{07}' {
          parse_state = 0
        } else if c == '\u{1b}' {
          parse_state = 4
        }
      _ => parse_state = 0
    }
  }
  // Flush final text segment
  flush_segment(segments, current, state)
  segments
}

///|
/// Flush the current text buffer as a segment with the current style.
fn flush_segment(
  segments : Array[AnsiSegment],
  buf : StringBuilder,
  state : AnsiStyleState,
) -> Unit {
  let text = buf.to_string()
  if text.length() == 0 {
    return
  }
  segments.push({ text, fg: state.fg, bold: state.bold, dim: state.dim })
  buf.reset()
}

///|
/// Apply an SGR (Select Graphic Rendition) parameter string to the style state.
fn apply_sgr(state : AnsiStyleState, params_str : String) -> Unit {
  let params = parse_sgr_params(params_str)
  let mut i = 0
  while i < params.length() {
    let code = params[i]
    match code {
      0 => {
        state.fg = None
        state.bold = false
        state.dim = false
      }
      1 => state.bold = true
      2 => state.dim = true
      22 => {
        state.bold = false
        state.dim = false
      }
      30 => state.fg = Some("black")
      31 => state.fg = Some("red")
      32 => state.fg = Some("green")
      33 => state.fg = Some("yellow")
      34 => state.fg = Some("blue")
      35 => state.fg = Some("magenta")
      36 => state.fg = Some("cyan")
      37 => state.fg = Some("white")
      39 => state.fg = None
      90 => state.fg = Some("rgb(128,128,128)")
      91 => state.fg = Some("rgb(255,85,85)")
      92 => state.fg = Some("rgb(85,255,85)")
      93 => state.fg = Some("rgb(255,255,85)")
      94 => state.fg = Some("rgb(85,85,255)")
      95 => state.fg = Some("rgb(255,85,255)")
      96 => state.fg = Some("rgb(85,255,255)")
      97 => state.fg = Some("rgb(255,255,255)")
      38 =>
        // Extended foreground: 38;5;N (256-color) or 38;2;R;G;B (truecolor)
        if i + 1 < params.length() {
          if params[i + 1] == 5 && i + 2 < params.length() {
            state.fg = Some(ansi_256_to_rgb(params[i + 2]))
            i = i + 2
          } else if params[i + 1] == 2 && i + 4 < params.length() {
            state.fg = Some(
              "rgb(\{params[i + 2]},\{params[i + 3]},\{params[i + 4]})",
            )
            i = i + 4
          }
        }
      _ => ()
    }
    i = i + 1
  }
}

///|
/// Parse SGR parameter string "1;31;2" into [1, 31, 2].
fn parse_sgr_params(s : String) -> Array[Int] {
  let result : Array[Int] = []
  let parts = s.split(";")
  for part in parts {
    let trimmed = part.trim()
    if trimmed.length() > 0 {
      let n = @string.parse_int(trimmed) catch { _ => -1 }
      if n >= 0 {
        result.push(n)
      }
    }
  }
  result
}

///|
/// Convert ANSI 256-color index to an rgb() CSS color string.
fn ansi_256_to_rgb(idx : Int) -> String {
  if idx < 8 {
    // Standard colors
    match idx {
      0 => "black"
      1 => "red"
      2 => "green"
      3 => "yellow"
      4 => "blue"
      5 => "magenta"
      6 => "cyan"
      _ => "white"
    }
  } else if idx < 16 {
    // Bright colors
    match idx {
      8 => "rgb(128,128,128)"
      9 => "rgb(255,85,85)"
      10 => "rgb(85,255,85)"
      11 => "rgb(255,255,85)"
      12 => "rgb(85,85,255)"
      13 => "rgb(255,85,255)"
      14 => "rgb(85,255,255)"
      _ => "rgb(255,255,255)"
    }
  } else if idx < 232 {
    // 6x6x6 color cube
    let i = idx - 16
    let r = if i / 36 > 0 { 55 + i / 36 * 40 } else { 0 }
    let g = if i % 36 / 6 > 0 { 55 + i % 36 / 6 * 40 } else { 0 }
    let b = if i % 6 > 0 { 55 + i % 6 * 40 } else { 0 }
    "rgb(\{r},\{g},\{b})"
  } else {
    // Grayscale ramp
    let v = 8 + (idx - 232) * 10
    "rgb(\{v},\{v},\{v})"
  }
}

///|
/// Convert an ANSI-coded string to a VNode tree preserving colors.
///
/// Parses SGR color codes and creates VNode text nodes with appropriate
/// fg colors. Multiple colored segments are placed in a row.
fn ansi_line_to_vnode(s : String) -> @tui.TuiNode {
  let segments = parse_ansi_segments(s)
  if segments.is_empty() {
    return @tui.text(" ")
  }
  // Check if all segments have the same style (optimization)
  if segments.length() == 1 {
    let seg = segments[0]
    return make_text_vnode(seg)
  }
  // Multiple segments: create a row of text nodes
  let children : Array[@tui.TuiNode] = []
  for seg in segments {
    if seg.text.length() > 0 {
      children.push(make_text_vnode(seg))
    }
  }
  if children.is_empty() {
    return @tui.text(" ")
  }
  @tui.row(children)
}

///|
/// Convert an ANSI-coded string to a single flat VNode row with explicit
/// size constraints applied directly to the row that holds the text segments.
///
/// Unlike `ansi_line_to_vnode` (which returns a bare `@tui.row(children)`),
/// this avoids wrapping that row in a second sized row. The nested
/// row-in-row structure was found to trigger per-segment width mismeasurement
/// in the mizchi/tui flexbox layout, truncating the last characters of each
/// colored segment (see SPEC-01 / BUG-001). The status bar uses this sized
/// variant so the width/height constraints live on the same row that owns the
/// text children.
fn ansi_line_to_vnode_sized(
  s : String,
  width : Double,
  height : Double,
) -> @tui.TuiNode {
  let segments = parse_ansi_segments(s)
  let children : Array[@tui.TuiNode] = []
  for seg in segments {
    if seg.text.length() > 0 {
      children.push(make_text_vnode(seg))
    }
  }
  if children.is_empty() {
    children.push(@tui.text(" "))
  }
  @tui.row(width~, height~, children)
}

///|
/// Create a VNode text node from an AnsiSegment.
fn make_text_vnode(seg : AnsiSegment) -> @tui.TuiNode {
  let fg = match seg.fg {
    Some(c) => c
    None => "white"
  }
  if seg.dim {
    @tui.text(seg.text, fg="rgb(128,128,128)", bold=seg.bold)
  } else {
    @tui.text(seg.text, fg~, bold=seg.bold)
  }
}

///|
/// Strip ANSI escape codes from a string (for plain text contexts).
fn strip_ansi(s : String) -> String {
  let segments = parse_ansi_segments(s)
  let result = StringBuilder::new()
  for seg in segments {
    result.write_string(seg.text)
  }
  result.to_string()
}
