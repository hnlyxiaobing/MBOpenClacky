///| Tests for the LLM client package.

///| Covers: SSE parsing, message formatting, response parsing, error handling.

// ── SSE Frame Parser Tests ──────────────────────────────────────────────────

///|
test "parse_sse_frames_single_frame" {
  let text = "data: hello world\n\n"
  let frames = parse_sse_frames(text)
  @debug.assert_eq(frames.length(), 1)
  @debug.assert_eq(frames[0].event, "message")
  @debug.assert_eq(frames[0].data, "hello world")
}

///|
test "parse_sse_frames_with_event" {
  let text = "event: message_start\ndata: {\"type\":\"start\"}\n\n"
  let frames = parse_sse_frames(text)
  @debug.assert_eq(frames.length(), 1)
  @debug.assert_eq(frames[0].event, "message_start")
  @debug.assert_eq(frames[0].data, "{\"type\":\"start\"}")
}

///|
test "parse_sse_frames_multiple" {
  let text = "data: first\n\ndata: second\n\ndata: third\n\n"
  let frames = parse_sse_frames(text)
  @debug.assert_eq(frames.length(), 3)
  @debug.assert_eq(frames[0].data, "first")
  @debug.assert_eq(frames[1].data, "second")
  @debug.assert_eq(frames[2].data, "third")
}

///|
test "parse_sse_frames_done_sentinel" {
  let text = "data: hello\n\ndata: [DONE]\n\n"
  let frames = parse_sse_frames(text)
  @debug.assert_eq(frames.length(), 2)
  @debug.assert_eq(frames[0].data, "hello")
  @debug.assert_eq(frames[1].data, "[DONE]")
}

///|
test "parse_sse_frames_incomplete_discarded" {
  // No trailing \n\n means the frame is incomplete
  let text = "data: incomplete"
  let frames = parse_sse_frames(text)
  @debug.assert_eq(frames.length(), 0)
}

///|
test "parse_sse_frames_empty" {
  let frames = parse_sse_frames("")
  @debug.assert_eq(frames.length(), 0)
}

///|
test "parse_sse_frames_comment_ignored" {
  let text = ": this is a comment\ndata: actual_data\n\n"
  let frames = parse_sse_frames(text)
  @debug.assert_eq(frames.length(), 1)
  @debug.assert_eq(frames[0].data, "actual_data")
}

// ── OpenAI Request Building Tests ───────────────────────────────────────────

///|
test "build_openai_request_basic" {
  let messages = [@message.Message::user("Hello")]
  let body = build_openai_request(messages, "gpt-4", [], 1024, false)
  let obj = match body {
    Object(o) => o
    _ => abort("expected object")
  }
  @debug.assert_eq(obj.get("model").unwrap().stringify(), "\"gpt-4\"")
  @debug.assert_eq(obj.get("max_tokens").unwrap().stringify(), "1024")
  match obj.get("messages") {
    Some(Array(msgs)) => @debug.assert_eq(msgs.length(), 1)
    _ => abort("expected messages array")
  }
}

///|
test "openai_max_output_for_overrides_ceiling" {
  // Capability table (Ruby MODEL_MAX_OUTPUT): strong models get a raised
  // ceiling instead of the 16K global default.
  @debug.assert_eq(@config.max_output_for("glm-5.2"), Some(65536))
  @debug.assert_eq(@config.max_output_for("GLM-5.2-Pro"), Some(65536))
  @debug.assert_eq(@config.max_output_for("kimi-k3"), Some(65536))
  @debug.assert_eq(@config.max_output_for("mimo-v2.5-pro"), Some(65536))
  // mimo-v2.5 (non-pro) matches the later /mimo/ entry → 32K
  @debug.assert_eq(@config.max_output_for("mimo-v2.5"), Some(32768))
  @debug.assert_eq(@config.max_output_for("gemini-3.5-flash"), Some(65536))
  @debug.assert_eq(@config.max_output_for("gpt-4o"), None)

  // Request body uses the raised ceiling (glm-5.2: 16384 → 65536)
  let messages = [@message.Message::user("Hello")]
  let body = build_openai_request(messages, "glm-5.2", [], 16384, false)
  let obj = match body {
    Object(o) => o
    _ => abort("expected object")
  }
  @debug.assert_eq(obj.get("max_tokens").unwrap().stringify(), "65536")

  // Unlisted model keeps the caller-supplied value
  let body2 = build_openai_request(messages, "gpt-4o", [], 1024, false)
  let obj2 = match body2 {
    Object(o) => o
    _ => abort("expected object")
  }
  @debug.assert_eq(obj2.get("max_tokens").unwrap().stringify(), "1024")
}

///|
test "build_openai_request_with_tools" {
  let messages = [@message.Message::user("test")]
  let tools : Array[Json] = [
    Json::object({
      "type": "function".to_json(),
      "function": Json::object({
        "name": "shell".to_json(),
        "description": "Run shell command".to_json(),
        "parameters": Json::object(Map([])),
      }),
    }),
  ]
  let body = build_openai_request(messages, "gpt-4", tools, 1024, false)
  let obj = match body {
    Object(o) => o
    _ => abort("expected object")
  }
  match obj.get("tools") {
    Some(Array(t)) => @debug.assert_eq(t.length(), 1)
    _ => abort("expected tools array")
  }
}

///|
test "build_openai_request_strips_image_for_non_vision" {
  let blocks : Array[@message.ContentBlock] = [
    @message.Text({ text: "describe" }),
    @message.Image({ url: "http://example.com/img.png", detail: None }),
  ]
  let msg : @message.Message = {
    role: @message.User,
    content: @message.Blocks(blocks),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    reasoning_content: None,
    task_id: None,
    created_at: None,
    system_injected: None,
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
  // vision_supported = false should strip image blocks
  let body = build_openai_request(
    [msg],
    "deepseek-chat",
    [],
    1024,
    false,
    vision_supported=false,
  )
  let json_str = body.stringify()
  // Should NOT contain image_url
  assert_true(json_str.find("image_url") is None)
}

///|
test "client_vision_defaults_from_capability_table" {
  // Provider with text_only() preset (DeepSeek) → vision defaults false
  let client = Client::new(
    "test-key",
    "https://api.deepseek.com",
    "deepseek-chat",
    @config.OpenAICompletions,
    provider_id=Some("deepseek"),
  )
  @debug.assert_eq(client.vision_supported, false)

  // Unknown provider → conservative default true (Ruby providers.rb:1151)
  let unknown = Client::new(
    "k",
    "https://api.unknown.example",
    "m",
    @config.OpenAICompletions,
    provider_id=Some("no-such-provider"),
  )
  @debug.assert_eq(unknown.vision_supported, true)

  // No provider_id → conservative default true
  let noprov = Client::new(
    "k",
    "https://api.x.example",
    "m",
    @config.OpenAICompletions,
  )
  @debug.assert_eq(noprov.vision_supported, true)

  // Explicit override still wins
  let explicit = Client::new(
    "k",
    "https://api.deepseek.com",
    "deepseek-chat",
    @config.OpenAICompletions,
    provider_id=Some("deepseek"),
    vision_supported=Some(true),
  )
  @debug.assert_eq(explicit.vision_supported, true)
}

// ── OpenAI Response Parsing Tests ───────────────────────────────────────────

///|
test "parse_openai_response_basic" {
  let raw = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Hello!\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}"
  let json = @json.parse(raw)
  let resp = parse_openai_response(json)
  assert_true(resp.content is Some(_))
  @debug.assert_eq(resp.content.unwrap(), "Hello!")
  @debug.assert_eq(resp.finish_reason.unwrap(), "stop")
  assert_true(resp.usage is Some(_))
  @debug.assert_eq(resp.usage.unwrap().input_tokens, 10)
  @debug.assert_eq(resp.usage.unwrap().output_tokens, 5)
}

///|
test "parse_openai_response_with_tool_calls" {
  let raw = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"shell\",\"arguments\":\"{\\\"cmd\\\":\\\"ls\\\"}\"}}],\"content\":null},\"finish_reason\":\"tool_calls\"}],\"usage\":{}}"
  let json = @json.parse(raw)
  let resp = parse_openai_response(json)
  assert_true(resp.has_tool_calls())
  let calls = resp.tool_calls.unwrap()
  @debug.assert_eq(calls.length(), 1)
  @debug.assert_eq(calls[0].id, "call_1")
  @debug.assert_eq(calls[0].function.name, "shell")
  @debug.assert_eq(calls[0].function.arguments, "{\"cmd\":\"ls\"}")
}

///|
test "parse_openai_response_empty" {
  let raw = "{\"choices\":[]}"
  let json = @json.parse(raw)
  let resp = parse_openai_response(json)
  @debug.assert_eq(resp.content.unwrap(), "")
}

// ── Anthropic Request Building Tests ────────────────────────────────────────

///|
test "build_anthropic_request_separates_system" {
  let messages = [
    @message.Message::system("You are helpful"),
    @message.Message::user("Hello"),
  ]
  let body = build_anthropic_request(
    messages,
    "claude-sonnet-4-5",
    [],
    1024,
    false,
  )
  let obj = match body {
    Object(o) => o
    _ => abort("expected object")
  }
  // System should be extracted into top-level field
  match obj.get("system") {
    Some(String(s)) => @debug.assert_eq(s, "You are helpful")
    _ => abort("expected system string")
  }
  // Only user message in messages array
  match obj.get("messages") {
    Some(Array(msgs)) => @debug.assert_eq(msgs.length(), 1)
    _ => abort("expected messages array")
  }
}

///|
test "build_anthropic_request_converts_tools" {
  let tools : Array[Json] = [
    Json::object({
      "type": "function".to_json(),
      "function": Json::object({
        "name": "read_file".to_json(),
        "description": "Read a file".to_json(),
        "parameters": Json::object({ "type": "object".to_json() }),
      }),
    }),
  ]
  let body = build_anthropic_request(
    [@message.Message::user("test")],
    "claude-sonnet-4-5",
    tools,
    1024,
    false,
  )
  let obj = match body {
    Object(o) => o
    _ => abort("expected object")
  }
  match obj.get("tools") {
    Some(Array(t)) => {
      @debug.assert_eq(t.length(), 1)
      // Should have input_schema, not parameters
      match t[0] {
        Object(tool) => {
          assert_true(tool.get("input_schema") is Some(_))
          assert_true(tool.get("name") is Some(_))
        }
        _ => abort("expected tool object")
      }
    }
    _ => abort("expected tools array")
  }
}

///|
test "build_anthropic_request_with_reasoning" {
  let body = build_anthropic_request(
    [@message.Message::user("think")],
    "claude-sonnet-4-5",
    [],
    1024,
    false,
    reasoning_effort=Some("high"),
  )
  let obj = match body {
    Object(o) => o
    _ => abort("expected object")
  }
  assert_true(obj.get("thinking") is Some(_))
  assert_true(obj.get("output_config") is Some(_))
}

// ── Anthropic Response Parsing Tests ────────────────────────────────────────

///|
test "parse_anthropic_response_text" {
  let raw = "{\"content\":[{\"type\":\"text\",\"text\":\"Hi there!\"}],\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":5,\"output_tokens\":3}}"
  let json = @json.parse(raw)
  let resp = parse_anthropic_response(json)
  @debug.assert_eq(resp.content.unwrap(), "Hi there!")
  @debug.assert_eq(resp.finish_reason.unwrap(), "stop")
  assert_true(resp.usage is Some(_))
}

///|
test "parse_anthropic_response_tool_use" {
  let raw = "{\"content\":[{\"type\":\"text\",\"text\":\"Let me check\"},{\"type\":\"tool_use\",\"id\":\"tu_1\",\"name\":\"shell\",\"input\":{\"cmd\":\"ls\"}}],\"stop_reason\":\"tool_use\",\"usage\":{\"input_tokens\":10,\"output_tokens\":5}}"
  let json = @json.parse(raw)
  let resp = parse_anthropic_response(json)
  assert_true(resp.has_tool_calls())
  @debug.assert_eq(resp.finish_reason.unwrap(), "tool_calls")
  let calls = resp.tool_calls.unwrap()
  @debug.assert_eq(calls.length(), 1)
  @debug.assert_eq(calls[0].id, "tu_1")
  @debug.assert_eq(calls[0].function.name, "shell")
}

///|
test "parse_anthropic_response_max_tokens" {
  let raw = "{\"content\":[{\"type\":\"text\",\"text\":\"partial\"}],\"stop_reason\":\"max_tokens\",\"usage\":{\"input_tokens\":5,\"output_tokens\":100}}"
  let json = @json.parse(raw)
  let resp = parse_anthropic_response(json)
  @debug.assert_eq(resp.finish_reason.unwrap(), "length")
}

///|
test "parse_anthropic_response_with_cache_usage" {
  let raw = "{\"content\":[{\"type\":\"text\",\"text\":\"cached\"}],\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":100,\"output_tokens\":50,\"cache_read_input_tokens\":80,\"cache_creation_input_tokens\":20}}"
  let json = @json.parse(raw)
  let resp = parse_anthropic_response(json)
  let usage = resp.usage.unwrap()
  // Anthropic two-convention normalisation: cached_input (80+20=100) fits
  // inside raw input_tokens (100), so input already excludes cache_read and
  // only cache_creation must be removed → 100-20 = 80.
  @debug.assert_eq(usage.input_tokens, 80)
  @debug.assert_eq(usage.output_tokens, 50)
  @debug.assert_eq(usage.cache_read_input_tokens, 80)
  @debug.assert_eq(usage.cache_creation_input_tokens, 20)
  // total_tokens = (input - cache_read) + cache_creation + output = 0+20+50
  @debug.assert_eq(usage.total_tokens, 70)
  @debug.assert_eq(usage.total_is_per_turn, true)
}

// ── Tool Result Formatting Tests ────────────────────────────────────────────

///|
test "format_openai_tool_results" {
  let resp : LlmResponse = {
    content: None,
    tool_calls: Some([@message.ToolCall::new("tc_1", "shell", "{}")]),
    finish_reason: Some("tool_calls"),
    usage: None,
    latency: None,
    reasoning_content: None,
  }
  let results : Map[String, String] = { "tc_1": "file list output" }
  let msgs = format_openai_tool_results(resp, results)
  @debug.assert_eq(msgs.length(), 1)
  assert_true(msgs[0].role == @message.Tool)
  match msgs[0].content {
    @message.Text(text) => @debug.assert_eq(text, "file list output")
    _ => abort("expected text content")
  }
}

///|
test "format_anthropic_tool_results" {
  let resp : LlmResponse = {
    content: None,
    tool_calls: Some([
      @message.ToolCall::new("tu_1", "read_file", "{}"),
      @message.ToolCall::new("tu_2", "shell", "{}"),
    ]),
    finish_reason: Some("tool_calls"),
    usage: None,
    latency: None,
    reasoning_content: None,
  }
  let results : Map[String, String] = {
    "tu_1": "file contents",
    "tu_2": "command output",
  }
  let msgs = format_anthropic_tool_results(resp, results)
  @debug.assert_eq(msgs.length(), 2)
  assert_true(msgs[0].role == @message.Tool)
  assert_true(msgs[1].role == @message.Tool)
}

///|
test "build_anthropic_request_merges_consecutive_tool_results" {
  // Two consecutive tool-result turns for the same assistant turn.
  // Anthropic requires them in a SINGLE user message; the canonical
  // per-message conversion would emit two user messages (protocol
  // violation → 400). Wire snapshot: exactly one user message with two
  // tool_result blocks.
  let assistant_msg : @message.Message = {
    role: @message.Assistant,
    content: @message.Text("searching"),
    tool_calls: Some([
      @message.ToolCall::new("tu_1", "read_file", "{\"path\":\"a\"}"),
      @message.ToolCall::new("tu_2", "shell", "{\"cmd\":\"ls\"}"),
    ]),
    tool_call_id: None,
    name: None,
    reasoning_content: None,
    task_id: None,
    created_at: None,
    system_injected: None,
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
  let messages = [
    assistant_msg,
    @message.Message::tool_result("tu_1", "read_file", "file contents"),
    @message.Message::tool_result("tu_2", "shell", "command output"),
  ]
  let body = build_anthropic_request(
    messages,
    "claude-sonnet-4-5",
    [],
    1024,
    false,
  )
  let obj = match body {
    Object(o) => o
    _ => abort("expected object")
  }
  let msgs = match obj.get("messages") {
    Some(Array(arr)) => arr
    _ => abort("expected messages array")
  }
  // assistant + 1 merged user message (NOT 2 separate tool messages)
  @debug.assert_eq(msgs.length(), 2)
  match msgs[1] {
    Object(user_msg) => {
      assert_eq(user_msg.get("role"), Some("user".to_json()))
      match user_msg.get("content") {
        Some(Array(blocks)) => {
          @debug.assert_eq(blocks.length(), 2)
          for block in blocks {
            match block {
              Object(b) =>
                assert_eq(b.get("type"), Some("tool_result".to_json()))
              _ => abort("expected tool_result block")
            }
          }
        }
        _ => abort("expected content array")
      }
    }
    _ => abort("expected user message object")
  }
}

///|
test "format_tool_results_missing_result" {
  let resp : LlmResponse = {
    content: None,
    tool_calls: Some([@message.ToolCall::new("tc_missing", "shell", "{}")]),
    finish_reason: Some("tool_calls"),
    usage: None,
    latency: None,
    reasoning_content: None,
  }
  let results : Map[String, String] = Map([])
  let msgs = format_openai_tool_results(resp, results)
  @debug.assert_eq(msgs.length(), 1)
  match msgs[0].content {
    @message.Text(text) => assert_true(text.find("missing") is Some(_))
    _ => abort("expected text content")
  }
}

// ── Error Message Extraction Tests ──────────────────────────────────────────

///|
test "extract_error_message_json_error" {
  let msg = extract_error_message("{\"error\":{\"message\":\"Invalid model\"}}")
  @debug.assert_eq(msg, "Invalid model")
}

///|
test "extract_error_message_upstream" {
  let msg = extract_error_message("{\"upstreamMessage\":\"Quota exceeded\"}")
  @debug.assert_eq(msg, "Quota exceeded")
}

///|
test "extract_error_message_plain_string" {
  let msg = extract_error_message("Something went wrong")
  @debug.assert_eq(msg, "Something went wrong")
}

///|
test "extract_error_message_html" {
  let msg = extract_error_message("<html><body>502 Bad Gateway</body></html>")
  assert_true(msg.find("HTML") is Some(_))
}

// ── Prompt Caching Detection Tests ──────────────────────────────────────────

///|
test "supports_prompt_caching_claude_models" {
  let client = Client::new(
    "key",
    "https://api.anthropic.com",
    "claude-sonnet-4-5",
    @config.AnthropicMessages,
  )
  assert_true(client.supports_prompt_caching("claude-sonnet-4-5"))
  assert_true(client.supports_prompt_caching("claude-haiku-4-5"))
  assert_true(client.supports_prompt_caching("claude-opus-4-6"))
}

///|
test "supports_prompt_caching_non_claude" {
  let client = Client::new(
    "key",
    "https://api.openai.com/v1",
    "gpt-4",
    @config.OpenAICompletions,
  )
  assert_false(client.supports_prompt_caching("gpt-4"))
  assert_false(client.supports_prompt_caching("deepseek-chat"))
}

///|
test "supports_prompt_caching_abs_prefix" {
  let client = Client::new(
    "key",
    "https://api.openclacky.com",
    "abs-claude-sonnet-4-6",
    @config.Bedrock,
  )
  assert_true(client.supports_prompt_caching("abs-claude-sonnet-4-6"))
}

// ── URL Building Tests ──────────────────────────────────────────────────────

///|
test "build_url_basic" {
  let client = Client::new(
    "key",
    "https://api.openai.com/v1",
    "gpt-4",
    @config.OpenAICompletions,
  )
  @debug.assert_eq(
    client.build_url("chat/completions"),
    "https://api.openai.com/v1/chat/completions",
  )
}

///|
test "build_url_trailing_slash" {
  let client = Client::new(
    "key",
    "https://api.openai.com/v1/",
    "gpt-4",
    @config.OpenAICompletions,
  )
  @debug.assert_eq(
    client.build_url("chat/completions"),
    "https://api.openai.com/v1/chat/completions",
  )
}

///|
test "anthropic_messages_path_no_v1" {
  @debug.assert_eq(
    anthropic_messages_path("https://api.anthropic.com"),
    "v1/messages",
  )
}

///|
test "anthropic_messages_path_with_v1" {
  @debug.assert_eq(
    anthropic_messages_path("https://openrouter.ai/api/v1"),
    "messages",
  )
}

// ── OpenAI Stream Aggregator Tests ──────────────────────────────────────────

///|
test "openai_aggregator_content" {
  let agg = OpenAiStreamAggregator::new()
  agg.handle("{\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}")
  agg.handle("{\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}")
  agg.handle("{\"choices\":[{\"delta\":{\"content\":\" world\"}}]}")
  agg.handle("{\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}")
  let resp = agg.to_response()
  @debug.assert_eq(resp.content.unwrap(), "Hello world")
  @debug.assert_eq(resp.finish_reason.unwrap(), "stop")
}

///|
test "openai_aggregator_tool_calls" {
  let agg = OpenAiStreamAggregator::new()
  agg.handle(
    "{\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"function\":{\"name\":\"shell\",\"arguments\":\"{\\\"cm\"}}]}}]}",
  )
  agg.handle(
    "{\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"d\\\":\\\"ls\\\"}\"}}]}}]}",
  )
  agg.handle("{\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}")
  let resp = agg.to_response()
  assert_true(resp.has_tool_calls())
  let calls = resp.tool_calls.unwrap()
  @debug.assert_eq(calls.length(), 1)
  @debug.assert_eq(calls[0].function.name, "shell")
  @debug.assert_eq(calls[0].function.arguments, "{\"cmd\":\"ls\"}")
}

///|
test "openai_aggregator_done_sentinel" {
  let agg = OpenAiStreamAggregator::new()
  agg.handle("[DONE]")
  let resp = agg.to_response()
  assert_true(resp.content is None)
}

///|
test "openai_aggregator_usage" {
  let agg = OpenAiStreamAggregator::new()
  agg.handle(
    "{\"choices\":[],\"usage\":{\"prompt_tokens\":100,\"completion_tokens\":50}}",
  )
  let resp = agg.to_response()
  assert_true(resp.usage is Some(_))
  @debug.assert_eq(resp.usage.unwrap().input_tokens, 100)
  @debug.assert_eq(resp.usage.unwrap().output_tokens, 50)
}

// ── Anthropic Stream Aggregator Tests ───────────────────────────────────────

///|
test "anthropic_aggregator_text" {
  let agg = AnthropicStreamAggregator::new()
  agg.handle("message_start", "{\"message\":{\"usage\":{\"input_tokens\":10}}}")
  agg.handle(
    "content_block_start", "{\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
  )
  agg.handle(
    "content_block_delta", "{\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}",
  )
  agg.handle(
    "content_block_delta", "{\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\" there\"}}",
  )
  agg.handle("content_block_stop", "{\"index\":0}")
  agg.handle(
    "message_delta", "{\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":5}}",
  )
  let resp = agg.to_response()
  @debug.assert_eq(resp.content.unwrap(), "Hello there")
  @debug.assert_eq(resp.finish_reason.unwrap(), "stop")
}

///|
test "anthropic_aggregator_tool_use" {
  let agg = AnthropicStreamAggregator::new()
  agg.handle(
    "content_block_start", "{\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"tu_1\",\"name\":\"read_file\"}}",
  )
  agg.handle(
    "content_block_delta", "{\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"path\\\":\\\"/\"}}",
  )
  agg.handle(
    "content_block_delta", "{\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"test.txt\\\"}\"}}",
  )
  agg.handle("content_block_stop", "{\"index\":0}")
  agg.handle(
    "message_delta", "{\"delta\":{\"stop_reason\":\"tool_use\"},\"usage\":{\"output_tokens\":10}}",
  )
  let resp = agg.to_response()
  assert_true(resp.has_tool_calls())
  @debug.assert_eq(resp.finish_reason.unwrap(), "tool_calls")
  let calls = resp.tool_calls.unwrap()
  @debug.assert_eq(calls[0].id, "tu_1")
  @debug.assert_eq(calls[0].function.name, "read_file")
  @debug.assert_eq(calls[0].function.arguments, "{\"path\":\"/test.txt\"}")
}

// ── Usage Helper Tests ──────────────────────────────────────────────────────

///|
test "usage_from_openai" {
  let usage = Usage::from_openai(100, 50, cache_creation=10, cache_read=20)
  @debug.assert_eq(usage.input_tokens, 100)
  @debug.assert_eq(usage.output_tokens, 50)
  @debug.assert_eq(usage.cache_creation_input_tokens, 10)
  @debug.assert_eq(usage.cache_read_input_tokens, 20)
  // total_tokens falls back to prompt+completion, NOT per-turn
  @debug.assert_eq(usage.total_tokens, 150)
  @debug.assert_eq(usage.total_is_per_turn, false)
}

///|
test "usage_from_anthropic" {
  let usage = Usage::from_anthropic(100, 50, cache_creation=10, cache_read=20)
  // Two-convention normalisation: cached_input (30) fits inside raw input
  // (100) → input already includes cache_creation, subtract it → 90.
  @debug.assert_eq(usage.input_tokens, 90)
  @debug.assert_eq(usage.output_tokens, 50)
  @debug.assert_eq(usage.cache_creation_input_tokens, 10)
  @debug.assert_eq(usage.cache_read_input_tokens, 20)
  // total_tokens = (90-20)+10+50 = 130, per-turn
  @debug.assert_eq(usage.total_tokens, 130)
  @debug.assert_eq(usage.total_is_per_turn, true)
}

// ── Bedrock API Key Detection Tests ──────────────────────────────────────────

///|
test "is_bedrock_api_key_absk_prefix" {
  assert_true(is_bedrock_api_key("ABSK1234567890", "some-model"))
}

///|
test "is_bedrock_api_key_abs_model_prefix" {
  assert_true(is_bedrock_api_key("regular-key", "abs-claude-sonnet-4-6"))
}

///|
test "is_bedrock_api_key_not_bedrock" {
  assert_false(is_bedrock_api_key("sk-regular-key", "gpt-4"))
}

///|
test "client_is_bedrock_format_by_api_type" {
  let client = Client::new(
    "regular-key",
    "https://api.openclacky.com",
    "some-model",
    @config.Bedrock,
  )
  assert_true(client.is_bedrock_format())
}

///|
test "client_is_bedrock_format_by_api_key" {
  let client = Client::new(
    "ABSK1234567890",
    "https://api.openclacky.com",
    "some-model",
    @config.OpenAICompletions,
  )
  assert_true(client.is_bedrock_format())
}

///|
test "client_is_bedrock_format_by_model_prefix" {
  let client = Client::new(
    "regular-key",
    "https://api.openclacky.com",
    "abs-claude-sonnet-4-6",
    @config.OpenAICompletions,
  )
  assert_true(client.is_bedrock_format())
}

///|
test "client_not_bedrock_format" {
  let client = Client::new(
    "sk-regular-key",
    "https://api.openai.com/v1",
    "gpt-4",
    @config.OpenAICompletions,
  )
  assert_false(client.is_bedrock_format())
}

///|
test "bedrock_converse_path_format" {
  @debug.assert_eq(
    bedrock_converse_path("abs-claude-sonnet-4-6"),
    "model/abs-claude-sonnet-4-6/converse",
  )
}

// ── Bedrock Request Building Tests ───────────────────────────────────────────

///|
test "build_bedrock_request_separates_system" {
  let messages = [
    @message.Message::system("You are helpful"),
    @message.Message::user("Hello"),
  ]
  let body = build_bedrock_request(
    messages,
    "abs-claude-sonnet-4-6",
    [],
    1024,
    false,
  )
  let obj = match body {
    Object(o) => o
    _ => abort("expected object")
  }
  // System should be in top-level "system" field as [{text: ...}]
  match obj.get("system") {
    Some(Array(arr)) =>
      match arr[0] {
        Object(sys_obj) =>
          match sys_obj.get("text") {
            Some(String(s)) => @debug.assert_eq(s, "You are helpful")
            _ => abort("expected system text")
          }
        _ => abort("expected system object")
      }
    _ => abort("expected system array")
  }
  // Only user message in messages array
  match obj.get("messages") {
    Some(Array(msgs)) => @debug.assert_eq(msgs.length(), 1)
    _ => abort("expected messages array")
  }
  // Should have inferenceConfig, not max_tokens
  match obj.get("inferenceConfig") {
    Some(Object(ic)) =>
      match ic.get("maxTokens") {
        Some(_) => ()
        _ => abort("expected maxTokens in inferenceConfig")
      }
    _ => abort("expected inferenceConfig")
  }
}

///|
test "build_bedrock_request_converts_tools" {
  let tools : Array[Json] = [
    Json::object({
      "type": "function".to_json(),
      "function": Json::object({
        "name": "read_file".to_json(),
        "description": "Read a file".to_json(),
        "parameters": Json::object({ "type": "object".to_json() }),
      }),
    }),
  ]
  let body = build_bedrock_request(
    [@message.Message::user("test")],
    "abs-claude-sonnet-4-6",
    tools,
    1024,
    false,
  )
  let obj = match body {
    Object(o) => o
    _ => abort("expected object")
  }
  match obj.get("toolConfig") {
    Some(Object(tc)) =>
      match tc.get("tools") {
        Some(Array(arr)) => {
          @debug.assert_eq(arr.length(), 1)
          match arr[0] {
            Object(tool) =>
              match tool.get("toolSpec") {
                Some(Object(spec)) => {
                  assert_true(spec.get("name") is Some(_))
                  assert_true(spec.get("inputSchema") is Some(_))
                }
                _ => abort("expected toolSpec")
              }
            _ => abort("expected tool object")
          }
        }
        _ => abort("expected tools array")
      }
    _ => abort("expected toolConfig")
  }
}

///|
test "client_build_request_body_bedrock_dispatch" {
  let client = Client::new(
    "ABSK1234567890",
    "https://api.openclacky.com",
    "abs-claude-sonnet-4-6",
    @config.Bedrock,
  )
  let request : SendRequest = {
    messages: [@message.Message::user("Hello")],
    model: "abs-claude-sonnet-4-6",
    tools: [],
    max_tokens: 1024,
    enable_caching: false,
    reasoning_effort: None,
  }
  let body = client.build_request_body(request)
  let obj = match body {
    Object(o) => o
    _ => abort("expected object")
  }
  // Bedrock uses inferenceConfig, not max_tokens
  assert_true(obj.get("inferenceConfig") is Some(_))
  assert_true(obj.get("max_tokens") is None)
}

// ── Bedrock Response Parsing Tests ───────────────────────────────────────────

///|
test "parse_bedrock_response_text" {
  let raw = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"Hello!\"}]}},\"stopReason\":\"end_turn\",\"usage\":{\"inputTokens\":10,\"outputTokens\":5}}"
  let json = @json.parse(raw)
  let resp = parse_bedrock_response(json)
  @debug.assert_eq(resp.content.unwrap(), "Hello!")
  @debug.assert_eq(resp.finish_reason.unwrap(), "stop")
  assert_true(resp.usage is Some(_))
  @debug.assert_eq(resp.usage.unwrap().input_tokens, 10)
  @debug.assert_eq(resp.usage.unwrap().output_tokens, 5)
}

///|
test "parse_bedrock_response_tool_use" {
  let raw = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"Let me check\"},{\"toolUse\":{\"toolUseId\":\"tu_1\",\"name\":\"shell\",\"input\":{\"cmd\":\"ls\"}}}]}},\"stopReason\":\"tool_use\",\"usage\":{\"inputTokens\":10,\"outputTokens\":5}}"
  let json = @json.parse(raw)
  let resp = parse_bedrock_response(json)
  assert_true(resp.has_tool_calls())
  @debug.assert_eq(resp.finish_reason.unwrap(), "tool_calls")
  let calls = resp.tool_calls.unwrap()
  @debug.assert_eq(calls.length(), 1)
  @debug.assert_eq(calls[0].id, "tu_1")
  @debug.assert_eq(calls[0].function.name, "shell")
  @debug.assert_eq(calls[0].function.arguments, "{\"cmd\":\"ls\"}")
}

///|
test "parse_bedrock_response_max_tokens" {
  let raw = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"partial\"}]}},\"stopReason\":\"max_tokens\",\"usage\":{\"inputTokens\":5,\"outputTokens\":100}}"
  let json = @json.parse(raw)
  let resp = parse_bedrock_response(json)
  @debug.assert_eq(resp.finish_reason.unwrap(), "length")
}

///|
test "parse_bedrock_response_cache_usage" {
  let raw = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"cached\"}]}},\"stopReason\":\"end_turn\",\"usage\":{\"inputTokens\":20,\"outputTokens\":50,\"cacheReadInputTokens\":80,\"cacheWriteInputTokens\":10}}"
  let json = @json.parse(raw)
  let resp = parse_bedrock_response(json)
  let usage = resp.usage.unwrap()
  // Bedrock: prompt_tokens = inputTokens + cacheReadInputTokens = 20 + 80 = 100
  @debug.assert_eq(usage.input_tokens, 100)
  @debug.assert_eq(usage.output_tokens, 50)
  @debug.assert_eq(usage.cache_read_input_tokens, 80)
  @debug.assert_eq(usage.cache_creation_input_tokens, 10)
}

///|
test "client_parse_response_bedrock_dispatch" {
  let client = Client::new(
    "ABSK1234567890",
    "https://api.openclacky.com",
    "abs-claude-sonnet-4-6",
    @config.Bedrock,
  )
  let raw = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"Hi\"}]}},\"stopReason\":\"end_turn\",\"usage\":{\"inputTokens\":5,\"outputTokens\":3}}"
  let json = @json.parse(raw)
  let resp = client.parse_response(json)
  @debug.assert_eq(resp.content.unwrap(), "Hi")
  @debug.assert_eq(resp.finish_reason.unwrap(), "stop")
}

// ── Bedrock Tool Result Formatting Tests ─────────────────────────────────────

///|
test "format_bedrock_tool_results" {
  let resp : LlmResponse = {
    content: None,
    tool_calls: Some([@message.ToolCall::new("tu_1", "shell", "{}")]),
    finish_reason: Some("tool_calls"),
    usage: None,
    latency: None,
    reasoning_content: None,
  }
  let results : Map[String, String] = { "tu_1": "command output" }
  let msgs = format_bedrock_tool_results(resp, results)
  @debug.assert_eq(msgs.length(), 1)
  assert_true(msgs[0].role == @message.Tool)
  match msgs[0].content {
    @message.Text(text) => @debug.assert_eq(text, "command output")
    _ => abort("expected text content")
  }
}

///|
test "client_api_path_bedrock" {
  let client = Client::new(
    "ABSK1234567890",
    "https://api.openclacky.com",
    "abs-claude-sonnet-4-6",
    @config.Bedrock,
  )
  @debug.assert_eq(client.api_path(), "model/abs-claude-sonnet-4-6/converse")
}

// ── Bedrock Stream Aggregator Tests ──────────────────────────────────────────

///|
test "bedrock_aggregator_text" {
  let agg = BedrockStreamAggregator::new()
  agg.handle("messageStart", "{\"role\":\"assistant\"}")
  agg.handle("contentBlockStart", "{\"contentBlockIndex\":0,\"start\":{}}")
  agg.handle(
    "contentBlockDelta", "{\"contentBlockIndex\":0,\"delta\":{\"text\":\"Hello\"}}",
  )
  agg.handle(
    "contentBlockDelta", "{\"contentBlockIndex\":0,\"delta\":{\"text\":\" there\"}}",
  )
  agg.handle("contentBlockStop", "{\"contentBlockIndex\":0}")
  agg.handle("messageStop", "{\"stopReason\":\"end_turn\"}")
  agg.handle("metadata", "{\"usage\":{\"inputTokens\":10,\"outputTokens\":5}}")
  let resp = agg.to_response()
  @debug.assert_eq(resp.content.unwrap(), "Hello there")
  @debug.assert_eq(resp.finish_reason.unwrap(), "stop")
  assert_true(resp.usage is Some(_))
  @debug.assert_eq(resp.usage.unwrap().input_tokens, 10)
  @debug.assert_eq(resp.usage.unwrap().output_tokens, 5)
}

///|
test "bedrock_aggregator_tool_use" {
  let agg = BedrockStreamAggregator::new()
  agg.handle("messageStart", "{\"role\":\"assistant\"}")
  agg.handle(
    "contentBlockStart", "{\"contentBlockIndex\":0,\"start\":{\"toolUse\":{\"toolUseId\":\"tu_1\",\"name\":\"read_file\"}}}",
  )
  agg.handle(
    "contentBlockDelta", "{\"contentBlockIndex\":0,\"delta\":{\"toolUse\":{\"input\":\"{\\\"path\\\":\\\"/\"}}}",
  )
  agg.handle(
    "contentBlockDelta", "{\"contentBlockIndex\":0,\"delta\":{\"toolUse\":{\"input\":\"test.txt\\\"}\"}}}",
  )
  agg.handle("contentBlockStop", "{\"contentBlockIndex\":0}")
  agg.handle("messageStop", "{\"stopReason\":\"tool_use\"}")
  agg.handle("metadata", "{\"usage\":{\"inputTokens\":10,\"outputTokens\":5}}")
  let resp = agg.to_response()
  assert_true(resp.has_tool_calls())
  @debug.assert_eq(resp.finish_reason.unwrap(), "tool_calls")
  let calls = resp.tool_calls.unwrap()
  @debug.assert_eq(calls[0].id, "tu_1")
  @debug.assert_eq(calls[0].function.name, "read_file")
  @debug.assert_eq(calls[0].function.arguments, "{\"path\":\"/test.txt\"}")
}

///|
test "bedrock_aggregator_cache_usage" {
  let agg = BedrockStreamAggregator::new()
  agg.handle("messageStart", "{\"role\":\"assistant\"}")
  agg.handle("contentBlockStart", "{\"contentBlockIndex\":0,\"start\":{}}")
  agg.handle(
    "contentBlockDelta", "{\"contentBlockIndex\":0,\"delta\":{\"text\":\"Hi\"}}",
  )
  agg.handle("contentBlockStop", "{\"contentBlockIndex\":0}")
  agg.handle("messageStop", "{\"stopReason\":\"end_turn\"}")
  agg.handle(
    "metadata", "{\"usage\":{\"inputTokens\":20,\"outputTokens\":50,\"cacheReadInputTokens\":80,\"cacheWriteInputTokens\":10}}",
  )
  let resp = agg.to_response()
  let usage = resp.usage.unwrap()
  // Bedrock: prompt_tokens = inputTokens + cacheReadInputTokens = 20 + 80 = 100
  @debug.assert_eq(usage.input_tokens, 100)
  @debug.assert_eq(usage.output_tokens, 50)
  @debug.assert_eq(usage.cache_read_input_tokens, 80)
  @debug.assert_eq(usage.cache_creation_input_tokens, 10)
}

///|
test "extract_error_code: string code from error.code" {
  let body = "{\"error\":{\"code\":\"insufficient_credit\",\"message\":\"Out of credits\"}}"
  @debug.assert_eq(extract_error_code(body), Some("insufficient_credit"))
}

///|
test "extract_error_code: numeric code from error.code" {
  let body = "{\"error\":{\"code\":402,\"message\":\"Payment required\"}}"
  @debug.assert_eq(extract_error_code(body), Some("402"))
}

///|
test "extract_error_code: fallback to error.type" {
  let body = "{\"error\":{\"type\":\"rate_limit_error\",\"message\":\"Too many requests\"}}"
  @debug.assert_eq(extract_error_code(body), Some("rate_limit_error"))
}

///|
test "extract_error_code: no code present" {
  let body = "{\"error\":{\"message\":\"Something went wrong\"}}"
  @debug.assert_eq(extract_error_code(body), None)
}

///|
test "extract_error_code: invalid json" {
  @debug.assert_eq(extract_error_code("not json"), None)
}

///|
test "extract_error_code: no error object" {
  let body = "{\"message\":\"Something went wrong\"}"
  @debug.assert_eq(extract_error_code(body), None)
}

///|
test "client_api_model_for_volcengine_payg_alias" {
  let client = Client::new(
    "sk-x",
    "https://ark.cn-beijing.volces.com/api/v3",
    "doubao-seed-2.1-pro",
    @config.OpenAICompletions,
    provider_id=Some("volcengine-ark"),
  )
  // Display name → versioned id on the pay-as-you-go endpoint
  @debug.assert_eq(
    client.api_model_for("doubao-seed-2.1-pro"),
    "doubao-seed-2-1-pro-260628",
  )
  // Model absent from alias table passes through
  @debug.assert_eq(
    client.api_model_for("doubao-1.5-pro-256k"),
    "doubao-1.5-pro-256k",
  )
  // The request body carries the versioned id
  let req : SendRequest = {
    messages: [@message.Message::user("hi")],
    model: "doubao-seed-2.1-pro",
    tools: [],
    max_tokens: 1024,
    enable_caching: false,
    reasoning_effort: None,
  }
  let body = client.build_request_body(req)
  match body {
    Object(o) =>
      @debug.assert_eq(
        o.get("model").unwrap().stringify(),
        "\"doubao-seed-2-1-pro-260628\"",
      )
    _ => abort("expected object")
  }
}

///|
test "client_api_model_for_non_alias_provider_unchanged" {
  let client = Client::new(
    "sk-x",
    "https://api.openai.com/v1",
    "gpt-4o",
    @config.OpenAICompletions,
  )
  @debug.assert_eq(client.api_model_for("gpt-4o"), "gpt-4o")
}

///|
test "client_anthropic_headers_kimi_coding_ua" {
  let kimi = Client::new(
    "sk-x",
    "https://api.kimi.com/coding",
    "kimi-for-coding",
    @config.AnthropicMessages,
    provider_id=Some("kimi-coding"),
  )
  let headers = kimi.anthropic_headers()
  @debug.assert_eq(
    headers.get("User-Agent").unwrap(),
    "claude-cli/1.0.51 (external, cli)",
  )
  // Non-kimi providers keep no special UA
  let openai = Client::new(
    "sk-x",
    "https://api.openai.com/v1",
    "gpt-4o",
    @config.OpenAICompletions,
  )
  let headers2 = openai.anthropic_headers()
  @debug.assert_eq(headers2.get("User-Agent"), None)
}
