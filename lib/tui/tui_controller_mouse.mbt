///|
/// Mouse event handling and scroll support for TuiController.

///|
/// Handle a mouse event from the terminal.
///
/// Supports:
/// - Scroll Up/Down: navigate output history
/// - Click: hit test on VNode elements, dispatch to registered handlers
async fn TuiController::handle_mouse(
  self : TuiController,
  ev : @tty/input.MouseEvent,
) -> Unit {
  match ev.kind {
    Scroll(scroll) => {
      let msg_height = self.term_height - 5
      let total = self.output.total_lines()
      match scroll {
        Up => {
          let max_offset = if total > msg_height {
            total - msg_height
          } else {
            0
          }
          if self.scroll_offset < max_offset {
            self.scroll_offset = self.scroll_offset + 3
            if self.scroll_offset > max_offset {
              self.scroll_offset = max_offset
            }
            self.dirty = true
            self.redraw()
          }
        }
        Down =>
          if self.scroll_offset > 0 {
            self.scroll_offset = self.scroll_offset - 3
            if self.scroll_offset < 0 {
              self.scroll_offset = 0
            }
            self.dirty = true
            self.redraw()
          }
        _ => ()
      }
    }
    Press(btn) =>
      // Click: dispatch via VNodeApp handle_click for any interactive element.
      // If no handler was found, reset scroll to bottom.
      match btn {
        Left => {
          let mouse_event : @tui_events.MouseEvent = {
            button: @tui_events.MouseButton::Left,
            event_type: @tui_events.MouseEventType::Press,
            x: ev.col - 1,
            y: ev.row - 1,
            modifier: @tui_events.KeyModifier::None,
          }
          let clicked_id = self.vnode_renderer.app.handle_click(mouse_event)
          match clicked_id {
            Some(_) => {
              self.dirty = true
              self.redraw()
            }
            None => {
              if self.scroll_offset > 0 {
                self.scroll_offset = 0
                self.dirty = true
                self.redraw()
              }
            }
          }
        }
        _ => ()
      }
    _ => ()
  }
}
