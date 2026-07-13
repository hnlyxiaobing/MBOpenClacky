///|
/// Banner renderer for displaying styled text banners in the terminal.
/// Supports Boxed, Minimal, and Block rendering styles.

///|
/// Banner rendering style
pub enum BannerStyle {
  Boxed // Box drawing characters border
  Minimal // Simple separator lines
  Block // Unicode block font
} derive(Debug, Eq)

///|
/// Banner renderer
pub(all) struct Banner {
  style : BannerStyle
  width : Int
  use_color : Bool
} derive(Eq, Debug)

///|
/// Create a new Banner with default style (Boxed, width 60, no color).
pub fn Banner::new() -> Banner {
  { style: Boxed, width: 60, use_color: false }
}

///|
/// Create a new Banner with custom width (Boxed style, no color).
pub fn Banner::with_width(width : Int) -> Banner {
  { style: Boxed, width, use_color: false }
}

///|
/// Create with custom style.
pub fn Banner::with_style(style : BannerStyle) -> Banner {
  { style, width: 60, use_color: false }
}

///|
/// Create with custom style and width.
pub fn Banner::with_style_and_width(style : BannerStyle, width : Int) -> Banner {
  { style, width, use_color: false }
}

///|
/// Compute an adaptive banner width based on terminal width.
/// Returns min(terminal_width - 4, 60), with a minimum of 20.
pub fn Banner::adaptive_width(terminal_width : Int) -> Int {
  let w = terminal_width - 4
  if w < 20 {
    20
  } else if w > 60 {
    60
  } else {
    w
  }
}

///|
/// Render a banner with title and optional subtitle.
pub fn Banner::render(
  self : Banner,
  title : String,
  subtitle : String?,
) -> String {
  match self.style {
    Boxed => self.render_boxed(title, subtitle)
    Minimal => self.render_simple(title, subtitle)
    Block => {
      let font = @utils.BlockFont::new()
      let lines = font.render_text(title)
      let sep = self.render_separator()
      let parts : Array[String] = [sep]
      for line in lines {
        parts.push(self.colorize(line))
      }
      match subtitle {
        Some(sub) => parts.push(self.colorize("  \{sub}"))
        None => ()
      }
      parts.push(sep)
      parts.join("\n")
    }
  }
}

///|
/// Render a simple text banner with separator lines.
pub fn Banner::render_simple(
  self : Banner,
  text : String,
  subtitle : String?,
) -> String {
  let sep = self.render_separator()
  let centered = self.center_text(text, self.width)
  let parts : Array[String] = [sep, self.colorize(centered)]
  match subtitle {
    Some(sub) => {
      let s : String = sub
      parts.push(self.colorize(self.center_text(s, self.width)))
    }
    None => ()
  }
  parts.push(sep)
  parts.join("\n")
}

///|
/// Render a separator line of the configured width.
pub fn Banner::render_separator(self : Banner) -> String {
  match self.style {
    Boxed => {
      let inner_width = self.width - 2
      let line = "═".repeat(inner_width)
      if self.use_color {
        "\u{1b}[36m\{line}\u{1b}[0m"
      } else {
        line
      }
    }
    _ => {
      let line = "─".repeat(self.width)
      if self.use_color {
        "\u{1b}[36m\{line}\u{1b}[0m"
      } else {
        line
      }
    }
  }
}

///|
/// Render with box border using box-drawing characters.
pub fn Banner::render_boxed(
  self : Banner,
  title : String,
  subtitle : String?,
) -> String {
  let inner_width = self.width - 4 // 2 for borders + 2 for padding
  let top = self.box_corner("╔", "╗", "═", self.width - 2)
  let bottom = self.box_corner("╚", "╝", "═", self.width - 2)
  let empty_line = self.box_row("", inner_width)
  let title_line = self.box_row(
    self.center_text(title, inner_width),
    inner_width,
  )
  let parts : Array[String] = [top, empty_line]
  parts.push(self.colorize(title_line))
  match subtitle {
    Some(sub) => {
      let s : String = sub
      let sub_line = self.box_row(self.center_text(s, inner_width), inner_width)
      parts.push(self.colorize(sub_line))
    }
    None => ()
  }
  parts.push(empty_line)
  parts.push(bottom)
  parts.join("\n")
}

///|
/// Build a box corner line like ╔══════╗ or ╚══════╝.
fn Banner::box_corner(
  self : Banner,
  left : String,
  right : String,
  fill : String,
  width : Int,
) -> String {
  let line = "\{left}\{fill.repeat(width)}\{right}"
  if self.use_color {
    "\u{1b}[36m\{line}\u{1b}[0m"
  } else {
    line
  }
}

///|
/// Build a box row with side borders.
fn Banner::box_row(
  self : Banner,
  content : String,
  inner_width : Int,
) -> String {
  let padding = inner_width - content.length()
  let left_pad = padding / 2
  let right_pad = padding - left_pad
  let line = "║\{" ".repeat(left_pad)}\{content}\{" ".repeat(right_pad)}║"
  if self.use_color {
    let border = "\u{1b}[36m"
    let reset = "\u{1b}[0m"
    "\{border}║\{reset}\{" ".repeat(left_pad)}\{content}\{" ".repeat(right_pad)}\{border}║\{reset}"
  } else {
    line
  }
}

///|
/// Center a text within a given width.
fn Banner::center_text(self : Banner, text : String, width : Int) -> String {
  let _ = self
  let padding = width - text.length()
  if padding <= 0 {
    return text
  }
  let left = padding / 2
  let right = padding - left
  "\{" ".repeat(left)}\{text}\{" ".repeat(right)}"
}

///|
/// Apply ANSI color codes if use_color is enabled.
fn Banner::colorize(self : Banner, text : String) -> String {
  if self.use_color {
    "\u{1b}[1m\u{1b}[36m\{text}\u{1b}[0m"
  } else {
    text
  }
}
