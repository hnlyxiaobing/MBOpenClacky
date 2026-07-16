///|
/// Enhanced Approval Dialog rendering using the Node system.
///
/// Renders tool approval prompts as a bordered dialog with:
/// - Tool name (bold)
/// - Argument summary (truncated when collapsed)
/// - Expandable details section (full args when expanded)
/// - Button row: [y] Allow | [n] Deny | [d] Details

///|
/// Maximum characters for collapsed argument summary.
let approval_summary_max = 80

///|
/// Render an ApprovalDialog state as a Node tree.
pub fn render_approval_dialog(dialog : ApprovalDialog) -> Node {
  let children : Array[Node] = []

  // Tool name (bold)
  children.push(Node::Text("Tool: \{dialog.tool_name}", Style::new(bold=true)))

  // Argument summary (truncated when collapsed)
  let summary = if dialog.tool_args.length() > approval_summary_max {
    dialog.tool_args[0:approval_summary_max].to_owned() + "..."
  } else {
    dialog.tool_args
  }
  children.push(Node::Text("Args: \{summary}", Style::default_()))

  // Details section (expanded)
  if dialog.show_details {
    children.push(Node::Text("", Style::default_()))
    children.push(Node::Text("─ Details ─", Style::new(dim=true)))
    children.push(Node::Text(dialog.detailed_args, Style::new(dim=true)))
  }

  // Button row
  let buttons : Array[Node] = [
    Node::Text(
      "[y] Allow",
      Style::new(fg=@color.Color::Basic(@color.BasicColor::Green), bold=true),
    ),
    Node::Text(
      "[n] Deny",
      Style::new(fg=@color.Color::Basic(@color.BasicColor::Red), bold=true),
    ),
    Node::Text(
      if dialog.show_details {
        "[d] Hide Details"
      } else {
        "[d] Details"
      },
      Style::new(fg=@color.Color::Basic(@color.BasicColor::Yellow)),
    ),
  ]
  children.push(Node::Text("", Style::default_()))
  children.push(Node::Row(buttons))

  Node::Border(Some("⚠ Approval Required"), children)
}

///|
/// Create an ApprovalDialog from tool name and args.
pub fn ApprovalDialog::new(
  tool_name : String,
  tool_args : String,
) -> ApprovalDialog {
  { tool_name, tool_args, show_details: false, detailed_args: tool_args }
}

///|
/// Toggle the details section of an ApprovalDialog.
pub fn ApprovalDialog::toggle_details(self : ApprovalDialog) -> Unit {
  self.show_details = !self.show_details
}
