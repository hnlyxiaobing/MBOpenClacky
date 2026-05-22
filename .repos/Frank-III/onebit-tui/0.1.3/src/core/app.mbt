///| Simple TUI Application that works without terminal input

///|
/// This is a minimal working implementation
pub struct App {
  renderer : @ffi.Renderer
  mut buffer : @ffi.Buffer
  mut width : Int
  mut height : Int
  mut running : Bool
}

///|
/// Initialize app without requiring terminal session
pub fn App::init() -> App? {
  let (width, height) = @ffi.get_terminal_size()
  match @ffi.Renderer::new(width, height) {
    None => None
    Some(renderer) =>
      Some(App::{
        renderer,
        buffer: renderer.get_next_buffer(),
        width: width.reinterpret_as_int(),
        height: height.reinterpret_as_int(),
        running: true,
      })
  }
}

///|
/// Clear the screen
pub fn App::clear(self : App, r : Double, g : Double, b : Double) -> Unit {
  self.buffer.clear(r, g, b, 1.0)
}

///|
/// Draw text at position
pub fn App::draw_text(
  self : App,
  text : String,
  x : Int,
  y : Int,
  color : Color,
) -> Unit {
  let (r, g, b) = color_to_rgb(color)
  self.buffer.draw_text(
    text,
    x.reinterpret_as_uint(),
    y.reinterpret_as_uint(),
    fg_r=r,
    fg_g=g,
    fg_b=b,
  )
}

///|
/// Draw a filled rectangle
pub fn App::draw_rect(
  self : App,
  x : Int,
  y : Int,
  w : Int,
  h : Int,
  color : Color,
) -> Unit {
  let (r, g, b, a) = color_to_rgba(color)
  self.buffer.fill_rect(
    x.reinterpret_as_uint(),
    y.reinterpret_as_uint(),
    w.reinterpret_as_uint(),
    h.reinterpret_as_uint(),
    r,
    g,
    b,
    a,
  )
}

///|
/// Render the current frame
pub fn App::render(self : App) -> Unit {
  // Use diffed rendering to minimize terminal writes
  self.renderer.render(force=false)
  self.buffer = self.renderer.get_next_buffer()
}

///|
/// Resize renderer and update cached dimensions used for layout
pub fn App::resize(self : App, width : UInt, height : UInt) -> Unit {
  self.renderer.resize(width, height)
  self.width = width.reinterpret_as_int()
  self.height = height.reinterpret_as_int()
}

///|
/// Expose current buffer for advanced rendering
pub fn App::get_buffer(self : App) -> @ffi.Buffer {
  self.buffer
}

///|
/// Current terminal dimensions
pub fn App::dimensions(self : App) -> (Int, Int) {
  (self.width, self.height)
}

///|
/// Expose renderer for advanced integration (hit-grid, etc.)
pub fn App::get_renderer(self : App) -> @ffi.Renderer {
  self.renderer
}

///|
/// Run a simple render loop
pub fn App::run_once(self : App, draw_fn : (App) -> Unit) -> Unit {
  // Clear screen
  self.clear(0.05, 0.05, 0.1)

  // Call user draw function
  draw_fn(self)

  // Render
  self.render()
}

///|
/// Cleanup
pub fn App::cleanup(self : App) -> Unit {
  self.renderer.destroy()
}
