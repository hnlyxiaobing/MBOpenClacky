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

///|
test "openai_agg_missing_index_appends_not_slot0" {
  let agg = OpenAiStreamAggregator::new()
  // A delta without an index must append a new tool call, never merge
  // into slot 0 (Ruby: `tc["index"] || @tool_calls.size`).
  agg.handle(
    "{\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"a\",\"function\":{\"name\":\"f1\",\"arguments\":\"{}\"}}]}}]}",
  )
  agg.handle(
    "{\"choices\":[{\"delta\":{\"tool_calls\":[{\"function\":{\"arguments\":\"{\\\"x\\\":1}\"}}]}}]}",
  )
  let resp = agg.to_response()
  match resp.tool_calls {
    Some(calls) => {
      assert_eq(calls.length(), 2)
      assert_eq(calls[0].id, "a")
      assert_eq(calls[0].function.name, "f1")
      assert_eq(calls[1].id, "")
      assert_eq(calls[1].function.arguments, "{\"x\":1}")
    }
    None => assert_true(false)
  }
}

///|
test "openai_agg_extra_content_preserved" {
  let agg = OpenAiStreamAggregator::new()
  agg.handle(
    "{\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"t1\",\"function\":{\"name\":\"g\",\"arguments\":\"{}\"},\"extra_content\":{\"thought_signature\":\"sig-1\"}}]}}]}",
  )
  let resp = agg.to_response()
  match resp.tool_calls {
    Some(calls) =>
      match calls[0].extra_content {
        Some(ec) =>
          assert_eq(
            (if ec is Object(obj) { obj.get("thought_signature") } else { None }) is Some(String(_)),
            true,
          )
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "anthropic_agg_blocks_by_index_out_of_order" {
  let agg = AnthropicStreamAggregator::new()
  // content_block_start with an explicit index 2 (out of order) must not
  // be dropped; deltas addressing it must land on the right block.
  agg.handle(
    "content_block_start", "{\"index\":2,\"content_block\":{\"type\":\"text\"}}",
  )
  agg.handle(
    "content_block_delta", "{\"index\":2,\"delta\":{\"type\":\"text_delta\",\"text\":\"three\"}}",
  )
  agg.handle(
    "content_block_delta", "{\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"one\"}}",
  )
  // Unknown index auto-creates a block instead of dropping the delta.
  agg.handle(
    "content_block_delta", "{\"index\":5,\"delta\":{\"type\":\"text_delta\",\"text\":\"six\"}}",
  )
  let resp = agg.to_response()
  match resp.content {
    Some(c) => assert_eq(c, "onethreesix")
    None => assert_true(false)
  }
}

///|
test "anthropic_agg_usage_merges_input_side" {
  let agg = AnthropicStreamAggregator::new()
  agg.handle(
    "message_start", "{\"message\":{\"usage\":{\"input_tokens\":10,\"output_tokens\":5}}}",
  )
  // A message_delta that re-emits input tokens must accumulate, not replace.
  agg.handle(
    "message_delta", "{\"delta\":{},\"usage\":{\"input_tokens\":2,\"output_tokens\":1}}",
  )
  let resp = agg.to_response()
  match resp.usage {
    Some(u) => {
      assert_eq(u.input_tokens, 12)
      assert_eq(u.output_tokens, 6)
    }
    None => assert_true(false)
  }
}

///|
test "openai_agg_usage_prompt_details_cached" {
  let agg = OpenAiStreamAggregator::new()
  agg.handle(
    "{\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":3,\"prompt_tokens_details\":{\"cached_tokens\":4}}}",
  )
  let resp = agg.to_response()
  match resp.usage {
    Some(u) => {
      assert_eq(u.input_tokens, 10)
      assert_eq(u.cache_read_input_tokens, 4)
      assert_eq(u.total_tokens, 13)
      assert_eq(u.total_is_per_turn, false)
    }
    None => assert_true(false)
  }
}

// ── Streaming pipeline tests (#4) ───────────────────────────────────────────

///|
test "openai handle_delta returns content delta" {
  let agg = OpenAiStreamAggregator::new()
  @debug.assert_eq(
    agg.handle_delta("{\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}"),
    "Hello",
  )
  // Role-only and finish frames carry no visible delta.
  @debug.assert_eq(
    agg.handle_delta("{\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}"),
    "",
  )
  @debug.assert_eq(
    agg.handle_delta(
      "{\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}",
    ),
    "",
  )
  @debug.assert_eq(agg.handle_delta("[DONE]"), "")
  @debug.assert_eq(agg.handle_delta("not valid json"), "")
  // Aggregation still works alongside delta reporting.
  ignore(
    agg.handle_delta("{\"choices\":[{\"delta\":{\"content\":\" world\"}}]}"),
  )
  let resp = agg.to_response()
  @debug.assert_eq(resp.content, Some("Hello world"))
}

///|
test "anthropic handle_delta returns text delta only" {
  let agg = AnthropicStreamAggregator::new()
  @debug.assert_eq(
    agg.handle_delta(
      "content_block_start", "{\"content_block\":{\"type\":\"text\"}}",
    ),
    "",
  )
  @debug.assert_eq(
    agg.handle_delta(
      "content_block_delta", "{\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi\"}}",
    ),
    "Hi",
  )
  // Thinking deltas are accumulated but NOT reported as visible text.
  @debug.assert_eq(
    agg.handle_delta(
      "content_block_delta", "{\"index\":0,\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"hmm\"}}",
    ),
    "",
  )
  @debug.assert_eq(
    agg.handle_delta(
      "message_delta", "{\"delta\":{\"stop_reason\":\"end_turn\"}}",
    ),
    "",
  )
  let resp = agg.to_response()
  @debug.assert_eq(resp.content, Some("Hihmm"))
}

///|
test "sse_byte_pump reassembles frames split across chunks" {
  let pump = SseBytePump::new()
  let bytes = @utf8.encode("data: {\"a\":1}\n\ndata: {\"b\":2}\n\n")
  // Split at an awkward position (inside the first frame).
  @debug.assert_eq(pump.feed(bytes[:7].to_owned()).length(), 0)
  let frames = pump.feed(bytes[7:].to_owned())
  @debug.assert_eq(frames.length(), 2)
  @debug.assert_eq(frames[0].data, "{\"a\":1}")
  @debug.assert_eq(frames[1].data, "{\"b\":2}")
  @debug.assert_eq(pump.finish().length(), 0)
}

///|
test "sse_byte_pump survives utf8 split across chunks" {
  let pump = SseBytePump::new()
  let bytes = @utf8.encode("data: 你好\n\n")
  // Split inside the multi-byte character (byte 7 is mid-sequence:
  // "data: " is 6 bytes, 你 is 3 bytes starting at offset 6).
  @debug.assert_eq(pump.feed(bytes[:7].to_owned()).length(), 0)
  let frames = pump.feed(bytes[7:].to_owned())
  @debug.assert_eq(frames.length(), 1)
  @debug.assert_eq(frames[0].data, "你好")
}

///|
test "sse_byte_pump drops keep-alive comment frames" {
  let pump = SseBytePump::new()
  let frames = pump.feed(@utf8.encode(": keep-alive\n\ndata: x\n\n"))
  @debug.assert_eq(frames.length(), 1)
  @debug.assert_eq(frames[0].data, "x")
}

///|
test "sse_byte_pump finish discards unterminated trailing frame" {
  let pump = SseBytePump::new()
  @debug.assert_eq(pump.feed(@utf8.encode("data: tail")).length(), 0)
  // Ruby keeps incomplete trailing data in the buffer and drops it at
  // end-of-stream; finish() must not emit a half frame.
  @debug.assert_eq(pump.finish().length(), 0)
}

///|
test "sse_byte_pump handles CRLF line endings" {
  let pump = SseBytePump::new()
  let frames = pump.feed(@utf8.encode("event: x\r\ndata: {\"a\":1}\r\n\r\n"))
  @debug.assert_eq(frames.length(), 1)
  @debug.assert_eq(frames[0].event, "x")
  @debug.assert_eq(frames[0].data, "{\"a\":1}")
}

///|
test "parse_sse_frames handles CRLF fixtures" {
  let text = "event: message\r\ndata: {\"b\":2}\r\n\r\n"
  let frames = parse_sse_frames(text)
  @debug.assert_eq(frames.length(), 1)
  @debug.assert_eq(frames[0].event, "message")
  @debug.assert_eq(frames[0].data, "{\"b\":2}")
}

///|
test "sse_byte_pump feed_string matches feed" {
  let pump = SseBytePump::new()
  let frames = pump.feed_string("data: hello\n\n")
  @debug.assert_eq(frames.length(), 1)
  @debug.assert_eq(frames[0].data, "hello")
}
