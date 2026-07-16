///|
/// TUI event types for the async event loop.
///
/// All events (terminal input, agent hooks, confirmation requests,
/// timer ticks, agent completion) are pushed to a single Queue[TuiEvent]
/// and processed by the main loop.

///|
pub enum TuiEvent {
  /// Terminal input/resize event.
  Terminal(@tty.Event)
  /// Agent hook event (status, tool, streaming, etc.).
  HookEvent(@agent.HookEvent)
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
