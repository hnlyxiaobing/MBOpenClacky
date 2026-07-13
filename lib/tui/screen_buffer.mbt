///|
/// ScreenBuffer: terminal rendering primitives wrapper.
///
/// Thin layer over tty's VT100 capabilities, providing semantic
/// rendering methods for the inline TUI. All write methods are async
/// because terminal I/O is inherently asynchronous.
///
/// Aligned with Ruby ui2/screen_buffer.rb.

///|
/// ScreenBuffer wraps a Tty handle and tracks terminal dimensions.
/// It provides cursor control, line clearing, color, scroll region
/// management, and synchronized update framing.
struct ScreenBuffer {
  /// Underlying terminal handle.
  tty : @tty.Tty
}

///|
/// Create a ScreenBuffer from a Tty handle.
fn ScreenBuffer::new(tty : @tty.Tty) -> ScreenBuffer {
  { tty, }
}

///|
/// Re-query terminal dimensions.
///
/// Called on SIGWINCH (resize) events. Returns the new (width, height).
fn ScreenBuffer::update_dimensions(self : ScreenBuffer) -> (Int, Int) {
  query_size_safe(self.tty)
}

///|
/// Query terminal size, falling back to 80×24 on error.
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

// ── Cursor Control ───────────────────────────────────────────────────

///|
/// Move cursor to absolute 1-based position (row, col).
async fn ScreenBuffer::move_cursor(
  self : ScreenBuffer,
  row : Int,
  col : Int,
) -> Unit {
  self.tty.set_cursor_position(row, col)
}

///|
/// Show the terminal cursor.
async fn ScreenBuffer::show_cursor(self : ScreenBuffer) -> Unit {
  self.tty.show_cursor()
}

///|
/// Erase from cursor to end of line (EL 0).
async fn ScreenBuffer::clear_to_eol(self : ScreenBuffer) -> Unit {
  self.tty.write_string("\u{1b}[K")
}

///|
/// Erase the entire visible display (ED 2).
async fn ScreenBuffer::clear_display(self : ScreenBuffer) -> Unit {
  self.tty.erase_display()
}

// ── Write ─────────────────────────────────────────────────────────────

///|
/// Write a string at the current cursor position.
async fn ScreenBuffer::write_string(self : ScreenBuffer, text : String) -> Unit {
  self.tty.write_string(text)
}

// ── Color & Style ────────────────────────────────────────────────────

///|
/// Set the foreground color.
async fn ScreenBuffer::set_foreground(
  self : ScreenBuffer,
  color : @color.Color,
) -> Unit {
  self.tty.set_foreground(color)
}

///|
/// Set bold style.
async fn ScreenBuffer::bold(self : ScreenBuffer) -> Unit {
  self.tty.bold()
}

///|
/// Reset all SGR style attributes.
async fn ScreenBuffer::reset_style(self : ScreenBuffer) -> Unit {
  self.tty.reset_style()
}

// ── Raw Mode ─────────────────────────────────────────────────────────
//
// Raw mode management is handled at the controller level (Phase 5)
// using `tty.with_raw_mode()` — an RAII-style async wrapper that
// ensures terminal state is restored even on error.
