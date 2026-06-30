fn main {
  println("Testing OneBit-TUI FFI...")
  
  // Test 1: Set cursor position (simple FFI call)
  @moonbit-community/onebit-tui/ffi.set_cursor_position(10, 10, visible=false)
  println("✓ Cursor position set")
  
  // Test 2: Try to create renderer
  match @moonbit-community/onebit-tui/ffi.Renderer::new(80, 24) {
    Some(r) => {
      println("✓ FFI Renderer created!")
      r.destroy()
      println("✓ FFI Renderer destroyed!")
    }
    None => {
      println("✗ Failed to create FFI renderer")
    }
  }
  
  println("Test complete!")
}
