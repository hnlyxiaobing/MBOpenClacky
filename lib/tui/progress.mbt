///|
/// Spinner animation for indicating background activity.
///
/// Implements a functional-style spinner that cycles through animation
/// frames. Each call to next_frame returns the rendered output and a
/// new Spinner state (immutable update pattern).

///|
/// Available spinner animation styles.
pub(all) enum SpinnerStyle {
  /// Braille dots: ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏
  Dots
  /// Line: -\|/
  Line
  /// Arrow: ←↖↑↗→↘↓↙
  Arrow
} derive(Eq, Debug)

///|
/// A spinner animation state (immutable).
pub(all) struct Spinner {
  frames : Array[String]
  interval_ms : Int
  current_frame : Int
  message : String
} derive(Eq, Debug)

///|
/// Create a new Spinner with the given style and message.
pub fn Spinner::new(style : SpinnerStyle, message : String) -> Spinner {
  let frames : Array[String] = match style {
    Dots =>
      ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    Line => ["-", "\\", "|", "/"]
    Arrow => ["←", "↖", "↑", "↗", "→", "↘", "↓", "↙"]
  }
  let interval_ms = match style {
    Dots => 80
    Line => 120
    Arrow => 100
  }
  { frames, interval_ms, current_frame: 0, message }
}

///|
/// Advance to the next frame, returning the rendered string and new state.
///
/// This is a pure functional update — the original Spinner is not modified.
pub fn Spinner::next_frame(self : Spinner) -> (String, Spinner) {
  let rendered = self.render_frame()
  let next_idx = (self.current_frame + 1) % self.frames.length()
  let new_spinner : Spinner = {
    frames: self.frames,
    interval_ms: self.interval_ms,
    current_frame: next_idx,
    message: self.message,
  }
  (rendered, new_spinner)
}

///|
/// Render the current frame as a formatted string: "[frame] message".
pub fn Spinner::render_frame(self : Spinner) -> String {
  let frame = self.frames[self.current_frame]
  "\{frame} \{self.message}"
}
