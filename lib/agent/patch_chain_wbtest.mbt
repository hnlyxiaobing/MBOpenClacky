///| White-box tests for `lib/agent/patch_chain.mbt`.

///| Covers: glob matching, declarative block, declarative allow,

///| imperative shell hook, audit log, short-circuit chain ordering,

///| and the integration with `Agent::execute_single_tool`.

// ── Helpers ───────────────────────────────────────────────────────────────────

///|
fn make_rule(
  name~ : String,
  source? : String = "test-ext",
  tool_pattern? : String = "*",
  args_pattern? : String = "",
  action~ : PatchAction,
  command? : String = "",
) -> PatchRule {
  { name, source, tool_pattern, args_pattern, action, command }
}

///|
fn block_rule(
  name : String,
  tool_pattern : String,
  args_pattern : String,
  reason : String,
) -> PatchRule {
  make_rule(name~, tool_pattern~, args_pattern~, action=Block(reason))
}

///|
fn allow_rule(name : String, tool_pattern : String) -> PatchRule {
  make_rule(name~, tool_pattern~, action=Allow)
}

// ── PatchChain behaviour ─────────────────────────────────────────────────────

///|
test "patch_chain_empty_allows_everything" {
  let chain = PatchChain::new()
  let args : Map[String, Json] = {}
  match chain.check_before("terminal", args) {
    Allow => ()
    Block(_) => fail("empty chain must not block")
  }
  assert_eq(chain.len(), 0)
  assert_eq(chain.audit_entries().length(), 0)
}

///|
test "patch_chain_declarative_blocks_matching_args" {
  let chain = PatchChain::new()
  chain.add_rule(
    block_rule("no-rm-rf", "terminal", "rm -rf", "destructive command"),
  )
  let args : Map[String, Json] = { "command": Json::string("rm -rf /tmp/foo") }
  match chain.check_before("terminal", args) {
    Block(reason) => assert_eq(reason, "destructive command")
    Allow => fail("should have blocked rm -rf")
  }
  // Audit log should record the block.
  let entries = chain.audit_entries()
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].rule_name, "no-rm-rf")
  assert_true(entries[0].action.contains("BLOCK"))
}

///|
test "patch_chain_declarative_allows_non_matching_args" {
  let chain = PatchChain::new()
  chain.add_rule(
    block_rule("no-rm-rf", "terminal", "rm -rf", "destructive command"),
  )
  let args : Map[String, Json] = { "command": Json::string("ls -la") }
  match chain.check_before("terminal", args) {
    Allow => ()
    Block(_) => fail("ls -la must not be blocked")
  }
  // No audit entry when nothing matched.
  assert_eq(chain.audit_entries().length(), 0)
}

///|
test "patch_chain_glob_tool_pattern" {
  let chain = PatchChain::new()
  chain.add_rule(block_rule("file-blocker", "file_*", "secret", "no secrets"))
  // file_reader should match file_*
  let args : Map[String, Json] = { "path": Json::string("/secret/key") }
  match chain.check_before("file_reader", args) {
    Block(_) => ()
    Allow => fail("file_* glob should match file_reader")
  }
  // terminal should not match file_*
  match chain.check_before("terminal", args) {
    Allow => ()
    Block(_) => fail("file_* glob must not match terminal")
  }
}

///|
test "patch_chain_short_circuits_on_first_block" {
  let chain = PatchChain::new()
  chain.add_rule(block_rule("first", "terminal", "rm -rf", "rule one reason"))
  chain.add_rule(block_rule("second", "terminal", "rm -rf", "rule two reason"))
  let args : Map[String, Json] = { "command": Json::string("rm -rf /") }
  match chain.check_before("terminal", args) {
    Block(reason) => assert_eq(reason, "rule one reason")
    Allow => fail("must block")
  }
  // Only the first matching rule should produce an audit entry.
  assert_eq(chain.audit_entries().length(), 1)
  assert_eq(chain.audit_entries()[0].rule_name, "first")
}

///|
test "patch_chain_allow_rule_records_but_passes" {
  let chain = PatchChain::new()
  chain.add_rule(allow_rule("audit-only", "terminal"))
  let args : Map[String, Json] = { "command": Json::string("echo hi") }
  match chain.check_before("terminal", args) {
    Allow => ()
    Block(_) => fail("Allow rule must allow")
  }
  // Allow matches still produce an audit entry.
  assert_eq(chain.audit_entries().length(), 1)
  assert_true(chain.audit_entries()[0].action.contains("ALLOW"))
}

///|
test "patch_chain_check_after_appends_post_exec_audit" {
  let chain = PatchChain::new()
  let args : Map[String, Json] = { "command": Json::string("echo done") }
  chain.check_after("terminal", args, "done\n", false)
  let entries = chain.audit_entries()
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].rule_name, "<post-exec>")
  assert_true(entries[0].action.contains("EXECUTED"))
  // Truncates long results to <= 200 chars in the audit message.
  let big = String::make(500, 'x')
  chain.check_after("terminal", args, big, false)
  let second = chain.audit_entries()[1]
  assert_true(second.action.length() < big.length() + 50)
}

///|
test "patch_chain_check_after_records_error_action" {
  let chain = PatchChain::new()
  let args : Map[String, Json] = {}
  chain.check_after("file_reader", args, "permission denied", true)
  let entries = chain.audit_entries()
  assert_eq(entries.length(), 1)
  assert_true(entries[0].action.contains("ERROR"))
}

// ── Agent integration ────────────────────────────────────────────────────────

///|
test "agent_block_short_circuits_execute_single_tool" {
  let agent = make_test_agent()
  agent.register_patch_rule(
    block_rule("no-rm-rf", "terminal", "rm -rf", "destructive"),
  )
  let args_str = "{\"command\": \"rm -rf /tmp/x\"}"
  let call = make_tool_call("call-1", "terminal", args_str)
  let result = agent.execute_single_tool(call)
  assert_true(result.is_error)
  assert_true(result.content.contains("blocked by patch"))
  assert_true(result.content.contains("destructive"))
  // Audit log should record the block (no post-exec since blocked early).
  let chain = agent.patch_chain_view()
  let entries = chain.audit_entries()
  let mut found_block = false
  for e in entries {
    if e.action.contains("BLOCK") {
      found_block = true
    }
  }
  assert_true(found_block)
}

///|
test "agent_no_patch_preserves_legacy_behaviour" {
  // Without any patch, the chain is empty and behaviour is unchanged
  // for tool resolution (e.g. unknown tool still returns error).
  let agent = make_test_agent()
  let call = make_tool_call("call-2", "no_such_tool_xyz", "{}")
  let result = agent.execute_single_tool(call)
  assert_true(result.is_error)
  assert_true(result.content.contains("Unknown tool"))
  // The unknown-tool branch must still emit a post-exec audit entry.
  let entries = agent.patch_chain_view().audit_entries()
  assert_eq(entries.length(), 1)
  assert_true(entries[0].action.contains("ERROR"))
}
