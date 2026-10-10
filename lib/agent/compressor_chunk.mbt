///| Chunk MD archiving for the message compression system.

///|
/// Archives compressed messages as Markdown files for future recall.
/// Reference: openclacky/lib/clacky/agent/message_compressor_helper.rb (save_compressed_chunk, build_chunk_md)

///|

// ── Content Helpers ──────────────────────────────────────────────────────────

///|
/// Extract plain text from a MessageContent value.
pub fn content_to_text(content : @message.MessageContent) -> String {
  match content {
    @message.Text(s) => s
    @message.Blocks(blocks) => {
      let parts : Array[String] = []
      for block in blocks {
        match block {
          @message.Text(tb) => parts.push(tb.text)
          @message.Image(ib) => parts.push("[Image: \{ib.url}]")
        }
      }
      parts.join("\n")
    }
  }
}

///|
/// Format message content for chunk Markdown output.
pub fn format_chunk_message_content(
  content : @message.MessageContent,
) -> String {
  let text = content_to_text(content)
  truncate_chunk_content(text, 500)
}

///|
/// Truncate text to a maximum length, appending a note if truncated.
pub fn truncate_chunk_content(text : String, max_length : Int) -> String {
  let len = text.length()
  if len <= max_length {
    text
  } else {
    let prefix = text[0:max_length].to_owned()
    prefix + "\n... [truncated, \{len} chars total]"
  }
}

// ── Index Padding ────────────────────────────────────────────────────────────

///|
/// Pad a chunk index to 4 digits (e.g. 1 -> "0001", 42 -> "0042").
pub fn pad_chunk_index(n : Int) -> String {
  let s = n.to_string()
  let len = s.length()
  if len >= 4 {
    s
  } else if len == 3 {
    "0" + s
  } else if len == 2 {
    "00" + s
  } else if len == 1 {
    "000" + s
  } else {
    "0000"
  }
}

// ── Chunk MD Builder ─────────────────────────────────────────────────────────

///|
/// Build Markdown content from messages being archived into a chunk.
///
/// The output includes front-matter metadata (chunk index, message count,
/// topics) and each message formatted with role headers and content.
pub fn build_chunk_md(
  messages : Array[@message.Message],
  chunk_index : Int,
  topics~ : String? = None,
) -> String {
  let lines : Array[String] = []

  // Front matter
  lines.push("---")
  lines.push("chunk: \{chunk_index}")
  lines.push("archived_at: \{current_timestamp_iso()}")
  lines.push("message_count: \{messages.length()}")
  match topics {
    Some(t) if !t.is_empty() => lines.push("topics: \{t}")
    _ => ()
  }
  lines.push("---")
  lines.push("")
  lines.push("# Session Chunk \{chunk_index}")
  lines.push("")
  lines.push(
    "> This file contains the original conversation archived during compression.",
  )
  lines.push(
    "> Use `file_reader` to recall specific details from this conversation.",
  )
  lines.push("")

  // Messages
  for msg in messages {
    match msg.role {
      @message.User => {
        if msg.system_injected == Some(true) {
          lines.push("## User [system-injected]")
        } else {
          lines.push("## User")
        }
        lines.push("")
        lines.push(format_chunk_message_content(msg.content))
        lines.push("")
      }
      @message.Assistant => {
        if msg.compressed_summary is Some(_) {
          lines.push("## Assistant [Compressed Summary]")
        } else {
          lines.push("## Assistant")
        }
        lines.push("")
        // Tool calls summary
        match msg.tool_calls {
          Some(calls) if calls.length() > 0 => {
            let tc_parts : Array[String] = []
            for tc in calls {
              let name = tc.function.name
              let args = tc.function.arguments
              if args.length() > 0 && args != "{}" {
                tc_parts.push("\{name} | \{args}")
              } else {
                tc_parts.push(name)
              }
            }
            lines.push("_Tool calls: \{tc_parts.join("; ")}_")
            lines.push("")
          }
          _ => ()
        }
        let text = content_to_text(msg.content)
        if !text.is_empty() {
          lines.push(format_chunk_message_content(msg.content))
          lines.push("")
        }
      }
      @message.Tool => {
        let tool_name = match msg.name {
          Some(n) => n
          None => "tool"
        }
        lines.push("### Tool Result: \{tool_name}")
        lines.push("")
        lines.push("```")
        lines.push(format_chunk_message_content(msg.content))
        lines.push("```")
        lines.push("")
      }
      @message.System => {
        lines.push("## System")
        lines.push("")
        lines.push(format_chunk_message_content(msg.content))
        lines.push("")
      }
    }
  }

  lines.join("\n")
}

// ── Chunk MD Parsing (for merge) ─────────────────────────────────────────────

///|
/// Read a chunk file from disk. Returns None if the file doesn't exist or
/// can't be read.
pub fn read_chunk(chunk_path : String) -> String? {
  if !@fs.path_exists(chunk_path) {
    return None
  }
  let content = @fs.read_file_to_string(chunk_path) catch { _ => return None }
  Some(content)
}

///|
/// Split raw chunk Markdown into front-matter key-value pairs and body.
/// Returns None if there is no leading `---` block.
/// Front-matter is returned as an array of (key, value) pairs preserving
/// insertion order.
pub fn split_chunk_md(raw : String) -> (Array[(String, String)], String)? {
  if !raw.has_prefix("---") {
    return None
  }
  let end_marker = "\n---\n"
  // Find end marker position manually
  let mut fm_end : Int = -1
  let marker_len = end_marker.length()
  let raw_len = raw.length()
  if raw_len >= marker_len + 4 {
    let mut i = 4
    while i <= raw_len - marker_len {
      if raw[i:i + marker_len].to_owned() == end_marker {
        fm_end = i
        break
      }
      i = i + 1
    }
  }
  if fm_end < 0 {
    return None
  }
  let fm_text = raw[4:fm_end].to_owned()
  let body = if fm_end + marker_len < raw_len {
    raw[fm_end + marker_len:].to_owned()
  } else {
    ""
  }
  let pairs : Array[(String, String)] = []
  for line in fm_text.split("\n") {
    let line_str = line.to_owned()
    // Find first colon
    let mut colon_pos : Int = -1
    let mut j = 0
    while j < line_str.length() {
      if line_str[j:j + 1].to_owned() == ":" {
        colon_pos = j
        break
      }
      j = j + 1
    }
    match colon_pos {
      -1 => ()
      _ => {
        let key = line_str[:colon_pos].to_owned().trim().to_owned()
        let value = if colon_pos + 1 < line_str.length() {
          line_str[colon_pos + 1:].to_owned().trim().to_owned()
        } else {
          ""
        }
        if !key.is_empty() {
          pairs.push((key, value))
        }
      }
    }
  }
  Some((pairs, body))
}

///|
/// Render message sections for appending to an existing chunk during merge.
/// Same format as `build_chunk_md` message rendering but without the
/// front-matter and header boilerplate.
pub fn render_message_sections(messages : Array[@message.Message]) -> String {
  let lines : Array[String] = []
  for msg in messages {
    match msg.role {
      @message.User => {
        if msg.system_injected == Some(true) {
          lines.push("## User [system-injected]")
        } else {
          lines.push("## User")
        }
        lines.push("")
        lines.push(format_chunk_message_content(msg.content))
        lines.push("")
      }
      @message.Assistant => {
        if msg.compressed_summary is Some(_) {
          lines.push("## Assistant [Compressed Summary]")
        } else {
          lines.push("## Assistant")
        }
        lines.push("")
        match msg.tool_calls {
          Some(calls) if calls.length() > 0 => {
            let tc_parts : Array[String] = []
            for tc in calls {
              let name = tc.function.name
              let args = tc.function.arguments
              if args.length() > 0 && args != "{}" {
                tc_parts.push("\{name} | \{args}")
              } else {
                tc_parts.push(name)
              }
            }
            lines.push("_Tool calls: \{tc_parts.join("; ")}_")
            lines.push("")
          }
          _ => ()
        }
        let text = content_to_text(msg.content)
        if !text.is_empty() {
          lines.push(format_chunk_message_content(msg.content))
          lines.push("")
        }
      }
      @message.Tool => {
        let tool_name = match msg.name {
          Some(n) => n
          None => "tool"
        }
        lines.push("### Tool Result: \{tool_name}")
        lines.push("")
        lines.push("```")
        lines.push(format_chunk_message_content(msg.content))
        lines.push("```")
        lines.push("")
      }
      @message.System => ()
    }
  }
  lines.join("\n")
}

///|
/// Union two comma-separated topic strings, preserving order, dropping dups.
fn merge_topics(existing : String?, incoming : String?) -> String? {
  let a_parts : Array[String] = []
  match existing {
    Some(s) if !s.is_empty() =>
      for part in s.split(",") {
        let trimmed = part.trim().to_owned()
        if !trimmed.is_empty() {
          a_parts.push(trimmed)
        }
      }
    _ => ()
  }
  let b_parts : Array[String] = []
  match incoming {
    Some(s) if !s.is_empty() =>
      for part in s.split(",") {
        let trimmed = part.trim().to_owned()
        if !trimmed.is_empty() {
          b_parts.push(trimmed)
        }
      }
    _ => ()
  }
  let merged : Array[String] = []
  for p in a_parts {
    let mut found = false
    for m in merged {
      if m == p {
        found = true
        break
      }
    }
    if !found {
      merged.push(p)
    }
  }
  for p in b_parts {
    let mut found = false
    for m in merged {
      if m == p {
        found = true
        break
      }
    }
    if !found {
      merged.push(p)
    }
  }
  if merged.is_empty() {
    None
  } else {
    Some(merged.join(", "))
  }
}

///|
/// Merge new messages into an existing chunk file, updating frontmatter.
/// Returns the chunk path on success, None on failure (caller should fall
/// back to creating a new chunk).
///
/// Reference: Ruby `merge_into_previous_chunk` in
/// `message_compressor_helper.rb:542-577`.
pub fn merge_into_previous_chunk(
  prev_chunk_path : String,
  prev_chunk_index : Int,
  messages : Array[@message.Message],
  compression_level : Int,
  session_id : String,
  created_at : String,
  topics~ : String? = None,
) -> String? {
  // Filter messages: skip system, system-injected, compressed summaries
  let to_archive : Array[@message.Message] = []
  for msg in messages {
    if msg.role != @message.System &&
      msg.system_injected != Some(true) &&
      msg.compressed_summary is None {
      to_archive.push(msg)
    }
  }
  if to_archive.is_empty() {
    return None
  }

  let raw = match read_chunk(prev_chunk_path) {
    None => return None
    Some(r) => r
  }
  let (fm_pairs, body) = match split_chunk_md(raw) {
    None => return None
    Some(v) => v
  }

  let new_sections = render_message_sections(to_archive)

  // Parse existing frontmatter values for updating
  let mut old_message_count = 0
  let mut old_merged_count = 1
  let mut old_topics : String? = None
  for (k, v) in fm_pairs {
    match k {
      "message_count" => old_message_count = parse_int_safe(v)
      "merged_count" => old_merged_count = parse_int_safe(v)
      "topics" => old_topics = Some(v)
      _ => ()
    }
  }

  let new_message_count = old_message_count + to_archive.length()
  let new_merged_count = old_merged_count + 1
  let merged_topics = merge_topics(old_topics, topics)

  // Rebuild frontmatter preserving original key order, updating changed fields
  let lines : Array[String] = ["---"]
  for (k, v) in fm_pairs {
    match k {
      "compression_level" =>
        lines.push("compression_level: \{compression_level}")
      "archived_at" => lines.push("archived_at: \{current_timestamp_iso()}")
      "message_count" => lines.push("message_count: \{new_message_count}")
      "merged_count" => lines.push("merged_count: \{new_merged_count}")
      "topics" =>
        match merged_topics {
          Some(t) => lines.push("topics: \{t}")
          None => ()
        }
      _ => lines.push("\{k}: \{v}")
    }
  }
  lines.push("---")
  lines.push(body.trim_end().to_owned())
  lines.push("")
  lines.push(new_sections)

  let content = lines.join("\n")
  match write_chunk(session_id, created_at, prev_chunk_index, content) {
    Ok(path) => Some(path)
    Err(_) => None
  }
}

///|
/// Parse a string as Int, returning 0 on failure.
fn parse_int_safe(s : String) -> Int {
  let mut result = 0
  let mut negative = false
  let mut started = false
  for c in s {
    if c == '-' && !started {
      negative = true
      started = true
    } else if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - '0'.to_int())
      started = true
    } else {
      break
    }
  }
  if negative {
    -result
  } else {
    result
  }
}

// ── Save Chunk to Disk ───────────────────────────────────────────────────────

///|
/// Save messages being compressed to a chunk MD file for future recall.
///
/// Uses the SessionManager's `write_chunk` for filesystem operations.
/// Returns the absolute path of the saved chunk file on success.
pub fn save_compressed_chunk(
  messages : Array[@message.Message],
  session_id : String,
  created_at : String,
  chunk_index : Int,
  topics~ : String? = None,
) -> Result[String, String] {
  // Filter out system messages, system-injected scaffolding, and previous
  // compressed summaries — these should not be archived inside a new chunk.
  let to_archive : Array[@message.Message] = []
  for msg in messages {
    if msg.role != @message.System &&
      msg.system_injected != Some(true) &&
      msg.compressed_summary is None {
      to_archive.push(msg)
    }
  }

  if to_archive.length() == 0 {
    return Err("No messages to archive")
  }

  let md_content = build_chunk_md(to_archive, chunk_index, topics~)
  write_chunk(session_id, created_at, chunk_index, md_content)
}

///|
/// Save or merge compressed messages into a chunk file.
///
/// Mirrors Ruby `message_compressor_helper.rb:269-302`: when existing chunks
/// are present, attempts to merge into the latest chunk (updating frontmatter);
/// if merge fails or no chunks exist, creates a new chunk with a disk-derived
/// index via `next_chunk_index`. This prevents overwriting existing chunks
/// after process restarts (BUG-0082).
///
/// Returns the chunk path on success.
pub fn save_or_merge_chunk(
  messages : Array[@message.Message],
  session_id : String,
  created_at : String,
  compression_level : Int,
  topics~ : String? = None,
) -> Result[String, String] {
  let existing = chunks_for_current(session_id, created_at)
  if existing.length() > 0 {
    let latest_path = existing[existing.length() - 1]
    // Extract index from the latest chunk filename
    let latest_index = extract_chunk_index_from_path(latest_path)
    match latest_index {
      Some(idx) =>
        match
          merge_into_previous_chunk(
            latest_path,
            idx,
            messages,
            compression_level,
            session_id,
            created_at,
            topics~,
          ) {
          Some(path) => return Ok(path)
          None => ()
        }
      None => ()
    }
  }
  // Fallback: create new chunk with disk-derived index
  let next_idx = next_chunk_index(session_id, created_at)
  save_compressed_chunk(messages, session_id, created_at, next_idx, topics~)
}

///|
/// Extract chunk index from a file path like `...-chunk-3.md`.
fn extract_chunk_index_from_path(path : String) -> Int? {
  let suffix = ".md"
  let marker = "-chunk-"
  if !path.has_suffix(suffix) {
    return None
  }
  let base = path[:path.length() - suffix.length()].to_owned()
  let marker_pos = base.last_index_of(marker)
  match marker_pos {
    None => None
    Some(idx) => {
      let idx_str = base[idx + marker.length():].to_owned()
      let n = parse_int_safe(idx_str)
      if n > 0 {
        Some(n)
      } else {
        None
      }
    }
  }
}

///|
/// Find the last occurrence of `needle` in `haystack`. Returns None if not found.
fn String::last_index_of(self : String, needle : String) -> Int? {
  let n_len = needle.length()
  let s_len = self.length()
  if n_len == 0 || n_len > s_len {
    return None
  }
  let mut i = s_len - n_len
  while i >= 0 {
    if self[i:i + n_len].to_owned() == needle {
      return Some(i)
    }
    if i == 0 {
      break
    }
    i = i - 1
  }
  None
}
