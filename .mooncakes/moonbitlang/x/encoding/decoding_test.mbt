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

// Streaming

///|
test "streaming decoding UTF8 rabbit" {
  let inputs = [b"abc", b"\u{f0}", b"\u{9f}\u{90}\u{b0}"] // UTF8(🐰) == <F09F 90B0>
  let decoder = @encoding.decoder(UTF8)
  @debug.debug_inspect(decoder.consume(inputs[0]), content="abc")
  @debug.debug_inspect(decoder.consume(inputs[1]), content="")
  @debug.debug_inspect(decoder.consume(inputs[2]), content="🐰")
  assert_true(decoder.finish().is_empty())
}

///|
test "decode_to/UTF8/stream" {
  let inputs = [b"abc", b"\u{f0}", b"\u{9f}\u{90}\u{b0}"] // UTF8(🐰) == <F09F 90B0>
  let decoder = @encoding.decoder(UTF8)
  let acc = StringBuilder::new()
  decoder.decode_to(inputs[0], acc, stream=true)
  @debug.debug_inspect(acc, content="abc")
  decoder.decode_to(inputs[1], acc, stream=true)
  @debug.debug_inspect(acc, content="abc")
  decoder.decode_to(inputs[2], acc, stream=true)
  @debug.debug_inspect(acc, content="abc🐰")
}

///|
test "streaming decoding UTF16LE rabbit" {
  // UTF16LE(🐰) == <3DD8 30DC>
  let inputs = [
    b"\u{3D}", b"\u{D8}\u{30}\u{DC}", b"\u{3D}\u{D8}", b"\u{30}\u{DC}", b"\u{3D}\u{D8}\u{30}", b"\u{DC}",
  ]
  let decoder = @encoding.decoder(UTF16LE)
  @debug.debug_inspect(decoder.consume(inputs[0]), content="")
  @debug.debug_inspect(decoder.consume(inputs[1]), content="🐰")
  @debug.debug_inspect(decoder.consume(inputs[2]), content="")
  @debug.debug_inspect(decoder.consume(inputs[3]), content="🐰")
  @debug.debug_inspect(decoder.consume(inputs[4]), content="")
  @debug.debug_inspect(decoder.consume(inputs[5]), content="🐰")
  assert_true(decoder.finish().is_empty())
}

///|
test "decode_to/UTF16LE/stream" {
  // UTF16LE(🐰) == <3DD8 30DC>
  let inputs = [
    b"\u{3D}", b"\u{D8}\u{30}\u{DC}", b"\u{3D}\u{D8}", b"\u{30}\u{DC}", b"\u{3D}\u{D8}\u{30}", b"\u{DC}",
  ]
  let decoder = @encoding.decoder(UTF16LE)
  let acc = StringBuilder::new()
  decoder.decode_to(inputs[0], acc, stream=true)
  @debug.debug_inspect(acc, content="")
  decoder.decode_to(inputs[1], acc, stream=true)
  @debug.debug_inspect(acc, content="🐰")
  decoder.decode_to(inputs[2], acc, stream=true)
  @debug.debug_inspect(acc, content="🐰")
  decoder.decode_to(inputs[3], acc, stream=true)
  @debug.debug_inspect(acc, content="🐰🐰")
  decoder.decode_to(inputs[4], acc, stream=true)
  @debug.debug_inspect(acc, content="🐰🐰")
  decoder.decode_to(inputs[5], acc, stream=true)
  @debug.debug_inspect(acc, content="🐰🐰🐰")
}

///|
test "streaming decoding UTF16LE ASCII" {
  let ascii = "How do we grasp all the apples at once?"
  let from_array = Bytes::from_array
  let decoder = @encoding.decoder(UTF16LE)

  // NOTE: `to_bytes` means `to_utf16le_bytes` to MoonBit String
  let chunks = @encoding.encode(UTF16, ascii).to_array().chunks(17)
  @debug.assert_eq(chunks.length(), 5)

  // chunk by chunk
  @debug.assert_eq(
    from_array(chunks[0]),
    b"\u{48}\u{00}\u{6f}\u{00}\u{77}\u{00}\u{20}\u{00}\u{64}\u{00}\u{6f}\u{00}\u{20}\u{00}\u{77}\u{00}\u{65}",
  )
  @debug.debug_inspect(decoder.consume(from_array(chunks[0])), content="How do w")
  @debug.assert_eq(
    from_array(chunks[1]),
    b"\u{00}\u{20}\u{00}\u{67}\u{00}\u{72}\u{00}\u{61}\u{00}\u{73}\u{00}\u{70}\u{00}\u{20}\u{00}\u{61}\u{00}",
  )
  @debug.debug_inspect(decoder.consume(from_array(chunks[1])), content="e grasp a")
  @debug.assert_eq(
    from_array(chunks[2]),
    b"\u{6c}\u{00}\u{6c}\u{00}\u{20}\u{00}\u{74}\u{00}\u{68}\u{00}\u{65}\u{00}\u{20}\u{00}\u{61}\u{00}\u{70}",
  )
  @debug.debug_inspect(decoder.consume(from_array(chunks[2])), content="ll the a")
  @debug.assert_eq(
    from_array(chunks[3]),
    b"\u{00}\u{70}\u{00}\u{6c}\u{00}\u{65}\u{00}\u{73}\u{00}\u{20}\u{00}\u{61}\u{00}\u{74}\u{00}\u{20}\u{00}",
  )
  @debug.debug_inspect(decoder.consume(from_array(chunks[3])), content="pples at ")
  @debug.assert_eq(from_array(chunks[4]), b"\u{6f}\u{00}\u{6e}\u{00}\u{63}\u{00}\u{65}\u{00}\u{3f}\u{00}")
  @debug.debug_inspect(decoder.consume(from_array(chunks[4])), content="once?")
  // `decode_finish()` is an alias for `decode(b"", stream=false)`
  assert_true(decoder.finish().is_empty())

  // check accumulator
  let decoder = @encoding.decoder(UTF16LE)
  let mut acc = ""
  for chunk in @encoding.encode(UTF16, ascii).to_array().chunks(7) {
    acc += decoder.consume(from_array(chunk))
  }
  assert_true(decoder.finish().is_empty())
  @debug.assert_eq(acc, ascii)
}

///|
test "streaming decoding UTF8 Emoji" {
  let art =
    #|   🎩
    #|   👶
    #| ✋👕🌂
    #|   ‼️
    #|   👞👞
  let art_bytes = @encoding.encode(UTF8, art)
  let from_array = Bytes::from_array
  let decoder = @encoding.decoder(UTF8)
  let buf = @buffer.new(size_hint=art_bytes.length())
  buf.write_bytes(art_bytes)
  let chunks = buf.contents().to_array().chunks(13)
  @debug.assert_eq(chunks.length(), 4)

  // chunk by chunk
  @debug.assert_eq(
    from_array(chunks[0]),
    b"\u{20}\u{20}\u{20}\u{f0}\u{9f}\u{8e}\u{a9}\u{0a}\u{20}\u{20}\u{20}\u{f0}\u{9f}",
  )
  @debug.debug_inspect(decoder.consume(from_array(chunks[0])), content="   🎩\n   ")
  @debug.assert_eq(
    from_array(chunks[1]),
    b"\u{91}\u{b6}\u{0a}\u{20}\u{e2}\u{9c}\u{8b}\u{f0}\u{9f}\u{91}\u{95}\u{f0}\u{9f}",
  )
  @debug.debug_inspect(decoder.consume(from_array(chunks[1])), content="👶\n ✋👕")
  @debug.assert_eq(
    from_array(chunks[2]),
    b"\u{8c}\u{82}\u{0a}\u{20}\u{20}\u{20}\u{e2}\u{80}\u{bc}\u{ef}\u{b8}\u{8f}\u{0a}",
  )
  @debug.debug_inspect(decoder.consume(from_array(chunks[2])), content="🌂\n   ‼️\n")
  @debug.assert_eq(
    from_array(chunks[3]),
    b"\u{20}\u{20}\u{20}\u{f0}\u{9f}\u{91}\u{9e}\u{f0}\u{9f}\u{91}\u{9e}",
  )
  // stream default to false
  @debug.debug_inspect(decoder.decode(from_array(chunks[3])), content="   👞👞")

  // check accumulator
  let decoder = @encoding.decoder(UTF8)
  let mut acc = ""
  for chunk in art_bytes.to_array().chunks(7) {
    acc += decoder.consume(from_array(chunk))
  }
  assert_true(decoder.finish().is_empty())
  @debug.assert_eq(acc, art)
}

///|
test "streaming decoding UTF16BE Tao71" {
  let tao71 = "知不知，尚矣；不知知，病也。圣人不病，以其病病，夫惟病病，是以不病。"
  let tao71_bytes = @encoding.encode(UTF16BE, tao71)
  let from_array = Bytes::from_array
  let decoder = @encoding.decoder(UTF16BE)
  let buf = @buffer.new(size_hint=tao71_bytes.length())
  buf.write_bytes(tao71_bytes)
  let chunks = buf.contents().to_array().chunks(17)
  @debug.assert_eq(chunks.length(), 4)

  // chunk by chunk
  @debug.assert_eq(
    from_array(chunks[0]),
    b"\u{77}\u{e5}\u{4e}\u{0d}\u{77}\u{e5}\u{ff}\u{0c}\u{5c}\u{1a}\u{77}\u{e3}\u{ff}\u{1b}\u{4e}\u{0d}\u{77}",
  )
  @debug.debug_inspect(
    decoder.consume(from_array(chunks[0])),
    content="知不知，尚矣；不",
  )
  @debug.assert_eq(
    from_array(chunks[1]),
    b"\u{e5}\u{77}\u{e5}\u{ff}\u{0c}\u{75}\u{c5}\u{4e}\u{5f}\u{30}\u{02}\u{57}\u{23}\u{4e}\u{ba}\u{4e}\u{0d}",
  )
  @debug.debug_inspect(
    decoder.consume(from_array(chunks[1])),
    content="知知，病也。圣人不",
  )
  @debug.assert_eq(
    from_array(chunks[2]),
    b"\u{75}\u{c5}\u{ff}\u{0c}\u{4e}\u{e5}\u{51}\u{76}\u{75}\u{c5}\u{75}\u{c5}\u{ff}\u{0c}\u{59}\u{2b}\u{60}",
  )
  @debug.debug_inspect(
    decoder.consume(from_array(chunks[2])),
    content="病，以其病病，夫",
  )
  @debug.assert_eq(
    from_array(chunks[3]),
    b"\u{df}\u{75}\u{c5}\u{75}\u{c5}\u{ff}\u{0c}\u{66}\u{2f}\u{4e}\u{e5}\u{4e}\u{0d}\u{75}\u{c5}\u{30}\u{02}",
  )
  // decoder.decode(input, stream~ = false)
  @debug.debug_inspect(
    decoder.decode(from_array(chunks[3])),
    content="惟病病，是以不病。",
  )

  // check accumulator
  let decoder = @encoding.decoder(UTF16BE)
  let mut acc = ""
  for chunk in tao71_bytes.to_array().chunks(7) {
    acc += decoder.consume(from_array(chunk))
  }
  assert_true(decoder.finish().is_empty())
  @debug.assert_eq(acc, tao71)
}

// In one go

///|
test "decoding String (UTF16LE encoded) to String (buffer.write_bytes)" {
  let src = "你好👀"
  let buf = @buffer.new(size_hint=@encoding.encode(UTF16, src).length())
  buf.write_bytes(@encoding.encode(UTF16, src))
  @debug.assert_eq(buf.to_bytes(), b"\u{60}\u{4f}\u{7d}\u{59}\u{3d}\u{d8}\u{40}\u{dc}")
  let decoder = @encoding.decoder(UTF16LE)
  let chars = decoder.decode(buf.to_bytes())
  @debug.assert_eq(chars, src)
}

///|
test "decode_to/UTF16LE" {
  let src = "你好👀"
  let buf = @buffer.new(size_hint=@encoding.encode(UTF16, src).length())
  buf.write_bytes(@encoding.encode(UTF16, src))
  let decoder = @encoding.decoder(UTF16LE)
  let acc = StringBuilder::new()
  decoder.decode_to(buf.to_bytes(), acc)
  @debug.debug_inspect(acc.to_string(), content="你好👀")
}

///|
test "decoding String (UTF16LE encoded) to String (buffer.write_char)" {
  let src = "👋再见"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    buf.write_char(s)
  }
  @debug.assert_eq(buf.to_bytes(), b"\u{3d}\u{d8}\u{4b}\u{dc}\u{8d}\u{51}\u{c1}\u{89}")
  let decoder = @encoding.decoder(UTF16LE)
  let chars = decoder.decode(buf.to_bytes())
  @debug.assert_eq(chars, src)
}

///|
test "decoding UTF16LE encoded data to String" {
  let buf = @buffer.new(size_hint=10)
  buf.write_bytes(b"\u{60}\u{4f}") // 你
  buf.write_bytes(b"\u{7d}\u{59}") // 好
  buf.write_bytes(b"\u{3d}\u{d8}\u{40}\u{dc}") // 👀
  @debug.assert_eq(buf.to_bytes(), b"\u{60}\u{4f}\u{7d}\u{59}\u{3d}\u{d8}\u{40}\u{dc}")
  let decoder = @encoding.decoder(UTF16LE)
  let chars = decoder.decode(buf.to_bytes())
  @debug.debug_inspect(chars, content="你好👀")
}

///|
test "decoding UTF16 (alias for UTF16LE) encoded data to String" {
  let buf = @buffer.new(size_hint=20)
  buf.write_bytes(b"\u{65}\u{18}")
  buf.write_bytes(b"\u{20}\u{18}")
  buf.write_bytes(b"\u{73}\u{18}")
  buf.write_bytes(b"\u{64}\u{18}")
  buf.write_bytes(b"\u{73}\u{18}")
  buf.write_bytes(b"\u{36}\u{18}")
  buf.write_bytes(b"\u{20}\u{18}")
  @debug.assert_eq(
    buf.to_bytes(),
    b"\u{65}\u{18}\u{20}\u{18}\u{73}\u{18}\u{64}\u{18}\u{73}\u{18}\u{36}\u{18}\u{20}\u{18}",
  )
  let decoder = @encoding.decoder(UTF16)
  let chars = decoder.decode(buf.to_bytes())
  @debug.debug_inspect(chars, content="ᡥᠠᡳᡤᡳᠶᠠ")
}

///|
test "decode_to/UTF16" {
  let buf = @buffer.new(size_hint=20)
  buf.write_bytes(b"\u{65}\u{18}")
  buf.write_bytes(b"\u{20}\u{18}")
  buf.write_bytes(b"\u{73}\u{18}")
  buf.write_bytes(b"\u{64}\u{18}")
  buf.write_bytes(b"\u{73}\u{18}")
  buf.write_bytes(b"\u{36}\u{18}")
  buf.write_bytes(b"\u{20}\u{18}")
  let decoder = @encoding.decoder(UTF16)
  let acc = StringBuilder::new()
  decoder.decode_to(buf.to_bytes(), acc)
  @debug.debug_inspect(acc.to_string(), content="ᡥᠠᡳᡤᡳᠶᠠ")
}

///|
test "decoding UTF16BE encoded data to String" {
  let buf = @buffer.new(size_hint=10)
  buf.write_bytes(b"\u{d8}\u{3d}\u{dc}\u{08}")
  buf.write_bytes(b"\u{d8}\u{3d}\u{dc}\u{31}")
  buf.write_bytes(b"\u{d8}\u{3d}\u{dc}\u{07}")
  buf.write_bytes(b"\u{d8}\u{3d}\u{dc}\u{30}")
  @debug.assert_eq(
    buf.to_bytes(),
    b"\u{d8}\u{3d}\u{dc}\u{08}\u{d8}\u{3d}\u{dc}\u{31}\u{d8}\u{3d}\u{dc}\u{07}\u{d8}\u{3d}\u{dc}\u{30}",
  )
  let decoder = @encoding.decoder(UTF16BE)
  let chars = decoder.decode(buf.to_bytes())
  @debug.debug_inspect(chars, content="🐈🐱🐇🐰")
}

///|
test "decode_to/UTF16BE" {
  let buf = @buffer.new(size_hint=10)
  buf.write_bytes(b"\u{d8}\u{3d}\u{dc}\u{08}")
  buf.write_bytes(b"\u{d8}\u{3d}\u{dc}\u{31}")
  buf.write_bytes(b"\u{d8}\u{3d}\u{dc}\u{07}")
  buf.write_bytes(b"\u{d8}\u{3d}\u{dc}\u{30}")
  let decoder = @encoding.decoder(UTF16BE)
  let acc = StringBuilder::new()
  decoder.decode_to(buf.to_bytes(), acc)
  @debug.debug_inspect(acc.to_string(), content="🐈🐱🐇🐰")
}

///|
test "decoding UTF8 encoded data to String" {
  let buf = @buffer.new(size_hint=10)
  buf.write_bytes(b"\u{e4}\u{bd}\u{a0}") // 你
  buf.write_bytes(b"\u{e5}\u{a5}\u{bd}") // 好
  buf.write_bytes(b"\u{f0}\u{9f}\u{91}\u{80}") // 👀
  @debug.assert_eq(buf.to_bytes(), b"\u{e4}\u{bd}\u{a0}\u{e5}\u{a5}\u{bd}\u{f0}\u{9f}\u{91}\u{80}")
  let decoder = @encoding.decoder(UTF8)
  let chars = decoder.decode(buf.to_bytes())
  @debug.debug_inspect(chars, content="你好👀")
}

///|
test "decode_to/UTF8" {
  let buf = @buffer.new(size_hint=10)
  buf.write_bytes(b"\u{e4}\u{bd}\u{a0}") // 你
  buf.write_bytes(b"\u{e5}\u{a5}\u{bd}") // 好
  buf.write_bytes(b"\u{f0}\u{9f}\u{91}\u{80}") // 👀
  let decoder = @encoding.decoder(UTF8)
  let acc = StringBuilder::new()
  decoder.decode_to(buf.to_bytes(), acc)
  @debug.debug_inspect(acc.to_string(), content="你好👀")
}

///|
test "decoding UTF8 encoded bytes to String" {
  let src = "👋再见"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf8_char(buf, s)
  }
  @debug.assert_eq(buf.to_bytes(), b"\u{f0}\u{9f}\u{91}\u{8b}\u{e5}\u{86}\u{8d}\u{e8}\u{a7}\u{81}")
  let decoder = @encoding.decoder(UTF8)
  let chars = decoder.decode(buf.to_bytes())
  @debug.assert_eq(chars, src)
}

///|
test "decoding UTF8 encoded data" {
  let src = "👋再见"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf8_char(buf, s)
  }
  @debug.assert_eq(buf.to_bytes(), b"\u{f0}\u{9f}\u{91}\u{8b}\u{e5}\u{86}\u{8d}\u{e8}\u{a7}\u{81}")
  let decoder = @encoding.decoder(UTF8)
  let chars = decoder.decode(buf.to_bytes())
  @debug.debug_inspect(chars.iter().collect(), content="['👋', '再', '见']")
}

///|
test "decoding UTF16LE encoded data with UTF8" {
  let src = "跑步🏃游泳🏊"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf16le_char(buf, s)
  }
  @debug.assert_eq(
    buf.to_bytes(),
    b"\u{d1}\u{8d}\u{65}\u{6b}\u{3c}\u{d8}\u{c3}\u{df}\u{38}\u{6e}\u{f3}\u{6c}\u{3c}\u{d8}\u{ca}\u{df}",
  )
  let decoder = @encoding.decoder(UTF8)
  // NOTE: Expected to be malformed here
  let chars = try? decoder.decode(buf.to_bytes())
  assert_true(chars is Err(_))
  @debug.debug_inspect(
    chars,
    content="Err(moonbitlang/x/encoding.MalformedError.MalformedError)",
  )
}

///|
test "decode_to/UTF16LE-UTF8/MalformedError" {
  let src = "跑步🏃游泳🏊"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf16le_char(buf, s)
  }
  let decoder = @encoding.decoder(UTF8)
  let acc = StringBuilder::new()
  @debug.debug_inspect(
    try? decoder.decode_to(buf.to_bytes(), acc),
    content="Err(moonbitlang/x/encoding.MalformedError.MalformedError)",
  )
}

///|
test "decode_to/UTF16LE-UTF8/TruncatedError" {
  let src = "跑步🏃游泳🏊"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf16le_char(buf, s)
  }
  let bytes = buf.to_bytes()
  let bytes_view : Bytes = [..bytes[:bytes.length() - 1]]
  let decoder = @encoding.decoder(UTF16LE)
  let acc = StringBuilder::new()
  let result = try? decoder.decode_to(bytes_view, acc)
  @debug.debug_inspect(
    result,
    content="Err(moonbitlang/x/encoding.TruncatedError.TruncatedError)",
  )
}

///|
test "decode_to/UTF16LE-UTF8/stream" {
  let src = "跑步🏃游泳🏊"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf16le_char(buf, s)
  }
  let bytes = buf.to_bytes()
  let bytes_view : Bytes = [..bytes[:bytes.length() - 1]]
  let decoder = @encoding.decoder(UTF16LE)
  let acc = StringBuilder::new()
  let result = try? decoder.decode_to(bytes_view, acc, stream=true)
  @debug.debug_inspect(result, content="Ok(())")
  @debug.debug_inspect(acc.to_string(), content="跑步🏃游泳")
  let result = try? decoder.decode_to(
    [bytes[bytes.length() - 1]],
    acc,
    stream=true,
  )
  @debug.debug_inspect(result, content="Ok(())")
  @debug.debug_inspect(acc.to_string(), content="跑步🏃游泳🏊")
}

///|
test "decode_to/empty" {
  let acc = StringBuilder::new()
  let decoder = @encoding.decoder(UTF8)
  decoder.decode_to("", acc)
  @debug.debug_inspect(acc.to_string(), content="")
  @encoding.decode_to("", acc, encoding=UTF8)
  @debug.debug_inspect(acc.to_string(), content="")
}

///|
test "decoding UTF8 encoded data with UTF16LE" {
  let src = "跑步🏃游泳🏊"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf8_char(buf, s)
  }
  @debug.assert_eq(
    buf.to_bytes(),
    b"\u{e8}\u{b7}\u{91}\u{e6}\u{ad}\u{a5}\u{f0}\u{9f}\u{8f}\u{83}\u{e6}\u{b8}\u{b8}\u{e6}\u{b3}\u{b3}\u{f0}\u{9f}\u{8f}\u{8a}",
  )
  let decoder = @encoding.decoder(UTF16LE)
  let chars = decoder.decode(buf.to_bytes())
  // NOTE: Happens to be legal UTF16LE
  @debug.debug_inspect(
    chars.iter().collect(),
    content="['럨', '\\u{e691}', 'ꖭ', '鿰', '莏', '룦', '\\u{e6b8}', '뎳', '鿰', '誏']",
  )
}

///|
test "decode_to/UTF8-UTF16LE" {
  let src = "跑步🏃游泳🏊"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf8_char(buf, s)
  }
  let decoder = @encoding.decoder(UTF16LE)
  let acc = StringBuilder::new()
  decoder.decode_to(buf.to_bytes(), acc)
  // NOTE: Happens to be legal UTF16LE
  @debug.debug_inspect(acc.to_string(), content="럨ꖭ鿰莏룦뎳鿰誏")
}

///|
test "decoding UTF16BE encoded data with UTF8" {
  let src = "跑步🏃游泳🏊"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf16be_char(buf, s)
  }
  @debug.assert_eq(
    buf.to_bytes(),
    b"\u{8d}\u{d1}\u{6b}\u{65}\u{d8}\u{3c}\u{df}\u{c3}\u{6e}\u{38}\u{6c}\u{f3}\u{d8}\u{3c}\u{df}\u{ca}",
  )
  let decoder = @encoding.decoder(UTF8)
  // NOTE: Expected to be malformed here
  let chars = try? decoder.decode(buf.to_bytes())
  assert_true(chars is Err(_))
  @debug.debug_inspect(
    chars,
    content="Err(moonbitlang/x/encoding.MalformedError.MalformedError)",
  )
}

///|
test "decode_to/UTF16BE-UTF8" {
  let src = "跑步🏃游泳🏊"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf16be_char(buf, s)
  }
  let decoder = @encoding.decoder(UTF8)
  let acc = StringBuilder::new()
  @debug.debug_inspect(
    try? decoder.decode_to(buf.to_bytes(), acc),
    content="Err(moonbitlang/x/encoding.MalformedError.MalformedError)",
  )
}

///|
test "decoding UTF8 encoded data with UTF16BE" {
  let src = "跑步🏃游泳🏊"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf8_char(buf, s)
  }
  @debug.assert_eq(
    buf.to_bytes(),
    b"\u{e8}\u{b7}\u{91}\u{e6}\u{ad}\u{a5}\u{f0}\u{9f}\u{8f}\u{83}\u{e6}\u{b8}\u{b8}\u{e6}\u{b3}\u{b3}\u{f0}\u{9f}\u{8f}\u{8a}",
  )
  let decoder = @encoding.decoder(UTF16BE)
  let chars = decoder.decode(buf.to_bytes())
  // NOTE: Happens to be legal UTF16BE
  @debug.debug_inspect(
    chars.to_array(),
    content="['\\u{e8b7}', '釦', '궥', '\\u{f09f}', '较', '\\u{e6b8}', '룦', '뎳', '\\u{f09f}', '辊']",
  )
}

///|
test "decode_to/UTF8-UTF16BE" {
  let src = "跑步🏃游泳🏊"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf8_char(buf, s)
  }
  let decoder = @encoding.decoder(UTF16BE)
  let acc = StringBuilder::new()
  decoder.decode_to(buf.to_bytes(), acc)
  // NOTE: Happens to be legal UTF16BE
  @debug.debug_inspect(acc.to_string(), content="釦궥较룦뎳辊")
}

///|
test "decoding UTF16LE encoded data with UTF16BE" {
  let src = "跑步🏃游泳🏊"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf16le_char(buf, s)
  }
  @debug.assert_eq(
    buf.to_bytes(),
    b"\u{d1}\u{8d}\u{65}\u{6b}\u{3c}\u{d8}\u{c3}\u{df}\u{38}\u{6e}\u{f3}\u{6c}\u{3c}\u{d8}\u{ca}\u{df}",
  )
  let decoder = @encoding.decoder(UTF16BE)
  let chars = decoder.decode(buf.to_bytes())
  // NOTE: Happens to be legal UTF16BE
  @debug.debug_inspect(
    chars.to_array(),
    content="['톍', '敫', '㳘', '쏟', '㡮', '\\u{f36c}', '㳘', '쫟']",
  )
}

///|
test "decode_to/UTF16LE-UTF16BE" {
  let src = "跑步🏃游泳🏊"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf16le_char(buf, s)
  }
  let decoder = @encoding.decoder(UTF16BE)
  let acc = StringBuilder::new()
  decoder.decode_to(buf.to_bytes(), acc)
  // NOTE: Happens to be legal UTF16BE
  @debug.debug_inspect(acc.to_string(), content="톍敫㳘쏟㡮㳘쫟")
}

///|
test "decoding UTF16BE encoded data with UTF16LE" {
  let src = "跑步🏃游泳🏊"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf16be_char(buf, s)
  }
  @debug.assert_eq(
    buf.to_bytes(),
    b"\u{8d}\u{d1}\u{6b}\u{65}\u{d8}\u{3c}\u{df}\u{c3}\u{6e}\u{38}\u{6c}\u{f3}\u{d8}\u{3c}\u{df}\u{ca}",
  )
  let decoder = @encoding.decoder(UTF16LE)
  let chars = decoder.decode(buf.to_bytes())
  // NOTE: Happens to be legal UTF16LE
  @debug.debug_inspect(
    chars.to_array(),
    content="['톍', '敫', '㳘', '쏟', '㡮', '\\u{f36c}', '㳘', '쫟']",
  )
}

///|
test "decode_to/UTF16BE-UTF16LE" {
  let src = "跑步🏃游泳🏊"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf16be_char(buf, s)
  }
  let decoder = @encoding.decoder(UTF16LE)
  let acc = StringBuilder::new()
  decoder.decode_to(buf.to_bytes(), acc)
  // NOTE: Happens to be legal UTF16LE
  @debug.debug_inspect(acc.to_string(), content="톍敫㳘쏟㡮㳘쫟")
}

///|
test "lossy decoding UTF16LE encoded data with UTF8" {
  let src = "跑步🏃游泳🏊"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf16le_char(buf, s)
  }
  @debug.assert_eq(
    buf.to_bytes(),
    b"\u{d1}\u{8d}\u{65}\u{6b}\u{3c}\u{d8}\u{c3}\u{df}\u{38}\u{6e}\u{f3}\u{6c}\u{3c}\u{d8}\u{ca}\u{df}",
  )
  let decoder = @encoding.decoder(UTF8)
  let chars = decoder.decode_lossy(buf.to_bytes())
  @debug.debug_inspect(
    chars.to_array(),
    content="['э', 'e', 'k', '<', '�', '�', 'n', '�', '�']",
  )
}

///|
test "decode_lossy_to/UTF16LE-UTF8" {
  let src = "跑步🏃游泳🏊"
  let buf = @buffer.new(size_hint=10)
  for s in src {
    @encoding.write_utf16le_char(buf, s)
  }
  let decoder = @encoding.decoder(UTF8)
  let acc = StringBuilder::new()
  decoder.decode_lossy_to(buf.to_bytes(), acc)
  @debug.debug_inspect(acc.to_string(), content="эek<��n��")
}

///|
test "lossy decoding UTF16LE incorrectly encoded data to String" {
  let src = b"\u{00}\u{D8}"
  @debug.assert_eq(src, b"\u{00}\u{d8}")
  let decoder = @encoding.decoder(UTF16LE)
  let chars = decoder.decode_lossy(src, stream=false)
  @debug.debug_inspect(chars, content="�")
  @debug.assert_eq(chars.length(), 1)
  @debug.assert_eq(
    Int::unsafe_to_char(chars.code_unit_at(0).to_int()),
    @encoding.U_REP,
  )
}

///|
test "decode_lossy_to/UTF16LE" {
  let src = b"\u{00}\u{D8}"
  @debug.assert_eq(src, b"\u{00}\u{d8}")
  let decoder = @encoding.decoder(UTF16LE)
  let acc = StringBuilder::new()
  decoder.decode_lossy_to(src, acc)
  @debug.debug_inspect(acc.to_string(), content="�")
}

///|
test "lossy decoding UTF16 (alias for UTF16LE) incorrectly encoded data to String" {
  let src = b"\u{00}\u{D8}"
  @debug.assert_eq(src, b"\u{00}\u{d8}")
  let decoder = @encoding.decoder(UTF16)
  let chars = decoder.decode_lossy(src, stream=false)
  @debug.debug_inspect(chars, content="�")
  @debug.assert_eq(chars.length(), 1)
  @debug.assert_eq(
    Int::unsafe_to_char(chars.code_unit_at(0).to_int()),
    @encoding.U_REP,
  )
}

///|
test "decode_lossy_to/UTF16" {
  let src = b"\u{00}\u{D8}"
  @debug.assert_eq(src, b"\u{00}\u{d8}")
  let decoder = @encoding.decoder(UTF16)
  let acc = StringBuilder::new()
  decoder.decode_lossy_to(src, acc)
  @debug.debug_inspect(acc.to_string(), content="�")
}

///|
test "lossy decoding UTF16BE incorrectly encoded data to String" {
  let src = b"\u{D8}\u{00}"
  @debug.assert_eq(src, b"\u{d8}\u{00}")
  let decoder = @encoding.decoder(UTF16BE)
  let chars = decoder.decode_lossy(src, stream=false)
  @debug.debug_inspect(chars, content="�")
  @debug.assert_eq(chars.length(), 1)
  @debug.assert_eq(
    Int::unsafe_to_char(chars.code_unit_at(0).to_int()),
    @encoding.U_REP,
  )
}

///|
test "decode_lossy_to/UTF16BE" {
  let src = b"\u{D8}\u{00}"
  @debug.assert_eq(src, b"\u{d8}\u{00}")
  let decoder = @encoding.decoder(UTF16BE)
  let acc = StringBuilder::new()
  decoder.decode_lossy_to(src, acc)
  @debug.debug_inspect(acc.to_string(), content="�")
}

///|
test "lossy decoding UTF16BE which is `HI+!LO`" {
  let src = b"\u{D8}\u{00}\u{00}\u{48}"
  @debug.assert_eq(src, b"\u{d8}\u{00}\u{00}\u{48}")
  let decoder = @encoding.decoder(UTF16BE)
  let chars = decoder.decode_lossy(src, stream=false)

  // NOTE(jinser): should decode as many characters as possible
  @debug.debug_inspect(chars, content="�H") // ✅
  @debug.assert_eq(chars.length(), 2)
  @debug.assert_eq(
    Int::unsafe_to_char(chars.code_unit_at(0).to_int()),
    @encoding.U_REP,
  )
  @debug.assert_eq(chars.get_char(1), Some('H'))
}

///|
test "decode_lossy_to/UTF16BE_2" {
  let src = b"\u{D8}\u{00}\u{00}\u{48}"
  @debug.assert_eq(src, b"\u{d8}\u{00}\u{00}\u{48}")
  let decoder = @encoding.decoder(UTF16BE)
  let acc = StringBuilder::new()
  decoder.decode_lossy_to(src, acc)

  // NOTE(jinser): should decode as many characters as possible
  @debug.debug_inspect(acc.to_string(), content="�H") // ✅
}

///|
/// Well-Formed UTF-8 Byte Sequences
/// https://www.unicode.org/versions/Unicode16.0.0/core-spec/chapter-3/#G27506
test "lossy decoding UTF8 incorrectly encoded data to String" {
  let buf = @buffer.new(size_hint=10)
  buf.write_bytes(b"\u{E0}\u{9F}\u{80}")
  @debug.assert_eq(buf.to_bytes(), b"\u{e0}\u{9f}\u{80}")
  let decoder = @encoding.decoder(UTF8)
  let chars = decoder.decode_lossy(buf.to_bytes())
  @debug.debug_inspect(chars, content="�")
  @debug.assert_eq(
    Int::unsafe_to_char(chars.code_unit_at(0).to_int()),
    @encoding.U_REP,
  )
}

///|
test "decode_lossy_to/UTF8" {
  let buf = @buffer.new(size_hint=10)
  buf.write_bytes(b"\u{E0}\u{9F}\u{80}")
  @debug.assert_eq(buf.to_bytes(), b"\u{e0}\u{9f}\u{80}")
  let decoder = @encoding.decoder(UTF8)
  let acc = StringBuilder::new()
  decoder.decode_lossy_to(buf.to_bytes(), acc)
  @debug.debug_inspect(acc.to_string(), content="�")
}

///|
test "decode_lossy_to/empty" {
  let acc = StringBuilder::new()
  let decoder = @encoding.decoder(UTF8)
  decoder.decode_lossy_to("", acc)
  @debug.debug_inspect(acc.to_string(), content="")
}

///|
/// https://learn.microsoft.com/en-us/windows/win32/intl/surrogates-and-supplementary-characters
/// > The first (high) surrogate is a 16-bit code value in the range U+D800 to U+DBFF.
/// > The second (low) surrogate is a 16-bit code value in the range U+DC00 to U+DFFF.
test "Not all UTF16LE is format-legal UTF16BE and vice versa" {
  let bytes_le = b"\u{D8}\u{00}\u{D9}\u{00}"

  // valid in UTF16LE
  let decoder_utf16le = @encoding.decoder(UTF16LE)
  let chars_utf16le = decoder_utf16le.decode(bytes_le)
  @debug.debug_inspect(chars_utf16le, content="ØÙ")

  // invalid in UTF16BE
  let decoder_utf16be = @encoding.decoder(UTF16BE)
  let malformedError = try? decoder_utf16be.decode(bytes_le)
  assert_true(malformedError is Err(_))

  // vice versa
  let bytes_be = b"\u{00}\u{D8}\u{00}\u{D9}"

  // valid in UTF16BE
  let decoder_utf16be = @encoding.decoder(UTF16BE)
  let chars_utf16be = decoder_utf16be.decode(bytes_be)
  @debug.debug_inspect(chars_utf16be, content="ØÙ")

  // invalid in UTF16LE
  let decoder_utf16le = @encoding.decoder(UTF16LE)
  let malformedError = try? decoder_utf16le.decode(bytes_be)
  assert_true(malformedError is Err(_))
}
