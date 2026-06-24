///|
/// Tests for Banner rendering.

///|
test "Banner::new defaults" {
  let banner = Banner::new()
  assert_eq(banner.style, Boxed)
  assert_eq(banner.width, 60)
  assert_eq(banner.use_color, false)
}

///|
test "Banner::with_style creates correct style" {
  let banner = Banner::with_style(Minimal)
  assert_eq(banner.style, Minimal)
  assert_eq(banner.width, 60)
}

///|
test "Banner::render_separator width for Boxed" {
  let banner = Banner::new()
  let sep = banner.render_separator()
  // Boxed separator uses width-2 = 58 '═' chars
  assert_eq(sep.length(), 58)
  assert_true(sep.contains("═"))
}

///|
test "Banner::render_separator width for Minimal" {
  let banner = Banner::with_style(Minimal)
  let sep = banner.render_separator()
  // Minimal separator uses full width = 60 '─' chars
  assert_eq(sep.length(), 60)
  assert_true(sep.contains("─"))
}

///|
test "Banner::render_simple contains title" {
  let banner = Banner::with_style(Minimal)
  let output = banner.render_simple("Hello World", None)
  assert_true(output.contains("Hello World"))
  assert_true(output.contains("─"))
}

///|
test "Banner::render_simple with subtitle" {
  let banner = Banner::with_style(Minimal)
  let output = banner.render_simple("Title", Some("Sub"))
  assert_true(output.contains("Title"))
  assert_true(output.contains("Sub"))
}

///|
test "Banner::render_boxed contains box characters" {
  let banner = Banner::new()
  let output = banner.render_boxed("Test", None)
  assert_true(output.contains("╔"))
  assert_true(output.contains("╗"))
  assert_true(output.contains("╚"))
  assert_true(output.contains("╝"))
  assert_true(output.contains("═"))
  assert_true(output.contains("║"))
  assert_true(output.contains("Test"))
}

///|
test "Banner::render_boxed with subtitle" {
  let banner = Banner::new()
  let output = banner.render_boxed("Main", Some("Extra"))
  assert_true(output.contains("Main"))
  assert_true(output.contains("Extra"))
}

///|
test "Banner::render dispatches by style" {
  let boxed = Banner::with_style(Boxed)
  let out1 = boxed.render("Hi", None)
  assert_true(out1.contains("╔"))

  let minimal = Banner::with_style(Minimal)
  let out2 = minimal.render("Hi", None)
  assert_true(out2.contains("─"))

  let block = Banner::with_style(Block)
  let out3 = block.render("HI", None)
  // Block style uses block font chars
  assert_true(out3.contains("█"))
}

///|
test "Banner::render_separator with color" {
  let banner = { style: Minimal, width: 20, use_color: true }
  let sep = banner.render_separator()
  assert_true(sep.contains("\u{1b}[36m"))
  assert_true(sep.contains("\u{1b}[0m"))
}
