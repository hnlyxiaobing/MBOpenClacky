///| Anthropic Messages API message format.

///|

///| Converts canonical OpenAI-style messages to Anthropic native format

///| on the way out, and parses Anthropic responses back to canonical form.

///|

///| Key differences from OpenAI:

///| - System messages go in a separate "system" field

///| - Tool definitions use "input_schema" instead of "parameters"

///| - Tool calls are "tool_use" content blocks

///| - Tool results are "user" messages with "tool_result" blocks

///| - Stop reason uses different names (end_turn, tool_use, max_tokens)

///|
/// Build an Anthropic Messages API request body.
///
/// Separates system messages, converts tool definitions,
/// and transforms tool call/result messages to Anthropic native format.
pub fn build_anthropic_request(
  messages : Array[@message.Message],
  model : String,
  tools : Array[Json],
  max_tokens : Int,
  enable_caching : Bool,
  reasoning_effort? : String? = None,
) -> Json {
  // Separate system messages from regular messages
  let system_parts : Array[String] = []
  let regular_messages : Array[@message.Message] = []

  for msg in messages {
    match msg.role {
      @message.System =>
        match msg.content {
          @message.Text(text) => system_parts.push(text)
          @message.Blocks(blocks) =>
            for block in blocks {
              match block {
                @message.Text(tb) => system_parts.push(tb.text)
                _ => ()
              }
            }
        }
      _ => regular_messages.push(msg)
    }
  }

  // Build system text
  let system_text = join_strings(system_parts, "\n\n")

  // Compute cache-candidate indices (tail 2 regular messages, skipping
  // injected compression hints) BEFORE conversion so the marker survives
  // the tool_result merge pass below.
  let cache_candidates = cache_candidate_indices(
    regular_messages, enable_caching,
  )

  // Convert regular messages to Anthropic format
  let api_messages : Array[Json] = []
  for i in 0..<regular_messages.length() {
    api_messages.push(
      to_anthropic_message(regular_messages[i], cache_candidates.contains(i)),
    )
  }

  // Merge consecutive tool_result user messages into a single user message.
  // Anthropic requires all tool_results for an assistant turn to appear in a
  // SINGLE user message immediately after the assistant — the canonical
  // format produces one role:"tool" message per result, which would break the
  // protocol contract and be rejected by the server.
  let api_messages = merge_anthropic_tool_results(api_messages)

  // Convert tools to Anthropic format
  let api_tools : Array[Json] = []
  let mut i = 0
  while i < tools.length() {
    let converted = to_anthropic_tool(tools[i])
    api_tools.push(converted)
    i = i + 1
  }

  // Add cache_control to last tool if caching enabled
  if enable_caching && api_tools.length() > 0 {
    let last_idx = api_tools.length() - 1
    let last_tool = api_tools[last_idx]
    match last_tool {
      Object(obj) => {
        let new_obj : Map[String, Json] = Map([])
        for k, v in obj {
          new_obj[k] = v
        }
        new_obj["cache_control"] = Json::object({
          "type": "ephemeral".to_json(),
        })
        api_tools[last_idx] = Json::object(new_obj)
      }
      _ => ()
    }
  }

  // Build request body
  let body : Map[String, Json] = {
    "model": model.to_json(),
    "max_tokens": max_tokens.to_json(),
    "messages": api_messages.to_json(),
  }

  if system_text.length() > 0 {
    body["system"] = system_text.to_json()
  }

  if api_tools.length() > 0 {
    body["tools"] = api_tools.to_json()
  }

  // Add thinking/reasoning params, model-family aware.
  // Kimi (Moonshot Coding Plan) models expect thinking:{type:"enabled"}
  // (the Claude-specific "adaptive" type is silently ignored by the Kimi
  // backend) and additionally support a "max" effort level.
  apply_anthropic_reasoning(body, model, reasoning_effort)

  Json::object(body)
}

///|
/// Normalize reasoning effort string, returning None for empty/invalid values.
/// Accepts the full 5-level domain (low/medium/high/xhigh/max); unknown
/// non-empty values warn on stderr instead of silently dropping the config.
fn normalize_effort(effort : String?) -> String? {
  match effort {
    Some(e) =>
      match e {
        "low" | "medium" | "high" | "xhigh" | "max" => Some(e)
        _ => {
          if e.length() > 0 {
            println(
              "[LLM] Unknown reasoning_effort '\{e}' ignored (valid: low/medium/high/xhigh/max)",
            )
          }
          None
        }
      }
    None => None
  }
}

///|
/// Compute the indices (into the regular-messages array) that should carry a
/// message-level cache_control marker: the tail 2 non-injected messages when
/// caching is enabled (mirrors Ruby `apply_message_caching`).
fn cache_candidate_indices(
  messages : Array[@message.Message],
  enable_caching : Bool,
) -> Array[Int] {
  let result : Array[Int] = []
  if !enable_caching {
    return result
  }
  for i = messages.length() - 1; i >= 0; i = i - 1 {
    if result.length() >= 2 {
      break
    }
    let is_injected = match messages[i].system_injected {
      Some(true) => true
      _ => false
    }
    if !is_injected {
      result.push(i)
    }
  }
  result
}

///|
/// Merge consecutive Anthropic-native user messages that contain tool_result
/// blocks into a single user message. Mirrors Ruby's
/// `merge_consecutive_tool_results` (run AFTER per-message conversion so
/// cache_control markers hoisted onto the tool_result block are preserved on
/// the merged message).
fn merge_anthropic_tool_results(api_messages : Array[Json]) -> Array[Json] {
  if api_messages.length() == 0 {
    return []
  }
  let merged : Array[Json] = []
  for msg in api_messages {
    let prev = if merged.length() > 0 {
      Some(merged[merged.length() - 1])
    } else {
      None
    }
    let should_merge = match prev {
      Some(prev_msg) =>
        is_anthropic_user_with_tool_result(prev_msg) &&
        is_anthropic_user_with_tool_result(msg)
      None => false
    }
    if should_merge {
      match (merged[merged.length() - 1], msg) {
        (Object(prev_obj), Object(cur_obj)) =>
          match (prev_obj.get("content"), cur_obj.get("content")) {
            (Some(Array(prev_arr)), Some(Array(cur_arr))) => {
              let combined : Array[Json] = []
              for item in prev_arr {
                combined.push(item)
              }
              for item in cur_arr {
                combined.push(item)
              }
              prev_obj["content"] = combined.to_json()
            }
            _ => merged.push(msg)
          }
        _ => merged.push(msg)
      }
    } else {
      merged.push(msg)
    }
  }
  merged
}

///|
/// Check if an Anthropic-native message is a user message with tool_result blocks.
/// Matches Ruby `b[:type] == "tool_result"` (anthropic.rb:151) — the converted
/// block shape is `{"type":"tool_result",...}`, NOT a `tool_result` key.
fn is_anthropic_user_with_tool_result(msg : Json) -> Bool {
  match msg {
    Object(obj) =>
      match (obj.get("role"), obj.get("content")) {
        (Some(String("user")), Some(Array(arr))) => {
          for item in arr {
            match item {
              Object(o) =>
                if o.get("type") == Some("tool_result".to_json()) {
                  return true
                }
              _ => ()
            }
          }
          false
        }
        _ => false
      }
    _ => false
  }
}

///|
/// Apply model-family aware reasoning/thinking parameters to an Anthropic
/// request body. Mirrors Ruby `MessageFormat::Anthropic.build_request_body`:
/// - Kimi K3 (and kimi-k3) → thinking:{type:"enabled"} + output_config.effort
///   (max/xhigh collapse to "max"); "off" leaves output_config unset.
/// - Everything else → thinking:{type:"adaptive"} + output_config.effort with
///   the full 5-level domain.
fn apply_anthropic_reasoning(
  body : Map[String, Json],
  model : String,
  reasoning_effort : String?,
) -> Unit {
  let model_lower = model.to_lower()
  let is_k3 = model_lower.has_prefix("k3") || model_lower.has_prefix("kimi-k3")
  if is_k3 {
    body["thinking"] = Json::object({ "type": "enabled".to_json() })
    let effort_str = match reasoning_effort {
      Some(e) => e
      None => ""
    }
    let k3_effort = match effort_str {
      "max" | "xhigh" => Some("max")
      "high" | "medium" | "low" => Some(effort_str)
      _ => None
    }
    match k3_effort {
      Some(ef) =>
        body["output_config"] = Json::object({ "effort": ef.to_json() })
      None => ()
    }
  } else {
    match normalize_effort(reasoning_effort) {
      Some(effort) => {
        body["thinking"] = Json::object({ "type": "adaptive".to_json() })
        body["output_config"] = Json::object({ "effort": effort.to_json() })
      }
      None => ()
    }
  }
}

///|
/// Convert a canonical message to Anthropic API format.
/// `is_cache_candidate` marks the message as a cache breakpoint: the marker
/// is hoisted onto the tool_result block for tool messages (where Anthropic
/// expects it) and onto the last text block otherwise.
fn to_anthropic_message(
  msg : @message.Message,
  is_cache_candidate : Bool,
) -> Json {
  match msg.role {
    @message.Assistant =>
      match msg.tool_calls {
        Some(calls) if calls.length() > 0 => {
          let blocks : Array[Json] = []
          // Add text content if present
          match msg.content {
            @message.Text(text) if text.length() > 0 =>
              blocks.push(
                Json::object({
                  "type": "text".to_json(),
                  "text": text.to_json(),
                }),
              )
            @message.Blocks(content_blocks) =>
              for block in content_blocks {
                match block {
                  @message.Text(tb) if tb.text.length() > 0 =>
                    blocks.push(
                      Json::object({
                        "type": "text".to_json(),
                        "text": tb.text.to_json(),
                      }),
                    )
                  _ => ()
                }
              }
            _ => ()
          }
          // Add tool_use blocks (id sanitised — Anthropic requires
          // ^[a-zA-Z0-9_-]{1,128}$ and OpenAI-compatible upstreams may
          // produce ids like "tool_name:0" that Anthropic rejects with 400)
          for tc in calls {
            let input = parse_tool_arguments(tc.function.arguments)
            blocks.push(
              Json::object({
                "type": "tool_use".to_json(),
                "id": sanitize_anthropic_tool_use_id(tc.id).to_json(),
                "name": tc.function.name.to_json(),
                "input": input,
              }),
            )
          }
          Json::object({
            "role": "assistant".to_json(),
            "content": blocks.to_json(),
          })
        }
        _ => {
          // Regular assistant message
          let content_json = content_to_anthropic_blocks(msg.content)
          let content_json = if is_cache_candidate {
            add_cache_control_to_last_block(content_json)
          } else {
            content_json
          }
          Json::object({
            "role": "assistant".to_json(),
            "content": content_json,
          })
        }
      }
    @message.Tool => {
      // Tool result -> Anthropic user message with tool_result block
      let tool_content : Json = match msg.content {
        @message.Text(text) => text.to_json()
        @message.Blocks(blocks) =>
          content_to_anthropic_blocks(@message.Blocks(blocks))
      }
      let tool_id = match msg.tool_call_id {
        Some(id) => sanitize_anthropic_tool_use_id(id)
        _ => ""
      }
      let tool_result_block : Map[String, Json] = {
        "type": "tool_result".to_json(),
        "tool_use_id": tool_id.to_json(),
        "content": tool_content,
      }
      if is_cache_candidate {
        // Hoist the cache marker onto the tool_result block — that's where
        // Anthropic expects it for a tool_result turn. Leaving it on an
        // inner text block would flip tool_result.content between "string"
        // and "[{text,cache_control}]" per turn, mutating the cached prefix
        // and destroying cache_read hit-rate.
        tool_result_block["cache_control"] = Json::object({
          "type": "ephemeral".to_json(),
        })
      }
      Json::object({
        "role": "user".to_json(),
        "content": Json::array([Json::object(tool_result_block)]),
      })
    }
    _ => {
      // Regular user/system message (system should already be filtered)
      let content_json = content_to_anthropic_blocks(msg.content)
      let content_json = if is_cache_candidate {
        add_cache_control_to_last_block(content_json)
      } else {
        content_json
      }
      Json::object({
        "role": msg.role.to_string_value().to_json(),
        "content": content_json,
      })
    }
  }
}

///|
/// Sanitize a tool use ID for Anthropic compatibility.
/// Anthropic requires tool_use.id to match ^[a-zA-Z0-9_-]{1,128}$; illegal
/// chars are replaced with "_" (pure function — same input maps to the same
/// output on both the tool_use and tool_result sides, keeping ids
/// self-consistent). Mirrors Ruby's `sanitize_tool_use_id`.
fn sanitize_anthropic_tool_use_id(id : String) -> String {
  let buf = StringBuilder::new()
  let mut count = 0
  for ch in id {
    if count >= 128 {
      break
    }
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_' ||
      ch == '-' {
      buf.write_char(ch)
    } else {
      buf.write_char('_')
    }
    count = count + 1
  }
  buf.to_string()
}

///|
/// Add a cache_control marker to the last TEXT block of an Anthropic content
/// array. Non-text trailing blocks (e.g. tool_use) are left untouched — a
/// cache_control on tool_use is not accepted by the API.
fn add_cache_control_to_last_block(content_json : Json) -> Json {
  match content_json {
    Array(arr) if arr.length() > 0 => {
      let last = arr[arr.length() - 1]
      match last {
        Object(obj) =>
          match obj.get("type") {
            Some(String("text")) => {
              let new_obj : Map[String, Json] = Map([])
              for k, v in obj {
                new_obj[k] = v
              }
              new_obj["cache_control"] = Json::object({
                "type": "ephemeral".to_json(),
              })
              let new_arr : Array[Json] = []
              for i in 0..<(arr.length() - 1) {
                new_arr.push(arr[i])
              }
              new_arr.push(Json::object(new_obj))
              Json::array(new_arr)
            }
            _ => content_json
          }
        _ => content_json
      }
    }
    _ => content_json
  }
}

///|
/// Convert message content to Anthropic content block array.
fn content_to_anthropic_blocks(content : @message.MessageContent) -> Json {
  match content {
    @message.Text(text) =>
      if text.length() == 0 {
        // Anthropic rejects empty text blocks — use placeholder
        Json::array([
          Json::object({ "type": "text".to_json(), "text": "...".to_json() }),
        ])
      } else {
        Json::array([
          Json::object({ "type": "text".to_json(), "text": text.to_json() }),
        ])
      }
    @message.Blocks(blocks) => {
      let result : Array[Json] = []
      for block in blocks {
        match block {
          @message.Text(tb) =>
            if tb.text.length() > 0 {
              result.push(
                Json::object({
                  "type": "text".to_json(),
                  "text": tb.text.to_json(),
                }),
              )
            }
          @message.Image(ib) =>
            match url_to_anthropic_image(ib.url) {
              Some(img) => result.push(img)
              None => ()
            }
        }
      }
      if result.length() == 0 {
        Json::array([
          Json::object({ "type": "text".to_json(), "text": "...".to_json() }),
        ])
      } else {
        result.to_json()
      }
    }
  }
}

///|
/// Convert an image URL to an Anthropic image block.
/// Handles data: URIs (base64) and regular URLs.
fn url_to_anthropic_image(url : String) -> Json? {
  if url.length() == 0 {
    return None
  }
  if url.length() >= 5 && url[:5].to_owned() == "data:" {
    // Parse data URI: data:<media_type>;base64,<data>
    match url.find(";base64,") {
      Some(sep) => {
        let media_type = url[5:sep].to_owned()
        let data = url[sep + 8:].to_owned()
        Some(
          Json::object({
            "type": "image".to_json(),
            "source": Json::object({
              "type": "base64".to_json(),
              "media_type": media_type.to_json(),
              "data": data.to_json(),
            }),
          }),
        )
      }
      None =>
        Some(
          Json::object({
            "type": "image".to_json(),
            "source": Json::object({
              "type": "url".to_json(),
              "url": url.to_json(),
            }),
          }),
        )
    }
  } else {
    Some(
      Json::object({
        "type": "image".to_json(),
        "source": Json::object({ "type": "url".to_json(), "url": url.to_json() }),
      }),
    )
  }
}

///|
/// Parse tool call arguments string as JSON, falling back to empty object.
fn parse_tool_arguments(arguments : String) -> Json {
  if arguments.length() == 0 {
    return Json::object(Map([]))
  }
  @json.parse(arguments) catch {
    _ => Json::object(Map([]))
  }
}

///|
/// Convert an OpenAI-style tool definition to Anthropic format.
/// OpenAI: { "type": "function", "function": { "name", "description", "parameters" } }
/// Anthropic: { "name", "description", "input_schema" }
fn to_anthropic_tool(tool : Json) -> Json {
  match tool {
    Object(obj) =>
      match obj.get("function") {
        Some(Object(func)) => {
          let result : Map[String, Json] = Map([])
          match func.get("name") {
            Some(v) => result["name"] = v
            _ => ()
          }
          match func.get("description") {
            Some(v) => result["description"] = v
            _ => ()
          }
          match func.get("parameters") {
            Some(v) => result["input_schema"] = v
            _ => result["input_schema"] = Json::object(Map([]))
          }
          Json::object(result)
        }
        _ =>
          // Already in Anthropic format or flat structure
          tool
      }
    _ => tool
  }
}

///|
/// Parse an Anthropic API response into an LlmResponse.
///
/// Handles:
/// - Content blocks (text + tool_use)
/// - Stop reason mapping (end_turn→stop, tool_use→tool_calls, max_tokens→length)
/// - Usage normalization (Anthropic reports input_tokens separately from cache tokens)
pub fn parse_anthropic_response(data : Json) -> LlmResponse {
  // Extract content blocks
  let blocks : Array[Json] = match
    (if data is Object(obj) { obj.get("content") } else { None }) {
    Some(Array(arr)) => arr
    _ => []
  }

  // Collect text content
  let text_parts : Array[String] = []
  let thinking_parts : Array[String] = []
  let tool_calls : Array[@message.ToolCall] = []

  for block in blocks {
    match (if block is Object(obj) { obj.get("type") } else { None }) {
      Some(String("text")) =>
        match (if block is Object(obj) { obj.get("text") } else { None }) {
          Some(String(text)) => text_parts.push(text)
          _ => ()
        }
      Some(String("thinking")) =>
        match (if block is Object(obj) { obj.get("thinking") } else { None }) {
          Some(String(thinking)) => thinking_parts.push(thinking)
          _ => ()
        }
      Some(String("tool_use")) => {
        let id = match
          (if block is Object(obj) { obj.get("id") } else { None }) {
          Some(String(s)) => s
          _ => ""
        }
        let name = match
          (if block is Object(obj) { obj.get("name") } else { None }) {
          Some(String(s)) => s
          _ => ""
        }
        // Anthropic tool_use "input" is a JSON object; serialize to string
        let input_str = match
          (if block is Object(obj) { obj.get("input") } else { None }) {
          Some(String(s)) => s
          Some(input) => input.stringify()
          _ => "{}"
        }
        tool_calls.push(@message.ToolCall::new(id, name, input_str))
      }
      _ => ()
    }
  }

  let content = join_strings(text_parts, "")
  let content_val : String? = if content.length() > 0 {
    Some(content)
  } else {
    None
  }
  let reasoning = join_strings(thinking_parts, "")
  let reasoning_val : String? = if reasoning.length() > 0 {
    Some(reasoning)
  } else {
    None
  }
  let tool_calls_val : Array[@message.ToolCall]? = if tool_calls.length() > 0 {
    Some(tool_calls)
  } else {
    None
  }

  // Map stop_reason
  let finish_reason : String? = match
    (if data is Object(obj) { obj.get("stop_reason") } else { None }) {
    Some(String("end_turn")) => Some("stop")
    Some(String("tool_use")) => Some("tool_calls")
    Some(String("max_tokens")) => Some("length")
    Some(String(other)) => Some(other)
    _ => None
  }

  // Extract and normalize usage
  let usage : Usage? = match
    (if data is Object(obj) { obj.get("usage") } else { None }) {
    Some(u) => {
      let raw_input = json_int(u, "input_tokens")
      let output = json_int(u, "output_tokens")
      let cache_creation = json_int(u, "cache_creation_input_tokens")
      let cache_read = json_int(u, "cache_read_input_tokens")
      if raw_input > 0 || output > 0 {
        Some(
          Usage::from_anthropic(raw_input, output, cache_creation~, cache_read~),
        )
      } else {
        None
      }
    }
    _ => None
  }

  {
    content: content_val,
    reasoning_content: reasoning_val,
    tool_calls: tool_calls_val,
    finish_reason,
    usage,
    latency: None,
  }
}

///|
/// Format tool results into canonical messages for the next API turn.
/// Returns canonical format (role: "tool") — conversion to Anthropic
/// native happens in to_anthropic_message during request building.
pub fn format_anthropic_tool_results(
  response : LlmResponse,
  tool_results : Map[String, String],
) -> Array[@message.Message] {
  match response.tool_calls {
    Some(calls) => {
      let messages : Array[@message.Message] = []
      for tc in calls {
        let content = match tool_results.get(tc.id) {
          Some(result) => result
          None => { "error": "Tool result missing" }.to_json().stringify()
        }
        messages.push(
          @message.Message::tool_result(tc.id, tc.function.name, content),
        )
      }
      messages
    }
    None => []
  }
}

///|
/// Determine the Anthropic Messages API path, accounting for base_url variations.
/// If base_url already contains "/v1", returns "messages"; otherwise "v1/messages".
pub fn anthropic_messages_path(base_url : String) -> String {
  let trimmed = base_url.trim_end()
  let len = trimmed.length()
  if len >= 3 && trimmed[len - 3:].to_owned() == "/v1" {
    "messages"
  } else if len >= 4 && trimmed[len - 4:].to_owned() == "/v1/" {
    "messages"
  } else {
    "v1/messages"
  }
}

///|
/// Join an array of strings with a separator.
fn join_strings(parts : Array[String], sep : String) -> String {
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
