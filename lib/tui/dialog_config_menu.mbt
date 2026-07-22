///|
/// Config Menu Dialog rendering using the Node system.
///
/// Renders a configuration menu with selectable items.
/// Supports both single-select (radio) and multi-select (checkbox) modes.
/// Keyboard navigation: Up/Down/j/k to move, Space to toggle, Enter to confirm.

///|
/// Maximum visible items before scrolling.
let config_menu_max_visible = 10

///|
/// Mask an API key for display: show first 3 and last 4 characters.
/// e.g. "sk-ant-abc123xyz789" -> "sk-...z789"
pub fn mask_api_key(key : String) -> String {
  let len = key.length()
  if len <= 8 {
    "****"
  } else {
    "\{key[0:3]}...\{key[len - 4:]}"
  }
}

///|
/// Build config menu items from an array of model configs.
/// Highlights the current model and shows masked API keys.
pub fn build_config_menu_items(
  models : Array[@config.ModelConfig],
  current_model_id : String?,
) -> Array[ConfigMenuItem] {
  let items : Array[ConfigMenuItem] = []
  for m in models {
    let is_current = match current_model_id {
      Some(id) => id == m.id
      None => false
    }
    let type_badge = match m.type_ {
      Some(t) => "[\{t}]"
      None => ""
    }
    let masked = mask_api_key(m.api_key)
    let current_marker = if is_current { " ●" } else { "" }
    let label = "\{m.model} \{type_badge} \{masked}\{current_marker}"
    items.push({ label, value: m.id, multi_select: false, checked: false })
  }
  items
}

///|
/// Build model selector items (simpler, just model name + current marker).
pub fn build_model_selector_items(
  models : Array[@config.ModelConfig],
  current_model_id : String?,
) -> Array[ConfigMenuItem] {
  let items : Array[ConfigMenuItem] = []
  for m in models {
    let is_current = match current_model_id {
      Some(id) => id == m.id
      None => false
    }
    let current_marker = if is_current { " (active)" } else { "" }
    items.push({
      label: "\{m.model}\{current_marker}",
      value: m.id,
      multi_select: false,
      checked: false,
    })
  }
  items
}

///|
/// Create a config menu dialog from model configs.
pub fn ConfigMenuDialog::from_models(
  models : Array[@config.ModelConfig],
  current_model_id : String?,
) -> ConfigMenuDialog {
  let items = build_config_menu_items(models, current_model_id)
  ConfigMenuDialog::new("Configuration Menu", items)
}

///|
/// Create a model selector dialog from model configs.
pub fn ConfigMenuDialog::as_model_selector(
  models : Array[@config.ModelConfig],
  current_model_id : String?,
) -> ConfigMenuDialog {
  let items = build_model_selector_items(models, current_model_id)
  ConfigMenuDialog::new("Select Model", items)
}

///|
/// Render a ConfigMenuDialog as a Node tree.
pub fn render_config_menu(dialog : ConfigMenuDialog) -> Node {
  let children : Array[Node] = []

  let visible_start = if dialog.selected_idx >= config_menu_max_visible {
    dialog.selected_idx - config_menu_max_visible + 1
  } else {
    0
  }

  let visible_end = if dialog.items.length() <
    visible_start + config_menu_max_visible {
    dialog.items.length()
  } else {
    visible_start + config_menu_max_visible
  }

  let mut i = visible_start
  while i < visible_end {
    let item = dialog.items[i]
    let is_selected = i == dialog.selected_idx

    let marker = if item.multi_select {
      if dialog.checked[i] {
        "[x]"
      } else {
        "[ ]"
      }
    } else if is_selected {
      "( )"
    } else {
      "   "
    }

    let label = if is_selected {
      "▶ \{item.label}"
    } else {
      "  \{item.label}"
    }

    let style = if is_selected {
      Style::new(fg=@color.Color::Basic(@color.BasicColor::Cyan), bold=true)
    } else {
      Style::default_()
    }

    let value_display = if item.value.length() > 0 {
      " (\{item.value})"
    } else {
      ""
    }

    children.push(Node::Text("\{marker} \{label}\{value_display}", style))

    i = i + 1
  }

  // Navigation hints
  children.push(Node::Text("", Style::default_()))
  children.push(
    Node::Text(
      "↑↓/jk Navigate  Enter Select  a Add  e Edit  d Delete  Esc Close",
      Style::new(dim=true),
    ),
  )

  Node::Border(Some(dialog.title), children)
}

///|
/// Create a ConfigMenuDialog from title and items.
pub fn ConfigMenuDialog::new(
  title : String,
  items : Array[ConfigMenuItem],
) -> ConfigMenuDialog {
  let checked = items.map(fn(_item) { false })
  { title, items, selected_idx: 0, checked }
}

///|
/// Move selection up.
pub fn ConfigMenuDialog::move_up(self : ConfigMenuDialog) -> Unit {
  if self.selected_idx > 0 {
    self.selected_idx = self.selected_idx - 1
  }
}

///|
/// Move selection down.
pub fn ConfigMenuDialog::move_down(self : ConfigMenuDialog) -> Unit {
  if self.selected_idx < self.items.length() - 1 {
    self.selected_idx = self.selected_idx + 1
  }
}

///|
/// Toggle the checked state of the current item (multi-select only).
pub fn ConfigMenuDialog::toggle_current(self : ConfigMenuDialog) -> Unit {
  let idx = self.selected_idx
  if idx >= 0 && idx < self.checked.length() {
    if self.items[idx].multi_select {
      self.checked[idx] = !self.checked[idx]
    }
  }
}

///|
/// Get the selected item (for single-select mode).
pub fn ConfigMenuDialog::get_selected(
  self : ConfigMenuDialog,
) -> ConfigMenuItem? {
  if self.selected_idx >= 0 && self.selected_idx < self.items.length() {
    Some(self.items[self.selected_idx])
  } else {
    None
  }
}

///|
/// Get all checked items (for multi-select mode).
pub fn ConfigMenuDialog::get_checked(
  self : ConfigMenuDialog,
) -> Array[ConfigMenuItem] {
  let result = []
  for i in 0..<self.items.length() {
    if i < self.checked.length() && self.checked[i] {
      result.push(self.items[i])
    }
  }
  result
}
