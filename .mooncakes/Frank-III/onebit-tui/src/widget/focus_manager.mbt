///|
/// Focus Management System for Widget Navigation
pub struct FocusManager {
  mut focusable_components : Array[FocusableComponent]
  mut current_index : Int?
}

///|
pub struct FocusableComponent {
  id : String
  component : &@view.Component
  tab_index : Int? // Optional explicit tab order
}

///|
/// Create a new focus manager
pub fn FocusManager::new() -> FocusManager {
  { focusable_components: [], current_index: None }
}

///|
/// Register a focusable component
pub fn FocusManager::register(
  self : FocusManager,
  id : String,
  component : &@view.Component,
  tab_index? : Int? = None,
) -> Unit {
  if component.is_focusable() {
    self.focusable_components.push({ id, component, tab_index })
    // Sort by tab_index if provided
    self.sort_by_tab_index()
  }
}

///|
/// Sort components by tab index
fn FocusManager::sort_by_tab_index(_self : FocusManager) -> Unit {
  // TODO: Implement sorting when MoonBit array sort API is available
  // For now, components are kept in registration order
  // This is actually fine for most use cases
}

///|
/// Focus the next component
pub fn FocusManager::focus_next(self : FocusManager) -> Bool {
  if self.focusable_components.is_empty() {
    return false
  }
  match self.current_index {
    None => {
      // Focus first component
      self.current_index = Some(0)
      self.trigger_focus_event(0, true)
      true
    }
    Some(current) => {
      // Unfocus current
      self.trigger_focus_event(current, false)

      // Focus next (with wrapping)
      let next = (current + 1) % self.focusable_components.length()
      self.current_index = Some(next)
      self.trigger_focus_event(next, true)
      true
    }
  }
}

///|
/// Focus the previous component
pub fn FocusManager::focus_previous(self : FocusManager) -> Bool {
  if self.focusable_components.is_empty() {
    return false
  }
  match self.current_index {
    None => {
      // Focus last component
      let last = self.focusable_components.length() - 1
      self.current_index = Some(last)
      self.trigger_focus_event(last, true)
      true
    }
    Some(current) => {
      // Unfocus current
      self.trigger_focus_event(current, false)

      // Focus previous (with wrapping)
      let prev = if current == 0 {
        self.focusable_components.length() - 1
      } else {
        current - 1
      }
      self.current_index = Some(prev)
      self.trigger_focus_event(prev, true)
      true
    }
  }
}

///|
/// Focus a specific component by ID
pub fn FocusManager::focus_by_id(self : FocusManager, id : String) -> Bool {
  for i = 0; i < self.focusable_components.length(); i = i + 1 {
    if self.focusable_components[i].id == id {
      // Unfocus current if any
      match self.current_index {
        Some(current) => self.trigger_focus_event(current, false)
        None => ()
      }

      // Focus the target
      self.current_index = Some(i)
      self.trigger_focus_event(i, true)
      return true
    }
  }
  false
}

///|
/// Get currently focused component
pub fn FocusManager::get_focused(self : FocusManager) -> FocusableComponent? {
  match self.current_index {
    Some(idx) if idx < self.focusable_components.length() =>
      Some(self.focusable_components[idx])
    _ => None
  }
}

///|
/// Clear focus
pub fn FocusManager::clear_focus(self : FocusManager) -> Unit {
  match self.current_index {
    Some(current) => {
      self.trigger_focus_event(current, false)
      self.current_index = None
    }
    None => ()
  }
}

///|
/// Handle Tab/Shift+Tab navigation
pub fn FocusManager::handle_navigation(
  self : FocusManager,
  event : @events.Event,
) -> Bool {
  match event {
    @events.Event::Key(@ffi.KeyEvent::Tab) =>
      self.focus_next()
    @events.Event::KeyMod(@ffi.KeyEvent::Tab, mods) =>
      if mods.shift { self.focus_previous() } else { self.focus_next() }
    // For now, use another key for reverse navigation
    @events.Event::Key(@ffi.KeyEvent::Escape) => {
      self.clear_focus()
      true
    }
    _ =>
      // Pass event to focused component
      match self.get_focused() {
        Some(focused) => focused.component.handle_event(event)
        None => false
      }
  }
}

///|
/// Trigger focus/blur event on component
fn FocusManager::trigger_focus_event(
  self : FocusManager,
  index : Int,
  focused : Bool,
) -> Unit {
  if index < self.focusable_components.length() {
    let component = self.focusable_components[index].component
    let focus_event = @events.Event::Focus(focused)
    let _ = component.handle_event(focus_event)

  }
}

///|
/// Clear all registered components
pub fn FocusManager::clear(self : FocusManager) -> Unit {
  self.focusable_components = []
  self.current_index = None
}
