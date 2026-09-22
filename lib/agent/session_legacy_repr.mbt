///| Read-only recovery of session files persisted as the MoonBit `Json`
/// Debug repr instead of JSON text.

///|
/// Early builds wrote `json.to_repr()` into `<session_id>.json`, producing
/// bytes like `Object({session_id: String(s_1), messages: Array([...])})`.
/// Those files are not JSON, so every reader skipped them silently and the
/// sessions became invisible (list, panel and `inspect` alike).
///
/// This module projects the repr back into `Json` so the ordinary session
/// decoder can read it. Nothing is written back: recovery is a read-only
/// projection, and a document that does not parse cleanly to its end yields
/// `None` rather than a partial guess.

///|
/// Cursor over a legacy Debug-repr document.
priv struct LegacyReprCursor {
  text : String
  mut pos : Int
}

///|
fn is_repr_space(c : UInt16) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

///|
/// Characters that may follow the paren closing a `String(...)` /
/// `Number(...)` body when that body is the last value in its container.
fn is_repr_container_close(c : UInt16) -> Bool {
  c == ',' || c == '}' || c == ']'
}

///|
/// Match and consume `kw` at the cursor.
fn LegacyReprCursor::eat(self : LegacyReprCursor, kw : String) -> Bool {
  let end = self.pos + kw.length()
  if end > self.text.length() {
    return false
  }
  if self.text[self.pos:end].to_owned() == kw {
    self.pos = end
    true
  } else {
    false
  }
}

///|
fn LegacyReprCursor::take(self : LegacyReprCursor, expected : UInt16) -> Bool {
  if self.pos < self.text.length() && self.text[self.pos] == expected {
    self.pos = self.pos + 1
    true
  } else {
    false
  }
}

///|
fn LegacyReprCursor::skip_ws(self : LegacyReprCursor) -> Unit {
  while self.pos < self.text.length() && is_repr_space(self.text[self.pos]) {
    self.pos = self.pos + 1
  }
}

///|
/// Consume the raw body of `String(...)` / `Number(...)` up to its closing
/// paren.
///
/// The repr prints string content unescaped, so the closing paren is found
/// structurally: parens *inside* the body are balanced, and the body ends at
/// a `)` whose next non-space character closes the surrounding container
/// (`,`, `}` or `]`). A stray `)` in the content is kept as content. When the
/// text is truncated or a body swallows the rest of the document, the
/// enclosing parse fails and the file is reported unreadable instead of
/// yielding wrong content.
fn LegacyReprCursor::take_raw_body(self : LegacyReprCursor) -> String? {
  let start = self.pos
  let mut depth = 0
  while self.pos < self.text.length() {
    let c = self.text[self.pos]
    if c == '(' {
      depth = depth + 1
    } else if c == ')' {
      if depth > 0 {
        depth = depth - 1
      } else {
        let mut look = self.pos + 1
        while look < self.text.length() && is_repr_space(self.text[look]) {
          look = look + 1
        }
        if look < self.text.length() &&
          is_repr_container_close(self.text[look]) {
          let body = self.text[start:self.pos].to_owned()
          self.pos = self.pos + 1
          return Some(body)
        }
      }
    }
    self.pos = self.pos + 1
  }
  None
}

///|
/// Parse a `Number(...)` body, keeping the literal as the number's repr so
/// whole numbers survive the JSON round trip exactly.
fn parse_repr_number(body : String) -> Json? {
  let text = body.trim().to_owned()
  if text.is_empty() {
    return None
  }
  let is_float = text.find(".") is Some(_) ||
    text.find("e") is Some(_) ||
    text.find("E") is Some(_)
  if is_float {
    let value = @string.parse_double(text) catch { _ => return None }
    Some(Json::number(value))
  } else {
    let value = @string.parse_int64(text) catch { _ => return None }
    Some(Json::number(value.to_double(), repr=text))
  }
}

///|
fn LegacyReprCursor::parse_object_body(
  self : LegacyReprCursor,
) -> Map[String, Json]? {
  self.skip_ws()
  if !self.take('{') {
    return None
  }
  let result : Map[String, Json] = Map([])
  while true {
    self.skip_ws()
    if self.take('}') {
      return Some(result)
    }
    let key_start = self.pos
    while self.pos < self.text.length() && self.text[self.pos] != ':' {
      self.pos = self.pos + 1
    }
    if self.pos >= self.text.length() {
      return None
    }
    let key = self.text[key_start:self.pos].trim().to_owned()
    if key.is_empty() {
      return None
    }
    self.pos = self.pos + 1
    let value = match self.parse_value() {
      Some(v) => v
      None => return None
    }
    result[key] = value
    self.skip_ws()
    ignore(self.take(','))
  }
  // unreachable: every path above returns
  None
}

///|
fn LegacyReprCursor::parse_array_body(self : LegacyReprCursor) -> Array[Json]? {
  self.skip_ws()
  if !self.take('[') {
    return None
  }
  let result : Array[Json] = []
  while true {
    self.skip_ws()
    if self.take(']') {
      return Some(result)
    }
    let value = match self.parse_value() {
      Some(v) => v
      None => return None
    }
    result.push(value)
    self.skip_ws()
    ignore(self.take(','))
  }
  // unreachable: every path above returns
  None
}

///|
fn LegacyReprCursor::parse_value(self : LegacyReprCursor) -> Json? {
  self.skip_ws()
  if self.eat("Object(") {
    let body = self.parse_object_body()
    match body {
      Some(map) => if self.take(')') { Some(Json::object(map)) } else { None }
      None => None
    }
  } else if self.eat("Array(") {
    let body = self.parse_array_body()
    match body {
      Some(items) =>
        if self.take(')') {
          Some(Json::array(items))
        } else {
          None
        }
      None => None
    }
  } else if self.eat("String(") {
    match self.take_raw_body() {
      Some(body) => Some(Json::string(body))
      None => None
    }
  } else if self.eat("Number(") {
    match self.take_raw_body() {
      Some(body) => parse_repr_number(body)
      None => None
    }
  } else if self.eat("True") {
    Some(Json::boolean(true))
  } else if self.eat("False") {
    Some(Json::boolean(false))
  } else if self.eat("Null") {
    Some(Json::null())
  } else {
    None
  }
}

///|
/// True when the text looks like a legacy Debug-repr session document.
fn looks_like_legacy_repr(text : String) -> Bool {
  text.trim().to_owned().has_prefix("Object(")
}

///|
/// Project a legacy Debug-repr session document into `Json`.
/// Returns None when the text is not a repr document or does not parse
/// cleanly to its end.
fn parse_legacy_debug_repr(text : String) -> Json? {
  if !looks_like_legacy_repr(text) {
    return None
  }
  let doc = text.trim().to_owned()
  let cursor : LegacyReprCursor = { text: doc, pos: 0 }
  let value = match cursor.parse_value() {
    Some(v) => v
    None => return None
  }
  cursor.skip_ws()
  if cursor.pos != doc.length() {
    return None
  }
  Some(value)
}