///|
/// Regression tests for SPEC-01: the top status bar must render fully.
///
/// Root cause (verified empirically): the layout hardcoded `width=100.0`,
/// which the mizchi/tui DSL interprets as `DimensionValue::Length(100)` —
/// i.e. 100 *absolute columns*, NOT 100%. The ~118-column status bar overflowed
/// the 100-column row, and the flexbox engine shrank each text node toward its
/// min-content width (the longest word, computed by splitting on spaces in
/// `text_measure_func`). Space-containing segments ("● idle", "0 tasks",
/// "0 calls", "0 iters") therefore shrank and were truncated to their longest
/// word, while space-free segments ("s_178524", "$0.0000", …) have
/// min_width == max_width and could not shrink, so they stayed full.
///
/// The fix threads the real terminal width through the layout builders so the
/// status bar row is as wide as the terminal and never overflows/shrinks.

///|
/// Build a representative multi-segment ANSI status string matching the format
/// produced by `StatusBar::colored_text` (several segments contain spaces,
/// which is exactly what triggered the truncation).
fn sample_status_text() -> String {
  let green = "\u{1b}[1m\u{1b}[38;2;0;255;100m"
  let cyan = "\u{1b}[38;2;0;200;255m"
  let white = "\u{1b}[38;2;220;220;220m"
  let yellow = "\u{1b}[38;2;255;255;85m"
  let magenta = "\u{1b}[38;2;200;100;255m"
  let reset = "\u{1b}[0m"
  let sep = " │ "
  green +
  "● idle" +
  reset +
  sep +
  cyan +
  "s_178524" +
  reset +
  sep +
  white +
  "/mnt/d/MoonBit/MBOpenClacky" +
  reset +
  sep +
  yellow +
  "confirm_safes" +
  reset +
  sep +
  magenta +
  "qwen3.7-plus" +
  reset +
  sep +
  white +
  "0 tasks" +
  reset +
  sep +
  white +
  "0 calls" +
  reset +
  sep +
  white +
  "0 iters" +
  reset +
  sep +
  green +
  "$0.0000" +
  reset
}

///|
/// Render the status bar through the real layout + vnode render pipeline and
/// return the rendered frame with ANSI codes stripped.
fn render_status_frame(term_width : Int) -> String {
  let w = term_width.to_double()
  let status_node = ansi_line_to_vnode_sized(sample_status_text(), w, 1.0)
  let layout = build_main_layout(
    status_node,
    [@vnode.text("body")],
    [],
    [separator_node(term_width), @vnode.text("> ")],
    w,
  )
  let app = @vnode.VNodeApp::new(term_width, 45)
  strip_ansi(app.render_frame(layout))
}

///|
/// SPEC-01 regression: at a wide terminal (150 cols) every status field must
/// render in full — no tail truncation of the space-containing segments and
/// separators intact. With the old hardcoded 100-col row this failed: the line
/// came back as "● id … 0 tas | 0 cal 0 ite …".
test "status bar renders fully at terminal width (SPEC-01)" {
  let frame = render_status_frame(150)
  // Space-containing segments were previously truncated to their longest word.
  @debug.assert_eq(frame.contains("● idle"), true)
  @debug.assert_eq(frame.contains("0 tasks"), true)
  @debug.assert_eq(frame.contains("0 calls"), true)
  @debug.assert_eq(frame.contains("0 iters"), true)
  // Space-free segments and the tail must also be intact.
  @debug.assert_eq(frame.contains("s_178524"), true)
  @debug.assert_eq(frame.contains("qwen3.7-plus"), true)
  @debug.assert_eq(frame.contains("$0.0000"), true)
  // Separators must survive (some were dropped entirely before the fix).
  @debug.assert_eq(frame.contains(" │ "), true)
}

///|
/// Build a test TuiState with realistic field values for SPEC-07 tests.
fn make_test_state_for_adaptive() -> TuiState {
  {
    session_id: "s_178524",
    model_name: "qwen3.7-plus",
    mode: Idle,
    agent_status: @mizchi/signals.signal("idle"),
    iterations: 0,
    working_dir: "/mnt/d/MoonBit/MBOpenClacky",
    permission_mode: "confirm_safes",
    active_tasks: 0,
    messages: [],
    streaming_buffer: @mizchi/signals.signal(""),
    streaming_active: @mizchi/signals.signal(false),
    tool_output: @mizchi/signals.signal(""),
    current_tool_name: "",
    current_tool_args: "",
    tool_history: [],
    llm_call_count: 0,
    llm_calling: false,
    phase_stack: [],
    total_cost: 0.0,
    cost_source: "estimated",
    latest_delta: 0,
    last_input_tokens: 0,
    last_output_tokens: 0,
    input_text: "",
    last_error: None,
    progress_stack: ProgressStack::new(),
    todo_area: TodoArea::new(),
    pending_confirmation: None,
    theme: Theme::default_(),
    dialog: DialogState::NoDialog,
    thinking_buffer: @mizchi/signals.signal(""),
    tick_count: 0,
    run_start_ts: 0L,
    total_iterations: 0,
    approved_all_tools: false,
    time_machine: @agent.TimeMachineState::new("test"),
    paste_placeholder_count: 0,
    paste_placeholders: [],
  }
}

///|
/// SPEC-07 regression: at 150 cols all 7 fields must be present.
test "adaptive status bar shows all fields at 150 cols (SPEC-07)" {
  let state = make_test_state_for_adaptive()
  let bar = StatusBar::new()
  bar.format_from_state_adaptive(state, 150)
  let text = bar.plain_text()
  assert_true(text.contains("● idle"))
  assert_true(text.contains("s_178524"))
  assert_true(text.contains("confirm_safes"))
  assert_true(text.contains("qwen3.7-plus"))
  assert_true(text.contains("0 tasks"))
  assert_true(text.contains("$0.0"))
  // All 6 separators present.
  assert_eq(bar.segment_count(), 13) // 7 fields + 6 separators
}

///|
/// SPEC-07 regression: at 80 cols critical fields must survive.
test "adaptive status bar keeps critical fields at 80 cols (SPEC-07)" {
  let state = make_test_state_for_adaptive()
  let bar = StatusBar::new()
  bar.format_from_state_adaptive(state, 80)
  let text = bar.plain_text()
  // Critical fields: status, model, cost.
  assert_true(text.contains("● idle"))
  assert_true(text.contains("qwen3.7-plus"))
  assert_true(text.contains("$0.0"))
  // Does not exceed 80 display columns.
  assert_true(display_width(text) <= 80)
}

///|
/// SPEC-07 regression: at 60 cols at least status + cost survive.
test "adaptive status bar degrades gracefully at 60 cols (SPEC-07)" {
  let state = make_test_state_for_adaptive()
  let bar = StatusBar::new()
  bar.format_from_state_adaptive(state, 60)
  let text = bar.plain_text()
  assert_true(text.contains("● idle"))
  assert_true(text.contains("$0.0"))
  assert_true(display_width(text) <= 60)
}

///|
/// SPEC-07 regression: directory is compressed but not dropped at 100 cols.
test "adaptive status bar compresses directory at 100 cols (SPEC-07)" {
  let state = make_test_state_for_adaptive()
  let bar = StatusBar::new()
  bar.format_from_state_adaptive(state, 100)
  let text = bar.plain_text()
  // Directory should be present (possibly compressed).
  assert_true(text.contains("MoonBit") || text.contains("..."))
  assert_true(text.contains("● idle"))
  assert_true(text.contains("$0.0"))
  assert_true(display_width(text) <= 100)
}
