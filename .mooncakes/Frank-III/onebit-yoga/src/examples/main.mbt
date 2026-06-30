///|
/// Yoga Layout Examples
fn main {
  println("=== Yoga Layout MoonBit Examples ===\n")

  // Example 1: Simple row layout
  simple_row_example()

  // Example 2: Column with flex
  flex_column_example()

  // Example 3: Nested layout
  nested_layout_example()

  // Example 4: Using the builder API
  builder_api_example()

  // Touch an FFI symbol to exercise alias usage (avoid unused alias warnings)
  let _ = @ffi.yoga_config_new_native
}

///|
fn simple_row_example() -> Unit {
  println("1. Simple Row Layout:")
  println("---------------------")

  // Create root node
  let root = @yoga.Node::new()
  root.set_flex_direction(@yoga.FlexDirection::Row)
  root.set_width_points(300.0)
  root.set_height_points(100.0)
  root.set_padding_all(@types.Value::point(10.0))

  // Create three child boxes
  for i = 0; i < 3; i = i + 1 {
    let child = @yoga.Node::new()
    child.set_width_points(80.0)
    child.set_height_points(50.0)
    child.set_margin(@yoga.Edge::Right, @yoga.Value::point(10.0))
    root.add_child(child)
  }

  // Calculate layout
  root.calculate_layout(300.0, 100.0, @yoga.Direction::LTR)

  // Print results
  println("Root: left=\{root.layout_left()}, top=\{root.layout_top()}, w=\{root.layout_width()}, h=\{root.layout_height()}")
  for i = 0; i < root.get_child_count(); i = i + 1 {
    match root.get_child(i) {
      Some(child) => {
        println("Child \{i}: left=\{child.layout_left()}, top=\{child.layout_top()}, w=\{child.layout_width()}, h=\{child.layout_height()}")
      }
      None => ()
    }
  }
  println("")
}

///|
fn flex_column_example() -> Unit {
  println("2. Flex Column Layout:")
  println("----------------------")
  let root = @yoga.Node::new()
  root.set_flex_direction(@yoga.FlexDirection::Column)
  root.set_width_points(200.0)
  root.set_height_points(300.0)
  root.set_justify_content(@yoga.Justify::SpaceBetween)
  root.set_align_items(@yoga.Align::Center)

  // Header
  let header = @yoga.Node::new()
  header.set_width_percent(100.0)
  header.set_height_points(50.0)
  root.add_child(header)

  // Content (flex grow)
  let content = @yoga.Node::new()
  content.set_width_percent(90.0)
  content.set_flex_grow(1.0)
  root.add_child(content)

  // Footer
  let footer = @yoga.Node::new()
  footer.set_width_percent(100.0)
  footer.set_height_points(40.0)
  root.add_child(footer)
  root.calculate_layout(200.0, 300.0, @yoga.Direction::LTR)
  println("Root: w=\{root.layout_width()}, h=\{root.layout_height()}")
  println("Header: w=\{header.layout_width()}, h=\{header.layout_height()}")
  println("Content: w=\{content.layout_width()}, h=\{content.layout_height()}")
  println("Footer: w=\{footer.layout_width()}, h=\{footer.layout_height()}")
  println("")
}

///|
fn nested_layout_example() -> Unit {
  println("3. Nested Layout:")
  println("-----------------")
  let root = @yoga.Node::new()
  root.set_width_points(400.0)
  root.set_height_points(300.0)
  root.set_flex_direction(@yoga.FlexDirection::Row)
  root.set_padding_all(@yoga.Value::point(20.0))

  // Left sidebar
  let sidebar = @yoga.Node::new()
  sidebar.set_width_points(100.0)
  sidebar.set_height_percent(100.0)
  sidebar.set_margin(@yoga.Edge::Right, @yoga.Value::point(20.0))
  root.add_child(sidebar)

  // Main content area
  let main_area = @yoga.Node::new()
  main_area.set_flex_grow(1.0)
  main_area.set_flex_direction(@yoga.FlexDirection::Column)
  root.add_child(main_area)

  // Add header to main area
  let header = @yoga.Node::new()
  header.set_height_points(60.0)
  header.set_width_percent(100.0)
  header.set_margin(@yoga.Edge::Bottom, @yoga.Value::point(10.0))
  main_area.add_child(header)

  // Add content to main area
  let content = @yoga.Node::new()
  content.set_flex_grow(1.0)
  main_area.add_child(content)
  root.calculate_layout(400.0, 300.0, @yoga.Direction::LTR)
  println("Root: w=\{root.layout_width()}, h=\{root.layout_height()}")
  println("Sidebar: w=\{sidebar.layout_width()}, h=\{sidebar.layout_height()}")
  println("Main Area: w=\{main_area.layout_width()}, h=\{main_area.layout_height()}")
  println("  Header: w=\{header.layout_width()}, h=\{header.layout_height()}")
  println("  Content: w=\{content.layout_width()}, h=\{content.layout_height()}")
  println("")
}

///|
fn builder_api_example() -> Unit {
  println("4. Builder API Example:")
  println("-----------------------")

  // Create a centered container with children
  let container = @yoga.NodeBuilder::center()
    .width(300.0)
    .height(200.0)
    .padding(20.0)
    .build()

  // Create a row with spaced items
  let row = @yoga.NodeBuilder::row()
    .width_percent(100.0)
    .height(50.0)
  .justify(@yoga.Justify::SpaceBetween)
    .build()

  // Add some boxes to the row
  for i = 0; i < 3; i = i + 1 {
    let box = @yoga.NodeBuilder::new().width(60.0).height(40.0).build()
    row.add_child(box)
  }
  container.add_child(row)

  // Add a spacer and another element
  let spacer = @yoga.NodeBuilder::spacer().build()
  container.add_child(spacer)
  let bottom_element = @yoga.NodeBuilder::new()
    .width_percent(80.0)
    .height(30.0)
    .align_self(@yoga.Align::Center)
    .build()
  container.add_child(bottom_element)
  container.calculate_layout(300.0, 200.0, @yoga.Direction::LTR)
  println("Container: w=\{container.layout_width()}, h=\{container.layout_height()}")
  println("Row: w=\{row.layout_width()}, h=\{row.layout_height()}")
  for i = 0; i < row.get_child_count(); i = i + 1 {
    match row.get_child(i) {
      Some(child) => println("  Box \{i}: w=\{child.layout_width()}, h=\{child.layout_height()}")
      None => ()
    }
  }
  println("Bottom Element: w=\{bottom_element.layout_width()}, h=\{bottom_element.layout_height()}")
  println("")
}
