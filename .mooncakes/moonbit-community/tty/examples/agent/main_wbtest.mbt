///|
test "editor starts at end and keeps cursor visible" {
  let editor = Editor::from_text("a\nb\nc")
  let point = editor.cursor_point()
  @debug.debug_inspect(point.line, content="2")
  @debug.debug_inspect(point.grapheme_column, content="1")
  @debug.debug_inspect(point.display_column, content="1")
  @debug.debug_inspect(editor.view_start, content="1")
  @debug.debug_inspect(editor_cursor_row(editor), content="1")
}

///|
test "editor up down moves cursor and scrolls viewport" {
  let bottom = Editor::from_text("one\ntwo\nthree")
  @debug.debug_inspect(bottom.cursor_point().line, content="2")
  @debug.debug_inspect(bottom.view_start, content="1")
  let up1 = bottom.move_vertical(-1)
  @debug.debug_inspect(up1.cursor_point().line, content="1")
  @debug.debug_inspect(up1.cursor_point().display_column, content="3")
  @debug.debug_inspect(up1.view_start, content="1")
  let up2 = up1.move_vertical(-1)
  @debug.debug_inspect(up2.cursor_point().line, content="0")
  @debug.debug_inspect(up2.cursor_point().display_column, content="3")
  @debug.debug_inspect(up2.view_start, content="0")
  let down1 = up2.move_vertical(1)
  @debug.debug_inspect(down1.cursor_point().line, content="1")
  @debug.debug_inspect(down1.view_start, content="0")
  let down2 = down1.move_vertical(1)
  @debug.debug_inspect(down2.cursor_point().line, content="2")
  @debug.debug_inspect(down2.view_start, content="1")
}

///|
test "editor inserts and deletes at cursor" {
  let inserted = Editor::from_text("ab").move_left().insert("X")
  @debug.debug_inspect(inserted.text, content="aXb")
  @debug.debug_inspect(inserted.cursor, content="2")
  let deleted_before = Editor::from_text("a👨‍👩‍👧‍👦b")
    .move_left()
    .delete_before()
  @debug.debug_inspect(deleted_before.text, content="ab")
  @debug.debug_inspect(deleted_before.cursor_point().display_column, content="1")
  let deleted_after = Editor::from_text("ab").move_home().delete_after()
  @debug.debug_inspect(deleted_after.text, content="b")
  @debug.debug_inspect(deleted_after.cursor, content="0")
}

///|
test "editor shell mode keeps marker out of text" {
  let shell = Editor::new().insert_user_text("!echo hi")
  assert_true(shell.shell_mode)
  @debug.debug_inspect(shell.text, content="echo hi")
  @debug.debug_inspect(shell.cursor, content="7")
  let normal = Editor::new().insert_user_text("!").delete_before()
  assert_false(normal.shell_mode)
  @debug.debug_inspect(normal.text, content="")
}

///|
test "editor home end moves within logical line" {
  let editor = Editor::from_text("ab\ncd")
  let home = editor.move_home()
  @debug.debug_inspect(home.cursor_point().line, content="1")
  @debug.debug_inspect(home.cursor_point().display_column, content="0")
  let end = home.move_end()
  @debug.debug_inspect(end.cursor_point().line, content="1")
  @debug.debug_inspect(end.cursor_point().display_column, content="2")
}

///|
test "input prefix marks only the first logical input line" {
  @debug.debug_inspect(input_prefix(0, 0), content="> ")
  @debug.debug_inspect(input_prefix(0, 0, shell_mode=true), content="! ")
  @debug.debug_inspect(input_prefix(1, 0), content="  ")
  @debug.debug_inspect(input_prefix(0, 1), content="  ")
  @debug.debug_inspect(input_prefix(0, 1, shell_mode=true), content="  ")
}

///|
test "input cursor offset accounts for prompt and display width" {
  @debug.debug_inspect(input_cursor_offset(Editor::new(), 80), content="2")
  @debug.debug_inspect(input_cursor_offset(Editor::from_text("abc"), 80), content="5")
  @debug.debug_inspect(input_cursor_offset(Editor::from_text("你好"), 80), content="6")
  @debug.debug_inspect(
    input_cursor_offset(Editor::from_text("abc").move_left(), 80),
    content="4",
  )
  @debug.debug_inspect(input_cursor_offset(Editor::from_text("a\nb"), 80), content="3")
  @debug.debug_inspect(input_cursor_offset(Editor::from_text("abcdef"), 5), content="5")
  @debug.debug_inspect(
    input_cursor_offset(Editor::new().insert_user_text("!abc"), 80),
    content="5",
  )
}

///|
test "viewport top derives from probed cursor row" {
  @debug.debug_inspect(viewport_top_from_cursor(4, Editor::new()), content="3")
  @debug.debug_inspect(viewport_top_from_cursor(5, Editor::from_text("a\nb")), content="3")
  @debug.debug_inspect(viewport_top_from_cursor(1, Editor::new()), content="1")
}

///|
test "viewport top clamps to visible terminal rows" {
  let size : AgentSize = { rows: 8, cols: 80 }
  @debug.debug_inspect(max_viewport_top(size), content="5")
  @debug.debug_inspect(clamp_viewport_top(1, size), content="1")
  @debug.debug_inspect(clamp_viewport_top(9, size), content="5")
  @debug.debug_inspect(viewport_bottom(5), content="8")
}

///|
test "fit line respects display width and graphemes" {
  @debug.debug_inspect(fit_line("abcdef", 3), content="abc")
  @debug.debug_inspect(fit_line("你好世界", 4), content="你好")
  @debug.debug_inspect(
    fit_line("x👨‍👩‍👧‍👦y", 3),
    content="x👨‍👩‍👧‍👦",
  )
}

///|
test "split input lines keeps trailing input row" {
  @debug.debug_inspect(split_input_lines("a\nb\n").join("|"), content="a|b|")
}

///|
test "fake response echoes input" {
  @debug.debug_inspect(fake_response("hello"), content="received: hello")
  @debug.debug_inspect(fake_response("hello\nworld"), content="received: hello / world")
}

///|
test "shell command text trims command" {
  @debug.debug_inspect(shell_command_text(" echo hi"), content="echo hi")
  @debug.debug_inspect(shell_command_text(""), content="")
}

///|
test "format shell result includes command and exit code" {
  @debug.debug_inspect(format_shell_result("echo hi", 0, "hi\n"), content="$ echo hi\nhi")
  @debug.debug_inspect(
    format_shell_result("bad", 2, ""),
    content="$ bad (exit 2)\n(no output)",
  )
  @debug.debug_inspect(
    format_shell_result("", 1, "empty shell command"),
    content="$ <empty command> (exit 1)\nempty shell command",
  )
}

///|
test "text from key ignores modified control keys" {
  let text = text_from_key(@tty/input.KeyEvent::new(Char('x'), text="x"))
  assert_true(text == Some("x"))
  assert_true(
    text_from_key(
      @tty/input.KeyEvent::new(
        Char('c'),
        modifiers=@tty/input.KeyModifiers::new(ctrl=true),
      ),
    ) ==
    None,
  )
}

///|
test "ctrl j is newline key" {
  assert_true(
    is_newline_key(
      @tty/input.KeyEvent::new(
        Char('j'),
        modifiers=@tty/input.KeyModifiers::new(ctrl=true),
      ),
    ),
  )
  assert_false(is_newline_key(@tty/input.KeyEvent::new(Enter)))
}

///|
test "exit newline count leaves below composer" {
  @debug.debug_inspect(exit_newline_count(Editor::new()), content="3")
  @debug.debug_inspect(exit_newline_count(Editor::from_text("a\nb")), content="2")
}
