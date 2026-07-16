///|
/// Lightweight Node-based rendering system for composable TUI components.
///
/// Provides a simple enum-based tree (Text/Column/Row/Border/Padding/Styled)
/// and a recursive `render_node` function that writes to ScreenBuffer.
/// Avoids external dependencies (no Virtual DOM, no diffing).

///|
/// ANSI color option for styling.
pub(all) struct Style {
  fg : @color.Color?
  bg : @color.Color?
  bold : Bool
  dim : Bool
}

///|
pub fn Style::default_() -> Style {
  { fg: None, bg: None, bold: false, dim: false }
}

///|
pub fn Style::new(
  fg? : @color.Color = @color.Color::Default,
  bg? : @color.Color = @color.Color::Default,
  bold? : Bool = false,
  dim? : Bool = false,
) -> Style {
  { fg: Some(fg), bg: Some(bg), bold, dim }
}

///|
/// A node in the rendering tree.
pub enum Node {
  /// Styled text string.
  Text(String, Style)
  /// Vertical stack of children.
  Column(Array[Node])
  /// Horizontal row of children.
  Row(Array[Node])
  /// Box border with optional title.
  Border(String?, Array[Node])
  /// Padding wrapper (vertical, horizontal).
  Padding(Int, Int, Node)
  /// Style wrapper applied to child.
  Styled(Style, Node)
  /// Empty node (renders nothing).
  Empty
}

///|
/// Apply a Style to the ScreenBuffer (set colors, bold, dim).
async fn apply_style(screen : ScreenBuffer, style : Style) -> Unit {
  match style.fg {
    Some(c) => screen.set_foreground(c)
    None => ()
  }
  if style.bold {
    screen.bold()
  }
}

///|
/// Reset all styles on the ScreenBuffer.
async fn reset_styles(screen : ScreenBuffer) -> Unit {
  screen.reset_style()
}

///|
/// Render a Node tree to the ScreenBuffer at the given position.
///
/// Returns the number of terminal rows consumed.
pub async fn render_node(
  screen : ScreenBuffer,
  node : Node,
  row : Int,
  col : Int,
  width : Int,
) -> Int {
  match node {
    Text(text, style) => {
      screen.move_cursor(row, col)
      apply_style(screen, style)
      screen.write_string(text)
      reset_styles(screen)
      1
    }
    Column(children) => {
      let mut current_row = row
      for child in children {
        let consumed = render_node(screen, child, current_row, col, width)
        current_row = current_row + consumed
      }
      current_row - row
    }
    Row(children) => {
      let mut current_col = col
      for child in children {
        let text = node_to_text(child)
        let w = string_display_width(text)
        let _ = render_node(screen, child, row, current_col, width)
        current_col = current_col + w + 1
      }
      1
    }
    Border(title, children) => {
      let border_w = width
      // Top border: ┌─ Title ──...─┐
      screen.move_cursor(row, col)
      screen.set_foreground(@color.Color::Basic(@color.BasicColor::Blue))
      screen.write_string("┌")
      match title {
        Some(t) => {
          screen.write_string("─ ")
          screen.write_string(t)
          screen.write_string(" ")
          let used = 4 + string_display_width(t)
          let remaining = border_w - used - 1
          if remaining > 0 {
            for _ in 0..<remaining {
              screen.write_string("─")
            }
          }
        }
        None => {
          let remaining = border_w - 2
          if remaining > 0 {
            for _ in 0..<remaining {
              screen.write_string("─")
            }
          }
        }
      }
      screen.write_string("┐")
      screen.reset_style()
      // Children
      let mut current_row = row + 1
      for child in children {
        screen.move_cursor(current_row, col)
        screen.set_foreground(@color.Color::Basic(@color.BasicColor::Blue))
        screen.write_string("│ ")
        screen.reset_style()
        let _ = render_node(screen, child, current_row, col + 2, width - 3)
        screen.move_cursor(current_row, col + width - 1)
        screen.set_foreground(@color.Color::Basic(@color.BasicColor::Blue))
        screen.write_string("│")
        screen.reset_style()
        current_row = current_row + 1
      }
      // Bottom border: └──...──┘
      screen.move_cursor(current_row, col)
      screen.set_foreground(@color.Color::Basic(@color.BasicColor::Blue))
      screen.write_string("└")
      let remaining = border_w - 2
      if remaining > 0 {
        for _ in 0..<remaining {
          screen.write_string("─")
        }
      }
      screen.write_string("┘")
      screen.reset_style()
      current_row - row + 1
    }
    Padding(v, h, child) =>
      render_node(screen, child, row + v, col + h, width - h * 2)
    Styled(style, child) =>
      match child {
        Text(text, _) => {
          screen.move_cursor(row, col)
          apply_style(screen, style)
          screen.write_string(text)
          reset_styles(screen)
          1
        }
        _ => render_node(screen, child, row, col, width)
      }
    Empty => 0
  }
}

///|
/// Extract plain text from a Node (for width calculation).
pub fn node_to_text(node : Node) -> String {
  match node {
    Text(text, _) => text
    Column(children) => {
      let mut result = ""
      for child in children {
        let t = node_to_text(child)
        if result.length() == 0 {
          result = t
        } else {
          result = result + " " + t
        }
      }
      result
    }
    Row(children) => {
      let mut result = ""
      for child in children {
        result = result + node_to_text(child) + " "
      }
      result.trim_end().to_string()
    }
    Border(title, children) => {
      let mut result = match title {
        Some(t) => t
        None => ""
      }
      for child in children {
        result = result + " " + node_to_text(child)
      }
      result
    }
    Padding(_, _, child) => node_to_text(child)
    Styled(_, child) => node_to_text(child)
    Empty => ""
  }
}
