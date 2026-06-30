///|
/// Modal Manager - Global state for modal dialogs
/// Handles modal stack and focus restoration
pub struct ModalManager {
  mut modal_stack : Array[Modal]      // Stack for nested modals
  mut saved_focus : Array[Int?]       // Save focus state per modal level
}

///|
/// Global modal manager instance
pub let global_modal_manager : Ref[ModalManager] = Ref::new({
  modal_stack: [],
  saved_focus: []
})

///|
/// Push a new modal onto the stack
pub fn ModalManager::push_modal(modal : Modal, current_focus : Int?) -> Unit {
  let manager = global_modal_manager.val
  
  // Save current focus state
  manager.saved_focus.push(current_focus)
  
  // Add modal to stack
  manager.modal_stack.push(modal)
}

///|
/// Pop the top modal from the stack
pub fn ModalManager::pop_modal() -> Int? {
  let manager = global_modal_manager.val
  
  if manager.modal_stack.length() > 0 {
    // Remove top modal
    let _ = manager.modal_stack.pop()
    
    // Restore previous focus
    match manager.saved_focus.pop() {
      Some(focus_id) => return focus_id
      None => return None
    }
  }
  None
}

///|
/// Get the currently active modal (top of stack)
pub fn ModalManager::get_active() -> Modal? {
  let manager = global_modal_manager.val
  
  if manager.modal_stack.length() > 0 {
    Some(manager.modal_stack[manager.modal_stack.length() - 1])
  } else {
    None
  }
}

///|
/// Check if any modal is active
pub fn ModalManager::is_active() -> Bool {
  let manager = global_modal_manager.val
  manager.modal_stack.length() > 0
}

///|
/// Clear all modals (emergency cleanup)
pub fn ModalManager::clear_all() -> Unit {
  let manager = global_modal_manager.val
  manager.modal_stack = []
  manager.saved_focus = []
}

///|
/// Get the number of active modals
pub fn ModalManager::depth() -> Int {
  let manager = global_modal_manager.val
  manager.modal_stack.length()
}