///| mock_llm_server 的白盒单测：畸形帧逐字节透传 + finish_reason 覆盖。
///
/// 对应 spec 2026-08-18_22_p6-e2e-link-layer-completion.md 任务包 1：
/// - malformed 类型：frames 原始帧字符串数组逐字节透传（不经 sse()/chunk_payload）。
/// - finish_reason 字段：content/tool_calls 收尾帧取该值（缺省 stop / tool_calls）。

///|
/// 自测 011 剧本依赖的畸形帧序列：逐字节透传，末尾仍补 [DONE]（与其余类型一致）。
async test "mock malformed 帧逐字节透传" {
  let server = MockLlmServer::new([])
  let resp = Json::object({
    "type": "malformed".to_json(),
    "frames": Json::array([
      "data: {bad json\n\n".to_json(),
      "garbage line\n\n".to_json(),
      "data: {\"choices\":[{\"delta\":{\"content\":\"trunc\"\n\n".to_json(),
    ]),
  })
  let frames = server.build_sse(resp, "mock-model")
  @debug.assert_eq(frames.length(), 4)
  @debug.assert_eq(frames[0], "data: {bad json\n\n")
  @debug.assert_eq(frames[1], "garbage line\n\n")
  @debug.assert_eq(
    frames[2],
    "data: {\"choices\":[{\"delta\":{\"content\":\"trunc\"\n\n",
  )
  @debug.assert_eq(frames[3], "data: [DONE]\n\n")
}

///|
/// 自测 finish_reason 覆盖：content 收尾帧取覆盖值、tool_calls 收尾帧取覆盖值
/// （012 的 stop+tool_calls 刺激）、缺省行为不变（content 仍为 stop）。
async test "mock finish_reason 覆盖 content/tool_calls 收尾帧" {
  let server = MockLlmServer::new([])
  // content + finish_reason=length：收尾帧应携带 length
  let c_resp = Json::object({
    "type": "content".to_json(),
    "text": "hi".to_json(),
    "finish_reason": "length".to_json(),
  })
  let c_frames = server.build_sse(c_resp, "mock-model")
  assert_true(
    c_frames[c_frames.length() - 2].contains("\"finish_reason\":\"length\""),
  )
  // tool_calls + finish_reason=stop：构成 012 刺激
  let t_resp = Json::object({
    "type": "tool_calls".to_json(),
    "tool_calls": Json::array([
      Json::object({
        "id": "call_1".to_json(),
        "name": "read_file".to_json(),
        "arguments": Json::object({ "path": "note.txt".to_json() }),
      }),
    ]),
    "finish_reason": "stop".to_json(),
  })
  let t_frames = server.build_sse(t_resp, "mock-model")
  assert_true(
    t_frames[t_frames.length() - 2].contains("\"finish_reason\":\"stop\""),
  )
  // 缺省行为不变：content 无 finish_reason 字段时收尾帧仍为 stop
  let d_resp = Json::object({
    "type": "content".to_json(),
    "text": "hi".to_json(),
  })
  let d_frames = server.build_sse(d_resp, "mock-model")
  assert_true(
    d_frames[d_frames.length() - 2].contains("\"finish_reason\":\"stop\""),
  )
}
