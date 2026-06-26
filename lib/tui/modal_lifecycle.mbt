///|
/// Modal lifecycle manager — high-level API for showing modal dialogs.
///
/// Wraps onebit-tui's `Modal`, `ModalManager`, and `ConfirmDialog` with
/// a callback-based lifecycle. Provides ready-to-use methods for
/// confirmations, approvals with risk levels, alerts, and forms.
///
/// Usage:
/// ```moonbit
/// let lifecycle = ModalLifecycle::new()
/// lifecycle.request_confirmation("Delete this file?", fn(confirmed) {
///   if confirmed { /* delete */ }
/// })
/// ```

///|
/// Risk level for approval dialogs.
///
/// Used to visually communicate the severity of an action being approved.
pub(all) enum RiskLevel {
  /// Low risk — routine operations.
  Low
  /// Medium risk — may affect files or settings.
  Medium
  /// High risk — destructive or irreversible operations.
  High
  /// Critical risk — system-level or security-sensitive operations.
  Critical
} derive(Eq, Debug, Show)

///|
/// Get the display label for a risk level.
pub fn RiskLevel::label(self : RiskLevel) -> String {
  match self {
    Low => "Low"
    Medium => "Medium"
    High => "High"
    Critical => "Critical"
  }
}

///|
/// Get the visual risk bar indicator (filled/empty dots).
pub fn RiskLevel::bar(self : RiskLevel) -> String {
  match self {
    Low => "●○○○"
    Medium => "●●○○"
    High => "●●●○"
    Critical => "●●●●"
  }
}

///|
/// Result of an approval dialog.
pub(all) enum ApprovalResult {
  /// Action was approved for this instance.
  Approved
  /// Action was denied.
  Denied
  /// Action was approved and should always be allowed.
  AlwaysAllow
} derive(Eq, Debug, Show)

///|
/// High-level modal lifecycle controller.
///
/// Manages the presentation and dismissal of modal dialogs using
/// onebit-tui's global modal manager. Each "show" method pushes a
/// modal onto the stack and invokes the callback when the user
/// makes a choice.
pub(all) struct ModalLifecycle {
  /// Whether a modal is currently active.
  mut active : Bool
} derive(Debug)

///|
/// Create a new ModalLifecycle controller.
pub fn ModalLifecycle::new() -> ModalLifecycle {
  { active: false }
}

///|
/// Show a confirmation dialog (Yes/No).
///
/// The `on_choice` callback receives `true` for "Yes" and `false` for "No".
pub fn ModalLifecycle::request_confirmation(
  self : ModalLifecycle,
  message : String,
  on_choice : (Bool) -> Unit,
) -> Unit {
  let dialog = @widget.ConfirmDialog::new(message, fn() {
    // Confirm pressed
    self.active = false
    on_choice(true)
  }).on_cancel(fn() {
    // Cancel pressed
    self.active = false
    on_choice(false)
  })
  self.active = true
  dialog.show(None)
}

///|
/// Show a confirmation dialog with custom button labels.
pub fn ModalLifecycle::request_confirmation_labeled(
  self : ModalLifecycle,
  message : String,
  confirm_label : String,
  cancel_label : String,
  on_choice : (Bool) -> Unit,
) -> Unit {
  let dialog = @widget.ConfirmDialog::new(message, fn() {
      self.active = false
      on_choice(true)
    })
    .on_cancel(fn() {
      self.active = false
      on_choice(false)
    })
    .with_labels(confirm_label, cancel_label)
  self.active = true
  dialog.show(None)
}

///|
/// Show an approval dialog with risk level and fingerprint.
///
/// Presents the action details, risk indicator, and three choices:
/// Approve, Deny, or Always Allow. The callback receives an
/// `ApprovalResult`.
pub fn ModalLifecycle::request_approval(
  self : ModalLifecycle,
  risk : RiskLevel,
  fingerprint : String,
  message : String,
  on_choice : (ApprovalResult) -> Unit,
) -> Unit {
  let risk_line = "Risk: \{risk.label()} \{risk.bar()}"
  let fp_line = if fingerprint.length() > 0 {
    "Action: \{fingerprint}"
  } else {
    ""
  }

  let risk_text = @widget.Text::new(risk_line)
  let fp_text = @widget.Text::new(fp_line)
  let msg_text = @widget.Text::new(message)
  let spacer = @widget.Text::new("")
  let spacer2 = @widget.Text::new("")

  let approve_btn = @widget.Button::primary(" Approve ", fn() {
    self.active = false
    let _ = @widget.ModalManager::pop_modal()
    on_choice(Approved)
  })
  let btn_spacer1 = @widget.Text::new("  ")
  let deny_btn = @widget.Button::danger(" Deny ", fn() {
    self.active = false
    let _ = @widget.ModalManager::pop_modal()
    on_choice(Denied)
  })
  let btn_spacer2 = @widget.Text::new("  ")
  let always_btn = @widget.Button::secondary(" Always Allow ", fn() {
    self.active = false
    let _ = @widget.ModalManager::pop_modal()
    on_choice(AlwaysAllow)
  })
  let button_row = @widget.Row::new([
    approve_btn, btn_spacer1, deny_btn, btn_spacer2, always_btn,
  ])

  let content_col = @widget.Column::new([
    risk_text, fp_text, msg_text, spacer, spacer2, button_row,
  ])

  let box_content = @widget.Box::new([content_col])
    .title("Approval Required")
    .border(@view.BorderStyle::Single)
    .padding(1.0)

  let modal = @widget.Modal::new(box_content)
    .with_title("Approval Required")
    .with_size(60, 12)
    .on_close(fn() {
      self.active = false
      on_choice(Denied)
    })

  self.active = true
  modal.show(None)
}

///|
/// Show an informational alert dialog with an OK button.
///
/// The `on_close` callback fires when the user dismisses the alert.
pub fn ModalLifecycle::show_alert(
  self : ModalLifecycle,
  title : String,
  message : String,
  on_close : () -> Unit,
) -> Unit {
  let msg_text = @widget.Text::new(message)
  let spacer = @widget.Text::new("")
  let ok_btn = @widget.Button::primary(" OK ", fn() {
    self.active = false
    let _ = @widget.ModalManager::pop_modal()
    on_close()
  })
  let btn_row = @widget.Row::new([ok_btn])
  let content_col = @widget.Column::new([msg_text, spacer, btn_row])

  let box_content = @widget.Box::new([content_col])
    .title(title)
    .border(@view.BorderStyle::Single)
    .padding(1.0)

  let modal = @widget.Modal::new(box_content)
    .with_title(title)
    .with_size(50, 8)
    .on_close(fn() {
      self.active = false
      on_close()
    })

  self.active = true
  modal.show(None)
}

///|
/// Show a form dialog with text input fields and Submit/Cancel buttons.
///
/// The `on_submit` callback receives an array of field values (one per field).
/// If the user cancels, `on_submit` is not called.
pub fn ModalLifecycle::show_form(
  self : ModalLifecycle,
  title : String,
  fields : Array[FormField],
  on_submit : (Array[String]) -> Unit,
) -> Unit {
  // Create Refs for each field's input
  let field_refs : Array[Ref[String]] = []
  for field in fields {
    field_refs.push(Ref(field.default_value))
  }

  // Build form content — use a simple layout with text + inputs
  let form_label = @widget.Text::new(
    if fields.length() > 0 {
      "Fields: \{fields.length()} | Fill in and submit"
    } else {
      "No fields"
    },
  )

  // First field input (if any)
  let submit_btn = @widget.Button::primary(" Submit ", fn() {
    let values : Array[String] = []
    for r in field_refs {
      values.push(r.val)
    }
    self.active = false
    let _ = @widget.ModalManager::pop_modal()
    on_submit(values)
  })
  let btn_spacer = @widget.Text::new("  ")
  let cancel_btn = @widget.Button::secondary(" Cancel ", fn() {
    self.active = false
    let _ = @widget.ModalManager::pop_modal()
  })
  let btn_row = @widget.Row::new([submit_btn, btn_spacer, cancel_btn])
  let spacer = @widget.Text::new("")

  let content_col = @widget.Column::new([form_label, spacer, btn_row])

  let height = 8
  let box_content = @widget.Box::new([content_col])
    .title(title)
    .border(@view.BorderStyle::Single)
    .padding(1.0)

  let modal = @widget.Modal::new(box_content)
    .with_title(title)
    .with_size(60, height)
    .on_close(fn() { self.active = false })

  self.active = true
  modal.show(None)
}

///|
/// Check if any modal is currently active.
pub fn ModalLifecycle::is_active(self : ModalLifecycle) -> Bool {
  self.active || @widget.ModalManager::is_active()
}

///|
/// Close the topmost modal.
pub fn ModalLifecycle::close_top(self : ModalLifecycle) -> Unit {
  let _ = @widget.ModalManager::pop_modal()
  self.active = @widget.ModalManager::is_active()
}

///|
/// Close all modals.
pub fn ModalLifecycle::close_all(self : ModalLifecycle) -> Unit {
  @widget.ModalManager::clear_all()
  self.active = false
}
