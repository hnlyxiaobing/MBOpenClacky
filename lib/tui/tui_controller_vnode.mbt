///|
/// VNode-based rendering methods for TuiController.
///
/// These methods build a complete VNode tree from the controller's state
/// and render it using the VNodeRenderer, replacing the imperative
/// ScreenBuffer + LayoutManager rendering approach.

///|
/// Full screen redraw using VNode rendering.
///
/// Builds a complete VNode tree from the current state (status bar,
/// output area, overlays, input area) and renders it in one shot
/// using mizchi/tui's flexbox layout and diff-based rendering engine.
async fn TuiController::full_redraw_vnode(self : TuiController) -> Unit {
  // Update layout dimensions
  let (tw, th) = query_size_safe(self.tty)
  self.term_width = tw
  self.term_height = th
  let (width, height) = (self.term_width, self.term_height)
  self.vnode_renderer.resize(width, height)

  // Handle file browser mode separately
  if self.state.val.shell_mode is ShellMode::FileBrowser {
    let node = self.build_file_browser_vnode()
    self.vnode_renderer.render(node)
    self.place_cursor_vnode()
    return
  }

  // Build status text (adaptive to terminal width)
  self.status_bar.format_from_state_adaptive(self.state.val, self.term_width)
  // Add scroll position indicator
  let msg_height = self.term_height - 5
  let total_lines = self.output.total_lines()
  self.status_bar.add_scroll_segment(
    self.scroll_offset,
    total_lines,
    msg_height,
  )
  let status_text = self.status_bar.colored_text()

  // Get output lines (tail to fit message area)
  let msg_height = self.term_height - 5
  let output_lines = self.output.tail_lines_with_scroll(
    msg_height,
    self.scroll_offset,
  )

  // Get input render lines
  let input_lines = self.input.render_lines()

  // Determine border color from theme
  let border_color = self.theme_border_color()

  // Build the complete screen VNode
  let vnode = self.build_complete_vnode(
    status_text, output_lines, input_lines, border_color,
  )

  // Render to terminal
  self.vnode_renderer.render(vnode)

  // Position cursor in input area
  self.place_cursor_vnode()
}

///|
/// Build the complete screen VNode tree including overlays.
fn TuiController::build_complete_vnode(
  self : TuiController,
  status_text : String,
  output_lines : Array[String],
  input_lines : Array[String],
  border_color : String,
) -> @vnode.TuiNode {
  let input_h = 4

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

  // Build overlay children (progress + suggestions above input)
  let overlay_children : Array[@vnode.TuiNode] = []
  // Progress indicators
  let progress_lines = self.get_progress_lines()
  for line in progress_lines {
    overlay_children.push(ansi_line_to_vnode(line))
  }
  // Suggestion dropdown
  if self.suggestions_active {
    let suggestion_lines = self.suggestions.render()
    for line in suggestion_lines {
      overlay_children.push(ansi_line_to_vnode(line))
    }
  }

  // Build input area children (preserve ANSI colors)
  let input_children : Array[@vnode.TuiNode] = []
  for line in input_lines {
    input_children.push(ansi_line_to_vnode(line))
  }
  while input_children.length() < input_h - 2 {
    input_children.push(@vnode.text(" "))
  }

  // Build status node — flat sized row spanning the full terminal width.
  // The DSL treats a numeric width as absolute columns (Length), so we must
  // pass the real terminal width; the old hardcoded 100.0 truncated the
  // ~118-column status bar (see SPEC-01).
  let term_width = self.term_width.to_double()
  let status_node = ansi_line_to_vnode_sized(status_text, term_width, 1.0)

  // Add overlay children to output if present
  if !overlay_children.is_empty() {
    for child in overlay_children {
      output_children.push(child)
    }
  }

  // Dispatch to brand layout builder
  match self.brand_layout {
    GeminiLike =>
      build_gemini_layout(
        status_node, output_children, input_children, border_color, input_h, term_width,
      )
    ClaudeCodeLike =>
      build_claude_code_layout(
        status_node,
        output_children,
        input_children,
        [],
        border_color,
        input_h,
      )
    Compact =>
      build_compact_layout(
        status_node, output_children, input_children, input_h, term_width,
      )
  }
}

///|
/// Build VNode for file browser mode.
fn TuiController::build_file_browser_vnode(
  self : TuiController,
) -> @vnode.TuiNode {
  let input_h = 4
  let term_width = self.term_width.to_double()
  let status_text = self.status_bar.colored_text()
  let node = render_file_browser(self.file_browser)
  let input_lines = self.input.render_lines()
  let border_color = self.theme_border_color()

  // Build input area children
  let input_children : Array[@vnode.TuiNode] = []
  for line in input_lines {
    input_children.push(ansi_line_to_vnode(line))
  }
  while input_children.length() < input_h - 2 {
    input_children.push(@vnode.text(" "))
  }

  @vnode.column(width=term_width, height=100.0, [
    // Flat sized status row spanning the full terminal width (see SPEC-01).
    ansi_line_to_vnode_sized(status_text, term_width, 1.0),
    @vnode.view(
      direction="column",
      flex_grow=1.0,
      width=term_width,
      border="rounded",
      border_color~,
      padding_x=1.0,
      [node_to_vnode(node)],
    ),
    @vnode.view(
      direction="column",
      width=term_width,
      height=input_h.to_double(),
      border="rounded",
      border_color~,
      padding_x=1.0,
      input_children,
    ),
  ])
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
/// Get border color from current theme.
fn TuiController::theme_border_color(self : TuiController) -> String {
  match self.theme.name {
    ThemeName::Default => "blue"
    ThemeName::Hacker => "green"
    ThemeName::Minimal => "white"
    ThemeName::Light => "black"
  }
}

///|
/// Position cursor in the input area after VNode rendering.
///
/// VNode rendering hides the cursor; this shows it and positions
/// it at the correct location for text editing.
async fn TuiController::place_cursor_vnode(self : TuiController) -> Unit {
  let (_, h) = (self.term_width, self.term_height)
  let input_h = 4
  let top = h - input_h
  let (cursor_line, cursor_col) = self.input.cursor_display_pos()
  let row = top + 1 + cursor_line
  // +1 for border, +1 for padding, +1 for 0-based to 1-based
  let col = 3 + cursor_col
  // Show cursor and position it
  let ansi = "\u{1b}[?25h\u{1b}[\{row};\{col}H"
  self.tty.write_string(ansi)
}
