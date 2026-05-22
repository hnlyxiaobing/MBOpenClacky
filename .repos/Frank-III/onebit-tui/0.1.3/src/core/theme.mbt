///|
/// Simple theme palette for Views
pub(all) struct Theme {
  fg : Color
  bg : Color
  accent : Color
}

///|
pub fn Theme::light() -> Theme {
  Theme::{ fg: Color::Black, bg: Color::BrightWhite, accent: Color::Blue }
}

///|
pub fn Theme::dark() -> Theme {
  Theme::{ fg: Color::BrightWhite, bg: Color::Black, accent: Color::Cyan }
}
