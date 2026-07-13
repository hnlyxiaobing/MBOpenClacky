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
struct CustomBytes(BytesView)

///|
impl Show for CustomBytes with output(self, logger) {
  for b in self.0 {
    if b is (' '..='~') {
      logger.write_char(b.to_char())
    } else {
      logger.write_string(
        "\\x\{b.to_uint().to_string(radix=16).pad_start(2, '0')}",
      )
    }
  }
}

///|
test "base64 encode" {
  @debug.debug_inspect(encode(b"light w"), content="bGlnaHQgdw==")
  @debug.debug_inspect(encode(b"light wo"), content="bGlnaHQgd28=")
  @debug.debug_inspect(encode(b"light wor"), content="bGlnaHQgd29y")
  @debug.debug_inspect(encode(b"light work"), content="bGlnaHQgd29yaw==")
  @debug.debug_inspect(encode(b"light work."), content="bGlnaHQgd29yay4=")
  @debug.debug_inspect(encode(b"a Ā 𐀀 文 🦄"), content="YSDEgCDwkICAIOaWhyDwn6aE")
}

///|
test "base64 decode" {
  @debug.debug_inspect(CustomBytes(decode("bGlnaHQgdw==")), content="light w")
  @debug.debug_inspect(CustomBytes(decode("bGlnaHQgd28=")), content="light wo")
  @debug.debug_inspect(CustomBytes(decode("bGlnaHQgd29y")), content="light wor")
  @debug.debug_inspect(CustomBytes(decode("bGlnaHQgd29yaw==")), content="light work")
  @debug.debug_inspect(CustomBytes(decode("bGlnaHQgd29yay4=")), content="light work.")
  @debug.debug_inspect(
    CustomBytes(decode("YSDEgCDwkICAIOaWhyDwn6aE")),
    content="a \\u{c4}\\u{80} \\u{f0}\\u{90}\\u{80}\\u{80} \\u{e6}\\u{96}\\u{87} \\u{f0}\\u{9f}\\u{a6}\\u{84}",
  )
}

///|
test "base64 decode with errors" {
  @debug.debug_inspect(try? decode("中文"), content="Err(InvalidChar('中'))")
}
