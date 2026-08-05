///|
/// Tests for the controller-level command suggestion / input history /
/// progress band glue (P1-2, P1-3, P2-2).
///
/// The TuiController itself needs a live Tty + Agent and is impractical to
/// instantiate in tests, so the decision logic is extracted into small
/// package-private functions tested here.

///|
test "arrow keys navigate suggestions when the dropdown is active" {
  match arrow_key_action(true, 1) {
    NavigateSuggestions => ()
    _ => fail("expected NavigateSuggestions")
  }
  // Multi-line input does not change this — the dropdown wins
  match arrow_key_action(true, 3) {
    NavigateSuggestions => ()
    _ => fail("expected NavigateSuggestions")
  }
}

///|
test "arrow keys browse history in single-line mode without suggestions" {
  match arrow_key_action(false, 1) {
    BrowseHistory => ()
    _ => fail("expected BrowseHistory")
  }
  match arrow_key_action(false, 0) {
    BrowseHistory => ()
    _ => fail("expected BrowseHistory for empty input")
  }
}

///|
test "arrow keys move the cursor in multi-line mode" {
  match arrow_key_action(false, 2) {
    MoveCursor => ()
    _ => fail("expected MoveCursor")
  }
}

///|
test "suggestions only track single-line slash-prefixed input" {
  assert_true(should_show_suggestions("/", 1))
  assert_true(should_show_suggestions("/he", 1))
  assert_false(should_show_suggestions("hello", 1))
  assert_false(should_show_suggestions("", 1))
  // Multi-line input never triggers the dropdown
  assert_false(should_show_suggestions("/he", 2))
}

///|
test "suggestion list is built from the registered slash commands" {
  let suggestions = build_command_suggestions()
  // Every parser command (including the newer /theme) must be present
  // in the dropdown
  let parser = SlashCommandParser::new()
  for cmd in parser.commands {
    suggestions.update_filter("/\{cmd.name}")
    assert_true(
      suggestions.filtered.iter().any(fn(item) { item.name == "/\{cmd.name}" }),
    )
  }
}

///|
test "suggestion filter navigates and accepts a completion" {
  let suggestions = build_command_suggestions()
  suggestions.update_filter("/th")
  assert_eq(suggestions.result_count(), 1)
  assert_true(suggestions.is_visible())
  assert_eq(suggestions.accept(), Some("/theme"))
  // Narrowing to no match hides the dropdown
  suggestions.update_filter("/zzz")
  assert_false(suggestions.is_visible())
  // Non-slash input hides the dropdown
  suggestions.update_filter("hello")
  assert_false(suggestions.is_visible())
}

///|
test "submitted input lands in history and is recalled by prev_history" {
  let input = InputArea::multiline_new()
  input.set_text("first message")
  ignore(input.submit())
  input.set_text("second message")
  ignore(input.submit())
  assert_true(input.is_empty())
  input.prev_history()
  assert_eq(input.text(), "second message")
  input.prev_history()
  assert_eq(input.text(), "first message")
  input.next_history()
  assert_eq(input.text(), "second message")
}

///|
test "band_rows stacks the dropdown directly above the input box" {
  // 24-row screen, 4-row input box whose top border sits on row 21
  assert_eq(_band_rows(24, 4, 0, 3), [18, 19, 20])
  // A single-line dropdown touches the input top border
  assert_eq(_band_rows(24, 4, 0, 1), [20])
  // Empty band produces no rows
  assert_eq(_band_rows(24, 4, 0, 0), [])
}

///|
test "band_rows places progress lines above the todo area" {
  // Todo area occupies rows [18, 19] (gap 1 keeps row 20 free above input)
  // so a single progress line goes to row 17
  assert_eq(_band_rows(24, 4, 1 + 2, 1), [17])
  // Without a todo area the progress line sits just above the free row
  assert_eq(_band_rows(24, 4, 1, 1), [19])
}

///|
test "progress stack render feeds the band and empties after close" {
  let stack = ProgressStack::new()
  assert_eq(stack.render(), [])
  let handle = stack.push("Thinking...")
  let lines = stack.render()
  assert_eq(lines.length(), 1)
  assert_true(lines[0].contains("Thinking..."))
  handle.close()
  // After close_last()/close() the band must be empty so it gets erased
  assert_eq(stack.render(), [])
}

///|
/// SPEC-03 regression: accepting a slash-command suggestion must submit it in
/// the same Enter keystroke (single-Enter execution). Every registered command
/// suggestion is a complete "/name", so each one is immediately executable.
test "accepted slash-command suggestion submits immediately (SPEC-03)" {
  // Complete slash commands → submit.
  assert_true(should_submit_accepted_suggestion("/help"))
  assert_true(should_submit_accepted_suggestion("/config"))
  assert_true(should_submit_accepted_suggestion("/theme"))
  assert_true(should_submit_accepted_suggestion("/clear"))
  // Future non-command completions (argument values) stay complete-only.
  assert_false(should_submit_accepted_suggestion("hacker"))
  assert_false(should_submit_accepted_suggestion("default"))
  assert_false(should_submit_accepted_suggestion(""))
}

///|
/// SPEC-03 end-to-end glue: the dropdown's accepted value for any registered
/// command is a complete slash command that the Enter handler will submit.
test "every dropdown acceptance yields a submittable command (SPEC-03)" {
  let suggestions = build_command_suggestions()
  let parser = SlashCommandParser::new()
  for cmd in parser.commands {
    suggestions.update_filter("/\{cmd.name}")
    match suggestions.accept() {
      Some(accepted) => {
        assert_eq(accepted, "/\{cmd.name}")
        assert_true(should_submit_accepted_suggestion(accepted))
      }
      None => fail("expected a suggestion for /\{cmd.name}")
    }
  }
}
