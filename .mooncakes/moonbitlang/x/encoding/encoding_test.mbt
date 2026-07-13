// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
test "encoding String to UTF8" {
  let src = "你好👀"
  let bytes = @encoding.encode(UTF8, src)
  @debug.debug_inspect(
    bytes,
    content=(
      #|b"\u{e4}\u{bd}\u{a0}\u{e5}\u{a5}\u{bd}\u{f0}\u{9f}\u{91}\u{80}"
    ),
  )
}

///|
test "encode_to/UTF8" {
  let src = "你好👀"
  let buf = @buffer.new(size_hint=10)
  @encoding.encode_to(src, buf, encoding=UTF8)
  @debug.debug_inspect(
    buf.to_bytes(),
    content=(
      #|b"\u{e4}\u{bd}\u{a0}\u{e5}\u{a5}\u{bd}\u{f0}\u{9f}\u{91}\u{80}"
    ),
  )
}

///|
test "encoding String to UTF16 (alias of UTF16LE)" {
  let src = "LISP programmers know the value of everything"
  let bytes = @encoding.encode(UTF16, src)
  @debug.debug_inspect(
    bytes,
    content=(
      #|b"L\u{00}I\u{00}S\u{00}P\u{00} \u{00}p\u{00}r\u{00}o\u{00}g\u{00}r\u{00}a\u{00}m\u{00}m\u{00}e\u{00}r\u{00}s\u{00} \u{00}k\u{00}n\u{00}o\u{00}w\u{00} \u{00}t\u{00}h\u{00}e\u{00} \u{00}v\u{00}a\u{00}l\u{00}u\u{00}e\u{00} \u{00}o\u{00}f\u{00} \u{00}e\u{00}v\u{00}e\u{00}r\u{00}y\u{00}t\u{00}h\u{00}i\u{00}n\u{00}g\u{00}"
    ),
  )
}

///|
test "encode_to/UTF16" {
  let src = "LISP programmers know the value of everything"
  let buf = @buffer.new(size_hint=10)
  @encoding.encode_to(src, buf, encoding=UTF16)
  @debug.debug_inspect(
    buf.to_bytes(),
    content=(
      #|b"L\u{00}I\u{00}S\u{00}P\u{00} \u{00}p\u{00}r\u{00}o\u{00}g\u{00}r\u{00}a\u{00}m\u{00}m\u{00}e\u{00}r\u{00}s\u{00} \u{00}k\u{00}n\u{00}o\u{00}w\u{00} \u{00}t\u{00}h\u{00}e\u{00} \u{00}v\u{00}a\u{00}l\u{00}u\u{00}e\u{00} \u{00}o\u{00}f\u{00} \u{00}e\u{00}v\u{00}e\u{00}r\u{00}y\u{00}t\u{00}h\u{00}i\u{00}n\u{00}g\u{00}"
    ),
  )
}

///|
test "encoding String to UTF16LE" {
  let src = "and the cost of nothing"
  let bytes = @encoding.encode(UTF16LE, src)
  @debug.debug_inspect(
    bytes,
    content=(
      #|b"a\u{00}n\u{00}d\u{00} \u{00}t\u{00}h\u{00}e\u{00} \u{00}c\u{00}o\u{00}s\u{00}t\u{00} \u{00}o\u{00}f\u{00} \u{00}n\u{00}o\u{00}t\u{00}h\u{00}i\u{00}n\u{00}g\u{00}"
    ),
  )
}

///|
test "encode_to/UTF16LE" {
  let src = "and the cost of nothing"
  let buf = @buffer.new(size_hint=10)
  @encoding.encode_to(src, buf, encoding=UTF16LE)
  @debug.debug_inspect(
    buf.to_bytes(),
    content=(
      #|b"a\u{00}n\u{00}d\u{00} \u{00}t\u{00}h\u{00}e\u{00} \u{00}c\u{00}o\u{00}s\u{00}t\u{00} \u{00}o\u{00}f\u{00} \u{00}n\u{00}o\u{00}t\u{00}h\u{00}i\u{00}n\u{00}g\u{00}"
    ),
  )
}

///|
test "encoding String to UTF16BE" {
  let src = "λf.(λx.f(x x))(λx.f(x x))"
  let bytes = @encoding.encode(UTF16BE, src)
  @debug.debug_inspect(
    bytes,
    content=(
      #|b"\u{03}\u{bb}\u{00}f\u{00}.\u{00}(\u{03}\u{bb}\u{00}x\u{00}.\u{00}f\u{00}(\u{00}x\u{00} \u{00}x\u{00})\u{00})\u{00}(\u{03}\u{bb}\u{00}x\u{00}.\u{00}f\u{00}(\u{00}x\u{00} \u{00}x\u{00})\u{00})"
    ),
  )
}

///|
test "encode_to/UTF16BE" {
  let src = "λf.(λx.f(x x))(λx.f(x x))"
  let buf = @buffer.new(size_hint=10)
  @encoding.encode_to(src, buf, encoding=UTF16BE)
  @debug.debug_inspect(
    buf.to_bytes(),
    content=(
      #|b"\u{03}\u{bb}\u{00}f\u{00}.\u{00}(\u{03}\u{bb}\u{00}x\u{00}.\u{00}f\u{00}(\u{00}x\u{00} \u{00}x\u{00})\u{00})\u{00}(\u{03}\u{bb}\u{00}x\u{00}.\u{00}f\u{00}(\u{00}x\u{00} \u{00}x\u{00})\u{00})"
    ),
  )
}

///|
test "to_utf8_bytes" {
  @debug.debug_inspect(
    @encoding.to_utf8_bytes('A'),
    content=(
      #|b"A"
    ),
  )
  @debug.debug_inspect(
    @encoding.to_utf8_bytes('α'),
    content=(
      #|b"\u{ce}\u{b1}"
    ),
  )
  @debug.debug_inspect(
    @encoding.to_utf8_bytes('啊'),
    content=(
      #|b"\u{e5}\u{95}\u{8a}"
    ),
  )
  @debug.debug_inspect(
    @encoding.to_utf8_bytes('😦'),
    content=(
      #|b"\u{f0}\u{9f}\u{98}\u{a6}"
    ),
  )
}

///|
test "to_utf16_bytes (alias for to_utf16le_bytes)" {
  @debug.debug_inspect(
    @encoding.to_utf16_bytes('A'),
    content=(
      #|b"A\u{00}"
    ),
  )
  @debug.debug_inspect(
    @encoding.to_utf16_bytes('α'),
    content=(
      #|b"\u{b1}\u{03}"
    ),
  )
  @debug.debug_inspect(
    @encoding.to_utf16_bytes('啊'),
    content=(
      #|b"JU"
    ),
  )
  @debug.debug_inspect(
    @encoding.to_utf16_bytes('😦'),
    content=(
      #|b"=\u{d8}&\u{de}"
    ),
  )
}

///|
test "to_utf16le_bytes" {
  @debug.debug_inspect(
    @encoding.to_utf16le_bytes('A'),
    content=(
      #|b"A\u{00}"
    ),
  )
  @debug.debug_inspect(
    @encoding.to_utf16le_bytes('α'),
    content=(
      #|b"\u{b1}\u{03}"
    ),
  )
  @debug.debug_inspect(
    @encoding.to_utf16le_bytes('啊'),
    content=(
      #|b"JU"
    ),
  )
  @debug.debug_inspect(
    @encoding.to_utf16le_bytes('😦'),
    content=(
      #|b"=\u{d8}&\u{de}"
    ),
  )
}

///|
test "to_utf16be_bytes" {
  @debug.debug_inspect(
    @encoding.to_utf16be_bytes('A'),
    content=(
      #|b"\u{00}A"
    ),
  )
  @debug.debug_inspect(
    @encoding.to_utf16be_bytes('α'),
    content=(
      #|b"\u{03}\u{b1}"
    ),
  )
  @debug.debug_inspect(
    @encoding.to_utf16be_bytes('啊'),
    content=(
      #|b"UJ"
    ),
  )
  @debug.debug_inspect(
    @encoding.to_utf16be_bytes('😦'),
    content=(
      #|b"\u{d8}=\u{de}&"
    ),
  )
}

///|
test "write_utf8_char" {
  let buf = @buffer.new(size_hint=10)
  @encoding.write_utf8_char(buf, 'A')
  @encoding.write_utf8_char(buf, 'α')
  @encoding.write_utf8_char(buf, '啊')
  @encoding.write_utf8_char(buf, '😦')
  @debug.debug_inspect(
    buf.to_bytes(),
    content=(
      #|b"A\u{ce}\u{b1}\u{e5}\u{95}\u{8a}\u{f0}\u{9f}\u{98}\u{a6}"
    ),
  )
}

///|
test "write_utf16_char (alias for write_utf16le_char)" {
  let buf = @buffer.new(size_hint=10)
  @encoding.write_utf16_char(buf, 'A')
  @encoding.write_utf16_char(buf, 'α')
  @encoding.write_utf16_char(buf, '啊')
  @encoding.write_utf16_char(buf, '😦')
  @debug.debug_inspect(
    buf.to_bytes(),
    content=(
      #|b"A\u{00}\u{b1}\u{03}JU=\u{d8}&\u{de}"
    ),
  )
}

///|
test "write_utf16le_char" {
  let buf = @buffer.new(size_hint=10)
  @encoding.write_utf16le_char(buf, 'A')
  @encoding.write_utf16le_char(buf, 'α')
  @encoding.write_utf16le_char(buf, '啊')
  @encoding.write_utf16le_char(buf, '😦')
  @debug.debug_inspect(
    buf.to_bytes(),
    content=(
      #|b"A\u{00}\u{b1}\u{03}JU=\u{d8}&\u{de}"
    ),
  )
}

///|
test "write_utf16be_char" {
  let buf = @buffer.new(size_hint=10)
  @encoding.write_utf16be_char(buf, 'A')
  @encoding.write_utf16be_char(buf, 'α')
  @encoding.write_utf16be_char(buf, '啊')
  @encoding.write_utf16be_char(buf, '😦')
  @debug.debug_inspect(
    buf.to_bytes(),
    content=(
      #|b"\u{00}A\u{03}\u{b1}UJ\u{d8}=\u{de}&"
    ),
  )
}
