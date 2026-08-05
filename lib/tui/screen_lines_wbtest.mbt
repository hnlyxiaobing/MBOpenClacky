///|
/// Invariant tests for the line-model screen composition (BUG-004 fix):
/// total rows == term_height, fixed-area order, body clipping, no
/// over-wide rows, and the Node line renderer.

///|
test "compose: total rows always equal term_height" {
  // Body smaller than the output area: padded with blank rows.
  let lines = compose_screen_lines(["a", "b"], ["s1", "s2", "s3"], 10)
  assert_eq(lines.length(), 10)
  // Fixed area occupies the bottom rows in order.
  assert_eq(lines[7], "s1")
  assert_eq(lines[8], "s2")
  assert_eq(lines[9], "s3")
  // Body is top-aligned.
  assert_eq(lines[0], "a")
  assert_eq(lines[1], "b")
  assert_eq(lines[2], "")
}

///|
test "compose: overflowing body is bottom-clipped, fixed rows stay intact" {
  let body : Array[String] = []
  for i in 1..<=20 {
    body.push("line\{i}")
  }
  let lines = compose_screen_lines(body, ["fixed"], 6)
  assert_eq(lines.length(), 6)
  // Top-aligned: the first body rows survive, the rest clip away.
  assert_eq(lines[0], "line1")
  assert_eq(lines[4], "line5")
  assert_eq(lines[5], "fixed")
}

///|
test "compose: fixed area taller than the screen keeps the bottom rows" {
  let fixed : Array[String] = []
  for i in 1..<=8 {
    fixed.push("f\{i}")
  }
  let lines = compose_screen_lines(["a"], fixed, 5)
  assert_eq(lines.length(), 5)
  // The top fixed rows are dropped; the input area at the bottom survives.
  assert_eq(lines[0], "f4")
  assert_eq(lines[4], "f8")
}

///|
test "truncate_ansi_line: CJK and ANSI lines occupy exactly one row" {
  // CJK double-width characters count as 2 columns.
  let cjk = truncate_ansi_line("你好世界", 5)
  assert_eq(ansi_display_width(cjk), 4) // 你(2) 好(2); next char won't fit
  // ANSI escape sequences pass through without consuming width.
  let styled = truncate_ansi_line("\u{1b}[31mhello world\u{1b}[0m", 5)
  assert_eq(strip_ansi(styled), "hello")
  assert_eq(ansi_display_width(styled), 5)
}

///|
test "pad_ansi_line pads to display width without touching wide lines" {
  assert_eq(pad_ansi_line("ab", 5), "ab   ")
  assert_eq(pad_ansi_line("\u{1b}[31m你好\u{1b}[0m", 6).length() > 10, true)
  let wide = pad_ansi_line("abcdefgh", 4)
  assert_eq(wide, "abcdefgh") // no truncation here — compose never widens
}

///|
test "node_to_lines: text, column, styled and border rendering" {
  // Plain text and styled text
  let t = node_to_lines(Node::Text("hello", Style::default_()))
  assert_eq(t, ["hello"])
  let st = node_to_lines(Node::Text("x", Style::new(bold=true, dim=true)))
  assert_eq(st.length(), 1)
  assert_true(st[0].contains("\u{1b}[1m"))
  assert_true(st[0].contains("\u{1b}[2m"))
  assert_true(st[0].contains("x"))
  // Column stacks children
  let col = node_to_lines(
    Node::Column([
      Node::Text("l1", Style::default_()),
      Node::Text("l2", Style::default_()),
    ]),
  )
  assert_eq(col, ["l1", "l2"])
  // Border wraps content in a rounded box sized to the content
  let bx = node_to_lines(
    Node::Border(Some("Title"), [Node::Text("body", Style::default_())]),
  )
  assert_eq(bx.length(), 3)
  assert_true(bx[0].has_prefix("╭"))
  assert_true(bx[0].contains("Title"))
  assert_true(bx[1].contains("body"))
  assert_true(bx[2].has_prefix("╰"))
  // All box rows share one display width
  assert_eq(ansi_display_width(bx[0]), ansi_display_width(bx[1]))
  assert_eq(ansi_display_width(bx[1]), ansi_display_width(bx[2]))
}
