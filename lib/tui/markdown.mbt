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
  BlockQuote(text~ : String)
  HorizontalRule
  TaskItem(checked~ : Bool, text~ : String)
  Link(text~ : String, url~ : String)
  Table(headers~ : Array[String], rows~ : Array[Array[String]])
} derive(Eq, Debug)

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
let ansi_reset : String = "\u001b[0m"

///|
let ansi_bold : String = "\u001b[1m"

///|
let ansi_italic : String = "\u001b[3m"

///|
let ansi_cyan : String = "\u001b[38;2;0;200;255m"

///|
let ansi_yellow : String = "\u001b[38;2;255;255;85m"

///|
let ansi_gray : String = "\u001b[38;2;128;128;128m"

///|
let ansi_green : String = "\u001b[38;2;0;255;100m"

///|
let ansi_underline : String = "\u001b[4m"

///|
/// Tokenize a Markdown string into an array of tokens.
///
/// Supports: headings (#), bold (**), italic (*), inline code (`),
/// code blocks (```), list items (- ), block quotes (> ),
/// horizontal rules (---, ***, ___), and task lists (- [x] / - [ ]).
pub fn tokenize(input : String) -> Array[MarkdownToken] {
  let tokens : Array[MarkdownToken] = []
  let lines = split_lines_impl(input)
  let i = Ref(0)
  while i.val < lines.length() {
    let line = lines[i.val]
    if line.has_prefix("```") {
      // Code block
      let lang = line[3:].trim().to_owned()
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
      let text = line[4:].trim().to_owned()
      tokens.push(Heading(level=3, text~))
      i.val = i.val + 1
    } else if line.has_prefix("## ") {
      let text = line[3:].trim().to_owned()
      tokens.push(Heading(level=2, text~))
      i.val = i.val + 1
    } else if line.has_prefix("# ") {
      let text = line[2:].trim().to_owned()
      tokens.push(Heading(level=1, text~))
      i.val = i.val + 1
    } else if is_horizontal_rule_impl(line.trim().to_owned()) {
      tokens.push(HorizontalRule)
      i.val = i.val + 1
    } else if line.has_prefix("> ") {
      // Block quote
      let text = line[2:].trim().to_owned()
      tokens.push(BlockQuote(text~))
      i.val = i.val + 1
    } else if line.has_prefix("- ") ||
      line.has_prefix("  - ") ||
      line.has_prefix("    - ") {
      let indent = count_leading_spaces_impl(line) / 2
      let text = line.trim().to_owned()
      let text2 = if text.has_prefix("- ") { text[2:].to_owned() } else { text }
      // Check for task list checkbox pattern: [x] or [ ]
      if text2.has_prefix("[x] ") || text2.has_prefix("[X] ") {
        let task_text = text2[4:].to_owned()
        tokens.push(TaskItem(checked=true, text=task_text))
      } else if text2.has_prefix("[ ] ") {
        let task_text = text2[4:].to_owned()
        tokens.push(TaskItem(checked=false, text=task_text))
      } else {
        tokens.push(ListItem(indent~, text=text2))
      }
      i.val = i.val + 1
    } else if is_table_start(lines, i.val) {
      // GFM Table: | header | header |\n|--------|--------|\n| cell   | cell   |
      let header_cells = parse_table_row(lines[i.val])
      i.val = i.val + 1
      // Skip separator line (|---|---|)
      if i.val < lines.length() && is_table_separator(lines[i.val]) {
        i.val = i.val + 1
      }
      // Parse data rows
      let table_rows : Array[Array[String]] = []
      while i.val < lines.length() && is_table_row(lines[i.val]) {
        table_rows.push(parse_table_row(lines[i.val]))
        i.val = i.val + 1
      }
      tokens.push(Table(headers=header_cells, rows=table_rows))
    } else {
      // Parse inline elements within a paragraph line
      let trimmed = line.trim().to_owned()
      if trimmed.length() > 0 {
        // Check for inline bold, italic, code, links
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
/// Check whether a trimmed line is a horizontal rule.
///
/// A horizontal rule consists of 3 or more identical characters
/// from the set: `-`, `*`, `_`.
fn is_horizontal_rule_impl(line : String) -> Bool {
  let trimmed = line.trim()
  if trimmed.length() < 3 {
    return false
  }
  let chars = trimmed.to_array()
  let first = chars[0]
  if first != '-' && first != '*' && first != '_' {
    return false
  }
  for c in chars {
    if c != first {
      return false
    }
  }
  true
}

///|
/// Parse inline Markdown elements (bold, italic, code, links) from a single line.
fn parse_inline_impl(line : String) -> Array[MarkdownToken] {
  let tokens : Array[MarkdownToken] = []
  let chars = line.to_array()
  let buf = StringBuilder::new()
  let i = Ref(0)
  while i.val < chars.length() {
    if chars[i.val] == '[' {
      // Potential link: [text](url)
      let link = try_parse_link_impl(line, i.val)
      match link {
        Some((text, url, end_pos)) => {
          if buf.to_string().length() > 0 {
            tokens.push(Paragraph(text=buf.to_string()))
            buf.reset()
          }
          tokens.push(Link(text~, url~))
          i.val = end_pos
        }
        None => {
          buf.write_char(chars[i.val])
          i.val = i.val + 1
        }
      }
    } else if i.val + 1 < chars.length() &&
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
      let text = line[start:i.val].to_owned()
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
      let text = line[start:i.val].to_owned()
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
      let text = line[start:i.val].to_owned()
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
/// Attempt to parse a Markdown link `[text](url)` starting at position `start`.
///
/// Returns `Some((text, url, end_position))` on success, `None` if no
/// valid link pattern is found.
fn try_parse_link_impl(line : String, start : Int) -> (String, String, Int)? {
  let chars = line.to_array()
  if start >= chars.length() || chars[start] != '[' {
    return None
  }
  // Find closing ]
  let mut pos = start + 1
  while pos < chars.length() && chars[pos] != ']' {
    pos = pos + 1
  }
  if pos >= chars.length() {
    return None
  }
  let text = line[start + 1:pos].to_owned()
  pos = pos + 1
  // Expect immediately (
  if pos >= chars.length() || chars[pos] != '(' {
    return None
  }
  pos = pos + 1
  let url_start = pos
  while pos < chars.length() && chars[pos] != ')' {
    pos = pos + 1
  }
  if pos >= chars.length() {
    return None
  }
  let url = line[url_start:pos].to_owned()
  Some((text, url, pos + 1))
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
      BlockQuote(text~) => {
        out.write_string(ansi_gray)
        out.write_string("\u2502 ")
        out.write_string(text)
        out.write_string(ansi_reset)
        out.write_string("\n")
      }
      HorizontalRule => {
        out.write_string(self.theme.dim_color)
        out.write_string("\u2500".repeat(40))
        out.write_string(ansi_reset)
        out.write_string("\n")
      }
      TaskItem(checked~, text~) => {
        if checked {
          out.write_string(ansi_green)
          out.write_string("\u2611 ")
          out.write_string(text)
          out.write_string(ansi_reset)
        } else {
          out.write_string(ansi_gray)
          out.write_string("\u2610 ")
          out.write_string(text)
          out.write_string(ansi_reset)
        }
        out.write_string("\n")
      }
      Link(text~, url~) => {
        out.write_string(ansi_underline)
        out.write_string(text)
        out.write_string(ansi_reset)
        out.write_string(" (")
        out.write_string(url)
        out.write_string(")")
      }
      Table(headers~, rows~) => {
        let all_rows : Array[Array[String]] = [headers]
        for row in rows {
          all_rows.push(row)
        }
        let builder = @tabular.Builder::from_rows(all_rows)
        let table = builder.build().apply(@tabular.Style::rounded())
        out.write_string(table.to_string())
        out.write_string("\n")
      }
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

// GFM Table Parsing helpers

///|
fn is_table_row(line : String) -> Bool {
  line.contains("|")
}

///|
fn is_table_start(lines : Array[String], idx : Int) -> Bool {
  if idx >= lines.length() || idx + 1 >= lines.length() {
    return false
  }
  let line = lines[idx]
  let next = lines[idx + 1]
  is_table_row(line) && is_table_separator(next)
}

///|
fn is_table_separator(line : String) -> Bool {
  let trimmed = line.trim().to_owned()
  if !trimmed.contains("|") {
    return false
  }
  let parts = trimmed.split("|").collect()
  let mut has_dash = false
  for part in parts {
    let p = part.trim().to_owned()
    if p.length() == 0 {
      continue
    }
    if p.contains("-") {
      has_dash = true
    } else {
      return false
    }
  }
  has_dash
}

///|
fn parse_table_row(line : String) -> Array[String] {
  let trimmed = line.trim().to_owned()
  let mut s = trimmed
  if s.has_prefix("|") {
    s = s[1:].to_owned()
  }
  if s.has_suffix("|") {
    s = s[:s.length() - 1].to_owned()
  }
  let cells : Array[String] = []
  for cell in s.split("|") {
    cells.push(cell.trim().to_owned())
  }
  cells
}
