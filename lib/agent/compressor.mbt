///| Message compression threshold detection for Agent sessions.

///| Phase 4 implements detection only; actual LLM-driven compression

///| requires async HTTP (Phase 5+).

///| Reference: openclacky/lib/clacky/agent/message_compressor_helper.rb

///|

///|
/// Token threshold that triggers message compression.
pub let compression_threshold : Int = 150_000

///|
/// Message count threshold that triggers compression.
pub let message_count_threshold : Int = 200

///|
/// Maximum number of recent messages to preserve after compression.
pub let max_recent_messages : Int = 20

///|
/// Target token count for the compressed summary.
pub let target_compressed_tokens : Int = 10_000

///|
/// Context captured when compression is triggered.
pub(all) struct CompressionContext {
  original_token_count : Int
  original_message_count : Int
  compression_level : Int
  recent_message_count : Int
} derive(Eq, Debug)

///|
/// Check whether the conversation history needs compression.
///
/// Returns true if estimated tokens exceed compression_threshold
/// or message count exceeds message_count_threshold.
pub fn Agent::needs_compression(self : Agent) -> Bool {
  let token_count = estimate_history_tokens(self.history)
  let msg_count = self.history.length()
  token_count >= compression_threshold || msg_count >= message_count_threshold
}

///|
/// Detect if compression is needed and prepare context.
///
/// Phase 4 stub: returns Some(CompressionContext) when thresholds
/// are exceeded but does not perform actual compression (requires
/// LLM call via async HTTP). Returns None if no compression needed.
pub fn Agent::compress_messages_if_needed(
  self : Agent,
  force : Bool,
) -> CompressionContext? {
  if !force && !self.needs_compression() {
    return None
  }
  let token_count = estimate_history_tokens(self.history)
  let msg_count = self.history.length()
  let recent = if msg_count < max_recent_messages {
    msg_count
  } else {
    max_recent_messages
  }
  Some({
    original_token_count: token_count,
    original_message_count: msg_count,
    compression_level: self.compression_level,
    recent_message_count: recent,
  })
}

///|
/// Estimate the total token count across all messages in history.
pub fn estimate_history_tokens(history : Array[@message.Message]) -> Int {
  let mut total = 0
  for msg in history {
    total = total + message_token_estimate(msg)
  }
  total
}

///|
/// Estimate token count for a single message.
fn message_token_estimate(msg : @message.Message) -> Int {
  let content_tokens = match msg.content {
    @message.Text(s) => estimate_token_count(s)
    @message.Blocks(blocks) => {
      let mut t = 0
      for block in blocks {
        match block {
          @message.Text(tb) => t = t + estimate_token_count(tb.text)
          @message.Image(_) => t = t + 100 // rough image token estimate
        }
      }
      t
    }
  }
  // Add overhead for tool_calls JSON
  let tc_tokens = match msg.tool_calls {
    Some(calls) => calls.length() * 50 // rough per-call overhead
    None => 0
  }
  content_tokens + tc_tokens
}
