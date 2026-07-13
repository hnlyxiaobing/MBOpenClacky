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
test "chachaEncrypt" {
  let key = Bytes::make(32, b'\x00')
  let nonce = Bytes::make(12, b'\x00')
  let plaintext = "abc"
  let block = @encoding.encode(UTF16, plaintext)
  @debug.debug_inspect(bytes_to_hex_string(block), content="610062006300")
  let encrypted = FixedArray::make(block.length(), b'\x00')
  @crypto.ChaCha::chacha8(key, nonce).transform(block, encrypted)
  @debug.debug_inspect(bytes_to_hex_string(encrypted), content="5f008d2fea5f")
  @crypto.ChaCha::chacha12(key, nonce).transform(block, encrypted)
  @debug.debug_inspect(bytes_to_hex_string(encrypted), content="faf4f86a6455")
  @crypto.ChaCha::chacha20(key, nonce).transform(block, encrypted)
  @debug.debug_inspect(bytes_to_hex_string(encrypted), content="17b882adc3f1")
}

///|
test "chacha stream encrypt RFC8439" {
  let key = b"\u{00}\u{01}\u{02}\u{03}\u{04}\u{05}\u{06}\u{07}\u{08}\u{09}\u{0a}\u{0b}\u{0c}\u{0d}\u{0e}\u{0f}\u{10}\u{11}\u{12}\u{13}\u{14}\u{15}\u{16}\u{17}\u{18}\u{19}\u{1a}\u{1b}\u{1c}\u{1d}\u{1e}\u{1f}"
  let nonce = b"\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{4a}\u{00}\u{00}\u{00}\u{00}"
  @debug.debug_inspect(key.length(), content="32")
  let chacha = ChaCha::chacha20(key, nonce, counter=1)
  let data = b"Ladies and Gentlemen of the class of '99: "
  let data2 = b"If I could offer you only one tip for the future, sunscreen would be it."
  let encrypted = FixedArray::make(data.length() + data2.length(), b'\x00')
  chacha.transform(data, encrypted)
  chacha.transform(data2, encrypted, offset=data.length())
  @debug.debug_inspect(
    bytes_to_hex_string(encrypted),
    content="6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0bf91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d807ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab77937365af90bbf74a35be6b40b8eedf2785e42874d",
  )
}

///|
test "chacha with error" {
  @debug.debug_inspect(
    (try? @crypto.ChaCha::chacha8(b"", Bytes::make(12, b'\x00'))) is Err(_),
    content="true",
  )
  @debug.debug_inspect(
    (try? @crypto.ChaCha::chacha8(Bytes::make(32, b'\x00'), b"")) is Err(_),
    content="true",
  )
}

///|
test (bench : @bench.T) {
  let key = Bytes::make(32, b'\x00')
  let nonce = Bytes::make(12, b'\x00')
  let plaintext = "abc".repeat(100)
  let block = @encoding.encode(UTF16, plaintext)
  let chacha8 = @crypto.ChaCha::chacha8(key, nonce)
  let chacha12 = @crypto.ChaCha::chacha12(key, nonce)
  let chacha20 = @crypto.ChaCha::chacha20(key, nonce)
  bench.bench(fn() {
    let target = FixedArray::make(block.length(), b'\x00')
    chacha8.transform(block, target)
    chacha12.transform(block, target)
    chacha20.transform(block, target)
  })
}
