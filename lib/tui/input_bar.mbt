///|
/// Input bar component — text input + submit/quit buttons.
///
/// Provides a text input field for user messages and buttons
/// to submit the message or quit the TUI.

///|
/// Build the input bar view with text input and action buttons.
///
/// Parameters:
/// - `input_ref`: shared Ref[String] for the TextInput widget
/// - `on_submit`: callback when the user submits a message
/// - `on_quit`: callback when the user quits
pub fn input_bar_render(
  input_ref : Ref[String],
  on_submit : () -> Unit,
  on_quit : () -> Unit,
) -> @view.View {
  let input = @widget.TextInput::new(input_ref)
    .placeholder("Type a message and press Enter or Submit...")
    .width(60.0)

  let submit_btn = @widget.Button::primary(" Submit ", on_submit)
  let quit_btn = @widget.Button::secondary(" Quit ", on_quit)

  @view.View::container_views([
    @widget.row([
      input,
      @widget.Text::new("  "),
      submit_btn,
      @widget.Text::new("  "),
      quit_btn,
    ]),
  ])
  .padding(1.0)
  .background(@tui_core.RGB(0.12, 0.12, 0.17))
}
