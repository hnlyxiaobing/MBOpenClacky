///|
/// Markdown to ANSI escape code renderer.
///
/// Provides a simple Markdown tokenizer and renderer that converts
/// basic Markdown syntax into ANSI-colored terminal output.

///|
/// Markdown token types produced by the tokenizer.
pub(all) enum MarkdownToken {
  Heading(level~ : Int, text~ : String)
  Bold(text~ : String)
  Italic(text~ : String)
  Code(text~ : String)
  CodeBlock(lang~ : String, code~ : String)
  ListItem(indent~ : Int, text~ : String)
  Paragraph(text~ : String)
} derive(Eq, Debug, Show)

///|
/// Renderer that converts Markdown to ANSI-colored strings.
pub(all) struct MarkdownRenderer {
  theme : Theme
} derive(Debug)

///|
/// Create a new MarkdownRenderer with a given theme.
pub fn MarkdownRenderer::new(theme~ : Theme) -> MarkdownRenderer {
  { theme, }
}

///|
/// ANSI escape code constants.
let ansi_reset : String = "\x1b[0m"

///|
let ansi_bold : String = "\x1b[1m"

///|
let ansi_italic : String = "\x1b[3m"

///|
let ansi_cyan : String = "\x1b[36m"

///|
let ansi_yellow : String = "\x1b[33m"

///|
/// Tokenize a Markdown string into an array of tokens.
///
/// Supports: headings (#), bold (**), italic (*), inline code (`),
/// code blocks (```), and list items (- ).
pub fn tokenize(input : String) -> Array[MarkdownToken] {
  let tokens : Array[MarkdownToken] = []
  let lines = split_lines_impl(input)
  let i = Ref(0)
  while i.val < lines.length() {
    let line = lines[i.val]
    if line.has_prefix("```") {
      // Code block
      let lang = line.substring(start=3).trim().to_string()
      let code_lines : Array[String] = []
      i.val = i.val + 1
      while i.val < lines.length() && !lines[i.val].has_prefix("```") {
        code_lines.push(lines[i.val])
        i.val = i.val + 1
      }
      // Skip closing ```
      if i.val < lines.length() {
        i.val = i.val + 1
      }
      let code = code_lines.join("\n")
      tokens.push(CodeBlock(lang~, code~))
    } else if line.has_prefix("### ") {
      let text = line.substring(start=4).trim().to_string()
      tokens.push(Heading(level=3, text~))
      i.val = i.val + 1
    } else if line.has_prefix("## ") {
      let text = line.substring(start=3).trim().to_string()
      tokens.push(Heading(level=2, text~))
      i.val = i.val + 1
    } else if line.has_prefix("# ") {
      let text = line.substring(start=2).trim().to_string()
      tokens.push(Heading(level=1, text~))
      i.val = i.val + 1
    } else if line.has_prefix("- ") ||
      line.has_prefix("  - ") ||
      line.has_prefix("    - ") {
      let indent = count_leading_spaces_impl(line) / 2
      let text = line.trim().to_string()
      let text2 = if text.has_prefix("- ") {
        text.substring(start=2)
      } else {
        text
      }
      tokens.push(ListItem(indent~, text=text2))
      i.val = i.val + 1
    } else {
      // Parse inline elements within a paragraph line
      let trimmed = line.trim().to_string()
      if trimmed.length() > 0 {
        // Check for inline bold, italic, code
        let parsed = parse_inline_impl(trimmed)
        for t in parsed {
          tokens.push(t)
        }
      }
      i.val = i.val + 1
    }
  }
  tokens
}

///|
/// Parse inline Markdown elements (bold, italic, code) from a single line.
fn parse_inline_impl(line : String) -> Array[MarkdownToken] {
  let tokens : Array[MarkdownToken] = []
  let chars = line.to_array()
  let buf = StringBuilder::new()
  let i = Ref(0)
  while i.val < chars.length() {
    if i.val + 1 < chars.length() &&
      chars[i.val] == '*' &&
      chars[i.val + 1] == '*' {
      // Bold: **text**
      if buf.to_string().length() > 0 {
        tokens.push(Paragraph(text=buf.to_string()))
        buf.reset()
      }
      i.val = i.val + 2
      let start = i.val
      while i.val + 1 < chars.length() &&
            !(chars[i.val] == '*' && chars[i.val + 1] == '*') {
        i.val = i.val + 1
      }
      let text = line.substring(start~, end=i.val)
      tokens.push(Bold(text~))
      if i.val + 1 < chars.length() {
        i.val = i.val + 2
      }
    } else if chars[i.val] == '*' &&
      (i.val + 1 >= chars.length() || chars[i.val + 1] != '*') {
      // Italic: *text*
      if buf.to_string().length() > 0 {
        tokens.push(Paragraph(text=buf.to_string()))
        buf.reset()
      }
      i.val = i.val + 1
      let start = i.val
      while i.val < chars.length() && chars[i.val] != '*' {
        i.val = i.val + 1
      }
      let text = line.substring(start~, end=i.val)
      tokens.push(Italic(text~))
      if i.val < chars.length() {
        i.val = i.val + 1
      }
    } else if chars[i.val] == '`' {
      // Inline code: `text`
      if buf.to_string().length() > 0 {
        tokens.push(Paragraph(text=buf.to_string()))
        buf.reset()
      }
      i.val = i.val + 1
      let start = i.val
      while i.val < chars.length() && chars[i.val] != '`' {
        i.val = i.val + 1
      }
      let text = line.substring(start~, end=i.val)
      tokens.push(Code(text~))
      if i.val < chars.length() {
        i.val = i.val + 1
      }
    } else {
      buf.write_char(chars[i.val])
      i.val = i.val + 1
    }
  }
  if buf.to_string().length() > 0 {
    tokens.push(Paragraph(text=buf.to_string()))
  }
  tokens
}

///|
/// Render a Markdown string to an ANSI-colored string.
pub fn MarkdownRenderer::render(
  self : MarkdownRenderer,
  input : String,
) -> String {
  let tokens = tokenize(input)
  let out = StringBuilder::new()
  for token in tokens {
    match token {
      Heading(level=_, text~) => {
        out.write_string(ansi_yellow)
        out.write_string(ansi_bold)
        out.write_string(text)
        out.write_string(ansi_reset)
        out.write_string("\n")
      }
      Bold(text~) => {
        out.write_string(ansi_bold)
        out.write_string(text)
        out.write_string(ansi_reset)
      }
      Italic(text~) => {
        out.write_string(ansi_italic)
        out.write_string(text)
        out.write_string(ansi_reset)
      }
      Code(text~) => {
        out.write_string(ansi_cyan)
        out.write_string(text)
        out.write_string(ansi_reset)
      }
      CodeBlock(lang=_, code~) => {
        out.write_string(ansi_cyan)
        out.write_string(code)
        out.write_string(ansi_reset)
        out.write_string("\n")
      }
      ListItem(indent~, text~) => {
        for j = 0; j < indent; j = j + 1 {
          out.write_string("  ")
        }
        out.write_string(self.theme.dim_color)
        out.write_string("\u2022 ")
        out.write_string(ansi_reset)
        out.write_string(text)
        out.write_string("\n")
      }
      Paragraph(text~) => out.write_string(text)
    }
  }
  out.to_string()
}

///|
/// Split a string into lines.
fn split_lines_impl(s : String) -> Array[String] {
  let lines : Array[String] = []
  let chars = s.to_array()
  let current = StringBuilder::new()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '\n' {
      lines.push(current.to_string())
      current.reset()
    } else if chars[i] == '\r' {
      // skip \r in \r\n
      continue
    } else {
      current.write_char(chars[i])
    }
  }
  // Don't forget the last line
  lines.push(current.to_string())
  lines
}

///|
/// Count leading spaces in a string.
fn count_leading_spaces_impl(s : String) -> Int {
  let chars = s.to_array()
  let mut count = 0
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == ' ' {
      count = count + 1
    } else {
      break
    }
  }
  count
}
