///|
/// Line-model rendering primitives.
///
/// The TUI frame path renders the whole screen as an array of text lines
/// (Ruby ui2 line-level repaint model): every line is written to the tty
/// with a clear-line prefix, so physical scrolling from commit-scrollback
/// can never leave stale fragments behind (the VNode coordinate-diff
/// engine fundamentally conflicted with scrolling — BUG-004).

///|
/// Strip ANSI escape sequences from a string.
pub fn strip_ansi(s : String) -> String {
  let buf = StringBuilder::new()
  // Parse state: 0=normal, 1=after_esc, 2=in_csi, 3=in_osc, 4=osc_after_esc
  let mut parse_state = 0
  for c in s.iter() {
    match parse_state {
      0 => if c == '\u{1b}' { parse_state = 1 } else { buf.write_char(c) }
      1 =>
        if c == '[' {
          parse_state = 2
        } else if c == ']' {
          parse_state = 3
        } else {
          parse_state = 0
        }
      2 => if c.to_int() >= 0x40 && c.to_int() <= 0x7E { parse_state = 0 }
      3 =>
        if c == '\u{07}' {
          parse_state = 0
        } else if c == '\u{1b}' {
          parse_state = 4
        }
      _ => if c == '\u{07}' { parse_state = 0 } else { parse_state = 0 }
    }
  }
  buf.to_string()
}

///|
/// Display width of a string in terminal columns (ANSI-aware, CJK-aware).
pub fn ansi_display_width(s : String) -> Int {
  let plain = strip_ansi(s)
  let mut w = 0
  for c in plain.iter() {
    w = w + @tui_core.char_display_width(c)
  }
  w
}

///|
/// Pad a possibly ANSI-styled line with trailing spaces up to `width`
/// display columns (no-op when already at or beyond the width).
pub fn pad_ansi_line(line : String, width : Int) -> String {
  let w = ansi_display_width(line)
  if w >= width {
    line
  } else {
    line + " ".repeat(width - w)
  }
}

///|
/// Compose the full screen as exactly `term_height` lines: body (output
/// area, top-aligned, bottom-clipped) above the fixed bottom area.
///
/// When the fixed area alone exceeds the screen, its TOP lines are dropped
/// so the input area at the bottom always stays visible.
pub fn compose_screen_lines(
  body : Array[String],
  fixed : Array[String],
  term_height : Int,
) -> Array[String] {
  if term_height <= 0 {
    return []
  }
  let fixed_lines = if fixed.length() > term_height {
    let start = fixed.length() - term_height
    let kept : Array[String] = []
    for i = start; i < fixed.length(); i = i + 1 {
      kept.push(fixed[i])
    }
    kept
  } else {
    fixed
  }
  let msg_height = term_height - fixed_lines.length()
  let lines : Array[String] = []
  let body_n = if body.length() < msg_height {
    body.length()
  } else {
    msg_height
  }
  for i = 0; i < body_n; i = i + 1 {
    lines.push(body[i])
  }
  for _ in body_n..<msg_height {
    lines.push("")
  }
  for line in fixed_lines {
    lines.push(line)
  }
  lines
}

// ── Style → ANSI ─────────────────────────────────────────────────────

///|
/// Convert a Node Style to an SGR prefix (empty when the style is plain).
fn style_prefix(style : Style) -> String {
  let buf = StringBuilder::new()
  if style.bold {
    buf.write_string("\u{1b}[1m")
  }
  if style.dim {
    buf.write_string("\u{1b}[2m")
  }
  match style.fg {
    Some(c) => buf.write_string(color_prefix(c, false))
    None => ()
  }
  match style.bg {
    Some(c) => buf.write_string(color_prefix(c, true))
    None => ()
  }
  buf.to_string()
}

///|
/// SGR color sequence for a @color.Color (fg when bg=false, bg otherwise).
fn color_prefix(color : @color.Color, bg : Bool) -> String {
  match color {
    @color.Color::Default => ""
    @color.Color::Indexed(n) =>
      if bg {
        "\u{1b}[48;5;\{n}m"
      } else {
        "\u{1b}[38;5;\{n}m"
      }
    @color.Color::Rgb(r, g, b) =>
      if bg {
        "\u{1b}[48;2;\{r};\{g};\{b}m"
      } else {
        "\u{1b}[38;2;\{r};\{g};\{b}m"
      }
    @color.Color::Basic(basic) => {
      let idx = match basic {
        @color.BasicColor::Black => 0
        @color.BasicColor::Red => 1
        @color.BasicColor::Green => 2
        @color.BasicColor::Yellow => 3
        @color.BasicColor::Blue => 4
        @color.BasicColor::Magenta => 5
        @color.BasicColor::Cyan => 6
        @color.BasicColor::White => 7
        @color.BasicColor::BrightBlack => 8
        @color.BasicColor::BrightRed => 9
        @color.BasicColor::BrightGreen => 10
        @color.BasicColor::BrightYellow => 11
        @color.BasicColor::BrightBlue => 12
        @color.BasicColor::BrightMagenta => 13
        @color.BasicColor::BrightCyan => 14
        @color.BasicColor::BrightWhite => 15
      }
      if bg {
        if idx < 8 {
          "\u{1b}[4\{idx}m"
        } else {
          "\u{1b}[10\{idx - 8}m"
        }
      } else if idx < 8 {
        "\u{1b}[3\{idx}m"
      } else {
        "\u{1b}[9\{idx - 8}m"
      }
    }
  }
}

///|
/// Apply a style prefix + reset around a content line.
fn styled_line(prefix : String, content : String) -> String {
  if prefix.length() == 0 {
    content
  } else {
    prefix + content + "\u{1b}[0m"
  }
}

// ── Node → lines ─────────────────────────────────────────────────────

///|
/// Render a Node tree to an array of display lines with ANSI styling.
///
/// Borders render as rounded boxes sized to their content; Rows join
/// single-line children horizontally (multi-line children fall back to
/// vertical stacking, which dialogs never produce).
pub fn node_to_lines(node : Node) -> Array[String] {
  match node {
    Empty => []
    Text(content, style) => [styled_line(style_prefix(style), content)]
    Column(children) => {
      let lines : Array[String] = []
      for child in children {
        for line in node_to_lines(child) {
          lines.push(line)
        }
      }
      lines
    }
    Row(children) => {
      let child_lines : Array[Array[String]] = []
      let mut all_single = true
      for child in children {
        let ls = node_to_lines(child)
        if ls.length() != 1 {
          all_single = false
        }
        child_lines.push(ls)
      }
      if all_single {
        let buf = StringBuilder::new()
        for ls in child_lines {
          if ls.length() == 1 {
            buf.write_string(ls[0])
          }
        }
        [buf.to_string()]
      } else {
        let lines : Array[String] = []
        for ls in child_lines {
          for line in ls {
            lines.push(line)
          }
        }
        lines
      }
    }
    Styled(style, child) => {
      let prefix = style_prefix(style)
      let lines : Array[String] = []
      for line in node_to_lines(child) {
        lines.push(styled_line(prefix, line))
      }
      lines
    }
    Padding(v, h, child) => {
      let lines : Array[String] = []
      for _ in 0..<v {
        lines.push("")
      }
      let pad = " ".repeat(h)
      for line in node_to_lines(child) {
        lines.push(pad + line)
      }
      for _ in 0..<v {
        lines.push("")
      }
      lines
    }
    Border(title, children) => {
      let content : Array[String] = []
      for child in children {
        for line in node_to_lines(child) {
          content.push(line)
        }
      }
      // Box inner width fits the widest content line and the title.
      let mut inner = 1
      for line in content {
        let w = ansi_display_width(line)
        if w > inner {
          inner = w
        }
      }
      let title_text = match title {
        Some(t) => t
        None => ""
      }
      let title_w = ansi_display_width(title_text)
      if title_w + 2 > inner {
        inner = title_w + 2
      }
      let box_w = inner + 4 // "│ " + inner + " │"
      let lines : Array[String] = []
      // Top border with optional title: ╭─ title ───╮
      if title_text.length() > 0 {
        let dashes = box_w - 5 - title_w
        lines.push(
          "╭─ \{title_text} " +
          "─".repeat(if dashes > 0 { dashes } else { 0 }) +
          "╮",
        )
      } else {
        lines.push("╭" + "─".repeat(box_w - 2) + "╮")
      }
      for line in content {
        lines.push("│ " + pad_ansi_line(line, inner) + " │")
      }
      lines.push("╰" + "─".repeat(box_w - 2) + "╯")
      lines
    }
  }
}
