///|
/// CodeView - simple syntax highlighted text renderer (token-based)
pub struct CodeView {
  text : Ref[String]
  mut width : Double
  mut height : Double
  mut border : @view.BorderStyle?
  mut padding : Double
  /// Highlighter callback: returns per-line segments (text, color)
  mut highlighter : (String) -> Array[Array[(String, @core.Color)]]
}

///|
pub fn CodeView::new(text : Ref[String]) -> CodeView {
  {
    text,
    width: 60.0,
    height: 16.0,
    border: Some(@view.BorderStyle::Single),
    padding: 1.0,
    highlighter: basic_ts_highlight,
  }
}

///|
pub fn CodeView::size(self : CodeView, w : Double, h : Double) -> CodeView {
  self.width = w
  self.height = h
  self
}

///|
pub fn CodeView::with_border(self : CodeView, style : @view.BorderStyle?) -> CodeView {
  self.border = style
  self
}

///|
pub fn CodeView::with_padding(self : CodeView, p : Double) -> CodeView {
  self.padding = p
  self
}

///|
pub fn CodeView::with_highlighter(
  self : CodeView,
  hi : (String) -> Array[Array[(String, @core.Color)]]
) -> CodeView {
  self.highlighter = hi
  self
}

///|
pub impl @view.Component for CodeView with render(self) {
  let lines = (self.highlighter)(self.text.val)

  let line_views : Array[@view.View] = []
  for i = 0; i < lines.length(); i = i + 1 {
    let segs = lines[i]
    let seg_views : Array[@view.View] = []
    for j = 0; j < segs.length(); j = j + 1 {
      let (seg_text, seg_color) = segs[j]
      seg_views.push(@view.View::text(seg_text, color=seg_color))
    }
    line_views.push(@view.View::container_views(seg_views).direction(@view.Direction::Row))
  }

  let mut container = @view.View::container_views(line_views)
    .direction(@view.Direction::Column)
    .width(self.width)
    .height(self.height)
    .padding(self.padding)
    .overflow_y(@view.Overflow::Hidden)

  match self.border {
    Some(b) => container = container.border(b, color=@core.Color::Gray)
    None => ()
  }
  container
}

///|
pub impl @view.Component for CodeView with handle_event(_self, _event) { false }

///|
pub impl @view.Component for CodeView with is_focusable(_self) { false }

///|
/// Very basic tokenizer for TS/JS-like syntax (keywords, strings, numbers, comments)
fn basic_ts_highlight(source : String) -> Array[Array[(String, @core.Color)]] {
  let out : Array[Array[(String, @core.Color)]] = []
  let lines = source.split("\n")
  lines.each(fn(view_line) {
    let line = view_line.to_string()
    out.push(highlight_line(line))
  })
  out
}

///|
fn is_digit(ch : Char) -> Bool { ch >= '0' && ch <= '9' }
fn is_ident_start(ch : Char) -> Bool { (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_' }
fn is_ident_part(ch : Char) -> Bool { is_ident_start(ch) || is_digit(ch) }

///|
fn highlight_line(line : String) -> Array[(String, @core.Color)] {
  let segs : Array[(String, @core.Color)] = []
  let default = @core.Color::White
  let kw = @core.Color::Cyan
  let ty = @core.Color::Yellow
  let strc = @core.Color::Green
  let com = @core.Color::Gray
  let num = @core.Color::Magenta

  // Handle comment start
  let mut i = 0
  let n = line.length()
  while i < n {
    // Line comment
    if i + 1 < n {
      match (line.get_char(i), line.get_char(i + 1)) {
        (Some('/'), Some('/')) => {
          let rest = substring_range(line, i, n)
          segs.push((rest, com))
          return segs
        }
        _ => ()
      }
    }
    // String literal '...' or "..."
    match line.get_char(i) {
      Some('"') | Some('\'') => {
        let quote = line.get_char(i).unwrap_or('"')
        let mut j = i + 1
        while j < n {
          match line.get_char(j) {
            Some(c) if c == quote => { j = j + 1; break }
            Some(_) => j = j + 1
            None => break
          }
        }
        segs.push((substring_range(line, i, j), strc))
        i = j
        continue
      }
      _ => ()
    }
    // Number
    match line.get_char(i) {
      Some(c) if is_digit(c) => {
        let mut j = i + 1
        while j < n {
          match line.get_char(j) {
            Some(d) if is_digit(d) => j = j + 1
            Some('.') => { j = j + 1; }
            _ => break
          }
        }
        segs.push((substring_range(line, i, j), num))
        i = j
        continue
      }
      _ => ()
    }
    // Identifier / keyword / type-ish (PascalCase)
    match line.get_char(i) {
      Some(c) if is_ident_start(c) => {
        let mut j = i + 1
        while j < n {
          match line.get_char(j) {
            Some(cc) if is_ident_part(cc) => j = j + 1
            _ => break
          }
        }
        let word = substring_range(line, i, j)
        let color = if is_keyword(word) { kw } else if is_pascal(word) { ty } else { default }
        segs.push((word, color))
        i = j
        continue
      }
      _ => ()
    }
    // Other single char
    match line.get_char(i) {
      Some(c) => segs.push((c.to_string(), default))
      None => ()
    }
    i = i + 1
  }
  segs
}

///|
fn substring_range(s : String, start : Int, end : Int) -> String {
  let chars : Array[Char] = []
  let mut i = start
  while i < end {
    match s.get_char(i) {
      Some(c) => chars.push(c)
      None => break
    }
    i = i + 1
  }
  String::from_array(chars)
}

///|
fn is_keyword(word : String) -> Bool {
  let kws = [
    "if", "else", "for", "while", "return", "function", "class", "new",
    "let", "const", "var", "import", "from", "export", "extends", "implements",
    "switch", "case", "break", "continue", "try", "catch", "finally", "throw",
    "as", "type", "interface", "enum", "public", "private", "protected", "static",
    "async", "await",
  ]
  for i = 0; i < kws.length(); i = i + 1 { if word == kws[i] { return true } }
  false
}

///|
fn is_pascal(word : String) -> Bool {
  match word.get_char(0) {
    Some(c) => c >= 'A' && c <= 'Z'
    None => false
  }
}
