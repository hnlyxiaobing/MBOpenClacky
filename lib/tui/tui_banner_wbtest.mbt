///|
/// Tests for Banner rendering.

///|
test "Banner::new defaults" {
  let banner = Banner::new()
  @debug.assert_eq(banner.style, Boxed)
  @debug.assert_eq(banner.width, 60)
  @debug.assert_eq(banner.use_color, false)
}

///|
test "Banner::with_style creates correct style" {
  let banner = Banner::with_style(Minimal)
  @debug.assert_eq(banner.style, Minimal)
  @debug.assert_eq(banner.width, 60)
}

///|
test "Banner::with_width creates correct width" {
  let banner = Banner::with_width(40)
  @debug.assert_eq(banner.style, Boxed)
  @debug.assert_eq(banner.width, 40)
  @debug.assert_eq(banner.use_color, false)
}

///|
test "Banner::with_style_and_width creates correct style and width" {
  let banner = Banner::with_style_and_width(Minimal, 80)
  @debug.assert_eq(banner.style, Minimal)
  @debug.assert_eq(banner.width, 80)
}

///|
test "Banner::adaptive_width clamps correctly" {
  // Small terminal: (30 - 4) = 26, within range
  @debug.assert_eq(Banner::adaptive_width(30), 26)
  // Very small terminal: (10 - 4) = 6, clamped to 20
  @debug.assert_eq(Banner::adaptive_width(10), 20)
  // Large terminal: (200 - 4) = 196, clamped to 60
  @debug.assert_eq(Banner::adaptive_width(200), 60)
  // Standard 80-column terminal: (80 - 4) = 76, clamped to 60
  @debug.assert_eq(Banner::adaptive_width(80), 60)
  // Exact boundary: 64 - 4 = 60, should be 60
  @debug.assert_eq(Banner::adaptive_width(64), 60)
}

///|
test "Banner::render_separator width for Boxed" {
  let banner = Banner::new()
  let sep = banner.render_separator()
  // Boxed separator uses width-2 = 58 '═' chars
  @debug.assert_eq(sep.length(), 58)
  assert_true(sep.contains("═"))
}

///|
test "Banner::render_separator width for Minimal" {
  let banner = Banner::with_style(Minimal)
  let sep = banner.render_separator()
  // Minimal separator uses full width = 60 '─' chars
  @debug.assert_eq(sep.length(), 60)
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
  let banner : Banner = {
    style: BannerStyle::Minimal,
    width: 20,
    use_color: true,
  }
  let sep = banner.render_separator()
  assert_true(sep.contains("\u{1b}[38;2;0;200;255m"))
  assert_true(sep.contains("\u{1b}[0m"))
}

///|
test "startup logo honours glyph density and frame" {
  let plain : Banner = {
    style: BannerStyle::Block,
    width: 60,
    use_color: false,
  }
  let plain_logo = plain.render_startup(
    "0.2.0",
    "/tmp",
    "default",
    false,
    false,
    terminal_width=120,
  )
  assert_true(plain_logo.contains("█"))
  assert_false(plain_logo.contains("░"))
}

///|
test "startup logo degrades to Minimal on a narrow terminal" {
  let banner : Banner = {
    style: BannerStyle::Block,
    width: 60,
    use_color: false,
  }
  let narrow = banner.render_startup(
    "0.2.0",
    "/tmp",
    "default",
    false,
    false,
    terminal_width=60,
  )
  assert_true(narrow.contains("Welcome, MBOpenClacky is here"))
  assert_false(narrow.contains("█"))
}
