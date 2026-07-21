///|
/// AgentOutputSync: mirrors agent reply state into the OutputBuffer.
///
/// Agent hooks write finalized replies into `TuiState.messages` and
/// in-progress streaming text into `TuiState.streaming_buffer` through a
/// Ref, bypassing the TuiEvent queue. The controller polls that state on
/// Tick and AgentDone; this struct tracks how much of it has already been
/// mirrored so each reply is displayed exactly once.
///
/// Streaming text is shown in a single live (uncommitted) entry that is
/// replaced in place as the buffer grows; when the hook finalizes the
/// reply into `messages`, the same entry is reused for the final text,
/// so the reply never appears twice.
pub struct AgentOutputSync {
  /// Number of `messages` entries already mirrored to the output.
  mut last_synced_index : Int
  /// Length of the streaming buffer content currently displayed.
  mut last_displayed_length : Int
  /// Entry id of the live streaming entry, if one is showing.
  mut stream_entry_id : Int?
  /// Renderer used to apply Markdown styling to finalized replies.
  mut markdown : MarkdownRenderer
}

///|
/// Create a fresh sync tracker (nothing mirrored yet).
fn AgentOutputSync::new() -> AgentOutputSync {
  {
    last_synced_index: 0,
    last_displayed_length: 0,
    stream_entry_id: None,
    markdown: MarkdownRenderer::new(theme=Theme::default_()),
  }
}

///|
/// Switch the theme used for Markdown rendering of finalized replies.
fn AgentOutputSync::set_theme(self : AgentOutputSync, theme : Theme) -> Unit {
  self.markdown = MarkdownRenderer::new(theme~)
}

///|
/// Split text into display lines (same convention as OutputBuffer::append_text).
fn split_display_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  for sv in text.split("\n") {
    lines.push(sv.to_owned())
  }
  lines
}

///|
/// Apply Markdown styling to a finalized "[assistant]" message.
///
/// The "[assistant] " prefix is kept as plain text; the body is rendered
/// to an ANSI-colored string. Other messages pass through unchanged.
fn AgentOutputSync::render_message(
  self : AgentOutputSync,
  msg : String,
) -> String {
  let prefix = "[assistant] "
  if msg.has_prefix(prefix) {
    let body = msg[prefix.length():].to_owned()
    prefix + render_markdown_preserving_lines(self.markdown, body)
  } else {
    msg
  }
}

///|
/// Render Markdown while preserving the input's line structure.
///
/// `MarkdownRenderer::render` concatenates consecutive Paragraph tokens
/// without newlines, so the input is split into segments first: fenced
/// code blocks stay together (they need multi-line context), every other
/// line is rendered on its own. Rendered segments are joined with "\n".
fn render_markdown_preserving_lines(
  renderer : MarkdownRenderer,
  text : String,
) -> String {
  let rendered : Array[String] = []
  let fence : Array[String] = []
  let mut in_fence = false
  for sv in text.split("\n") {
    let line = sv.to_owned()
    if in_fence {
      fence.push(line)
      if line.has_prefix("```") {
        rendered.push(trim_trailing_newline(renderer.render(fence.join("\n"))))
        fence.clear()
        in_fence = false
      }
    } else if line.has_prefix("```") {
      fence.push(line)
      in_fence = true
    } else {
      rendered.push(trim_trailing_newline(renderer.render(line)))
    }
  }
  // Unclosed fence: render what was collected as a code block.
  if fence.length() > 0 {
    rendered.push(trim_trailing_newline(renderer.render(fence.join("\n"))))
  }
  rendered.join("\n")
}

///|
/// Remove a single trailing newline, if present.
fn trim_trailing_newline(s : String) -> String {
  if s.has_suffix("\n") {
    s[:s.length() - 1].to_owned()
  } else {
    s
  }
}

///|
/// Mirror newly finalized messages into the output buffer.
///
/// Returns true if the output buffer was modified.
fn AgentOutputSync::sync_messages(
  self : AgentOutputSync,
  messages : Array[String],
  output : OutputBuffer,
) -> Bool {
  let mut changed = false
  while self.last_synced_index < messages.length() {
    let display = self.render_message(messages[self.last_synced_index])
    match self.stream_entry_id {
      Some(id) => {
        // The live streaming entry already shows this reply — finalize it
        // in place instead of appending a duplicate.
        match output.replace(id, split_display_lines(display)) {
          Some(_) => ()
          None => ignore(output.append_text(display, OutputKind::Text))
        }
        self.stream_entry_id = None
        self.last_displayed_length = 0
      }
      None => ignore(output.append_text(display, OutputKind::Text))
    }
    self.last_synced_index = self.last_synced_index + 1
    changed = true
  }
  changed
}

///|
/// Mirror the in-progress streaming buffer into a live output entry.
///
/// The entry is replaced in place as the buffer grows, so the reply
/// appears to stream in real time. A cleared buffer (the hook finalized
/// or discarded the reply) resets the tracking so the next stream starts
/// a fresh entry.
///
/// Returns true if the output buffer was modified.
fn AgentOutputSync::sync_streaming(
  self : AgentOutputSync,
  streaming_buffer : String,
  messages : Array[String],
  output : OutputBuffer,
) -> Bool {
  // Finalize completed replies first — the hook may have pushed the
  // message and cleared the buffer between two ticks.
  let mut changed = self.sync_messages(messages, output)
  if streaming_buffer.length() < self.last_displayed_length {
    // Buffer shrank without a finalized message (e.g. error) — keep the
    // partial entry as-is and start fresh on the next stream.
    self.last_displayed_length = 0
    self.stream_entry_id = None
  }
  if streaming_buffer.length() > self.last_displayed_length {
    self.last_displayed_length = streaming_buffer.length()
    let text = "[assistant] \{streaming_buffer}"
    match self.stream_entry_id {
      Some(id) =>
        match output.replace(id, split_display_lines(text)) {
          Some(_) => ()
          None => {
            // Entry was committed externally — open a fresh live entry.
            let new_id = output.append_text(text, OutputKind::Text)
            self.stream_entry_id = Some(new_id)
          }
        }
      None => {
        let id = output.append_text(text, OutputKind::Text)
        self.stream_entry_id = Some(id)
      }
    }
    changed = true
  }
  changed
}
