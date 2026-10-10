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
  vision_supported~ : Bool = true,
  reasoning_effort~ : String? = None,
) -> Json {
  // Convert messages to API format
  let api_messages : Array[Json] = []
  for msg in messages {
    let api_msg = msg.to_api_message()
    // BUG-0069：`to_api_message` 会剥掉 `system_injected`，但 Ruby 侧是否带
    // `display_text` 键恰恰取决于「这条消息是否为 system 注入」——只有真实用户
    // 回合的 hash 带该键（agent.rb:1026-1032）。所以在剥之前先取好这个判定，
    // 传给序列化层。
    let emit_display_text = msg.system_injected != Some(true)
    let json = normalize_openai_message(
      api_msg, vision_supported, emit_display_text,
    )
    api_messages.push(json)
  }

  let body : Map[String, Json] = {
    "model": Json(model),
    "messages": Json(api_messages),
  }
  // Map literals require static keys; max-token field name is model-dependent
  // (some OpenAI-compatible models only accept max_completion_tokens).
  // Also override max_tokens when the model declares a higher output ceiling
  // in the capability table (mirrors Ruby send_openai_request, client.rb:348).
  let effective_max_tokens = match @config.max_output_for(model) {
    Some(limit) => limit
    None => max_tokens
  }
  body[token_field_for(model)] = Json(effective_max_tokens)

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
                "type": Json("ephemeral"),
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
      body["tools"] = Json(cached_tools)
    } else {
      body["tools"] = Json(tools)
    }
  }

  // Add reasoning effort if specified (model-family aware mapping).
  apply_reasoning_params(body, model, reasoning_effort)

  Json::object(body)
}

///|
/// Return the token-limit field name for the given model.
/// Most OpenAI-compatible APIs use `max_tokens`; MiMo-V2.5 (Xiaomi) and
/// MiniMax-M3 use `max_completion_tokens` to cap the combined thinking +
/// answer length (M3 documents max_completion_tokens over the legacy
/// max_tokens field). Mirrors Ruby `token_field_for`.
fn token_field_for(model : String) -> String {
  let m = model.to_lower()
  if m.has_prefix("mimo-v2") || m == "minimax-m3" {
    "max_completion_tokens"
  } else {
    "max_tokens"
  }
}

///|
/// Apply model-specific reasoning / thinking parameters to the request body.
///
/// Different model families expose extended reasoning through different API
/// fields. Maps the shared internal reasoning_effort value to each family's
/// native parameters in-place. Mirrors Ruby `apply_reasoning_params`.
///
/// Zero side-effects: when reasoning_effort is nil/empty the body is
/// unchanged, preserving the provider default for all models.
fn apply_reasoning_params(
  body : Map[String, Json],
  model : String,
  reasoning_effort : String?,
) -> Unit {
  let m = model.to_lower()
  let effort_str = match reasoning_effort {
    Some(e) => e
    None => ""
  }

  if m.has_prefix("glm-5.3") || m.has_prefix("glm-5-3") {
    // GLM-5.3 always thinks: thinking.type "disabled" is rejected with an
    // error (Z.ai migration guide), so "off" maps to the lightest effort
    // "low". Effort accepts low/high/max only; server default is max.
    body["thinking"] = Json::object({ "type": Json("enabled") })
    if effort_str == "off" ||
      effort_str == "nothink" ||
      effort_str == "disabled" {
      body["reasoning_effort"] = Json("low")
    } else if effort_str.length() > 0 {
      let mapped = match effort_str {
        "max" | "xhigh" => "max"
        "high" => "high"
        "medium" | "low" => "low"
        _ => "max"
      }
      body["reasoning_effort"] = Json(mapped)
    }
  } else if m.has_prefix("glm-4") || m.has_prefix("glm-5") {
    // GLM (Zhipu / Z.ai) supports a native top-level "thinking" field
    // ({type: "enabled"|"disabled"}) plus a restricted reasoning_effort that
    // only accepts "max" or "high". Other effort levels collapse to "high".
    if effort_str == "off" ||
      effort_str == "nothink" ||
      effort_str == "disabled" {
      body["thinking"] = Json::object({ "type": Json("disabled") })
    } else if effort_str.length() > 0 {
      let glm_effort = match effort_str {
        "max" | "xhigh" => "max"
        "high" => "high"
        "medium" | "low" => "high" // GLM collapses these to "high"
        _ => "max"
      }
      body["thinking"] = Json::object({ "type": Json("enabled") })
      body["reasoning_effort"] = Json(glm_effort)
    }
  } else if m.has_prefix("kimi-k3") {
    // Kimi K3 reasoning_effort only accepts low/high/max (default max).
    // Thinking is always enabled and cannot be turned off; "off" maps to the
    // lowest intensity "low". Unsupported levels (medium, xhigh) would be
    // rejected or ignored by the server.
    if effort_str == "off" ||
      effort_str == "nothink" ||
      effort_str == "disabled" {
      body["reasoning_effort"] = Json("low")
    } else if effort_str.length() > 0 {
      let mapped = match effort_str {
        "max" | "xhigh" => "max"
        "high" => "high"
        "medium" | "low" => "low"
        _ => "max"
      }
      body["reasoning_effort"] = Json(mapped)
    }
  } else if m.has_prefix("mimo-v2") {
    // MiMo-V2.5 (Xiaomi) controls reasoning via a top-level
    // thinking:{type:...} field rather than reasoning_effort.
    if effort_str == "off" ||
      effort_str == "nothink" ||
      effort_str == "disabled" {
      body["thinking"] = Json::object({ "type": Json("disabled") })
    } else if effort_str.length() > 0 {
      body["thinking"] = Json::object({ "type": Json("enabled") })
    }
  } else if m == "minimax-m3" {
    // MiniMax-M3 controls thinking via { type: "adaptive" | "disabled" }.
    // Adaptive thinking is the server default when the field is omitted, so
    // we only send the field to explicitly switch modes:
    //   - reasoning_effort "off"/"disabled" → thinking disabled
    //   - any other effort → adaptive thinking (server picks intensity).
    if effort_str == "off" ||
      effort_str == "nothink" ||
      effort_str == "disabled" {
      body["thinking"] = Json::object({ "type": Json("disabled") })
    } else if effort_str.length() > 0 {
      body["thinking"] = Json::object({ "type": Json("adaptive") })
    }
  } else if m.contains("deepseek") {
    // DeepSeek V4 reasoning_effort only accepts low/high/max.
    // xhigh is not recognized — map it to max.
    let effort = if effort_str == "xhigh" { "max" } else { effort_str }
    if effort.length() > 0 {
      body["reasoning_effort"] = Json(effort)
    }
  } else if effort_str.length() > 0 {
    body["reasoning_effort"] = Json(effort_str)
  }
}

///|
/// Add observability / display fields (latency, display_text) to the wire
/// JSON object. Per spec 2026-08-18_23 option A:
/// - assistant messages: include `latency` when set (mirrors Ruby
///   message_format/open_ai.rb hash-passthrough, which echoes the 7-field
///   latency hash verbatim).
/// - user messages: include `display_text` (null when unset, matching Ruby's
///   nil-as-null serialization) **only for real user turns** —
///   `emit_display_text` 由调用方依据原消息的 `system_injected` 传入（见
///   `build_openai_request`）。`display_files` is NOT emitted: it is
///   listed in Ruby's `MessageHistory::INTERNAL_FIELDS` and therefore stripped
///   before the payload is built (BUG-0069).
/// - other roles (system/tool): skipped — no observability fields defined.
///
/// Also leaks the session-context fields into the wire payload (spec
/// 2026-08-18_29 decision 4): `session_date` whenever present, and
/// `session_context: true` only when set — mirrors Ruby's hash-passthrough
/// (session_date is a plain key on the wire; session_context is only emitted
/// by the Ruby serializer when truthy).
fn add_observability_fields(
  msg : @message.Message,
  obj : Map[String, Json],
  emit_display_text : Bool,
) -> Unit {
  match msg.latency {
    Some(v) => obj["latency"] = v
    None => ()
  }
  match msg.role {
    @message.User =>
      // BUG-0069：Ruby 对消息是「hash 直通 + 黑名单剥离」（`to_api` →
      // `strip_internal_fields`），因此**键是否存在**决定它是否出网：
      //   - `display_files` 在 `INTERNAL_FIELDS`（message_history.rb:13-19）里，
      //     永远被剥离 → 这里不写。
      //   - `display_text` 不在黑名单里，但只有真实用户回合才在
      //     `@history.append` 里带上它（agent.rb:1026-1032）；session context
      //     （agent.rb:2875-2881）、文件/上下文注入（agent.rb:1128/1137/1274）
      //     等 system-injected 消息的键集合里根本没有该键，Ruby 侧不会出现。
      //     故由调用方传入 `emit_display_text`（= 原消息非 system_injected），
      //     因为 `to_api_message` 已把 `system_injected` 剥掉。
      if emit_display_text {
        obj["display_text"] = match msg.display_text {
          Some(s) => Json(s)
          None => Json::null()
        }
      }
    _ => ()
  }
  // Session context fields leak into the wire by design (decision 4).
  match msg.session_date {
    Some(d) => obj["session_date"] = Json(d)
    None => ()
  }
  match msg.session_context {
    Some(true) => obj["session_context"] = Json(true)
    _ => ()
  }
}

///|
/// Normalize a message's content for the OpenAI API.
/// Strips image_url blocks when vision is not supported.
/// `emit_display_text` 见 `add_observability_fields`（BUG-0069）。
fn normalize_openai_message(
  msg : @message.Message,
  vision_supported : Bool,
  emit_display_text : Bool,
) -> Json {
  match msg.content {
    @message.Text(_) => message_to_json(msg, emit_display_text)
    @message.Blocks(blocks) => {
      let filtered = normalize_content_blocks(blocks, vision_supported)
      if filtered.length() == 0 {
        let obj : Map[String, Json] = {
          "role": Json(msg.role.to_string_value()),
          "content": Json::array([
            Json::object({ "type": Json("text"), "text": Json("...") }),
          ]),
        }
        add_tool_fields(msg, obj)
        add_observability_fields(msg, obj, emit_display_text)
        Json::object(obj)
      } else {
        let content_arr : Array[Json] = []
        for block in filtered {
          content_arr.push(content_block_to_json(block))
        }
        let obj : Map[String, Json] = {
          "role": Json(msg.role.to_string_value()),
          "content": Json(content_arr),
        }
        add_tool_fields(msg, obj)
        add_observability_fields(msg, obj, emit_display_text)
        Json::object(obj)
      }
    }
  }
}

///|
/// Convert a Message to its JSON representation manually.
fn message_to_json(msg : @message.Message, emit_display_text : Bool) -> Json {
  let obj : Map[String, Json] = {
    "role": Json(msg.role.to_string_value()),
    "content": content_to_json(msg.content),
  }
  add_tool_fields(msg, obj)
  add_observability_fields(msg, obj, emit_display_text)
  match msg.name {
    Some(n) => obj["name"] = Json(n)
    _ => ()
  }
  Json::object(obj)
}

///|
/// Convert MessageContent to JSON.
fn content_to_json(content : @message.MessageContent) -> Json {
  match content {
    @message.Text(s) => Json(s)
    @message.Blocks(blocks) => {
      let arr : Array[Json] = []
      for b in blocks {
        arr.push(content_block_to_json(b))
      }
      Json(arr)
    }
  }
}

///|
/// Convert a ContentBlock to JSON.
fn content_block_to_json(block : @message.ContentBlock) -> Json {
  match block {
    @message.Text(tb) =>
      Json::object({ "type": Json("text"), "text": Json(tb.text) })
    @message.Image(ib) =>
      Json::object({
        "type": Json("image_url"),
        "image_url": Json::object(
          match ib.detail {
            Some(detail) => { "url": Json(ib.url), "detail": Json(detail) }
            None => { "url": Json(ib.url) }
          },
        ),
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
        let tc_obj : Map[String, Json] = {
          "id": Json(tc.id),
          "type": Json("function"),
          "function": Json::object({
            "name": Json(tc.function.name),
            "arguments": Json(tc.function.arguments),
          }),
        }
        // Preserve provider-specific per-call metadata (e.g. Vertex Gemini's
        // thought_signature via OpenRouter) — it must be echoed back on the
        // next turn or the API rejects the replay with a 400.
        match tc.extra_content {
          Some(ec) => tc_obj["extra_content"] = ec
          None => ()
        }
        arr.push(Json::object(tc_obj))
      }
      obj["tool_calls"] = Json(arr)
    }
    _ => ()
  }
  match msg.tool_call_id {
    Some(id) => obj["tool_call_id"] = Json(id)
    _ => ()
  }
}

///|
/// Filter and normalize content blocks for OpenAI API.
/// Non-vision models get image blocks replaced with a text placeholder
/// (mirrors Ruby; silently dropping them could leave a message empty and
/// break the request, and the placeholder keeps the message readable).
fn normalize_content_blocks(
  blocks : Array[@message.ContentBlock],
  vision_supported : Bool,
) -> Array[@message.ContentBlock] {
  let result : Array[@message.ContentBlock] = []
  for block in blocks {
    match block {
      @message.Text(tb) => if tb.text.length() > 0 { result.push(block) }
      @message.Image(_) =>
        if vision_supported {
          result.push(block)
        } else {
          result.push(
            @message.Text({
              text: "[Image content removed — current model does not support vision input]",
            }),
          )
        }
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

  // Extract reasoning_content (thinking-mode models)
  let reasoning_content : String? = match
    (if message is Object(obj) { obj.get("reasoning_content") } else { None }) {
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
      // OpenRouter reports total_tokens and cost (USD) inside usage; pass
      // them through verbatim (cost as Double for the pricing layer).
      let total = json_int(u, "total_tokens")
      let api_cost = match
        (if u is Object(obj) { obj.get("cost") } else { None }) {
        Some(Number(n, ..)) => Some(n)
        _ => None
      }

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
          total_tokens=total,
          api_cost~,
        ),
      )
    }
    _ => None
  }

  {
    content,
    reasoning_content,
    tool_calls,
    finish_reason,
    usage,
    latency: None,
  }
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
            // Preserve provider-specific per-call metadata (e.g. Vertex
            // Gemini's thought_signature via OpenRouter) — it must be echoed
            // back on the next turn or the replay 400s with "Function call is
            // missing a thought_signature".
            let extra_content = match
              (if call is Object(obj) {
                obj.get("extra_content")
              } else {
                None
              }) {
              Some(ec) => Some(ec)
              _ => None
            }
            calls.push(
              @message.ToolCall::new(id, name, arguments, extra_content~),
            )
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
