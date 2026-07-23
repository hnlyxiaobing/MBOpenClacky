///| OpenAI-compatible API message format.

///|

///| Handles request body construction, response parsing, and tool result

///| formatting for OpenAI Chat Completions API (/v1/chat/completions).

///|

///| The canonical internal message format IS OpenAI format, so this

///| module mainly handles response parsing and edge cases.

///|
/// Build an OpenAI-compatible request body.
///
/// Messages are converted to API format (internal fields stripped,
/// content normalized). Vision-unsupported models have image blocks removed.
pub fn build_openai_request(
  messages : Array[@message.Message],
  model : String,
  tools : Array[Json],
  max_tokens : Int,
  enable_caching : Bool,
  vision_supported? : Bool = true,
  reasoning_effort? : String? = None,
) -> Json {
  // Convert messages to API format
  let api_messages : Array[Json] = []
  for msg in messages {
    let api_msg = msg.to_api_message()
    let json = normalize_openai_message(api_msg, vision_supported)
    api_messages.push(json)
  }

  let body : Map[String, Json] = {
    "model": model.to_json(),
    "max_tokens": max_tokens.to_json(),
    "messages": api_messages.to_json(),
  }

  // Add tools with optional cache_control on last tool
  if tools.length() > 0 {
    if enable_caching && tools.length() > 0 {
      let cached_tools : Array[Json] = []
      let mut i = 0
      while i < tools.length() {
        if i == tools.length() - 1 {
          // Add cache_control to last tool
          let tool_obj = tools[i]
          match tool_obj {
            Object(obj) => {
              let new_obj : Map[String, Json] = Map([])
              for k, v in obj {
                new_obj[k] = v
              }
              new_obj["cache_control"] = Json::object({
                "type": "ephemeral".to_json(),
              })
              cached_tools.push(Json::object(new_obj))
            }
            _ => cached_tools.push(tool_obj)
          }
        } else {
          cached_tools.push(tools[i])
        }
        i = i + 1
      }
      body["tools"] = cached_tools.to_json()
    } else {
      body["tools"] = tools.to_json()
    }
  }

  // Add reasoning effort if specified
  match reasoning_effort {
    Some(effort) if effort.length() > 0 =>
      body["reasoning_effort"] = effort.to_json()
    _ => ()
  }

  Json::object(body)
}

///|
/// Normalize a message's content for the OpenAI API.
/// Strips image_url blocks when vision is not supported.
fn normalize_openai_message(
  msg : @message.Message,
  vision_supported : Bool,
) -> Json {
  match msg.content {
    @message.Text(_) => message_to_json(msg)
    @message.Blocks(blocks) => {
      let filtered = normalize_content_blocks(blocks, vision_supported)
      if filtered.length() == 0 {
        let obj : Map[String, Json] = {
          "role": msg.role.to_string_value().to_json(),
          "content": Json::array([
            Json::object({ "type": "text".to_json(), "text": "...".to_json() }),
          ]),
        }
        add_tool_fields(msg, obj)
        Json::object(obj)
      } else {
        let content_arr : Array[Json] = []
        for block in filtered {
          content_arr.push(content_block_to_json(block))
        }
        let obj : Map[String, Json] = {
          "role": msg.role.to_string_value().to_json(),
          "content": content_arr.to_json(),
        }
        add_tool_fields(msg, obj)
        Json::object(obj)
      }
    }
  }
}

///|
/// Convert a Message to its JSON representation manually.
fn message_to_json(msg : @message.Message) -> Json {
  let obj : Map[String, Json] = {
    "role": msg.role.to_string_value().to_json(),
    "content": content_to_json(msg.content),
  }
  add_tool_fields(msg, obj)
  match msg.name {
    Some(n) => obj["name"] = n.to_json()
    _ => ()
  }
  Json::object(obj)
}

///|
/// Convert MessageContent to JSON.
fn content_to_json(content : @message.MessageContent) -> Json {
  match content {
    @message.Text(s) => s.to_json()
    @message.Blocks(blocks) => {
      let arr : Array[Json] = []
      for b in blocks {
        arr.push(content_block_to_json(b))
      }
      arr.to_json()
    }
  }
}

///|
/// Convert a ContentBlock to JSON.
fn content_block_to_json(block : @message.ContentBlock) -> Json {
  match block {
    @message.Text(tb) =>
      Json::object({ "type": "text".to_json(), "text": tb.text.to_json() })
    @message.Image(ib) =>
      Json::object({
        "type": "image_url".to_json(),
        "image_url": Json::object({
          "url": ib.url.to_json(),
          "detail": ib.detail.to_json(),
        }),
      })
  }
}

///|
/// Add optional tool_calls and tool_call_id fields to a message JSON object.
fn add_tool_fields(msg : @message.Message, obj : Map[String, Json]) -> Unit {
  match msg.tool_calls {
    Some(calls) => {
      let arr : Array[Json] = []
      for tc in calls {
        arr.push(
          Json::object({
            "id": tc.id.to_json(),
            "type": "function".to_json(),
            "function": Json::object({
              "name": tc.function.name.to_json(),
              "arguments": tc.function.arguments.to_json(),
            }),
          }),
        )
      }
      obj["tool_calls"] = arr.to_json()
    }
    _ => ()
  }
  match msg.tool_call_id {
    Some(id) => obj["tool_call_id"] = id.to_json()
    _ => ()
  }
}

///|
/// Filter and normalize content blocks for OpenAI API.
/// Strips image_url blocks when vision is not supported.
fn normalize_content_blocks(
  blocks : Array[@message.ContentBlock],
  vision_supported : Bool,
) -> Array[@message.ContentBlock] {
  let result : Array[@message.ContentBlock] = []
  for block in blocks {
    match block {
      @message.Text(tb) => if tb.text.length() > 0 { result.push(block) }
      @message.Image(_) => if vision_supported { result.push(block) }
      // Non-vision models: skip image blocks silently
    }
  }
  result
}

///|
/// Parse an OpenAI-compatible API response into an LlmResponse.
///
/// Expects the standard chat/completions response shape:
/// `{ "choices": [{ "message": {...}, "finish_reason": "..." }], "usage": {...} }`
pub fn parse_openai_response(data : Json) -> LlmResponse {
  let choices = match
    (if data is Object(obj) { obj.get("choices") } else { None }) {
    Some(Array(arr)) if arr.length() > 0 => arr
    _ => return LlmResponse::text_only("")
  }
  let first_choice = choices[0]
  let message = match
    (if first_choice is Object(obj) { obj.get("message") } else { None }) {
    Some(m) => m
    _ => return LlmResponse::text_only("")
  }

  // Extract content
  let content : String? = match
    (if message is Object(obj) { obj.get("content") } else { None }) {
    Some(String(s)) => Some(s)
    _ => None
  }

  // Extract tool calls
  let tool_calls : Array[@message.ToolCall]? = parse_openai_tool_calls(message)

  // Extract finish reason
  let finish_reason : String? = match
    (if first_choice is Object(obj) { obj.get("finish_reason") } else { None }) {
    Some(String(s)) => Some(s)
    _ => None
  }

  // Extract usage
  let usage : Usage? = match
    (if data is Object(obj) { obj.get("usage") } else { None }) {
    Some(u) => {
      let prompt = json_int(u, "prompt_tokens")
      let completion = json_int(u, "completion_tokens")
      let cache_creation = json_int(u, "cache_creation_input_tokens")
      let cache_read = json_int(u, "cache_read_input_tokens")

      // Also check prompt_tokens_details for OpenRouter cache info
      let (final_creation, final_read) = match
        (if u is Object(obj) { obj.get("prompt_tokens_details") } else { None }) {
        Some(details) => {
          let cached_tokens = json_int(details, "cached_tokens")
          let write_tokens = json_int(details, "cache_write_tokens")
          (
            if cache_creation > 0 {
              cache_creation
            } else {
              write_tokens
            },
            if cache_read > 0 {
              cache_read
            } else {
              cached_tokens
            },
          )
        }
        _ => (cache_creation, cache_read)
      }

      Some(
        Usage::from_openai(
          prompt,
          completion,
          cache_creation=final_creation,
          cache_read=final_read,
        ),
      )
    }
    _ => None
  }

  { content, tool_calls, finish_reason, usage, latency: None }
}

///|
/// Parse tool calls from an OpenAI response message.
fn parse_openai_tool_calls(message : Json) -> Array[@message.ToolCall]? {
  match (if message is Object(obj) { obj.get("tool_calls") } else { None }) {
    Some(Array(arr)) if arr.length() > 0 => {
      let calls : Array[@message.ToolCall] = []
      for call in arr {
        let id = match
          (if call is Object(obj) { obj.get("id") } else { None }) {
          Some(String(s)) => s
          _ => continue
        }
        match (if call is Object(obj) { obj.get("function") } else { None }) {
          Some(func) => {
            let name = match
              (if func is Object(obj) { obj.get("name") } else { None }) {
              Some(String(s)) => s
              _ => continue
            }
            let arguments = match
              (if func is Object(obj) { obj.get("arguments") } else { None }) {
              Some(String(s)) => s
              _ => continue
            }
            calls.push(@message.ToolCall::new(id, name, arguments))
          }
          _ => ()
        }
      }
      if calls.length() > 0 {
        Some(calls)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// Format tool results into canonical messages for the next API turn.
///
/// Each tool call in the response gets a corresponding tool result message.
pub fn format_openai_tool_results(
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
