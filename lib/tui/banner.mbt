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
/// Create a Block-style banner with custom width (style variants are
/// read-only outside this package, hence a dedicated constructor).
pub fn Banner::block_with_width(width : Int) -> Banner {
  { style: Block, width, use_color: false }
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
        "\u{1b}[38;2;0;200;255m\{line}\u{1b}[0m"
      } else {
        line
      }
    }
    _ => {
      let line = "─".repeat(self.width)
      if self.use_color {
        "\u{1b}[38;2;0;200;255m\{line}\u{1b}[0m"
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
    "\u{1b}[38;2;0;200;255m\{line}\u{1b}[0m"
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
    let border = "\u{1b}[38;2;0;200;255m"
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
    "\u{1b}[1m\u{1b}[38;2;0;200;255m\{text}\u{1b}[0m"
  } else {
    text
  }
}

// ── Multi-section startup banner ────────────────────────────────────

///|
/// Minimum terminal width for showing the full ASCII art logo.
/// Below this width, the logo degrades to a plain text welcome line.
pub let min_width_for_logo : Int = 90

///|
/// Tagline shown below the logo (aligned with the OpenClacky baseline
/// `[>]` prefix; wording matches this project's assistant identity).
let banner_tagline : String =
  "[>] Your personal Assistant & Technical Co-founder"

///|
/// Usage tips shown at startup (aligned with the OpenClacky baseline:
/// four `[*]`-prefixed entries, including the `.clackyrules / AGENTS.md`
/// customization hint that MB previously lacked).
let banner_tips : Array[String] = [
  "Press Tab for completions, /help for commands",
  "Type your message and press Enter to chat",
  "Create .clackyrules or AGENTS.md to customize behavior",
  "Use Ctrl+J for newlines, Ctrl+V to paste text",
]

///|
/// Render the full multi-section startup banner.
///
/// `terminal_width` is the actual terminal column count, used to decide
/// whether to show the full ASCII art logo (>= 90) or a plain text fallback.
///
/// Sections:
/// 1. Logo (block font or plain text if terminal < 90 cols)
/// 2. Tagline + version
/// 3. Tips
/// 4. AGENT MODE separator
/// 5. Info lines (working dir, mode, rules)
/// 6. Optional API key warning
pub fn Banner::render_startup(
  self : Banner,
  version : String,
  working_dir : String,
  permission_mode : String,
  has_rules : Bool,
  api_key_missing : Bool,
  terminal_width? : Int = 0,
) -> String {
  let effective_width = if terminal_width > 0 {
    terminal_width
  } else {
    self.width
  }
  let sections : Array[String] = []
  // Section 1: Logo
  sections.push(self.render_logo_section(effective_width))
  // Section 2: Tagline + version
  sections.push(self.render_tagline_section(version))
  // Section 3: Tips
  sections.push(self.render_tips_section())
  // Section 4: AGENT MODE separator
  sections.push(self.render_agent_mode_section())
  // Section 5: Info lines
  sections.push(
    self.render_info_section(working_dir, permission_mode, has_rules),
  )
  // Section 6: Exit hint (aligned with the OpenClacky baseline)
  sections.push(self.render_exit_hint())
  // Section 7: Optional API key warning
  if api_key_missing {
    sections.push(self.render_api_key_warning())
  }
  sections.join("\n")
}

///|
/// Render the logo section: block font for wide terminals, plain text for narrow.
fn Banner::render_logo_section(self : Banner, effective_width : Int) -> String {
  if effective_width >= min_width_for_logo {
    // Full block font logo
    let font = @utils.BlockFont::new()
    let lines = font.render_text("MBOpenClacky")
    let parts : Array[String] = []
    for line in lines {
      parts.push(self.colorize(line))
    }
    parts.join("\n")
  } else {
    // Narrow terminal: plain text fallback
    self.colorize("Welcome, MBOpenClacky is here")
  }
}

///|
/// Render the tagline + version section.
///
/// Aligned with the OpenClacky baseline: the tagline stands on its own
/// line and the version is rendered as a separate dim line (`Version x.y.z`)
/// rather than being appended to the tagline.
fn Banner::render_tagline_section(self : Banner, version : String) -> String {
  let tagline = "  \{banner_tagline}"
  let version_line = "  Version \{version}"
  if self.use_color {
    "\u{1b}[38;2;0;200;255m\{tagline}\u{1b}[0m\n\u{1b}[2m\{version_line}\u{1b}[0m"
  } else {
    "\{tagline}\n\{version_line}"
  }
}

///|
/// Render the tips section.
fn Banner::render_tips_section(self : Banner) -> String {
  let parts : Array[String] = []
  for tip in banner_tips {
    let line = "  [*] \{tip}"
    if self.use_color {
      parts.push("\u{1b}[2m\{line}\u{1b}[0m")
    } else {
      parts.push(line)
    }
  }
  parts.join("\n")
}

///|
/// Render the AGENT MODE separator section.
///
/// Aligned with the OpenClacky baseline: a `[+] AGENT MODE INITIALIZED`
/// header followed by a line of `=` (instead of a centered `─ AGENT MODE ─`).
fn Banner::render_agent_mode_section(self : Banner) -> String {
  let bar_width = if self.width > 40 { 40 } else { self.width }
  let header = "  [+] AGENT MODE INITIALIZED"
  let bar = "  \{"=".repeat(bar_width)}"
  if self.use_color {
    "\u{1b}[1m\u{1b}[38;2;255;255;85m\{header}\u{1b}[0m\n\u{1b}[38;2;255;255;85m\{bar}\u{1b}[0m"
  } else {
    "\{header}\n\{bar}"
  }
}

///|
/// Render the info section with working directory, permission mode, and rules status.
fn Banner::render_info_section(
  self : Banner,
  working_dir : String,
  permission_mode : String,
  has_rules : Bool,
) -> String {
  let rules_str = if has_rules { "✓" } else { "—" }
  // Field labels aligned with the OpenClacky baseline (`[Working Directory]`,
  // `[Permission Mode]`). The `[Project Rules]` line is an MB value-add kept
  // in the same label style (no emoji) per the SPEC-04 decision.
  let parts : Array[String] = [
    "  [Working Directory] \{working_dir}",
    "  [Permission Mode] \{permission_mode}",
    "  [Project Rules] \{rules_str}",
  ]
  if self.use_color {
    let colored : Array[String] = []
    for line in parts {
      colored.push("\u{1b}[38;2;220;220;220m\{line}\u{1b}[0m")
    }
    colored.join("\n")
  } else {
    parts.join("\n")
  }
}

///|
/// Render the exit hint line (aligned with the OpenClacky baseline
/// `[!] Type 'exit' or 'quit' to terminate session`).
fn Banner::render_exit_hint(self : Banner) -> String {
  let line = "  [!] Type 'exit' or 'quit' to terminate session"
  if self.use_color {
    "\u{1b}[2m\{line}\u{1b}[0m"
  } else {
    line
  }
}

///|
/// Render the API key missing warning.
fn Banner::render_api_key_warning(self : Banner) -> String {
  let line = "  ⚠ [warning] No API key configured. Set OPENAI_API_KEY or use /config."
  if self.use_color {
    "\u{1b}[1m\u{1b}[38;2;255;255;85m\{line}\u{1b}[0m"
  } else {
    line
  }
}
