///|
/// Form Dialog rendering using the Node system.
///
/// Renders a multi-field form with text input fields.
/// Supports Tab to switch between fields, character input, backspace,
/// and Enter to submit with required field validation.

///|
/// Render a FormDialog as a Node tree.
pub fn render_form_dialog(dialog : FormDialog) -> Node {
  let children : Array[Node] = []

  for i in 0..<dialog.fields.length() {
    let field = dialog.fields[i]
    let is_focused = i == dialog.focused_idx

    let required_marker = if field.required { " *" } else { "" }

    let label_style = if is_focused {
      Style::new(fg=@color.Color::Basic(@color.BasicColor::Cyan), bold=true)
    } else {
      Style::default_()
    }

    children.push(Node::Text("\{field.label}\{required_marker}:", label_style))

    let display_value = if field.value.length() == 0 && is_focused {
      field.placeholder
    } else if field.value.length() == 0 && field.placeholder.length() > 0 {
      field.placeholder
    } else if field.masked && field.value.length() > 0 {
      mask_api_key(field.value)
    } else {
      field.value
    }

    let value_style = if is_focused {
      Style::new(fg=@color.Color::Basic(@color.BasicColor::White), bold=true)
    } else if field.value.length() == 0 {
      Style::new(dim=true)
    } else {
      Style::default_()
    }

    let cursor = if is_focused { "▌" } else { "" }

    children.push(Node::Text("  \{display_value}\{cursor}", value_style))
    children.push(Node::Text("", Style::default_()))
  }

  // Navigation hints
  children.push(
    Node::Text("Tab Next Field  Enter Submit  Esc Cancel", Style::new(dim=true)),
  )

  Node::Border(Some(dialog.title), children)
}

///|
/// Create a FormDialog from title and field definitions.
pub fn FormDialog::new(
  title : String,
  fields : Array[(String, Bool, String)],
) -> FormDialog {
  let form_fields = fields.map(fn(entry) {
    let (label, required, placeholder) = entry
    { label, value: "", required, placeholder, masked: false }
  })
  { title, fields: form_fields, focused_idx: 0 }
}

///|
/// Create a FormDialog with masked field support.
/// Each entry is (label, required, placeholder, masked).
pub fn FormDialog::new_with_mask(
  title : String,
  fields : Array[(String, Bool, String, Bool)],
) -> FormDialog {
  let form_fields = fields.map(fn(entry) {
    let (label, required, placeholder, masked) = entry
    { label, value: "", required, placeholder, masked }
  })
  { title, fields: form_fields, focused_idx: 0 }
}

///|
/// Move focus to the next field.
pub fn FormDialog::next_field(self : FormDialog) -> Unit {
  self.focused_idx = (self.focused_idx + 1) % self.fields.length()
}

///|
/// Move focus to the previous field.
pub fn FormDialog::prev_field(self : FormDialog) -> Unit {
  if self.focused_idx > 0 {
    self.focused_idx = self.focused_idx - 1
  } else {
    self.focused_idx = self.fields.length() - 1
  }
}

///|
/// Append a character to the focused field's value.
pub fn FormDialog::input_char(self : FormDialog, c : Char) -> Unit {
  let idx = self.focused_idx
  if idx >= 0 && idx < self.fields.length() {
    self.fields[idx].value = self.fields[idx].value + c.to_string()
  }
}

///|
/// Delete the last character from the focused field's value.
pub fn FormDialog::backspace(self : FormDialog) -> Unit {
  let idx = self.focused_idx
  if idx >= 0 && idx < self.fields.length() {
    let val = self.fields[idx].value
    if val.length() > 0 {
      self.fields[idx].value = val[0:val.length() - 1].to_owned()
    }
  }
}

///|
/// Validate all required fields are non-empty.
pub fn FormDialog::validate(self : FormDialog) -> String? {
  for field in self.fields {
    if field.required && field.value.length() == 0 {
      return Some("Required field '\{field.label}' is empty")
    }
  }
  None
}

///|
/// Collect all field values as a key-value map.
pub fn FormDialog::collect_values(self : FormDialog) -> Array[(String, String)] {
  self.fields.map(fn(field) { (field.label, field.value) })
}
