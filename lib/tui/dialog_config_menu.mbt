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
/// Mask an API key for the post-update configuration summary (Ruby
/// cli.rb:283-288): keys of 12+ chars show the first 8 and last 4 around
/// 20 asterisks; shorter keys (including empty) render as "(not set)".
pub fn mask_api_key_summary(key : String) -> String {
  if key.length() >= 12 {
    "\{key[0:8]}\{"*".repeat(20)}\{key[key.length() - 4:]}"
  } else {
    "(not set)"
  }
}

///|
/// Special action item values for the config menu.
const ACTION_ADD : String = "__action_add"

///|
const ACTION_EDIT : String = "__action_edit"

///|
const ACTION_DELETE : String = "__action_delete"

///|
const ACTION_CLOSE : String = "__action_close"

///|
const SEPARATOR_VALUE : String = "__separator"

///|
/// Check if a ConfigMenuItem is a separator (non-selectable).
pub fn is_separator(item : ConfigMenuItem) -> Bool {
  item.value == SEPARATOR_VALUE
}

///|
/// Check if a ConfigMenuItem is an action item.
pub fn is_action(item : ConfigMenuItem) -> Bool {
  item.value == ACTION_ADD ||
  item.value == ACTION_EDIT ||
  item.value == ACTION_DELETE ||
  item.value == ACTION_CLOSE
}

///|
/// Build config menu items from an array of model configs.
/// Highlights the current model and shows masked API keys.
/// Appends action items: separator, Add, Edit, Delete (when >1 model), Close.
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
  // Separator (non-selectable)
  items.push({
    label: "──────────",
    value: SEPARATOR_VALUE,
    multi_select: false,
    checked: false,
  })
  // Action items
  items.push({
    label: "[+] Add New Model",
    value: ACTION_ADD,
    multi_select: false,
    checked: false,
  })
  items.push({
    label: "[*] Edit Current Model",
    value: ACTION_EDIT,
    multi_select: false,
    checked: false,
  })
  if models.length() > 1 {
    items.push({
      label: "[-] Delete Model",
      value: ACTION_DELETE,
      multi_select: false,
      checked: false,
    })
  }
  items.push({
    label: "[X] Close",
    value: ACTION_CLOSE,
    multi_select: false,
    checked: false,
  })
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
/// Provider sub-model names for a model card ([] when its base_url has no
/// provider preset — such cards have no sub-model drawer).
pub fn provider_submodels(model : @config.ModelConfig) -> Array[String] {
  match @config.Providers::resolve(model.base_url) {
    Some(p) => p.models
    None => []
  }
}

///|
/// Build level-1 card items for the /model drawer (Ruby ui2
/// show_model_card_level): current card marked, expandable cards (with
/// provider sub-models) carry a "›" hint.
pub fn build_model_card_items(
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
    // "›" hint only for cards whose provider exposes >= 2 sub-models
    // (Ruby ui_controller.rb:1690) — same threshold as the drawer.
    let arrow = if provider_submodels(m).length() >= 2 { "  ›" } else { "" }
    items.push({
      label: "\{m.model}\{current_marker}\{arrow}",
      value: m.id,
      multi_select: false,
      checked: false,
    })
  }
  items
}

///|
/// Build level-2 sub-model items for one card (Ruby ui2
/// show_model_submodel_level): "Default (<card model>)" first — choosing
/// it clears the per-session sub-model overlay — then every provider
/// sub-model. The active entry mirrors the current overlay.
pub fn build_submodel_items(
  card : @config.ModelConfig,
  overlay : String?,
) -> Array[ConfigMenuItem] {
  let items : Array[ConfigMenuItem] = []
  let default_marker = match overlay {
    Some(_) => ""
    None => " (active)"
  }
  items.push({
    label: "Default (\{card.model})\{default_marker}",
    value: "",
    multi_select: false,
    checked: false,
  })
  for name in provider_submodels(card) {
    let marker = match overlay {
      Some(o) if o == name => " (active)"
      _ => ""
    }
    items.push({
      label: name + marker,
      value: name,
      multi_select: false,
      checked: false,
    })
  }
  items
}

///|
/// Create a Time Machine navigation dialog from enriched task entries
/// (Ruby ui2 show_time_machine_menu). Markers: ● current, · on-path
/// history, ✗ undone/abandoned branch, ⎇ has branches. The cursor lands
/// on the current task.
pub fn ConfigMenuDialog::as_time_machine(
  entries : Array[@agent.TaskHistoryEntry],
) -> ConfigMenuDialog {
  let items : Array[ConfigMenuItem] = []
  let mut current_idx = 0
  for i = 0; i < entries.length(); i = i + 1 {
    let e = entries[i]
    let marker = match e.status {
      Current => {
        current_idx = i
        "● "
      }
      Undone => "✗ "
      Past => "· "
    }
    let branch = if e.has_branches { "⎇ " } else { "" }
    let summary = truncate_to_display_width(e.summary, 60)
    let suffix = if e.status is Undone { "  (undone)" } else { "" }
    items.push({
      label: "\{marker}\{branch}Task \{e.task_num}: \{summary}\{suffix}",
      value: e.task_id,
      multi_select: false,
      checked: false,
    })
  }
  let dialog = ConfigMenuDialog::new(
    "Time Machine - Select Task to Navigate", items,
  )
  dialog.selected_idx = current_idx
  dialog
}

///|
/// Truncate a string to fit within max display columns, appending "…" if truncated.
fn truncate_to_display_width(s : String, max_w : Int) -> String {
  if max_w <= 0 {
    return ""
  }
  let w = display_width(s)
  if w <= max_w {
    return s
  }
  // Reserve 1 column for the ellipsis character.
  let target = max_w - 1
  let mut acc = ""
  let mut acc_w = 0
  let chars = s.to_array()
  let mut i = 0
  while i < chars.length() {
    let cw = @tui_core.char_display_width(chars[i])
    if acc_w + cw > target {
      break
    }
    acc = acc + chars[i].to_string()
    acc_w = acc_w + cw
    i = i + 1
  }
  acc + "…"
}

///|
/// Render a ConfigMenuDialog as a Node tree.
/// When `term_width` > 0, labels are truncated to fit within the terminal
/// width (minus border overhead) so the dialog never overflows horizontally.
/// `hints` overrides the footer shortcut line (default: config menu hints).
pub fn render_config_menu(
  dialog : ConfigMenuDialog,
  term_width? : Int = 0,
  hints? : String? = None,
) -> Node {
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

    let style = if is_separator(item) {
      Style::new(dim=true)
    } else if is_selected {
      Style::new(fg=@color.Color::Basic(@color.BasicColor::Cyan), bold=true)
    } else {
      Style::default_()
    }

    let value_display = if item.value.length() > 0 &&
      is_separator(item) == false &&
      is_action(item) == false {
      " (\{item.value})"
    } else {
      ""
    }

    let raw_label = if is_separator(item) {
      item.label
    } else {
      "\{marker} \{label}\{value_display}"
    }
    // Truncate to fit terminal width when term_width is specified.
    let max_content = if term_width > 0 {
      // Border adds 2 chars (left + right), plus 2 for margin safety.
      term_width - 4
    } else {
      0 // 0 = no limit
    }
    let final_label = if max_content > 0 {
      truncate_to_display_width(raw_label, max_content)
    } else {
      raw_label
    }
    children.push(Node::Text(final_label, style))

    i = i + 1
  }

  // Navigation hints — abbreviate for narrow terminals.
  let hints = match hints {
    Some(h) => h
    None =>
      if term_width > 0 && term_width < 70 {
        "↑↓ Navigate  Enter Select  Esc Close"
      } else {
        "↑↓/jk Navigate  Enter Select  a Add  e Edit  d Delete  Esc Close"
      }
  }
  let max_content = if term_width > 0 { term_width - 4 } else { 0 }
  let final_hints = if max_content > 0 {
    truncate_to_display_width(hints, max_content)
  } else {
    hints
  }
  children.push(Node::Text("", Style::default_()))
  children.push(Node::Text(final_hints, Style::new(dim=true)))

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
/// Move selection up, skipping separator items.
pub fn ConfigMenuDialog::move_up(self : ConfigMenuDialog) -> Unit {
  let mut idx = self.selected_idx
  while idx > 0 {
    idx = idx - 1
    if !is_separator(self.items[idx]) {
      self.selected_idx = idx
      return
    }
  }
}

///|
/// Move selection down, skipping separator items.
pub fn ConfigMenuDialog::move_down(self : ConfigMenuDialog) -> Unit {
  let mut idx = self.selected_idx
  while idx < self.items.length() - 1 {
    idx = idx + 1
    if !is_separator(self.items[idx]) {
      self.selected_idx = idx
      return
    }
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
