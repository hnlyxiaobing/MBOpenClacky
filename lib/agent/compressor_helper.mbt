///| Helper functions for the Insert-then-Compress message compression system.

///| Reference: openclacky/lib/clacky/agent/message_compressor_helper.rb

///|

// 鈹€鈹€ XML Content Extraction 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

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

// 鈹€鈹€ Message Counting 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

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

// 鈹€鈹€ Summary Message Builder 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

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

// 鈹€鈹€ Idle Compression Check 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

///|
/// Check if idle compression should trigger based on estimated token count.
pub fn should_trigger_idle_compression(
  messages : Array[@message.Message],
  threshold : Int,
) -> Bool {
  let tokens = estimate_history_tokens(messages)
  tokens >= threshold
}

// 鈹€鈹€ Compression Stats 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

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

// 鈹€鈹€ KeyInformation 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

///|
/// Key information extracted from conversation messages.
/// Used for generating hierarchical summaries and chunk metadata.
pub(all) struct KeyInformation {
  files_mentioned : Array[String]
  decisions_made : Array[String]
  tasks_completed : Array[String]
  tasks_pending : Array[String]
  errors_encountered : Array[String]
} derive(Eq, Debug)

// 鈹€鈹€ Keyword Matching Helpers 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

///|
/// Check if a line looks like a file path (has a known extension or path separator).
fn is_likely_file_path(s : String) -> Bool {
  if s.contains("/") || s.contains("\\") {
    if s.contains(".mbt") ||
      s.contains(".rb") ||
      s.contains(".py") ||
      s.contains(".js") ||
      s.contains(".ts") ||
      s.contains(".json") ||
      s.contains(".toml") ||
      s.contains(".md") ||
      s.contains(".txt") ||
      s.contains(".yaml") ||
      s.contains(".yml") ||
      s.contains(".c") ||
      s.contains(".h") ||
      s.contains(".rs") ||
      s.contains(".go") {
      return true
    }
  }
  false
}

///|
/// Extract file paths mentioned in text, one per line.
fn extract_file_paths_from_text(text : String) -> Array[String] {
  let lines = text.split("\n")
  let paths : Array[String] = []
  for line in lines {
    let trimmed = line.trim().to_owned()
    if is_likely_file_path(trimmed) {
      paths.push(trimmed)
    }
  }
  paths
}

///|
/// Check if a string array already contains a value.
fn str_array_contains(arr : Array[String], val : String) -> Bool {
  for item in arr {
    if item == val {
      return true
    }
  }
  false
}

///|
/// Push a string to an array only if not already present.
fn push_unique(arr : Array[String], val : String) -> Unit {
  if !str_array_contains(arr, val) {
    arr.push(val)
  }
}

// 鈹€鈹€ Extract Key Information 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

///|
/// Extract key information from conversation messages via keyword matching.
///
/// Scans message content for file paths, decision keywords, task completion
/// indicators, pending tasks, and error messages.
pub fn extract_key_information(
  messages : Array[@message.Message],
) -> KeyInformation {
  let result : KeyInformation = {
    files_mentioned: [],
    decisions_made: [],
    tasks_completed: [],
    tasks_pending: [],
    errors_encountered: [],
  }

  for msg in messages {
    let text = content_to_text(msg.content)
    if text.is_empty() {
      continue
    }

    // Extract file paths from message content
    let paths = extract_file_paths_from_text(text)
    for p in paths {
      push_unique(result.files_mentioned, p)
    }

    // Extract decisions from assistant messages
    if msg.role == @message.Assistant {
      let sentences = text.split(".")
      for sentence in sentences {
        let s = sentence.trim().to_owned()
        if s.contains("decision") ||
          s.contains("decided") ||
          s.contains("chose") ||
          s.contains("will use") ||
          s.contains("selected") ||
          s.contains("using") {
          if s.length() > 0 && s.length() <= 200 {
            push_unique(result.decisions_made, s)
          }
        }
      }
    }

    // Extract completed tasks from tool messages
    if msg.role == @message.Tool {
      if text.contains("completed") ||
        text.contains("done") ||
        text.contains("success") ||
        text.contains("created") ||
        text.contains("written") {
        let cap = if text.length() > 100 { 100 } else { text.length() }
        push_unique(result.tasks_completed, text[0:cap].trim().to_owned())
      }
    }

    // Extract errors from any message
    if msg.role == @message.User || msg.role == @message.Assistant {
      if text.contains("error") ||
        text.contains("Error") ||
        text.contains("failed") ||
        text.contains("Failed") {
        let cap = if text.length() > 100 { 100 } else { text.length() }
        push_unique(result.errors_encountered, text[0:cap].trim().to_owned())
      }
    }

    // Extract pending tasks
    if msg.role == @message.Tool {
      if text.contains("pending") ||
        text.contains("blocked") ||
        text.contains("waiting") ||
        text.contains("TODO") {
        let cap = if text.length() > 100 { 100 } else { text.length() }
        push_unique(result.tasks_pending, text[0:cap].trim().to_owned())
      }
    }
  }

  result
}

// 鈹€鈹€ Hierarchical Summary 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

///|
/// Generate a hierarchical summary based on compression level.
///
/// - Level 1: Concatenate all summaries directly (detailed)
/// - Level 2: Group by topic, one sentence per group
/// - Level 3: Extract key decisions and milestones only
/// - Level 4: Single-line summary of overall project state
pub fn generate_hierarchical_summary(
  summaries : Array[String],
  level : Int,
) -> String {
  if summaries.length() == 0 {
    return "No previous conversation context."
  }

  match level {
    1 =>
      // Level 1: Direct concatenation of all summaries
      summaries.join("\n\n")
    2 => {
      // Level 2: Concise summary 鈥?first sentence of each
      let parts : Array[String] = []
      for s in summaries {
        let first = first_sentence(s)
        if !first.is_empty() {
          parts.push(first)
        }
      }
      "Conversation summary:\n" + parts.join("\n")
    }
    3 => {
      // Level 3: Key decisions and milestones only
      let parts : Array[String] = []
      for s in summaries {
        let key = extract_key_sentences(s)
        if !key.is_empty() {
          parts.push(key)
        }
      }
      if parts.length() > 0 {
        "Key progress: " + parts.join("; ")
      } else {
        first_sentence(summaries[0])
      }
    }
    _ => {
      // Level 4+: Ultra-minimal single-line summary
      let total = summaries.length()
      let first = first_sentence(summaries[0])
      "Progress across \{total} compression(s): \{first}"
    }
  }
}

///|
/// Extract the first sentence from text (up to first period or newline).
fn first_sentence(text : String) -> String {
  let mut end = text.length()
  for i = 0; i < text.length(); i = i + 1 {
    if text[i] == '.' || text[i] == '\n' {
      end = i + 1
      break
    }
  }
  if end > 200 {
    end = 200
  }
  text[0:end].trim().to_owned()
}

///|
/// Extract key sentences containing decision or milestone keywords.
fn extract_key_sentences(text : String) -> String {
  let sentences = text.split(".")
  let key : Array[String] = []
  for s in sentences {
    let trimmed = s.trim().to_owned()
    if trimmed.contains("decision") ||
      trimmed.contains("decided") ||
      trimmed.contains("completed") ||
      trimmed.contains("created") ||
      trimmed.contains("milestone") ||
      trimmed.contains("deployed") {
      key.push(trimmed)
    }
  }
  key.join(". ")
}

// 鈹€鈹€ Tool Result Truncation 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

///|
/// Truncate oversized tool result content to avoid token bloat.
///
/// If `content` exceeds `max_chars`, keeps the first 1500 characters and
/// appends a truncation marker. Designed to be applied only to tool_result
/// role messages (caller's responsibility to check role).
pub fn truncate_tool_result(
  content : String,
  max_chars? : Int = 2000,
) -> String {
  if content.length() <= max_chars {
    content
  } else {
    let keep = 1500
    let actual_keep = if keep < content.length() {
      keep
    } else {
      content.length()
    }
    let truncated_count = content.length() - actual_keep
    content[0:actual_keep].to_owned() +
    "... [truncated \{truncated_count} chars] ..."
  }
}

// 鈹€鈹€ Chunk Index Helpers 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

///|
/// Metadata about a previously archived chunk file, used for building
/// the previous-chunks index section in compressed summaries.
pub(all) struct ChunkInfo {
  basename : String
  path : String
  topics : String?
} derive(Eq, Debug)

///|
/// Build a previous-chunks index section for embedding in compressed summaries.
///
/// Lists up to 10 most recent chunks (newest first) with their topics,
/// so the AI can locate older conversation archives via file_reader.
pub fn build_previous_chunks_index(
  previous_chunks : Array[ChunkInfo],
) -> String {
  if previous_chunks.length() == 0 {
    return ""
  }

  let mut section = "\n\n---\nPrevious chunks (newest first):\n"
  let max_visible = 10
  let total = previous_chunks.length()
  let start = if total > max_visible { total - max_visible } else { 0 }

  // Iterate newest to oldest
  let mut i = total - 1
  while i >= start {
    let chunk = previous_chunks[i]
    match chunk.topics {
      Some(t) if !t.is_empty() =>
        section = section + "- `\{chunk.basename}` -- \{t}\n"
      _ => section = section + "- `\{chunk.basename}`\n"
    }
    if i == 0 {
      break
    }
    i = i - 1
  }

  if start > 0 {
    let oldest = previous_chunks[0]
    section = section +
      "- ... and \{start} older chunks back to `\{oldest.basename}`\n"
  }

  section = section + "_Use `file_reader` to recall details from these chunks._"
  section
}

///|
/// Build a compressed summary message with chunk path anchor and previous
/// chunks index embedded in the content.
pub fn build_compressed_summary_with_chunks(
  summary : String,
  topics : String,
  chunk_path? : String? = None,
  previous_chunks? : Array[ChunkInfo] = [],
) -> @message.Message {
  let mut content = "[Compressed conversation summary -- previous turns archived]\n"

  // Add topics line
  if !topics.is_empty() {
    content = content + "Topics: " + topics + "\n\n"
  } else {
    content = content + "\n"
  }

  // Add summary text
  content = content + summary

  // Add previous chunks index
  if previous_chunks.length() > 0 {
    content = content + build_previous_chunks_index(previous_chunks)
  }

  // Add chunk path anchor
  match chunk_path {
    Some(path) => {
      content = content +
        "\n\n---\nCurrent chunk archived at: `\{path}`\n" +
        "_Use `file_reader` tool to recall details from this chunk._"
      // Also add HTML comment anchor for programmatic lookup
      content = content + "\n<!-- chunk: \{path} -->"
    }
    None => ()
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
