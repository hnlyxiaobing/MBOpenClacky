///| Core color type and helpers

///|
/// Helper function to create RGB color from 0-255 values
pub fn rgb(r : Int, g : Int, b : Int) -> Color {
  Color::RGB(
    r.to_double() / 255.0,
    g.to_double() / 255.0,
    b.to_double() / 255.0,
  )
}

///|
/// Helper function to create RGBA color from 0-255 values (alpha is 0.0-1.0)  
pub fn rgba(r : Int, g : Int, b : Int, a : Double) -> Color {
  Color::RGBA(
    r.to_double() / 255.0,
    g.to_double() / 255.0,
    b.to_double() / 255.0,
    a,
  )
}

///|
pub(all) enum Color {
  Black
  Red
  Green
  Yellow
  Blue
  Magenta
  Cyan
  White
  Gray
  BrightRed
  BrightGreen
  BrightYellow
  BrightBlue
  BrightMagenta
  BrightCyan
  BrightWhite
  RGB(Double, Double, Double) // r, g, b (0.0-1.0)
  RGBA(Double, Double, Double, Double) // r, g, b, a (0.0-1.0)
}

///|
pub fn color_to_rgb(color : Color) -> (Double, Double, Double) {
  match color {
    Black => (0.0, 0.0, 0.0)
    Red => (0.7, 0.0, 0.0)
    Green => (0.0, 0.7, 0.0)
    Yellow => (0.7, 0.7, 0.0)
    Blue => (0.0, 0.0, 0.7)
    Magenta => (0.7, 0.0, 0.7)
    Cyan => (0.0, 0.7, 0.7)
    White => (0.9, 0.9, 0.9)
    Gray => (0.5, 0.5, 0.5)
    BrightRed => (1.0, 0.0, 0.0)
    BrightGreen => (0.0, 1.0, 0.0)
    BrightYellow => (1.0, 1.0, 0.0)
    BrightBlue => (0.0, 0.0, 1.0)
    BrightMagenta => (1.0, 0.0, 1.0)
    BrightCyan => (0.0, 1.0, 1.0)
    BrightWhite => (1.0, 1.0, 1.0)
    RGB(r, g, b) => (r, g, b)
    RGBA(r, g, b, _) => (r, g, b) // For now, ignore alpha in RGB conversion
  }
}

///|
/// Get RGBA values from a color (default alpha = 1.0 for non-RGBA colors)
pub fn color_to_rgba(color : Color) -> (Double, Double, Double, Double) {
  match color {
    RGBA(r, g, b, a) => (r, g, b, a)
    _ => {
      let (r, g, b) = color_to_rgb(color)
      (r, g, b, 1.0)
    }
  }
}

///|
/// Blend two colors using alpha compositing
pub fn blend_colors(foreground : Color, background : Color) -> Color {
  let (fr, fg, fb, fa) = color_to_rgba(foreground)
  let (br, bg, bb, ba) = color_to_rgba(background)

  // Porter-Duff "over" operator
  let a_out = fa + ba * (1.0 - fa)
  if a_out == 0.0 {
    Color::Black
  } else {
    let r_out = (fr * fa + br * ba * (1.0 - fa)) / a_out
    let g_out = (fg * fa + bg * ba * (1.0 - fa)) / a_out
    let b_out = (fb * fa + bb * ba * (1.0 - fa)) / a_out
    Color::RGBA(r_out, g_out, b_out, a_out)
  }
}
