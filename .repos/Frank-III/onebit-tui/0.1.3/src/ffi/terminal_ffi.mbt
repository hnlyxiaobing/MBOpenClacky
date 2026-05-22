///| FFI bindings for OpenTUI's Zig terminal renderer

///|
/// These bindings provide access to the high-performance terminal rendering engine

// Opaque types for C pointers
type RendererPtr

///|
type BufferPtr

// Type alias for RGBA color (4 doubles)

///|
typealias FixedArray[Double] as Color

// Helper function to convert MoonBit String (UTF-16) to null-terminated UTF-8 Bytes for C FFI

///|
fn string_to_c_bytes(s : String) -> Bytes {
  // MoonBit strings are UTF-16, but C expects UTF-8
  let utf16_bytes = s.to_bytes().to_array()
  let utf8_arr : Ref[Array[Byte]] = Ref::new([])

  // Convert UTF-16 to UTF-8 (simple ASCII case for now)
  // For ASCII characters, UTF-16 uses 2 bytes: [char, 0x00]
  // We need to extract just the character bytes
  let mut i = 0
  while i < utf16_bytes.length() {
    let byte = utf16_bytes[i]
    let next = if i + 1 < utf16_bytes.length() { utf16_bytes[i + 1] } else { 0 }

    // For ASCII range (0-127), just take the first byte if the second is 0
    if byte <= 127 && next == 0 {
      utf8_arr.val.push(byte)
      i = i + 2 // Skip the null byte
    } else if byte > 127 || next != 0 {
      // For now, handle extended ASCII/Unicode simply
      // This is a simplified conversion - proper UTF-16 to UTF-8 would be more complex
      utf8_arr.val.push(byte)
      if next != 0 {
        utf8_arr.val.push(next)
      }
      i = i + 2
    } else {
      // Single byte (shouldn't happen in UTF-16 but handle it)
      utf8_arr.val.push(byte)
      i = i + 1
    }
  }

  // Ensure null termination for C
  if utf8_arr.val.last() != Some(0) {
    utf8_arr.val.push(0)
  }
  Bytes::from_array(utf8_arr.val)
}

// Renderer management functions

///|
extern "C" fn createRenderer(width : UInt, height : UInt) -> RendererPtr = "createRendererDebug"

///|
#borrow(renderer)
extern "C" fn destroyRenderer(
  renderer : RendererPtr,
  use_alternate_screen : Bool,
  split_height : UInt,
) -> Unit = "destroyRenderer"

///|
#borrow(renderer)
extern "C" fn setUseThread(renderer : RendererPtr, use_thread : Bool) -> Unit = "setUseThread"

///|
#borrow(renderer, color)
extern "C" fn setBackgroundColorMB(
  renderer : RendererPtr,
  color : Color,
) -> Unit = "setBackgroundColorMB"

///|
#borrow(renderer)
extern "C" fn render(renderer : RendererPtr, force : Bool) -> Unit = "render"

///|
#borrow(renderer)
extern "C" fn getNextBuffer(renderer : RendererPtr) -> BufferPtr = "getNextBuffer"

///|
#borrow(renderer)
extern "C" fn getCurrentBuffer(renderer : RendererPtr) -> BufferPtr = "getCurrentBuffer"

// Buffer management functions

///|
extern "C" fn createOptimizedBuffer(
  width : UInt,
  height : UInt,
  respect_alpha : Bool,
) -> BufferPtr? = "createOptimizedBufferSimple"

///|
#borrow(buffer)
extern "C" fn destroyOptimizedBuffer(buffer : BufferPtr) -> Unit = "destroyOptimizedBuffer"

///|
#borrow(buffer)
extern "C" fn getBufferWidth(buffer : BufferPtr) -> UInt = "getBufferWidth"

///|
#borrow(buffer)
extern "C" fn getBufferHeight(buffer : BufferPtr) -> UInt = "getBufferHeight"

// Buffer drawing functions - use MB variants that handle Double->Float conversion

///|
#borrow(buffer, bg)
extern "C" fn bufferClearMB(buffer : BufferPtr, bg : Color) -> Unit = "bufferClearMB"

///|
#borrow(buffer, text, fg, bg)
extern "C" fn bufferDrawTextMB(
  buffer : BufferPtr,
  text : Bytes,
  text_len : UInt,
  x : UInt,
  y : UInt,
  fg : Color,
  bg : Color,
  attributes : Byte,
) -> Unit = "bufferDrawTextMB"

///|
#borrow(buffer, text, fg)
extern "C" fn bufferDrawTextNoBgMB(
  buffer : BufferPtr,
  text : Bytes,
  text_len : UInt,
  x : UInt,
  y : UInt,
  fg : Color,
  attributes : Byte,
) -> Unit = "bufferDrawTextNoBgMB"

///|
#borrow(buffer, bg)
extern "C" fn bufferFillRectMB(
  buffer : BufferPtr,
  x : UInt,
  y : UInt,
  width : UInt,
  height : UInt,
  bg : Color,
) -> Unit = "bufferFillRectMB"

// Cursor control functions

///|
extern "C" fn setCursorPosition(x : Int, y : Int, visible : Bool) -> Unit = "setCursorPosition"

///|
#borrow(style)
extern "C" fn setCursorStyle(
  style : Bytes,
  style_len : UInt,
  blinking : Bool,
) -> Unit = "setCursorStyle"

///|
#borrow(color)
extern "C" fn setCursorColorMB(color : Color) -> Unit = "setCursorColorMB"

// Terminal control functions

///|
#borrow(renderer)
extern "C" fn clearTerminal(renderer : RendererPtr) -> Unit = "clearTerminal"

///|
#borrow(renderer)
extern "C" fn resizeRenderer(
  renderer : RendererPtr,
  width : UInt,
  height : UInt,
) -> Unit = "resizeRenderer"

// Newer renderer-scoped cursor control (adapts to old symbols via C wrapper)

///|
#borrow(renderer)
extern "C" fn setCursorPositionRMB(
  renderer : RendererPtr,
  x : Int,
  y : Int,
  visible : Bool,
) -> Unit = "setCursorPositionRMB"

///|
#borrow(renderer, style)
extern "C" fn setCursorStyleRMB(
  renderer : RendererPtr,
  style : Bytes,
  style_len : UInt,
  blinking : Bool,
) -> Unit = "setCursorStyleRMB"

///|
#borrow(renderer, color)
extern "C" fn setCursorColorRMB(renderer : RendererPtr, color : Color) -> Unit = "setCursorColorRMB"

// Newer renderer controls

///|
#borrow(renderer)
extern "C" fn enableMouseR(
  renderer : RendererPtr,
  enable_movement : Bool,
) -> Unit = "enableMouseR"

///|
#borrow(renderer)
extern "C" fn disableMouseR(renderer : RendererPtr) -> Unit = "disableMouseR"

///|
#borrow(renderer)
extern "C" fn setRenderOffsetR(renderer : RendererPtr, offset : UInt) -> Unit = "setRenderOffsetR"

///|
#borrow(renderer)
extern "C" fn updateStatsR(
  renderer : RendererPtr,
  time : Double,
  fps : UInt,
  frame_cb : Double,
) -> Unit = "updateStatsR"

///|
#borrow(renderer)
extern "C" fn updateMemoryStatsR(
  renderer : RendererPtr,
  heap_used : UInt,
  heap_total : UInt,
  array_buffers : UInt,
) -> Unit = "updateMemoryStatsR"

// Hit testing for mouse events

///|
#borrow(renderer)
extern "C" fn addToHitGrid(
  renderer : RendererPtr,
  x : Int,
  y : Int,
  width : UInt,
  height : UInt,
  id : UInt,
) -> Unit = "addToHitGrid"

///|
#borrow(renderer)
extern "C" fn checkHit(renderer : RendererPtr, x : UInt, y : UInt) -> UInt = "checkHit"

///|
#borrow(renderer)
extern "C" fn dumpHitGrid(renderer : RendererPtr) -> Unit = "dumpHitGrid"

// Scissor rects for clipping

///|
#borrow(buffer)
extern "C" fn bufferPushScissorRect(
  buffer : BufferPtr,
  x : Int,
  y : Int,
  width : UInt,
  height : UInt,
) -> Unit = "bufferPushScissorRect"

///|
#borrow(buffer)
extern "C" fn bufferPopScissorRect(buffer : BufferPtr) -> Unit = "bufferPopScissorRect"

///|
#borrow(buffer)
extern "C" fn bufferClearScissorRects(buffer : BufferPtr) -> Unit = "bufferClearScissorRects"

// Enhanced buffer creation & drawing

///|
extern "C" fn createOptimizedBuffer2(
  width : UInt,
  height : UInt,
  respect_alpha : Bool,
  width_method : Byte,
) -> BufferPtr? = "createOptimizedBuffer2"

///|
#borrow(buffer, fg, bg)
extern "C" fn bufferSetCellWithAlphaBlendingMB(
  buffer : BufferPtr,
  x : UInt,
  y : UInt,
  char_code : UInt,
  fg : Color,
  bg : Color,
  attributes : Byte,
) -> Unit = "bufferSetCellWithAlphaBlendingMB"

///|
#borrow(buffer, border_chars, border_color, background_color, title)
extern "C" fn bufferDrawBoxMB(
  buffer : BufferPtr,
  x : Int,
  y : Int,
  width : UInt,
  height : UInt,
  border_chars : FixedArray[UInt],
  packed_options : UInt,
  border_color : Color,
  background_color : Color,
  title : Bytes,
  title_len : UInt,
) -> Unit = "bufferDrawBoxMB"

///|
#borrow(target, frame_buffer)
extern "C" fn drawFrameBufferR(
  target : BufferPtr,
  dest_x : Int,
  dest_y : Int,
  frame_buffer : BufferPtr,
  src_x : UInt,
  src_y : UInt,
  src_w : UInt,
  src_h : UInt,
) -> Unit = "drawFrameBufferR"

///|
#borrow(buffer, data)
extern "C" fn bufferDrawPackedBufferR(
  buffer : BufferPtr,
  data : Bytes,
  data_len : UInt,
  pos_x : UInt,
  pos_y : UInt,
  term_w : UInt,
  term_h : UInt,
) -> Unit = "bufferDrawPackedBufferR"

///|
#borrow(buffer, pixel_data)
extern "C" fn bufferDrawSuperSampleBufferR(
  buffer : BufferPtr,
  x : UInt,
  y : UInt,
  pixel_data : Bytes,
  len : UInt,
  format : Byte,
  aligned_bytes_per_row : UInt,
) -> Unit = "bufferDrawSuperSampleBufferR"

// Terminal input handling functions

///|
extern "C" fn setTerminalRawMode() -> Int = "setTerminalRawMode"

///|
extern "C" fn restoreTerminalMode() -> Int = "restoreTerminalMode"

///|
extern "C" fn readKeyByte() -> Int = "readKeyByte"

///|
#borrow(width, height)
extern "C" fn getTerminalSize(
  width : FixedArray[UInt],
  height : FixedArray[UInt],
) -> Unit = "getTerminalSize"

///|
extern "C" fn isInputAvailable() -> Bool = "isInputAvailable"

// Terminal resize handling

///|
extern "C" fn installResizeHandler() -> Int = "installResizeHandler"

///|
extern "C" fn wasTerminalResized() -> Bool = "wasTerminalResized"

// Mouse tracking control

///|
extern "C" fn enableMouseTracking(track_movement : Bool) -> Unit = "enableMouseTracking"

///|
extern "C" fn disableMouseTracking() -> Unit = "disableMouseTracking"

///|
extern "C" fn sleepMs(ms : Int) -> Unit = "sleepMs"

///|
/// High-level wrapper types with automatic memory management
pub struct Renderer {
  ptr : RendererPtr
}

///|
pub struct Buffer {
  ptr : BufferPtr
  width : UInt
  height : UInt
}

///|
/// Create a new renderer with the given dimensions
pub fn Renderer::new(width : UInt, height : UInt) -> Renderer? {
  let ptr = createRenderer(width, height)
  // Check if the pointer is null (MoonBit represents null as 0)
  // For now, assume any non-null pointer is valid
  Some(Renderer::{ ptr, })
}

///|
/// Clean up and destroy the renderer
pub fn Renderer::destroy(
  self : Renderer,
  use_alternate_screen? : Bool = true,
  split_height? : UInt = 0,
) -> Unit {
  destroyRenderer(self.ptr, use_alternate_screen, split_height)
}

///|
/// Set whether to use a separate thread for rendering
pub fn Renderer::set_use_thread(self : Renderer, use_thread : Bool) -> Unit {
  setUseThread(self.ptr, use_thread)
}

///|
/// Set the background color for the terminal
pub fn Renderer::set_background_color(
  self : Renderer,
  r : Double,
  g : Double,
  b : Double,
  a : Double,
) -> Unit {
  let color = FixedArray::make(4, 0.0)
  color[0] = r
  color[1] = g
  color[2] = b
  color[3] = a
  setBackgroundColorMB(self.ptr, color)
}

///|
/// Renderer-scoped cursor control (preferred with newer OpenTUI)
pub fn Renderer::cursor(
  self : Renderer,
  x : Int,
  y : Int,
  visible? : Bool = true,
) -> Unit {
  setCursorPositionRMB(self.ptr, x, y, visible)
}

///|
pub fn Renderer::cursor_style(
  self : Renderer,
  style : String,
  blinking? : Bool = true,
) -> Unit {
  let bs = style.to_bytes()
  setCursorStyleRMB(self.ptr, bs, bs.length().reinterpret_as_uint(), blinking)
}

///|
pub fn Renderer::cursor_color(
  self : Renderer,
  r : Double,
  g : Double,
  b : Double,
  a : Double,
) -> Unit {
  let color = FixedArray::make(4, 0.0)
  color[0] = r
  color[1] = g
  color[2] = b
  color[3] = a
  setCursorColorRMB(self.ptr, color)
}

///|
/// Render the current frame
pub fn Renderer::render(self : Renderer, force? : Bool = false) -> Unit {
  render(self.ptr, force)
}

///|
/// Get the next buffer for double-buffering
pub fn Renderer::get_next_buffer(self : Renderer) -> Buffer {
  let ptr = getNextBuffer(self.ptr)
  let width = getBufferWidth(ptr)
  let height = getBufferHeight(ptr)
  { ptr, width, height }
}

///|
/// Get the current buffer
pub fn Renderer::get_current_buffer(self : Renderer) -> Buffer {
  let ptr = getCurrentBuffer(self.ptr)
  let width = getBufferWidth(ptr)
  let height = getBufferHeight(ptr)
  { ptr, width, height }
}

///|
/// Clear the terminal
pub fn Renderer::clear_terminal(self : Renderer) -> Unit {
  clearTerminal(self.ptr)
}

///|
/// Resize the renderer
pub fn Renderer::resize(self : Renderer, width : UInt, height : UInt) -> Unit {
  resizeRenderer(self.ptr, width, height)
}

///|
/// Newer renderer controls
pub fn Renderer::enable_mouse(
  self : Renderer,
  enable_movement? : Bool = false,
) -> Unit {
  enableMouseR(self.ptr, enable_movement)
}

///|
pub fn Renderer::disable_mouse(self : Renderer) -> Unit {
  disableMouseR(self.ptr)
}

///|
pub fn Renderer::render_offset(self : Renderer, offset : UInt) -> Unit {
  setRenderOffsetR(self.ptr, offset)
}

///|
pub fn Renderer::stats(
  self : Renderer,
  time : Double,
  fps : UInt,
  frame_cb_ms : Double,
) -> Unit {
  updateStatsR(self.ptr, time, fps, frame_cb_ms)
}

///|
pub fn Renderer::memory_stats(
  self : Renderer,
  heap_used : UInt,
  heap_total : UInt,
  array_buffers : UInt,
) -> Unit {
  updateMemoryStatsR(self.ptr, heap_used, heap_total, array_buffers)
}

// Hit testing already defined in terminal_input.mbt

///|
/// Create a new buffer with the given dimensions
pub fn Buffer::new(
  width : UInt,
  height : UInt,
  respect_alpha? : Bool = false,
) -> Buffer? {
  match createOptimizedBuffer(width, height, respect_alpha) {
    Some(ptr) => Some(Buffer::{ ptr, width, height })
    None => None
  }
}

///|
/// Create a buffer with an explicit width method (newer OpenTUI)
pub fn Buffer::new_with_width(
  width : UInt,
  height : UInt,
  respect_alpha? : Bool = false,
  width_method? : Byte = 0,
) -> Buffer? {
  match createOptimizedBuffer2(width, height, respect_alpha, width_method) {
    Some(ptr) => Some(Buffer::{ ptr, width, height })
    None => None
  }
}

///|
/// Destroy the buffer
pub fn Buffer::destroy(self : Buffer) -> Unit {
  destroyOptimizedBuffer(self.ptr)
}

///|
/// Clear the buffer with a background color
pub fn Buffer::clear(
  self : Buffer,
  r : Double,
  g : Double,
  b : Double,
  a : Double,
) -> Unit {
  let bg = FixedArray::make(4, 0.0)
  bg[0] = r
  bg[1] = g
  bg[2] = b
  bg[3] = a
  bufferClearMB(self.ptr, bg)
}

///|
/// Push scissor rect for clipping (if upstream supports it; otherwise no-op)
pub fn Buffer::push_scissor(
  self : Buffer,
  x : Int,
  y : Int,
  w : Int,
  h : Int,
) -> Unit {
  bufferPushScissorRect(
    self.ptr,
    x,
    y,
    w.reinterpret_as_uint(),
    h.reinterpret_as_uint(),
  )
}

///|
/// Pop last scissor rect
pub fn Buffer::pop_scissor(self : Buffer) -> Unit {
  bufferPopScissorRect(self.ptr)
}

///|
/// Clear all scissor rects
pub fn Buffer::clear_scissors(self : Buffer) -> Unit {
  bufferClearScissorRects(self.ptr)
}

///|
/// Draw text to the buffer
pub fn Buffer::draw_text(
  self : Buffer,
  text : String,
  x : UInt,
  y : UInt,
  fg_r? : Double = 1.0,
  fg_g? : Double = 1.0,
  fg_b? : Double = 1.0,
  fg_a? : Double = 1.0,
  bg_r? : Double? = None,
  bg_g? : Double? = None,
  bg_b? : Double? = None,
  bg_a? : Double? = None,
  bold? : Bool = false,
  underline? : Bool = false,
) -> Unit {
  let text_bytes = string_to_c_bytes(text)
  // The C side expects the byte length (without null terminator)
  let text_len = (text_bytes.length() - 1).reinterpret_as_uint()
  let fg = FixedArray::make(4, 0.0)
  fg[0] = fg_r
  fg[1] = fg_g
  fg[2] = fg_b
  fg[3] = fg_a
  let mut attributes : Byte = 0
  if bold {
    attributes = attributes | 1
  }
  if underline {
    attributes = attributes | 8
  }

  // Handle optional background color
  match (bg_r, bg_g, bg_b, bg_a) {
    (Some(r), Some(g), Some(b), Some(a)) => {
      let bg_color = FixedArray::make(4, 0.0)
      bg_color[0] = r
      bg_color[1] = g
      bg_color[2] = b
      bg_color[3] = a
      bufferDrawTextMB(
        self.ptr,
        text_bytes,
        text_len,
        x,
        y,
        fg,
        bg_color,
        attributes,
      )
    }
    _ =>
      bufferDrawTextNoBgMB(self.ptr, text_bytes, text_len, x, y, fg, attributes)
  }
}

///|
/// Fill a rectangle in the buffer
pub fn Buffer::fill_rect(
  self : Buffer,
  x : UInt,
  y : UInt,
  width : UInt,
  height : UInt,
  r : Double,
  g : Double,
  b : Double,
  a : Double,
) -> Unit {
  let bg = FixedArray::make(4, 0.0)
  bg[0] = r
  bg[1] = g
  bg[2] = b
  bg[3] = a
  bufferFillRectMB(self.ptr, x, y, width, height, bg)
}

///|
/// Set single cell with alpha blending (newer OpenTUI)
pub fn Buffer::set_cell_alpha(
  self : Buffer,
  x : UInt,
  y : UInt,
  char_code : UInt,
  fg_r? : Double = 1.0,
  fg_g? : Double = 1.0,
  fg_b? : Double = 1.0,
  fg_a? : Double = 1.0,
  bg_r? : Double = 0.0,
  bg_g? : Double = 0.0,
  bg_b? : Double = 0.0,
  bg_a? : Double = 0.0,
  attributes? : Byte = 0,
) -> Unit {
  let fg = FixedArray::make(4, 0.0)
  fg[0] = fg_r
  fg[1] = fg_g
  fg[2] = fg_b
  fg[3] = fg_a
  let bg = FixedArray::make(4, 0.0)
  bg[0] = bg_r
  bg[1] = bg_g
  bg[2] = bg_b
  bg[3] = bg_a
  bufferSetCellWithAlphaBlendingMB(
    self.ptr,
    x,
    y,
    char_code,
    fg,
    bg,
    attributes,
  )
}

///|
/// Draw framed box with colors and title (newer OpenTUI)
pub fn Buffer::draw_box(
  self : Buffer,
  x : Int,
  y : Int,
  width : UInt,
  height : UInt,
  border_chars : FixedArray[UInt],
  packed_options : UInt,
  border_color : Color,
  background_color : Color,
  title? : String = "",
) -> Unit {
  let title_bytes = title.to_bytes()
  bufferDrawBoxMB(
    self.ptr,
    x,
    y,
    width,
    height,
    border_chars,
    packed_options,
    border_color,
    background_color,
    title_bytes,
    title_bytes.length().reinterpret_as_uint(),
  )
}

///|
/// Blit from framebuffer to buffer (newer OpenTUI)
pub fn Buffer::blit_from(
  self : Buffer,
  src : Buffer,
  dest_x : Int,
  dest_y : Int,
  src_x? : UInt = 0,
  src_y? : UInt = 0,
  src_w? : UInt = 0,
  src_h? : UInt = 0,
) -> Unit {
  drawFrameBufferR(
    self.ptr,
    dest_x,
    dest_y,
    src.ptr,
    src_x,
    src_y,
    src_w,
    src_h,
  )
}

///|
/// Draw packed or super-sampled buffers
pub fn Buffer::draw_packed(
  self : Buffer,
  data : Bytes,
  pos_x : UInt,
  pos_y : UInt,
  term_w : UInt,
  term_h : UInt,
) -> Unit {
  bufferDrawPackedBufferR(
    self.ptr,
    data,
    data.length().reinterpret_as_uint(),
    pos_x,
    pos_y,
    term_w,
    term_h,
  )
}

///|
pub fn Buffer::draw_supersampled(
  self : Buffer,
  x : UInt,
  y : UInt,
  pixels : Bytes,
  format : Byte,
  aligned_bytes_per_row : UInt,
) -> Unit {
  bufferDrawSuperSampleBufferR(
    self.ptr,
    x,
    y,
    pixels,
    pixels.length().reinterpret_as_uint(),
    format,
    aligned_bytes_per_row,
  )
}

///|
/// Scissor rect functions for clipping
pub fn Buffer::push_clip(
  self : Buffer,
  x : Int,
  y : Int,
  width : UInt,
  height : UInt,
) -> Unit {
  bufferPushScissorRect(self.ptr, x, y, width, height)
}

///|
pub fn Buffer::pop_clip(self : Buffer) -> Unit {
  bufferPopScissorRect(self.ptr)
}

///|
pub fn Buffer::clear_clips(self : Buffer) -> Unit {
  bufferClearScissorRects(self.ptr)
}

///|
/// Global cursor control functions
pub fn set_cursor_position(x : Int, y : Int, visible? : Bool = true) -> Unit {
  setCursorPosition(x, y, visible)
}

///|
pub fn set_cursor_style(style : String, blinking? : Bool = true) -> Unit {
  let style_bytes = style.to_bytes()
  let style_len = style_bytes.length().reinterpret_as_uint()
  setCursorStyle(style_bytes, style_len, blinking)
}

///|
pub fn set_cursor_color(r : Double, g : Double, b : Double, a : Double) -> Unit {
  let color = FixedArray::make(4, 0.0)
  color[0] = r
  color[1] = g
  color[2] = b
  color[3] = a
  setCursorColorMB(color)
}

/// Terminal input handling functions

///|
/// Set terminal to raw mode for keyboard input
/// Returns 0 on success, -1 on error
pub fn set_terminal_raw_mode() -> Int {
  setTerminalRawMode()
}

///|
/// Restore terminal to normal mode
/// Returns 0 on success, -1 on error
pub fn restore_terminal_mode() -> Int {
  restoreTerminalMode()
}

///|
/// Read a single key byte from stdin (non-blocking)
/// Returns -1 if no data available, -2 on error, or the byte value (0-255)
pub fn read_key_byte() -> Int {
  readKeyByte()
}

///|
/// Check if input is available (non-blocking)
pub fn is_input_available() -> Bool {
  isInputAvailable()
}

///|
/// Get terminal size
pub fn get_terminal_size() -> (UInt, UInt) {
  let width = FixedArray::make(1, 0_U)
  let height = FixedArray::make(1, 0_U)
  getTerminalSize(width, height)
  (width[0], height[0])
}

///|
/// Mouse button types
pub(all) enum MouseButton {
  Left
  Middle
  Right
  ScrollUp
  ScrollDown
  None
}

///|
/// Input event types with full keyboard and mouse support
pub(all) enum InputEvent {
  // Keyboard events
  Key(KeyEvent)
  KeyMod(KeyEvent, KeyModifiers) // key with modifiers
  // Mouse events  
  MouseMove(Int, Int) // x, y position
  MouseDown(Int, Int, MouseButton) // x, y, button
  MouseUp(Int, Int, MouseButton) // x, y, button
  MouseDrag(Int, Int, MouseButton) // x, y, button being dragged
  // Terminal events
  Resize(UInt, UInt) // new width, height
  Paste(String) // Bracketed paste event with pasted text
  // No event available
  None
}

///|
/// High-level key events
pub(all) enum KeyEvent {
  Char(Int) // Regular character
  Escape // ESC key
  Enter // Enter key
  Backspace // Backspace
  Tab // Tab key
  ArrowUp // Arrow keys
  ArrowDown
  ArrowLeft
  ArrowRight
  Home // Navigation keys
  End
  PageUp
  PageDown
  Insert
  Delete
  F(Int) // Function keys F1-F12
  Unknown // Unknown sequence
} derive(Eq)

///|
/// Modifier flags for key events from CSI sequences
pub(all) struct KeyModifiers {
  ctrl : Bool
  alt : Bool
  shift : Bool
  meta : Bool
}

///|
/// Decode xterm-style modifier code (2..8) into KeyModifiers
fn decode_modifiers(code : Int) -> KeyModifiers {
  // Mapping based on xterm: 2=Shift, 3=Alt, 4=Shift+Alt, 5=Ctrl, 6=Shift+Ctrl, 7=Alt+Ctrl, 8=Shift+Alt+Ctrl
  let shift = code == 2 || code == 4 || code == 6 || code == 8
  let alt = code == 3 || code == 4 || code == 7 || code == 8
  let ctrl = code == 5 || code == 6 || code == 7 || code == 8
  { ctrl: ctrl, alt: alt, shift: shift, meta: false }
}

///|
/// Decode kitty keyboard modifier bitfield into KeyModifiers
/// Approx mapping: bit1=Shift, bit2=Alt, bit4=Ctrl, bit8=Meta/Super
fn decode_kb_kitty_modifiers(code : Int) -> KeyModifiers {
  let shift = (code & 1) != 0
  let alt = (code & 2) != 0
  let ctrl = (code & 4) != 0
  let meta = (code & 8) != 0
  { ctrl, alt, shift, meta }
}

///|
/// Parse a CSI sequence (ESC[...)
fn parse_csi_sequence() -> InputEvent {
  let params = FixedArray::make(10, 0)
  let mut param_count = 0
  let mut current_param = 0
  let mut final_char = 0

  // Read parameters and final character
  while true {
    let byte = read_key_byte()
    if byte < 0 {
      return InputEvent::None
    }

    // Check for parameter separator
    if byte == 59 { // ';'
      if param_count < 10 {
        params[param_count] = current_param
        param_count = param_count + 1
        current_param = 0
      }
    } else if byte >= 48 && byte <= 57 { // '0'-'9'
      current_param = current_param * 10 + (byte - 48)
    } else {
      // Final character - could be arrow key without parameters
      final_char = byte
      // Save current param if we have one
      if current_param > 0 && param_count < 10 {
        params[param_count] = current_param
        param_count = param_count + 1
      }
      break
    }
  }

  // Debug: Print the final char we received
  // CSI final char handled

  // Parse based on final character
  match final_char {
    65 => { // A (ArrowUp)
      if param_count >= 2 {
        let mods = decode_modifiers(params[param_count - 1])
        if mods.ctrl || mods.alt || mods.shift {
          return InputEvent::KeyMod(KeyEvent::ArrowUp, mods)
        }
      }
      InputEvent::Key(KeyEvent::ArrowUp)
    }
    66 => { // B (ArrowDown)
      if param_count >= 2 {
        let mods = decode_modifiers(params[param_count - 1])
        if mods.ctrl || mods.alt || mods.shift {
          return InputEvent::KeyMod(KeyEvent::ArrowDown, mods)
        }
      }
      InputEvent::Key(KeyEvent::ArrowDown)
    }
    67 => { // C (ArrowRight)
      if param_count >= 2 {
        let mods = decode_modifiers(params[param_count - 1])
        if mods.ctrl || mods.alt || mods.shift {
          return InputEvent::KeyMod(KeyEvent::ArrowRight, mods)
        }
      }
      InputEvent::Key(KeyEvent::ArrowRight)
    }
    68 => { // D (ArrowLeft)
      if param_count >= 2 {
        let mods = decode_modifiers(params[param_count - 1])
        if mods.ctrl || mods.alt || mods.shift {
          return InputEvent::KeyMod(KeyEvent::ArrowLeft, mods)
        }
      }
      InputEvent::Key(KeyEvent::ArrowLeft)
    }
    72 => { // H (Home)
      if param_count >= 2 {
        let mods = decode_modifiers(params[param_count - 1])
        if mods.ctrl || mods.alt || mods.shift {
          return InputEvent::KeyMod(KeyEvent::Home, mods)
        }
      }
      InputEvent::Key(KeyEvent::Home)
    }
    70 => { // F (End)
      if param_count >= 2 {
        let mods = decode_modifiers(params[param_count - 1])
        if mods.ctrl || mods.alt || mods.shift {
          return InputEvent::KeyMod(KeyEvent::End, mods)
        }
      }
      InputEvent::Key(KeyEvent::End)
    }

    // Mouse events (ESC[<button;x;y[mM])
    77 | 109 => // 'M' or 'm'
      // Check if first param byte was '<' for SGR mode
      if param_count > 0 && params[0] == 60 { // '<' - SGR mouse mode
        parse_sgr_mouse_event()
      } else if param_count >= 3 {
        // Traditional mouse event
        let button = params[0]
        let x = params[1] - 1 // Convert to 0-based
        let y = params[2] - 1
        parse_mouse_event(button, x, y, final_char == 77)
      } else {
        InputEvent::None
      }

    // Kitty keyboard CSI u: ESC [ <codepoint> ; <modifiers> u
    117 => { // 'u'
      if param_count >= 2 {
        let codepoint = params[0]
        let mods = decode_kb_kitty_modifiers(params[param_count - 1])
        return InputEvent::KeyMod(KeyEvent::Char(codepoint), mods)
      } else {
        InputEvent::Key(KeyEvent::Unknown)
      }
    }

    // Page keys with ~
    126 => // '~'
      if param_count > 0 {
        let code = params[0]
        let base_event = match code {
          2 => KeyEvent::Insert
          3 => KeyEvent::Delete
          5 => KeyEvent::PageUp
          6 => KeyEvent::PageDown
          n if n >= 11 && n <= 15 => KeyEvent::F(n - 10)
          n if n >= 17 && n <= 21 => KeyEvent::F(n - 11)
          n if n == 23 || n == 24 => KeyEvent::F(n - 12)
          _ => KeyEvent::Unknown
        }
        if param_count >= 2 {
          let mods = decode_modifiers(params[param_count - 1])
          if mods.ctrl || mods.alt || mods.shift {
            return InputEvent::KeyMod(base_event, mods)
          }
        }
        InputEvent::Key(base_event)
      } else {
        InputEvent::Key(KeyEvent::Unknown)
      }
    _ => InputEvent::Key(KeyEvent::Unknown)
  }
}

///|
/// Parse SGR mouse event (ESC[<button;x;yM or m)
fn parse_sgr_mouse_event() -> InputEvent {
  let mut button = 0
  let mut x = 0
  let mut y = 0
  let mut reading = 0 // 0=button, 1=x, 2=y
  let mut current = 0
  while reading < 3 {
    let byte = read_key_byte()
    if byte < 0 {
      return InputEvent::None
    }
    if byte == 59 { // ';'
      match reading {
        0 => {
          button = current
          reading = 1
        }
        1 => {
          x = current
          reading = 2
        }
        _ => break
      }
      current = 0
    } else if byte >= 48 && byte <= 57 { // '0'-'9'
      current = current * 10 + (byte - 48)
    } else if byte == 77 || byte == 109 { // 'M' or 'm'
      y = current
      let is_press = byte == 77
      return parse_mouse_event(button, x - 1, y - 1, is_press)
    } else {
      return InputEvent::None
    }
  }
  InputEvent::None
}

///|
/// Parse mouse button and event type
fn parse_mouse_event(
  button_code : Int,
  x : Int,
  y : Int,
  is_press : Bool,
) -> InputEvent {
  // Extract button and modifiers from button code
  let button_num = button_code & 0x03
  let shift = (button_code & 0x04) != 0
  let meta = (button_code & 0x08) != 0
  let ctrl = (button_code & 0x10) != 0
  let motion = (button_code & 0x20) != 0
  let wheel = (button_code & 0x40) != 0
  let button = if wheel {
    if button_num == 0 {
      MouseButton::ScrollUp
    } else {
      MouseButton::ScrollDown
    }
  } else {
    match button_num {
      0 => MouseButton::Left
      1 => MouseButton::Middle
      2 => MouseButton::Right
      _ => MouseButton::None
    }
  }
  if motion {
    if button_num == 3 {
      InputEvent::MouseMove(x, y)
    } else {
      InputEvent::MouseDrag(x, y, button)
    }
  } else if is_press {
    InputEvent::MouseDown(x, y, button)
  } else {
    InputEvent::MouseUp(x, y, button)
  }
}

///|
/// Read any input event (keyboard, mouse, or terminal)
pub fn read_input_event() -> InputEvent {
  let byte = read_key_byte()
  if byte == -1 {
    return InputEvent::None
  }
  if byte == -2 {
    return InputEvent::None // Error reading
  }

  // Handle special keys and escape sequences
  match byte {
    27 => {
      // ESC - check for escape sequence
      // For arrow keys, we need to read the next bytes quickly
      let next = read_key_byte()
      // ESC followed by next byte
      if next == 91 { // '[' - CSI sequence
        parse_csi_sequence() // ESC[
      } else if next == 79 { // 'O' - SS3 sequence (F1-F4 on some terminals)
        let seq = read_key_byte()
        match seq {
          80 => InputEvent::Key(KeyEvent::F(1)) // OP
          81 => InputEvent::Key(KeyEvent::F(2)) // OQ
          82 => InputEvent::Key(KeyEvent::F(3)) // OR
          83 => InputEvent::Key(KeyEvent::F(4)) // OS
          _ => InputEvent::Key(KeyEvent::Unknown)
        }
      } else if next == -1 {
        // No more bytes, it's just ESC
        InputEvent::Key(KeyEvent::Escape)
      } else {
        // Treat ESC + printable as Alt+char when not CSI/SS3
        if next >= 32 && next <= 126 {
          let mods = KeyModifiers::{ ctrl: false, alt: true, shift: false, meta: false }
          InputEvent::KeyMod(KeyEvent::Char(next), mods)
        } else {
          // Some other ESC sequence we don't recognize
          InputEvent::Key(KeyEvent::Escape)
        }
      }
    }
    13 => InputEvent::Key(KeyEvent::Enter)
    127 => InputEvent::Key(KeyEvent::Backspace)
    9 => InputEvent::Key(KeyEvent::Tab)
    _ => InputEvent::Key(KeyEvent::Char(byte))
  }
}

///|
/// Simpler read_key_event for backwards compatibility
pub fn read_key_event() -> KeyEvent {
  match read_input_event() {
    InputEvent::Key(key) => key
    _ => KeyEvent::Unknown
  }
}

/// Terminal management functions

///|
/// Install resize handler to detect terminal size changes
pub fn install_resize_handler() -> Bool {
  installResizeHandler() == 0
}

///|
/// Check if terminal was resized (clears flag after checking)
pub fn was_terminal_resized() -> Bool {
  wasTerminalResized()
}

///|
/// Sleep for specified milliseconds
pub fn sleep_ms(ms : Int) -> Unit {
  sleepMs(ms)
}

///|
/// Enable mouse tracking in the terminal
pub fn enable_mouse_tracking(track_movement? : Bool = false) -> Unit {
  enableMouseTracking(track_movement)
}

///|
/// Disable mouse tracking
pub fn disable_mouse_tracking() -> Unit {
  disableMouseTracking()
}

///|
/// Poll for input events with resize detection
pub fn poll_input_event() -> InputEvent {
  // Check for resize first
  if was_terminal_resized() {
    let (width, height) = get_terminal_size()
    return InputEvent::Resize(width, height)
  }

  // Then check for input
  read_input_event()
}

///|
/// Terminal session manager for clean setup/teardown
pub(all) struct TerminalSession {
  mut raw_mode : Bool
  mut mouse_enabled : Bool
  mut resize_handler : Bool
}

///|
/// Create a new terminal session with specified features
pub fn TerminalSession::new(
  raw_mode? : Bool = true,
  mouse? : Bool = false,
  mouse_movement? : Bool = false,
  resize_detection? : Bool = true,
) -> TerminalSession? {
  let session = TerminalSession::{
    raw_mode: false,
    mouse_enabled: false,
    resize_handler: false,
  }

  // Set up raw mode if requested
  if raw_mode {
    if set_terminal_raw_mode() != 0 {
      return None
    }
    session.raw_mode = true
  }

  // Enable mouse if requested
  if mouse {
    enable_mouse_tracking(track_movement=mouse_movement)
    session.mouse_enabled = true
  }

  // Install resize handler if requested
  if resize_detection {
    if install_resize_handler() {
      session.resize_handler = true
    }
  }
  Some(session)
}

///|
/// Clean up terminal session
pub fn TerminalSession::cleanup(self : TerminalSession) -> Unit {
  if self.mouse_enabled {
    disable_mouse_tracking()
  }
  if self.raw_mode {
    let _ = restore_terminal_mode()

  }
}
