///|
/// Hook system for Agent lifecycle events.
///
/// Provides an observer pattern that allows external components
/// (such as the TUI) to observe and react to Agent execution events
/// without tight coupling.
///
/// Reference: openclacky/lib/clacky/agent/hookable.rb
pub(all) enum HookEvent {
  /// Agent status changed (old_status, new_status).
  StatusChanged(AgentStatus, AgentStatus)
  /// A new ReAct iteration has begun (iteration number).
  BeforeIteration(Int)
  /// A ReAct iteration has completed (iteration number).
  AfterIteration(Int)
  /// About to call the LLM.
  BeforeLlmCall
  /// LLM call completed.
  AfterLlmCall
  /// A new message was added to the conversation history.
  MessageAdded
  /// A tool is about to execute (tool_name, args_json).
  ToolExecuting(String, String)
  /// A tool has completed execution (tool_name, result).
  ToolExecuted(String, ToolResultEntry)
  /// A tool call was denied by the user (tool_name).
  ToolDenied(String)
  /// Token usage tracked for a single LLM call (delta/input/output/cost).
  UsageUpdated(IterationTokenData)
  /// An error occurred during agent execution.
  ErrorOccurred(String)
  /// Agent run completed with final result.
  RunCompleted(RunResult)
  /// LLM streaming response chunk (text fragment).
  StreamChunk(String)
  /// Session started (session_id).
  SessionStarted(String)
  /// Session ended (session_id).
  SessionEnded(String)
  /// Cost updated (new total cost in USD).
  CostUpdated(Double)
  /// Non-fatal warning occurred (message).
  WarningOccurred(String)
  /// File accessed (path, operation: "read"/"write"/"delete").
  FileAccessed(String, String)
  /// Extended thinking phase started.
  ThinkingStarted
  /// Extended thinking phase ended.
  ThinkingEnded
  /// Sub-agent started (agent_name).
  SubagentStarted(String)
  /// Sub-agent ended (agent_name).
  SubagentEnded(String)
  /// Retry attempt (attempt_number, reason).
  RetryAttempt(Int, String)
}

///|
/// Manages hook callback registration and event emission.
///
/// Callbacks are stored as an array and invoked in FIFO order
/// during `emit`. The HookManager is intentionally simple:
/// no filtering, no priority, no async — just fire-and-forget
/// notifications.
pub(all) struct HookManager {
  mut callbacks : Array[(HookEvent) -> Unit]
}

///|
/// Create a new HookManager with no registered callbacks.
pub fn HookManager::new() -> HookManager {
  { callbacks: [] }
}

///|
/// Register a callback to receive all hook events.
///
/// The callback is invoked for every emitted event. If the caller
/// only wants specific events, it should filter inside the callback.
pub fn HookManager::register(
  self : HookManager,
  callback : (HookEvent) -> Unit,
) -> Unit {
  self.callbacks.push(callback)
}

///|
/// Emit a hook event to all registered callbacks.
///
/// Callbacks are invoked in registration order. An error in one
/// callback does not prevent subsequent callbacks from running.
pub fn HookManager::emit(self : HookManager, event : HookEvent) -> Unit {
  for cb in self.callbacks {
    cb(event)
  }
}

///|
/// Remove all registered callbacks.
pub fn HookManager::clear(self : HookManager) -> Unit {
  self.callbacks = []
}
