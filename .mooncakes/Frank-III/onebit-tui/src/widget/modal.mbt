///|
/// Modal Component - Overlay dialogs with focus trap
pub struct Modal {
  content : &@view.Component       // The actual dialog content  
  mut title : String?               // Optional title
  mut width : Int?                  // Fixed width (chars) or auto
  mut height : Int?                 // Fixed height (lines) or auto
  mut backdrop : Bool               // Show dimmed background
  close_on_escape : Bool            // Close when Escape is pressed
  mut close_on_backdrop : Bool      // Close when clicking backdrop
  mut on_close : (() -> Unit)?     // Callback when modal closes
}

///|
/// Create a new modal with content
pub fn Modal::new(content : &@view.Component) -> Modal {
  {
    content,
    title: None,
    width: None,
    height: None,
    backdrop: true,
    close_on_escape: true,
    close_on_backdrop: false,
    on_close: None
  }
}

///|
/// Create a modal with a title
pub fn Modal::with_title(self : Modal, title : String) -> Modal {
  self.title = Some(title)
  self
}

///|
/// Set modal dimensions
pub fn Modal::with_size(self : Modal, width : Int, height : Int) -> Modal {
  self.width = Some(width)
  self.height = Some(height)
  self
}

///|
/// Set backdrop options
pub fn Modal::with_backdrop(self : Modal, show : Bool, close_on_click : Bool) -> Modal {
  self.backdrop = show
  self.close_on_backdrop = close_on_click
  self
}

///|
/// Set close callback
pub fn Modal::on_close(self : Modal, callback : () -> Unit) -> Modal {
  self.on_close = Some(callback)
  self
}

///|
/// Close this modal
pub fn Modal::close(self : Modal) -> Unit {
  // Call close callback if set
  match self.on_close {
    Some(callback) => callback()
    None => ()
  }
  
  // Remove from modal manager (returns focus to restore)
  let _ = ModalManager::pop_modal()
}

///|
/// Show this modal
pub fn Modal::show(self : Modal, current_focus : Int?) -> Unit {
  // Push to modal manager
  ModalManager::push_modal(self, current_focus)
}

///|
/// Component implementation for Modal
pub impl @view.Component for Modal with render(self) {
  // Build content stack (title + body)
  let content_components : Array[&@view.Component] = []
  match self.title {
    Some(title) => content_components.push(Text::new(title))
    None => ()
  }
  content_components.push(self.content)

  let mut dialog = @view.View::container(content_components)
    .border(@view.BorderStyle::Double, color=@core.Color::White)
    .padding(1.0)

  // Size
  match self.width {
    Some(w) => dialog = dialog.width(w.to_double())
    None => dialog = dialog.width(50.0)
  }
  match self.height {
    Some(h) => dialog = dialog.height(h.to_double())
    None => ()
  }

  // Backdrop (full-screen) + dialog centered in an absolute overlay
  let children : Array[@view.View] = []
  if self.backdrop {
    let mut backdrop = @view.View::empty()
      .position(@view.Position::Absolute)
      .top(0.0)
      .left(0.0)
      .width_percent(100.0)
      .height_percent(100.0)
      .background(@core.rgba(0, 0, 0, 0.6))
    if self.close_on_backdrop {
      backdrop = backdrop.on_click(Some(fn(_x : Int, _y : Int) { self.close() }))
    }
    children.push(backdrop)
  }
  children.push(dialog)

  @view.View::container_views(children)
    .position(@view.Position::Absolute)
    .top(0.0)
    .left(0.0)
    .width_percent(100.0)
    .height_percent(100.0)
    .align_items(@types.Align::Center)
    .justify_content(@types.Justify::Center)
}

///|
pub impl @view.Component for Modal with handle_event(_self, _event) {
  // Let the overlay focus logic in the runtime handle Tab/Escape.
  // Modal-level component does not intercept events; content components receive events via view handlers.
  false
}

///|
pub impl @view.Component for Modal with is_focusable(_self) {
  true  // Modal itself is focusable to trap focus
}

///|
/// Confirmation Dialog - A simple yes/no modal
pub struct ConfirmDialog {
  message : String
  on_confirm : () -> Unit
  mut on_cancel : (() -> Unit)?
  mut confirm_text : String
  mut cancel_text : String
}

///|
/// Create a confirmation dialog
pub fn ConfirmDialog::new(
  message : String,
  on_confirm : () -> Unit
) -> ConfirmDialog {
  {
    message,
    on_confirm,
    on_cancel: None,
    confirm_text: "Yes",
    cancel_text: "No"
  }
}

///|
/// Set cancel callback
pub fn ConfirmDialog::on_cancel(self : ConfirmDialog, callback : () -> Unit) -> ConfirmDialog {
  self.on_cancel = Some(callback)
  self
}

///|
/// Set button labels
pub fn ConfirmDialog::with_labels(
  self : ConfirmDialog,
  confirm : String,
  cancel : String
) -> ConfirmDialog {
  self.confirm_text = confirm
  self.cancel_text = cancel
  self
}

///|
/// Show the confirmation dialog
pub fn ConfirmDialog::show(self : ConfirmDialog, current_focus : Int?) -> Unit {
  // Create the dialog content
  let content = Column::new([
    Text::new(self.message),
    Row::new([
      Button::primary(self.confirm_text, fn() {
        // Close modal first
        let _ = ModalManager::pop_modal()
        // Then execute callback
        (self.on_confirm)()
      }),
      Button::secondary(self.cancel_text, fn() {
        // Close modal
        let _ = ModalManager::pop_modal()
        // Execute cancel callback if set
        match self.on_cancel {
          Some(callback) => callback()
          None => ()
        }
      })
    ]).spacing(2.0)
  ])
  
  // Create and show modal
  let modal = Modal::new(content)
    .with_title("Confirm")
    .with_backdrop(true, false)
  
  modal.show(current_focus)
}

///|
/// Component implementation for ConfirmDialog
pub impl @view.Component for ConfirmDialog with render(self) {
  // Create the content and wrap in a modal
  let content = Column::new([
    Text::new(self.message),
    Row::new([
      Button::primary(self.confirm_text, fn() {
        let _ = ModalManager::pop_modal()
        (self.on_confirm)()
      }),
      Button::secondary(self.cancel_text, fn() {
        let _ = ModalManager::pop_modal()
        match self.on_cancel {
          Some(callback) => callback()
          None => ()
        }
      })
    ]).spacing(2.0)
  ])
  
  Modal::new(content).with_title("Confirm").render()
}

///|
pub impl @view.Component for ConfirmDialog with handle_event(_self, _event) {
  false  // Let the modal handle events
}

///|
pub impl @view.Component for ConfirmDialog with is_focusable(_self) {
  false
}
