///|
/// TUI application entry point.
///
/// Phase 5: Full inline TUI with raw-mode event processing,
/// agent hook integration, and multi-line input editing.

///|
/// Entry point: launch the TUI with an initialized agent.
///
/// Opens the terminal in raw mode and starts the event loop.
/// Falls back to a console message if terminal initialization fails.
pub async fn run_tui_interactive(agent : @agent.Agent) -> Unit {
  let tty = @tty.Tty::stdio()
  try tty.with_raw_mode(() => {
    let controller = TuiController::new(tty, agent)
    controller.run()
  }) catch {
    _ => {
      println("TUI initialization failed. Falling back to console mode.")
      println("Use --message to send a message, or --server for web UI.")
    }
  }
}
