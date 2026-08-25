///|
/// Incremental line-level frame rendering for TuiController.
///
/// Aligned with Ruby ui2/layout_manager.rb paint_new_lines model:
/// - Only new/changed rows are painted (never a full-screen repaint).
/// - Overflow scrolls one row at a time via real \n at the bottom row,
///   committing the oldest display line from the OutputBuffer.
/// - Committed rows are NEVER repainted (they live in terminal scrollback).
/// - The fixed area (status bar, separator, input, etc.) is repainted
///   in full on every frame (it sits at the bottom, always dirty).
///
/// This eliminates the "reply flashes then disappears" bug: in the old
/// full-redraw model, `commit_output()` after AgentDone marked entries
/// committed, then the next redraw painted an empty body — wiping the
/// reply from the screen. In the incremental model, entries stay live
/// while they're on screen and commit only when they physically scroll
/// into the terminal's native scrollback.

///|
/// Query terminal size, falling back to 80x24 on error.
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

///|
/// Full rebuild: clear the screen, reset painting state, and paint
/// everything from scratch.
///
/// Used on: initial draw, resize, Ctrl+L, /clear, theme switch.
///
/// On the first call (screen_inited == false), uses the incremental
/// scroll path so rows that overflow the output area physically enter
/// the terminal's native scrollback (e.g. the startup banner on a
/// small terminal). On subsequent calls (rebuild after resize/Ctrl+L),
/// commits excess live rows directly without physical scroll (the screen
/// was just cleared; the content is already gone from display).
async fn TuiController::full_redraw_screen(self : TuiController) -> Unit {
  let (tw, th) = query_size_safe(self.tty)
  self.term_width = tw
  self.term_height = th
  self.output.width = tw

  if !self.screen_inited {
    // First paint: hide cursor, clear screen, home.
    self.tty.write_string("\u{1b}[?25l\u{1b}[2J\u{1b}[1;1H")
    self.painted_body = []
    self.last_fixed_height = 0
    self.screen_inited = true
    // Incremental scroll path: overflow rows physically enter scrollback.
    self.frame_incremental()
    return
  }

  // Rebuild path (resize / Ctrl+L / /clear / theme):
  // Clear screen and commit excess live rows without physical scroll.
  self.tty.write_string("\u{1b}[2J\u{1b}[1;1H")
  self.painted_body = []
  self.last_fixed_height = 0

  // If the body overflows the output area, commit the excess head rows.
  // They were visible before the clear; the terminal itself may have
  // pushed them into scrollback during a resize shrink.
  let status_text = self.format_status_text()
  let fixed_lines = self.build_fixed_area_lines(status_text)
  let fixed_h = clamp_fixed_height(fixed_lines.length(), self.term_height)
  let max_row = self.term_height - fixed_h
  if max_row > 0 {
    let body = self.build_body_lines()
    let mut overflow = body.length() - max_row
    let mut attempts = 0
    while overflow > 0 && attempts < 10 {
      let committed = self.output.commit_oldest_display_lines(overflow)
      if committed <= 0 {
        break
      }
      attempts = attempts + 1
      // Rebuild to get the updated live line count.
      let updated = self.build_body_lines()
      overflow = updated.length() - max_row
    }
  }

  // Now paint incrementally from an empty screen.
  self.frame_incremental()
}

///|
/// Incremental frame: compute the body diff, paint only changed rows,
/// repaint the fixed area, and position the cursor.
///
/// Called on every dirty tick (200ms), every key press that modifies
/// state, and as the tail of full_redraw_screen.
async fn TuiController::frame_incremental(self : TuiController) -> Unit {
  // Format status text (adaptive to terminal width)
  let status_text = self.format_status_text()
  let fixed_lines = self.build_fixed_area_lines(status_text)
  let fixed_h = clamp_fixed_height(fixed_lines.length(), self.term_height)

  // Fixed-area height change handling.
  if self.last_fixed_height > 0 {
    if fixed_h > self.last_fixed_height {
      // Grew: scroll covered output rows into scrollback.
      let delta = fixed_h - self.last_fixed_height
      let n = self.scroll_phys(delta)
      drop_head_mut(self.painted_body, n)
    } else if fixed_h < self.last_fixed_height {
      // Shrank: clear rows freed between the old and new fixed tops.
      // These rows had old fixed-area content and are now part of the
      // output area — clear them before the body diff overwrites them.
      let old_top = self.term_height - self.last_fixed_height
      let new_top = self.term_height - fixed_h
      self.clear_rows_range(old_top, new_top)
    }
  }
  self.last_fixed_height = fixed_h

  // Body diff + paint.
  let max_row = self.term_height - fixed_h
  let new_body = self.build_body_lines()
  self.paint_body_diff(new_body, max_row)

  // Fixed area at the bottom.
  self.paint_fixed_area(fixed_lines)

  // Cursor in the input area.
  self.place_cursor()
}

///|
/// Format status text, caching via the status bar.
fn TuiController::format_status_text(self : TuiController) -> String {
  self.status_bar.format_from_state_adaptive(self.state.val, self.term_width)
  self.status_bar.colored_text()
}

///|
/// Clamp the fixed-area height so it never exceeds the terminal height
/// (tiny terminal edge case).
fn clamp_fixed_height(fixed_h : Int, term_height : Int) -> Int {
  if fixed_h > term_height {
    term_height
  } else if fixed_h < 1 {
    1
  } else {
    fixed_h
  }
}

// ── Body diff & incremental paint ─────────────────────────────────────

///|
/// Compute the diff between the currently painted body rows and the
/// new body rows, then paint only the changed rows.
///
/// Invariant: `self.painted_body` always equals the body lines
/// currently physically present on screen (rows 0..len-1).
async fn TuiController::paint_body_diff(
  self : TuiController,
  new_body : Array[String],
  max_row : Int,
) -> Unit {
  if max_row <= 0 {
    return
  }
  let painted = self.painted_body

  // Defensive: existing overflow (e.g. after a vertical shrink that
  // wasn't caught by the fixed-area growth path).
  while painted.length() > max_row {
    let n = self.scroll_phys(1)
    drop_head_mut(painted, n)
  }

  // Find common prefix.
  let mut prefix = 0
  let min_n = if painted.length() < new_body.length() {
    painted.length()
  } else {
    new_body.length()
  }
  while prefix < min_n {
    if painted[prefix] != new_body[prefix] {
      break
    }
    prefix = prefix + 1
  }

  // No change.
  if prefix == new_body.length() && prefix == painted.length() {
    return
  }

  // Paint changed rows, scrolling when we reach the bottom of the
  // output area.
  let mut buf = StringBuilder()
  let mut row = prefix
  let mut i = prefix
  while i < new_body.length() {
    if row >= max_row {
      // Flush pending paints before scrolling (the scroll shifts
      // all rows up; pending paints must be at their intended positions).
      self.tty.write_string(buf.to_string())
      buf = StringBuilder()
      let n = self.scroll_phys(1)
      drop_head_mut(painted, n)
      row = row - n
    }
    buf.write_string("\u{1b}[")
    buf.write_string((row + 1).to_string())
    buf.write_string(";1H\u{1b}[2K")
    buf.write_string(truncate_ansi_line(new_body[i], self.term_width))
    buf.write_string("\u{1b}[0m")
    // Update painted tracking.
    if row < painted.length() {
      painted[row] = new_body[i]
    } else {
      painted.push(new_body[i])
    }
    row = row + 1
    i = i + 1
  }

  // Clear leftover old rows (new body was shorter than old painted).
  let mut r = painted.length()
  while r > row {
    r = r - 1
    buf.write_string("\u{1b}[")
    buf.write_string((r + 1).to_string())
    buf.write_string(";1H\u{1b}[2K")
  }
  while painted.length() > row {
    ignore(painted.pop())
  }

  self.tty.write_string(buf.to_string())
  self.painted_body = painted
}

///|
/// Drop the first `n` elements from a mutable array (in-place shift).
fn drop_head_mut(arr : Array[String], n : Int) -> Unit {
  if n <= 0 {
    return
  }
  let len = arr.length()
  if n >= len {
    arr.clear()
    return
  }
  // Shift elements left.
  let mut dst = 0
  let mut src = n
  while src < len {
    arr[dst] = arr[src]
    dst = dst + 1
    src = src + 1
  }
  // Remove trailing duplicates.
  while arr.length() > len - n {
    ignore(arr.pop())
  }
}

// ── Scroll ────────────────────────────────────────────────────────────

///|
/// Scroll the screen by committing `requested` display lines from the
/// OutputBuffer and emitting real newlines at the bottom row.
///
/// Returns the actual number of rows scrolled (may exceed `requested`
/// when a collapsed entry commits its full projection).
///
/// This is the physical equivalent of Ruby's paint_new_lines scroll:
/// move cursor to bottom row, emit \n → the top row enters terminal
/// scrollback. Buffer commit marks those rows as "in scrollback" so
/// they are never repainted.
async fn TuiController::scroll_phys(
  self : TuiController,
  requested : Int,
) -> Int {
  if requested <= 0 {
    return 0
  }
  let committed = self.output.commit_oldest_display_lines(requested)
  let n = if committed > requested { committed } else { requested }
  // Emit n newlines at the bottom row to scroll the screen up.
  let buf = StringBuilder()
  buf.write_string("\u{1b}[")
  buf.write_string(self.term_height.to_string())
  buf.write_string(";1H")
  let mut i = 0
  while i < n {
    buf.write_char('\n')
    i = i + 1
  }
  self.tty.write_string(buf.to_string())
  n
}

// ── Fixed area ────────────────────────────────────────────────────────

///|
/// Paint the fixed area at the bottom of the screen.
///
/// Always repainted in full (it changes on every key press / spinner
/// tick). When the fixed area is taller than the terminal (extreme
/// edge case), only the last `term_height` lines are painted so the
/// input area always stays visible.
async fn TuiController::paint_fixed_area(
  self : TuiController,
  fixed_lines : Array[String],
) -> Unit {
  let n = fixed_lines.length()
  let th = self.term_height
  // Determine the slice of fixed_lines that fits on screen.
  let skip = if n > th { n - th } else { 0 }
  let visible = n - skip
  let start = th - visible
  let buf = StringBuilder()
  let mut i = 0
  while i < visible {
    buf.write_string("\u{1b}[")
    buf.write_string((start + i + 1).to_string())
    buf.write_string(";1H\u{1b}[2K")
    buf.write_string(truncate_ansi_line(fixed_lines[skip + i], self.term_width))
    buf.write_string("\u{1b}[0m")
    i = i + 1
  }
  self.tty.write_string(buf.to_string())
}

///|
/// Clear a range of screen rows [from_row, to_row) (0-based).
async fn TuiController::clear_rows_range(
  self : TuiController,
  from_row : Int,
  to_row : Int,
) -> Unit {
  if from_row >= to_row {
    return
  }
  let buf = StringBuilder()
  let mut r = from_row
  while r < to_row {
    buf.write_string("\u{1b}[")
    buf.write_string((r + 1).to_string())
    buf.write_string(";1H\u{1b}[2K")
    r = r + 1
  }
  self.tty.write_string(buf.to_string())
}

// ── Content builders ──────────────────────────────────────────────────

///|
/// Body (output area) lines in render order: live output lines, the
/// thinking view when active, the active dialog, progress indicators.
fn TuiController::build_body_lines(self : TuiController) -> Array[String] {
  let lines = self.output.live_display_lines()
  if self.state.val.thinking_buffer.get().length() > 0 {
    for
      line in node_to_lines(
        render_thinking_live_view(self.state.val, self.thinking_animator),
      ) {
      lines.push(line)
    }
  }
  match self.get_dialog_node() {
    Some(node) =>
      for line in node_to_lines(node) {
        lines.push(line)
      }
    None => ()
  }
  for line in self.get_progress_lines() {
    lines.push(line)
  }
  lines
}

///|
/// A dim horizontal separator row spanning the terminal width.
fn dim_separator_line(width : Int) -> String {
  "\u{1b}[2m" + "─".repeat(width) + "\u{1b}[0m"
}

///|
/// Fixed bottom area lines in Ruby ui2 order: todo (above the status bar),
/// status bar, separator, attachments, input lines, separator,
/// suggestions, tips. Must stay exactly consistent with
/// `fixed_area_height` — the scroll math depends on it.
fn TuiController::build_fixed_area_lines(
  self : TuiController,
  status_text : String,
) -> Array[String] {
  let w = self.term_width
  let content_width = effective_content_width(w)
  let lines : Array[String] = []
  // Todo area rows (directly above the status bar, Ruby ui2 order)
  if self.state.val.todo_area.visible() {
    for line in self.state.val.todo_area.render_lines() {
      lines.push(line)
    }
  }
  // Status bar
  lines.push(status_text)
  // Separator
  lines.push(dim_separator_line(w))
  // Attachment rows: one dim row per stored paste placeholder
  for pair in self.state.val.paste_placeholders {
    let (num, text) = pair
    let n_lines = paste_line_count(text)
    lines.push("\u{1b}[2m  [#\{num} Paste Text] \{n_lines} lines\u{1b}[0m")
  }
  // Input lines (auto-wrapped, borderless)
  for line in self.input.render_wrapped_lines(content_width) {
    lines.push(line)
  }
  // Separator
  lines.push(dim_separator_line(w))
  // Command suggestions dropdown
  if self.suggestions_active {
    for line in self.suggestions.render() {
      lines.push(line)
    }
  }
  // System tips row
  match self.tips.message {
    Some(msg) => lines.push(format_tips(msg, self.tips.type_, w))
    None => ()
  }
  lines
}

// ── Truncation ────────────────────────────────────────────────────────

///|
/// Truncate a possibly ANSI-styled line to at most `width` display columns
/// (CJK-aware), passing escape sequences through untouched so exactly one
/// terminal row is occupied when the line is printed directly to the tty.
fn truncate_ansi_line(line : String, width : Int) -> String {
  let buf = StringBuilder()
  let mut col = 0
  // Parse state: 0=normal, 1=after_esc, 2=in_csi, 3=in_osc, 4=osc_after_esc
  let mut parse_state = 0
  for c in line.iter() {
    match parse_state {
      0 =>
        if c == '\u{1b}' {
          buf.write_char(c)
          parse_state = 1
        } else {
          let cw = @tui_core.char_display_width(c)
          if col + cw > width {
            break
          }
          buf.write_char(c)
          col = col + cw
        }
      1 => {
        buf.write_char(c)
        if c == '[' {
          parse_state = 2
        } else if c == ']' {
          parse_state = 3
        } else {
          parse_state = 0
        }
      }
      2 => {
        buf.write_char(c)
        if c.to_int() >= 0x40 && c.to_int() <= 0x7E {
          parse_state = 0
        }
      }
      3 => {
        buf.write_char(c)
        if c == '\u{07}' {
          parse_state = 0
        } else if c == '\u{1b}' {
          parse_state = 4
        }
      }
      _ => {
        buf.write_char(c)
        if c == '\u{07}' {
          parse_state = 0
        }
      }
    }
  }
  buf.to_string()
}

// ── Layout helpers ────────────────────────────────────────────────────

///|
/// Number of todo-area rows currently rendered above the status bar
/// (0 when hidden or empty).
fn TuiController::todo_row_count(self : TuiController) -> Int {
  if self.state.val.todo_area.visible() {
    self.state.val.todo_area.render_lines().length()
  } else {
    0
  }
}

///|
/// Height in rows of the bottom fixed area, aligned with Ruby ui2
/// `input_area.required_height` (+ todo rows above the status bar):
///   todo (0-N) + status bar (1) + separator (1) + attachments (0-N)
///   + input lines (1-N, auto-wrapped at 90% terminal width)
///   + separator (1) + suggestions (0-N) + tips (0-1)
///
/// This must stay exactly consistent with `build_fixed_area_lines` — the
/// scroll overflow math uses it to compute the output height.
fn TuiController::fixed_area_height(self : TuiController) -> Int {
  let content_width = effective_content_width(self.term_width)
  let input_rows = self.input.render_wrapped_lines(content_width).length()
  let attach_rows = self.state.val.paste_placeholders.length()
  let suggestion_rows = if self.suggestions_active {
    self.suggestions.render().length()
  } else {
    0
  }
  let tips_rows = if self.tips.message is Some(_) { 1 } else { 0 }
  self.todo_row_count() +
  1 +
  1 +
  attach_rows +
  input_rows +
  1 +
  suggestion_rows +
  tips_rows
}

// ── Dialog / progress ─────────────────────────────────────────────────

///|
/// Get the active dialog Node if any.
fn TuiController::get_dialog_node(self : TuiController) -> Node? {
  match self.state.val.dialog {
    NoDialog => None
    Approval(dialog) => Some(render_approval_dialog(dialog))
    ConfigMenu(dialog) =>
      Some(render_config_menu(dialog, term_width=self.term_width))
    Form(dialog) => Some(render_form_dialog(dialog))
    ConfigForm(form~, ..) => Some(render_form_dialog(form))
    TimeMachineMenu(dialog) =>
      Some(
        render_config_menu(
          dialog,
          term_width=self.term_width,
          hints=Some("↑↓/jk Navigate  Enter Switch  Esc Cancel"),
        ),
      )
    ModelDrawer(level~, dialog~, ..) => {
      let hints = if level is Cards {
        "↑↓/jk Navigate  Enter/→ Select  Esc Close"
      } else {
        "↑↓/jk Navigate  Enter Select  ←/Esc Back"
      }
      Some(
        render_config_menu(
          dialog,
          term_width=self.term_width,
          hints=Some(hints),
        ),
      )
    }
  }
}

///|
/// Get progress indicator lines for overlay rendering.
fn TuiController::get_progress_lines(self : TuiController) -> Array[String] {
  let lines : Array[String] = []
  // Tool call progress
  if self.state.val.mode is Running {
    let tool_name = self.state.val.current_tool_name
    if tool_name.length() > 0 {
      lines.push("  > \{tool_name}...")
    }
  }
  // LLM call indicator
  if self.state.val.llm_calling {
    let dots = ".".repeat(self.state.val.tick_count % 3 + 1)
    lines.push("  Thinking\{dots}")
  }
  lines
}

// ── Cursor placement ──────────────────────────────────────────────────

///|
/// Position cursor in the input area after rendering.
///
/// The incremental painter hides the cursor; this shows it and positions
/// it at the correct location for text editing.
async fn TuiController::place_cursor(self : TuiController) -> Unit {
  let h = self.term_height
  // Borderless bottom fixed area: todo rows + status(1) + separator(1)
  // + attachments, then the wrapped input lines.
  let fixed_h = self.fixed_area_height()
  let attach_rows = self.state.val.paste_placeholders.length()
  let todo_rows = self.todo_row_count()
  let input_top = h - fixed_h + 3 + todo_rows + attach_rows
  let content_width = effective_content_width(self.term_width)
  let (cursor_row, cursor_col) = self.input.cursor_display_pos_wrapped(
    content_width,
  )
  let (row, col) = (input_top + cursor_row, 1 + cursor_col)
  // Show cursor and position it
  let ansi = "\u{1b}[?25h\u{1b}[\{row};\{col}H"
  self.tty.write_string(ansi)
}
