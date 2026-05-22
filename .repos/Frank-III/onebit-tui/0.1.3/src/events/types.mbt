///|
/// Core event types for OneBit-TUI
pub(all) enum Event {
  Key(@ffi.KeyEvent)
  KeyMod(@ffi.KeyEvent, @ffi.KeyModifiers) // Key with modifiers
  Mouse(MouseEvent)
  Focus(Bool) // true = gained, false = lost
  Paste(String) // Bracketed paste event with pasted text
}

///|
pub(all) struct MouseEvent {
  x : Int
  y : Int
  button : MouseButton
  action : MouseAction
}

///|
pub(all) enum MouseButton {
  Left
  Right
  Middle
} derive(Eq)

///|
pub(all) enum MouseAction {
  Press
  Release
  Click
  DoubleClick
  Move
} derive(Eq)

///|
/// Common key codes for convenience
pub enum KeyCode {
  KeyEnter
  KeySpace
  KeyEscape
  KeyTab
  KeyBackspace
  KeyDelete
  KeyUp
  KeyDown
  KeyLeft
  KeyRight
  KeyHome
  KeyEnd
  KeyPageUp
  KeyPageDown
  KeyChar(Char)
  KeyF(Int) // F1-F12
}

///|
/// Convert FFI KeyEvent to our KeyCode
pub fn KeyCode::from_ffi(key : @ffi.KeyEvent) -> KeyCode {
  match key {
    @ffi.KeyEvent::Enter => KeyEnter
    @ffi.KeyEvent::Escape => KeyEscape
    @ffi.KeyEvent::Tab => KeyTab
    @ffi.KeyEvent::Backspace => KeyBackspace
    @ffi.KeyEvent::Delete => KeyDelete
    @ffi.KeyEvent::ArrowUp => KeyUp
    @ffi.KeyEvent::ArrowDown => KeyDown
    @ffi.KeyEvent::ArrowLeft => KeyLeft
    @ffi.KeyEvent::ArrowRight => KeyRight
    @ffi.KeyEvent::Home => KeyHome
    @ffi.KeyEvent::End => KeyEnd
    @ffi.KeyEvent::PageUp => KeyPageUp
    @ffi.KeyEvent::PageDown => KeyPageDown
    @ffi.KeyEvent::F(n) => KeyF(n)
    @ffi.KeyEvent::Char(c) =>
      if c == 32 {
        KeySpace
      } else {
        KeyChar(c.to_char().unwrap_or(' '))
      }
    @ffi.KeyEvent::Insert | @ffi.KeyEvent::Unknown => KeyChar(' ')
  }
}
