///|
/// Progress Bar Widget - Visual progress indicator
pub struct ProgressBar {
  value : Double // 0.0 to 1.0
  mut width : Double
  mut style : ProgressStyle
  mut label : String?
}

///|
pub struct ProgressStyle {
  filled_char : String
  empty_char : String
  filled_color : @core.Color
  empty_color : @core.Color
  show_percentage : Bool
}

///|
/// Create a new progress bar
pub fn ProgressBar::new(value : Double) -> ProgressBar {
  {
    value: clamp_progress(value),
    width: 20.0,
    style: ProgressStyle::default(),
    label: None,
  }
}

///|
/// Set the width
pub fn ProgressBar::width(self : ProgressBar, w : Double) -> ProgressBar {
  self.width = w
  self
}

///|
/// Set the label
pub fn ProgressBar::label(self : ProgressBar, text : String) -> ProgressBar {
  self.label = Some(text)
  self
}

///|
/// Set custom style
pub fn ProgressBar::with_style(
  self : ProgressBar,
  style : ProgressStyle,
) -> ProgressBar {
  self.style = style
  self
}

///|
/// Default progress style
pub fn ProgressStyle::default() -> ProgressStyle {
  {
    filled_char: "█",
    empty_char: "░",
    filled_color: @core.Color::Green,
    empty_color: @core.Color::Gray,
    show_percentage: true,
  }
}

///|
/// Simple style with ASCII characters
pub fn ProgressStyle::simple() -> ProgressStyle {
  {
    filled_char: "=",
    empty_char: "-",
    filled_color: @core.Color::Cyan,
    empty_color: @core.Color::Gray,
    show_percentage: true,
  }
}

///|
/// Dots style
pub fn ProgressStyle::dots() -> ProgressStyle {
  {
    filled_char: "●",
    empty_char: "○",
    filled_color: @core.Color::Blue,
    empty_color: @core.Color::Gray,
    show_percentage: false,
  }
}

///|
/// Clamp progress value between 0 and 1
fn clamp_progress(value : Double) -> Double {
  if value < 0.0 {
    0.0
  } else if value > 1.0 {
    1.0
  } else {
    value
  }
}

///|
/// Build the progress bar string
fn build_progress_string(
  value : Double,
  width : Int,
  filled_char : String,
  empty_char : String,
) -> String {
  let filled_width = (value * width.to_double()).to_int()
  let empty_width = width - filled_width
  let mut result = ""

  // Add filled portion
  for i = 0; i < filled_width; i = i + 1 {
    result = result + filled_char
  }

  // Add empty portion
  for i = 0; i < empty_width; i = i + 1 {
    result = result + empty_char
  }
  result
}

///|
/// Implement Component trait
pub impl @view.Component for ProgressBar with render(self) {
  // Calculate actual width in characters
  let bar_width = self.width.to_int()

  // Build progress bar string
  let bar_string = build_progress_string(
    self.value,
    bar_width,
    self.style.filled_char,
    self.style.empty_char,
  )

  // Create display string with optional percentage
  let display_string = if self.style.show_percentage {
    let percentage = (self.value * 100.0).to_int()
    "\{bar_string} \{percentage}%"
  } else {
    bar_string
  }

  // Add label if present
  let final_string = match self.label {
    Some(label) => "\{label}: \{display_string}"
    None => display_string
  }

  // Create view with appropriate coloring
  // For now, use single color for the whole bar
  @view.View::text(final_string, color=self.style.filled_color).flex(1.0) // Make it flexible to fill available space
}

///|
pub impl @view.Component for ProgressBar with handle_event(_self, _event) {
  // Progress bars are display-only, no event handling
  false
}

///|
pub impl @view.Component for ProgressBar with is_focusable(_self) {
  false
}
