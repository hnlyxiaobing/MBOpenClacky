///|
/// Adversarial layout-correctness tests.
///
/// These tests bypass the terminal entirely: they build the same kind of View
/// tree the TUI produces, run it through the real Yoga layout engine at a fixed
/// "terminal" size, and then assert the computed coordinates are SANE.
///
/// The bug we are guarding against ("flex collapse") manifests as every node
/// collapsing to width/height 0 at position (0,0) — everything drawn on top of
/// everything else. If the root fills the available space and the three stacked
/// regions (content / status / footer) get distinct, non-overlapping vertical
/// bands, the layout is healthy.

///|
/// Build a representative 3-region column layout the same way build_main_layout
/// does: a flex content region, a fixed-ish status line, and a footer.
fn make_test_layout() -> @view.View {
  let content = @view.View::container_views([
    @view.View::text("message one"),
    @view.View::text("message two"),
  ])
  let status = @view.View::text("● idle | session | dir | model | 0 tasks | $0.0")
  let footer = @view.View::text("> type here")
  @view.View::container_views([content.flex(1.0).flex_basis(0.0), status, footer])
  .direction(@view.Direction::Column)
  .width(100.0)
  .height(40.0)
}

///|
test "layout: root fills the available terminal space (no flex collapse)" {
  let root = make_test_layout()
  let node = @layout.calculate_layout(root, 100.0, 40.0)
  let w = node.layout_width().to_int()
  let h = node.layout_height().to_int()
  // Root must occupy the full 100x40, not collapse to 0 or content size.
  assert_eq(w, 100)
  assert_eq(h, 40)
}

///|
test "layout: three regions occupy distinct non-overlapping vertical bands" {
  let root = make_test_layout()
  let node = @layout.calculate_layout(root, 100.0, 40.0)

  // Expect exactly 3 children: content, status, footer.
  assert_eq(node.get_child_count(), 3)

  let content = node.get_child(0).unwrap()
  let status = node.get_child(1).unwrap()
  let footer = node.get_child(2).unwrap()

  let content_top = content.layout_top().to_int()
  let content_h = content.layout_height().to_int()
  let status_top = status.layout_top().to_int()
  let status_h = status.layout_height().to_int()
  let footer_top = footer.layout_top().to_int()
  println(
    "DEBUG bands: root_h=\{node.layout_height().to_int()} content(top=\{content_top},h=\{content_h}) status(top=\{status_top},h=\{status_h}) footer(top=\{footer_top})",
  )

  // Content starts at the top.
  assert_eq(content_top, 0)
  // The flex content region must actually grow (this is the collapse guard):
  // it should take the lion's share of the 40-row height.
  assert_true(content_h > 30)
  // Status must sit strictly below the content region (no overlap at (0,0)).
  assert_eq(status_top, content_top + content_h)
  // Footer must sit strictly below the status line.
  assert_eq(footer_top, status_top + status_h)
  // Footer must stay on-screen.
  assert_true(footer_top < 40)
}

///|
test "layout: message_view_render produces a non-collapsed bordered box" {
  let agent = make_test_agent()
  let state = Ref::new(TuiState::from_agent(agent))
  state.val.messages.push("[user] hello")
  state.val.messages.push("[assistant] hi there")
  let view = message_view_render(state)
  // Wrap in a full-screen root so percent/flex resolve against a real size.
  let root = @view.View::container_views([view.flex(1.0)])
    .direction(@view.Direction::Column)
    .width_percent(100.0)
    .height_percent(100.0)
  let node = @layout.calculate_layout(root, 120.0, 50.0)
  let child = node.get_child(0).unwrap()
  let cw = child.layout_width().to_int()
  let ch = child.layout_height().to_int()
  // The message box must have real dimensions, not (0,0).
  assert_true(cw > 10)
  assert_true(ch > 3)
}
