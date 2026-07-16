///|
/// Msg-driven interaction system (inspired by Elm architecture).
///
/// TuiMsg represents semantic user actions. The `update` function
/// transforms TuiState based on a Msg, returning a TuiCmd for side effects.
/// This keeps state transitions testable and separates logic from I/O.

///|
/// Semantic message types for TUI interactions.
pub enum TuiMsg {
  // ── Input ──
  KeyChar(Char)
  KeyEnter
  KeyBackspace
  KeyDelete
  KeyArrow(Direction)
  KeyHome
  KeyEnd
  KeyCtrl(Char)
  KeyTab
  KeyEscape
  KeyPaste(String)
  // ── Agent ──
  SubmitInput(String)
  CancelAgent
  // ── Dialog ──
  DialogApprove
  DialogDeny
  DialogToggleDetails
  DialogSelectItem(Int)
  DialogToggleItem(Int)
  DialogConfirm
  DialogCancel
  // ── Shell ──
  SwitchMode(ShellMode)
  // ── System ──
  Redraw
  Resize(Int, Int)
} derive(Eq)

///|
/// Arrow direction for key navigation.
pub enum Direction {
  Up
  Down
  Left
  Right
} derive(Eq)

///|
/// Command returned by `update`, describing side effects to perform.
pub enum TuiCmd {
  /// No action needed.
  None
  /// Redraw the screen.
  Redraw
  /// Submit text to the agent.
  SubmitToAgent(String)
  /// Cancel the running agent.
  CancelAgentTask
  /// Full screen redraw.
  FullRedraw
  /// Quit the TUI.
  Quit
}

///|
/// Pure state update function: applies a Msg to TuiState, returns Cmd.
///
/// This function does NOT perform I/O. It only updates state and returns
/// a Cmd describing what side effects the controller should perform.
pub fn update(state : TuiState, msg : TuiMsg) -> TuiCmd {
  match msg {
    // ── Dialog handling ──
    DialogToggleDetails =>
      match state.dialog {
        Approval(d) => {
          d.show_details = !d.show_details
          Redraw
        }
        _ => None
      }
    DialogSelectItem(idx) =>
      match state.dialog {
        ConfigMenu(d) => {
          if idx >= 0 && idx < d.items.length() {
            d.selected_idx = idx
          }
          Redraw
        }
        _ => None
      }
    DialogToggleItem(idx) =>
      match state.dialog {
        ConfigMenu(d) => {
          if idx >= 0 && idx < d.checked.length() {
            d.checked[idx] = !d.checked[idx]
          }
          Redraw
        }
        _ => None
      }
    // ── Shell mode ──
    SwitchMode(mode) => {
      state.shell_mode = mode
      FullRedraw
    }
    // ── System ──
    Redraw => Redraw
    Resize(_, _) => FullRedraw
    // ── Default: no-op (controller handles input directly) ──
    _ => None
  }
}
