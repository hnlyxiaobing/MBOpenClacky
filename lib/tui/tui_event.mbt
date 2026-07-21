///|
/// TUI event types for the async event loop.
///
/// Terminal input, confirmation requests, agent completion and timer ticks
/// are pushed to a single Queue[TuiEvent] and processed by the main loop.
///
/// NOTE: agent hook events do NOT flow through this queue. Hooks are
/// registered with the agent's HookManager as closures that mutate the
/// shared TuiState Ref directly (see agent_hooks.mbt); the single-threaded
/// cooperative async runtime makes this race-free, and the periodic Tick
/// picks up the resulting dirty state. A former HookEvent variant for
/// queued hook delivery was removed as dead code — StreamChunk events
/// emitted by the streaming LLM path (think_async) reach the UI through
/// the same direct-hook mechanism.

///|
pub enum TuiEvent {
  /// Terminal input/resize event.
  Terminal(@tty.Event)
  /// Agent requests tool confirmation: (tool_name, tool_args).
  ConfirmationRequest(String, String)
  /// Agent run completed.
  AgentDone(@agent.RunResult)
  /// Agent run failed with error.
  AgentError(String)
  /// User submitted input text.
  SubmitInput(String)
  /// Periodic tick for spinner/animation (every ~200ms).
  Tick
  /// Terminal reader closed (EOF).
  TerminalClosed
}
