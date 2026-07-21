///|
/// Layout manager: coordinates screen regions and rendering.
///
/// Divides the terminal into three fixed regions:
///
/// ```text
/// ┌──────────────────────────────┐
/// │ Status Bar       (top, fixed) │  rows [0, status_h)
/// ├──────────────────────────────┤
/// │ Message Area   (middle, scroll) │  rows [msg_top, msg_bottom]
/// ├──────────────────────────────┤
/// │ Input Area      (bottom, fixed) │ rows [input_top, height)
/// └──────────────────────────────┘
/// ```
///
/// **Commit invariant**: committed output lines are never re-rendered.
/// Only live (uncommitted) entries are redrawn on each frame.
pub(all) struct LayoutManager {
  screen : ScreenBuffer
  output : OutputBuffer
  status_h : Int
  input_h : Int
  mut width : Int
  mut height : Int
  mut msg_top : Int
  mut msg_bottom : Int
  mut msg_height : Int
}

///|
pub fn LayoutManager::new(
  screen : ScreenBuffer,
  output : OutputBuffer,
  status_h? : Int = 1,
  input_h? : Int = 3,
) -> LayoutManager {
  let m = {
    screen,
    output,
    status_h,
    input_h,
    width: 80,
    height: 24,
    msg_top: 1,
    msg_bottom: 20,
    msg_height: 20,
  }
  m.compute_layout()
  m
}

///|
pub fn LayoutManager::compute_layout(self : LayoutManager) -> Unit {
  let (w, h) = self.screen.update_dimensions()
  self.width = w
  self.height = h
  self.msg_top = self.status_h
  self.msg_bottom = h - self.input_h - 1
  self.msg_height = self.msg_bottom - self.msg_top + 1
  if self.msg_height < 1 {
    self.msg_height = 1
  }
}

// ── Rendering ────────────────────────────────────────────────────

///|
/// Full screen redraw: status bar, output area, input area.
pub async fn LayoutManager::full_redraw(
  self : LayoutManager,
  status_text : String,
  input_lines : Array[String],
) -> Unit {
  self.compute_layout()
  self.screen.clear_display()
  self.render_status_bar(status_text)
  self.render_output_area()
  self.render_input_area(input_lines)
}

///|
/// Redraw only live (uncommitted) output entries.
///
/// Scrolling policy (conservative "page repaint" approach):
/// - When the total output no longer fits in the message area, the oldest
///   overflow lines are committed via `commit_oldest_lines` and the whole
///   message area is repainted with `render_output_area` (visually
///   equivalent to scrolling, at the cost of redrawing committed lines).
/// - The newest live entry is never partially committed by this path, so an
///   in-progress streaming entry stays `replace`-able.
/// - When live lines still exceed the remaining space (e.g. a single entry
///   taller than the screen), the NEWEST lines are kept and the oldest live
///   lines are dropped, so streaming output always shows its latest tail.
pub async fn LayoutManager::redraw_live(self : LayoutManager) -> Unit {
  let live_entries = self.output.live_entries()
  if live_entries.is_empty() {
    return
  }
  // Overflow: total output taller than the message area. Commit the oldest
  // overflow lines (never touching the newest live entry) and repaint the
  // whole message area — this is the "scroll" path.
  let total = self.output.total_lines()
  if total > self.msg_height {
    let newest_lines = live_entries[live_entries.length() - 1].line_count()
    let committable = total - newest_lines
    let to_commit = if total - self.msg_height < committable {
      total - self.msg_height
    } else {
      committable
    }
    if to_commit > 0 {
      ignore(self.output.commit_oldest_lines(to_commit))
    }
    self.render_output_area()
    return
  }
  let committed_lines = self.output.total_lines() -
    self.output.total_live_lines()
  let available = self.msg_height - committed_lines
  if available <= 0 {
    return
  }
  let start_row = self.msg_top + committed_lines
  let live_lines : Array[String] = []
  for entry in live_entries {
    for line in entry.lines {
      live_lines.push(line)
    }
  }
  // Keep the NEWEST lines when the live region overflows: the latest
  // streaming content must always be visible.
  let skip = if live_lines.length() > available {
    live_lines.length() - available
  } else {
    0
  }
  // Clear the area we'll write into
  for row = start_row; row <= self.msg_bottom; row = row + 1 {
    self.screen.move_cursor(row + 1, 1)
    self.screen.clear_to_eol()
  }
  // Write live lines (newest `available` of them)
  let mut i = skip
  while i < live_lines.length() {
    self.screen.move_cursor(start_row + (i - skip) + 1, 1)
    self.screen.write_string(live_lines[i])
    i = i + 1
  }
}

// ── Internal renderers ───────────────────────────────────────────

///|
async fn LayoutManager::render_status_bar(
  self : LayoutManager,
  text : String,
) -> Unit {
  self.screen.move_cursor(1, 1)
  self.screen.clear_to_eol()
  self.screen.bold()
  self.screen.write_string(text)
  self.screen.reset_style()
}

///|
async fn LayoutManager::render_output_area(self : LayoutManager) -> Unit {
  let tail = self.output.tail_lines(self.msg_height)
  let start_row = self.msg_top
  for i = 0; i < tail.length(); i = i + 1 {
    self.screen.move_cursor(start_row + i + 1, 1)
    self.screen.clear_to_eol()
    self.screen.write_string(tail[i])
  }
  // Clear remaining lines in the message area
  for i = tail.length(); i < self.msg_height; i = i + 1 {
    self.screen.move_cursor(start_row + i + 1, 1)
    self.screen.clear_to_eol()
  }
}

///|
async fn LayoutManager::render_input_area(
  self : LayoutManager,
  lines : Array[String],
) -> Unit {
  let input_top = self.height - self.input_h
  for i = 0; i < self.input_h; i = i + 1 {
    self.screen.move_cursor(input_top + i + 1, 1)
    self.screen.clear_to_eol()
    if i == 0 {
      // Top border: ┌─ Input ────┐
      self.screen.set_foreground(@color.Color::Basic(@color.BasicColor::Blue))
      self.screen.write_string("┌─ Input ")
      let border_w = self.width - 10
      for j = 0; j < border_w; j = j + 1 {
        self.screen.write_string("─")
      }
      self.screen.reset_style()
    } else if i == self.input_h - 1 {
      // Bottom border: └──────┘
      self.screen.set_foreground(@color.Color::Basic(@color.BasicColor::Blue))
      self.screen.write_string("└")
      let border_w = self.width - 2
      for j = 0; j < border_w; j = j + 1 {
        self.screen.write_string("─")
      }
      self.screen.write_string("┘")
      self.screen.reset_style()
    } else if i - 1 < lines.length() {
      // Content line: │ text
      self.screen.set_foreground(@color.Color::Basic(@color.BasicColor::Blue))
      self.screen.write_string("│ ")
      self.screen.reset_style()
      self.screen.write_string(lines[i - 1])
    } else {
      // Empty line: │
      self.screen.set_foreground(@color.Color::Basic(@color.BasicColor::Blue))
      self.screen.write_string("│")
      self.screen.reset_style()
    }
  }
}

// ── Commit & queries ─────────────────────────────────────────────

///|
pub fn LayoutManager::commit_all(self : LayoutManager) -> Unit {
  match self.output.last_entry_id() {
    Some(id) => self.output.commit_through(id)
    None => ()
  }
}

///|
pub fn LayoutManager::message_area(self : LayoutManager) -> (Int, Int, Int) {
  (self.msg_top, self.msg_bottom, self.msg_height)
}

///|
pub fn LayoutManager::screen_size(self : LayoutManager) -> (Int, Int) {
  (self.width, self.height)
}
