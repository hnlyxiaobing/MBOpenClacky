///| Tests for SubAgentHandle, SubAgentConfig, SubAgentStatus, and AgentPool.

///|
test "subagent_status_to_string" {
  @debug.debug_inspect(
    SubAgentStatus::Pending.to_string_value(),
    content=(
      #|"pending"
    ),
  )
  @debug.debug_inspect(
    SubAgentStatus::Running.to_string_value(),
    content=(
      #|"running"
    ),
  )
  @debug.debug_inspect(
    SubAgentStatus::Completed.to_string_value(),
    content=(
      #|"completed"
    ),
  )
  @debug.debug_inspect(
    SubAgentStatus::Failed.to_string_value(),
    content=(
      #|"failed"
    ),
  )
}

///|
test "subagent_handle_new" {
  let cfg : SubAgentConfig = {
    name: "worker",
    model: None,
    allowed_tools: None,
    system_prompt_override: None,
    max_iterations: 10,
  }
  let h = SubAgentHandle::new("sa_1", cfg)
  @debug.debug_inspect(
    h.id,
    content=(
      #|"sa_1"
    ),
  )
  @debug.debug_inspect(h.status, content="Pending")
  @debug.debug_inspect(h.result is None, content="true")
  @debug.debug_inspect(h.error is None, content="true")
  @debug.debug_inspect(h.is_done(), content="false")
}

///|
test "subagent_handle_mark_running" {
  let cfg : SubAgentConfig = {
    name: "runner",
    model: Some("gpt-4"),
    allowed_tools: Some(["read_file", "web_search"]),
    system_prompt_override: Some("Be concise."),
    max_iterations: 5,
  }
  let h = SubAgentHandle::new("sa_2", cfg)
  h.mark_running()
  @debug.debug_inspect(h.status, content="Running")
  @debug.debug_inspect(h.is_done(), content="false")
}

///|
test "subagent_handle_mark_completed" {
  let cfg : SubAgentConfig = {
    name: "completer",
    model: None,
    allowed_tools: None,
    system_prompt_override: None,
    max_iterations: 3,
  }
  let h = SubAgentHandle::new("sa_3", cfg)
  h.mark_running()
  h.mark_completed("Task finished successfully")
  @debug.debug_inspect(h.status, content="Completed")
  @debug.debug_inspect(h.is_done(), content="true")
  match h.result {
    Some(r) =>
      @debug.debug_inspect(
        r,
        content=(
          #|"Task finished successfully"
        ),
      )
    None => fail("Expected a result")
  }
}

///|
test "subagent_handle_mark_failed" {
  let cfg : SubAgentConfig = {
    name: "failer",
    model: None,
    allowed_tools: None,
    system_prompt_override: None,
    max_iterations: 1,
  }
  let h = SubAgentHandle::new("sa_4", cfg)
  h.mark_running()
  h.mark_failed("Timeout exceeded")
  @debug.debug_inspect(h.status, content="Failed")
  @debug.debug_inspect(h.is_done(), content="true")
  match h.error {
    Some(e) =>
      @debug.debug_inspect(
        e,
        content=(
          #|"Timeout exceeded"
        ),
      )
    None => fail("Expected an error")
  }
}

///|
test "agent_pool_new" {
  let pool = AgentPool::new(4, 2)
  @debug.debug_inspect(pool.size(), content="0")
  @debug.debug_inspect(pool.max_running, content="4")
  @debug.debug_inspect(pool.max_idle, content="2")
  @debug.debug_inspect(pool.can_spawn(), content="true")
  @debug.debug_inspect(pool.all_done(), content="true")
}

///|
test "agent_pool_can_spawn_limit" {
  let pool = AgentPool::new(2, 1)
  let cfg : SubAgentConfig = {
    name: "a",
    model: None,
    allowed_tools: None,
    system_prompt_override: None,
    max_iterations: 5,
  }
  let h1 = SubAgentHandle::new("sa_1", cfg)
  h1.mark_running()
  pool.add(h1)
  @debug.debug_inspect(pool.can_spawn(), content="true")

  let cfg2 : SubAgentConfig = {
    name: "b",
    model: None,
    allowed_tools: None,
    system_prompt_override: None,
    max_iterations: 5,
  }
  let h2 = SubAgentHandle::new("sa_2", cfg2)
  h2.mark_running()
  pool.add(h2)
  // Now active_count == 2 == max_running
  @debug.debug_inspect(pool.can_spawn(), content="false")
}

///|
test "agent_pool_add_and_get" {
  let pool = AgentPool::new(4, 2)
  let cfg : SubAgentConfig = {
    name: "worker",
    model: None,
    allowed_tools: None,
    system_prompt_override: None,
    max_iterations: 10,
  }
  let h = SubAgentHandle::new("sa_x", cfg)
  pool.add(h)
  @debug.debug_inspect(pool.size(), content="1")
  let found = pool.get("sa_x")
  @debug.debug_inspect(found is None, content="false")
  match found {
    Some(handle) =>
      @debug.debug_inspect(
        handle.id,
        content=(
          #|"sa_x"
        ),
      )
    None => fail("Expected to find handle")
  }
}

///|
test "agent_pool_active_count" {
  let pool = AgentPool::new(4, 2)
  let cfg : SubAgentConfig = {
    name: "w",
    model: None,
    allowed_tools: None,
    system_prompt_override: None,
    max_iterations: 5,
  }
  let h1 = SubAgentHandle::new("sa_1", cfg)
  h1.mark_running()
  pool.add(h1)
  let h2 = SubAgentHandle::new("sa_2", {
    name: "w2",
    model: None,
    allowed_tools: None,
    system_prompt_override: None,
    max_iterations: 5,
  })
  h2.mark_completed("done")
  pool.add(h2)
  // h1 is Running (active), h2 is Completed (not active)
  @debug.debug_inspect(pool.active_count(), content="1")
}

///|
test "agent_pool_collect_completed" {
  let pool = AgentPool::new(4, 2)
  let h1 = SubAgentHandle::new("sa_1", {
    name: "a",
    model: None,
    allowed_tools: None,
    system_prompt_override: None,
    max_iterations: 5,
  })
  h1.mark_running()
  pool.add(h1)
  let h2 = SubAgentHandle::new("sa_2", {
    name: "b",
    model: None,
    allowed_tools: None,
    system_prompt_override: None,
    max_iterations: 5,
  })
  h2.mark_completed("result")
  pool.add(h2)
  let h3 = SubAgentHandle::new("sa_3", {
    name: "c",
    model: None,
    allowed_tools: None,
    system_prompt_override: None,
    max_iterations: 5,
  })
  h3.mark_failed("err")
  pool.add(h3)
  @debug.debug_inspect(pool.size(), content="3")
  let collected = pool.collect_completed()
  @debug.debug_inspect(collected.length(), content="2")
  // Only h1 (Running) should remain
  @debug.debug_inspect(pool.size(), content="1")
}

///|
test "agent_pool_all_done" {
  let pool = AgentPool::new(4, 2)
  let h1 = SubAgentHandle::new("sa_1", {
    name: "a",
    model: None,
    allowed_tools: None,
    system_prompt_override: None,
    max_iterations: 5,
  })
  h1.mark_running()
  pool.add(h1)
  @debug.debug_inspect(pool.all_done(), content="false")
  h1.mark_completed("done")
  @debug.debug_inspect(pool.all_done(), content="true")
}

///|
test "agent_pool_summary" {
  let pool = AgentPool::new(3, 1)
  @debug.debug_inspect(
    pool.summary(),
    content=(
      #|"Agent pool: empty"
    ),
  )

  let h = SubAgentHandle::new("sa_1", {
    name: "w",
    model: None,
    allowed_tools: None,
    system_prompt_override: None,
    max_iterations: 5,
  })
  h.mark_running()
  pool.add(h)
  let s = pool.summary()
  guard s.contains("1 total") else {
    fail("Summary should contain total count")
  }
  guard s.contains("1 running") else {
    fail("Summary should contain running count")
  }
}
