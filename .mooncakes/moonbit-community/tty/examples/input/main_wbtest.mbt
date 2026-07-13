///|
test "string char count" {
  @debug.debug_inspect(string_char_count("abc"), content="3")
  @debug.debug_inspect(string_char_count("你好"), content="2")
  @debug.debug_inspect(string_char_count("👨‍👩‍👧‍👦"), content="7")
}

///|
test "describe bytes" {
  @debug.debug_inspect(byte_to_hex(b'\x00'), content="0x00")
  @debug.debug_inspect(byte_to_hex(b'\xab'), content="0xab")
  @debug.debug_inspect(describe_bytes(b"\u{00}\u{7f}\u{ff}"), content="0x00 0x7f 0xff")
}

///|
test "describe modifiers" {
  @debug.debug_inspect(describe_modifiers(@tty/input.KeyModifiers::new()), content="")
  @debug.debug_inspect(
    describe_modifiers(
      @tty/input.KeyModifiers::new(shift=true, alt=true, ctrl=true, meta=true),
    ),
    content="Ctrl+Alt+Shift+Meta+",
  )
}

///|
test "describe key names" {
  @debug.debug_inspect(
    describe_key(@tty/input.KeyEvent::new(Char('x'))),
    content="event: Key x",
  )
  @debug.debug_inspect(
    describe_key(@tty/input.KeyEvent::new(Text)),
    content="event: Key Text",
  )
  @debug.debug_inspect(
    describe_key(@tty/input.KeyEvent::new(Enter)),
    content="event: Key Enter",
  )
  @debug.debug_inspect(describe_key(@tty/input.KeyEvent::new(Tab)), content="event: Key Tab")
  @debug.debug_inspect(
    describe_key(@tty/input.KeyEvent::new(Backspace)),
    content="event: Key Backspace",
  )
  @debug.debug_inspect(
    describe_key(@tty/input.KeyEvent::new(Delete)),
    content="event: Key Delete",
  )
  @debug.debug_inspect(
    describe_key(@tty/input.KeyEvent::new(Escape)),
    content="event: Key Escape",
  )
  @debug.debug_inspect(describe_key(@tty/input.KeyEvent::new(Up)), content="event: Key Up")
  @debug.debug_inspect(
    describe_key(@tty/input.KeyEvent::new(Down)),
    content="event: Key Down",
  )
  @debug.debug_inspect(
    describe_key(@tty/input.KeyEvent::new(Left)),
    content="event: Key Left",
  )
  @debug.debug_inspect(
    describe_key(@tty/input.KeyEvent::new(Right)),
    content="event: Key Right",
  )
  @debug.debug_inspect(
    describe_key(@tty/input.KeyEvent::new(Home)),
    content="event: Key Home",
  )
  @debug.debug_inspect(describe_key(@tty/input.KeyEvent::new(End)), content="event: Key End")
  @debug.debug_inspect(
    describe_key(@tty/input.KeyEvent::new(PageUp)),
    content="event: Key PageUp",
  )
  @debug.debug_inspect(
    describe_key(@tty/input.KeyEvent::new(PageDown)),
    content="event: Key PageDown",
  )
  @debug.debug_inspect(
    describe_key(@tty/input.KeyEvent::new(Insert)),
    content="event: Key Insert",
  )
  @debug.debug_inspect(describe_key(@tty/input.KeyEvent::new(F1)), content="event: Key F1")
  @debug.debug_inspect(describe_key(@tty/input.KeyEvent::new(F2)), content="event: Key F2")
  @debug.debug_inspect(describe_key(@tty/input.KeyEvent::new(F3)), content="event: Key F3")
  @debug.debug_inspect(describe_key(@tty/input.KeyEvent::new(F4)), content="event: Key F4")
  @debug.debug_inspect(describe_key(@tty/input.KeyEvent::new(F5)), content="event: Key F5")
  @debug.debug_inspect(describe_key(@tty/input.KeyEvent::new(F6)), content="event: Key F6")
  @debug.debug_inspect(describe_key(@tty/input.KeyEvent::new(F7)), content="event: Key F7")
  @debug.debug_inspect(describe_key(@tty/input.KeyEvent::new(F8)), content="event: Key F8")
  @debug.debug_inspect(describe_key(@tty/input.KeyEvent::new(F9)), content="event: Key F9")
  @debug.debug_inspect(describe_key(@tty/input.KeyEvent::new(F10)), content="event: Key F10")
  @debug.debug_inspect(describe_key(@tty/input.KeyEvent::new(F11)), content="event: Key F11")
  @debug.debug_inspect(
    describe_key(
      @tty/input.KeyEvent::new(
        F12,
        modifiers=@tty/input.KeyModifiers::new(ctrl=true),
      ),
    ),
    content="event: Key Ctrl+F12",
  )
}

///|
test "describe input events" {
  @debug.debug_inspect(describe_input(Paste("hello")), content="event: Paste 5 chars")
  @debug.debug_inspect(describe_input(FocusIn), content="event: FocusIn")
  @debug.debug_inspect(describe_input(FocusOut), content="event: FocusOut")
  @debug.debug_inspect(
    describe_input(Unknown(b"\u{00}\u{7f}")),
    content="event: Unknown 2 bytes [0x00 0x7f]",
  )
}

///|
test "describe mouse events" {
  @debug.debug_inspect(describe_mouse_button(Left), content="Left")
  @debug.debug_inspect(describe_mouse_button(Middle), content="Middle")
  @debug.debug_inspect(describe_mouse_button(Right), content="Right")
  @debug.debug_inspect(describe_mouse_scroll(Up), content="Up")
  @debug.debug_inspect(describe_mouse_scroll(Down), content="Down")
  @debug.debug_inspect(describe_mouse_scroll(Left), content="Left")
  @debug.debug_inspect(describe_mouse_scroll(Right), content="Right")
  @debug.debug_inspect(describe_mouse_kind(Press(Left)), content="Press Left")
  @debug.debug_inspect(describe_mouse_kind(Release(Middle)), content="Release Middle")
  @debug.debug_inspect(describe_mouse_kind(Drag(Right)), content="Drag Right")
  @debug.debug_inspect(describe_mouse_kind(Move), content="Move")
  @debug.debug_inspect(describe_mouse_kind(Scroll(Down)), content="Scroll Down")
  @debug.debug_inspect(
    describe_mouse(
      @tty/input.MouseEvent::new(
        Press(Left),
        10,
        20,
        modifiers=@tty/input.KeyModifiers::new(shift=true),
      ),
    ),
    content="event: Mouse Shift+Press Left row=10 col=20",
  )
}

///|
test "describe terminal events" {
  @debug.debug_inspect(
    describe_event(Input(Key(@tty/input.KeyEvent::new(Char('x'))))),
    content="event: Key x",
  )
  @debug.debug_inspect(describe_event(Input(FocusIn)), content="event: FocusIn")
}
