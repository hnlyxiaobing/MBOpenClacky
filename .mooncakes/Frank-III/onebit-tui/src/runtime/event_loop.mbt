///| Event Loop - Handles input events and dispatches to components

///|
/// Main event loop that processes input and updates UI
pub fn run_event_loop(
  app : @core.App,
  build_ui : () -> @view.View,
  on_global_event? : (@ffi.InputEvent) -> Bool = fn(_) { false },
  enable_kitty_keyboard? : Bool = false,
  debug_mouse? : Bool = false,
) -> Unit {
  // Enable raw mode for input (already enabled by new())
  let session = @ffi.TerminalSession::new(raw_mode=true, mouse=true)

  // Mouse tracking already enabled by session
  // Optionally enable kitty keyboard for richer modifiers
  if enable_kitty_keyboard {
    app.get_renderer().enable_kitty_keyboard(0b00001)
  }

  // Track if we need to redraw
  let needs_redraw = Ref::new(true)
  let running = Ref::new(true)

  // Track current UI and layout for event dispatch
  let current_ui : Ref[@view.View?] = Ref::new(None)
  let current_layout : Ref[@yoga.Node?] = Ref::new(None)
  let focused_view_id : Ref[Int?] = Ref::new(None)
  // Focus position within traversal order of focusables (pre-order)
  let focused_pos : Ref[Int?] = Ref::new(None)

  // Modal overlay state
  let current_modal_view : Ref[@view.View?] = Ref::new(None)
  let current_modal_layout : Ref[@yoga.Node?] = Ref::new(None)
  let modal_focused_view_id : Ref[Int?] = Ref::new(None)
  let modal_focused_pos : Ref[Int?] = Ref::new(None)

  // Hover tracking (last mouse position)
  let last_mouse_x = Ref::new(0)
  let last_mouse_y = Ref::new(0)
  let last_over_id = Ref::new(0)

  // Frame timing (target 60 FPS = ~16ms per frame)
  let frame_time_ms = 16

  // Dimensions are now stored in the app and updated on resize

  while running.val {
    // Poll for input events (always try to read)
    let event = @ffi.poll_input_event()

    // Handle system events
    match event {
      @ffi.InputEvent::Key(@ffi.KeyEvent::Char(3)) =>
        // Ctrl+C to quit
        running.val = false
      @ffi.InputEvent::Resize(new_w, new_h) => {
        // Update app dimensions
        app.resize(new_w, new_h)
        // Force redraw with new dimensions
        needs_redraw.val = true
      }
      @ffi.InputEvent::MouseDown(x, y, button) => {
        // Global pre-capture for mouse
        if on_global_event(@ffi.InputEvent::MouseDown(x, y, button)) {
          needs_redraw.val = true
          continue
        }
        // Prefer renderer hit grid for click targeting; fall back to layout hit-test
        let clicked_id = app.get_renderer().check_hit(x, y)
        if clicked_id > 0 {
          let action = @events.MouseAction::Click
          let btn = match button {
            @ffi.MouseButton::Left => @events.MouseButton::Left
            @ffi.MouseButton::Right => @events.MouseButton::Right
            @ffi.MouseButton::Middle => @events.MouseButton::Middle
            _ => @events.MouseButton::Left
          }
          let ev = @events.Event::Mouse(@events.MouseEvent::{ x, y, button: btn, action })
          match @widget.ModalManager::get_active() {
            Some(_) =>
              match current_modal_view.val {
                Some(mv) => if dispatch_event_to_id(mv, clicked_id, ev) { needs_redraw.val = true }
                None => ()
              }
            None =>
              match current_ui.val {
                Some(ui) => if dispatch_event_to_id(ui, clicked_id, ev) { needs_redraw.val = true }
                None => ()
              }
          }
          continue
        }
        // Wheel → Arrow dispatch (hover target preferred; modal takes precedence)
        match button {
          @ffi.MouseButton::ScrollUp => {
            let mut handled_scroll = false
            let target_event = @events.Event::Key(@ffi.KeyEvent::ArrowUp)
            let hid = app.get_renderer().check_hit(x, y)
            if hid > 0 {
              match @widget.ModalManager::get_active() {
                Some(_) =>
                  match current_modal_view.val {
                    Some(mv) => handled_scroll = dispatch_event_to_id(mv, hid, target_event)
                    None => ()
                  }
                None =>
                  match current_ui.val {
                    Some(ui) => handled_scroll = dispatch_event_to_id(ui, hid, target_event)
                    None => ()
                  }
              }
            }
            if not(handled_scroll) {
              match @widget.ModalManager::get_active() {
                Some(_) =>
                  match (current_modal_view.val, current_modal_layout.val) {
                    (Some(mv), Some(ml)) => {
                      match find_view_at_position(mv, x, y, 0, 0, ml) {
                        Some(target) => handled_scroll = dispatch_key_event_direct(target, @ffi.KeyEvent::ArrowUp)
                        None => ()
                      }
                      if not(handled_scroll) {
                        handled_scroll = dispatch_key_event(mv, @ffi.KeyEvent::ArrowUp, modal_focused_view_id.val)
                      }
                    }
                    _ => ()
                  }
                None =>
                  match (current_ui.val, current_layout.val) {
                    (Some(ui), Some(layout)) => {
                      match find_view_at_position(ui, x, y, 0, 0, layout) {
                        Some(target) => handled_scroll = dispatch_key_event_direct(target, @ffi.KeyEvent::ArrowUp)
                        None => ()
                      }
                      if not(handled_scroll) {
                        handled_scroll = match focused_view_id.val {
                          Some(_) => dispatch_key_event(ui, @ffi.KeyEvent::ArrowUp, focused_view_id.val)
                          None => false
                        }
                      }
                    }
                    _ => ()
                  }
              }
            }
            if handled_scroll { needs_redraw.val = true }
            continue
          }
          @ffi.MouseButton::ScrollDown => {
            let mut handled_scroll = false
            let target_event = @events.Event::Key(@ffi.KeyEvent::ArrowDown)
            let hid = app.get_renderer().check_hit(x, y)
            if hid > 0 {
              match @widget.ModalManager::get_active() {
                Some(_) =>
                  match current_modal_view.val {
                    Some(mv) => handled_scroll = dispatch_event_to_id(mv, hid, target_event)
                    None => ()
                  }
                None =>
                  match current_ui.val {
                    Some(ui) => handled_scroll = dispatch_event_to_id(ui, hid, target_event)
                    None => ()
                  }
              }
            }
            if not(handled_scroll) {
              match @widget.ModalManager::get_active() {
                Some(_) =>
                  match (current_modal_view.val, current_modal_layout.val) {
                    (Some(mv), Some(ml)) => {
                      match find_view_at_position(mv, x, y, 0, 0, ml) {
                        Some(target) => handled_scroll = dispatch_key_event_direct(target, @ffi.KeyEvent::ArrowDown)
                        None => ()
                      }
                      if not(handled_scroll) {
                        handled_scroll = dispatch_key_event(mv, @ffi.KeyEvent::ArrowDown, modal_focused_view_id.val)
                      }
                    }
                    _ => ()
                  }
                None =>
                  match (current_ui.val, current_layout.val) {
                    (Some(ui), Some(layout)) => {
                      match find_view_at_position(ui, x, y, 0, 0, layout) {
                        Some(target) => handled_scroll = dispatch_key_event_direct(target, @ffi.KeyEvent::ArrowDown)
                        None => ()
                      }
                      if not(handled_scroll) {
                        handled_scroll = match focused_view_id.val {
                          Some(_) => dispatch_key_event(ui, @ffi.KeyEvent::ArrowDown, focused_view_id.val)
                          None => false
                        }
                      }
                    }
                    _ => ()
                  }
              }
            }
            if handled_scroll { needs_redraw.val = true }
            continue
          }
          _ => ()
        }
        // Fallback: Click dispatch by layout hit-testing
        match @widget.ModalManager::get_active() {
          Some(_) =>
            match (current_modal_view.val, current_modal_layout.val) {
              (Some(mv), Some(ml)) => if dispatch_click(mv, x, y, ml) { needs_redraw.val = true }
              _ => ()
            }
          None => {
            match (current_ui.val, current_layout.val) {
              (Some(ui), Some(layout)) => if dispatch_click(ui, x, y, layout) { needs_redraw.val = true }
              _ => ()
            }
          }
        }

        // Additionally deliver Click to event handlers with bubbling
        let btn = match button {
          @ffi.MouseButton::Left => @events.MouseButton::Left
          @ffi.MouseButton::Right => @events.MouseButton::Right
          @ffi.MouseButton::Middle => @events.MouseButton::Middle
          _ => @events.MouseButton::Left
        }
        let action = @events.MouseAction::Click
        match @widget.ModalManager::get_active() {
          Some(_) =>
            match (current_modal_view.val, current_modal_layout.val) {
              (Some(mv), Some(ml)) => if dispatch_mouse_with_bubble(mv, x, y, ml, action, btn) { needs_redraw.val = true }
              _ => ()
            }
          None =>
            match (current_ui.val, current_layout.val) {
              (Some(ui), Some(layout)) => if dispatch_mouse_with_bubble(ui, x, y, layout, action, btn) { needs_redraw.val = true }
              _ => ()
            }
        }
      }
      @ffi.InputEvent::MouseUp(x, y, button) => {
        // Global pre-capture
        if on_global_event(@ffi.InputEvent::MouseUp(x, y, button)) {
          needs_redraw.val = true
        } else {
          let btn = match button {
            @ffi.MouseButton::Left => @events.MouseButton::Left
            @ffi.MouseButton::Right => @events.MouseButton::Right
            @ffi.MouseButton::Middle => @events.MouseButton::Middle
            _ => @events.MouseButton::Left
          }
          let action = @events.MouseAction::Release
          match @widget.ModalManager::get_active() {
            Some(_) =>
              match (current_modal_view.val, current_modal_layout.val) {
                (Some(mv), Some(ml)) => if dispatch_mouse_with_bubble(mv, x, y, ml, action, btn) { needs_redraw.val = true }
                _ => ()
              }
            None =>
              match (current_ui.val, current_layout.val) {
                (Some(ui), Some(layout)) => if dispatch_mouse_with_bubble(ui, x, y, layout, action, btn) { needs_redraw.val = true }
                _ => ()
              }
          }
        }
      }
      @ffi.InputEvent::MouseDrag(x, y, button) => {
        // Global pre-capture for drag
        if on_global_event(@ffi.InputEvent::MouseDrag(x, y, button)) {
          needs_redraw.val = true
          continue
        }
        // Bubble as Move for now
        let btn = match button {
          @ffi.MouseButton::Left => @events.MouseButton::Left
          @ffi.MouseButton::Right => @events.MouseButton::Right
          @ffi.MouseButton::Middle => @events.MouseButton::Middle
          _ => @events.MouseButton::Left
        }
        let action = @events.MouseAction::Move
        match @widget.ModalManager::get_active() {
          Some(_) =>
            match (current_modal_view.val, current_modal_layout.val) {
              (Some(mv), Some(ml)) => if dispatch_mouse_with_bubble(mv, x, y, ml, action, btn) { needs_redraw.val = true }
              _ => ()
            }
          None =>
            match (current_ui.val, current_layout.val) {
              (Some(ui), Some(layout)) => if dispatch_mouse_with_bubble(ui, x, y, layout, action, btn) { needs_redraw.val = true }
              _ => ()
            }
        }
      }
      @ffi.InputEvent::MouseMove(x, y) => {
        // Track last known mouse position for hover-aware behaviors
        last_mouse_x.val = x
        last_mouse_y.val = y
        // Optional: global pre-capture for move (disabled to avoid chatter)
        // Dispatch Move to target via hit grid; fall back to layout bubble.
        let btn = @events.MouseButton::Left
        let ev_move = @events.Event::Mouse(@events.MouseEvent::{ x, y, button: btn, action: @events.MouseAction::Move })
        let hid = app.get_renderer().check_hit(x, y)
        let mut handled_move = false
        if hid > 0 {
          match @widget.ModalManager::get_active() {
            Some(_) =>
              match current_modal_view.val {
                Some(mv) => handled_move = dispatch_event_to_id(mv, hid, ev_move)
                None => ()
              }
            None =>
              match current_ui.val {
                Some(ui) => handled_move = dispatch_event_to_id(ui, hid, ev_move)
                None => ()
              }
          }
          last_over_id.val = hid
        }
        if not(handled_move) {
          match @widget.ModalManager::get_active() {
            Some(_) =>
              match (current_modal_view.val, current_modal_layout.val) {
                (Some(mv), Some(ml)) => { let _ = dispatch_mouse_with_bubble(mv, x, y, ml, @events.MouseAction::Move, btn) }
                _ => ()
              }
            None =>
              match (current_ui.val, current_layout.val) {
                (Some(ui), Some(layout)) => { let _ = dispatch_mouse_with_bubble(ui, x, y, layout, @events.MouseAction::Move, btn) }
                _ => ()
              }
          }
        }
      }
      @ffi.InputEvent::Key(key) => {
        // Modal active: route to modal view handlers and manage modal focus
        match @widget.ModalManager::get_active() {
          Some(modal) => {
            // Global pre-capture: allow preventDefault to block modal handling
            if on_global_event(event) {
              needs_redraw.val = true
            } else {
              // Escape closes
              if key == @ffi.KeyEvent::Escape && modal.close_on_escape {
                modal.close()
                needs_redraw.val = true
                // Restore base focus
                if not(@widget.ModalManager::is_active()) {
                  let restored_focus = @widget.ModalManager::pop_modal()
                  match restored_focus {
                    Some(id) => {
                      focused_view_id.val = Some(id)
                      match current_ui.val {
                        Some(ui) => { let _ = set_view_focused(ui, Some(id), true) }
                        None => ()
                      }
                    }
                    None => ()
                  }
                }
              } else {
                // Dispatch to modal overlay view
                let handled = match current_modal_view.val {
                  Some(mv) => dispatch_key_event(mv, key, modal_focused_view_id.val)
                  None => false
                }
                if not(handled) {
                  // Handle Tab focus cycle inside modal, otherwise bubble to ancestors
                  match key {
                    @ffi.KeyEvent::Tab =>
                      match current_modal_view.val {
                        Some(mv) => {
                          let ids = collect_focusable_ids(mv)
                          if ids.length() > 0 {
                            let new_pos = match modal_focused_pos.val {
                              Some(pos) => (pos + 1) % ids.length()
                              None => 0
                            }
                            clear_all_focus(mv)
                            let new_id = ids[new_pos]
                            let _ = set_view_focused(mv, Some(new_id), true)
                            modal_focused_view_id.val = Some(new_id)
                            modal_focused_pos.val = Some(new_pos)
                            needs_redraw.val = true
                          }
                        }
                        None => ()
                      }
                    _ =>
                      match current_modal_view.val {
                        Some(mv) => if bubble_key_event(mv, key, modal_focused_view_id.val) { needs_redraw.val = true }
                        None => ()
                      }
                  }
                } else {
                  needs_redraw.val = true
                }
              }
            }
          }
          None => {
            // Global pre-capture: allow preventDefault
            if on_global_event(event) {
              needs_redraw.val = true
            } else {
              // No modal active, handle normally
              match key {
                @ffi.KeyEvent::Escape => running.val = false
                @ffi.KeyEvent::Char(113) => running.val = false
                _ => {
                  // First try to dispatch to focused view
                  let handled = match (current_ui.val, focused_view_id.val) {
                    (Some(ui), Some(_)) => dispatch_key_event(ui, key, focused_view_id.val)
                    _ => false
                  }

                  // Handle Tab for focus navigation, otherwise bubble to ancestors
                  if not(handled) {
                    match key {
                      @ffi.KeyEvent::Tab =>
                        match current_ui.val {
                          Some(ui) => {
                            let ids = collect_focusable_ids(ui)
                            if ids.length() > 0 {
                              let new_pos = match focused_pos.val {
                                Some(pos) => (pos + 1) % ids.length()
                                None => 0
                              }
                              clear_all_focus(ui)
                              let new_id = ids[new_pos]
                              let _ = set_view_focused(ui, Some(new_id), true)
                              focused_view_id.val = Some(new_id)
                              focused_pos.val = Some(new_pos)
                              needs_redraw.val = true
                            }
                          }
                          None => ()
                        }
                      _ =>
                        match current_ui.val {
                          Some(ui) => if bubble_key_event(ui, key, focused_view_id.val) { needs_redraw.val = true }
                          None => ()
                        }
                    }
                  } else {
                    needs_redraw.val = true
                  }
                }
              }
            }
          }
        }
      }
      @ffi.InputEvent::KeyMod(key, mods) => {
        // If a modal is active, it gets the first chance
        match @widget.ModalManager::get_active() {
          Some(_) => {
            // Global pre-capture for modals
            if on_global_event(@ffi.InputEvent::KeyMod(key, mods)) {
              needs_redraw.val = true
            } else {
            // Shift+Tab reverse focus within modal
            match key {
              @ffi.KeyEvent::Tab if mods.shift =>
                match current_modal_view.val {
                  Some(mv) => {
                    let ids = collect_focusable_ids(mv)
                    if ids.length() > 0 {
                      let new_pos = match modal_focused_pos.val {
                        Some(pos) => if pos == 0 { ids.length() - 1 } else { pos - 1 }
                        None => ids.length() - 1
                      }
                      clear_all_focus(mv)
                      let new_id = ids[new_pos]
                      let _ = set_view_focused(mv, Some(new_id), true)
                      modal_focused_view_id.val = Some(new_id)
                      modal_focused_pos.val = Some(new_pos)
                      needs_redraw.val = true
                    }
                  }
                  None => ()
                }
              _ => {
                let handled_mod = match current_modal_view.val {
                  Some(mv) => dispatch_key_mod_event(mv, key, mods, modal_focused_view_id.val)
                  None => false
                }
                if handled_mod { needs_redraw.val = true } else {
                  match current_modal_view.val {
                    Some(mv) => if bubble_key_mod_event(mv, key, mods, modal_focused_view_id.val) { needs_redraw.val = true }
                    None => ()
                  }
                }
              }
            }
            }
          }
          None => {
            if on_global_event(@ffi.InputEvent::KeyMod(key, mods)) {
              needs_redraw.val = true
            } else {
              // Handle Shift+Tab for reverse focus navigation
              match key {
                @ffi.KeyEvent::Tab if mods.shift =>
                  match current_ui.val {
                    Some(ui) => {
                      let ids = collect_focusable_ids(ui)
                      if ids.length() > 0 {
                        let new_pos = match focused_pos.val {
                          Some(pos) => if pos == 0 { ids.length() - 1 } else { pos - 1 }
                          None => ids.length() - 1
                        }
                        clear_all_focus(ui)
                        let new_id = ids[new_pos]
                        let _ = set_view_focused(ui, Some(new_id), true)
                        focused_view_id.val = Some(new_id)
                        focused_pos.val = Some(new_pos)
                        needs_redraw.val = true
                      }
                    }
                    None => ()
                  }
                _ => {
                  // Try mod-aware dispatch first; then bubble; then fallback to base key
                  let handled_mod = match (current_ui.val, focused_view_id.val) {
                    (Some(ui), Some(_)) => dispatch_key_mod_event(ui, key, mods, focused_view_id.val)
                    _ => false
                  }
                  if handled_mod {
                    needs_redraw.val = true
                  } else {
                    match current_ui.val {
                      Some(ui) => if bubble_key_mod_event(ui, key, mods, focused_view_id.val) { needs_redraw.val = true }
                      None => ()
                    }
                    if not(needs_redraw.val) {
                      let handled = match (current_ui.val, focused_view_id.val) {
                        (Some(ui), Some(_)) => dispatch_key_event(ui, key, focused_view_id.val)
                        _ => false
                      }
                      if handled { needs_redraw.val = true }
                    }
                  }
                }
              }
            }
          }
        }
      }
      @ffi.InputEvent::Paste(text) => {
        // Global pre-capture for paste
        if on_global_event(@ffi.InputEvent::Paste(text)) {
          needs_redraw.val = true
        } else {
          // Deliver as Event::Paste to focused component
          let mut handled_any = false
          match (current_ui.val, focused_view_id.val) {
            (Some(ui), Some(fid)) => {
              if dispatch_event(ui, @events.Event::Paste(text), Some(fid)) {
                handled_any = true
              }
            }
            _ => ()
          }
          if handled_any { needs_redraw.val = true }
        }
      }
      @ffi.InputEvent::None =>
        // No input available, continue
        ()
      // All other cases are covered; no default branch needed
    }

    // Redraw if needed
    if needs_redraw.val {
      // Clear and rebuild UI
      app.clear(0.05, 0.05, 0.1)

      // Build UI tree (base)
      let ui = build_ui()

      // Store current UI for event dispatch
      current_ui.val = Some(ui)

      // If no focus yet, auto focus the first focusable view
      match focused_pos.val {
        None => {
          let ids = collect_focusable_ids(ui)
          if ids.length() > 0 {
            clear_all_focus(ui)
            let first_id = ids[0]
            let _ = set_view_focused(ui, Some(first_id), true)
            focused_view_id.val = Some(first_id)
            focused_pos.val = Some(0)
          }
        }
        Some(_) => ()
      }

      // Ensure focus after rebuild using traversal index if present
      match focused_pos.val {
        Some(pos) => {
          let ids = collect_focusable_ids(ui)
          if ids.length() > 0 {
            let clamped = if pos >= ids.length() {
              ids.length() - 1
            } else {
              pos
            }
            clear_all_focus(ui)
            let new_id = ids[clamped]
            let _ = set_view_focused(ui, Some(new_id), true)
            focused_view_id.val = Some(new_id)
            focused_pos.val = Some(clamped)
          }
        }
        None => ()
      }

      // If a modal is active, suppress base focus visuals/input focus
      if @widget.ModalManager::is_active() {
        clear_all_focus(ui)
        focused_view_id.val = None
        focused_pos.val = None
      }

      // Calculate layout with Yoga using current app dimensions
      let yoga_root = @layout.calculate_layout(
        ui,
        app.width.to_double().to_float(),
        app.height.to_double().to_float(),
      )

      // Store current layout for event dispatch (free previous tree if available)
      match current_layout.val {
        Some(prev) => prev.free_recursive()
        None => ()
      }
      current_layout.val = Some(yoga_root)

      // Render base UI
      @layout.render_with_layout(app, ui, yoga_root, 0, 0)

      // Render active modal as an overlay pass (on top of base UI)
      match @widget.ModalManager::get_active() {
        Some(modal) => {
          let mv = modal.render()
          current_modal_view.val = Some(mv)
          // Ensure modal focus every frame using traversal index
          let ids = collect_focusable_ids(mv)
          if ids.length() > 0 {
            let desired_pos = match modal_focused_pos.val {
              Some(pos) => if pos >= ids.length() { ids.length() - 1 } else { pos }
              None => 0
            }
            clear_all_focus(mv)
            let new_id = ids[desired_pos]
            let _ = set_view_focused(mv, Some(new_id), true)
            modal_focused_view_id.val = Some(new_id)
            modal_focused_pos.val = Some(desired_pos)
          } else {
            modal_focused_view_id.val = None
            modal_focused_pos.val = None
          }
          let ml = @layout.calculate_layout(
            mv,
            app.width.to_double().to_float(),
            app.height.to_double().to_float(),
          )
          match current_modal_layout.val {
            Some(prev_ml) => prev_ml.free_recursive()
            None => ()
          }
          current_modal_layout.val = Some(ml)
          @layout.render_with_layout(app, mv, ml, 0, 0)
        }
        None => ()
      }

      // Present to screen
      app.render()
      needs_redraw.val = false
    }

    // Frame rate limiting
    @ffi.sleep_ms(frame_time_ms)
  }

  // Cleanup
  match session {
    Some(s) => s.cleanup()
    None => ()
  }
}
