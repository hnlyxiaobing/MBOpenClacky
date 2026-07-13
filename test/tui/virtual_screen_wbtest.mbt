///|
/// Tests for VirtualScreen — L1 rendering snapshot tests.
///
/// These tests verify the in-memory character grid rendering
/// without any terminal or async dependencies.
test "VirtualScreen::new creates empty grid" {
  let screen = VirtualScreen::new(20, 5)
  // All rows should be empty (just spaces)
  @debug.debug_inspect(
    screen.content_trimmed(),
    content=(
      #|""
    ),
  )
}

///|
test "VirtualScreen::write_string writes at cursor" {
  let screen = VirtualScreen::new(20, 5)
  screen.move_cursor(1, 1)
  screen.write_string("Hello")
  @debug.debug_inspect(
    screen.get_row_trimmed(1),
    content=(
      #|"Hello"
    ),
  )
}

///|
test "VirtualScreen::move_cursor clamps to bounds" {
  let screen = VirtualScreen::new(10, 5)
  screen.move_cursor(0, 0) // Below minimum
  @debug.debug_inspect(screen.cursor_row, content="1")
  @debug.debug_inspect(screen.cursor_col, content="1")
  screen.move_cursor(100, 100) // Above maximum
  @debug.debug_inspect(screen.cursor_row, content="5")
  @debug.debug_inspect(screen.cursor_col, content="10")
}

///|
test "VirtualScreen::clear_to_eol clears from cursor" {
  let screen = VirtualScreen::new(20, 5)
  screen.move_cursor(1, 1)
  screen.write_string("Hello World")
  screen.move_cursor(1, 6)
  screen.clear_to_eol()
  @debug.debug_inspect(
    screen.get_row_trimmed(1),
    content=(
      #|"Hello"
    ),
  )
}

///|
test "VirtualScreen::clear_line clears entire line" {
  let screen = VirtualScreen::new(20, 5)
  screen.move_cursor(3, 1)
  screen.write_string("Some text")
  screen.move_cursor(3, 1)
  screen.clear_line()
  @debug.debug_inspect(
    screen.get_row_trimmed(3),
    content=(
      #|""
    ),
  )
}

///|
test "VirtualScreen::clear_display clears all" {
  let screen = VirtualScreen::new(20, 5)
  screen.move_cursor(1, 1)
  screen.write_string("Row 1")
  screen.move_cursor(2, 1)
  screen.write_string("Row 2")
  screen.clear_display()
  @debug.debug_inspect(
    screen.content_trimmed(),
    content=(
      #|""
    ),
  )
}

///|
test "VirtualScreen::contains finds text" {
  let screen = VirtualScreen::new(40, 10)
  screen.move_cursor(5, 1)
  screen.write_string("Find me here")
  @debug.debug_inspect(screen.contains("Find me"), content="true")
  @debug.debug_inspect(screen.contains("not here"), content="false")
}

///|
test "VirtualScreen::row_contains checks specific row" {
  let screen = VirtualScreen::new(40, 10)
  screen.move_cursor(3, 1)
  screen.write_string("Status: idle")
  @debug.debug_inspect(screen.row_contains(3, "idle"), content="true")
  @debug.debug_inspect(screen.row_contains(1, "idle"), content="false")
}

///|
test "VirtualScreen::find_row returns correct row" {
  let screen = VirtualScreen::new(40, 10)
  screen.move_cursor(4, 1)
  screen.write_string("Target line")
  @debug.debug_inspect(screen.find_row("Target"), content="4")
  @debug.debug_inspect(screen.find_row("Missing"), content="0")
}

///|
test "VirtualScreen::render_status_text renders at row 1" {
  let screen = VirtualScreen::new(40, 10)
  screen.render_status_text("Status: OK")
  @debug.debug_inspect(
    screen.get_row_trimmed(1),
    content=(
      #|"Status: OK"
    ),
  )
}

///|
test "VirtualScreen::render_input_area renders border and content" {
  let screen = VirtualScreen::new(40, 10)
  screen.render_input_area(["hello world"])
  // Input area is at bottom 4 rows (rows 7-10)
  @debug.debug_inspect(screen.row_contains(7, "Input"), content="true")
  @debug.debug_inspect(screen.row_contains(8, "hello world"), content="true")
  @debug.debug_inspect(screen.row_contains(10, "└"), content="true")
}

///|
test "VirtualScreen::render_output_lines renders messages" {
  let screen = VirtualScreen::new(40, 10)
  screen.render_output_lines(["Message 1", "Message 2"], 2, 4)
  @debug.debug_inspect(
    screen.get_row_trimmed(2),
    content=(
      #|"Message 1"
    ),
  )
  @debug.debug_inspect(
    screen.get_row_trimmed(3),
    content=(
      #|"Message 2"
    ),
  )
}

///|
test "VirtualScreen::get_region extracts sub-area" {
  let screen = VirtualScreen::new(40, 10)
  screen.move_cursor(2, 5)
  screen.write_string("ABCDEF")
  let region = screen.get_region(2, 5, 2, 8)
  @debug.debug_inspect(
    region,
    content=(
      #|"ABCD"
    ),
  )
}

///|
test "VirtualScreen::content includes all rows" {
  let screen = VirtualScreen::new(20, 3)
  screen.move_cursor(1, 1)
  screen.write_string("A")
  screen.move_cursor(2, 1)
  screen.write_string("B")
  screen.move_cursor(3, 1)
  screen.write_string("C")
  let content = screen.content()
  @debug.debug_inspect(content.contains("A"), content="true")
  @debug.debug_inspect(content.contains("B"), content="true")
  @debug.debug_inspect(content.contains("C"), content="true")
}

///|
test "VirtualScreen::write_string truncates at right edge" {
  let screen = VirtualScreen::new(5, 3)
  screen.move_cursor(1, 1)
  screen.write_string("Hello World!") // Longer than width
  @debug.debug_inspect(
    screen.get_row_trimmed(1),
    content=(
      #|"Hello"
    ),
  )
}
