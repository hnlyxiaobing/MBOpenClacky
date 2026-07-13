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
/// Public gzip/deflate vectors in this file come from zlib's `test/infcover.c`
/// in the `madler/zlib` repository.

///|
fn add_metadata(deflate : Bytes, crc32 : UInt, input_size : UInt) -> Bytes {
  let trailer = FixedArray::make(8, b'\x00')
  trailer.unsafe_write_uint32_le(0, crc32)
  trailer.unsafe_write_uint32_le(4, input_size)
  b"\u{1f}\u{8b}\u{08}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{ff}" +
  deflate +
  trailer.unsafe_reinterpret_as_bytes()
}

///|
test "zlib infcover stored block" {
  let compressed = add_metadata(b"\u{01}\u{01}\u{00}\u{fe}\u{ff}\u{00}", 3523407757U, 1U)
  let decoded = decode(compressed, expected_len=1)
  let decoded_min = decode(compressed, expected_len=1, input_step=Min)
  @debug.assert_eq(decoded, b"\u{00}")
  @debug.assert_eq(decoded_min, b"\u{00}")
  @debug.assert_eq(decode(encode(decoded), expected_len=1), decoded)
}

///|
test "zlib infcover fixed huffman block" {
  let compressed = add_metadata(b"\u{03}\u{00}", 0U, 0U)
  let decoded = decode(compressed, expected_len=0)
  let decoded_min = decode(compressed, expected_len=0, input_step=Min)
  @debug.assert_eq(decoded, b"")
  @debug.assert_eq(decoded_min, b"")
  @debug.assert_eq(decode(encode(decoded), expected_len=0), decoded)
}

///|
test "zlib infcover invalid stored block lengths" {
  let compressed = add_metadata(b"\u{00}\u{00}\u{00}\u{00}\u{00}", 0U, 0U)
  let result = try? decode(compressed, expected_len=0)
  let result_min = try? decode(compressed, expected_len=0, input_step=Min)
  assert_true(result is Err(_))
  assert_true(result_min is Err(_))
}

///|
test "zlib infcover invalid block type" {
  let compressed = add_metadata(b"\u{06}", 0U, 0U)
  let result = try? decode(compressed, expected_len=0)
  let result_min = try? decode(compressed, expected_len=0, input_step=Min)
  assert_true(result is Err(_))
  assert_true(result_min is Err(_))
}

///|
test "zlib infcover gzip optional header fields rejected" {
  let compressed = b"\u{1f}\u{8b}\u{08}\u{02}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{1d}\u{26}\u{03}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}"
  let result = try? decode(compressed, expected_len=0)
  let result_min = try? decode(compressed, expected_len=0, input_step=Min)
  assert_true(result is Err(_))
  assert_true(result_min is Err(_))
}

///|
test "zlib infcover dynamic huffman length extra" {
  let compressed = add_metadata(
    b"\u{ed}\u{c0}\u{01}\u{01}\u{00}\u{00}\u{00}\u{40}\u{20}\u{ff}\u{57}\u{1b}\u{42}\u{2c}\u{4f}", 2893183767U,
    516U,
  )
  let decoded = decode(compressed, expected_len=516)
  let decoded_min = decode(compressed, expected_len=516, input_step=Min)
  @debug.debug_inspect(decoded.length(), content="516")
  @debug.assert_eq(decoded_min.length(), 516)
  @debug.assert_eq(decoded_min, decoded)
  @debug.assert_eq(decode(encode(decoded), expected_len=516), decoded)
}

///|
test "zlib infcover dynamic huffman window end" {
  let compressed = add_metadata(
    b"\u{ed}\u{c0}\u{81}\u{00}\u{00}\u{00}\u{00}\u{80}\u{a0}\u{fd}\u{a9}\u{17}\u{a9}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{06}",
    4130011695U, 33025U,
  )
  let decoded = decode(compressed, expected_len=33025)
  let decoded_min = decode(compressed, expected_len=33025, input_step=Min)
  @debug.debug_inspect(decoded.length(), content="33025")
  @debug.assert_eq(decoded_min.length(), 33025)
  @debug.assert_eq(decoded_min, decoded)
  @debug.assert_eq(decode(encode(decoded), expected_len=33025), decoded)
}
