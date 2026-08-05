///| Tool execution, permission checking, and result building.

///| Reference: openclacky/lib/clacky/agent/tool_executor.rb

///|

///|
/// Internal result entry for a single tool execution.
pub(all) struct ToolResultEntry {
  /// The tool_call_id this result corresponds to.
  id : String
  /// Result content (tool output or error message).
  content : String
  /// Whether this result represents an error.
  is_error : Bool
} derive(Eq, Debug)

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
  let args = parse_tool_arguments(call)
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
      self.patch_chain.check_after(
        tool_name,
        args,
        result.content,
        result.is_error,
      )
      return result
    }
    "memory" => {
      let result = self.execute_memory_tool(call, args)
      self.patch_chain.check_after(
        tool_name,
        args,
        result.content,
        result.is_error,
      )
      return result
    }
    "todo_manager" => {
      let result = self.execute_todo_tool(call, args)
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
  // Execute — AnyTool implements Tool trait
  let result : @tool.ToolResult = @tool.Tool::execute(tool, args)
  let final_result = if result.is_error {
    build_error_result(call, result.content)
  } else {
    build_success_result(call, result)
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
/// Returns an empty map if arguments are empty or invalid JSON.
pub fn parse_tool_arguments(call : @message.ToolCall) -> Map[String, Json] {
  let args_str = call.function.arguments.trim()
  if args_str.length() == 0 {
    return Map([])
  }
  try {
    let parsed = @json.parse(args_str)
    match parsed {
      Object(obj) => {
        let result : Map[String, Json] = Map([])
        for k, v in obj {
          result[k] = v
        }
        result
      }
      _ => Map([])
    }
  } catch {
    _ => Map([])
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
/// Applies output truncation to prevent context window overflow.
pub fn build_success_result(
  call : @message.ToolCall,
  result : @tool.ToolResult,
) -> ToolResultEntry {
  {
    id: call.id,
    content: truncate_tool_output(result.content),
    is_error: false,
  }
}

///|
/// Build an error result entry from a tool call and error message.
pub fn build_error_result(
  call : @message.ToolCall,
  error_message : String,
) -> ToolResultEntry {
  { id: call.id, content: "{error: \{error_message}}", is_error: true }
}

///|
/// Build a denied result entry when user rejects tool execution.
pub fn build_denied_result(
  call : @message.ToolCall,
  feedback : String?,
) -> ToolResultEntry {
  let msg = match feedback {
    Some(fb) => "{error: \"User denied: \{fb}\", action_performed: false}"
    None => "{error: \"User denied execution\", action_performed: false}"
  }
  { id: call.id, content: msg, is_error: true }
}
