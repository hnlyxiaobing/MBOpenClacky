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

///|
test "config_menu: mask_api_key short key" {
  @debug.assert_eq(mask_api_key("short"), "****")
  @debug.assert_eq(mask_api_key("12345678"), "****")
}

///|
test "config_menu: mask_api_key long key" {
  let masked = mask_api_key("sk-ant-abc123xyz789")
  assert_true(masked.has_prefix("sk-"))
  assert_true(masked.has_suffix("z789"))
  assert_true(masked.contains("..."))
}

///|
test "config_menu: build_config_menu_items from models" {
  let models = [
    @config.ModelConfig::new(
      "m1", "sk-key1abcdefgh", "https://api.example.com", "gpt-4",
    ),
    @config.ModelConfig::new(
      "m2", "sk-key2abcdefgh", "https://api.example.com", "claude-3",
    ),
  ]
  let items = build_config_menu_items(models, Some("m1"))
  @debug.assert_eq(items.length(), 2)
  // First item should have current marker
  assert_true(items[0].label.contains("●"))
  // Second item should not
  assert_false(items[1].label.contains("●"))
  // Both should have masked keys
  assert_true(items[0].label.contains("..."))
}

///|
test "config_menu: from_models creates dialog" {
  let models = [
    @config.ModelConfig::new(
      "m1", "sk-key1", "https://api.example.com", "gpt-4",
    ),
  ]
  let dialog = ConfigMenuDialog::from_models(models, Some("m1"))
  @debug.assert_eq(dialog.title, "Configuration Menu")
  @debug.assert_eq(dialog.items.length(), 1)
}

///|
test "config_menu: as_model_selector creates dialog" {
  let models = [
    @config.ModelConfig::new(
      "m1", "sk-key1", "https://api.example.com", "gpt-4",
    ),
    @config.ModelConfig::new(
      "m2", "sk-key2", "https://api.example.com", "claude-3",
    ),
  ]
  let dialog = ConfigMenuDialog::as_model_selector(models, None)
  @debug.assert_eq(dialog.title, "Select Model")
  @debug.assert_eq(dialog.items.length(), 2)
  // First model should have (active) marker only if selected
  assert_false(dialog.items[0].label.contains("(active)"))
}
