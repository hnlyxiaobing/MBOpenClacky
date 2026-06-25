///|
/// Modal dialog system for the TUI.
///
/// Supports approval, confirmation, alert, and form dialogs with
/// keyboard navigation and text-based rendering.

///|
/// Type of modal dialog.
pub(all) enum DialogType {
  /// Approval dialog (e.g., approve an action).
  Approval
  /// Form dialog with input fields.
  Form
  /// Simple confirmation (yes/no).
  Confirm
  /// Informational alert.
  Alert
} derive(Eq, Debug, Show)

///|
/// A form field definition for Form-type dialogs.
pub(all) struct FormField {
  /// Display label for the field.
  label : String
  /// Field type: "text", "select", "toggle".
  field_type : String
  /// Default value string.
  default_value : String
  /// Available options for "select" type fields.
  options : Array[String]
  /// Whether this field is required.
  required : Bool
} derive(Eq, Debug, Show)

///|
/// Create a simple text input form field.
pub fn FormField::text(
  label : String,
  default_value? : String = "",
) -> FormField {
  { label, field_type: "text", default_value, options: [], required: false }
}

///|
/// Create a required text input form field.
pub fn FormField::required_text(
  label : String,
  default_value? : String = "",
) -> FormField {
  { label, field_type: "text", default_value, options: [], required: true }
}

///|
/// Create a select-type form field with options.
pub fn FormField::select(
  label : String,
  options : Array[String],
  default_value? : String = "",
) -> FormField {
  { label, field_type: "select", default_value, options, required: false }
}

///|
/// Create a toggle-type form field.
pub fn FormField::toggle(
  label : String,
  default_value? : String = "false",
) -> FormField {
  { label, field_type: "toggle", default_value, options: [], required: false }
}

///|
/// A modal dialog with buttons and optional form fields.
pub(all) struct Dialog {
  /// Type of dialog.
  dialog_type : DialogType
  /// Dialog title.
  title : String
  /// Dialog message body.
  message : String
  /// Form fields (for Form type).
  mut form_fields : Array[FormField]
  /// Current form field values.
  mut form_values : Array[String]
  /// Index of the currently selected button.
  mut selected_button : Int
  /// Button labels.
  buttons : Array[String]
  /// Result string after submission.
  mut result : String?
  /// Whether the dialog is currently open.
  mut is_open : Bool
} derive(Debug)

///|
/// Create an approval dialog.
pub fn Dialog::approval(title : String, message : String) -> Dialog {
  {
    dialog_type: Approval,
    title,
    message,
    form_fields: [],
    form_values: [],
    selected_button: 0,
    buttons: ["Approve", "Deny"],
    result: None,
    is_open: false,
  }
}

///|
/// Create a form dialog with the given fields.
pub fn Dialog::form(title : String, fields : Array[FormField]) -> Dialog {
  let values : Array[String] = []
  for field in fields {
    values.push(field.default_value)
  }
  {
    dialog_type: Form,
    title,
    message: "",
    form_fields: fields,
    form_values: values,
    selected_button: 0,
    buttons: ["Submit", "Cancel"],
    result: None,
    is_open: false,
  }
}

///|
/// Create a confirmation dialog.
pub fn Dialog::confirm(title : String, message : String) -> Dialog {
  {
    dialog_type: Confirm,
    title,
    message,
    form_fields: [],
    form_values: [],
    selected_button: 0,
    buttons: ["Yes", "No"],
    result: None,
    is_open: false,
  }
}

///|
/// Create an alert dialog.
pub fn Dialog::alert(title : String, message : String) -> Dialog {
  {
    dialog_type: Alert,
    title,
    message,
    form_fields: [],
    form_values: [],
    selected_button: 0,
    buttons: ["OK"],
    result: None,
    is_open: false,
  }
}

///|
/// Open the dialog for interaction.
pub fn Dialog::open(self : Dialog) -> Unit {
  self.is_open = true
  self.selected_button = 0
  self.result = None
}

///|
/// Close the dialog.
pub fn Dialog::close(self : Dialog) -> Unit {
  self.is_open = false
}

///|
/// Move button selection to the next button.
pub fn Dialog::select_next_button(self : Dialog) -> Unit {
  let n = self.buttons.length()
  if n > 0 {
    self.selected_button = (self.selected_button + 1) % n
  }
}

///|
/// Move button selection to the previous button.
pub fn Dialog::select_prev_button(self : Dialog) -> Unit {
  let n = self.buttons.length()
  if n > 0 {
    self.selected_button = if self.selected_button <= 0 {
      n - 1
    } else {
      self.selected_button - 1
    }
  }
}

///|
/// Submit the dialog, returning the result string.
///
/// For simple dialogs, returns the selected button label.
/// For form dialogs, returns "submit" with form values accessible via form_values.
pub fn Dialog::submit(self : Dialog) -> String? {
  if !self.is_open {
    return None
  }
  let btn = if self.selected_button >= 0 &&
    self.selected_button < self.buttons.length() {
    self.buttons[self.selected_button]
  } else {
    "OK"
  }
  let result_str = btn.to_lower()
  self.result = Some(result_str)
  self.is_open = false
  Some(result_str)
}

///|
/// Update the value of a form field by index.
pub fn Dialog::update_field(self : Dialog, index : Int, value : String) -> Unit {
  if index >= 0 && index < self.form_values.length() {
    self.form_values[index] = value
  }
}

///|
/// Render the dialog as an array of text lines for display.
pub fn Dialog::render(self : Dialog) -> Array[String] {
  let lines : Array[String] = []
  let border_w = 50

  // Top border
  lines.push("╔\{"═".repeat(border_w - 2)}╗")

  // Title
  let title_padded = center_pad(self.title, border_w - 4)
  lines.push("║ \{title_padded} ║")

  // Separator
  lines.push("╠\{"═".repeat(border_w - 2)}╣")

  // Message lines (wrap at border width)
  if self.message.length() > 0 {
    let msg_lines = wrap_text(self.message, border_w - 6)
    for ml in msg_lines {
      lines.push("║  \{pad_right(ml, border_w - 6)}  ║")
    }
  }

  // Form fields
  if self.form_fields.length() > 0 {
    lines.push("║\{" ".repeat(border_w - 2)}║")
    for i = 0; i < self.form_fields.length(); i = i + 1 {
      let field = self.form_fields[i]
      let value = self.form_values[i]
      let field_line = "  \{field.label}: [\{value}]"
      lines.push("║\{pad_right(field_line, border_w - 4)}  ║")
    }
  }

  lines.push("║\{" ".repeat(border_w - 2)}║")

  // Buttons
  let btn_parts : Array[String] = []
  for i = 0; i < self.buttons.length(); i = i + 1 {
    let btn = self.buttons[i]
    if i == self.selected_button {
      btn_parts.push("[\{btn}]")
    } else {
      btn_parts.push(" \{btn} ")
    }
  }
  let btn_line = btn_parts.join("  ")
  let btn_centered = center_pad(btn_line, border_w - 4)
  lines.push("║ \{btn_centered} ║")

  // Bottom border
  lines.push("╚\{"═".repeat(border_w - 2)}╝")

  lines
}

// ── Internal helpers ────────────────────────────────────────────────

///|
/// Pad a string on the right to the given width.
fn pad_right(s : String, width : Int) -> String {
  let pad = width - s.length()
  if pad <= 0 {
    s
  } else {
    s + " ".repeat(pad)
  }
}

///|
/// Center-pad a string within the given width.
fn center_pad(s : String, width : Int) -> String {
  let pad = width - s.length()
  if pad <= 0 {
    s
  } else {
    let left = pad / 2
    let right = pad - left
    " ".repeat(left) + s + " ".repeat(right)
  }
}

///|
/// Simple text wrapping at the given width.
fn wrap_text(text : String, width : Int) -> Array[String] {
  let result : Array[String] = []
  if text.length() <= width {
    result.push(text)
    return result
  }
  // Simple character-based wrapping
  let chars = text.to_array()
  let current = StringBuilder::new()
  for i = 0; i < chars.length(); i = i + 1 {
    if current.to_string().length() >= width {
      result.push(current.to_string())
      current.reset()
    }
    current.write_char(chars[i])
  }
  if current.to_string().length() > 0 {
    result.push(current.to_string())
  }
  result
}
