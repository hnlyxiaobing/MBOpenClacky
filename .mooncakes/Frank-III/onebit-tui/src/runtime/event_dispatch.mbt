///| Event Dispatch - Routes events to appropriate View handlers

///|
/// Find which view should handle a mouse event based on position
pub fn find_view_at_position(
  view : @view.View,
  x : Int,
  y : Int,
  current_x : Int,
  current_y : Int,
  layout : @yoga.Node,
) -> @view.View? {
  // Get the computed layout bounds
  let left = layout.layout_left().to_int() + current_x
  let top = layout.layout_top().to_int() + current_y
  let width = layout.layout_width().to_int()
  let height = layout.layout_height().to_int()

  // Check if position is within this view's bounds
  if x >= left && x < left + width && y >= top && y < top + height {
    // Check children first (they render on top)
    let children = view.children
    let child_count = layout.get_child_count()
    for i = child_count - 1; i >= 0; i = i - 1 {
      let child_layout = layout.get_child(i)
      match child_layout {
        Some(cl) =>
          if i < children.length() {
            match find_view_at_position(children[i], x, y, left, top, cl) {
              Some(found) => return Some(found)
              None => ()
            }
          }
        None => ()
      }
    }

    // If no child handles it, return this view if it can handle mouse (event_handler or click_handler)
    match (view.event_handler, view.click_handler) {
      (Some(_), _) => Some(view)
      (None, Some(_)) => Some(view)
      _ => None
    }
  } else {
    None
  }
}

///|
/// Dispatch keyboard event to focused view
pub fn dispatch_key_event(
  view : @view.View,
  event : @ffi.KeyEvent,
  focused_view_id : Int?,
) -> Bool {
  // First check if this view is focused
  match (view.view_id, focused_view_id) {
    (Some(id), Some(focused_id)) if id == focused_id => {
      // Prefer unified event handler if present
      match view.event_handler {
        Some(eh) => if eh(@events.Event::Key(event)) { return true }
        None => ()
      }
      // Fallback to legacy key handler
      match view.key_handler {
        Some(handler) => return handler(event)
        None => ()
      }
    }
    _ => ()
  }

  // Then check children
  for child in view.children {
    if dispatch_key_event(child, event, focused_view_id) {
      return true
    }
  }
  false
}

///|
/// Dispatch a generic Event to focused view (uses unified event_handler only)
pub fn dispatch_event(
  view : @view.View,
  event : @events.Event,
  focused_view_id : Int?,
) -> Bool {
  // Deliver only to the focused view
  match (view.view_id, focused_view_id) {
    (Some(id), Some(focused_id)) if id == focused_id => {
      match view.event_handler {
        Some(eh) => return eh(event)
        None => ()
      }
    }
    _ => ()
  }

  for child in view.children {
    if dispatch_event(child, event, focused_view_id) {
      return true
    }
  }
  false
}

///|
/// Dispatch keyboard event with modifiers to focused view
pub fn dispatch_key_mod_event(
  view : @view.View,
  event : @ffi.KeyEvent,
  mods : @ffi.KeyModifiers,
  focused_view_id : Int?,
) -> Bool {
  // First check if this view is focused
  match (view.view_id, focused_view_id) {
    (Some(id), Some(focused_id)) if id == focused_id => {
      // Prefer unified event handler if present
      match view.event_handler {
        Some(eh) => if eh(@events.Event::KeyMod(event, mods)) { return true }
        None => ()
      }
      // Fallback to legacy key_mod handler
      match view.key_mod_handler {
        Some(handler) => return handler(event, mods)
        None => ()
      }
    }
    _ => ()
  }

  // Then check children
  for child in view.children {
    if dispatch_key_mod_event(child, event, mods, focused_view_id) {
      return true
    }
  }
  false
}

///|
/// Directly dispatch a key event to a specific view, regardless of focus
pub fn dispatch_key_event_direct(view : @view.View, event : @ffi.KeyEvent) -> Bool {
  // Prefer unified event handler
  match view.event_handler {
    Some(eh) => if eh(@events.Event::Key(event)) { return true }
    None => ()
  }
  // Fallback to legacy key handler
  match view.key_handler {
    Some(handler) => return handler(event)
    None => ()
  }
  false
}

///|
/// Directly dispatch a KeyMod event to a specific view, regardless of focus
pub fn dispatch_key_mod_event_direct(
  view : @view.View,
  event : @ffi.KeyEvent,
  mods : @ffi.KeyModifiers,
) -> Bool {
  match view.event_handler {
    Some(eh) => if eh(@events.Event::KeyMod(event, mods)) { return true }
    None => ()
  }
  match view.key_mod_handler {
    Some(handler) => return handler(event, mods)
    None => ()
  }
  false
}

///|
/// Bubble a Key event from the focused view up through its ancestors
pub fn bubble_key_event(
  view : @view.View,
  event : @ffi.KeyEvent,
  focused_view_id : Int?,
) -> Bool {
  let handled_ref = Ref::new(false)
  let _ = bubble_key_event_rec(view, event, focused_view_id, handled_ref)
  handled_ref.val
}

fn bubble_key_event_rec(
  view : @view.View,
  event : @ffi.KeyEvent,
  focused_view_id : Int?,
  handled : Ref[Bool],
) -> Bool {
  // Returns whether this subtree contains the focused view
  let mut contains = false
  // Check if this node is the focused one
  match (view.view_id, focused_view_id) {
    (Some(id), Some(fid)) if id == fid => contains = true
    _ => ()
  }
  // Recurse into children
  for child in view.children {
    if bubble_key_event_rec(child, event, focused_view_id, handled) {
      contains = true
      // We're on an ancestor of the focused node; try to handle here if not yet handled
      if not(handled.val) {
        match view.event_handler {
          Some(eh) => if eh(@events.Event::Key(event)) { handled.val = true; return true }
          None => ()
        }
      }
      // Continue bubbling up through higher ancestors
      return true
    }
  }
  contains
}

///|
/// Bubble a KeyMod event from the focused view up through its ancestors
pub fn bubble_key_mod_event(
  view : @view.View,
  event : @ffi.KeyEvent,
  mods : @ffi.KeyModifiers,
  focused_view_id : Int?,
) -> Bool {
  let handled_ref = Ref::new(false)
  let _ = bubble_key_mod_event_rec(view, event, mods, focused_view_id, handled_ref)
  handled_ref.val
}

fn bubble_key_mod_event_rec(
  view : @view.View,
  event : @ffi.KeyEvent,
  mods : @ffi.KeyModifiers,
  focused_view_id : Int?,
  handled : Ref[Bool],
) -> Bool {
  let mut contains = false
  match (view.view_id, focused_view_id) {
    (Some(id), Some(fid)) if id == fid => contains = true
    _ => ()
  }
  for child in view.children {
    if bubble_key_mod_event_rec(child, event, mods, focused_view_id, handled) {
      contains = true
      if not(handled.val) {
        match view.event_handler {
          Some(eh) => if eh(@events.Event::KeyMod(event, mods)) { handled.val = true; return true }
          None => ()
        }
      }
      return true
    }
  }
  contains
}

///|
/// Dispatch mouse click to appropriate view
pub fn dispatch_click(
  view : @view.View,
  x : Int,
  y : Int,
  layout : @yoga.Node,
) -> Bool {
  match find_view_at_position(view, x, y, 0, 0, layout) {
    Some(target_view) => {
      // Try unified event handler first
      match target_view.event_handler {
        Some(eh) => {
          let mouse_event : @events.MouseEvent = {
            x, y,
            button: @events.MouseButton::Left,
            action: @events.MouseAction::Click,
          }
          if eh(@events.Event::Mouse(mouse_event)) {
            return true
          }
        }
        None => ()
      }
      // Fallback to legacy click handler
      match target_view.click_handler {
        Some(handler) => { handler(x, y); true }
        None => false
      }
    }
    None => false
  }
}

///|
/// Dispatch a mouse event with bubbling from the deepest child under (x,y) up through ancestors
pub fn dispatch_mouse_with_bubble(
  view : @view.View,
  x : Int,
  y : Int,
  layout : @yoga.Node,
  action : @events.MouseAction,
  button : @events.MouseButton,
) -> Bool {
  let (handled, _found) = dispatch_mouse_bubble_rec(view, x, y, 0, 0, layout, action, button)
  handled
}

fn dispatch_mouse_bubble_rec(
  view : @view.View,
  x : Int,
  y : Int,
  current_x : Int,
  current_y : Int,
  layout : @yoga.Node,
  action : @events.MouseAction,
  button : @events.MouseButton,
) -> (Bool, Bool) {
  // Compute bounds
  let left = layout.layout_left().to_int() + current_x
  let top = layout.layout_top().to_int() + current_y
  let width = layout.layout_width().to_int()
  let height = layout.layout_height().to_int()

  if x >= left && x < left + width && y >= top && y < top + height {
    // Traverse children from top-most
    let children = view.children
    let child_count = layout.get_child_count()
    for i = child_count - 1; i >= 0; i = i - 1 {
      let child_layout = layout.get_child(i)
      match child_layout {
        Some(cl) =>
          if i < children.length() {
            let (handled_child, found_child) = dispatch_mouse_bubble_rec(children[i], x, y, left, top, cl, action, button)
            if found_child {
              if handled_child { return (true, true) }
              // Child path found but not handled; try current view handler (bubble)
              match view.event_handler {
                Some(eh) => {
                  let mouse_event : @events.MouseEvent = { x, y, button, action }
                  if eh(@events.Event::Mouse(mouse_event)) { return (true, true) }
                }
                None => ()
              }
              return (false, true)
            }
          }
        None => ()
      }
    }

    // No child handled and no child path found; try this view directly
    match view.event_handler {
      Some(eh) => {
        let mouse_event : @events.MouseEvent = { x, y, button, action }
        if eh(@events.Event::Mouse(mouse_event)) { return (true, true) }
      }
      None => ()
    }
    return (false, true)
  }
  (false, false)
}

///|
/// Set focus state on a view by ID
pub fn set_view_focused(
  view : @view.View,
  view_id : Int?,
  focused : Bool,
) -> Bool {
  match (view.view_id, view_id) {
    (Some(vid), Some(target_id)) if vid == target_id => {
      view.set_focused(focused)
      return true
    }
    _ => ()
  }

  // Check children
  for child in view.children {
    if set_view_focused(child, view_id, focused) {
      return true
    }
  }
  false
}

///|
/// Clear all focus states in view tree
pub fn clear_all_focus(view : @view.View) -> Unit {
  view.set_focused(false)
  for child in view.children {
    clear_all_focus(child)
  }
}

///|
/// Find a view by its view_id
pub fn find_view_by_id(view : @view.View, target_id : Int) -> @view.View? {
  match view.view_id {
    Some(id) if id == target_id => return Some(view)
    _ => ()
  }
  for child in view.children {
    match find_view_by_id(child, target_id) {
      Some(v) => return Some(v)
      None => ()
    }
  }
  None
}

///|
/// Dispatch an event to a specific view ID (searches the tree)
pub fn dispatch_event_to_id(
  view : @view.View,
  target_id : Int,
  event : @events.Event,
) -> Bool {
  match view.view_id {
    Some(id) if id == target_id => {
      // Prefer unified event handler
      match view.event_handler {
        Some(eh) => return eh(event)
        None => ()
      }
      // Fallbacks for legacy mouse/click path
      match event {
        @events.Event::Mouse(me) =>
          match (me.action, view.click_handler) {
            (@events.MouseAction::Click, Some(handler)) => { handler(me.x, me.y); return true }
            _ => ()
          }
        _ => ()
      }
      return false
    }
    _ => ()
  }
  for child in view.children {
    if dispatch_event_to_id(child, target_id, event) {
      return true
    }
  }
  false
}

///|
/// Find next focusable view (for Tab navigation)
pub fn find_next_focusable(
  view : @view.View,
  current_id : Int?,
  found_current : Ref[Bool],
) -> Int? {
  // If this view is focusable and we've passed the current
  if view.is_focusable && found_current.val {
    return view.view_id
  }

  // Check if this is the current focused view
  match (view.view_id, current_id) {
    (Some(id), Some(curr)) if id == curr => found_current.val = true
    _ => ()
  }

  // Check children
  for child in view.children {
    match find_next_focusable(child, current_id, found_current) {
      Some(id) => return Some(id)
      None => ()
    }
  }

  // If we haven't found anything and this is focusable, return it (wrap around)
  if view.is_focusable && current_id is None {
    return view.view_id
  }
  None
}

///|
/// Collect all focusable view IDs in pre-order traversal
pub fn collect_focusable_ids(view : @view.View) -> Array[Int] {
  let ids : Array[Int] = []
  collect_focusable_ids_rec(view, ids)
  ids
}

///|
fn collect_focusable_ids_rec(view : @view.View, out : Array[Int]) -> Unit {
  if view.is_focusable {
    match view.view_id {
      Some(id) => out.push(id)
      None => ()
    }
  }
  for child in view.children {
    collect_focusable_ids_rec(child, out)
  }
}
