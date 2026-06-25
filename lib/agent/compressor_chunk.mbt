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
  topics? : String? = None,
) -> String {
  let lines : Array[String] = []

  // Front matter
  lines.push("---")
  lines.push("chunk: \{chunk_index}")
  lines.push("archived_at: \{current_timestamp_ms()}")
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

// ── Save Chunk to Disk ───────────────────────────────────────────────────────

///|
/// Save messages being compressed to a chunk MD file for future recall.
///
/// Uses the SessionManager's `write_chunk` for filesystem operations.
/// Returns the absolute path of the saved chunk file on success.
pub fn save_compressed_chunk(
  messages : Array[@message.Message],
  session_id : String,
  chunk_index : Int,
  topics? : String? = None,
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
  write_chunk(session_id, chunk_index, md_content)
}
