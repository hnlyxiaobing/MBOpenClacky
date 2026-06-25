///|
/// Sidebar panel for navigation and session management.
///
/// Provides a vertical list of selectable items with icons, badges,
/// and keyboard navigation. Can be toggled visible/hidden.

///|
/// A single item in the sidebar.
pub(all) struct SidebarItem {
  /// Unique identifier.
  id : String
  /// Display label.
  label : String
  /// Optional icon character or emoji.
  icon : String?
  /// Optional badge text (e.g., count indicator).
  mut badge : String?
  /// Whether this item is currently selected.
  mut selected : Bool
} derive(Eq, Debug, Show)

///|
/// Create a sidebar item.
pub fn SidebarItem::new(id : String, label : String) -> SidebarItem {
  { id, label, icon: None, badge: None, selected: false }
}

///|
/// Create a sidebar item with an icon.
pub fn SidebarItem::with_icon(
  id : String,
  label : String,
  icon : String,
) -> SidebarItem {
  { id, label, icon: Some(icon), badge: None, selected: false }
}

///|
/// Sidebar panel containing navigable items.
pub(all) struct SidebarPanel {
  /// Panel title displayed at the top.
  title : String
  /// List of items in the sidebar.
  mut items : Array[SidebarItem]
  /// Index of the currently selected item.
  mut selected_index : Int
  /// Whether the sidebar is visible.
  mut visible : Bool
  /// Width of the sidebar in columns.
  width : Int
} derive(Debug)

///|
/// Create a new sidebar panel.
pub fn SidebarPanel::new(title : String, width : Int) -> SidebarPanel {
  { title, items: [], selected_index: 0, visible: false, width }
}

///|
/// Add an item to the sidebar.
pub fn SidebarPanel::add_item(self : SidebarPanel, item : SidebarItem) -> Unit {
  // If this is the first item, select it
  if self.items.length() == 0 {
    item.selected = true
  }
  self.items.push(item)
}

///|
/// Remove an item by id.
pub fn SidebarPanel::remove_item(self : SidebarPanel, id : String) -> Unit {
  let new_items : Array[SidebarItem] = []
  let mut removed_idx = -1
  for i = 0; i < self.items.length(); i = i + 1 {
    if self.items[i].id == id {
      removed_idx = i
    } else {
      new_items.push(self.items[i])
    }
  }
  // Rebuild items
  self.items.clear()
  for item in new_items {
    self.items.push(item)
  }
  // Adjust selection
  if removed_idx >= 0 && self.items.length() > 0 {
    if self.selected_index >= self.items.length() {
      self.selected_index = self.items.length() - 1
    }
    // Update selection state
    for i = 0; i < self.items.length(); i = i + 1 {
      self.items[i].selected = i == self.selected_index
    }
  }
}

///|
/// Select the next item in the list.
pub fn SidebarPanel::select_next(self : SidebarPanel) -> Unit {
  if self.items.length() == 0 {
    return
  }
  // Deselect current
  self.items[self.selected_index].selected = false
  self.selected_index = (self.selected_index + 1) % self.items.length()
  self.items[self.selected_index].selected = true
}

///|
/// Select the previous item in the list.
pub fn SidebarPanel::select_prev(self : SidebarPanel) -> Unit {
  if self.items.length() == 0 {
    return
  }
  self.items[self.selected_index].selected = false
  self.selected_index = if self.selected_index <= 0 {
    self.items.length() - 1
  } else {
    self.selected_index - 1
  }
  self.items[self.selected_index].selected = true
}

///|
/// Get the currently selected item, or None if empty.
pub fn SidebarPanel::get_selected(self : SidebarPanel) -> SidebarItem? {
  if self.items.length() == 0 {
    None
  } else {
    Some(self.items[self.selected_index])
  }
}

///|
/// Toggle sidebar visibility.
pub fn SidebarPanel::toggle_visibility(self : SidebarPanel) -> Unit {
  self.visible = !self.visible
}

///|
/// Update the badge text for an item identified by id.
pub fn SidebarPanel::update_badge(
  self : SidebarPanel,
  id : String,
  badge : String,
) -> Unit {
  for item in self.items {
    if item.id == id {
      item.badge = Some(badge)
      return
    }
  }
}

///|
/// Render the sidebar as an array of text lines.
pub fn SidebarPanel::render(self : SidebarPanel) -> Array[String] {
  let lines : Array[String] = []
  let w = self.width

  // Title bar
  let title_trunc = truncate_str(self.title, w - 4)
  lines.push(pad_or_truncate(" ┌\{title_trunc}", w))

  // Separator
  lines.push(pad_or_truncate(" │", w))

  // Items
  for i = 0; i < self.items.length(); i = i + 1 {
    let item = self.items[i]
    let prefix = if item.selected { "▸ " } else { "  " }
    let icon_str = match item.icon {
      Some(ic) => "\{ic} "
      None => ""
    }
    let badge_str = match item.badge {
      Some(b) => " [\{b}]"
      None => ""
    }
    let label_max = w - 4 - icon_str.length() - badge_str.length()
    let label_trunc = truncate_str(item.label, label_max)
    let line = " │\{prefix}\{icon_str}\{label_trunc}\{badge_str}"
    lines.push(pad_or_truncate(line, w))
  }

  // Bottom border
  lines.push(pad_or_truncate(" └\{"─".repeat(w - 4)}", w))

  lines
}

// ── Internal helpers ────────────────────────────────────────────────

///|
/// Pad a string to exact width or truncate if longer.
fn pad_or_truncate(s : String, width : Int) -> String {
  if s.length() >= width {
    s[0:width].to_owned()
  } else {
    s + " ".repeat(width - s.length())
  }
}

///|
/// Truncate a string to the given max length, adding "…" if needed.
fn truncate_str(s : String, max_len : Int) -> String {
  if s.length() <= max_len {
    s
  } else if max_len <= 1 {
    "…"
  } else {
    s[0:max_len - 1].to_owned() + "…"
  }
}
