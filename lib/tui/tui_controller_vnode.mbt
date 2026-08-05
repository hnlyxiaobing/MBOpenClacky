///|
/// VNode-based rendering methods for TuiController.
///
/// These methods build a complete VNode tree from the controller's state
/// and render it using the VNodeRenderer, replacing the imperative
/// ScreenBuffer + LayoutManager rendering approach.

///|
/// Full screen redraw using VNode rendering.
///
/// Commit-scrollback model (aligned with Ruby ui2/layout_manager.rb):
/// - The output area height is limited to `term_height - 5` (status bar 1 +
///   input area 4, the fixed bottom area).
/// - When live (uncommitted) display rows overflow that height, the oldest
///   rows are pushed into the terminal's native scrollback with real
///   newlines and marked committed in the OutputBuffer.
/// - The VNode frame then renders only the still-live lines plus the fixed
///   bottom area, so committed lines are never re-rendered (no duplicates,
///   no flicker on resize).
async fn TuiController::full_redraw_vnode(self : TuiController) -> Unit {
  // Update layout dimensions
  let (tw, th) = query_size_safe(self.tty)
  self.term_width = tw
  self.term_height = th
  let (width, height) = (self.term_width, self.term_height)
  self.vnode_renderer.resize(width, height)

  // Commit overflow: live display rows beyond the output area height leave
  // the screen into the terminal scrollback. The output area height is the
  // terminal height minus the bottom fixed area (status bar, separators,
  // attachments, input lines, suggestions, tips).
  let fixed_h = self.fixed_area_height()
  let msg_height = height - fixed_h
  if msg_height > 0 {
    let live_count = self.output.live_display_lines().length()
    let overflow = live_count - msg_height
    if overflow > 0 {
      self.commit_overflow_lines(overflow)
    }
  }

  // Build status text (adaptive to terminal width)
  self.status_bar.format_from_state_adaptive(self.state.val, self.term_width)
  let status_text = self.status_bar.colored_text()

  // Get live output lines (committed lines are excluded by construction)
  let output_lines = self.output.live_display_lines()

  // Build the complete screen VNode
  let vnode = self.build_complete_vnode(status_text, output_lines)

  // Render to terminal
  self.vnode_renderer.render(vnode)

  // Position cursor in input area
  self.place_cursor_vnode()
}

///|
/// Push the oldest live display rows into the terminal scrollback.
///
/// The rows about to be committed may never have been painted by a VNode
/// frame (a single batch can append more lines than the screen shows —
/// e.g. the startup banner on a small terminal, or a long tool dump).
/// The terminal only adds to its scrollback the rows that physically
/// scroll off the top, so we first reprint the `overflow` oldest live
/// display rows at the top of the screen (each truncated to one terminal
/// row), then emit `overflow` real newlines at the bottom row to scroll
/// them off, and finally mark them committed in the buffer. The following
/// VNode render repaints the screen with the remaining live lines.
async fn TuiController::commit_overflow_lines(
  self : TuiController,
  overflow : Int,
) -> Unit {
  // Capture the live display rows before committing; the oldest `scrolled`
  // of them are exactly the rows that must enter the scrollback.
  let live = self.output.live_display_lines()
  let scrolled = self.output.commit_oldest_display_lines(overflow)
  if scrolled <= 0 {
    return
  }
  let buf = StringBuilder::new()
  buf.write_string("\u{1b}[1;1H")
  let mut i = 0
  while i < scrolled && i < live.length() {
    buf.write_string(truncate_ansi_line(live[i], self.term_width))
    buf.write_string("\u{1b}[0m\r\n")
    i = i + 1
  }
  // Scroll the whole screen up by the number of rows actually committed, so
  // the reprinted rows (and only those) enter the native scrollback.
  buf.write_string("\u{1b}[" + self.term_height.to_string() + ";1H")
  for _ in 0..<scrolled {
    buf.write_char('\n')
  }
  self.tty.write_string(buf.to_string())
}

///|
/// Truncate a possibly ANSI-styled line to at most `width` display columns
/// (CJK-aware), passing escape sequences through untouched so exactly one
/// terminal row is occupied when the line is printed directly to the tty.
fn truncate_ansi_line(line : String, width : Int) -> String {
  let buf = StringBuilder::new()
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
/// This must stay exactly consistent with the fixed children assembled in
/// `build_complete_vnode` — the commit-scrollback overflow math uses it to
/// compute the output area height.
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

///|
/// Build the complete screen VNode tree including overlays.
fn TuiController::build_complete_vnode(
  self : TuiController,
  status_text : String,
  output_lines : Array[String],
) -> @vnode.TuiNode {
  let term_width = self.term_width.to_double()
  let content_width = effective_content_width(self.term_width)

  // Build output area children (preserve ANSI colors via parser)
  let output_children : Array[@vnode.TuiNode] = []
  for line in output_lines {
    let plain = strip_ansi(line)
    if plain.length() > 0 {
      output_children.push(ansi_line_to_vnode(line))
    } else {
      output_children.push(@vnode.text(" "))
    }
  }

  // Add thinking view if active (VNode direct, with spinner animation)
  if self.state.val.thinking_buffer.get().length() > 0 {
    output_children.push(
      render_thinking_live_vnode(
        self.state.val,
        self.thinking_animator,
        self.state.val.tick_count,
      ),
    )
  }

  // Add dialog if active
  let dialog_node = self.get_dialog_node()
  match dialog_node {
    Some(node) => output_children.push(node_to_vnode(node))
    None => ()
  }

  // Progress indicators stay as overlay rows at the bottom of the output area
  let progress_lines = self.get_progress_lines()
  for line in progress_lines {
    output_children.push(ansi_line_to_vnode(line))
  }

  // Build status node — flat sized row spanning the full terminal width.
  // The DSL treats a numeric width as absolute columns (Length), so we must
  // pass the real terminal width; the old hardcoded 100.0 truncated the
  // ~118-column status bar (see SPEC-01).
  let status_node = ansi_line_to_vnode_sized(status_text, term_width, 1.0)

  // Build the bottom fixed area rows below the status bar, in Ruby ui2
  // order: separator, attachments, input lines, separator, suggestions, tips.
  let fixed_children : Array[@vnode.TuiNode] = []
  fixed_children.push(separator_node(self.term_width))
  // Attachment rows: one dim row per stored paste placeholder.
  for pair in self.state.val.paste_placeholders {
    let (num, text) = pair
    let n_lines = paste_line_count(text)
    fixed_children.push(
      @vnode.text(
        "  [#\{num} Paste Text] \{n_lines} lines",
        fg="rgb(128,128,128)",
      ),
    )
  }
  // Input lines (auto-wrapped, borderless).
  for line in self.input.render_wrapped_lines(content_width) {
    fixed_children.push(ansi_line_to_vnode(line))
  }
  fixed_children.push(separator_node(self.term_width))
  // Command suggestions dropdown.
  if self.suggestions_active {
    for line in self.suggestions.render() {
      fixed_children.push(ansi_line_to_vnode(line))
    }
  }
  // System tips row.
  match self.tips.message {
    Some(msg) =>
      fixed_children.push(
        ansi_line_to_vnode(format_tips(msg, self.tips.type_, self.term_width)),
      )
    None => ()
  }

  // Todo area rows (directly above the status bar, Ruby ui2 order).
  let todo_children : Array[@vnode.TuiNode] = []
  if self.state.val.todo_area.visible() {
    for line in self.state.val.todo_area.render_lines() {
      todo_children.push(ansi_line_to_vnode(line))
    }
  }

  build_main_layout(
    status_node, output_children, todo_children, fixed_children, term_width,
  )
}

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

///|
/// Position cursor in the input area after VNode rendering.
///
/// VNode rendering hides the cursor; this shows it and positions
/// it at the correct location for text editing.
async fn TuiController::place_cursor_vnode(self : TuiController) -> Unit {
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
