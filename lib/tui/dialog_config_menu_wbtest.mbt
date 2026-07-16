///|
/// Tests for ConfigMenuDialog rendering and navigation.
fn make_test_menu() -> ConfigMenuDialog {
  let items = [
    { label: "Option A", value: "a", multi_select: false, checked: false },
    { label: "Option B", value: "b", multi_select: false, checked: false },
    { label: "Option C", value: "c", multi_select: false, checked: false },
  ]
  ConfigMenuDialog::new("Test Menu", items)
}

///|
fn make_multi_menu() -> ConfigMenuDialog {
  let items = [
    { label: "Enable X", value: "", multi_select: true, checked: false },
    { label: "Enable Y", value: "", multi_select: true, checked: false },
    { label: "Enable Z", value: "", multi_select: true, checked: false },
  ]
  ConfigMenuDialog::new("Multi Menu", items)
}

///|
test "config_menu: new dialog starts at index 0" {
  let m = make_test_menu()
  @debug.assert_eq(m.selected_idx, 0)
  @debug.assert_eq(m.items.length(), 3)
}

///|
test "config_menu: move_down increments selected_idx" {
  let m = make_test_menu()
  m.move_down()
  @debug.assert_eq(m.selected_idx, 1)
  m.move_down()
  @debug.assert_eq(m.selected_idx, 2)
}

///|
test "config_menu: move_down stops at last item" {
  let m = make_test_menu()
  m.move_down()
  m.move_down()
  m.move_down()
  @debug.assert_eq(m.selected_idx, 2)
}

///|
test "config_menu: move_up decrements selected_idx" {
  let m = make_test_menu()
  m.move_down()
  m.move_down()
  m.move_up()
  @debug.assert_eq(m.selected_idx, 1)
}

///|
test "config_menu: move_up stops at first item" {
  let m = make_test_menu()
  m.move_up()
  @debug.assert_eq(m.selected_idx, 0)
}

///|
test "config_menu: toggle_current checks multi-select" {
  let m = make_multi_menu()
  m.toggle_current()
  assert_true(m.checked[0])
  m.toggle_current()
  assert_false(m.checked[0])
}

///|
test "config_menu: get_selected returns current item" {
  let m = make_test_menu()
  m.move_down()
  let selected = m.get_selected()
  assert_true(selected is Some(_))
  match selected {
    Some(item) => @debug.assert_eq(item.label, "Option B")
    None => assert_true(false)
  }
}

///|
test "config_menu: get_checked returns only checked items" {
  let m = make_multi_menu()
  m.toggle_current()
  m.move_down()
  m.toggle_current()
  let checked = m.get_checked()
  @debug.assert_eq(checked.length(), 2)
}

///|
test "config_menu: render produces Border node with title" {
  let m = make_test_menu()
  let node = render_config_menu(m)
  let text = node_to_text(node)
  assert_true(text.contains("Test Menu"))
  assert_true(text.contains("Option A"))
  assert_true(text.contains("Option B"))
}
