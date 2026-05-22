///| Extended FFI bindings for terminal input and control

///|
/// These are critical for interactive TUI applications

// Keyboard input functions (mouse functions already in terminal_ffi.mbt)
#borrow(renderer)
extern "C" fn enableKittyKeyboardR(
  renderer : RendererPtr,
  flags : Byte,
) -> Unit = "enableKittyKeyboard"

///|
#borrow(renderer)
extern "C" fn disableKittyKeyboardR(renderer : RendererPtr) -> Unit = "disableKittyKeyboard"

// Bracketed Paste Mode

///|
/// Enable bracketed paste mode - allows detecting pasted text
#borrow(renderer)
extern "C" fn setBracketedPasteR(
  renderer : RendererPtr,
  enable : Bool,
) -> Unit = "setBracketedPaste"

// Terminal capabilities

///|
#borrow(renderer, caps_ptr)
extern "C" fn getTerminalCapabilitiesR(
  renderer : RendererPtr,
  caps_ptr : TerminalCapabilitiesPtr,
) -> Unit = "getTerminalCapabilities"

///|
#borrow(renderer, response)
extern "C" fn processCapabilityResponseR(
  renderer : RendererPtr,
  response : Bytes,
  response_len : UInt,
) -> Unit = "processCapabilityResponse"

// Cursor control

///|
#borrow(renderer)
extern "C" fn setCursorPositionR(
  renderer : RendererPtr,
  x : Int,
  y : Int,
  visible : Bool,
) -> Unit = "setCursorPosition"

///|
#borrow(renderer, style)
extern "C" fn setCursorStyleR(
  renderer : RendererPtr,
  style : Bytes,
  style_len : UInt,
  blinking : Bool,
) -> Unit = "setCursorStyle"

///|
#borrow(renderer, color)
extern "C" fn setCursorColorR(renderer : RendererPtr, color : Color) -> Unit = "setCursorColor"

// Terminal management

///|
#borrow(renderer)
extern "C" fn clearTerminalR(renderer : RendererPtr) -> Unit = "clearTerminal"

///|
#borrow(renderer, title)
extern "C" fn setTerminalTitleR(
  renderer : RendererPtr,
  title : Bytes,
  title_len : UInt,
) -> Unit = "setTerminalTitle"

///|
#borrow(renderer)
extern "C" fn resizeRendererR(
  renderer : RendererPtr,
  width : UInt,
  height : UInt,
) -> Unit = "resizeRenderer"

///|
#borrow(renderer)
extern "C" fn setupTerminalR(
  renderer : RendererPtr,
  use_alternate_screen : Bool,
) -> Unit = "setupTerminal"

// Hit testing for mouse events

///|
#borrow(renderer)
extern "C" fn addToHitGridR(
  renderer : RendererPtr,
  x : Int,
  y : Int,
  width : UInt,
  height : UInt,
  id : UInt,
) -> Unit = "addToHitGrid"

///|
#borrow(renderer)
extern "C" fn checkHitR(renderer : RendererPtr, x : UInt, y : UInt) -> UInt = "checkHit"

// Debug functions

///|
#borrow(renderer)
extern "C" fn dumpHitGridR(renderer : RendererPtr) -> Unit = "dumpHitGrid"

///|
#borrow(renderer)
extern "C" fn setDebugOverlayR(
  renderer : RendererPtr,
  enabled : Bool,
  corner : Byte,
) -> Unit = "setDebugOverlay"

// Terminal capabilities structure

///|
pub(all) struct TerminalCapabilities {
  supports_truecolor : Bool
  supports_unicode : Bool
  supports_mouse : Bool
  supports_kitty_keyboard : Bool
  width : Int
  height : Int
}

///|
type TerminalCapabilitiesPtr

// Extension methods for Renderer (mouse methods already in terminal_ffi.mbt)

///|
pub fn Renderer::enable_kitty_keyboard(self : Renderer, flags : Byte) -> Unit {
  enableKittyKeyboardR(self.ptr, flags)
}

///|
pub fn Renderer::disable_kitty_keyboard(self : Renderer) -> Unit {
  disableKittyKeyboardR(self.ptr)
}

///|
pub fn Renderer::set_cursor_position(
  self : Renderer,
  x : Int,
  y : Int,
  visible : Bool,
) -> Unit {
  setCursorPositionR(self.ptr, x, y, visible)
}

///|
pub fn Renderer::set_cursor_style_ext(
  self : Renderer,
  style : String,
  blinking : Bool,
) -> Unit {
  let style_bytes = style.to_bytes()
  setCursorStyleR(
    self.ptr,
    style_bytes,
    style_bytes.length().reinterpret_as_uint(),
    blinking,
  )
}

///|
pub fn Renderer::set_cursor_color_ext(
  self : Renderer,
  r : Double,
  g : Double,
  b : Double,
  a : Double,
) -> Unit {
  let color_array = FixedArray::make(4, 0.0)
  color_array[0] = r
  color_array[1] = g
  color_array[2] = b
  color_array[3] = a
  setCursorColorR(self.ptr, color_array)
}

///|
pub fn set_terminal_title(self : Renderer, title : String) -> Unit {
  let title_bytes = title.to_bytes()
  setTerminalTitleR(
    self.ptr,
    title_bytes,
    title_bytes.length().reinterpret_as_uint(),
  )
}

///|
pub fn setup_terminal(self : Renderer, use_alternate_screen : Bool) -> Unit {
  setupTerminalR(self.ptr, use_alternate_screen)
}

///|
pub fn add_hit_region(
  self : Renderer,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
  id : Int,
) -> Unit {
  addToHitGridR(
    self.ptr,
    x,
    y,
    width.reinterpret_as_uint(),
    height.reinterpret_as_uint(),
    id.reinterpret_as_uint(),
  )
}

///|
pub fn check_hit(self : Renderer, x : Int, y : Int) -> Int {
  checkHitR(self.ptr, x.reinterpret_as_uint(), y.reinterpret_as_uint()).reinterpret_as_int()
}

///|
pub fn Renderer::enable_debug_overlay(
  self : Renderer,
  enabled : Bool,
  corner : Byte,
) -> Unit {
  setDebugOverlayR(self.ptr, enabled, corner)
}

///|
pub fn Renderer::dump_hit_grid(self : Renderer) -> Unit {
  dumpHitGridR(self.ptr)
}
