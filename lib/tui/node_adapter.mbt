///|
/// Node-to-VNode adapter.
///
/// Converts the existing Node tree (used by dialog_*, thinking_view,
/// file_browser, etc.) to mizchi/tui's VNode tree for rendering through
/// the VNodeRenderer.
///
/// This allows existing components to work with the new VNode-based
/// rendering pipeline without changing their return types.

///|
/// Convert a Node tree to a VNode tree.
pub fn node_to_vnode(node : Node) -> @vnode.TuiNode {
  match node {
    Text(content, style) => text_to_vnode(content, style)
    Column(children) => @vnode.column(children.map(fn(c) { node_to_vnode(c) }))
    Row(children) => @vnode.row(children.map(fn(c) { node_to_vnode(c) }))
    Border(title, children) => border_to_vnode(title, children)
    Padding(v, h, child) =>
      @vnode.view(
        direction="column",
        padding_x=h.to_double(),
        padding_y=v.to_double(),
        [node_to_vnode(child)],
      )
    Styled(style, child) => styled_to_vnode(style, child)
    Empty => @vnode.text("")
  }
}

///|
/// Convert a Text node to a VNode text element.
fn text_to_vnode(content : String, style : Style) -> @vnode.TuiNode {
  let plain = strip_ansi(content)
  // Dim overrides fg with gray
  if style.dim {
    return @vnode.text(plain, fg="rgb(128,128,128)", bold=style.bold)
  }
  match style.fg {
    Some(c) => @vnode.text(plain, fg=color_to_string(c), bold=style.bold)
    None => @vnode.text(plain, bold=style.bold)
  }
}

///|
/// Convert a Styled wrapper to a VNode.
fn styled_to_vnode(style : Style, child : Node) -> @vnode.TuiNode {
  match child {
    Text(content, _) => text_to_vnode(content, style)
    _ => node_to_vnode(child)
  }
}

///|
/// Convert a Border node to a VNode bordered view.
fn border_to_vnode(title : String?, children : Array[Node]) -> @vnode.TuiNode {
  let child_nodes : Array[@vnode.TuiNode] = []
  // If there's a title, add it as the first text element
  match title {
    Some(t) => child_nodes.push(@vnode.text(strip_ansi(t), bold=true))
    None => ()
  }
  for child in children {
    child_nodes.push(node_to_vnode(child))
  }
  @vnode.view(
    direction="column",
    border="rounded",
    border_color="blue",
    padding_x=1.0,
    child_nodes,
  )
}

///|
/// Convert a @color.Color to a VNode color string.
///
/// Maps the 16 ANSI basic colors to named CSS colors, and RGB colors
/// to "rgb(r,g,b)" format supported by mizchi/tui.
fn color_to_string(color : @color.Color) -> String {
  match color {
    @color.Color::Default => "white"
    @color.Color::Basic(basic) => basic_color_to_string(basic)
    @color.Color::Indexed(_) => "white"
    @color.Color::Rgb(r, g, b) => "rgb(\{r},\{g},\{b})"
  }
}

///|
/// Map a BasicColor to a CSS color name.
fn basic_color_to_string(c : @color.BasicColor) -> String {
  match c {
    @color.BasicColor::Black => "black"
    @color.BasicColor::Red => "red"
    @color.BasicColor::Green => "green"
    @color.BasicColor::Yellow => "yellow"
    @color.BasicColor::Blue => "blue"
    @color.BasicColor::Magenta => "magenta"
    @color.BasicColor::Cyan => "cyan"
    @color.BasicColor::White => "white"
    @color.BasicColor::BrightBlack => "rgb(128,128,128)"
    @color.BasicColor::BrightRed => "rgb(255,85,85)"
    @color.BasicColor::BrightGreen => "rgb(85,255,85)"
    @color.BasicColor::BrightYellow => "rgb(255,255,85)"
    @color.BasicColor::BrightBlue => "rgb(85,85,255)"
    @color.BasicColor::BrightMagenta => "rgb(255,85,255)"
    @color.BasicColor::BrightCyan => "rgb(85,255,255)"
    @color.BasicColor::BrightWhite => "rgb(255,255,255)"
  }
}
