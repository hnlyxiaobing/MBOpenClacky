///| Helper functions for the Insert-then-Compress message compression system.

///| Reference: openclacky/lib/clacky/agent/message_compressor_helper.rb

///|

// ── XML Content Extraction ──────────────────────────────────────────────────

///|
/// Extract content between XML-style tags.
/// e.g. extract_xml_content("<topics>a, b</topics>", "topics") => Some("a, b")
pub fn extract_xml_content(text : String, tag_name : String) -> String? {
  let open_tag = "<" + tag_name + ">"
  let close_tag = "</" + tag_name + ">"
  let open_len = open_tag.length()
  // Find the opening tag
  let mut open_idx = -1
  let text_len = text.length()
  for i = 0; i <= text_len - open_len; i = i + 1 {
    let mut matched = true
    for j = 0; j < open_len; j = j + 1 {
      if text[i + j] != open_tag[j] {
        matched = false
        break
      }
    }
    if matched {
      open_idx = i
      break
    }
  }
  if open_idx < 0 {
    return None
  }
  let content_start = open_idx + open_len
  // Find the closing tag
  let close_len = close_tag.length()
  let mut close_idx = -1
  for i = content_start; i <= text_len - close_len; i = i + 1 {
    let mut matched = true
    for j = 0; j < close_len; j = j + 1 {
      if text[i + j] != close_tag[j] {
        matched = false
        break
      }
    }
    if matched {
      close_idx = i
      break
    }
  }
  if close_idx < 0 {
    return None
  }
  // Extract content between tags using string slice
  let result = text[content_start:close_idx].trim().to_owned()
  if result.length() == 0 {
    None
  } else {
    Some(result)
  }
}

// ── Message Counting ────────────────────────────────────────────────────────

///|
/// Count messages that will be compressed (excludes system and recent messages).
pub fn count_messages_to_compress(
  messages : Array[@message.Message],
  recent_count : Int,
) -> Int {
  let len = messages.length()
  // Count non-system messages
  let mut non_system_count = 0
  for msg in messages {
    if msg.role != @message.System {
      non_system_count = non_system_count + 1
    }
  }
  // Messages to compress = non-system total minus the recent ones we keep
  let to_keep = if recent_count > non_system_count {
    non_system_count
  } else {
    recent_count
  }
  let _ = len
  non_system_count - to_keep
}

// ── Summary Message Builder ─────────────────────────────────────────────────

///|
/// Create a compressed summary message marked with compressed_summary flag.
/// Uses role: User with system_injected: true to maintain valid turn structure.
pub fn build_compressed_summary_message(
  summary : String,
  topics : String,
) -> @message.Message {
  let content = if topics.length() > 0 {
    "[Compressed conversation summary \u2014 previous turns archived]\nTopics: " +
    topics +
    "\n\n" +
    summary
  } else {
    "[Compressed conversation summary \u2014 previous turns archived]\n\n" +
    summary
  }
  {
    role: @message.User,
    content: @message.Text(content),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    task_id: None,
    created_at: None,
    system_injected: Some(true),
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: Some("true"),
    transient: None,
  }
}

// ── Idle Compression Check ──────────────────────────────────────────────────

///|
/// Check if idle compression should trigger based on estimated token count.
pub fn should_trigger_idle_compression(
  messages : Array[@message.Message],
  threshold : Int,
) -> Bool {
  let tokens = estimate_history_tokens(messages)
  tokens >= threshold
}

// ── Compression Stats ───────────────────────────────────────────────────────

///|
/// Statistics about a compression operation.
pub(all) struct CompressionStats {
  before_tokens : Int
  after_tokens : Int
  messages_removed : Int
  compression_ratio : Double
} derive(Eq, Debug)

///|
/// Calculate compression savings statistics.
pub fn calculate_compression_savings(
  before_tokens : Int,
  after_tokens : Int,
  messages_before : Int,
  messages_after : Int,
) -> CompressionStats {
  let ratio = if before_tokens > 0 {
    1.0 - after_tokens.to_double() / before_tokens.to_double()
  } else {
    0.0
  }
  {
    before_tokens,
    after_tokens,
    messages_removed: messages_before - messages_after,
    compression_ratio: ratio,
  }
}
