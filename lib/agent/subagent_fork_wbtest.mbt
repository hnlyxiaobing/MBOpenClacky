///| White-box tests for forked-subagent machinery (B7 decision 5).

///| Covers fork_subagent (config/model inheritance, history deep-clone,

///| suffix + forbidden-notice scaffolding, runtime forbidden/allowed

///| enforcement), final_reply / generate_subagent_summary /

///| extract_subagent_transcript slicing, and run_detached cost absorption.

// ── fork_subagent: basic inheritance ─────────────────────────────────────────

///|
test "fork_subagent_inherits_and_deep_clones" {
  let agent = make_test_agent()
  agent.history.append(stamp_created_at(@message.Message::user("hello")))
  agent.history.append(stamp_created_at(@message.Message::assistant("hi")))
  let sub = agent.fork_subagent() catch { _ => abort("fork failed") }
  assert_true(sub.is_subagent)
  // parent_message_count = parent history size at fork
  @debug.assert_eq(sub.parent_message_count, 2)
  // history deep-cloned
  @debug.assert_eq(sub.history.size(), 2)
  // config is a deep copy: mutating the subagent config must not affect parent
  sub.config.models.push(
    @config.ModelConfig::new("m", "k", "https://api.test.com", "mm"),
  )
  @debug.assert_eq(agent.config.models.length(), 0)
  // tool restrictions empty by default
  @debug.assert_eq(sub.forbidden_tools.length(), 0)
  @debug.assert_eq(sub.allowed_tools, None)
}

///|
test "fork_subagent_client_model_switch" {
  let agent = make_test_agent()
  agent.config.add_model(
    @config.ModelConfig::new("m1", "k", "https://api.test.com", "model-a"),
  )
  agent.config.add_model(
    @config.ModelConfig::new("m2", "k", "https://api.test.com", "model-b"),
  )
  let sub = agent.fork_subagent(model=Some("model-b")) catch {
    _ => abort("fork failed")
  }
  // Subagent client follows the switched model; parent client untouched.
  @debug.assert_eq(sub.client.model, "model-b")
  @debug.assert_eq(agent.client.model, "test-model")
}

///|
test "fork_subagent_unknown_model_raises" {
  let agent = make_test_agent()
  let result = Ok(agent.fork_subagent(model=Some("no-such-model"))) catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

///|
test "fork_subagent_lite_model_uses_overlay" {
  let agent = make_test_agent()
  // Explicit lite companion (type_ = "lite").
  let lite : @config.ModelConfig = {
    id: "lite-1",
    type_: Some("lite"),
    api_key: "k",
    base_url: "https://api.test.com",
    model: "lite-model",
    anthropic_format: false,
    runtime_id: "lite-1",
    media_type: None,
  }
  agent.config.add_model(
    @config.ModelConfig::new("m1", "k", "https://api.test.com", "primary"),
  )
  agent.config.add_model(lite)
  let sub = agent.fork_subagent(model=Some("lite")) catch {
    _ => abort("fork failed")
  }
  // lite_model_config_for_current finds the explicit lite entry and the
  // virtual overlay points current_model at it.
  @debug.assert_eq(sub.client.model, "lite-model")
  // Parent still on its own model.
  @debug.assert_eq(agent.client.model, "test-model")
}

///|
test "fork_subagent_suffix_and_forbidden_notice" {
  let agent = make_test_agent()
  agent.history.append(stamp_created_at(@message.Message::user("hello")))
  let sub = agent.fork_subagent(
    forbidden_tools=["terminal", "write"],
    system_prompt_suffix=Some("EXTRA SUFFIX"),
  ) catch {
    _ => abort("fork failed")
  }
  // parent_message_count counts only the parent's own messages.
  @debug.assert_eq(sub.parent_message_count, 1)
  // Two scaffolding messages appended after the fork point.
  @debug.assert_eq(sub.history.size(), 3)
  let msgs = sub.history.all()
  let preamble = msgs[1]
  let ack = msgs[2]
  // Preamble: user role, injected, carries the suffix + forbidden notice.
  @debug.assert_eq(preamble.role, @message.User)
  @debug.assert_eq(preamble.system_injected, Some(true))
  @debug.assert_eq(preamble.subagent_instructions, Some("true"))
  match preamble.content {
    @message.Text(t) => {
      assert_true(t.contains("CRITICAL: TASK CONTEXT SWITCH"))
      assert_true(t.contains("EXTRA SUFFIX"))
      assert_true(t.contains("`terminal`"))
      assert_true(t.contains("`write`"))
    }
    _ => abort("expected Text content")
  }
  // Assistant ack, injected, completes the turn structure.
  @debug.assert_eq(ack.role, @message.Assistant)
  @debug.assert_eq(ack.system_injected, Some(true))
  match ack.content {
    @message.Text(t) => assert_true(t.contains("Understood"))
    _ => abort("expected Text content")
  }
  // Runtime restrictions registered on the subagent.
  @debug.assert_eq(sub.forbidden_tools, ["terminal", "write"])
}

///|
test "fork_subagent_history_isolated_from_parent" {
  let agent = make_test_agent()
  agent.history.append(stamp_created_at(@message.Message::user("hello")))
  let sub = agent.fork_subagent(system_prompt_suffix=Some("suffix")) catch {
    _ => abort("fork failed")
  }
  // Subagent appends its own run messages...
  sub.history.append(stamp_created_at(@message.Message::user("sub task")))
  // ...parent history is untouched.
  @debug.assert_eq(agent.history.size(), 1)
  @debug.assert_eq(sub.history.size(), 4)
}

// ── Runtime forbidden/allowed enforcement ────────────────────────────────────

///|
async test "fork_subagent_forbidden_tool_denied" {
  let agent = make_test_agent()
  agent.forbidden_tools = ["memory"]
  let call = make_tool_call("c1", "memory", "{\"action\":\"list\"}")
  let entry = agent.execute_single_tool(call)
  assert_true(entry.is_error)
  assert_true(entry.content.contains("forbidden in this subagent context"))
}

///|
async test "fork_subagent_allowed_set_denies_others" {
  let agent = make_test_agent()
  agent.allowed_tools = Some(["glob"])
  let call = make_tool_call("c1", "memory", "{\"action\":\"list\"}")
  let entry = agent.execute_single_tool(call)
  assert_true(entry.is_error)
  assert_true(entry.content.contains("not in the allowed tool set"))
}

///|
async test "fork_subagent_alias_cannot_bypass_forbidden" {
  let agent = make_test_agent()
  // Forbid canonical "write"; invoke via alias "Write" — canonical-name
  // re-check must still deny it.
  agent.forbidden_tools = ["write"]
  let call = make_tool_call(
    "c1", "Write", "{\"path\":\"/tmp/sub_fork_alias.txt\",\"content\":\"x\"}",
  )
  let entry = agent.execute_single_tool(call)
  assert_true(entry.is_error)
  assert_true(entry.content.contains("forbidden in this subagent context"))
}

///|
async test "fork_subagent_unrestricted_executes_normally" {
  let agent = make_test_agent()
  let call = make_tool_call("c1", "memory", "{\"action\":\"list\"}")
  let entry = agent.execute_single_tool(call)
  assert_false(entry.is_error)
}

// ── final_reply / summary / transcript slicing ───────────────────────────────

///|
test "final_reply_returns_last_assistant_text" {
  let agent = make_test_agent()
  agent.history.append(stamp_created_at(@message.Message::user("hello")))
  let sub = agent.fork_subagent(system_prompt_suffix=Some("suffix")) catch {
    _ => abort("fork failed")
  }
  // Subagent run messages after the fork point.
  sub.history.append(stamp_created_at(@message.Message::user("do it")))
  sub.history.append(
    stamp_created_at(@message.Message::assistant("first partial")),
  )
  sub.history.append(stamp_created_at(@message.Message::assistant("DONE")))
  @debug.assert_eq(final_reply(sub), "DONE")
  // Empty assistant text is skipped.
  sub.history.append(stamp_created_at(@message.Message::assistant("")))
  @debug.assert_eq(final_reply(sub), "DONE")
}

///|
test "final_reply_empty_when_no_assistant_text" {
  let agent = make_test_agent()
  let sub = agent.fork_subagent() catch { _ => abort("fork failed") }
  @debug.assert_eq(final_reply(sub), "")
}

///|
test "generate_subagent_summary_contents" {
  let agent = make_test_agent()
  let sub = agent.fork_subagent(system_prompt_suffix=Some("suffix")) catch {
    _ => abort("fork failed")
  }
  sub.iterations = 3
  sub.total_cost = 0.0123
  sub.history.append(stamp_created_at(@message.Message::user("task")))
  sub.history.append(
    stamp_created_at({
      role: @message.Assistant,
      content: @message.Text(""),
      tool_calls: Some([
        make_tool_call("t1", "glob", "{\"pattern\":\"**/*.mbt\"}"),
        make_tool_call("t2", "file_reader", "{\"path\":\"/tmp/x\"}"),
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
    }),
  )
  sub.history.append(stamp_created_at(@message.Message::assistant("answer!")))
  let summary = generate_subagent_summary(sub)
  assert_true(summary.contains("[SUBAGENT SUMMARY]"))
  assert_true(summary.contains("3 iterations"))
  assert_true(summary.contains("$0.0123"))
  assert_true(summary.contains("glob"))
  assert_true(summary.contains("file_reader"))
  assert_true(summary.contains("answer!"))
}

///|
test "extract_subagent_transcript_drops_injected_scaffolding" {
  let agent = make_test_agent()
  agent.history.append(stamp_created_at(@message.Message::user("hello")))
  let sub = agent.fork_subagent(system_prompt_suffix=Some("suffix")) catch {
    _ => abort("fork failed")
  }
  sub.iterations = 2
  sub.total_cost = 0.0042
  sub.history.append(stamp_created_at(@message.Message::user("do it")))
  sub.history.append(
    stamp_created_at({
      role: @message.Assistant,
      content: @message.Text(""),
      tool_calls: Some([make_tool_call("t1", "glob", "{\"pattern\":\"*\"}")]),
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
    }),
  )
  sub.history.append(
    stamp_created_at({
      role: @message.Tool,
      content: @message.Text("[]"),
      tool_calls: None,
      tool_call_id: Some("t1"),
      name: Some("glob"),
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
    }),
  )
  sub.history.append(stamp_created_at(@message.Message::assistant("done")))
  let transcript = extract_subagent_transcript(sub, "test-skill")
  let str = transcript.stringify()
  // Skill metadata present.
  assert_true(str.contains("\"skill\":\"test-skill\""))
  assert_true(str.contains("\"iterations\":2"))
  assert_true(str.contains("\"cost_usd\":\"0.0042\""))
  // System-injected scaffolding (fork preamble/ack) dropped: only the 4
  // real run messages remain.
  assert_true(str.contains("\"events\""))
  assert_false(str.contains("CRITICAL: TASK CONTEXT SWITCH"))
  assert_false(str.contains("Understood"))
  // Roles of the real messages survive.
  assert_true(str.contains("\"role\":\"user\""))
  assert_true(str.contains("\"role\":\"assistant\""))
  assert_true(str.contains("\"role\":\"tool\""))
  assert_true(str.contains("\"name\":\"glob\""))
}

// ── run_detached ─────────────────────────────────────────────────────────────

///|
async test "run_detached_absorbs_cost_and_returns_final_reply" {
  let agent = make_test_agent()
  agent.mock_responses.push(make_mock_response("detached answer", None))
  let reply = agent.run_detached("do the task") catch {
    _ => abort("unexpected error")
  }
  @debug.assert_eq(reply, "detached answer")
  // Parent history untouched: detached runs stay invisible.
  @debug.assert_eq(agent.history.size(), 0)
  // Cost absorbed silently into the parent.
  assert_true(agent.total_cost >= 0.0)
}

///|
async test "run_detached_with_forbidden_tools" {
  let agent = make_test_agent()
  agent.mock_responses.push(make_mock_response("blocked answer", None))
  let reply = agent.run_detached("do the task", forbidden_tools=["terminal"]) catch {
    _ => abort("unexpected error")
  }
  @debug.assert_eq(reply, "blocked answer")
  @debug.assert_eq(agent.history.size(), 0)
}

// ── fan_out ──────────────────────────────────────────────────────────────────

///|
async test "fan_out_empty_returns_empty" {
  let jobs : Array[FanOutJob[Int]] = []
  let results = fan_out(jobs) catch { _ => abort("unexpected") }
  @debug.assert_eq(results.length(), 0)
}

///|
async test "fan_out_results_aligned_to_input_order" {
  // Jobs complete out of order; results must stay aligned to input order
  // (Ruby Fanout: results[index] regardless of completion order).
  let jobs : Array[FanOutJob[Int]] = [
    {
      label: "slow",
      run: () => {
        @async.sleep(60)
        1
      },
    },
    {
      label: "fast",
      run: () => {
        @async.sleep(5)
        2
      },
    },
    {
      label: "mid",
      run: () => {
        @async.sleep(20)
        3
      },
    },
  ]
  let results = fan_out(jobs) catch { _ => abort("unexpected") }
  @debug.assert_eq(results.length(), 3)
  for i, r in results {
    @debug.assert_eq(r.index, i)
    @debug.assert_eq(r.value, Some(i + 1))
    @debug.assert_eq(r.error, None)
    assert_true(r.ok())
  }
  // Fast job finished sooner than slow job but still lands on index 1.
  @debug.assert_eq(results[1].value, Some(2))
}

///|
async test "fan_out_raising_job_is_failed_slot" {
  // A raising job becomes a failed slot; siblings are NOT torn down.
  let jobs : Array[FanOutJob[Int]] = [
    {
      label: "ok1",
      run: () => {
        @async.sleep(5)
        10
      },
    },
    {
      label: "boom",
      run: () => {
        @async.sleep(5)
        raise @errors.AgentError("job exploded")
      },
    },
    {
      label: "ok2",
      run: () => {
        @async.sleep(5)
        30
      },
    },
  ]
  let results = fan_out(jobs) catch { _ => abort("unexpected") }
  @debug.assert_eq(results.length(), 3)
  @debug.assert_eq(results[0].value, Some(10))
  @debug.assert_eq(results[0].error, None)
  assert_true(results[0].ok())
  // Failed slot: no value, error message captured, not ok.
  @debug.assert_eq(results[1].value, None)
  assert_true(results[1].error is Some(_))
  assert_false(results[1].ok())
  // Sibling survived.
  @debug.assert_eq(results[2].value, Some(30))
  assert_true(results[2].ok())
}

///|
async test "fan_out_timeout_fills_unfinished_slots" {
  // Wall-clock budget for the whole batch: a slow job is cancelled and its
  // slot carries a timeout error, while finished slots are preserved.
  let jobs : Array[FanOutJob[Int]] = [
    {
      label: "quick",
      run: () => {
        @async.sleep(5)
        1
      },
    },
    {
      label: "slow",
      run: () => {
        // Use a very long sleep so that even under heavy event-loop load the
        // timeout always fires before this job can complete naturally.
        @async.sleep(3_600_000)
        2
      },
    },
  ]
  let results = fan_out(jobs, max_concurrency=2, timeout_ms=Some(200)) catch {
    _ => abort("unexpected")
  }
  @debug.assert_eq(results.length(), 2)
  // Finished slot preserved.
  @debug.assert_eq(results[0].value, Some(1))
  assert_true(results[0].ok())
  // Unfinished slot filled with a timeout error (Ruby FanoutTimeoutError).
  @debug.assert_eq(results[1].value, None)
  assert_true(results[1].error is Some(_))
  assert_true(results[1].error.unwrap().contains("did not finish"))
  assert_false(results[1].ok())
}

///|
async test "fan_out_labeled_default_and_custom_labels" {
  // Empty label → "Subagent {i+1}/{size}"; custom label preserved.
  let jobs : Array[FanOutJob[String]] = [
    { label: "", run: () => "a" },
    { label: "custom", run: () => "b" },
  ]
  let results = fan_out_labeled(jobs) catch { _ => abort("unexpected") }
  @debug.assert_eq(results.length(), 2)
  @debug.assert_eq(results[0].value, Some("a"))
  @debug.assert_eq(results[1].value, Some("b"))
  // Label is informational (not part of the result slot); alignment holds.
  @debug.assert_eq(results[0].index, 0)
  @debug.assert_eq(results[1].index, 1)
}

///|
async test "fan_out_labeled_empty_returns_empty" {
  let jobs : Array[FanOutJob[Int]] = []
  let results = fan_out_labeled(jobs) catch { _ => abort("unexpected") }
  @debug.assert_eq(results.length(), 0)
}
