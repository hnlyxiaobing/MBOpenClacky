///|
/// Test Yoga FFI with real library
test "ffi run demo" {
  println("=== Testing Yoga FFI with Real Library ===")

  // Test native FFI functions
  test_native_ffi()

  // Test wrapper API  
  test_wrapper_api()
}

///|
fn test_native_ffi() -> Unit {
  println("\n1. Testing Native FFI Functions:")
  println("--------------------------------")

  // Create config and node using native FFI
  let config = @ffi.yoga_config_new_native()
  let node = @ffi.yoga_node_new_with_config_native(config)
  println("✓ Created config and node via native FFI")

  // Set properties
  @ffi.yoga_node_set_display_native(node, @types.Display::Flex)
  @ffi.yoga_node_set_flex_direction_native(node, @types.FlexDirection::Row)
  @ffi.yoga_node_set_width_native(node, 200.0)
  @ffi.yoga_node_set_height_native(node, 100.0)
  println("✓ Set node properties")

  // Calculate layout
  @ffi.yoga_node_calculate_layout_native(
    node,
    200.0,
    100.0,
    @types.Direction::LTR,
  )
  println("✓ Calculated layout")

  // Get results
  let layout = @ffi.yoga_node_get_layout_native(node)
  println(
    "✓ Layout result: left=\{layout.left}, top=\{layout.top}, width=\{layout.width}, height=\{layout.height}",
  )

  // Clean up
  @ffi.yoga_node_free_native(node)
  @ffi.yoga_config_free_native(config)
  println("✓ Cleaned up resources")
}

///|
fn test_wrapper_api() -> Unit {
  println("\n2. Testing Wrapper API:")
  println("-----------------------")

  // Create a simple layout using the yoga package
  let root = @yoga.Node::new()
  root.set_flex_direction(@types.FlexDirection::Column)
  root.set_width_points(300.0)
  root.set_height_points(200.0)
  root.set_padding_all(@types.Value::point(10.0))
  println("✓ Created root node with wrapper API")

  // Add children
  let child1 = @yoga.Node::new()
  child1.set_flex_grow(1.0)
  child1.set_margin(@types.Edge::Bottom, @types.Value::point(5.0))
  root.add_child(child1)
  let child2 = @yoga.Node::new()
  child2.set_height_points(50.0)
  root.add_child(child2)
  println("✓ Added child nodes")

  // Calculate layout
  root.calculate_layout(300.0, 200.0, @types.Direction::LTR)

  // Print results
  println("✓ Root layout: left=\{root.layout_left()}, top=\{root.layout_top()}, width=\{root.layout_width()}, height=\{root.layout_height()}")
  println("✓ Child 1 layout: left=\{child1.layout_left()}, top=\{child1.layout_top()}, width=\{child1.layout_width()}, height=\{child1.layout_height()}")
  println("✓ Child 2 layout: left=\{child2.layout_left()}, top=\{child2.layout_top()}, width=\{child2.layout_width()}, height=\{child2.layout_height()}")

  // The nodes will be cleaned up automatically by wrapper destructors
  println("✓ Wrapper API test complete")
}

///|
test "real yoga calculations" {
  println("\n3. Testing Real Yoga Calculations:")
  println("----------------------------------")
  let root = @yoga.Node::new()
  root.set_flex_direction(@types.FlexDirection::Row)
  root.set_width_points(500.0)
  root.set_justify_content(@types.Justify::SpaceEvenly)
  root.set_align_items(@types.Align::Center)

  // Add 3 equal-sized children
  for i = 0; i < 3; i = i + 1 {
    let child = @yoga.Node::new()
    child.set_width_points(100.0)
    child.set_height_points(80.0)
    root.add_child(child)
  }
  root.calculate_layout(500.0, 200.0, @types.Direction::LTR)
  println("✓ SpaceEvenly layout calculated:")
  println("  Root: left=\{root.layout_left()}, top=\{root.layout_top()}, width=\{root.layout_width()}, height=\{root.layout_height()}")
  for i = 0; i < 3; i = i + 1 {
    match root.get_child(i) {
      Some(child) => {
        println(
          "  Child \{i}: left=\{child.layout_left()}, top=\{child.layout_top()}, width=\{child.layout_width()}, height=\{child.layout_height()}",
        )
      }
      None => ()
    }
  }
}
