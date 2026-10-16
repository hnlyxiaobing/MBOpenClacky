///| White-box tests for the /ws frame-level gate (`ws_frame_gate`).
///
/// These lock the malformed-frame invariant inside the CI test step: a frame
/// that fails the gate must be answered with an `error` event and must never
/// be routed to a handler that can start a billed LLM run. The end-to-end
/// journey `web_ws_malformed_frames_rejected` covers the same contract over a
/// real socket, but it is not part of the CI gates, so silently reverting a
/// guard to `return` (no error frame at all) would only be caught locally.

///|
/// Raising helpers: `abort()` fast-fails the native binary with
/// `0xc0000409` and only reports the active test location, which the CI
/// annotation step cannot grep. `fail`/`assert_eq` produce the ordinary
/// `test <file>:<line> ("<name>") failed: ...` line instead.
fn assert_rejects(text : String, expected : String) -> Unit raise {
  match ws_frame_gate(text) {
    WsFrameReject(reason) => assert_eq(reason, expected)
    WsFrameRoute(_, _) => fail("frame was routed, expected rejection: " + text)
  }
}

///|
fn assert_routes(text : String) -> Unit raise {
  match ws_frame_gate(text) {
    WsFrameRoute(_, _) => ()
    WsFrameReject(reason) =>
      fail("frame was rejected, expected routing: \{text} -> \{reason}")
  }
}

///|
test "ws frame gate: unparsable text is an invalid JSON frame" {
  assert_rejects("not json at all", "invalid JSON frame")
  assert_rejects("", "invalid JSON frame")
  assert_rejects("{", "invalid JSON frame")
}

///|
test "ws frame gate: json that is not an object is rejected" {
  assert_rejects("[]", "expected JSON object")
  assert_rejects("42", "expected JSON object")
  assert_rejects("\"message\"", "expected JSON object")
  assert_rejects("null", "expected JSON object")
}

///|
test "ws frame gate: a missing type never defaults to message" {
  // The invariant this whole guard exists for: `{}` must not become a chat
  // message, or every malformed frame would start a billed run.
  assert_rejects("{}", "missing message type")
  assert_rejects("{\"type\":null}", "missing message type")
  assert_rejects("{\"type\":123}", "missing message type")
  assert_rejects("{\"type\":[\"message\"]}", "missing message type")
  assert_rejects("{\"content\":\"hi\"}", "missing message type")
}

///|
test "ws frame gate: an unknown type is rejected and echoed verbatim" {
  assert_rejects(
    "{\"type\":\"bogus_kind\"}", "unknown message type: bogus_kind",
  )
  assert_rejects("{\"type\":\"\"}", "unknown message type: ")
  // Case and separators are significant on the wire.
  assert_rejects("{\"type\":\"Message\"}", "unknown message type: Message")
  assert_rejects(
    "{\"type\":\"edit-message\"}", "unknown message type: edit-message",
  )
}

///|
test "ws frame gate: every known upstream type routes" {
  for
    t in [
      "subscribe", "message", "edit_message", "interrupt", "confirmation", "feedback",
      "run_task", "ping", "list_sessions",
    ] {
    assert_routes("{ \"type\": \"\{t}\" }")
  }
}

///|
test "ws frame gate: routing is shape-only, field checks stay downstream" {
  // The gate answers "may this frame reach a handler", not "is the payload
  // complete": empty content / missing session_id are per-handler guards
  // (asserted end-to-end by the journey). Locking the split here keeps a
  // future change from moving the empty-content check up and dropping it.
  assert_routes("{\"type\":\"message\",\"content\":\"\"}")
  assert_routes("{\"type\":\"message\"}")
  assert_routes("{\"type\":\"interrupt\"}")
}
