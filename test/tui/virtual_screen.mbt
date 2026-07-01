///|
/// VirtualScreen: in-memory character grid for headless TUI rendering tests.
///
/// Provides synchronous rendering primitives that mirror ScreenBuffer's
/// behavior but operate on a 2D character array instead of a real terminal.
/// This enables TUI eval without async/TTY dependencies.
///
/// Design rationale (from adversarial review):
/// - ScreenBuffer methods are all `async fn` because they call `tty.write_string`
/// - MoonBit `await` only works in `async fn` context
/// - VirtualScreen provides pure sync equivalents for test use
/// - Platform-independent: works on Windows without PTY

///|
/// A virtual terminal screen backed by a character grid.
/// All operations are synchronous and in-memory.
pub(all) struct VirtualScreen {
  /// Terminal width (columns).
  width : Int
  /// Terminal height (rows).
  height : Int
  /// Cursor row (1-based, matches terminal convention).
  mut cursor_row : Int
  /// Cursor col (1-based, matches terminal convention).
  mut cursor_col : Int
  /// The character grid: rows indexed [0..height), cols [0..width).
  grid : Array[Array[Char]]
}

///|
/// Create a new VirtualScreen with given dimensions.
pub fn VirtualScreen::new(width : Int, height : Int) -> VirtualScreen {
  let grid : Array[Array[Char]] = []
  let mut r = 0
  while r < height {
    let row : Array[Char] = []
    let mut c = 0
    while c < width {
      row.push(' ')
      c = c + 1
    }
    grid.push(row)
    r = r + 1
  }
  { width, height, cursor_row: 1, cursor_col: 1, grid }
}

///|
/// Move cursor to 1-based (row, col). Out-of-bounds positions are clamped.
pub fn VirtualScreen::move_cursor(
  self : VirtualScreen,
  row : Int,
  col : Int,
) -> Unit {
  self.cursor_row = if row < 1 {
    1
  } else if row > self.height {
    self.height
  } else {
    row
  }
  self.cursor_col = if col < 1 {
    1
  } else if col > self.width {
    self.width
  } else {
    col
  }
}

///|
/// Write text at the current cursor position.
/// Characters are placed sequentially across the row.
/// If text extends past the right edge, it is truncated.
pub fn VirtualScreen::write_string(self : VirtualScreen, text : String) -> Unit {
  let row = self.cursor_row - 1
  if row < 0 || row >= self.height {
    return
  }
  let mut col = self.cursor_col - 1
  for ch in text.iter() {
    if col >= self.width {
      break
    }
    if col >= 0 {
      self.grid[row][col] = ch
    }
    col = col + 1
  }
  self.cursor_col = col + 1
}

///|
/// Clear from cursor to end of current line.
pub fn VirtualScreen::clear_to_eol(self : VirtualScreen) -> Unit {
  let row = self.cursor_row - 1
  if row < 0 || row >= self.height {
    return
  }
  let mut col = self.cursor_col - 1
  if col < 0 {
    col = 0
  }
  while col < self.width {
    self.grid[row][col] = ' '
    col = col + 1
  }
}

///|
/// Clear the entire line at the cursor row.
pub fn VirtualScreen::clear_line(self : VirtualScreen) -> Unit {
  let row = self.cursor_row - 1
  if row < 0 || row >= self.height {
    return
  }
  for col = 0; col < self.width; col = col + 1 {
    self.grid[row][col] = ' '
  }
}

///|
/// Clear the entire screen (all cells to space).
pub fn VirtualScreen::clear_display(self : VirtualScreen) -> Unit {
  for row = 0; row < self.height; row = row + 1 {
    for col = 0; col < self.width; col = col + 1 {
      self.grid[row][col] = ' '
    }
  }
}

///|
/// Get a specific row's content as a String.
/// The result is NOT trimmed (full width including trailing spaces).
pub fn VirtualScreen::get_row(self : VirtualScreen, row : Int) -> String {
  let r = row - 1
  if r < 0 || r >= self.height {
    return ""
  }
  let chars : Array[Char] = []
  for col = 0; col < self.width; col = col + 1 {
    chars.push(self.grid[r][col])
  }
  chars.map(fn(c) { c.to_string() }).join("")
}

///|
/// Get a specific row's content as a trimmed String (no trailing spaces).
pub fn VirtualScreen::get_row_trimmed(
  self : VirtualScreen,
  row : Int,
) -> String {
  self.get_row(row).trim_end().to_owned()
}

///|
/// Get the full screen content as a multi-line string.
/// Each row is included, separated by newlines.
pub fn VirtualScreen::content(self : VirtualScreen) -> String {
  let lines : Array[String] = []
  for row = 0; row < self.height; row = row + 1 {
    let line = self.get_row(row + 1).trim_end().to_owned()
    lines.push(line)
  }
  lines.join("\n")
}

///|
/// Get screen content with trailing empty lines removed.
pub fn VirtualScreen::content_trimmed(self : VirtualScreen) -> String {
  let lines : Array[String] = []
  for row = 0; row < self.height; row = row + 1 {
    let line = self.get_row(row + 1).trim_end().to_owned()
    lines.push(line)
  }
  // Remove trailing empty lines
  let mut end = lines.length()
  while end > 0 && lines[end - 1].length() == 0 {
    end = end - 1
  }
  if end <= 0 {
    return ""
  }
  lines[0:end].join("\n")
}

///|
/// Check if a specific row contains the given substring.
pub fn VirtualScreen::row_contains(
  self : VirtualScreen,
  row : Int,
  text : String,
) -> Bool {
  self.get_row(row).contains(text)
}

///|
/// Check if ANY row in the screen contains the given substring.
pub fn VirtualScreen::contains(self : VirtualScreen, text : String) -> Bool {
  for row = 0; row < self.height; row = row + 1 {
    if self.row_contains(row + 1, text) {
      return true
    }
  }
  false
}

///|
/// Find the first row containing the given text.
/// Returns the 1-based row number, or 0 if not found.
pub fn VirtualScreen::find_row(self : VirtualScreen, text : String) -> Int {
  for row = 0; row < self.height; row = row + 1 {
    if self.row_contains(row + 1, text) {
      return row + 1
    }
  }
  0
}

///|
/// Get a region of the screen as a string.
/// Row and col are 1-based and inclusive.
pub fn VirtualScreen::get_region(
  self : VirtualScreen,
  top_row : Int,
  left_col : Int,
  bottom_row : Int,
  right_col : Int,
) -> String {
  let lines : Array[String] = []
  for r = top_row; r <= bottom_row; r = r + 1 {
    let row_idx = r - 1
    if row_idx < 0 || row_idx >= self.height {
      continue
    }
    let chars : Array[String] = []
    for c = left_col; c <= right_col; c = c + 1 {
      let col_idx = c - 1
      if col_idx >= 0 && col_idx < self.width {
        chars.push(self.grid[row_idx][col_idx].to_string())
      }
    }
    lines.push(chars.join("").trim_end().to_owned())
  }
  lines.join("\n")
}

// ── Rendering helpers ─────────────────────────────────────────────────

///|
/// Render a status bar text at the top row (row 1).
/// This mirrors TuiController::redraw_status in sync mode.
pub fn VirtualScreen::render_status_text(
  self : VirtualScreen,
  text : String,
) -> Unit {
  self.move_cursor(1, 1)
  self.clear_to_eol()
  self.write_string(text)
}

///|
/// Render an input area with border at the bottom of the screen.
/// This mirrors TuiController::redraw_input in sync mode.
///
/// Layout (4 lines from bottom):
///   ┌─ Input ──────────┐
///   │ content line 1
///   │ content line 2
///   └──────────────────┘
pub fn VirtualScreen::render_input_area(
  self : VirtualScreen,
  input_lines : Array[String],
) -> Unit {
  let input_h = 4
  let top = self.height - input_h
  let w = self.width
  let mut i = 0
  while i < input_h {
    self.move_cursor(top + i + 1, 1)
    self.clear_to_eol()
    if i == 0 {
      // Top border: ┌─ Input ────┐
      self.write_string("┌─ Input ")
      let border_w = w - 10
      if border_w > 0 {
        let dashes : Array[String] = []
        let mut d = 0
        while d < border_w {
          dashes.push("─")
          d = d + 1
        }
        self.write_string(dashes.join(""))
      }
    } else if i == input_h - 1 {
      // Bottom border: └──────┘
      self.write_string("└")
      let border_w = w - 2
      if border_w > 0 {
        let dashes : Array[String] = []
        let mut d = 0
        while d < border_w {
          dashes.push("─")
          d = d + 1
        }
        self.write_string(dashes.join(""))
      }
      self.write_string("┘")
    } else if i - 1 < input_lines.length() {
      // Content line: │ text
      self.write_string("│ ")
      self.write_string(input_lines[i - 1])
    } else {
      // Empty line: │
      self.write_string("│")
    }
    i = i + 1
  }
}

///|
/// Render output lines in the message area (between status bar and input area).
/// This mirrors LayoutManager::render_output_area in sync mode.
pub fn VirtualScreen::render_output_lines(
  self : VirtualScreen,
  lines : Array[String],
  top_row : Int,
  max_rows : Int,
) -> Unit {
  let count = if lines.length() > max_rows { max_rows } else { lines.length() }
  for i = 0; i < count; i = i + 1 {
    self.move_cursor(top_row + i, 1)
    self.clear_to_eol()
    self.write_string(lines[i])
  }
  // Clear remaining lines in message area
  for i = count; i < max_rows; i = i + 1 {
    self.move_cursor(top_row + i, 1)
    self.clear_to_eol()
  }
}
