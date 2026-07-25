///| White-box tests for `lib/extension/patch_loader.mbt`.

///| Covers: contribution-to-rule conversion (declarative + imperative),

///| empty-config handling, manifest ordering, and disabled-extension

///| filtering inside `build_patch_chain`.

// ── Helpers ───────────────────────────────────────────────────────────────────

///|
fn make_extension_with_patches(
  id : String,
  enabled : Bool,
  contributions : Array[ExtensionContribution],
) -> Extension {
  {
    manifest: {
      id,
      name: id,
      version: "0.1.0",
      description: "",
      author: "tester",
      license: "MIT",
      homepage: None,
      repository: None,
      keywords: [],
      dependencies: Map([]),
      contributions,
      enabled_by_default: true,
    },
    source: Builtin,
    root_path: "/tmp/" + id,
    enabled,
    loaded_at: 0L,
    sha256: None,
  }
}

///|
fn patch_contrib(
  id : String,
  name : String,
  description : String,
  config : Map[String, String],
  path : String,
) -> ExtensionContribution {
  { type_: Patch, id, name, description, path, config }
}

// ── Tests ────────────────────────────────────────────────────────────────────

///|
test "patch_rule_from_contribution_returns_none_for_non_patch" {
  let contrib : ExtensionContribution = {
    type_: Panel,
    id: "x",
    name: "x",
    description: "",
    path: "",
    config: Map([]),
  }
  let ext = make_extension_with_patches("ext-a", true, [])
  match patch_rule_from_contribution(ext, contrib) {
    Some(_) => fail("non-Patch contribution must yield None")
    None => ()
  }
}

///|
test "patch_rule_from_contribution_skips_empty_patch" {
  // Patch with no config and no path is vacuous → None.
  let contrib = patch_contrib("p1", "noop", "", Map([]), "")
  let ext = make_extension_with_patches("ext-a", true, [])
  match patch_rule_from_contribution(ext, contrib) {
    Some(_) => fail("empty Patch contribution must yield None")
    None => ()
  }
}

///|
test "patch_rule_from_contribution_declarative_block" {
  let config : Map[String, String] = {
    "tool": "terminal",
    "block_pattern": "rm -rf",
  }
  let contrib = patch_contrib(
    "p1", "no-rm", "destructive ops not allowed", config, "",
  )
  let ext = make_extension_with_patches("ext-a", true, [])
  let rule = match patch_rule_from_contribution(ext, contrib) {
    Some(r) => r
    None => fail("expected a rule")
  }
  assert_eq(rule.name, "no-rm")
  assert_eq(rule.source, "ext-a")
  assert_eq(rule.tool_pattern, "terminal")
  assert_eq(rule.args_pattern, "rm -rf")
  assert_eq(rule.command, "")
  match rule.action {
    Block(reason) => assert_eq(reason, "destructive ops not allowed")
    Allow => fail("declarative block must produce Block")
  }
}

///|
test "patch_rule_from_contribution_imperative_with_path" {
  // path set, no declarative config → Allow prefilter + shell hook.
  let contrib = patch_contrib(
    "p1",
    "auditor",
    "audit via script",
    Map([]),
    "/opt/hooks/audit.sh",
  )
  let ext = make_extension_with_patches("ext-a", true, [])
  let rule = match patch_rule_from_contribution(ext, contrib) {
    Some(r) => r
    None => fail("expected a rule")
  }
  assert_eq(rule.command, "/opt/hooks/audit.sh")
  // No declarative block → prefilter is Allow, shell decides.
  match rule.action {
    Allow => ()
    Block(_) => fail("imperative-only must default to Allow")
  }
}

///|
test "patch_rules_from_extension_preserves_manifest_order" {
  let c1 = patch_contrib("p1", "r1", "first", { "block_pattern": "x" }, "")
  let c2 = patch_contrib("p2", "r2", "second", { "block_pattern": "y" }, "")
  let ext = make_extension_with_patches("ext-a", true, [c1, c2])
  let rules = patch_rules_from_extension(ext)
  assert_eq(rules.length(), 2)
  assert_eq(rules[0].name, "r1")
  assert_eq(rules[1].name, "r2")
}

///|
async test "build_patch_chain_skips_disabled_extensions" {
  let c1 = patch_contrib("p1", "r1", "first", { "block_pattern": "x" }, "")
  let c2 = patch_contrib("p2", "r2", "second", { "block_pattern": "y" }, "")
  let enabled_ext = make_extension_with_patches("ext-on", true, [c1])
  let disabled_ext = make_extension_with_patches("ext-off", false, [c2])
  let chain = build_patch_chain([enabled_ext, disabled_ext])
  assert_eq(chain.len(), 1)
  // Audit trail of an empty chain is empty until a check is run.
  assert_eq(chain.audit_entries().length(), 0)
  // The surviving rule must be the enabled one.
  let entries = chain.audit_entries()
  let _ = entries
  match chain.check_before("terminal", { "command": Json::string("x") }) {
    Block(_) => ()
    Allow => fail("enabled extension's rule must fire")
  }
  assert_eq(chain.audit_entries().length(), 1)
  assert_eq(chain.audit_entries()[0].source, "ext-on")
}

///|
test "build_patch_chain_empty_for_no_extensions" {
  let chain = build_patch_chain([])
  assert_eq(chain.len(), 0)
}
