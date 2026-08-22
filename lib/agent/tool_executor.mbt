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
  // ── Subagent tool restriction (B7 decision 5) ───────────────
  // Mirrors Ruby fork_subagent's before_tool_use hook: forbidden tools
  // are blocked at runtime without touching the shared registry (cache
  // reuse). The raw name is checked first; the canonical name is checked
  // again after resolution so aliases/case variants cannot bypass.
  match self.tool_restriction_reason(tool_name) {
    Some(reason) => {
      let result = build_denied_result(call, Some(reason))
      self.patch_chain.check_after(tool_name, args, result.content, true)
      return result
    }
    None => ()
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
  // Canonical-name restriction re-check: an alias (e.g. "Write", "EDIT")
  // that slipped past the raw-name check cannot bypass forbidden/allowed.
  match self.tool_restriction_reason(canonical) {
    Some(reason) => {
      let result = build_denied_result(call, Some(reason))
      self.patch_chain.check_after(tool_name, args, result.content, true)
      return result
    }
    None => ()
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
  // ── Document read interception (stubfix-03 task pack 4) ──────────
  // Ruby FileReader#execute parses .pdf/.docx/.pptx/.xlsx/.doc/.wps via
  // MoonBitMark and reports `parsed_from` as a structured field. MB's
  // ToolResult carries only text content, so the parsed-from marker rides
  // as a header line inside the content. .et/.dps hit decision 9 (honest
  // error) before the generic reader; all other paths keep file_reader's
  // existing text semantics untouched.
  if canonical == "file_reader" {
    match args.get("path") {
      Some(String(p)) if @parser.is_whitelisted_document_extension(p) ||
        @parser.is_wps_binary_extension(p) => {
        let result = execute_document_read(call, p)
        self.patch_chain.check_after(
          tool_name,
          args,
          result.content,
          result.is_error,
        )
        return result
      }
      _ => ()
    }
  }
  // Inject CLACKY_SESSION_ID into terminal env (Ruby agent.rb semantics:
  // every terminal invocation gets the session id so child processes can
  // correlate output with the agent session).
  let args = if canonical == "terminal" {
    let session_json = Json::string(self.session_id)
    let new_env : Map[String, Json] = match args.get("env") {
      Some(obj) =>
        // env: { ... } — merge CLACKY_SESSION_ID first so user value wins
        match obj {
          Object(m) => {
            let merged = Map::from_array(m.to_array())
            merged.set("CLACKY_SESSION_ID", session_json)
            args.set("env", Json::object(merged))
            args
          }
          _ => {
            args.set(
              "env",
              Json::object(
                Map::from_array([("CLACKY_SESSION_ID", session_json)]),
              ),
            )
            args
          }
        }
      None => {
        args.set(
          "env",
          Json::object(Map::from_array([("CLACKY_SESSION_ID", session_json)])),
        )
        args
      }
    }
    new_env
  } else {
    args
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
/// Parse a whitelisted document via MoonBitMark and build the result
/// entry (stubfix-03 task pack 4). Mirrors Ruby FileReader#execute's
/// parsed_from path: success carries the converted markdown with a
/// `[Parsed from <FMT> via MoonBitMark]` header line (MB ToolResult has
/// no structured fields); failure carries the MoonBitMark diagnostic
/// (including decision-9 wording for .et/.dps, which never reaches the
/// engine). R7: cancellation is checked before and after the convert.
async fn execute_document_read(
  call : @message.ToolCall,
  path : String,
) -> ToolResultEntry {
  if @async.is_being_cancelled() {
    return build_error_result(call, "Tool execution cancelled")
  }
  let result = @parser.ParserManager::new().parse_document(path)
  if @async.is_being_cancelled() {
    return build_error_result(call, "Tool execution cancelled")
  }
  if result.is_success {
    let fmt = result.metadata.format.to_string()
    let marker = "[Parsed from \{fmt} via MoonBitMark]\n\n"
    let content = marker + result.content
    build_success_result(call, @tool.ToolResult::success(content))
  } else {
    let msg = match result.error {
      Some(err) => err
      None => "Document parsing failed"
    }
    build_error_result(call, msg)
  }
}

///|
/// Execute the invoke_skill tool by resolving the skill from the registry.
/// Mirrors Ruby InvokeSkill#execute: skill_name and task are both required;
/// the skill content is NOT returned inline — it is enqueued for deferred
/// injection as a system-injected assistant message after observe(), so the
/// toolResult is appended first (correct toolUse/toolResult ordering).
fn Agent::execute_invoke_skill(
  self : Agent,
  call : @message.ToolCall,
  args : Map[String, Json],
) -> ToolResultEntry {
  let skill_name = match args.get("skill_name") {
    Some(String(s)) => s
    _ => return build_error_result(call, "invoke_skill: missing 'skill_name'")
  }
  let task = match args.get("task") {
    Some(String(s)) => s
    _ => return build_error_result(call, "invoke_skill: missing 'task'")
  }
  match self.skill_registry.get(skill_name) {
    None =>
      build_error_result(call, "Skill '\\{skill_name}' not found in registry")
    Some(_skill) => {
      // disable-model-invocation guard (Ruby skill.rb): the model may not
      // invoke skills that opted out; only the user can via `/name`.
      if _skill.disable_model_invocation {
        return build_error_result(
          call,
          "Skill '\{skill_name}' does not allow model invocation",
        )
      }
      // Agent-scope guard: skills scoped to another agent type are not
      // invocable from this agent.
      match _skill.agent_type {
        Some(agent_type) =>
          if agent_type != self.name {
            return build_error_result(
              call,
              "Skill '\{skill_name}' is scoped to agent '\{agent_type}'",
            )
          }
        None => ()
      }
      self.enqueue_injection(skill_name, task)
      build_success_result(call, @tool.ToolResult::{
        content: "Skill '\{skill_name}' instructions expanded. Proceed to execute the task.",
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
/// Collect the `task` argument (string or array of strings), trimming
/// each entry and dropping empties (Ruby normalize_to_array + strip).
fn todo_tasks_arg(args : Map[String, Json]) -> Array[String] {
  let out : Array[String] = []
  match args.get("task") {
    Some(String(s)) => {
      let t = s.trim().to_owned()
      if t.length() > 0 {
        out.push(t)
      }
    }
    Some(Array(items)) =>
      for item in items {
        match item {
          String(s) => {
            let t = s.trim().to_owned()
            if t.length() > 0 {
              out.push(t)
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  out
}

///|
/// Collect the `id` argument (integer or array of integers).
fn todo_ids_arg(args : Map[String, Json]) -> Array[Int] {
  let out : Array[Int] = []
  match args.get("id") {
    Some(Number(n, ..)) => out.push(n.to_int())
    Some(Array(items)) =>
      for item in items {
        match item {
          Number(n, ..) => out.push(n.to_int())
          _ => ()
        }
      }
    _ => ()
  }
  out
}

///|
/// Execute the todo_manager tool by dispatching to the agent's TodoManager.
/// The result content mirrors the Ruby todo_manager result hash (JSON),
/// so the model sees the same message/todos/reminder fields.
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
    "add" => self.todo_add(call, args)
    "list" => self.todo_list(call)
    "complete" => self.todo_complete(call, args)
    "remove" => self.todo_remove(call, args)
    "clear" => self.todo_clear(call)
    _ => build_error_result(call, "Unknown action: \{action}")
  }
}

///|
/// add: batch-add tasks, auto-clearing old completed items first
/// (Ruby add_todos semantics).
fn Agent::todo_add(
  self : Agent,
  call : @message.ToolCall,
  args : Map[String, Json],
) -> ToolResultEntry {
  let tasks = todo_tasks_arg(args)
  if tasks.is_empty() {
    return build_error_result(call, "At least one task description is required")
  }
  let _ = self.todo_manager.clear_completed()
  let added : Array[TodoItem] = []
  for t in tasks {
    added.push(self.todo_manager.add(t, ""))
  }
  let message = if added.length() == 1 {
    "TODO added successfully"
  } else {
    "\{added.length()} TODOs added successfully"
  }
  let todos_json : Array[Json] = added.map(todo_item_to_model_json)
  let content = Json::object({
    "message": message.to_json(),
    "todos": ToJson::to_json(todos_json),
    "total": self.todo_manager.size().to_json(),
    "reminder": "⚠️ IMPORTANT: You have added TODO(s) but have NOT started working yet! You MUST now use other tools (write, edit, shell, etc.) to actually complete these tasks. DO NOT stop here!".to_json(),
  }).stringify()
  build_success_result(call, @tool.ToolResult::{ content, is_error: false })
}

///|
/// list: render all tasks with pending/completed counts (Ruby list_todos).
fn Agent::todo_list(self : Agent, call : @message.ToolCall) -> ToolResultEntry {
  let content = if self.todo_manager.size() == 0 {
    let todos_json : Array[Json] = []
    Json::object({
      "message": "No TODO items".to_json(),
      "todos": ToJson::to_json(todos_json),
      "total": (0).to_json(),
    }).stringify()
  } else {
    self.todo_manager.list_to_model_json().stringify()
  }
  build_success_result(call, @tool.ToolResult::{ content, is_error: false })
}

///|
/// complete: mark one or more ids completed, auto-clearing when all tasks
/// are done (Ruby complete_todo/complete_todos semantics).
fn Agent::todo_complete(
  self : Agent,
  call : @message.ToolCall,
  args : Map[String, Json],
) -> ToolResultEntry {
  let ids = todo_ids_arg(args)
  if ids.is_empty() {
    return build_error_result(call, "Task ID is required")
  }
  let (completed_now, already, not_found) = self.todo_manager.complete_by_ids(
    ids,
  )
  // Single-id semantics mirror Ruby complete_todo: a missing task is an
  // error, an already-completed task returns "Task already completed".
  if ids.length() == 1 && not_found.length() == 1 {
    return build_error_result(call, "Task not found: \{not_found[0]}")
  }
  if ids.length() == 1 && completed_now.length() == 0 && already.length() == 1 {
    let content = Json::object({
      "message": "Task already completed".to_json(),
      "todo": todo_item_to_model_json(already[0]),
    }).stringify()
    return build_success_result(call, @tool.ToolResult::{
      content,
      is_error: false,
    })
  }
  let completed_count = self.todo_manager.size() -
    self.todo_manager.items.filter(fn(i) { i.status != Completed }).length()
  let total_count = self.todo_manager.size()
  let message = if ids.length() == 1 {
    "Task marked as completed"
  } else {
    "\{completed_now.length()} task(s) marked as completed"
  }
  let result_map : Map[String, Json] = Map([])
  result_map["message"] = message.to_json()
  result_map["progress"] = "\{completed_count}/\{total_count}".to_json()
  result_map["reminder"] = "⚠️ REMINDER: Check the PROJECT-SPECIFIC RULES section in your system prompt before continuing to the next task".to_json()
  if already.length() > 0 {
    result_map["already_completed"] = ToJson::to_json(
      already.map(todo_item_to_model_json),
    )
  }
  if not_found.length() > 0 {
    result_map["not_found"] = ToJson::to_json(not_found)
  }
  match self.todo_manager.next_pending() {
    Some(next) => {
      result_map["next_task"] = todo_item_to_model_json(next)
      result_map["next_task_info"] = "Progress: \{completed_count}/\{total_count}. Next task: #\{todo_int_id(next.id)} - \{next.title}".to_json()
    }
    None => {
      // All tasks completed — auto-clear (Ruby behavior).
      let _ = self.todo_manager.clear_all()
      result_map["all_completed"] = true.to_json()
      result_map["completion_message"] = "All tasks completed and cleared! (\{completed_count}/\{total_count})".to_json()
    }
  }
  build_success_result(call, @tool.ToolResult::{
    content: Json::object(result_map).stringify(),
    is_error: false,
  })
}

///|
/// remove: delete one or more tasks (Ruby remove_todo/remove_todos).
fn Agent::todo_remove(
  self : Agent,
  call : @message.ToolCall,
  args : Map[String, Json],
) -> ToolResultEntry {
  let ids = todo_ids_arg(args)
  if ids.is_empty() {
    return build_error_result(call, "Task ID is required")
  }
  let (removed, not_found) = self.todo_manager.remove_by_ids(ids)
  if removed.is_empty() && not_found.length() == ids.length() {
    return build_error_result(call, "Task not found: \{not_found[0]}")
  }
  let message = if ids.length() == 1 {
    "Task removed"
  } else {
    "\{removed.length()} task(s) removed"
  }
  let result_map : Map[String, Json] = Map([])
  result_map["message"] = message.to_json()
  result_map["remaining"] = self.todo_manager.size().to_json()
  if not_found.length() > 0 {
    result_map["not_found"] = ToJson::to_json(not_found)
  }
  build_success_result(call, @tool.ToolResult::{
    content: Json::object(result_map).stringify(),
    is_error: false,
  })
}

///|
/// clear: wipe all tasks (Ruby clear_todos).
fn Agent::todo_clear(self : Agent, call : @message.ToolCall) -> ToolResultEntry {
  let count = self.todo_manager.clear_all()
  let content = Json::object({
    "message": "All TODOs cleared".to_json(),
    "cleared_count": count.to_json(),
  }).stringify()
  build_success_result(call, @tool.ToolResult::{ content, is_error: false })
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
/// Check whether a tool name is restricted by this agent's subagent
/// forbidden/allowed sets (B7 decision 5). Returns a denial reason, or
/// None when the tool may execute.
///
/// Mirrors Ruby fork_subagent's before_tool_use hook semantics:
/// forbidden_tools deny by exact name; allowed_tools (when set and
/// non-empty) deny everything not listed. Ordinary (non-subagent)
/// agents have both sets empty/None and are never restricted.
fn Agent::tool_restriction_reason(self : Agent, name : String) -> String? {
  for f in self.forbidden_tools {
    if f == name {
      return Some("Tool '\{name}' is forbidden in this subagent context")
    }
  }
  match self.allowed_tools {
    Some(allowed) =>
      if !allowed.is_empty() && !allowed.contains(name) {
        return Some(
          "Tool '\{name}' is not in the allowed tool set for this subagent",
        )
      }
    None => ()
  }
  None
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
