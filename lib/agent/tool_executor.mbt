///| Tool execution, permission checking, and result building.

///| Reference: openclacky/lib/clacky/agent/tool_executor.rb

///|

///|
/// Sidecar image payload delivered out-of-band from tool content.
///
/// Aligned with Ruby `image_inject` (openclacky tools/browser.rb +
/// agent/tool_executor.rb): the tool content carries a plain-text
/// description for the LLM, while the base64 image rides here and is
/// attached to the next `role:"user"` message (OpenAI-compatible APIs
/// reject image_url blocks in tool messages).
pub(all) struct ImageInject {
  mime_type : String
  base64_data : String
  path : String?
} derive(Eq, Debug)

///|
pub extend ImageInject with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ImageInject with Eq::{not_equal, equal}

///|
/// Internal result entry for a single tool execution.
pub(all) struct ToolResultEntry {
  /// The tool_call_id this result corresponds to.
  id : String
  /// Result content (tool output or error message).
  content : String
  /// Whether this result represents an error.
  is_error : Bool
  /// Out-of-band image payload (screenshot base64), if any.
  image_inject : ImageInject?
} derive(Eq, Debug)

///|
pub extend ToolResultEntry with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ToolResultEntry with Eq::{not_equal, equal}

///|
/// Determine whether a tool should execute automatically based on
/// the current permission mode.
///
/// Aligned with Ruby openclacky agent.rb + tool_executor.rb:
/// - AutoApprove: all tools auto-execute, no human present
/// - ConfirmAll: all tools auto-execute, human present for
///   request_user_feedback only
/// - ConfirmSafes: blacklist model — only `edit` and `write` require
///   confirmation; everything else auto-executes
pub fn Agent::should_auto_execute(
  self : Agent,
  tool_name : String,
  tool_params : Map[String, Json],
) -> Bool {
  match self.config.permission_mode {
    @config.AutoApprove => true
    @config.ConfirmAll => true
    @config.ConfirmSafes => self.is_safe_operation(tool_name, tool_params)
  }
}

///|
/// Check if a tool operation is safe for automatic execution.
///
/// Aligned with Ruby openclacky tool_executor.rb `is_safe_operation?`:
/// - `edit` and `write` are NOT safe (require user confirmation)
/// - `terminal` commands are checked via the security module
/// - Everything else is safe (auto-execute)
pub fn Agent::is_safe_operation(
  _self : Agent,
  tool_name : String,
  tool_params : Map[String, Json],
) -> Bool {
  match tool_name {
    "edit" | "write" => false
    "terminal" =>
      // Check the command via the security module
      match tool_params.get("command") {
        Some(String(cmd)) => @tool.command_safe_for_auto_execution(cmd)
        _ => true
      }
    _ => true
  }
}

///|
/// Execute a single tool call, resolving the name and dispatching
/// to the ToolRegistry.
///
/// Patch chain is evaluated before execution; a `Block` decision
/// short-circuits and returns an error result. After successful
/// (or failed) execution an audit entry is appended for every tool
/// call so the trail is complete.
///
/// Returns a ToolResultEntry with the execution result.
pub async fn Agent::execute_single_tool(
  self : Agent,
  call : @message.ToolCall,
) -> ToolResultEntry {
  let tool_name = call.function.name
  let (args, parse_error) = parse_tool_arguments_checked(call)
  // ── Parse error: report explicitly so the model knows the arguments
  // itself were unparseable (distinct from "missing parameter").
  match parse_error {
    Some(err) => {
      let result = build_error_result(call, err)
      self.patch_chain.check_after(tool_name, args, result.content, true)
      return result
    }
    None => ()
  }
  // ── Patch chain: before-hook ────────────────────────────────
  // Short-circuit on Block so a misbehaving patch can deny the call
  // before we even resolve the tool.
  match self.patch_chain.check_before(tool_name, args) {
    Block(reason) => {
      let msg = "Tool '\{tool_name}' blocked by patch: \{reason}"
      return build_error_result(call, msg)
    }
    Allow => ()
  }
  // Resolve canonical name
  let canonical = match self.tool_registry.resolve(tool_name) {
    Some(name) => name
    None => {
      let names = self.tool_registry.tool_names().join(", ")
      let result = build_error_result(
        call,
        "Unknown tool: \{tool_name}. Available: \{names}",
      )
      self.patch_chain.check_after(tool_name, args, result.content, true)
      return result
    }
  }
  // Get the tool instance
  let tool = match self.tool_registry.get(canonical) {
    Some(t) => t
    None => {
      let result = build_error_result(
        call,
        "Tool '\{canonical}' registered but not found",
      )
      self.patch_chain.check_after(tool_name, args, result.content, true)
      return result
    }
  }
  // Intercept agent-context tools before generic dispatch
  match canonical {
    "invoke_skill" => {
      let result = self.execute_invoke_skill(call, args)
      let final_result = if result.is_error {
        result
      } else {
        self.inject_todo_reminder(call, result)
      }
      self.patch_chain.check_after(
        tool_name,
        args,
        final_result.content,
        final_result.is_error,
      )
      return final_result
    }
    "memory" => {
      let result = self.execute_memory_tool(call, args)
      let final_result = if result.is_error {
        result
      } else {
        self.inject_todo_reminder(call, result)
      }
      self.patch_chain.check_after(
        tool_name,
        args,
        final_result.content,
        final_result.is_error,
      )
      return final_result
    }
    "todo_manager" => {
      let result = self.execute_todo_tool(call, args)
      let final_result = if result.is_error {
        result
      } else {
        self.inject_todo_reminder(call, result)
      }
      self.patch_chain.check_after(
        tool_name,
        args,
        final_result.content,
        final_result.is_error,
      )
      return final_result
    }
    _ => ()
  }
  // Execute — AnyTool implements Tool trait
  let result : @tool.ToolResult = @tool.Tool::execute(tool, args)
  let final_result = if result.is_error {
    build_error_result(call, result.content)
  } else {
    // Inject the TODO reminder on successful results (Ruby semantics)
    let entry = build_success_result(call, result)
    self.inject_todo_reminder(call, entry)
  }
  // ── Patch chain: after-hook (audit only, never blocks) ────────
  self.patch_chain.check_after(
    tool_name,
    args,
    final_result.content,
    final_result.is_error,
  )
  final_result
}

///|
/// Execute the invoke_skill tool by resolving the skill from the registry
/// and returning its context as the result.
fn Agent::execute_invoke_skill(
  self : Agent,
  call : @message.ToolCall,
  args : Map[String, Json],
) -> ToolResultEntry {
  let skill_name = match args.get("skill_name") {
    Some(String(s)) => s
    _ => return build_error_result(call, "invoke_skill: missing 'skill_name'")
  }
  let arguments = match args.get("arguments") {
    Some(String(s)) => s
    _ => ""
  }
  match self.skill_registry.get(skill_name) {
    None =>
      build_error_result(call, "Skill '\{skill_name}' not found in registry")
    Some(skill) => {
      let ctx = @skill.build_skill_context(skill, arguments)
      build_success_result(call, @tool.ToolResult::{
        content: ctx,
        is_error: false,
      })
    }
  }
}

///|
/// Execute the memory tool by dispatching to the agent's MemoryStore.
fn Agent::execute_memory_tool(
  self : Agent,
  call : @message.ToolCall,
  args : Map[String, Json],
) -> ToolResultEntry {
  let action = match args.get("action") {
    Some(String(s)) => s
    _ => return build_error_result(call, "memory: missing 'action'")
  }
  // Ensure memory store is initialised
  let store = match self.memory_store {
    None => {
      self.memory_store = Some(MemoryStore::new(""))
      match self.memory_store {
        Some(s) => s
        None => return build_error_result(call, "memory: store init failed")
      }
    }
    Some(s) => s
  }
  match action {
    "create" => {
      let title = match args.get("title") {
        Some(String(s)) => s
        _ => return build_error_result(call, "memory create: missing 'title'")
      }
      let content = match args.get("content") {
        Some(String(s)) => s
        _ => return build_error_result(call, "memory create: missing 'content'")
      }
      let category = match args.get("category") {
        Some(String(s)) =>
          match MemoryCategory::from_string(s) {
            Some(c) => c
            None => UserPreference
          }
        _ => UserPreference
      }
      let entry = store.add(title, content, category, [])
      build_success_result(call, @tool.ToolResult::{
        content: "Memory created with id: \{entry.id}",
        is_error: false,
      })
    }
    "search" => {
      let query = match args.get("query") {
        Some(String(s)) => s
        _ => return build_error_result(call, "memory search: missing 'query'")
      }
      let category = match args.get("category") {
        Some(String(s)) => MemoryCategory::from_string(s)
        _ => None
      }
      let results = store.search(query, category)
      let count = results.length()
      let mut out = "Found \{count} memories:\n"
      for e in results {
        out = out + "- [\{e.id}] \{e.title}\n"
      }
      build_success_result(call, @tool.ToolResult::{
        content: out,
        is_error: false,
      })
    }
    "update" => {
      let id = match args.get("id") {
        Some(String(s)) => s
        _ => return build_error_result(call, "memory update: missing 'id'")
      }
      let content = match args.get("content") {
        Some(String(s)) => s
        _ => return build_error_result(call, "memory update: missing 'content'")
      }
      if store.update(id, content) {
        build_success_result(call, @tool.ToolResult::{
          content: "Memory \{id} updated",
          is_error: false,
        })
      } else {
        build_error_result(call, "Memory '\{id}' not found")
      }
    }
    "delete" => {
      let id = match args.get("id") {
        Some(String(s)) => s
        _ => return build_error_result(call, "memory delete: missing 'id'")
      }
      if store.delete(id) {
        build_success_result(call, @tool.ToolResult::{
          content: "Memory \{id} deleted",
          is_error: false,
        })
      } else {
        build_error_result(call, "Memory '\{id}' not found")
      }
    }
    "list" => {
      let summary = store.summary()
      build_success_result(call, @tool.ToolResult::{
        content: summary,
        is_error: false,
      })
    }
    _ => build_error_result(call, "memory: unknown action '\{action}'")
  }
}

///|
/// Execute the todo_manager tool by dispatching to the agent's TodoManager.
fn Agent::execute_todo_tool(
  self : Agent,
  call : @message.ToolCall,
  args : Map[String, Json],
) -> ToolResultEntry {
  let action = match args.get("action") {
    Some(String(s)) => s
    _ => return build_error_result(call, "todo_manager: missing 'action'")
  }
  match action {
    "add" => {
      let title = match args.get("title") {
        Some(String(s)) => s
        _ => return build_error_result(call, "todo add: missing 'title'")
      }
      let description = match args.get("description") {
        Some(String(s)) => s
        _ => ""
      }
      let item = self.todo_manager.add(title, description)
      build_success_result(call, @tool.ToolResult::{
        content: "Task created with id: \{item.id}",
        is_error: false,
      })
    }
    "update" => {
      let id = match args.get("id") {
        Some(String(s)) => s
        _ => return build_error_result(call, "todo update: missing 'id'")
      }
      let status_str = match args.get("status") {
        Some(String(s)) => s
        _ => return build_error_result(call, "todo update: missing 'status'")
      }
      let status = match TodoStatus::from_string(status_str) {
        Some(st) => st
        None =>
          return build_error_result(
            call,
            "todo update: unknown status '\{status_str}'",
          )
      }
      if self.todo_manager.update_status(id, status) {
        build_success_result(call, @tool.ToolResult::{
          content: "Task \{id} updated to \{status_str}",
          is_error: false,
        })
      } else {
        build_error_result(call, "Task '\{id}' not found")
      }
    }
    "list" => {
      let summary = self.todo_manager.summary()
      build_success_result(call, @tool.ToolResult::{
        content: summary,
        is_error: false,
      })
    }
    "remove" => {
      let id = match args.get("id") {
        Some(String(s)) => s
        _ => return build_error_result(call, "todo remove: missing 'id'")
      }
      if self.todo_manager.remove(id) {
        build_success_result(call, @tool.ToolResult::{
          content: "Task \{id} removed",
          is_error: false,
        })
      } else {
        build_error_result(call, "Task '\{id}' not found")
      }
    }
    "set_deps" => {
      let id = match args.get("id") {
        Some(String(s)) => s
        _ => return build_error_result(call, "todo set_deps: missing 'id'")
      }
      let deps : Array[String] = match args.get("deps") {
        Some(Array(items)) => {
          let arr : Array[String] = []
          for item in items {
            match item {
              String(s) => arr.push(s)
              _ => ()
            }
          }
          arr
        }
        _ => []
      }
      if self.todo_manager.set_blocked_by(id, deps) {
        build_success_result(call, @tool.ToolResult::{
          content: "Task \{id} dependencies updated",
          is_error: false,
        })
      } else {
        build_error_result(call, "Task '\{id}' not found")
      }
    }
    _ => build_error_result(call, "todo_manager: unknown action '\{action}'")
  }
}

///|
/// Parse tool arguments from the JSON string in a ToolCall.
///
/// Tries a strict parse first; on failure attempts a bounded JSON repair
/// (unescape, XML tag removal, comma/quote/bracket fixes — aligned with
/// Ruby `Utils::ArgumentsParser.repair_json`) before giving up.
///
/// Returns `(args, error)`: `error` is None on success (including empty
/// arguments); Some(message) when the arguments could not be parsed as
/// JSON — distinct from "missing required parameter" so the model gets
/// the right repair direction.
pub fn parse_tool_arguments_checked(
  call : @message.ToolCall,
) -> (Map[String, Json], String?) {
  let args_str = call.function.arguments.trim().to_owned()
  if args_str.length() == 0 {
    return (Map([]), None)
  }
  // Attempt 1: strict parse
  match parse_json_object(args_str) {
    Some(m) => (m, None)
    None =>
      // Attempt 2: repair then parse
      match parse_json_object(repair_json(args_str)) {
        Some(m) => (m, None)
        None =>
          (
            Map([]),
            Some(
              "Tool arguments could not be parsed as JSON. Raw arguments: \{call.function.arguments}",
            ),
          )
      }
  }
}

///|
/// Parse a JSON string into a Map, returning None on any failure
/// (invalid JSON or a non-object root).
fn parse_json_object(s : String) -> Map[String, Json]? {
  try {
    let parsed = @json.parse(s)
    match parsed {
      Object(obj) => {
        let result : Map[String, Json] = Map([])
        for k, v in obj {
          result[k] = v
        }
        Some(result)
      }
      _ => None
    }
  } catch {
    _ => None
  }
}

///|
/// Backwards-compatible simple parse: empty map on any failure.
/// Used where only the argument values matter (e.g. permission checks).
pub fn parse_tool_arguments(call : @message.ToolCall) -> Map[String, Json] {
  let (args, _err) = parse_tool_arguments_checked(call)
  args
}

///|
/// Bounded JSON repair for common LLM output defects.
///
/// Aligned with Ruby `Utils::ArgumentsParser.repair_json`:
/// - unescape literal `\n` / `\"` (backslash followed by n / quote)
/// - convert `<parameter name="key">` / `<parameter name="key":` to
///   `, "key": `
/// - strip stray angle-bracket tags
/// - normalize comma/newline sequences; drop duplicate, trailing and
///   leading commas
/// - close unclosed quotes and brackets
///
/// This is a best-effort repair — if the result still fails to parse,
/// the caller returns an explicit parse-error result.
fn repair_json(json_str : String) -> String {
  let mut result = json_str.trim().to_owned()
  // Literal backslash-n → real newline
  result = replace_all(result, "\\n", "\n")
  // Literal backslash-quote → real quote
  result = replace_all(result, "\\\"", "\"")
  // Remove closing parameter tags
  result = replace_all(result, "</parameter>", "")
  // Convert `<parameter name="key">` / `<parameter name="key":` to `, "key": `
  let marker = "<parameter name=\""
  while true {
    match index_of_from(result, marker, 0) {
      None => break
      Some(pos) => {
        let key_start = pos + marker.length()
        match index_of_from(result, "\"", key_start) {
          None => break
          Some(qpos) => {
            let key = result[key_start:qpos].to_owned()
            let after_quote = result[qpos + 1:].to_owned()
            let tail = if after_quote.length() > 0 &&
              (after_quote[0] == '>' || after_quote[0] == ':') {
              after_quote[1:].to_owned()
            } else {
              after_quote
            }
            let head = result[:pos].to_owned()
            result = head + ", \"\{key}\": " + tail
          }
        }
      }
    }
  }
  // Strip remaining angle-bracket tags
  result = strip_angle_tags(result)
  // Comma / newline normalization (JSON treats newlines as whitespace)
  result = replace_all(result, "\n,", ",")
  result = replace_all(result, ",\n", ",")
  // Collapse duplicate commas
  while result.contains(",,") {
    result = replace_all(result, ",,", ",")
  }
  // Trailing commas (with optional single space)
  result = replace_all(result, ",}", "}")
  result = replace_all(result, ",]", "]")
  result = replace_all(result, ", }", "}")
  result = replace_all(result, ", ]", "]")
  // Leading commas (with optional single space)
  result = replace_all(result, "{,", "{")
  result = replace_all(result, "[,", "[")
  result = replace_all(result, "{ ,", "{")
  result = replace_all(result, "[ ,", "[")
  result = replace_all(result, "{,\"", "{\"")
  result = replace_all(result, "[,\"", "[\"")
  result = replace_all(result, "{ ,\"", "{\"")
  result = replace_all(result, "[ ,\"", "[\"")
  // Balance quotes: odd count → append one
  let mut quote_count = 0
  for c in result {
    if c == '"' {
      quote_count = quote_count + 1
    }
  }
  if quote_count % 2 == 1 {
    result = result + "\""
  }
  // Balance brackets: close any unclosed
  let mut depth = 0
  for c in result {
    match c {
      '{' | '[' => depth = depth + 1
      '}' | ']' => depth = depth - 1
      _ => ()
    }
  }
  while depth > 0 {
    result = result + "}"
    depth = depth - 1
  }
  result
}

///|
/// Replace ALL occurrences of `old` with `new`.
///
/// MoonBit's `String::replace` only replaces the first match; Ruby's
/// `gsub` (which `repair_json` mirrors) replaces all, so loop until done.
fn replace_all(s : String, old : String, new : String) -> String {
  let mut result = s
  while result.contains(old) {
    result = result.replace(old~, new~)
  }
  result
}

///|
/// Remove closed `<...>` angle-bracket tags from a string.
fn strip_angle_tags(s : String) -> String {
  let mut result = s
  while true {
    match index_of_from(result, "<", 0) {
      None => break
      Some(pos) =>
        match index_of_from(result, ">", pos + 1) {
          None => break
          Some(gpos) => {
            let head = result[:pos].to_owned()
            let tail = result[gpos + 1:].to_owned()
            result = head + tail
          }
        }
    }
  }
  result
}

///|
/// Inject a TODO reminder into a successful tool result when there are
/// pending tasks. Skips the todo_manager tool itself to avoid
/// redundancy. Aligned with Ruby `ToolExecutor#inject_todo_reminder`.
fn Agent::inject_todo_reminder(
  self : Agent,
  call : @message.ToolCall,
  entry : ToolResultEntry,
) -> ToolResultEntry {
  if call.function.name == "todo_manager" {
    return entry
  }
  let mut pending = 0
  for item in self.todo_manager.list_all() {
    if item.status == Pending {
      pending = pending + 1
    }
  }
  if pending == 0 {
    return entry
  }
  let reminder = "\n\n📋 REMINDER: You have \{pending} pending TODO(s). After completing each task, remember to mark it as complete using todo_manager with action 'complete' and the task id."
  {
    id: entry.id,
    content: entry.content + reminder,
    is_error: entry.is_error,
    image_inject: entry.image_inject,
  }
}

// ── Result Builders ───────────────────────────────────────────────────────────

///|
/// Maximum tool output length in characters before truncation.
/// Matches Ruby's 80K limit to prevent context window overflow.
pub let max_tool_output_chars : Int = 80000

///|
/// Truncate tool output if it exceeds the maximum length.
/// Appends a notice so the model knows output was cut.
/// Uses byte length for the fast initial check, then iterates by
/// character to ensure valid UTF-8 in the truncated output.
fn truncate_tool_output(output : String) -> String {
  if output.length() <= max_tool_output_chars {
    return output
  }
  let buf = StringBuilder::new()
  let mut count = 0
  let mut did_truncate = false
  for c in output {
    if count >= max_tool_output_chars {
      did_truncate = true
      break
    }
    buf.write_char(c)
    count = count + 1
  }
  if did_truncate {
    buf.write_string(
      "\n\n[Output truncated at \{max_tool_output_chars} characters]",
    )
  }
  buf.to_string()
}

///|
/// Build a success result entry from a tool call and its result.
/// Applies output truncation to prevent context window overflow, then
/// extracts any `[image_inject]` sidecar marker into the out-of-band
/// `image_inject` field (aligned with Ruby build_success_result).
pub fn build_success_result(
  call : @message.ToolCall,
  result : @tool.ToolResult,
) -> ToolResultEntry {
  let (content, inject) = extract_image_inject(
    truncate_tool_output(result.content),
  )
  { id: call.id, content, is_error: false, image_inject: inject }
}

///|
/// Extract an `[image_inject]` sidecar marker from tool output.
///
/// Contract with the browser screenshot producer (B3 spec): the marker
/// block looks like
///
/// ```text
/// [image_inject]
/// mime_type: image/png
/// base64_data: <base64>
/// path: /tmp/xxx.png          (optional)
/// ```
///
/// When present with a real base64 payload, the marker block is stripped
/// from the content (so it is not tokenised as text) and returned as an
/// `ImageInject`. If the marker carries only a placeholder (e.g. the
/// current `base64_data: (12345 chars)` length summary with no payload)
/// the content is returned unchanged with no inject, preserving the
/// path/size info for the LLM until the producer ships real data.
pub fn extract_image_inject(content : String) -> (String, ImageInject?) {
  match content.find("[image_inject]") {
    None => (content, None)
    Some(marker_pos) => {
      let tail = content[marker_pos + "[image_inject]".length():].to_owned()
      let mut mime_type : String? = None
      let mut base64_data : String? = None
      let mut path : String? = None
      for line in tail.split("\n") {
        if line.has_prefix("mime_type:") {
          mime_type = Some(line["mime_type:".length():].trim().to_owned())
        } else if line.has_prefix("base64_data:") {
          let value = line["base64_data:".length():].trim().to_owned()
          // Skip placeholder length summaries: `(12345 chars)`
          if value.length() > 0 && value[0] != '(' {
            base64_data = Some(value)
          }
        } else if line.has_prefix("path:") {
          path = Some(line["path:".length():].trim().to_owned())
        }
      }
      match (mime_type, base64_data) {
        (Some(mime), Some(b64)) =>
          (
            content[:marker_pos].to_owned().trim().to_owned(),
            Some({ mime_type: mime, base64_data: b64, path }),
          )
        _ => (content, None)
      }
    }
  }
}

///|
/// Build an error result entry from a tool call and error message.
/// Content is a valid JSON object `{"error": "..."}` — keys are quoted
/// and the message is escaped by the JSON serializer.
pub fn build_error_result(
  call : @message.ToolCall,
  error_message : String,
) -> ToolResultEntry {
  let content = Json::object({ "error": ToJson::to_json(error_message) }).stringify()
  { id: call.id, content, is_error: true, image_inject: None }
}

///|
/// Build a denied result entry when user rejects tool execution.
///
/// Aligned with Ruby `ToolExecutor#build_denied_result` (non
/// system-injected path): the message clearly states the action was NOT
/// performed, `action_performed` is false and `user_feedback` carries
/// the user's feedback (JSON null when absent).
pub fn build_denied_result(
  call : @message.ToolCall,
  feedback : String?,
) -> ToolResultEntry {
  let msg = match feedback {
    Some(fb) =>
      "Tool use denied by user. This action was NOT performed. User feedback: \{fb}"
    None => "Tool use denied by user. This action was NOT performed."
  }
  let content = Json::object({
    "error": ToJson::to_json(msg),
    "action_performed": ToJson::to_json(false),
    "user_feedback": match feedback {
      Some(fb) => ToJson::to_json(fb)
      None => Json::null()
    },
  }).stringify()
  { id: call.id, content, is_error: true, image_inject: None }
}
