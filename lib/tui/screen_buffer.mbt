///|
/// Screen buffer for low-level terminal rendering.
///
/// Manages a 2D grid of cells with foreground/background colors and
/// tracks dirty regions for efficient partial screen updates.

///|
/// A single cell on the screen buffer.
pub(all) struct ScreenCell {
  /// Character displayed in this cell.
  ch : Char
  /// Foreground color name (e.g., "white", "red", "green").
  fg : String
  /// Background color name.
  bg : String
  /// Whether the cell is rendered bold.
  bold : Bool
} derive(Eq, Debug)

///|
/// Create a default empty cell (space, white on black).
pub fn ScreenCell::default_() -> ScreenCell {
  { ch: ' ', fg: "white", bg: "black", bold: false }
}

///|
/// Screen buffer managing a 2D grid of cells and dirty regions.
pub(all) struct ScreenBuffer {
  /// Buffer width in columns.
  width : Int
  /// Buffer height in rows.
  height : Int
  /// 2D grid of cells: cells[row][col].
  mut cells : Array[Array[ScreenCell]]
  /// Dirty regions as (x, y, width, height) tuples.
  mut dirty_regions : Array[(Int, Int, Int, Int)]
} derive(Debug)

///|
/// Create a new ScreenBuffer with the given dimensions.
pub fn ScreenBuffer::new(width : Int, height : Int) -> ScreenBuffer {
  let cells = create_cell_grid(width, height)
  { width, height, cells, dirty_regions: [] }
}

///|
/// Put a character at the given position with optional styling.
pub fn ScreenBuffer::put_char(
  self : ScreenBuffer,
  x : Int,
  y : Int,
  ch : Char,
  fg? : String = "white",
  bg? : String = "black",
  bold? : Bool = false,
) -> Unit {
  if x < 0 || x >= self.width || y < 0 || y >= self.height {
    return
  }
  self.cells[y][x] = { ch, fg, bg, bold }
  self.mark_dirty(x, y, 1, 1)
}

///|
/// Put a string starting at the given position with optional styling.
pub fn ScreenBuffer::put_string(
  self : ScreenBuffer,
  x : Int,
  y : Int,
  s : String,
  fg? : String = "white",
  bg? : String = "black",
  bold? : Bool = false,
) -> Unit {
  if y < 0 || y >= self.height {
    return
  }
  let chars = s.to_array()
  let mut col = x
  for i = 0; i < chars.length(); i = i + 1 {
    if col >= self.width {
      break
    }
    if col >= 0 {
      self.cells[y][col] = { ch: chars[i], fg, bg, bold }
    }
    col = col + 1
  }
  self.mark_dirty(x, y, chars.length(), 1)
}

///|
/// Clear a rectangular region to default cells.
pub fn ScreenBuffer::clear_region(
  self : ScreenBuffer,
  x : Int,
  y : Int,
  w : Int,
  h : Int,
) -> Unit {
  for row = y; row < y + h; row = row + 1 {
    if row < 0 || row >= self.height {
      continue
    }
    for col = x; col < x + w; col = col + 1 {
      if col >= 0 && col < self.width {
        self.cells[row][col] = ScreenCell::default_()
      }
    }
  }
  self.mark_dirty(x, y, w, h)
}

///|
/// Clear the entire screen buffer.
pub fn ScreenBuffer::clear_all(self : ScreenBuffer) -> Unit {
  self.clear_region(0, 0, self.width, self.height)
}

///|
/// Mark a rectangular region as dirty for re-rendering.
pub fn ScreenBuffer::mark_dirty(
  self : ScreenBuffer,
  x : Int,
  y : Int,
  w : Int,
  h : Int,
) -> Unit {
  self.dirty_regions.push((x, y, w, h))
}

///|
/// Get all dirty regions.
pub fn ScreenBuffer::get_dirty_regions(
  self : ScreenBuffer,
) -> Array[(Int, Int, Int, Int)] {
  self.dirty_regions
}

///|
/// Clear the dirty region tracking list.
pub fn ScreenBuffer::clear_dirty(self : ScreenBuffer) -> Unit {
  self.dirty_regions.clear()
}

///|
/// Get the cell at the given position, or None if out of bounds.
pub fn ScreenBuffer::get_cell(
  self : ScreenBuffer,
  x : Int,
  y : Int,
) -> ScreenCell? {
  if x < 0 || x >= self.width || y < 0 || y >= self.height {
    return None
  }
  Some(self.cells[y][x])
}

///|
/// Resize the screen buffer to new dimensions.
///
/// Existing content is preserved where possible; new cells are default.
pub fn ScreenBuffer::resize(
  self : ScreenBuffer,
  width : Int,
  height : Int,
) -> Unit {
  let new_cells = create_cell_grid(width, height)
  // Copy existing content where it fits
  let copy_rows = if self.height < height { self.height } else { height }
  let copy_cols = if self.width < width { self.width } else { width }
  for row = 0; row < copy_rows; row = row + 1 {
    for col = 0; col < copy_cols; col = col + 1 {
      new_cells[row][col] = self.cells[row][col]
    }
  }
  self.cells = new_cells
  self.mark_dirty(0, 0, width, height)
}

// ── Internal helpers ────────────────────────────────────────────────

///|
/// Create a 2D grid of default cells.
fn create_cell_grid(width : Int, height : Int) -> Array[Array[ScreenCell]] {
  let rows : Array[Array[ScreenCell]] = []
  for i = 0; i < height; i = i + 1 {
    let row : Array[ScreenCell] = []
    for j = 0; j < width; j = j + 1 {
      row.push(ScreenCell::default_())
    }
    rows.push(row)
  }
  rows
}
