///|
/// This file is based on the Go implementation found here:
/// https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/hash/crc32/crc32_test.go
/// which has the copyright notice:
/// Copyright 2009 The Go Authors. All rights reserved.
/// Use of this source code is governed by a BSD-style
/// license that can be found in the LICENSE file.
using @io {type Slice}

///|
let golden : ReadOnlyArray[(UInt, Bytes)] = [
  (0x414fa339U, b"The quick brown fox jumps over the lazy dog"),
  (0x00000000U, b""),
  (0xe8b7be43U, b"a"),
  (0x9e83486dU, b"ab"),
  (0x352441c2U, b"abc"),
  (0xed82cd11U, b"abcd"),
  (0x8587d865U, b"abcde"),
  (0x4b8e39efU, b"abcdef"),
  (0x312a6aa6U, b"abcdefg"),
  (0xaeef2a50U, b"abcdefgh"),
  (0x8da988afU, b"abcdefghi"),
  (0x3981703aU, b"abcdefghij"),
  (0x6b9cdfe7U, b"Discard medicine more than two years old."),
  (0xc90ef73fU, b"He who has a shady past knows that nice guys finish last."),
  (0xb902341fU, b"I wouldn't marry him with a ten foot pole."),
  (0x042080e8U, b"Free! Free!/A trip/to Mars/for 900/empty jars/Burma Shave"),
  (0x154c6d11U, b"The days of the digital watch are numbered.  -Tom Stoppard"),
  (0x4c418325U, b"Nepal premier won't resign."),
  (
    0x33955150U, b"For every action there is an equal and opposite government program.",
  ),
  (0x26216a4bU, b"His money is twice tainted: 'taint yours and 'taint mine."),
  (
    0x1abbe45eU, b"There is no reason for any individual to have a computer in their home. -Ken Olsen, 1977",
  ),
  (
    0xc89a94f7U, b"It's a tiny change to the code and not completely disgusting. - Bob Manchek",
  ),
  (0xab3abe14U, b"size:  a.out:  bad magic"),
  (0xbab102b6U, b"The major problem is with sendmail.  -Mark Horton"),
  (
    0x999149d7U, b"Give me a rock, paper and scissors and I will move the world.  CCFestoon",
  ),
  (0x6d52a33cU, b"If the enemy is within range, then so are you."),
  (
    0x90631e8dU, b"It's well we cannot hear the screams/That we create in others' dreams.",
  ),
  (
    0x78309130U, b"You remind me of a TV show, but that's all right: I watch it anyway.",
  ),
  (0x7d0a377fU, b"C is as portable as Stonehedge!!"),
  (
    0x8c79fd79U, b"Even if I could be Shakespeare, I think I should still choose to be Faraday. - A. Huxley",
  ),
  (
    0xa20b7167U, b"The fugacity of a constituent in a mixture of gases at a given temperature is proportional to its mole fraction.  Lewis-Randall Rule",
  ),
  (0x8e0bb443U, b"How can you write a big system without C++?  -Paul Glick"),
]

///|
test "crc32 functions correctly" {
  for pair in golden {
    let sum = @crc32.new()
    let b = Slice::new(pair.1.to_array())
    guard sum.write(b) is (_, None)
    let got = sum.sum32()
    assert_eq(got, pair.0)
  }
}
