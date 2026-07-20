///|
/// Modal lifecycle state machine for confirmation dialogs.
///
/// Manages the state transitions for tool approval prompts:
/// ```
/// Idle → (agent requests confirmation) → PendingConfirm
///      → (user presses y/Enter) → ResultReady(true)  → (agent consumes) → Idle
///      → (user presses n/Escape) → ResultReady(false) → (agent consumes) → Idle
/// ```
///
/// This is a pure state machine — key reading is done by the TUI callback.
/// Functions are designed to be testable without a real terminal.

///|
/// Set the pending confirmation on TuiState.
///
/// Called by the agent confirmation callback before rendering.
pub fn request_confirmation(
  state : TuiState,
  tool_name : String,
  tool_args : String,
  prompt_text : String,
  default_yes? : Bool = false,
) -> Unit {
  state.pending_confirmation = Some({
    tool_name,
    tool_args,
    prompt_text,
    default_yes,
  })
}

///|
/// Process a key input for the pending confirmation.
///
/// Parameters:
/// - `key_char`: The character pressed (Some('y'), Some('n'), None for special keys)
/// - `is_enter`: Whether the Enter key was pressed
/// - `is_escape`: Whether the Escape key was pressed
///
/// Returns:
/// - `Some(true)` if the user approved
/// - `Some(false)` if the user denied
/// - `None` if the input is not a confirmation key (still waiting)
///
/// No-ops if there is no pending confirmation.
pub fn handle_confirmation_input(
  state : TuiState,
  key_char : Char?,
  is_enter : Bool,
  is_escape : Bool,
) -> Bool? {
  let pending = match state.pending_confirmation {
    Some(p) => p
    None => return None
  }
  // Process key
  match key_char {
    Some(c) =>
      if c == 'y' || c == 'Y' {
        Some(true)
      } else if c == 'n' || c == 'N' {
        Some(false)
      } else {
        None // Not a confirmation key, keep waiting
      }
    None =>
      if is_enter {
        // Enter uses the default
        Some(pending.default_yes)
      } else if is_escape {
        // Escape cancels (denies)
        Some(false)
      } else {
        None // Not a confirmation key
      }
  }
}

///|
/// Consume the confirmation result and clear the pending state.
///
/// Returns the result if available, None if no confirmation was pending
/// or no result has been produced yet.
///
/// This function always clears `pending_confirmation`.
pub fn consume_confirmation(state : TuiState) -> Unit {
  state.pending_confirmation = None
}

///|
/// Check whether a confirmation prompt is currently pending.
pub fn has_pending_confirmation(state : TuiState) -> Bool {
  match state.pending_confirmation {
    Some(_) => true
    None => false
  }
}

///|
/// Get the prompt text for the pending confirmation, or empty string.
pub fn confirmation_prompt_text(state : TuiState) -> String {
  match state.pending_confirmation {
    Some(p) => p.prompt_text
    None => ""
  }
}

///|
/// Get the default yes flag for the pending confirmation.
/// Returns false if no confirmation is pending.
pub fn confirmation_default_yes(state : TuiState) -> Bool {
  match state.pending_confirmation {
    Some(p) => p.default_yes
    None => false
  }
}
