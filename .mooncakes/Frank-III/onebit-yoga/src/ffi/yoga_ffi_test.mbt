///|
/// Test the Yoga FFI integration
test "yoga_config" {
  // Test config creation and destruction
  let config = yoga_config_new()
  inspect(config, content="YogaConfigRef(0)")
  yoga_config_free(config)
}

///|
test "yoga_node_basic" {
  // Test node creation
  let node = yoga_node_new()
  inspect(node, content="YogaNodeRef(0)")

  // Set some style properties
  yoga_node_set_width(node, 100.0)
  yoga_node_set_height(node, 50.0)
  yoga_node_set_flex_direction(node, @types.FlexDirection::Row)
  yoga_node_set_justify_content(node, @types.Justify::Center)

  // Calculate layout
  yoga_node_calculate_layout(node, 200.0, 100.0, @types.Direction::LTR)

  // Get layout results
  let layout = yoga_node_get_layout(node)
  inspect(layout, content="{left: 0, top: 0, width: 100, height: 50}")

  // Clean up
  yoga_node_free(node)
}

///|
test "yoga_node_tree" {
  // Test parent-child relationships
  let parent = yoga_node_new()
  let child1 = yoga_node_new()
  let child2 = yoga_node_new()

  // Set parent size
  yoga_node_set_width(parent, 300.0)
  yoga_node_set_height(parent, 200.0)
  yoga_node_set_flex_direction(parent, @types.FlexDirection::Row)

  // Set child sizes
  yoga_node_set_flex(child1, 1.0)
  yoga_node_set_flex(child2, 1.0)

  // Build tree
  yoga_node_insert_child(parent, child1, 0)
  yoga_node_insert_child(parent, child2, 1)

  // Calculate layout
  yoga_node_calculate_layout(parent, 300.0, 200.0, @types.Direction::LTR)

  // Check child count
  let child_count = yoga_node_get_child_count(parent)
  inspect(child_count, content="2")

  // Clean up
  yoga_node_free(child1)
  yoga_node_free(child2)
  yoga_node_free(parent)
}

///|
test "yoga_wrapper_api" {
  // Test the high-level wrapper API
  let config = yoga_config_new_native()
  inspect(config, content="YogaConfigRef(0)")
  let node = yoga_node_new_with_config_native(config)
  inspect(node, content="YogaNodeRef(0)")

  // Set display
  yoga_node_set_display_native(node, @types.Display::Flex)
  yoga_node_set_flex_direction_native(node, @types.FlexDirection::Column)

  // Calculate layout
  yoga_node_calculate_layout_native(node, 100.0, 100.0, @types.Direction::LTR)
  let layout = yoga_node_get_layout_native(node)
  inspect(layout, content="{left: 0, top: 0, width: 100, height: 100}")

  // Clean up
  yoga_node_free_native(node)
  yoga_config_free_native(config)
}
