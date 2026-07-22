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

// ── Multi-step config modal lifecycle ──────────────────────────

///|
/// Open the config menu dialog from the agent's current model configuration.
pub fn open_config_menu(state : TuiState, agent : @agent.Agent) -> Unit {
  let dialog = ConfigMenuDialog::from_models(
    agent.config.models,
    agent.config.current_model_id,
  )
  state.dialog = DialogState::ConfigMenu(dialog)
}

///|
/// Open the model selector dialog from the agent's current model configuration.
pub fn open_model_selector(state : TuiState, agent : @agent.Agent) -> Unit {
  let dialog = ConfigMenuDialog::as_model_selector(
    agent.config.models,
    agent.config.current_model_id,
  )
  state.dialog = DialogState::ConfigMenu(dialog)
}

///|
/// Transition from config menu to an Add form.
pub fn open_add_form(state : TuiState, mode : ConfigMode) -> Unit {
  let fields = [
    ("name", true, "my-model", false),
    ("model", true, "gpt-4o", false),
    ("api_key", true, "sk-...", true),
    ("base_url", true, "https://api.openai.com/v1", false),
  ]
  let form = FormDialog::new_with_mask("Add Model", fields)
  state.dialog = ConfigForm(mode~, form~, action=Add, target_idx=-1)
}

///|
/// Transition from config menu to an Edit form for the selected model.
///
/// The model id ("name") is immutable and therefore not editable; the form
/// only exposes model / api_key / base_url (see tui-parity review: editing
/// the name used to be a no-op that pretended to succeed).
pub fn open_edit_form(
  state : TuiState,
  mode : ConfigMode,
  model : @config.ModelConfig,
  idx : Int,
) -> Unit {
  let fields = [
    ("model", true, "gpt-4o", false),
    ("api_key", true, "sk-...", true),
    ("base_url", true, "https://api.openai.com/v1", false),
  ]
  let form = FormDialog::new_with_mask("Edit Model", fields)
  // Pre-fill with existing values
  form.fields[0].value = model.model
  form.fields[1].value = model.api_key
  form.fields[2].value = model.base_url
  state.dialog = ConfigForm(mode~, form~, action=Edit, target_idx=idx)
}

///|
/// Return from form back to the config menu.
pub fn return_to_config_menu(
  state : TuiState,
  agent : @agent.Agent,
  mode : ConfigMode,
) -> Unit {
  match mode {
    ConfigMenu => open_config_menu(state, agent)
    ModelSelector => open_model_selector(state, agent)
  }
}

///|
/// Close any config-related dialog and return to normal state.
pub fn close_config_dialog(state : TuiState) -> Unit {
  state.dialog = DialogState::NoDialog
}

///|
/// Build a config form for model editing with pre-filled values.
pub fn build_model_form(
  title : String,
  model : @config.ModelConfig?,
) -> FormDialog {
  let fields = [
    ("name", true, "my-model", false),
    ("model", true, "gpt-4o", false),
    ("api_key", true, "sk-...", true),
    ("base_url", true, "https://api.openai.com/v1", false),
  ]
  let form = FormDialog::new_with_mask(title, fields)
  match model {
    Some(m) => {
      form.fields[0].value = m.id
      form.fields[1].value = m.model
      form.fields[2].value = m.api_key
      form.fields[3].value = m.base_url
    }
    None => ()
  }
  form
}
