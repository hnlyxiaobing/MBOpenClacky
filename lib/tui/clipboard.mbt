///|
/// OSC 52 clipboard support for terminal text selection copy.
///
/// OSC 52 is an ANSI escape sequence that writes text to the system
/// clipboard, enabling copy operations in terminal environments that
/// support it (iTerm2, Windows Terminal, xterm, etc.).

///|
/// Base64 encoding alphabet as a char array for safe indexing.
let b64_chars : Array[Char] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".to_array()

///|
/// Encode a string to base64 (UTF-8 bytes).
fn base64_encode(text : String) -> String {
  // Convert string to UTF-8 byte array
  let bytes : Array[Int] = []
  for c in text.iter() {
    let cp = c.to_int()
    if cp < 0x80 {
      bytes.push(cp)
    } else if cp < 0x800 {
      bytes.push(0xC0 | (cp >> 6))
      bytes.push(0x80 | (cp & 0x3F))
    } else if cp < 0x10000 {
      bytes.push(0xE0 | (cp >> 12))
      bytes.push(0x80 | ((cp >> 6) & 0x3F))
      bytes.push(0x80 | (cp & 0x3F))
    } else {
      bytes.push(0xF0 | (cp >> 18))
      bytes.push(0x80 | ((cp >> 12) & 0x3F))
      bytes.push(0x80 | ((cp >> 6) & 0x3F))
      bytes.push(0x80 | (cp & 0x3F))
    }
  }
  // Base64 encode
  let result = StringBuilder()
  let len = bytes.length()
  let mut i = 0
  while i < len {
    let b0 = bytes[i]
    let b1 = if i + 1 < len { bytes[i + 1] } else { 0 }
    let b2 = if i + 2 < len { bytes[i + 2] } else { 0 }
    let triple = (b0 << 16) | (b1 << 8) | b2
    let idx0 = (triple >> 18) & 0x3F
    let idx1 = (triple >> 12) & 0x3F
    let idx2 = (triple >> 6) & 0x3F
    let idx3 = triple & 0x3F
    result.write_char(b64_chars[idx0])
    result.write_char(b64_chars[idx1])
    if i + 1 < len {
      result.write_char(b64_chars[idx2])
    } else {
      result.write_char('=')
    }
    if i + 2 < len {
      result.write_char(b64_chars[idx3])
    } else {
      result.write_char('=')
    }
    i = i + 3
  }
  result.to_string()
}

///|
/// Copy text to the system clipboard via OSC 52.
///
/// Sends the OSC 52 escape sequence to the terminal. The terminal
/// (if it supports OSC 52) will place the text on the clipboard.
async fn copy_to_clipboard(tty : @tty.Tty, text : String) -> Unit {
  let encoded = base64_encode(text)
  let osc52 = "\u{1b}]52;c;" + encoded + "\u{07}"
  tty.write_string(osc52)
}
