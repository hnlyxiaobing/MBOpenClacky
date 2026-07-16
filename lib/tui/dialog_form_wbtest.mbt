///|
/// Tests for FormDialog rendering, input, and validation.
fn make_test_form() -> FormDialog {
  let fields = [
    ("Name", true, "Enter your name"),
    ("Email", false, "optional@email.com"),
    ("Description", true, "Describe..."),
  ]
  FormDialog::new("Test Form", fields)
}

///|
test "form: new dialog starts at field index 0" {
  let f = make_test_form()
  @debug.assert_eq(f.focused_idx, 0)
  @debug.assert_eq(f.fields.length(), 3)
}

///|
test "form: next_field cycles through fields" {
  let f = make_test_form()
  f.next_field()
  @debug.assert_eq(f.focused_idx, 1)
  f.next_field()
  @debug.assert_eq(f.focused_idx, 2)
  f.next_field()
  @debug.assert_eq(f.focused_idx, 0)
}

///|
test "form: prev_field wraps around" {
  let f = make_test_form()
  f.prev_field()
  @debug.assert_eq(f.focused_idx, 2)
}

///|
test "form: input_char appends to focused field" {
  let f = make_test_form()
  f.input_char('H')
  f.input_char('i')
  @debug.assert_eq(f.fields[0].value, "Hi")
}

///|
test "form: input_char to non-focused field does nothing" {
  let f = make_test_form()
  f.next_field()
  f.input_char('X')
  @debug.assert_eq(f.fields[0].value, "")
  @debug.assert_eq(f.fields[1].value, "X")
}

///|
test "form: backspace removes last character" {
  let f = make_test_form()
  f.input_char('A')
  f.input_char('B')
  f.backspace()
  @debug.assert_eq(f.fields[0].value, "A")
}

///|
test "form: backspace on empty does nothing" {
  let f = make_test_form()
  f.backspace()
  @debug.assert_eq(f.fields[0].value, "")
}

///|
test "form: validate fails on empty required field" {
  let f = make_test_form()
  let err = f.validate()
  assert_true(err is Some(_))
}

///|
test "form: validate passes when required fields filled" {
  let f = make_test_form()
  f.input_char('X')
  f.next_field()
  f.next_field()
  f.input_char('Y')
  let err = f.validate()
  assert_true(err is None)
}

///|
test "form: collect_values returns all field data" {
  let f = make_test_form()
  f.input_char('J')
  f.next_field()
  f.input_char('D')
  let vals = f.collect_values()
  @debug.assert_eq(vals.length(), 3)
  @debug.assert_eq(vals[0].0, "Name")
  @debug.assert_eq(vals[0].1, "J")
}

///|
test "form: render produces Border node with title" {
  let f = make_test_form()
  let node = render_form_dialog(f)
  let text = node_to_text(node)
  assert_true(text.contains("Test Form"))
  assert_true(text.contains("Name"))
  assert_true(text.contains("Email"))
}
