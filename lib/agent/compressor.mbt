///| Message compression system using Insert-then-Compress strategy.

///| Instead of a separate API call, we insert a compression instruction into the

///| conversation flow, reusing the existing cache (system prompt + tools).

///| Reference: openclacky/lib/clacky/agent/message_compressor.rb

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

// ── Compression Prompt ────────────────────────────────────────────────────────

///|
/// The prompt text inserted into the conversation to instruct the LLM
/// to compress the preceding history.
let compression_prompt : String =
  #|═════════════════════════════════════════════════════════════
  #|CRITICAL: TASK CHANGE - MEMORY COMPRESSION MODE
  #|═════════════════════════════════════════════════════════════
  #|The conversation above has ENDED. You are now in MEMORY COMPRESSION MODE.
  #|
  #|CRITICAL INSTRUCTIONS - READ CAREFULLY:
  #|
  #|1. This is NOT a continuation of the conversation
  #|2. DO NOT respond to any requests in the conversation above
  #|3. DO NOT call ANY tools or functions
  #|4. DO NOT use tool_calls in your response
  #|5. Your response MUST be PURE TEXT ONLY
  #|
  #|YOUR ONLY TASK: Create a comprehensive summary of the conversation above.
  #|
  #|REQUIRED RESPONSE FORMAT:
  #|First output a <topics> line listing 3-6 key topic phrases (comma-separated, concise).
  #|Then output the full summary wrapped in <summary> tags.
  #|
  #|Example format:
  #|<topics>Rails setup, database config, deploy pipeline, Tailwind CSS</topics>
  #|<summary>
  #|...full summary text...
  #|</summary>
  #|
  #|Focus on:
  #|- User's explicit requests and intents
  #|- Key technical concepts and code changes
  #|- Files examined and modified
  #|- Errors encountered and fixes applied
  #|- Current work status and pending tasks
  #|
  #|Begin your response NOW. Remember: PURE TEXT only, starting with <topics> then <summary>.

// ── CompressionConfig ─────────────────────────────────────────────────────────

///|
/// Configuration for the compression system.
pub(all) struct CompressionConfig {
  max_recent_messages : Int
  target_compressed_tokens : Int
  idle_compression_threshold : Int
} derive(Eq, Debug)

///|
pub extend CompressionConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CompressionConfig with Eq::{not_equal, equal}

///|
/// Create a default compression configuration.
pub fn CompressionConfig::default() -> CompressionConfig {
  {
    max_recent_messages: 20,
    target_compressed_tokens: 10_000,
    idle_compression_threshold: 20_000,
  }
}

// ── CompressedSummary ─────────────────────────────────────────────────────────

///|
/// Record of a single compression operation for tracking history.
pub(all) struct CompressedSummary {
  timestamp : String
  original_count : Int
  compressed_count : Int
  token_savings : Double
} derive(Eq, Debug)

///|
pub extend CompressedSummary with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CompressedSummary with Eq::{not_equal, equal}

// ── CompressionContext ────────────────────────────────────────────────────────

///|
/// Context captured when compression is triggered.
pub(all) struct CompressionContext {
  original_token_count : Int
  original_message_count : Int
  compression_level : Int
  recent_message_count : Int
  chunk_path : String?
  previous_chunks : Array[String]
  compression_history : Array[CompressedSummary]
} derive(Eq, Debug)

///|
pub extend CompressionContext with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CompressionContext with Eq::{not_equal, equal}

// ── ParsedCompression ─────────────────────────────────────────────────────────

///|
/// Result of parsing an LLM compression response.
pub(all) struct ParsedCompression {
  topics : String
  summary : String
} derive(Eq, Debug)

///|
pub extend ParsedCompression with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ParsedCompression with Eq::{not_equal, equal}

// ── Core Detection Functions ──────────────────────────────────────────────────

///|
/// Check whether the conversation history needs compression.
///
/// Returns true if estimated tokens exceed compression_threshold
/// or message count exceeds message_count_threshold.
///
/// Aligns with Ruby's `needs_compression` in `message_compressor_helper.rb`:
/// when triggered by token threshold, additionally checks that the
/// reduction needed is at least 10% of current size; otherwise skips.
pub fn Agent::needs_compression(self : Agent) -> Bool {
  // Ruby: total_tokens = [@previous_total_tokens, @history.estimate_tokens].max
  // (message_compressor_helper.rb:143)。API 报告的上一轮 token 数与当前估算取
  // 大，覆盖"最后一个大 tool_result 刚追加、上一轮 usage 尚未反映"的场景
  // （BUG-0042 差异一）。
  let token_count = self.previous_total_tokens.max(
    estimate_history_tokens(self.history),
  )
  let msg_count = self.history.length()
  let token_threshold_exceeded = token_count >=
    self.config.compression_threshold
  let message_count_exceeded = msg_count >= message_count_threshold
  if !token_threshold_exceeded && !message_count_exceeded {
    return false
  }
  // Ruby: skip compression if reduction is minimal (< 10% of current size)
  // Only applies when triggered by token threshold (not force mode)
  if token_threshold_exceeded {
    let reduction_needed = token_count - target_compressed_tokens
    if reduction_needed.to_double() < token_count.to_double() * 0.1 {
      return false
    }
  }
  true
}

///|
/// Detect if compression is needed and prepare context.
///
/// Returns Some(CompressionContext) when thresholds are exceeded.
/// Returns None if no compression needed.
pub fn Agent::compress_messages_if_needed(
  self : Agent,
  force : Bool,
) -> CompressionContext? {
  if !force && !self.needs_compression() {
    return None
  }
  let token_count = estimate_history_tokens(self.history)
  let msg_count = self.history.length()
  let config = CompressionConfig::default()
  let recent = if msg_count < config.max_recent_messages {
    msg_count
  } else {
    config.max_recent_messages
  }
  // Ruby: if nothing to compress (all non-system messages are recent), skip.
  // build_compression_message returns nil when messages_to_compress is empty.
  // In MB, this happens when recent >= msg_count - 1 (excluding system message).
  let non_system_count = {
    let mut n = 0
    for msg in self.history {
      if msg.role != @message.System {
        n = n + 1
      }
    }
    n
  }
  if recent >= non_system_count {
    // Ruby 无此守卫；等价逻辑是 build_compression_message 在 messages_to_compress
    // 为空时返回 nil。但 Ruby 的 get_recent_messages_with_tool_pairs 会对 content
    // > 2000 字符的 tool_result 执行 truncate_tool_result（返回新 Hash，helper.rb
    // :472-478），使原始大 tool_result 因对象相等性失配落入待压缩集 → 压缩指令
    // 仍会生成（BUG-0042 差异二）。MB 显式模拟该可观测结果：存在超大 tool_result
    // 时继续压缩流程，否则才返回 None。
    let has_oversized_tool_result = {
      let mut found = false
      for msg in self.history {
        if msg.role == @message.Tool {
          match msg.content {
            @message.Text(s) if s.length() > 2000 => {
              found = true
              break
            }
            _ => ()
          }
        }
      }
      found
    }
    if !has_oversized_tool_result {
      return None
    }
  }
  Some({
    original_token_count: token_count,
    original_message_count: msg_count,
    compression_level: self.compression_level,
    recent_message_count: recent,
    chunk_path: None,
    previous_chunks: [],
    compression_history: [],
  })
}

// ── Insert-then-Compress Functions ────────────────────────────────────────────

///|
/// Build the compression instruction message to be inserted into the conversation.
/// This allows the LLM to use existing cache (system prompt + tools) for compression.
pub fn build_compression_message() -> @message.Message {
  {
    role: @message.User,
    content: @message.Text(compression_prompt),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    reasoning_content: None,
    task_id: None,
    created_at: None,
    system_injected: Some(true),
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
}

///|
/// Parse LLM response for compression: extract <topics> and <summary> tags.
pub fn parse_compression_response(
  content : String,
) -> Result[ParsedCompression, String] {
  let topics = extract_xml_content(content, "topics")
  let summary = extract_xml_content(content, "summary")
  match (topics, summary) {
    (Some(t), Some(s)) => Ok({ topics: t, summary: s })
    (None, Some(s)) =>
      // Topics missing but summary present - use empty topics
      Ok({ topics: "", summary: s })
    (_, None) =>
      Err("Failed to parse compression response: missing <summary> tag")
  }
}

///|
/// Rebuild message history after compression.
/// Result: [system_message] + [compressed_summary_as_user] + [recent_messages]
pub fn rebuild_history_with_compression(
  original_messages : Array[@message.Message],
  compressed_summary : String,
  topics : String,
  recent_count : Int,
) -> Array[@message.Message] {
  let result : Array[@message.Message] = []
  // 1. Find and preserve system message
  for msg in original_messages {
    if msg.role == @message.System {
      result.push(msg)
      break
    }
  }
  // 2. Add compressed summary as a user message (system_injected)
  let summary_msg = build_compressed_summary_message(compressed_summary, topics)
  result.push(summary_msg)
  // 3. Add recent messages (tool pairs preserved, oversized tool results truncated)
  let recent = get_recent_with_tool_pairs(original_messages, recent_count)
  for msg in recent {
    // Skip system messages in recent (already added)
    if msg.role != @message.System {
      // Truncate oversized tool result content to prevent token bloat
      // (Ruby: get_recent_messages_with_tool_pairs → truncate_tool_result).
      let truncated_msg = if msg.role == @message.Tool {
        match msg.content {
          @message.Text(content) if content.length() > 2000 => {
            let truncated = truncate_tool_result(content)
            { ..msg, content: @message.Text(truncated) }
          }
          _ => msg
        }
      } else {
        msg
      }
      result.push(truncated_msg)
    }
  }
  result
}

///|
/// Get the most recent N messages, ensuring tool_call/tool_result pairs stay together.
/// If a message has tool_calls, include all following tool result messages too.
pub fn get_recent_with_tool_pairs(
  messages : Array[@message.Message],
  count : Int,
) -> Array[@message.Message] {
  let len = messages.length()
  if len == 0 || count <= 0 {
    return []
  }
  // Filter out system messages for slicing
  let non_system : Array[@message.Message] = []
  for msg in messages {
    if msg.role != @message.System {
      non_system.push(msg)
    }
  }
  let ns_len = non_system.length()
  if ns_len <= count {
    return non_system
  }
  // Start from the candidate cut point
  let mut start = ns_len - count
  // Walk backwards to avoid splitting a tool_call from its tool_results:
  // If the message at `start` is a Tool message, its parent tool_call is before it,
  // so include that parent too.
  while start > 0 && non_system[start].role == @message.Tool {
    start = start - 1
  }
  let result : Array[@message.Message] = []
  for i = start; i < ns_len; i = i + 1 {
    result.push(non_system[i])
  }
  result
}

// ── Token Estimation ──────────────────────────────────────────────────────────

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
  let mut tokens = 0
  match msg.content {
    @message.Text(s) => tokens = tokens + estimate_token_count(s)
    @message.Blocks(blocks) =>
      for block in blocks {
        match block {
          @message.Text(tb) => tokens = tokens + estimate_token_count(tb.text)
          // Image blocks carry no text field; Ruby counts them as 0
          @message.Image(_) => ()
        }
      }
  }
  // Tool calls: only the function name and arguments contribute tokens
  match msg.tool_calls {
    Some(calls) =>
      for tc in calls {
        tokens = tokens + estimate_token_count(tc.function.name)
        tokens = tokens + estimate_token_count(tc.function.arguments)
      }
    None => ()
  }
  tokens
}

// ── Dynamic Recent Count ─────────────────────────────────────────────────────

///|
/// Calculate the target number of recent messages to preserve after compression.
///
/// Matches Ruby `calculate_target_recent_count` (message_compressor_helper.rb):
/// recent messages get ~20% of the target compressed token budget at
/// ~500 tokens per message, clamped to [20, max_recent_messages].
/// Under current constants (target_compressed_tokens=10_000) the result is
/// always 20 regardless of `reduction_needed`; the parameter is kept for
/// API parity with Ruby.
pub fn calculate_target_recent_count(reduction_needed : Int) -> Int {
  let _ = reduction_needed // kept for API parity with Ruby; unused under constants
  let tokens_per_message = 500 // Average estimate for a message with content
  // Target recent messages budget (~20% of target compressed size)
  let recent_budget = (target_compressed_tokens.to_double() * 0.2).to_int()
  let target_messages = recent_budget / tokens_per_message
  // Clamp to reasonable bounds
  target_messages.max(20).min(max_recent_messages)
}

// ── Compression Skip Logic ───────────────────────────────────────────────────

///|
/// Check if compression should be skipped based on the last reduction percentage.
///
/// If the last compression achieved less than 10% reduction, it's not
/// worth compressing again yet — the conversation hasn't grown enough.
pub fn should_skip_compression(last_reduction_pct : Double) -> Bool {
  last_reduction_pct < 0.1
}

// ── Overflow Recovery ────────────────────────────────────────────────────────

///|
/// Pop messages from the tail until total tokens are within `max_tokens`.
///
/// Returns (kept_messages, pulled_back_messages).
/// Ensures tool_call/tool_result pair integrity: if a tool_result is kept,
/// its parent assistant message with tool_calls is also kept.
pub fn pulled_back_messages(
  messages : Array[@message.Message],
  max_tokens : Int,
) -> (Array[@message.Message], Array[@message.Message]) {
  let total = messages.length()
  let kept : Array[@message.Message] = []
  for msg in messages {
    kept.push(msg)
  }

  let mut total_tokens = estimate_history_tokens(kept)

  // Pop from tail until within budget
  while total_tokens > max_tokens && kept.length() > 1 {
    let msg = kept[kept.length() - 1]
    let msg_tokens = message_token_estimate(msg)
    let _ = kept.pop()
    total_tokens = total_tokens - msg_tokens
  }

  // Fix tool pair integrity: if a kept Tool message references an assistant
  // tool_call that is no longer in kept, move that assistant to pulled too.
  let kept_ids : Map[String, Bool] = Map([])
  for msg in kept {
    if msg.role == @message.Assistant {
      match msg.tool_calls {
        Some(calls) =>
          for call in calls {
            kept_ids[call.id] = true
          }
        None => ()
      }
    }
  }
  // Remove orphan tool results from kept (Tool messages whose call_id isn't in kept)
  let clean_kept : Array[@message.Message] = []
  for msg in kept {
    if msg.role == @message.Tool {
      match msg.tool_call_id {
        Some(tc_id) =>
          if kept_ids.get(tc_id) is Some(_) {
            clean_kept.push(msg)
          }
        None => clean_kept.push(msg)
      }
    } else {
      clean_kept.push(msg)
    }
  }

  // Build pulled: messages not in clean_kept (in original order)
  let kept_len = clean_kept.length()
  let pulled : Array[@message.Message] = []
  for i = kept_len; i < total; i = i + 1 {
    pulled.push(messages[i])
  }
  // Also add any orphaned tool results that were removed from kept
  // (they may be at indices < kept_len)
  if clean_kept.length() < kept.length() {
    // Some messages were removed from middle of kept; rebuild pulled
    while pulled.length() > 0 {
      let _ = pulled.pop()
    }
    // Simple approach: messages in original but not in clean_kept
    let kept_set : Map[Int, Bool] = Map([])
    let mut ki = 0
    for msg in clean_kept {
      // Find msg in original messages
      for j = 0; j < total; j = j + 1 {
        if messages[j] == msg && kept_set.get(j) is None {
          kept_set[j] = true
          break
        }
      }
      let _ = ki
      ki = ki + 1
    }
    for j = 0; j < total; j = j + 1 {
      if kept_set.get(j) is None {
        pulled.push(messages[j])
      }
    }
  }

  (clean_kept, pulled)
}
