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
  /// Current terminal width (columns).
  mut width : Int
  /// Current terminal height (rows).
  mut height : Int
}

///|
/// Create a ScreenBuffer from a Tty handle.
///
/// Queries the initial terminal size, falling back to 80×24 on error.
fn ScreenBuffer::new(tty : @tty.Tty) -> ScreenBuffer {
  let (w, h) = query_size_safe(tty)
  { tty, width: w, height: h }
}

///|
/// Re-query terminal dimensions and update stored values.
///
/// Called on SIGWINCH (resize) events. Returns the new (width, height).
fn ScreenBuffer::update_dimensions(self : ScreenBuffer) -> (Int, Int) {
  let (w, h) = query_size_safe(self.tty)
  self.width = w
  self.height = h
  (w, h)
}

///|
/// Query terminal size, falling back to 80×24 on error.
fn query_size_safe(tty : @tty.Tty) -> (Int, Int) {
  try tty.window_size() catch {
    _ => (80, 24)
  } noraise {
    size =>
      (
        if size.cols < 1 { 80 } else { size.cols },
        if size.rows < 1 { 24 } else { size.rows },
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
/// Move cursor up by n rows.
async fn ScreenBuffer::cursor_up(self : ScreenBuffer, n : Int) -> Unit {
  self.tty.cursor_up(n)
}

///|
/// Move cursor forward (right) by n columns.
async fn ScreenBuffer::cursor_forward(self : ScreenBuffer, n : Int) -> Unit {
  self.tty.cursor_forward(n)
}

///|
/// Move cursor back (left) by n columns.
async fn ScreenBuffer::cursor_back(self : ScreenBuffer, n : Int) -> Unit {
  self.tty.cursor_back(n)
}

///|
/// Move cursor to the start of the current line (column 1).
async fn ScreenBuffer::cursor_to_line_start(self : ScreenBuffer) -> Unit {
  self.tty.write_string("\r")
}

///|
/// Save cursor position (DECSC — ESC 7).
async fn ScreenBuffer::save_cursor(self : ScreenBuffer) -> Unit {
  self.tty.write_string("\x1b7")
}

///|
/// Restore cursor position (DECRC — ESC 8).
async fn ScreenBuffer::restore_cursor(self : ScreenBuffer) -> Unit {
  self.tty.write_string("\x1b8")
}

///|
/// Hide the terminal cursor.
async fn ScreenBuffer::hide_cursor(self : ScreenBuffer) -> Unit {
  self.tty.hide_cursor()
}

///|
/// Show the terminal cursor.
async fn ScreenBuffer::show_cursor(self : ScreenBuffer) -> Unit {
  self.tty.show_cursor()
}

// ── Erase ────────────────────────────────────────────────────────────

///|
/// Erase the entire current line (EL 2).
async fn ScreenBuffer::clear_line(self : ScreenBuffer) -> Unit {
  self.tty.erase_line_all()
}

///|
/// Erase from cursor to end of line (EL 0).
async fn ScreenBuffer::clear_to_eol(self : ScreenBuffer) -> Unit {
  self.tty.write_string("\x1b[K")
}

///|
/// Erase the entire visible display (ED 2).
async fn ScreenBuffer::clear_display(self : ScreenBuffer) -> Unit {
  self.tty.erase_display()
}

///|
/// Erase saved lines in the terminal scrollback (ED 3).
async fn ScreenBuffer::clear_scrollback(self : ScreenBuffer) -> Unit {
  self.tty.erase_scrollback()
}

// ── Write ─────────────────────────────────────────────────────────────

///|
/// Write a string at the current cursor position.
async fn ScreenBuffer::write_string(
  self : ScreenBuffer,
  text : String,
) -> Unit {
  self.tty.write_string(text)
}

///|
/// Write a string at the current position, then move to next line.
///
/// Uses \r\n for maximum terminal compatibility (some terminals
/// treat bare \n as line feed without carriage return).
async fn ScreenBuffer::write_line(
  self : ScreenBuffer,
  text : String,
) -> Unit {
  self.tty.write_string(text + "\r\n")
}

///|
/// Move to absolute position and write a string.
async fn ScreenBuffer::write_at(
  self : ScreenBuffer,
  row : Int,
  col : Int,
  text : String,
) -> Unit {
  self.tty.set_cursor_position(row, col)
  self.tty.write_string(text)
}

///|
/// Move to absolute position, write a string, then clear to end of line.
///
/// Useful for rendering fixed-width lines where trailing content
/// must be erased.
async fn ScreenBuffer::write_at_clear(
  self : ScreenBuffer,
  row : Int,
  col : Int,
  text : String,
) -> Unit {
  self.tty.set_cursor_position(row, col)
  self.tty.write_string(text)
  self.tty.write_string("\x1b[K")
}

// ── Scroll Region ────────────────────────────────────────────────────

///|
/// Set the scroll region (DECSTBM) to rows [top, bottom] (1-based).
///
/// After setting, cursor movement and line feeds within this region
/// will scroll content within the region, leaving lines outside
/// (status bar, input area) untouched.
async fn ScreenBuffer::set_scroll_region(
  self : ScreenBuffer,
  top : Int,
  bottom : Int,
) -> Unit {
  self.tty.set_top_bottom_margins(top, bottom)
}

///|
/// Reset the scroll region to the full screen.
async fn ScreenBuffer::reset_scroll_region(self : ScreenBuffer) -> Unit {
  self.tty.reset_top_bottom_margins()
}

///|
/// Scroll content up by one line within the scroll region (RI).
///
/// Moves the cursor to the top of the scroll region and performs a
/// reverse index, causing all lines within the region to move down
/// by one. The top line of the region scrolls into the terminal's
/// scrollback buffer. A blank line appears at the top.
///
/// This is the inverse of a line feed at the bottom of the region.
async fn ScreenBuffer::scroll_down_in_region(
  self : ScreenBuffer,
  region_top : Int,
) -> Unit {
  self.tty.set_cursor_position(region_top, 1)
  self.tty.reverse_index()
}

///|
/// Scroll content up by one line within the scroll region (LF at bottom).
///
/// Moves the cursor to the bottom of the scroll region and performs a
/// line feed, causing all lines to move up by one. The bottom line
/// scrolls into the terminal's scrollback. A blank line appears at
/// the bottom.
async fn ScreenBuffer::scroll_up_in_region(
  self : ScreenBuffer,
  region_bottom : Int,
) -> Unit {
  self.tty.set_cursor_position(region_bottom, 1)
  self.tty.write_string("\r\n")
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
/// Set the background color.
async fn ScreenBuffer::set_background(
  self : ScreenBuffer,
  color : @color.Color,
) -> Unit {
  self.tty.set_background(color)
}

///|
/// Reset foreground color to terminal default.
async fn ScreenBuffer::reset_foreground(self : ScreenBuffer) -> Unit {
  self.tty.reset_foreground()
}

///|
/// Reset background color to terminal default.
async fn ScreenBuffer::reset_background(self : ScreenBuffer) -> Unit {
  self.tty.reset_background()
}

///|
/// Set bold style.
async fn ScreenBuffer::bold(self : ScreenBuffer) -> Unit {
  self.tty.bold()
}

///|
/// Set italic style.
async fn ScreenBuffer::italic(self : ScreenBuffer) -> Unit {
  self.tty.italic()
}

///|
/// Set underline style.
async fn ScreenBuffer::underline(self : ScreenBuffer) -> Unit {
  self.tty.underline()
}

///|
/// Set reverse video.
async fn ScreenBuffer::reverse(self : ScreenBuffer) -> Unit {
  self.tty.reverse()
}

///|
/// Reset all SGR style attributes.
async fn ScreenBuffer::reset_style(self : ScreenBuffer) -> Unit {
  self.tty.reset_style()
}

// ── Synchronized Update ───────────────────────────────────────────────

///|
/// Begin a synchronized update frame (DEC mode 2026).
///
/// All output written between `begin_frame` and `end_frame` is
/// buffered by the terminal and presented atomically, preventing
/// visible flicker from multi-step repaints.
async fn ScreenBuffer::begin_frame(self : ScreenBuffer) -> Unit {
  self.tty.begin_synchronized_update()
}

///|
/// End a synchronized update frame and present atomically.
async fn ScreenBuffer::end_frame(self : ScreenBuffer) -> Unit {
  self.tty.end_synchronized_update()
}

// ── Raw Mode ─────────────────────────────────────────────────────────
//
// Raw mode management is handled at the controller level (Phase 5)
// using `tty.with_raw_mode()` — an RAII-style async wrapper that
// ensures terminal state is restored even on error.
