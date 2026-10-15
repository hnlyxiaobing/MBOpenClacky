///| OpenAI Responses API message format.

///|

///| Handles request body construction, response parsing, and tool result

///| formatting for OpenAI Responses API (/v1/responses).

///|

///| The Responses API uses a different wire format than Chat Completions:

///| - `input` array instead of `messages`

///| - `max_output_tokens` instead of `max_tokens`

///| - `developer` role instead of `system`

///| - Flattened tool definitions (no nested `function` key)

///| - `function_call_output` items instead of `tool` role messages

///| - Stream events are typed (response.output_text.delta, etc.)

///|   with no `[DONE]` sentinel

///| Build an OpenAI Responses API request body.

///|

///| Converts internal messages to the Responses `input` array format,

///| flattens tool definitions, and uses `max_output_tokens` for the

///|
/// token limit.
pub fn build_openai_responses_request(
  messages : Array[@message.Message],
  model : String,
  tools : Array[Json],
  max_tokens : Int32,
  enable_caching : Bool,
  vision_supported~ : Bool = true,
  reasoning_effort~ : String? = None,
) -> Json {
  let input_items : Array[Json] = []
  for msg in messages {
    let api_msg = msg.to_api_message()
    convert_to_responses_input(input_items, api_msg, vision_supported)
  }

  let body : Map[String, Json] = {
    "model": Json(model),
    "input": Json(input_items),
  }
  let effective_max_tokens = match @config.max_output_for(model) {
    Some(limit) => limit
    None => max_tokens
  }
  body["max_output_tokens"] = Json(effective_max_tokens)

  if tools.length() > 0 {
    let flat_tools = flatten_responses_tools(tools, enable_caching)
    body["tools"] = Json(flat_tools)
  }

  apply_responses_reasoning(body, model, reasoning_effort)

  Json::object(body)
}

///|
/// Convert a single internal message into one or more Responses API input
/// items. Tool-role messages become `function_call_output` items; assistant
/// messages with tool_calls emit the content as an assistant message followed
/// by `function_call` items for each call.
fn convert_to_responses_input(
  items : Array[Json],
  msg : @message.Message,
  vision_supported : Bool,
) -> Unit {
  match msg.role {
    @message.Tool => {
      let output_text = match msg.content {
        @message.Text(s) => s
        @message.Blocks(blocks) => {
          let parts : Array[String] = []
          for b in blocks {
            match b {
              @message.Text(tb) => parts.push(tb.text)
              @message.Image(_) => ()
            }
          }
          join_responses_parts(parts)
        }
      }
      let call_id = match msg.tool_call_id {
        Some(id) => id
        None => ""
      }
      items.push(
        Json::object({
          "type": Json("function_call_output"),
          "call_id": Json(call_id),
          "output": Json(output_text),
        }),
      )
    }
    @message.Assistant => {
      let content_text = message_content_to_text(msg.content, vision_supported)
      if content_text.length() > 0 || msg.tool_calls is None {
        items.push(
          Json::object({
            "type": Json("message"),
            "role": Json("assistant"),
            "content": Json(content_text),
          }),
        )
      }
      match msg.tool_calls {
        Some(calls) =>
          for tc in calls {
            items.push(
              Json::object({
                "type": Json("function_call"),
                "call_id": Json(tc.id),
                "name": Json(tc.function.name),
                "arguments": Json(tc.function.arguments),
              }),
            )
          }
        None => ()
      }
    }
    @message.System => {
      let content_text = message_content_to_text(msg.content, vision_supported)
      items.push(
        Json::object({
          "type": Json("message"),
          "role": Json("developer"),
          "content": Json(content_text),
        }),
      )
    }
    @message.User => {
      let content_json = message_content_to_responses_content(
        msg.content,
        vision_supported,
      )
      items.push(
        Json::object({
          "type": Json("message"),
          "role": Json("user"),
          "content": content_json,
        }),
      )
    }
  }
}

///|
/// Extract plain text from MessageContent, filtering images when
/// vision is unsupported.
fn message_content_to_text(
  content : @message.MessageContent,
  vision_supported : Bool,
) -> String {
  match content {
    @message.Text(s) => s
    @message.Blocks(blocks) => {
      let parts : Array[String] = []
      for b in blocks {
        match b {
          @message.Text(tb) => if tb.text.length() > 0 { parts.push(tb.text) }
          @message.Image(_) =>
            if vision_supported {
              parts.push("[image]")
            } else {
              parts.push(
                "[Image content removed — current model does not support vision input]",
              )
            }
        }
      }
      join_responses_parts(parts)
    }
  }
}

///|
/// Convert MessageContent to the Responses API `content` field.
/// User messages can carry structured content arrays; we send plain text
/// as a string (the API accepts both).
fn message_content_to_responses_content(
  content : @message.MessageContent,
  vision_supported : Bool,
) -> Json {
  match content {
    @message.Text(s) => Json(s)
    @message.Blocks(blocks) => {
      let items : Array[Json] = []
      for b in blocks {
        match b {
          @message.Text(tb) =>
            if tb.text.length() > 0 {
              items.push(
                Json::object({
                  "type": Json("input_text"),
                  "text": Json(tb.text),
                }),
              )
            }
          @message.Image(ib) =>
            if vision_supported {
              items.push(
                Json::object({
                  "type": Json("input_image"),
                  "image_url": Json(ib.url),
                }),
              )
            } else {
              items.push(
                Json::object({
                  "type": Json("input_text"),
                  "text": Json(
                    "[Image content removed — current model does not support vision input]",
                  ),
                }),
              )
            }
        }
      }
      if items.length() == 0 {
        Json("")
      } else {
        Json(items)
      }
    }
  }
}

///|
/// Flatten Chat Completions tool definitions to Responses API format.
/// Chat Completions: `{"type":"function","function":{"name":...,"parameters":...}}`
/// Responses API:    `{"type":"function","name":...,"parameters":...}`
fn flatten_responses_tools(
  tools : Array[Json],
  enable_caching : Bool,
) -> Array[Json] {
  let result : Array[Json] = []
  let mut i = 0
  while i < tools.length() {
    let tool = tools[i]
    let flat = match tool {
      Object(obj) => {
        let func_def = match obj.get("function") {
          Some(Object(f)) => f
          _ => {
            result.push(tool)
            i = i + 1
            continue
          }
        }
        let new_obj : Map[String, Json] = { "type": Json("function") }
        for k, v in func_def {
          new_obj[k] = v
        }
        if enable_caching && i == tools.length() - 1 {
          new_obj["cache_control"] = Json::object({ "type": Json("ephemeral") })
        }
        Json::object(new_obj)
      }
      _ => tool
    }
    result.push(flat)
    i = i + 1
  }
  result
}

///|
/// Apply reasoning parameters to a Responses API request body.
/// The Responses API uses a `reasoning` object with `effort` field.
fn apply_responses_reasoning(
  body : Map[String, Json],
  model : String,
  reasoning_effort : String?,
) -> Unit {
  let m = model.to_lower()
  let effort_str = match reasoning_effort {
    Some(e) => e
    None => ""
  }
  if effort_str.length() > 0 {
    let mapped = match m {
      _ if m.contains("deepseek") =>
        if effort_str == "xhigh" {
          "max"
        } else {
          effort_str
        }
      _ =>
        match effort_str {
          "off" | "nothink" | "disabled" => "minimal"
          other => other
        }
    }
    body["reasoning"] = Json::object({ "effort": Json(mapped) })
  }
}

///|
/// Parse an OpenAI Responses API response into an LlmResponse.
///
/// Expects the Responses API shape:
/// `{ "output": [...], "usage": {...}, "status": "completed" }`
pub fn parse_openai_responses_response(data : Json) -> LlmResponse {
  let output_items = match
    (if data is Object(obj) { obj.get("output") } else { None }) {
    Some(Array(arr)) => arr
    _ => return LlmResponse::text_only("")
  }

  let content_parts : Array[String] = []
  let mut reasoning_content : String? = None
  let tool_calls_arr : Array[@message.ToolCall] = []

  for item in output_items {
    match (if item is Object(obj) { obj.get("type") } else { None }) {
      Some(String("message")) =>
        match (if item is Object(obj) { obj.get("content") } else { None }) {
          Some(Array(content_arr)) =>
            for block in content_arr {
              match
                (if block is Object(obj) { obj.get("type") } else { None }) {
                Some(String("output_text")) =>
                  match
                    (if block is Object(obj) { obj.get("text") } else { None }) {
                    Some(String(text)) => content_parts.push(text)
                    _ => ()
                  }
                Some(String("reasoning")) =>
                  match
                    (if block is Object(obj) { obj.get("text") } else { None }) {
                    Some(String(text)) =>
                      match reasoning_content {
                        Some(existing) =>
                          reasoning_content = Some(existing + text)
                        None => reasoning_content = Some(text)
                      }
                    _ => ()
                  }
                _ => ()
              }
            }
          Some(String(text)) => content_parts.push(text)
          _ => ()
        }
      Some(String("function_call")) => {
        let call_id = match
          (if item is Object(obj) { obj.get("call_id") } else { None }) {
          Some(String(s)) => s
          _ => ""
        }
        let name = match
          (if item is Object(obj) { obj.get("name") } else { None }) {
          Some(String(s)) => s
          _ => ""
        }
        let arguments = match
          (if item is Object(obj) { obj.get("arguments") } else { None }) {
          Some(String(s)) => s
          _ => ""
        }
        tool_calls_arr.push(@message.ToolCall::new(call_id, name, arguments))
      }
      _ => ()
    }
  }

  let content = join_responses_parts(content_parts)
  let content_val : String? = if content.length() > 0 {
    Some(content)
  } else {
    None
  }
  let tool_calls : Array[@message.ToolCall]? = if tool_calls_arr.length() > 0 {
    Some(tool_calls_arr)
  } else {
    None
  }

  let finish_reason = map_responses_status_to_finish(data)

  let usage = match
    (if data is Object(obj) { obj.get("usage") } else { None }) {
    Some(u) => {
      let input_tokens = json_int_responses(u, "input_tokens")
      let output_tokens = json_int_responses(u, "output_tokens")
      let total = json_int_responses(u, "total_tokens")
      Some(Usage::from_openai(input_tokens, output_tokens, total_tokens=total))
    }
    _ => None
  }

  {
    content: content_val,
    reasoning_content,
    tool_calls,
    finish_reason,
    usage,
    latency: None,
  }
}

///|
/// Map the Responses API `status` field to a canonical finish_reason.
fn map_responses_status_to_finish(data : Json) -> String? {
  let status = match
    (if data is Object(obj) { obj.get("status") } else { None }) {
    Some(String(s)) => s
    _ => return Some("stop")
  }
  match status {
    "completed" => Some("stop")
    "incomplete" => Some("length")
    "failed" => Some("error")
    _ => Some("stop")
  }
}

///|
/// Format tool results into Responses API input items for the next turn.
///
/// Each tool call gets a `function_call_output` item.
pub fn format_openai_responses_tool_results(
  response : LlmResponse,
  tool_results : Map[String, String],
) -> Array[@message.Message] {
  match response.tool_calls {
    Some(calls) => {
      let messages : Array[@message.Message] = []
      for tc in calls {
        let content = match tool_results.get(tc.id) {
          Some(result) => result
          None => Json({ "error": "Tool result missing" }).stringify()
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
/// Safely extract an integer from a JSON object, defaulting to 0.
fn json_int_responses(json : Json, key : String) -> Int32 {
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
/// Join string parts with newline separator.
fn join_responses_parts(parts : Array[String]) -> String {
  if parts.length() == 0 {
    return ""
  }
  let mut result = parts[0]
  let mut i = 1
  while i < parts.length() {
    result = result + "\n" + parts[i]
    i = i + 1
  }
  result
}
