///|
using @cmd {type Cmd}

///|
/// Scroll behavior for navigation commands.
///
/// These variants map to the DOM `ScrollBehavior` string values:
/// `auto`, `instant`, and `smooth`.
#cfg(target="js")
pub(all) enum ScrollBehavior {
  Auto
  Instant
  Smooth
}

///|
#cfg(target="js")
pub impl Show for ScrollBehavior with fn output(self, buf) {
  match self {
    Auto => buf.write_string("auto")
    Instant => buf.write_string("instant")
    Smooth => buf.write_string("smooth")
  }
}

///|
/// Create a command to scroll the window to a specific position.
#cfg(target="js")
pub fn scroll_to_pos(
  x : Int,
  y : Int,
  behavior? : ScrollBehavior = Auto,
) -> Cmd {
  @cmd.custom_cmd(kind=AfterRender, _ => {
    @dom.window().scroll_to(x, y, behavior=behavior.to_string())
  })
}

///|
/// Create a command to scroll the window by a specific amount.
#cfg(target="js")
pub fn scroll_by_pos(
  x : Int,
  y : Int,
  behavior? : ScrollBehavior = Auto,
) -> Cmd {
  @cmd.custom_cmd(kind=AfterRender, _ => {
    @dom.window().scroll_by(x, y, behavior=behavior.to_string())
  })
}

///|
/// Create a command to scroll the window to a specific element.
/// The element is specified by its id.
#cfg(target="js")
pub fn scroll_to(element : String, behavior? : ScrollBehavior = Auto) -> Cmd {
  @cmd.custom_cmd(kind=AfterRender, _ => {
    match @dom.document().get_element_by_id(element).to_option() {
      Some(e) => e.scroll_into_view(behavior=behavior.to_string())
      None => ()
    }
  })
}

///|
/// Create a command to scroll the window to the top.
#cfg(target="js")
pub fn scroll_to_top(behavior? : ScrollBehavior = Auto) -> Cmd {
  @cmd.custom_cmd(kind=AfterRender, _ => {
    @dom.window().scroll_to_top(behavior=behavior.to_string())
  })
}

///|
/// Create a command to scroll the window to the bottom.
#cfg(target="js")
pub fn scroll_to_bottom(behavior? : ScrollBehavior = Auto) -> Cmd {
  @cmd.custom_cmd(kind=AfterRender, _ => {
    @dom.window().scroll_to_bottom(behavior=behavior.to_string())
  })
}
