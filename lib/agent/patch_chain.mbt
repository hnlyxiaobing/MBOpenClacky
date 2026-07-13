///| Patch rule data structures for the agent tool-execution patch system.

///| Patches are evaluated before and after every tool call. A patch can be

///| declarative (pattern match) or imperative (shell command hook).

///|

///|
/// Decision returned by `PatchChain::check_before`.
pub(all) enum PatchAction {
  /// Allow the tool call to proceed.
  Allow
  /// Block the tool call, attaching a reason surfaced to the agent.
  Block(String)
} derive(Eq, Debug)

///|
/// A single patch rule. Two flavours are supported:
///
/// 1. Declarative — `tool_pattern` and `args_pattern` are matched in-memory
///    against the tool call. `command` is empty.
/// 2. Imperative — `command` is a shell script that must print `BLOCK` or
///    `ALLOW`. The tool/args patterns are still matched first as a fast
///    prefilter; the command is only executed when the prefilter matches.
pub(all) struct PatchRule {
  /// Human-readable rule name.
  name : String
  /// Source extension id (for audit).
  source : String
  /// Glob-style tool-name pattern (`*` matches any, `terminal` exact,
  /// `file_*` prefix). Empty means "any tool".
  tool_pattern : String
  /// Substring to look for in the serialized args (empty = match all).
  args_pattern : String
  /// Action to take when the rule matches (declarative mode).
  action : PatchAction
  /// Imperative shell command (only used when prefilter matches).
  command : String
} derive(Debug)

///|
/// Single audit-log entry. One entry is appended for every
/// `check_before` decision and every `check_after` post-execution summary.
pub(all) struct PatchAuditEntry {
  /// Rule name (or "<post-exec>" for after-hook summary).
  rule_name : String
  /// Source extension id (or "<audit>" for post-exec).
  source : String
  /// Tool name called.
  tool_name : String
  /// Serialized tool arguments.
  tool_args : String
  /// Free-form action string (e.g. "BLOCK: rm -rf", "ALLOW", "EXECUTED").
  action : String
  /// Timestamp (ms since epoch).
  timestamp : Int64
} derive(Debug)

///|
/// Ordered chain of patch rules plus the running audit log.
///
/// Rules execute in registration order; the first `Block` decision
/// short-circuits. `check_after` does not block — it only appends an
/// audit entry summarizing the actual tool result.
pub(all) struct PatchChain {
  rules : Array[PatchRule]
  mut audit_log : Array[PatchAuditEntry]
}

///|
/// Create an empty patch chain.
pub fn PatchChain::new() -> PatchChain {
  { rules: [], audit_log: [] }
}

///|
/// Append a rule to the chain. Order matters: rules are evaluated
/// sequentially and the first `Block` short-circuits.
pub fn PatchChain::add_rule(self : PatchChain, rule : PatchRule) -> Unit {
  self.rules.push(rule)
}

///|
/// Number of registered rules.
pub fn PatchChain::len(self : PatchChain) -> Int {
  self.rules.length()
}

///|
/// Read-only view of the audit log.
pub fn PatchChain::audit_entries(self : PatchChain) -> Array[PatchAuditEntry] {
  self.audit_log
}

///|
/// Evaluate `tool_name` + `tool_args` against every rule in order.
///
/// Returns `Allow` when no rule blocks, or the first `Block` decision
/// encountered. Every rule that matches (Allow or Block) appends an
/// audit-log entry; the first Block is the one returned.
pub fn PatchChain::check_before(
  self : PatchChain,
  tool_name : String,
  tool_args : Map[String, Json],
) -> PatchAction {
  let args_str = serialize_args(tool_args)
  for rule in self.rules {
    if !glob_match(rule.tool_pattern, tool_name) {
      continue
    }
    if rule.args_pattern != "" && !args_str.contains(rule.args_pattern) {
      continue
    }
    // Prefilter matched — consult imperative hook if present.
    let effective = match execute_hook(rule, tool_name, args_str) {
      Some(decision) => decision
      None => rule.action
    }
    match effective {
      Block(reason) => {
        self.log_audit(rule, tool_name, args_str, "BLOCK: " + reason)
        return Block(reason)
      }
      Allow =>
        // Imperative hook returned Allow — still record that the rule
        // fired, so the audit trail shows what was checked.
        self.log_audit(rule, tool_name, args_str, "ALLOW (rule match)")
    }
  }
  Allow
}

///|
/// Record a post-execution audit entry. Never blocks.
///
/// `result_excerpt` is the first 200 characters of the tool result,
/// useful for after-the-fact review.
pub fn PatchChain::check_after(
  self : PatchChain,
  tool_name : String,
  tool_args : Map[String, Json],
  result_excerpt : String,
  is_error : Bool,
) -> Unit {
  let args_str = serialize_args(tool_args)
  let action = if is_error { "ERROR" } else { "EXECUTED" }
  let excerpt = if result_excerpt.length() > 200 {
    result_excerpt[0:200].to_string()
  } else {
    result_excerpt
  }
  let entry : PatchAuditEntry = {
    rule_name: "<post-exec>",
    source: "<audit>",
    tool_name,
    tool_args: args_str,
    action: action + " (" + excerpt + ")",
    timestamp: current_time_ms(),
  }
  self.audit_log.push(entry)
}

///|
/// Serialize a tool-args map into a single string for substring matching.
/// Non-string JSON values are JSON-encoded.
fn serialize_args(args : Map[String, Json]) -> String {
  if args.is_empty() {
    return ""
  }
  let buf = StringBuilder::new()
  buf.write_char('[')
  let mut first = true
  for k, v in args {
    if !first {
      buf.write_string(", ")
    }
    first = false
    buf.write_string(k)
    buf.write_string("=")
    buf.write_string(json_value_to_string(v))
  }
  buf.write_char(']')
  buf.to_string()
}

///|
/// Convert a JSON value to its string representation.
fn json_value_to_string(v : Json) -> String {
  match v {
    String(s) => "\"" + s + "\""
    Number(n) => n.to_string()
    True => "true"
    False => "false"
    Null => "null"
    _ => v.stringify()
  }
}

///|
/// Glob-style match supporting `*` wildcards. Empty pattern matches
/// every value (treated as "*").
fn glob_match(pattern : String, value : String) -> Bool {
  if pattern == "" || pattern == "*" {
    return true
  }
  if !pattern.contains("*") {
    return pattern == value
  }
  // Convert glob to anchored regex-lite: split on `*` and walk.
  let parts = pattern.split("*")
  let mut idx = 0
  let mut first = true
  let is_suffix_anchored = !pattern.has_suffix("*")
  for part in parts {
    let p = part.to_string()
    if p == "" {
      continue
    }
    if first {
      if !value.has_prefix(p) {
        return false
      }
      idx = p.length()
      first = false
      continue
    }
    let pos = match index_of_from(value, p, idx) {
      Some(p) => p
      None => return false
    }
    idx = pos + p.length()
  }
  if is_suffix_anchored && idx != value.length() {
    return false
  }
  true
}

///|
/// Linear search for `needle` in `haystack` starting at `from` (inclusive).
/// Returns the byte offset of the first match, or None.
fn index_of_from(haystack : String, needle : String, from : Int) -> Int? {
  if needle == "" {
    return Some(from)
  }
  let h_len = haystack.length()
  let n_len = needle.length()
  if from < 0 || from > h_len - n_len {
    return None
  }
  let mut i = from
  while i <= h_len - n_len {
    if haystack[i:i + n_len] == needle {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// Execute the imperative hook for `rule` if it has one.
///
/// Returns `Some(decision)` when the command was run, `None` when the
/// rule has no `command`. A non-zero exit code is treated as `Allow`
/// (fail-open) so a misbehaving hook cannot lock the agent out.
fn execute_hook(
  rule : PatchRule,
  tool_name : String,
  args_str : String,
) -> PatchAction? {
  if rule.command == "" {
    return None
  }
  let result = @tool.run_shell_command(rule.command, env_vars=[
    ("CLACKY_PATCH_NAME", rule.name),
    ("CLACKY_PATCH_SOURCE", rule.source),
    ("CLACKY_PATCH_TOOL", tool_name),
    ("CLACKY_PATCH_ARGS", args_str),
  ])
  let out = result.output.trim().to_owned()
  if result.exit_code != 0 {
    return Some(Allow)
  }
  if out.contains("BLOCK") {
    Some(
      Block(
        "blocked by patch '\{rule.name}': " +
        (if out == "BLOCK" { "no reason given" } else { out }),
      ),
    )
  } else {
    Some(Allow)
  }
}

///|
/// Internal: append a single audit-log entry.
fn PatchChain::log_audit(
  self : PatchChain,
  rule : PatchRule,
  tool_name : String,
  args_str : String,
  action : String,
) -> Unit {
  let entry : PatchAuditEntry = {
    rule_name: rule.name,
    source: rule.source,
    tool_name,
    tool_args: args_str,
    action,
    timestamp: current_time_ms(),
  }
  self.audit_log.push(entry)
}
