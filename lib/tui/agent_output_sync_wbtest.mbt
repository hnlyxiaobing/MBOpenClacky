///|
/// Tests for AgentOutputSync (P0-1 agent reply rendering pipeline).
///
/// The sync tracker mirrors `TuiState.messages` (finalized replies) and
/// `TuiState.streaming_buffer` (in-progress streaming) into an OutputBuffer,
/// guaranteeing each reply is displayed exactly once.

///|
test "sync_messages appends new messages once" {
  let output = OutputBuffer::new()
  let sync = AgentOutputSync::new()
  let messages : Array[String] = ["[assistant] hello"]
  assert_true(sync.sync_messages(messages, output))
  assert_eq(output.entry_count(), 1)
  assert_eq(output.tail_lines(1), ["[assistant] hello"])
  // Second call with no new messages is a no-op
  assert_false(sync.sync_messages(messages, output))
  assert_eq(output.entry_count(), 1)
}

///|
test "sync_streaming grows a single live entry in place" {
  let output = OutputBuffer::new()
  let sync = AgentOutputSync::new()
  let messages : Array[String] = []
  assert_true(sync.sync_streaming("Hello", messages, output))
  assert_eq(output.entry_count(), 1)
  assert_true(sync.sync_streaming("Hello, world", messages, output))
  // Still one entry — replaced, not appended
  assert_eq(output.entry_count(), 1)
  assert_eq(output.tail_lines(1), ["[assistant] Hello, world"])
  // No growth — no change
  assert_false(sync.sync_streaming("Hello, world", messages, output))
}

///|
test "finalized message reuses the live streaming entry" {
  let output = OutputBuffer::new()
  let sync = AgentOutputSync::new()
  let messages : Array[String] = []
  ignore(sync.sync_streaming("partial reply", messages, output))
  // AfterLlmCall hook: push finalized message, clear the buffer
  messages.push("[assistant] partial reply")
  assert_true(sync.sync_streaming("", messages, output))
  // The same single entry now holds the finalized text — no duplicate
  assert_eq(output.entry_count(), 1)
  assert_eq(output.tail_lines(1), ["[assistant] partial reply"])
  // AgentDone sync finds nothing new
  assert_false(sync.sync_messages(messages, output))
  assert_eq(output.entry_count(), 1)
}

///|
test "two streaming rounds produce exactly two entries" {
  let output = OutputBuffer::new()
  let sync = AgentOutputSync::new()
  let messages : Array[String] = []
  ignore(sync.sync_streaming("first", messages, output))
  messages.push("[assistant] first")
  ignore(sync.sync_streaming("", messages, output))
  // Second LLM call streams into a fresh entry
  ignore(sync.sync_streaming("second", messages, output))
  messages.push("[assistant] second")
  ignore(sync.sync_messages(messages, output))
  assert_eq(output.entry_count(), 2)
  assert_eq(output.tail_lines(2), ["[assistant] first", "[assistant] second"])
}

///|
test "cleared buffer without message resets stream tracking" {
  let output = OutputBuffer::new()
  let sync = AgentOutputSync::new()
  let messages : Array[String] = []
  ignore(sync.sync_streaming("partial", messages, output))
  // Error path: buffer cleared without a finalized message
  assert_false(sync.sync_streaming("", messages, output))
  // The partial entry stays visible
  assert_eq(output.tail_lines(1), ["[assistant] partial"])
  // The next stream opens a fresh entry
  assert_true(sync.sync_streaming("new reply", messages, output))
  assert_eq(output.entry_count(), 2)
  assert_eq(output.tail_lines(2), [
    "[assistant] partial", "[assistant] new reply",
  ])
}

///|
test "sync_messages renders markdown headings with ANSI styles" {
  let output = OutputBuffer::new()
  let sync = AgentOutputSync::new()
  let messages : Array[String] = ["[assistant] # Hello"]
  ignore(sync.sync_messages(messages, output))
  // Heading: yellow + bold, "[assistant] " prefix stays plain
  assert_eq(output.tail_lines(1), [
    "[assistant] \u{1b}[38;2;255;255;85m\u{1b}[1mHello\u{1b}[0m",
  ])
}

///|
test "sync_messages renders inline markdown in assistant replies" {
  let output = OutputBuffer::new()
  let sync = AgentOutputSync::new()
  let messages : Array[String] = ["[assistant] line1\nline2 **bold**"]
  ignore(sync.sync_messages(messages, output))
  // Plain line structure is preserved; inline bold is styled
  assert_eq(output.tail_lines(2), [
    "[assistant] line1", "line2 \u{1b}[1mbold\u{1b}[0m",
  ])
}

///|
test "sync_messages renders fenced code blocks with ANSI styles" {
  let output = OutputBuffer::new()
  let sync = AgentOutputSync::new()
  let messages : Array[String] = ["[assistant] ```mbt\nlet x = 1\n```"]
  ignore(sync.sync_messages(messages, output))
  // Code block: cyan
  assert_eq(output.tail_lines(1), [
    "[assistant] \u{1b}[38;2;0;200;255mlet x = 1\u{1b}[0m",
  ])
}

///|
test "sync_messages renders list items using the theme dim color" {
  let output = OutputBuffer::new()
  let sync = AgentOutputSync::new()
  let messages : Array[String] = ["[assistant] - foo"]
  ignore(sync.sync_messages(messages, output))
  // Default theme dim color (gray) bullet
  assert_eq(output.tail_lines(1), [
    "[assistant] \u{1b}[38;2;128;128;128m• \u{1b}[0mfoo",
  ])
}

///|
test "sync_messages preserves blank lines in assistant replies" {
  let output = OutputBuffer::new()
  let sync = AgentOutputSync::new()
  let messages : Array[String] = ["[assistant] a\n\nb"]
  ignore(sync.sync_messages(messages, output))
  assert_eq(output.tail_lines(3), ["[assistant] a", "", "b"])
}

///|
test "sync_messages leaves non-assistant messages untouched" {
  let output = OutputBuffer::new()
  let sync = AgentOutputSync::new()
  let messages : Array[String] = ["[user] # not a heading"]
  ignore(sync.sync_messages(messages, output))
  assert_eq(output.tail_lines(1), ["[user] # not a heading"])
}
