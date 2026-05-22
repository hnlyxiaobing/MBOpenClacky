///| FFI bindings for text buffer functionality

///|
/// Wrap modes for text
pub(all) enum WrapMode {
  Char // Break at any character
  Word // Break at word boundaries
}

///|
/// Simple color representation for text buffer
pub struct TextColor {
  r : Float
  g : Float
  b : Float
  a : Float
}

///|
pub fn TextColor::white() -> TextColor {
  { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }
}

///|
pub fn TextColor::black() -> TextColor {
  { r: 0.0, g: 0.0, b: 0.0, a: 1.0 }
}

///|
pub fn TextColor::rgb(r : Int, g : Int, b : Int) -> TextColor {
  {
    r: (r.to_double() / 255.0) |> Double::to_float,
    g: (g.to_double() / 255.0) |> Double::to_float,
    b: (b.to_double() / 255.0) |> Double::to_float,
    a: 1.0,
  }
}

///|
/// Create a new text buffer
extern "C" fn createTextBuffer(
  width_method : Byte, // 0 = wcwidth, 1 = unicode
) -> UInt = "createTextBuffer"

///|
/// Destroy a text buffer
extern "C" fn destroyTextBuffer(tb : UInt) -> Unit = "destroyTextBuffer"

///|
/// Get the length of text in the buffer
extern "C" fn textBufferGetLength(tb : UInt) -> UInt = "textBufferGetLength"

///|
/// Reset the text buffer
extern "C" fn textBufferReset(tb : UInt) -> Unit = "textBufferReset"

///|
/// Write a chunk of text to the buffer
extern "C" fn textBufferWriteChunk(
  tb : UInt,
  text : Bytes,
  text_len : UInt,
  fg_color : FixedArray[Float]?, // RGBA color array or null
  bg_color : FixedArray[Float]?, // RGBA color array or null
  attributes : Byte,
) -> UInt = "textBufferWriteChunk"

///|
/// Set wrap width for text buffer
extern "C" fn textBufferSetWrapWidth(
  tb : UInt,
  width : UInt, // 0 means no wrapping
) -> Unit = "textBufferSetWrapWidth"

///|
/// Set wrap mode for text buffer
extern "C" fn textBufferSetWrapMode(
  tb : UInt,
  mode : Byte, // 0 = char, 1 = word
) -> Unit = "textBufferSetWrapMode"

///|
/// Set selection in text buffer
extern "C" fn textBufferSetSelection(
  tb : UInt,
  start : UInt,
  end : UInt,
  bg_color : FixedArray[Float]?, // RGBA color array or null
  fg_color : FixedArray[Float]?, // RGBA color array or null
) -> Unit = "textBufferSetSelection"

///|
/// Reset selection in text buffer
extern "C" fn textBufferResetSelection(tb : UInt) -> Unit = "textBufferResetSelection"

///|
/// Draw text buffer to a buffer
extern "C" fn bufferDrawTextBuffer(
  buffer : UInt, // BufferPtr
  tb : UInt,
  x : Int,
  y : Int,
  clip_x : Int,
  clip_y : Int,
  clip_width : UInt,
  clip_height : UInt,
) -> Unit = "bufferDrawTextBuffer"

///|
/// High-level wrapper for TextBuffer
pub struct TextBuffer {
  ptr : UInt // TextBuffer pointer
  mut wrap_width : UInt
  mut wrap_mode : WrapMode
}

///|
/// Create a new text buffer
pub fn TextBuffer::new(width_method? : Byte = 0) -> TextBuffer {
  let ptr = createTextBuffer(width_method)
  { ptr, wrap_width: 0, wrap_mode: WrapMode::Word }
}

///|
/// Set wrap width
pub fn TextBuffer::set_wrap_width(self : TextBuffer, width : UInt) -> Unit {
  self.wrap_width = width
  textBufferSetWrapWidth(self.ptr, width)
}

///|
/// Set wrap mode
pub fn TextBuffer::set_wrap_mode(self : TextBuffer, mode : WrapMode) -> Unit {
  self.wrap_mode = mode
  let mode_byte : Byte = match mode {
    WrapMode::Char => 0
    WrapMode::Word => 1
  }
  textBufferSetWrapMode(self.ptr, mode_byte)
}

///|
/// Helper to convert TextColor to RGBA array
fn color_to_rgba(color : TextColor) -> FixedArray[Float] {
  [color.r, color.g, color.b, color.a]
}

///|
/// Write text to the buffer
pub fn TextBuffer::write(
  self : TextBuffer,
  text : String,
  fg_color? : TextColor = TextColor::white(),
  bg_color? : TextColor? = None,
) -> Unit {
  let text_bytes = text.to_bytes()

  // Convert colors to float arrays
  let fg_rgba = color_to_rgba(fg_color)
  let bg_rgba : FixedArray[Float]? = match bg_color {
    Some(color) => Some(color_to_rgba(color))
    None => None
  }
  let _ = textBufferWriteChunk(
    self.ptr,
    text_bytes,
    text_bytes.length().reinterpret_as_uint(),
    Some(fg_rgba),
    bg_rgba,
    0b0, // No special attributes
  )

}

///|
/// Reset the buffer
pub fn TextBuffer::reset(self : TextBuffer) -> Unit {
  textBufferReset(self.ptr)
}

///|
/// Clean up the buffer
pub fn TextBuffer::destroy(self : TextBuffer) -> Unit {
  destroyTextBuffer(self.ptr)
}
