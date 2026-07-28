///|
/// Lightweight Node-based rendering system for composable TUI components.
///
/// Provides a simple enum-based tree (Text/Column/Row/Border/Padding/Styled)
/// with a recursive text extraction function.

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
      result.trim_end().to_owned()
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
