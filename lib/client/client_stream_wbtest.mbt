///| Tests for SSE frame parser and stream aggregators in client/stream.mbt.

// ── parse_sse_frames Tests ──────────────────────────────────────────────────

///|
test "sse_parse_single_frame" {
  let text = "event: message\ndata: hello\n\n"
  let frames = parse_sse_frames(text)
  assert_eq(frames.length(), 1)
  assert_eq(frames[0].event, "message")
  assert_eq(frames[0].data, "hello")
}

///|
test "sse_parse_multiple_frames" {
  let text = "event: a\ndata: 1\n\nevent: b\ndata: 2\n\n"
  let frames = parse_sse_frames(text)
  assert_eq(frames.length(), 2)
  assert_eq(frames[0].event, "a")
  assert_eq(frames[1].event, "b")
  assert_eq(frames[0].data, "1")
  assert_eq(frames[1].data, "2")
}

///|
test "sse_parse_empty_string" {
  let frames = parse_sse_frames("")
  assert_eq(frames.length(), 0)
}

///|
test "sse_parse_default_event_message" {
  let text = "data: hello\n\n"
  let frames = parse_sse_frames(text)
  assert_eq(frames.length(), 1)
  assert_eq(frames[0].event, "message")
  assert_eq(frames[0].data, "hello")
}

///|
test "sse_parse_multi_line_data" {
  let text = "data: line1\ndata: line2\n\n"
  let frames = parse_sse_frames(text)
  assert_eq(frames.length(), 1)
  assert_eq(frames[0].data, "line1\nline2")
}

///|
test "sse_parse_no_terminator" {
  let frames = parse_sse_frames("data: incomplete")
  assert_eq(frames.length(), 0)
}

///|
test "sse_frame_equality" {
  let f1 : SseFrame = { event: "msg", data: "x" }
  let f2 : SseFrame = { event: "msg", data: "x" }
  let f3 : SseFrame = { event: "msg", data: "y" }
  assert_true(f1 == f2)
  assert_true(f1 != f3)
}

// ── OpenAiStreamAggregator Tests ─────────────────────────────────────────────

///|
test "openai_agg_content_accumulation" {
  let agg = OpenAiStreamAggregator::new()
  agg.handle("{\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}")
  agg.handle("{\"choices\":[{\"delta\":{\"content\":\" World\"}}]}")
  let resp = agg.to_response()
  match resp.content {
    Some(c) => assert_eq(c, "Hello World")
    None => assert_true(false)
  }
}

///|
test "openai_agg_done_sentinel_ignored" {
  let agg = OpenAiStreamAggregator::new()
  agg.handle("[DONE]")
  let resp = agg.to_response()
  assert_true(resp.content is None)
}

///|
test "openai_agg_finish_reason" {
  let agg = OpenAiStreamAggregator::new()
  agg.handle("{\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}")
  let resp = agg.to_response()
  @debug.assert_eq(resp.finish_reason, Some("stop"))
}

///|
test "openai_agg_usage_extraction" {
  let agg = OpenAiStreamAggregator::new()
  agg.handle("{\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":20}}")
  let resp = agg.to_response()
  assert_true(resp.usage is Some(_))
}

///|
test "openai_agg_invalid_json_ignored" {
  let agg = OpenAiStreamAggregator::new()
  agg.handle("not valid json")
  agg.handle("{\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}")
  let resp = agg.to_response()
  match resp.content {
    Some(c) => assert_eq(c, "ok")
    None => assert_true(false)
  }
}

///|
test "openai_agg_empty_response" {
  let agg = OpenAiStreamAggregator::new()
  let resp = agg.to_response()
  assert_true(resp.content is None)
  assert_true(resp.tool_calls is None)
}

// ── AnthropicStreamAggregator Tests ─────────────────────────────────────────

///|
test "anthropic_agg_text_accumulation" {
  let agg = AnthropicStreamAggregator::new()
  agg.handle(
    "content_block_start", "{\"index\":0,\"content_block\":{\"type\":\"text\"}}",
  )
  agg.handle(
    "content_block_delta", "{\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}",
  )
  agg.handle(
    "content_block_delta", "{\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\" World\"}}",
  )
  let resp = agg.to_response()
  match resp.content {
    Some(c) => assert_eq(c, "Hello World")
    None => assert_true(false)
  }
}

///|
test "anthropic_agg_message_start_usage" {
  let agg = AnthropicStreamAggregator::new()
  agg.handle(
    "message_start", "{\"message\":{\"usage\":{\"input_tokens\":10,\"output_tokens\":5}}}",
  )
  let resp = agg.to_response()
  assert_true(resp.usage is Some(_))
}

///|
test "anthropic_agg_stop_reason" {
  let agg = AnthropicStreamAggregator::new()
  agg.handle("message_delta", "{\"delta\":{\"stop_reason\":\"end_turn\"}}")
  let resp = agg.to_response()
  @debug.assert_eq(resp.finish_reason, Some("stop"))
}

///|
test "anthropic_agg_empty_response" {
  let agg = AnthropicStreamAggregator::new()
  let resp = agg.to_response()
  assert_true(resp.content is None)
}

///|
test "anthropic_agg_ping_ignored" {
  let agg = AnthropicStreamAggregator::new()
  agg.handle("ping", "{}")
  let resp = agg.to_response()
  assert_true(resp.content is None)
}

///|
test "anthropic_agg_output_tokens_delta" {
  let agg = AnthropicStreamAggregator::new()
  agg.handle("message_delta", "{\"delta\":{},\"usage\":{\"output_tokens\":42}}")
  let resp = agg.to_response()
  assert_true(resp.usage is Some(_))
}
