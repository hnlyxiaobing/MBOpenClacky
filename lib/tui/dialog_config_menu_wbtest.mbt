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

///|
/// SPEC-07 regression: config menu labels are truncated at narrow widths.
test "config_menu: truncates long labels at narrow width (SPEC-07)" {
  let items = [
    {
      label: "Very Long Model Name That Should Be Truncated",
      value: "v1",
      multi_select: false,
      checked: false,
    },
  ]
  let m = ConfigMenuDialog::new("Menu", items)
  let node = render_config_menu(m, term_width=40)
  let text = node_to_text(node)
  // The label should be truncated with ellipsis.
  assert_true(text.contains("…"))
  // The label portion itself should be shorter than the original.
  assert_false(text.contains("Very Long Model Name That Should Be Truncated"))
}

///|
/// SPEC-07 regression: config menu uses abbreviated hints at narrow width.
test "config_menu: abbreviated hints at narrow width (SPEC-07)" {
  let m = make_test_menu()
  let node = render_config_menu(m, term_width=60)
  let text = node_to_text(node)
  // Narrow hints should NOT contain "Delete" (full hint has it).
  assert_false(text.contains("Delete"))
  // But should still have "Navigate".
  assert_true(text.contains("Navigate"))
}

///|
/// SPEC-07 regression: config menu shows full hints at wide width.
test "config_menu: full hints at wide width (SPEC-07)" {
  let m = make_test_menu()
  let node = render_config_menu(m, term_width=120)
  let text = node_to_text(node)
  assert_true(text.contains("Delete"))
}

///|
/// SPEC-07 regression: config menu with default term_width has no limit.
test "config_menu: no truncation with default term_width (SPEC-07)" {
  let items = [
    {
      label: "A Very Long Label That Would Normally Be Truncated",
      value: "long-value",
      multi_select: false,
      checked: false,
    },
  ]
  let m = ConfigMenuDialog::new("Menu", items)
  let node = render_config_menu(m)
  let text = node_to_text(node)
  // Full label should be present (no truncation).
  assert_true(text.contains("A Very Long Label"))
  assert_false(text.contains("…"))
}

///|
test "time_machine_menu: markers and cursor on current task" {
  let tm = @agent.TimeMachineState::new("sess-menu")
  ignore(tm.start_new_task(Some("first task")))
  ignore(tm.start_new_task(Some("second task")))
  ignore(tm.undo_last_task()) // current = task-001, task-002 undone
  ignore(tm.start_new_task(Some("branch task")))
  let dialog = ConfigMenuDialog::as_time_machine(tm.history_with_status())
  assert_eq(dialog.title, "Time Machine - Select Task to Navigate")
  assert_eq(dialog.items.length(), 3)
  // ● current (task-003 branch), · on-path (task-001), ✗ undone (task-002)
  assert_true(dialog.items[0].label.has_prefix("· "))
  assert_true(dialog.items[1].label.has_prefix("✗ "))
  assert_true(dialog.items[2].label.has_prefix("● "))
  // Cursor lands on the current task (Ruby initial_index = active).
  assert_eq(dialog.selected_idx, 2)
  // Branch marker on task-001 (two children), undone suffix on task-002.
  assert_true(dialog.items[0].label.contains("⎇"))
  assert_true(dialog.items[1].label.contains("(undone)"))
  // Summary text is shown.
  assert_true(dialog.items[2].label.contains("branch task"))
}

///|
test "mask_api_key_summary: 12+ char keys show first 8 and last 4" {
  // "sk-ant-api03-abcdefghij" (23 chars)
  let masked = mask_api_key_summary("sk-ant-api03-abcdefghij")
  assert_eq(masked, "sk-ant-a" + "*".repeat(20) + "ghij")
}

///|
test "mask_api_key_summary: short or empty keys render as (not set)" {
  assert_eq(mask_api_key_summary(""), "(not set)")
  assert_eq(mask_api_key_summary("short"), "(not set)")
  assert_eq(mask_api_key_summary("12345678901"), "(not set)")
}

///|
test "model drawer: card items mark active and expandable" {
  let models = [
    @config.ModelConfig::new("m1", "k1", "https://api.openai.com/v1", "gpt-4o"),
    @config.ModelConfig::new(
      "m2", "k2", "https://custom.example.com", "custom-x",
    ),
  ]
  let items = build_model_card_items(models, Some("m1"))
  assert_eq(items.length(), 2)
  // OpenAI card has provider sub-models → expandable "›" marker.
  assert_true(items[0].label.contains("(active)"))
  assert_true(items[0].label.contains("›"))
  assert_eq(items[0].value, "m1")
  // Custom base_url has no provider preset → no drawer, no marker.
  assert_true(!items[1].label.contains("›"))
  assert_true(provider_submodels(models[1]).is_empty())
}

///|
test "model drawer: sub-model items put Default first and mark overlay" {
  let card = @config.ModelConfig::new(
    "m1", "k1", "https://api.anthropic.com", "claude-sonnet-4-6",
  )
  // No overlay: Default is the active entry.
  let items = build_submodel_items(card, None)
  assert_true(items[0].label.has_prefix("Default (claude-sonnet-4-6)"))
  assert_true(items[0].label.contains("(active)"))
  assert_eq(items[0].value, "")
  assert_true(items.length() > 2) // Default + provider sub-models
  // Overlay pinned: the matching sub-model is active, Default is not.
  let items2 = build_submodel_items(card, Some("claude-haiku-4-5"))
  assert_true(!items2[0].label.contains("(active)"))
  let mut found = false
  for item in items2 {
    if item.value == "claude-haiku-4-5" {
      found = true
      assert_true(item.label.contains("(active)"))
    }
  }
  assert_true(found)
}
