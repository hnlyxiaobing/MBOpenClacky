///| MessageHistory - Advanced message history manager.

///| Provides internal field filtering, UTF-8 sanitization,

///| dangling tool call cleanup, and token estimation.

///|
pub(all) struct MessageHistory {
  mut messages : Array[Message]
} derive(Eq)

// ── Constructor ──────────────────────────────────────────────────────────────

///|
/// Create an empty message history.
pub fn MessageHistory::new() -> MessageHistory {
  { messages: [] }
}

///|
/// Create a message history from an existing array of messages.
pub fn MessageHistory::from_messages(msgs : Array[Message]) -> MessageHistory {
  { messages: msgs }
}

// ── Write operations ─────────────────────────────────────────────────────────

///| Append a message to the history.

///| When appending a user message, automatically drops any trailing

///|
/// assistant message with unanswered tool_calls (dangling).
pub fn MessageHistory::append(self : MessageHistory, msg : Message) -> Unit {
  if msg.role == User {
    self.drop_dangling_tool_calls()
  }
  self.messages.push(deep_sanitize_utf8(msg))
}

///|
/// Replace (or insert at head) the system prompt message.
pub fn MessageHistory::replace_system_prompt(
  self : MessageHistory,
  content : String,
) -> Unit {
  let new_msg = Message::system(content)
  let len = self.messages.length()
  let mut found = -1
  for i = 0; i < len; i = i + 1 {
    if self.messages[i].role == System {
      found = i
      break
    }
  }
  if found >= 0 {
    self.messages[found] = new_msg
  } else {
    // Insert at head
    let old = self.messages
    self.messages = [new_msg]
    for m in old {
      self.messages.push(m)
    }
  }
}

///|
/// Remove and return the last message, or None if empty.
pub fn MessageHistory::pop_last(self : MessageHistory) -> Message? {
  if self.messages.is_empty() {
    None
  } else {
    let len = self.messages.length()
    let msg = self.messages[len - 1]
    let kept : Array[Message] = []
    for i = 0; i < len - 1; i = i + 1 {
      kept.push(self.messages[i])
    }
    self.messages = kept
    Some(msg)
  }
}

///|
/// Truncate history from the given index onward.
pub fn MessageHistory::truncate_from(
  self : MessageHistory,
  index : Int,
) -> Unit {
  if index >= 0 && index < self.messages.length() {
    let kept : Array[Message] = []
    for i = 0; i < index; i = i + 1 {
      kept.push(self.messages[i])
    }
    self.messages = kept
  }
}

// ── Query operations ─────────────────────────────────────────────────────────

///|
/// Return API-ready messages with internal fields stripped and UTF-8 sanitized.
pub fn MessageHistory::to_api(self : MessageHistory) -> Array[Message] {
  let result : Array[Message] = []
  for msg in self.messages {
    result.push(strip_internal_fields(msg))
  }
  result
}

///|
/// Return all messages (including internal fields).
pub fn MessageHistory::all(self : MessageHistory) -> Array[Message] {
  self.messages
}

///|
/// Return only real (non-system-injected) user messages.
pub fn MessageHistory::real_user_messages(
  self : MessageHistory,
) -> Array[Message] {
  let result : Array[Message] = []
  for msg in self.messages {
    if msg.role == User {
      match msg.system_injected {
        Some(true) => continue
        _ => result.push(msg)
      }
    }
  }
  result
}

///|
/// Check if the last assistant message has unanswered tool_calls.
pub fn MessageHistory::pending_tool_calls(self : MessageHistory) -> Bool {
  let len = self.messages.length()
  if len == 0 {
    return false
  }
  let last = self.messages[len - 1]
  // Last message must be assistant with tool_calls
  guard last.role == Assistant else { return false }
  let calls = match last.tool_calls {
    Some(tc) => tc
    None => return false
  }
  if calls.is_empty() {
    return false
  }
  // Find last assistant index
  let mut last_assistant_idx = len - 1
  for i = len - 1; i >= 0; i = i - 1 {
    if self.messages[i] == last {
      last_assistant_idx = i
      break
    }
  }
  // Check if any tool result follows
  for i = last_assistant_idx + 1; i < len; i = i + 1 {
    if self.messages[i].role == Tool {
      return false
    }
  }
  true
}

///|
/// Estimate total token count for all messages.
pub fn MessageHistory::estimate_tokens(self : MessageHistory) -> Int {
  let mut total = 0
  for msg in self.messages {
    total = total + estimate_message_tokens(msg)
  }
  total
}

///|
/// Return the index of the last real (non-system-injected) user message.
pub fn MessageHistory::last_real_user_index(self : MessageHistory) -> Int? {
  let len = self.messages.length()
  for i = len - 1; i >= 0; i = i - 1 {
    let msg = self.messages[i]
    if msg.role == User {
      match msg.system_injected {
        Some(true) => continue
        _ => return Some(i)
      }
    }
  }
  None
}

///|
/// Return the number of messages.
pub fn MessageHistory::size(self : MessageHistory) -> Int {
  self.messages.length()
}

///|
/// Check if the history is empty.
pub fn MessageHistory::is_empty(self : MessageHistory) -> Bool {
  self.messages.is_empty()
}

// ── Private helpers ──────────────────────────────────────────────────────────

///|
/// Strip internal fields from a message, returning an API-ready copy.
fn strip_internal_fields(msg : Message) -> Message {
  {
    role: msg.role,
    content: msg.content,
    tool_calls: msg.tool_calls,
    tool_call_id: msg.tool_call_id,
    name: msg.name,
    task_id: None,
    created_at: None,
    system_injected: None,
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
}

///| Recursively sanitize UTF-8 in message content.

///|
/// Replaces invalid characters with U+FFFD replacement character.
fn deep_sanitize_utf8(msg : Message) -> Message {
  let content = match msg.content {
    MessageContent::Text(s) => MessageContent::Text(sanitize_utf8_string(s))
    MessageContent::Blocks(blocks) => {
      let cleaned : Array[ContentBlock] = []
      for block in blocks {
        match block {
          ContentBlock::Text(tb) =>
            cleaned.push(
              ContentBlock::Text({ text: sanitize_utf8_string(tb.text) }),
            )
          ContentBlock::Image(ib) =>
            cleaned.push(
              ContentBlock::Image({
                url: sanitize_utf8_string(ib.url),
                detail: ib.detail,
              }),
            )
        }
      }
      MessageContent::Blocks(cleaned)
    }
  }
  {
    role: msg.role,
    content,
    tool_calls: msg.tool_calls,
    tool_call_id: msg.tool_call_id,
    name: msg.name,
    task_id: msg.task_id,
    created_at: msg.created_at,
    system_injected: msg.system_injected,
    memory_update: msg.memory_update,
    subagent_instructions: msg.subagent_instructions,
    subagent_result: msg.subagent_result,
    token_usage: msg.token_usage,
    compressed_summary: msg.compressed_summary,
    transient: msg.transient,
  }
}

///| Sanitize a UTF-8 string by replacing invalid chars with U+FFFD.

///| MoonBit strings are valid UTF-16 internally, so this is primarily

///|
/// a defense-in-depth pass for data from external sources.
fn sanitize_utf8_string(s : String) -> String {
  // MoonBit strings are internally valid, but we iterate to clean
  // any replacement characters or control chars that snuck in.
  let buf = StringBuilder::new()
  for c in s {
    // Replace null bytes and surrogates with replacement char
    if c == '\u0000' {
      buf.write_char('\u{FFFD}')
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Estimate token count for a single message.
fn estimate_message_tokens(msg : Message) -> Int {
  // ~4 tokens overhead per message (role, formatting)
  let mut tokens = 4
  // Content tokens
  match msg.content {
    Text(s) => tokens = tokens + estimate_token_count(s)
    Blocks(blocks) =>
      for block in blocks {
        match block {
          ContentBlock::Text(tb) =>
            tokens = tokens + estimate_token_count(tb.text)
          ContentBlock::Image(_) => tokens = tokens + 100
        }
      }
  }
  // Tool calls overhead
  match msg.tool_calls {
    Some(calls) =>
      for tc in calls {
        tokens = tokens + 50
        tokens = tokens + estimate_token_count(tc.function.name)
        tokens = tokens + estimate_token_count(tc.function.arguments)
      }
    None => ()
  }
  tokens
}

///|
/// Estimate token count from string length (~4 chars per token).
fn estimate_token_count(s : String) -> Int {
  let len = s.length()
  // Ceiling division: (len + 3) / 4
  (len + 3) / 4
}

///| Drop the trailing assistant message if it has tool_calls with no

///|
/// subsequent tool result (dangling). Called before appending user messages.
fn MessageHistory::drop_dangling_tool_calls(self : MessageHistory) -> Unit {
  if self.pending_tool_calls() {
    let _ = self.messages.pop()
  }
}
