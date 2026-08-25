///| AWS Bedrock Converse API message format.
///
/// Converts canonical OpenAI-style messages to Bedrock Converse API format
/// on the way out, and parses Bedrock responses back to canonical form.
///
/// Key differences from OpenAI/Anthropic:
/// - System messages go in a separate "system" field as [{text: ...}]
/// - Messages use content blocks: [{text:...}] | [{toolUse:{toolUseId,name,input}}] | [{toolResult:{toolUseId,content:[...]}}]
/// - Tool definitions use toolSpec format: {toolSpec:{name,description,inputSchema:{json:...}}}
/// - inferenceConfig: {maxTokens: ...} instead of max_tokens
/// - Stop reason: end_turn→stop, tool_use→tool_calls, max_tokens→length
/// - Usage: inputTokens, outputTokens, cacheReadInputTokens, cacheWriteInputTokens

///|
/// Detect if the request should use the Bedrock Converse API.
/// Matches API key with "ABSK" prefix (native AWS Bedrock)
/// or model ID with "abs-" prefix (ClackyAI proxy that speaks Bedrock Converse).
pub fn is_bedrock_api_key(api_key : String, model : String) -> Bool {
  if api_key.length() >= 4 && api_key[:4].to_owned() == "ABSK" {
    return true
  }
  model.length() >= 4 && model[:4].to_owned() == "abs-"
}

///|
/// Build a Bedrock Converse API request body.
///
/// Separates system messages, converts tool definitions to toolSpec format,
/// and transforms tool call/result messages to Bedrock native format.
/// Merges consecutive tool result messages (Bedrock requires alternating roles).
pub fn build_bedrock_request(
  messages : Array[@message.Message],
  _model : String,
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

  // Convert regular messages to Bedrock format
  let raw_messages : Array[Json] = []
  for msg in regular_messages {
    raw_messages.push(to_bedrock_message(msg))
  }

  // Merge consecutive tool result messages (Bedrock requires alternating roles)
  let api_messages = merge_consecutive_tool_results(raw_messages)

  // Apply caching if enabled
  let final_messages = if enable_caching {
    apply_bedrock_caching(api_messages)
  } else {
    api_messages
  }

  // Build request body
  let body : Map[String, Json] = { "messages": final_messages.to_json() }

  // Add system prompt if present
  let system_text = join_strings(system_parts, "\n\n")
  if system_text.length() > 0 {
    body["system"] = Json::array([
      Json::object({ "text": system_text.to_json() }),
    ])
  }

  // Add inference config
  body["inferenceConfig"] = Json::object({ "maxTokens": max_tokens.to_json() })

  // Add tool config if tools are provided
  if tools.length() > 0 {
    let api_tools : Array[Json] = []
    for tool in tools {
      api_tools.push(to_bedrock_tool(tool))
    }
    body["toolConfig"] = Json::object({ "tools": api_tools.to_json() })
  }

  // Add reasoning effort if specified
  match normalize_effort(reasoning_effort) {
    Some(effort) =>
      body["additionalModelRequestFields"] = Json::object({
        "thinking": Json::object({ "type": "adaptive".to_json() }),
        "output_config": Json::object({ "effort": effort.to_json() }),
      })
    None => ()
  }

  Json::object(body)
}

///|
/// Parse a Bedrock Converse API response into an LlmResponse.
///
/// Handles:
/// - Content blocks (text + toolUse)
/// - Stop reason mapping (end_turn→stop, tool_use→tool_calls, max_tokens→length)
/// - Usage normalization (Bedrock reports inputTokens separately from cache tokens)
pub fn parse_bedrock_response(data : Json) -> LlmResponse {
  // Extract output.message.content
  let blocks : Array[Json] = match
    (if data is Object(obj) { obj.get("output") } else { None }) {
    Some(Object(out_obj)) =>
      match
        (if out_obj.get("message") is Some(Object(msg_obj)) {
          msg_obj.get("content")
        } else {
          None
        }) {
        Some(Array(arr)) => arr
        _ => []
      }
    _ => []
  }

  // Collect text content and tool calls
  let text_parts : Array[String] = []
  let reasoning_parts : Array[String] = []
  let tool_calls : Array[@message.ToolCall] = []

  for block in blocks {
    match (if block is Object(obj) { obj.get("text") } else { None }) {
      Some(String(text)) => text_parts.push(text)
      _ => ()
    }
    match
      (if block is Object(obj) { obj.get("reasoningContent") } else { None }) {
      Some(Object(rc)) =>
        match rc.get("text") {
          Some(String(text)) => reasoning_parts.push(text)
          _ => ()
        }
      _ => ()
    }
    match (if block is Object(obj) { obj.get("toolUse") } else { None }) {
      Some(Object(tu)) => {
        let id = match tu.get("toolUseId") {
          Some(String(s)) => s
          _ => ""
        }
        let name = match tu.get("name") {
          Some(String(s)) => s
          _ => ""
        }
        // Bedrock toolUse "input" is a JSON object; serialize to string
        let args_str = match tu.get("input") {
          Some(String(s)) => s
          Some(input) => input.stringify()
          _ => "{}"
        }
        tool_calls.push(@message.ToolCall::new(id, name, args_str))
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
  let reasoning = join_strings(reasoning_parts, "")
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

  // Map Bedrock stopReason to canonical finish_reason
  let finish_reason : String? = match
    (if data is Object(obj) { obj.get("stopReason") } else { None }) {
    Some(String("end_turn")) => Some("stop")
    Some(String("tool_use")) => Some("tool_calls")
    Some(String("max_tokens")) => Some("length")
    Some(String(s)) => Some(s)
    None => None
    _ => None
  }

  // Parse usage
  let usage : Usage? = match
    (if data is Object(obj) { obj.get("usage") } else { None }) {
    Some(u) => {
      let input_tokens = json_int(u, "inputTokens")
      let output_tokens = json_int(u, "outputTokens")
      let cache_read = json_int(u, "cacheReadInputTokens")
      let cache_write = json_int(u, "cacheWriteInputTokens")
      // Bedrock inputTokens = non-cached input only.
      // Normalize: prompt_tokens = inputTokens + cacheReadInputTokens
      Some(
        Usage::from_openai(
          input_tokens + cache_read,
          output_tokens,
          cache_creation=cache_write,
          cache_read~,
        ),
      )
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
/// Same as OpenAI format — canonical tool messages.
pub fn format_bedrock_tool_results(
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

// ── Private Helpers ──────────────────────────────────────────────────────────

///|
/// Determine the Bedrock Converse API path for a given model.
/// Format: model/{modelId}/converse
/// The modelId is used as-is (ClackyAI proxy accepts both abs- prefixed and raw IDs).
pub fn bedrock_converse_path(model : String) -> String {
  "model/\{model}/converse"
}

///|
/// Determine the Bedrock Converse streaming API path for a given model.
/// Format: model/{modelId}/converse-stream
/// Mirrors Ruby `bedrock_stream_endpoint(model)` (client.rb:236).
pub fn bedrock_converse_stream_path(model : String) -> String {
  "model/\{model}/converse-stream"
}

///|
/// Convert a canonical message to Bedrock Converse API format.
fn to_bedrock_message(msg : @message.Message) -> Json {
  match msg.role {
    @message.Assistant =>
      match msg.tool_calls {
        Some(calls) if calls.length() > 0 => {
          let blocks : Array[Json] = []
          // Add text content if present
          match msg.content {
            @message.Text(text) if text.length() > 0 =>
              blocks.push(Json::object({ "text": text.to_json() }))
            @message.Blocks(content_blocks) =>
              for block in content_blocks {
                match block {
                  @message.Text(tb) if tb.text.length() > 0 =>
                    blocks.push(Json::object({ "text": tb.text.to_json() }))
                  _ => ()
                }
              }
            _ => ()
          }
          // Add toolUse blocks
          for tc in calls {
            let input = parse_tool_arguments(tc.function.arguments)
            blocks.push(
              Json::object({
                "toolUse": Json::object({
                  "toolUseId": sanitize_tool_use_id(tc.id).to_json(),
                  "name": tc.function.name.to_json(),
                  "input": input,
                }),
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
          let content_json = content_to_bedrock_blocks(msg.content)
          Json::object({
            "role": "assistant".to_json(),
            "content": content_json,
          })
        }
      }
    @message.Tool => {
      // Tool result -> Bedrock user message with toolResult block
      let result_blocks : Array[Json] = match msg.content {
        @message.Text(text) => [Json::object({ "text": text.to_json() })]
        @message.Blocks(blocks) => {
          let result : Array[Json] = []
          for block in blocks {
            match block {
              @message.Text(tb) if tb.text.length() > 0 =>
                result.push(Json::object({ "text": tb.text.to_json() }))
              @message.Image(ib) =>
                match url_to_bedrock_image(ib.url) {
                  Some(img) => result.push(img)
                  None => ()
                }
              _ => ()
            }
          }
          if result.length() == 0 {
            [Json::object({ "text": "...".to_json() })]
          } else {
            result
          }
        }
      }
      let tool_id = match msg.tool_call_id {
        Some(id) => sanitize_tool_use_id(id)
        _ => ""
      }
      Json::object({
        "role": "user".to_json(),
        "content": Json::array([
          Json::object({
            "toolResult": Json::object({
              "toolUseId": tool_id.to_json(),
              "content": result_blocks.to_json(),
            }),
          }),
        ]),
      })
    }
    _ => {
      // Regular user message
      let content_json = content_to_bedrock_blocks(msg.content)
      Json::object({
        "role": msg.role.to_string_value().to_json(),
        "content": content_json,
      })
    }
  }
}

///|
/// Convert message content to Bedrock content block array.
fn content_to_bedrock_blocks(content : @message.MessageContent) -> Json {
  match content {
    @message.Text(text) =>
      if text.length() == 0 {
        // Bedrock rejects empty content arrays — use placeholder
        Json::array([Json::object({ "text": "...".to_json() })])
      } else {
        Json::array([Json::object({ "text": text.to_json() })])
      }
    @message.Blocks(blocks) => {
      let result : Array[Json] = []
      for block in blocks {
        match block {
          @message.Text(tb) if tb.text.length() > 0 =>
            result.push(Json::object({ "text": tb.text.to_json() }))
          @message.Image(ib) =>
            match url_to_bedrock_image(ib.url) {
              Some(img) => result.push(img)
              None => ()
            }
          _ => ()
        }
      }
      if result.length() == 0 {
        Json::array([Json::object({ "text": "...".to_json() })])
      } else {
        result.to_json()
      }
    }
  }
}

///|
/// Convert an image URL to a Bedrock image block.
/// Bedrock only supports base64 data URIs for images.
fn url_to_bedrock_image(url : String) -> Json? {
  if url.length() == 0 {
    return None
  }
  if url.length() >= 5 && url[:5].to_owned() == "data:" {
    // Parse data URI: data:image/<format>;base64,<data>
    match url.find(";base64,") {
      Some(sep) => {
        let media_type = url[5:sep].to_owned()
        // Extract format from media_type (e.g. "image/png" -> "png")
        let format = match media_type.find("/") {
          Some(slash) => media_type[slash + 1:].to_owned()
          None => media_type
        }
        let data = url[sep + 8:].to_owned()
        Some(
          Json::object({
            "image": Json::object({
              "format": format.to_json(),
              "source": Json::object({ "bytes": data.to_json() }),
            }),
          }),
        )
      }
      None => None
    }
  } else {
    // Bedrock doesn't support URL-based images in all regions; skip
    None
  }
}

///|
/// Convert an OpenAI-style tool definition to Bedrock toolSpec format.
/// OpenAI: { "type": "function", "function": { "name", "description", "parameters" } }
/// Bedrock: { "toolSpec": { "name", "description", "inputSchema": { "json": <parameters> } } }
fn to_bedrock_tool(tool : Json) -> Json {
  match tool {
    Object(obj) =>
      match obj.get("function") {
        Some(Object(func)) => {
          let spec : Map[String, Json] = Map([])
          match func.get("name") {
            Some(v) => spec["name"] = v
            _ => ()
          }
          match func.get("description") {
            Some(v) => spec["description"] = v
            _ => ()
          }
          match func.get("parameters") {
            Some(v) => spec["inputSchema"] = Json::object({ "json": v })
            None =>
              spec["inputSchema"] = Json::object({
                "json": Json::object(Map([])),
              })
          }
          Json::object({ "toolSpec": Json::object(spec) })
        }
        _ => tool
      }
    _ => tool
  }
}

///|
/// Sanitize a tool use ID for Bedrock compatibility.
/// Bedrock requires toolUseId to contain only alphanumeric characters, underscores, and hyphens.
fn sanitize_tool_use_id(id : String) -> String {
  let buf = StringBuilder()
  for ch in id {
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_' ||
      ch == '-' {
      buf.write_char(ch)
    } else {
      buf.write_char('_')
    }
  }
  buf.to_string()
}

///|
/// Merge consecutive tool result messages (user messages with toolResult blocks).
/// Bedrock Converse API requires strict user/assistant alternation.
fn merge_consecutive_tool_results(messages : Array[Json]) -> Array[Json] {
  if messages.length() == 0 {
    return []
  }
  let merged : Array[Json] = []
  for msg in messages {
    let prev = if merged.length() > 0 {
      Some(merged[merged.length() - 1])
    } else {
      None
    }
    // Check if both current and previous are user messages with toolResult blocks
    let should_merge = match prev {
      Some(prev_msg) =>
        is_user_with_tool_result(prev_msg) && is_user_with_tool_result(msg)
      None => false
    }
    if should_merge {
      // Merge content arrays
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
/// Check if a JSON message is a user message containing toolResult blocks.
fn is_user_with_tool_result(msg : Json) -> Bool {
  match msg {
    Object(obj) =>
      match (obj.get("role"), obj.get("content")) {
        (Some(String("user")), Some(Array(arr))) => {
          let has_tool_result = false
          for item in arr {
            match item {
              Object(o) => if o.get("toolResult") is Some(_) { return true }
              _ => ()
            }
          }
          has_tool_result
        }
        _ => false
      }
    _ => false
  }
}

///|
/// Inject cachePoint blocks into already-converted Bedrock API format messages.
/// Marks the last 2 messages so Bedrock can cache the conversation prefix.
fn apply_bedrock_caching(api_messages : Array[Json]) -> Array[Json] {
  if api_messages.length() == 0 {
    return api_messages
  }
  let result : Array[Json] = []
  let total = api_messages.length()
  let candidate_count = if total >= 2 { 2 } else { total }
  for i in 0..<total {
    let msg = api_messages[i]
    let is_candidate = i >= total - candidate_count
    if is_candidate {
      match msg {
        Object(obj) =>
          match obj.get("content") {
            Some(Array(content_arr)) => {
              // Check if cachePoint already present
              let already_marked = if content_arr.length() > 0 {
                match content_arr[content_arr.length() - 1] {
                  Object(o) => o.get("cachePoint") is Some(_)
                  _ => false
                }
              } else {
                false
              }
              if !already_marked {
                let new_content : Array[Json] = []
                for item in content_arr {
                  new_content.push(item)
                }
                new_content.push(
                  Json::object({
                    "cachePoint": Json::object({ "type": "default".to_json() }),
                  }),
                )
                obj["content"] = new_content.to_json()
              }
            }
            _ => ()
          }
        _ => ()
      }
    }
    result.push(msg)
  }
  result
}
