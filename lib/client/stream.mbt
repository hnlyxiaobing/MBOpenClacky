///| SSE (Server-Sent Events) frame parser and stream aggregators.

///|

///| Provides generic SSE frame extraction and two protocol-specific

///| aggregators that reassemble streaming chunks into LlmResponse.

///|
/// A single parsed SSE frame with event type and data payload.
pub(all) struct SseFrame {
  event : String
  data : String
} derive(Eq, Debug)

///|
/// Callback trait for streaming progress notifications.
pub(open) trait StreamCallback {
  ///| Called when new token usage information is available.
  fn on_chunk(Self, input_tokens : Int, output_tokens : Int) -> Unit
}

// ── SSE Frame Parser ────────────────────────────────────────────────────────

///|
/// Parse all complete SSE frames from a text string.
/// Returns the list of parsed frames (incomplete trailing data is discarded).
pub fn parse_sse_frames(text : String) -> Array[SseFrame] {
  let frames : Array[SseFrame] = []
  let mut pos = 0
  let len = text.length()
  while pos < len {
    let rest = text[pos:].to_string()
    match rest.find("\n\n") {
      Some(sep_offset) => {
        let frame_text = text[pos:pos + sep_offset].to_string()
        pos = pos + sep_offset + 2
        match parse_single_frame(frame_text) {
          Some(frame) => frames.push(frame)
          None => ()
        }
      }
      None => break
    }
  }
  frames
}

///|
/// Parse a single SSE frame from text (between two \n\n separators).
/// Returns None if the frame has no data lines.
fn parse_single_frame(frame_text : String) -> SseFrame? {
  let mut event : String? = None
  let data_parts : Array[String] = []
  let mut has_data = false
  let mut pos = 0
  let len = frame_text.length()

  while pos < len {
    let rest = frame_text[pos:].to_string()
    let line_end = match rest.find("\n") {
      Some(offset) => pos + offset
      None => len
    }
    let line = frame_text[pos:line_end].to_string()
    pos = if line_end < len { line_end + 1 } else { len }

    if is_line_prefix(line, "event:") {
      event = Some(strip_sse_field(line, "event:"))
    } else if is_line_prefix(line, "data:") {
      data_parts.push(strip_sse_field(line, "data:"))
      has_data = true
    }
  }

  guard has_data else { return None }
  let data = join_str_array(data_parts, "\n")
  let evt = match event {
    Some(e) => e
    None => "message"
  }
  Some({ event: evt, data })
}

///|
/// Check if a line starts with the given prefix.
fn is_line_prefix(line : String, prefix : String) -> Bool {
  line.length() >= prefix.length() &&
  line[:prefix.length()].to_string() == prefix
}

///|
/// Strip an SSE field prefix and optional leading space.
fn strip_sse_field(line : String, prefix : String) -> String {
  let rest = line[prefix.length():].to_string()
  if rest.length() > 0 && rest[:1].to_string() == " " {
    rest[1:].to_string()
  } else {
    rest
  }
}

// ── OpenAI Stream Aggregator ────────────────────────────────────────────────

///|
/// Internal accumulator for a single OpenAI streaming tool call.
struct OpenAiToolCallAcc {
  mut id : String?
  mut type_ : String?
  mut name : String?
  mut arguments : String
}

///|
/// Reassembles an OpenAI-compatible chat-completion SSE stream into
/// a non-streaming LlmResponse. Mirrors Ruby's OpenAIStreamAggregator.
pub(all) struct OpenAiStreamAggregator {
  mut content_parts : Array[String]
  mut content_len : Int
  mut tool_calls : Array[OpenAiToolCallAcc]
  mut finish_reason : String?
  mut usage : Usage?
  mut last_output_tokens : Int
}

///|
/// Create a new OpenAI stream aggregator.
pub fn OpenAiStreamAggregator::new() -> OpenAiStreamAggregator {
  {
    content_parts: [],
    content_len: 0,
    tool_calls: [],
    finish_reason: None,
    usage: None,
    last_output_tokens: 0,
  }
}

///|
/// Handle a single SSE data string from the OpenAI stream.
/// Ignores the "[DONE]" sentinel and unparseable JSON.
pub fn OpenAiStreamAggregator::handle(
  self : OpenAiStreamAggregator,
  data_str : String,
) -> Unit {
  guard data_str != "[DONE]" else { return }
  let json = @json.parse(data_str) catch { _ => return }

  // Process choice delta
  match (if json is Object(obj) { obj.get("choices") } else { None }) {
    Some(Array(choices)) if choices.length() > 0 => {
      let choice = choices[0]
      match (if choice is Object(obj) { obj.get("delta") } else { None }) {
        Some(delta) => {
          // Accumulate content
          match (if delta is Object(obj) { obj.get("content") } else { None }) {
            Some(String(text)) => {
              self.content_parts.push(text)
              self.content_len = self.content_len + text.length()
            }
            _ => ()
          }

          // Accumulate tool calls
          match
            (if delta is Object(obj) { obj.get("tool_calls") } else { None }) {
            Some(Array(tcs)) =>
              for tc in tcs {
                self.merge_tool_call(tc)
              }
            _ => ()
          }

          // Capture finish reason
          match
            (if choice is Object(obj) {
              obj.get("finish_reason")
            } else {
              None
            }) {
            Some(String(reason)) => self.finish_reason = Some(reason)
            _ => ()
          }
        }
        _ => ()
      }
    }
    _ => ()
  }

  // Process usage (emitted in final frame with stream_options.include_usage)
  match (if json is Object(obj) { obj.get("usage") } else { None }) {
    Some(u) => {
      let input_tokens = json_int(u, "prompt_tokens")
      let output_tokens = json_int(u, "completion_tokens")
      let cache_creation = json_int(u, "cache_creation_input_tokens")
      let cache_read = json_int(u, "cache_read_input_tokens")
      if input_tokens > 0 || output_tokens > 0 {
        self.usage = Some(
          Usage::from_openai(
            input_tokens,
            output_tokens,
            cache_creation~,
            cache_read~,
          ),
        )
      }
    }
    _ => ()
  }
}

///|
/// Convert accumulated stream data into a non-streaming LlmResponse.
pub fn OpenAiStreamAggregator::to_response(
  self : OpenAiStreamAggregator,
) -> LlmResponse {
  let content = join_str_array(self.content_parts, "")
  let content_val : String? = if content.length() > 0 {
    Some(content)
  } else {
    None
  }

  // Build tool calls
  let tool_calls : Array[@message.ToolCall]? = if self.tool_calls.length() > 0 {
    let arr : Array[@message.ToolCall] = []
    for acc in self.tool_calls {
      let id = match acc.id {
        Some(id) => id
        _ => ""
      }
      let name = match acc.name {
        Some(n) => n
        _ => ""
      }
      arr.push(@message.ToolCall::new(id, name, acc.arguments))
    }
    Some(arr)
  } else {
    None
  }

  {
    content: content_val,
    tool_calls,
    finish_reason: self.finish_reason,
    usage: self.usage,
    latency: None,
  }
}

///|
fn OpenAiStreamAggregator::merge_tool_call(
  self : OpenAiStreamAggregator,
  tc : Json,
) -> Unit {
  let idx = json_int(tc, "index")
  while self.tool_calls.length() <= idx {
    self.tool_calls.push({ id: None, type_: None, name: None, arguments: "" })
  }
  let acc = self.tool_calls[idx]

  // Merge id
  match (if tc is Object(obj) { obj.get("id") } else { None }) {
    Some(String(id)) => if acc.id is None { acc.id = Some(id) }
    _ => ()
  }

  // Merge type
  match (if tc is Object(obj) { obj.get("type") } else { None }) {
    Some(String(t)) => if acc.type_ is None { acc.type_ = Some(t) }
    _ => ()
  }

  // Merge function name and arguments
  match (if tc is Object(obj) { obj.get("function") } else { None }) {
    Some(Object(fn_obj)) => {
      match fn_obj.get("name") {
        Some(String(name)) => if acc.name is None { acc.name = Some(name) }
        _ => ()
      }
      match fn_obj.get("arguments") {
        Some(String(args)) => acc.arguments = acc.arguments + args
        _ => ()
      }
    }
    _ => ()
  }
}

// ── Anthropic Stream Aggregator ─────────────────────────────────────────────

///|
/// Kind of content block in an Anthropic stream.
priv enum AnthropicBlockKind {
  Text
  ToolUse
}

///|
/// Internal accumulator for a single Anthropic content block.
struct AnthropicBlockAcc {
  kind : AnthropicBlockKind
  text : String
  tool_id : String?
  tool_name : String?
  input_str : String
}

///|
/// Reassembles an Anthropic Messages SSE stream into a non-streaming
/// LlmResponse. Mirrors Ruby's AnthropicStreamAggregator.
pub(all) struct AnthropicStreamAggregator {
  mut blocks : Array[AnthropicBlockAcc]
  mut stop_reason : String?
  mut input_tokens : Int
  mut output_tokens : Int
  mut cache_creation : Int
  mut cache_read : Int
  mut last_output_tokens : Int
}

///|
/// Create a new Anthropic stream aggregator.
pub fn AnthropicStreamAggregator::new() -> AnthropicStreamAggregator {
  {
    blocks: [],
    stop_reason: None,
    input_tokens: 0,
    output_tokens: 0,
    cache_creation: 0,
    cache_read: 0,
    last_output_tokens: 0,
  }
}

///|
/// Handle a single SSE event+data pair from the Anthropic stream.
pub fn AnthropicStreamAggregator::handle(
  self : AnthropicStreamAggregator,
  event : String,
  data_str : String,
) -> Unit {
  let json = @json.parse(data_str) catch { _ => return }

  match event {
    "message_start" =>
      match (if json is Object(obj) { obj.get("message") } else { None }) {
        Some(msg) =>
          match (if msg is Object(obj) { obj.get("usage") } else { None }) {
            Some(u) => {
              self.input_tokens = self.input_tokens +
                json_int(u, "input_tokens")
              self.output_tokens = self.output_tokens +
                json_int(u, "output_tokens")
              self.cache_creation = self.cache_creation +
                json_int(u, "cache_creation_input_tokens")
              self.cache_read = self.cache_read +
                json_int(u, "cache_read_input_tokens")
            }
            _ => ()
          }
        _ => ()
      }
    "content_block_start" =>
      match
        (if json is Object(obj) { obj.get("content_block") } else { None }) {
        Some(cb) =>
          match (if cb is Object(obj) { obj.get("type") } else { None }) {
            Some(String("tool_use")) => {
              let id = match
                (if cb is Object(obj) { obj.get("id") } else { None }) {
                Some(String(s)) => Some(s)
                _ => None
              }
              let name = match
                (if cb is Object(obj) { obj.get("name") } else { None }) {
                Some(String(s)) => Some(s)
                _ => None
              }
              self.blocks.push({
                kind: ToolUse,
                text: "",
                tool_id: id,
                tool_name: name,
                input_str: "",
              })
            }
            _ =>
              self.blocks.push({
                kind: Text,
                text: "",
                tool_id: None,
                tool_name: None,
                input_str: "",
              })
          }
        _ => ()
      }
    "content_block_delta" => {
      let idx = json_int(json, "index")
      if idx < self.blocks.length() {
        let block = self.blocks[idx]
        match (if json is Object(obj) { obj.get("delta") } else { None }) {
          Some(delta) =>
            match (if delta is Object(obj) { obj.get("type") } else { None }) {
              Some(String("text_delta")) =>
                match
                  (if delta is Object(obj) { obj.get("text") } else { None }) {
                  Some(String(text)) => {
                    let new_block = {
                      kind: block.kind,
                      text: block.text + text,
                      tool_id: block.tool_id,
                      tool_name: block.tool_name,
                      input_str: block.input_str,
                    }
                    self.blocks[idx] = new_block
                  }
                  _ => ()
                }
              Some(String("input_json_delta")) =>
                match
                  (if delta is Object(obj) {
                    obj.get("partial_json")
                  } else {
                    None
                  }) {
                  Some(String(partial)) => {
                    let new_block = {
                      kind: ToolUse,
                      text: block.text,
                      tool_id: block.tool_id,
                      tool_name: block.tool_name,
                      input_str: block.input_str + partial,
                    }
                    self.blocks[idx] = new_block
                  }
                  _ => ()
                }
              Some(String("thinking_delta")) =>
                match
                  (if delta is Object(obj) {
                    obj.get("thinking")
                  } else {
                    None
                  }) {
                  Some(String(thinking)) => {
                    let new_block = {
                      kind: block.kind,
                      text: block.text + thinking,
                      tool_id: block.tool_id,
                      tool_name: block.tool_name,
                      input_str: block.input_str,
                    }
                    self.blocks[idx] = new_block
                  }
                  _ => ()
                }
              _ => ()
            }
          _ => ()
        }
      }
    }
    "content_block_stop" => ()
    "message_delta" => {
      match (if json is Object(obj) { obj.get("delta") } else { None }) {
        Some(delta) =>
          match
            (if delta is Object(obj) { obj.get("stop_reason") } else { None }) {
            Some(String(reason)) => self.stop_reason = Some(reason)
            _ => ()
          }
        _ => ()
      }
      match (if json is Object(obj) { obj.get("usage") } else { None }) {
        Some(u) =>
          self.output_tokens = self.output_tokens + json_int(u, "output_tokens")
        _ => ()
      }
    }
    "message_stop" | "ping" | "error" => ()
    _ => ()
  }
}

///|
/// Convert accumulated stream data into a non-streaming LlmResponse.
pub fn AnthropicStreamAggregator::to_response(
  self : AnthropicStreamAggregator,
) -> LlmResponse {
  let text_parts : Array[String] = []
  let tool_calls_arr : Array[@message.ToolCall] = []

  for block in self.blocks {
    match block.kind {
      Text => text_parts.push(block.text)
      ToolUse => {
        let id = match block.tool_id {
          Some(id) => id
          _ => ""
        }
        let name = match block.tool_name {
          Some(n) => n
          _ => ""
        }
        tool_calls_arr.push(@message.ToolCall::new(id, name, block.input_str))
      }
    }
  }

  let content = join_str_array(text_parts, "")
  let content_val : String? = if content.length() > 0 {
    Some(content)
  } else {
    None
  }
  let tool_calls_val : Array[@message.ToolCall]? = if tool_calls_arr.length() >
    0 {
    Some(tool_calls_arr)
  } else {
    None
  }

  // Map Anthropic stop_reason to canonical finish_reason
  let finish_reason = match self.stop_reason {
    Some("end_turn") => Some("stop")
    Some("tool_use") => Some("tool_calls")
    Some("max_tokens") => Some("length")
    other => other
  }

  let usage = if self.input_tokens > 0 || self.output_tokens > 0 {
    Some(
      Usage::from_anthropic(
        self.input_tokens,
        self.output_tokens,
        cache_creation=self.cache_creation,
        cache_read=self.cache_read,
      ),
    )
  } else {
    None
  }

  {
    content: content_val,
    tool_calls: tool_calls_val,
    finish_reason,
    usage,
    latency: None,
  }
}

// ── Bedrock Stream Aggregator ───────────────────────────────────────────────

///|
/// Kind of content block in a Bedrock Converse stream.
priv enum BedrockBlockKind {
  BedrockText
  BedrockToolUse
  BedrockReasoning
}

///|
/// Internal accumulator for a single Bedrock content block.
struct BedrockBlockAcc {
  kind : BedrockBlockKind
  text : String
  tool_id : String?
  tool_name : String?
  input_str : String
  reasoning : String
}

///|
/// Reassembles a Bedrock Converse event stream into a non-streaming
/// LlmResponse. Mirrors Ruby's BedrockStreamAggregator.
///
/// Handles 6 Bedrock event types:
/// - messageStart → sets role
/// - contentBlockStart → initializes block (text or tool_use)
/// - contentBlockDelta → appends text/toolUse input/reasoningContent
/// - contentBlockStop → no-op
/// - messageStop → sets stopReason
/// - metadata → merges usage
pub(all) struct BedrockStreamAggregator {
  mut role : String
  mut blocks : Map[Int, BedrockBlockAcc]
  mut stop_reason : String?
  mut input_tokens : Int
  mut output_tokens : Int
  mut cache_read : Int
  mut cache_write : Int
}

///|
/// Create a new Bedrock stream aggregator.
pub fn BedrockStreamAggregator::new() -> BedrockStreamAggregator {
  {
    role: "assistant",
    blocks: {},
    stop_reason: None,
    input_tokens: 0,
    output_tokens: 0,
    cache_read: 0,
    cache_write: 0,
  }
}

///|
/// Handle a single SSE event+data pair from the Bedrock stream.
pub fn BedrockStreamAggregator::handle(
  self : BedrockStreamAggregator,
  event : String,
  data_str : String,
) -> Unit {
  let json = @json.parse(data_str) catch { _ => return }

  match event {
    "messageStart" =>
      match (if json is Object(obj) { obj.get("role") } else { None }) {
        Some(String(r)) => self.role = r
        _ => ()
      }
    "contentBlockStart" => {
      let idx = json_int(json, "contentBlockIndex")
      match (if json is Object(obj) { obj.get("start") } else { None }) {
        Some(Object(start)) =>
          match start.get("toolUse") {
            Some(Object(tu)) => {
              let id = match tu.get("toolUseId") {
                Some(String(s)) => Some(s)
                _ => None
              }
              let name = match tu.get("name") {
                Some(String(s)) => Some(s)
                _ => None
              }
              self.blocks[idx] = {
                kind: BedrockToolUse,
                text: "",
                tool_id: id,
                tool_name: name,
                input_str: "",
                reasoning: "",
              }
            }
            _ =>
              self.blocks[idx] = {
                kind: BedrockText,
                text: "",
                tool_id: None,
                tool_name: None,
                input_str: "",
                reasoning: "",
              }
          }
        _ => ()
      }
    }
    "contentBlockDelta" => {
      let idx = json_int(json, "contentBlockIndex")
      match (if json is Object(obj) { obj.get("delta") } else { None }) {
        Some(Object(delta)) => {
          // Check for text delta
          match delta.get("text") {
            Some(String(text)) =>
              match self.blocks.get(idx) {
                Some(block) =>
                  self.blocks[idx] = {
                    kind: block.kind,
                    text: block.text + text,
                    tool_id: block.tool_id,
                    tool_name: block.tool_name,
                    input_str: block.input_str,
                    reasoning: block.reasoning,
                  }
                None =>
                  self.blocks[idx] = {
                    kind: BedrockText,
                    text,
                    tool_id: None,
                    tool_name: None,
                    input_str: "",
                    reasoning: "",
                  }
              }
            _ => ()
          }
          // Check for toolUse delta
          match delta.get("toolUse") {
            Some(Object(tu)) => {
              let input_delta = match tu.get("input") {
                Some(String(s)) => s
                _ => ""
              }
              match self.blocks.get(idx) {
                Some(block) => {
                  let id = match tu.get("toolUseId") {
                    Some(String(s)) => Some(s)
                    _ => block.tool_id
                  }
                  let name = match tu.get("name") {
                    Some(String(s)) => Some(s)
                    _ => block.tool_name
                  }
                  self.blocks[idx] = {
                    kind: BedrockToolUse,
                    text: block.text,
                    tool_id: id,
                    tool_name: name,
                    input_str: block.input_str + input_delta,
                    reasoning: block.reasoning,
                  }
                }
                None =>
                  self.blocks[idx] = {
                    kind: BedrockToolUse,
                    text: "",
                    tool_id: match tu.get("toolUseId") {
                      Some(String(s)) => Some(s)
                      _ => None
                    },
                    tool_name: match tu.get("name") {
                      Some(String(s)) => Some(s)
                      _ => None
                    },
                    input_str: input_delta,
                    reasoning: "",
                  }
              }
            }
            _ => ()
          }
          // Check for reasoningContent delta
          match delta.get("reasoningContent") {
            Some(Object(rc)) => {
              let reasoning_delta = match rc.get("text") {
                Some(String(s)) => s
                _ => ""
              }
              match self.blocks.get(idx) {
                Some(block) =>
                  self.blocks[idx] = {
                    kind: BedrockReasoning,
                    text: block.text,
                    tool_id: block.tool_id,
                    tool_name: block.tool_name,
                    input_str: block.input_str,
                    reasoning: block.reasoning + reasoning_delta,
                  }
                None =>
                  self.blocks[idx] = {
                    kind: BedrockReasoning,
                    text: "",
                    tool_id: None,
                    tool_name: None,
                    input_str: "",
                    reasoning: reasoning_delta,
                  }
              }
            }
            _ => ()
          }
        }
        _ => ()
      }
    }
    "contentBlockStop" => ()
    "messageStop" =>
      match (if json is Object(obj) { obj.get("stopReason") } else { None }) {
        Some(String(reason)) => self.stop_reason = Some(reason)
        _ => ()
      }
    "metadata" =>
      match (if json is Object(obj) { obj.get("usage") } else { None }) {
        Some(u) => {
          self.input_tokens = self.input_tokens + json_int(u, "inputTokens")
          self.output_tokens = self.output_tokens + json_int(u, "outputTokens")
          self.cache_read = self.cache_read +
            json_int(u, "cacheReadInputTokens")
          self.cache_write = self.cache_write +
            json_int(u, "cacheWriteInputTokens")
        }
        _ => ()
      }
    _ => ()
  }
}

///|
/// Render the accumulated stream data as a Bedrock Converse response JSON,
/// suitable for consumption by parse_bedrock_response.
pub fn BedrockStreamAggregator::to_json(self : BedrockStreamAggregator) -> Json {
  // Collect and sort block indices
  let indices : Array[Int] = []
  for k, _ in self.blocks {
    indices.push(k)
  }
  indices.sort()

  // Build content blocks array
  let content_blocks : Array[Json] = []
  for idx in indices {
    match self.blocks.get(idx) {
      Some(block) =>
        match block.kind {
          BedrockToolUse => {
            let id = match block.tool_id {
              Some(id) => id
              _ => ""
            }
            let name = match block.tool_name {
              Some(n) => n
              _ => ""
            }
            let input : Json = if block.input_str.length() == 0 {
              Json::object({})
            } else {
              @json.parse(block.input_str) catch {
                _ => Json::object({})
              }
            }
            content_blocks.push(
              Json::object({
                "toolUse": Json::object({
                  "toolUseId": id.to_json(),
                  "name": name.to_json(),
                  "input": input,
                }),
              }),
            )
          }
          _ =>
            content_blocks.push(Json::object({ "text": block.text.to_json() }))
        }
      None => ()
    }
  }

  // Build response body
  let body : Map[String, Json] = {
    "output": Json::object({
      "message": Json::object({
        "role": self.role.to_json(),
        "content": content_blocks.to_json(),
      }),
    }),
    "usage": Json::object({
      "inputTokens": self.input_tokens.to_json(),
      "outputTokens": self.output_tokens.to_json(),
      "cacheReadInputTokens": self.cache_read.to_json(),
      "cacheWriteInputTokens": self.cache_write.to_json(),
    }),
  }
  match self.stop_reason {
    Some(r) => body["stopReason"] = r.to_json()
    None => ()
  }
  Json::object(body)
}

///|
/// Convert accumulated stream data into a non-streaming LlmResponse.
/// Renders to Bedrock response JSON and delegates to parse_bedrock_response.
pub fn BedrockStreamAggregator::to_response(
  self : BedrockStreamAggregator,
) -> LlmResponse {
  parse_bedrock_response(self.to_json())
}

// ── JSON Helpers ────────────────────────────────────────────────────────────

///|
/// Safely extract an integer from a JSON object, defaulting to 0.
fn json_int(json : Json, key : String) -> Int {
  match json {
    Object(obj) =>
      match obj.get(key) {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
    _ => 0
  }
}

///|
/// Join an array of strings with a separator.
fn join_str_array(parts : Array[String], sep : String) -> String {
  if parts.length() == 0 {
    return ""
  }
  let mut result = parts[0]
  let mut i = 1
  while i < parts.length() {
    result = result + sep + parts[i]
    i = i + 1
  }
  result
}
