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
/// - AutoApprove: all tools auto-execute
/// - ConfirmSafes: read-only tools + safe terminal commands auto-execute
/// - ConfirmAll: all tools auto-execute (UI shows confirmation for awareness)
pub fn Agent::should_auto_execute(
  self : Agent,
  tool_name : String,
  tool_params : Map[String, Json],
) -> Bool {
  match self.config.permission_mode {
    @config.AutoApprove => true
    @config.ConfirmSafes => self.is_safe_operation(tool_name, tool_params)
    @config.ConfirmAll => true
  }
}

///|
/// Check if a tool operation is safe for automatic execution.
///
/// Safe operations:
/// - Read-only tools: file_reader, grep, glob
/// - Terminal commands that pass command_safe_for_auto_execution
pub fn Agent::is_safe_operation(
  _self : Agent,
  tool_name : String,
  tool_params : Map[String, Json],
) -> Bool {
  match tool_name {
    "file_reader" | "grep" | "glob" => true
    "terminal" =>
      // Check the command via the security module
      match tool_params.get("command") {
        Some(String(cmd)) => @tool.command_safe_for_auto_execution(cmd)
        _ => false
      }
    _ => false
  }
}

///|
/// Execute a single tool call, resolving the name and dispatching
/// to the ToolRegistry.
///
/// Returns a ToolResultEntry with the execution result.
pub fn Agent::execute_single_tool(
  self : Agent,
  call : @message.ToolCall,
) -> ToolResultEntry {
  let tool_name = call.function.name
  // Resolve canonical name
  let canonical = match self.tool_registry.resolve(tool_name) {
    Some(name) => name
    None => {
      let names = self.tool_registry.tool_names().join(", ")
      return build_error_result(
        call,
        "Unknown tool: \{tool_name}. Available: \{names}",
      )
    }
  }
  // Get the tool instance
  let tool = match self.tool_registry.get(canonical) {
    Some(t) => t
    None =>
      return build_error_result(
        call,
        "Tool '\{canonical}' registered but not found",
      )
  }
  // Parse arguments
  let args = parse_tool_arguments(call)
  // Execute — AnyTool implements Tool trait
  let result : @tool.ToolResult = @tool.Tool::execute(tool, args) catch {
    err =>
      return build_error_result(call, "Tool execution error: \{err.to_repr()}")
  }
  if result.is_error {
    build_error_result(call, result.content)
  } else {
    build_success_result(call, result)
  }
}

///|
/// Parse tool arguments from the JSON string in a ToolCall.
///
/// Returns an empty map if arguments are empty or invalid JSON.
pub fn parse_tool_arguments(call : @message.ToolCall) -> Map[String, Json] {
  let args_str = call.function.arguments.trim()
  if args_str.length() == 0 {
    return {}
  }
  try {
    let parsed = @json.parse(args_str)
    match parsed {
      Object(obj) => {
        let result : Map[String, Json] = {}
        for k, v in obj {
          result[k] = v
        }
        result
      }
      _ => {}
    }
  } catch {
    _ => {}
  }
}

// ── Result Builders ───────────────────────────────────────────────────────────

///|
/// Build a success result entry from a tool call and its result.
pub fn build_success_result(
  call : @message.ToolCall,
  result : @tool.ToolResult,
) -> ToolResultEntry {
  { id: call.id, content: result.content, is_error: false }
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
