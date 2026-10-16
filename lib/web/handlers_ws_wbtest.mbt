///| White-box tests for WS Time Machine hook integration (T07).
///
/// Verifies that the web-mode ToolExecuting hook snapshots file content
/// before write-type tools modify files, mirroring the TUI pattern in
/// lib/tui/agent_hooks.mbt.

///|
test "ws time machine: is_file_write_tool matches write tools" {
  assert_true(is_file_write_tool("write"))
  assert_true(is_file_write_tool("edit"))
  assert_true(is_file_write_tool("write_file"))
  assert_true(is_file_write_tool("file_edit"))
  assert_true(is_file_write_tool("create_file"))
  assert_true(is_file_write_tool("patch"))
}

///|
test "ws time machine: is_file_write_tool rejects non-write tools" {
  assert_false(is_file_write_tool("terminal"))
  assert_false(is_file_write_tool("bash"))
  assert_false(is_file_write_tool("read"))
  assert_false(is_file_write_tool("glob"))
  assert_false(is_file_write_tool("grep"))
  assert_false(is_file_write_tool(""))
}

///|
test "ws time machine: json_string_field extracts path" {
  let result = json_string_field("{\"path\":\"/tmp/test.txt\"}", "path")
  assert_true(result == Some("/tmp/test.txt"))
}

///|
test "ws time machine: json_string_field returns none for missing key" {
  let result = json_string_field("{\"command\":\"ls\"}", "path")
  assert_true(result is None)
}

///|
test "ws time machine: json_string_field returns none for invalid json" {
  let result = json_string_field("not json at all", "path")
  assert_true(result is None)
}

///|
test "ws time machine: get_ws_state creates time_machine" {
  let sid = "wbtest-tm-create"
  let state = get_ws_state(sid)
  // Verify time_machine was initialized
  assert_true(state.time_machine.session_id == sid)
  // Clean up
  ws_states.remove(sid)
}

///|
test "ws time machine: record_file_before_change stores snapshot" {
  let sid = "wbtest-tm-record"
  let state = get_ws_state(sid)
  let tm = state.time_machine

  // Start a task (required for record to attach to a snapshot)
  let task_id = tm.start_new_task(Some("test task"))
  assert_true(!task_id.is_empty())

  // Record a file change (file exists, with content)
  tm.record_file_before_change("/tmp/before_test.txt", Some("old content"))

  // Verify the snapshot was recorded
  let history = tm.get_task_history()
  @debug.assert_eq(history.length(), 1)
  @debug.assert_eq(history[0].before_entries.length(), 1)
  @debug.assert_eq(history[0].before_entries[0].path, "/tmp/before_test.txt")
  assert_true(history[0].before_entries[0].content == Some("old content"))
  assert_false(history[0].before_entries[0].is_absent)

  // Clean up
  ws_states.remove(sid)
}

///|
test "ws time machine: record_file_before_change with absent file" {
  let sid = "wbtest-tm-absent"
  let state = get_ws_state(sid)
  let tm = state.time_machine

  ignore(tm.start_new_task(None))

  // Record a file that doesn't exist (content = None)
  tm.record_file_before_change("/tmp/nonexistent_file.mbt", None)

  let history = tm.get_task_history()
  @debug.assert_eq(history[0].before_entries.length(), 1)
  assert_true(history[0].before_entries[0].is_absent)
  assert_true(history[0].before_entries[0].content is None)

  // Clean up
  ws_states.remove(sid)
}

///|
test "ws time machine: record does nothing without active task" {
  let sid = "wbtest-tm-no-task"
  let state = get_ws_state(sid)
  let tm = state.time_machine

  // No start_new_task called - record should be a no-op
  tm.record_file_before_change("/tmp/orphan.txt", Some("content"))

  let history = tm.get_task_history()
  @debug.assert_eq(history.length(), 0)

  // Clean up
  ws_states.remove(sid)
}

///|
test "ws time machine: record skips duplicate path in same task" {
  let sid = "wbtest-tm-dedup"
  let state = get_ws_state(sid)
  let tm = state.time_machine

  ignore(tm.start_new_task(Some("dedup task")))

  // Record the same file twice
  tm.record_file_before_change("/tmp/dedup.txt", Some("v1"))
  tm.record_file_before_change("/tmp/dedup.txt", Some("v2"))

  let history = tm.get_task_history()
  // Only one entry should exist (deduped)
  @debug.assert_eq(history[0].before_entries.length(), 1)
  // The first recording wins
  assert_true(history[0].before_entries[0].content == Some("v1"))

  // Clean up
  ws_states.remove(sid)
}

///|
test "ws time machine: full hook simulation for write tool" {
  let sid = "wbtest-tm-hook-write"
  let state = get_ws_state(sid)
  let tm = state.time_machine

  // Simulate what register_ws_hooks does on ToolExecuting("write", ...)
  ignore(tm.start_new_task(Some("user message")))

  let tool_name = "write"
  let tool_args = "{\"path\":\"/tmp/hook_test.mbt\",\"content\":\"new\"}"

  // Replicate the hook logic
  if is_file_write_tool(tool_name) {
    match json_string_field(tool_args, "path") {
      Some(path) => {
        let content : String? = if @fs.path_exists(path) {
          Some(@fs.read_file_to_string(path) catch { _ => "" })
        } else {
          None
        }
        tm.record_file_before_change(path, content)
      }
      None => ()
    }
  }

  // Verify: file didn't exist, so content should be None (is_absent=true)
  let history = tm.get_task_history()
  @debug.assert_eq(history[0].before_entries.length(), 1)
  @debug.assert_eq(history[0].before_entries[0].path, "/tmp/hook_test.mbt")
  assert_true(history[0].before_entries[0].is_absent)

  // Clean up
  ws_states.remove(sid)
}

///|
test "ws time machine: full hook simulation for non-write tool" {
  let sid = "wbtest-tm-hook-nonwrite"
  let state = get_ws_state(sid)
  let tm = state.time_machine

  ignore(tm.start_new_task(Some("user message")))

  // Simulate ToolExecuting("grep", ...) - should NOT record
  let tool_name = "grep"
  let tool_args = "{\"path\":\"/tmp/some.txt\"}"

  if is_file_write_tool(tool_name) {
    match json_string_field(tool_args, "path") {
      Some(path) => {
        let content : String? = if @fs.path_exists(path) {
          Some(@fs.read_file_to_string(path) catch { _ => "" })
        } else {
          None
        }
        tm.record_file_before_change(path, content)
      }
      None => ()
    }
  }

  // Verify: no snapshot recorded (grep is not a write tool)
  let history = tm.get_task_history()
  @debug.assert_eq(history[0].before_entries.length(), 0)

  // Clean up
  ws_states.remove(sid)
}

// ── F1: mid-run incremental persistence debounce ─────────────────────────────

///|
test "mid_run_persist_due: first boundary saves, bursts collapse" {
  // Never persisted (0) -> the first message boundary is always due, so a
  // run's opening user turn reaches disk immediately.
  assert_true(mid_run_persist_due(0L, 1000000L))
  // Later than the debounce window -> due.
  assert_true(mid_run_persist_due(1000L, 4000L))
  // Inside the window -> collapsed into the previous save.
  assert_false(mid_run_persist_due(1000L, 3999L))
  assert_false(mid_run_persist_due(1000L, 1000L))
  // Clock skew must not produce a negative wait that trips the guard.
  assert_false(mid_run_persist_due(1000L, 500L))
}

// ── F2: pending-card replay on subscribe ─────────────────────────────────────

///|
test "pending replay frames hold broadcast cards until resolved" {
  let sid = "wbtest-replay-cards"
  let state = get_ws_state(sid)
  let conf_id = sid + "-conf-1"
  let fb_id = sid + "-fb-2"
  let conf_frame = @protocol.request_confirmation_frame(
    sid, conf_id, "Allow tool \"terminal\" to execute?",
  )
  let fb_frame = @protocol.request_feedback_frame(
    sid,
    fb_id,
    "which environment?",
    None,
    None,
    [],
  )
  state.pending_confirmation_cards[conf_id] = conf_frame
  state.pending_feedback_cards[fb_id] = fb_frame
  let frames = pending_replay_frames(state)
  @debug.assert_eq(frames.length(), 2)
  // Both cards survive a view-switch re-subscribe...
  assert_true(frames.contains(conf_frame))
  assert_true(frames.contains(fb_frame))
  // ...and each carries the request id the client answers with, so the
  // replayed card resolves against the same pending queue.
  assert_true(conf_frame.contains(conf_id))
  assert_true(fb_frame.contains(fb_id))
  // Resolving the reply must clear the card: a later subscriber must not
  // be offered an already-answered confirmation.
  ignore(state.pending_confirmation_cards.remove(conf_id))
  let remaining = pending_replay_frames(state)
  @debug.assert_eq(remaining.length(), 1)
  assert_true(remaining.contains(fb_frame))
  // Nothing pending -> nothing replayed.
  ignore(state.pending_feedback_cards.remove(fb_id))
  @debug.assert_eq(pending_replay_frames(state).length(), 0)
  ws_states.remove(sid)
}
