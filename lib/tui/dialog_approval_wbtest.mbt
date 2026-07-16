///|
/// Tests for ApprovalDialog rendering and interaction.

///|
test "approval: new dialog has show_details=false" {
  let d = ApprovalDialog::new("terminal", "rm -rf /tmp")
  assert_false(d.show_details)
  @debug.assert_eq(d.tool_name, "terminal")
  @debug.assert_eq(d.tool_args, "rm -rf /tmp")
}

///|
test "approval: toggle_details flips state" {
  let d = ApprovalDialog::new("write", "/etc/passwd")
  assert_false(d.show_details)
  d.toggle_details()
  assert_true(d.show_details)
  d.toggle_details()
  assert_false(d.show_details)
}

///|
test "approval: render produces Border node" {
  let d = ApprovalDialog::new("terminal", "ls -la")
  let node = render_approval_dialog(d)
  let text = node_to_text(node)
  assert_true(text.contains("terminal"))
  assert_true(text.contains("ls -la"))
  assert_true(text.contains("Allow"))
  assert_true(text.contains("Deny"))
}

///|
test "approval: collapsed shows truncated args" {
  let long_args = "a".repeat(100)
  let d = ApprovalDialog::new("terminal", long_args)
  let node = render_approval_dialog(d)
  let text = node_to_text(node)
  assert_true(text.contains("..."))
}

///|
test "approval: expanded shows full args" {
  let long_args = "a".repeat(100)
  let d = ApprovalDialog::new("terminal", long_args)
  d.show_details = true
  let node = render_approval_dialog(d)
  let text = node_to_text(node)
  assert_true(text.contains("Details"))
  assert_true(text.contains("Hide"))
}
