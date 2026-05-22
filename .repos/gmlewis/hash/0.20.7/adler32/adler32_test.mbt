// Copyright 2009 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

///|
/// This file is based on the Go implementation found here:
/// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/hash/adler32/adler32_test.go
/// which has the copyright notice:
using @io {type Slice}

///|
struct TestT {
  out : UInt
  inp : Bytes
  half_state : Bytes
}

///|
let golden : Array[TestT] = [
  { out: 0x00000001U, inp: b"", half_state: b"adl\x01\x00\x00\x00\x01" },
  { out: 0x00620062U, inp: b"a", half_state: b"adl\x01\x00\x00\x00\x01" },
  { out: 0x012600c4U, inp: b"ab", half_state: b"adl\x01\x00b\x00b" },
  { out: 0x024d0127U, inp: b"abc", half_state: b"adl\x01\x00b\x00b" },
  { out: 0x03d8018bU, inp: b"abcd", half_state: b"adl\x01\x01&\x00\xc4" },
  { out: 0x05c801f0U, inp: b"abcde", half_state: b"adl\x01\x01&\x00\xc4" },
  { out: 0x081e0256U, inp: b"abcdef", half_state: b"adl\x01\x02M\x01'" },
  { out: 0x0adb02bdU, inp: b"abcdefg", half_state: b"adl\x01\x02M\x01'" },
  { out: 0x0e000325U, inp: b"abcdefgh", half_state: b"adl\x01\x03\xd8\x01\x8b" },
  {
    out: 0x118e038eU,
    inp: b"abcdefghi",
    half_state: b"adl\x01\x03\xd8\x01\x8b",
  },
  {
    out: 0x158603f8U,
    inp: b"abcdefghij",
    half_state: b"adl\x01\x05\xc8\x01\xf0",
  },
  {
    out: 0x3f090f02U,
    inp: b"Discard medicine more than two years old.",
    half_state: b"adl\x01NU\x07\x87",
  },
  {
    out: 0x46d81477U,
    inp: b"He who has a shady past knows that nice guys finish last.",
    half_state: b"adl\x01\x89\x8e\t\xe9",
  },
  {
    out: 0x40ee0ee1U,
    inp: b"I wouldn't marry him with a ten foot pole.",
    half_state: b"adl\x01R\t\x07g",
  },
  {
    out: 0x16661315U,
    inp: b"Free! Free!/A trip/to Mars/for 900/empty jars/Burma Shave",
    half_state: b"adl\x01\x7f\xbb\x09\x10",
  },
  {
    out: 0x5b2e1480U,
    inp: b"The days of the digital watch are numbered.  -Tom Stoppard",
    half_state: b"adl\x01\x99:\n~",
  },
  {
    out: 0x8c3c09eaU,
    inp: b"Nepal premier won't resign.",
    half_state: b"adl\x01\"\x05\x05\x05",
  },
  {
    out: 0x45ac18fdU,
    inp: b"For every action there is an equal and opposite government program.",
    half_state: b"adl\x01\xcc\xfa\x0c\x00",
  },
  {
    out: 0x53c61462U,
    inp: b"His money is twice tainted: 'taint yours and 'taint mine.",
    half_state: b"adl\x01\x93\xa9\n\b",
  },
  {
    out: 0x7e511e63U,
    inp: b"There is no reason for any individual to have a computer in their home. -Ken Olsen, 1977",
    half_state: b"adl\x01e\xf5\x10\x14",
  },
  {
    out: 0xe4801a6aU,
    inp: b"It's a tiny change to the code and not completely disgusting. - Bob Manchek",
    half_state: b"adl\x01\xee\x00\x0c\xb2",
  },
  {
    out: 0x61b507dfU,
    inp: b"size:  a.out:  bad magic",
    half_state: b"adl\x01\x1a\xfc\x04\x1d",
  },
  {
    out: 0xb8631171U,
    inp: b"The major problem is with sendmail.  -Mark Horton",
    half_state: b"adl\x01mi\b\xdc",
  },
  {
    out: 0x8b5e1904U,
    inp: b"Give me a rock, paper and scissors and I will move the world.  CCFestoon",
    half_state: b"adl\x01\xe3\n\x0c\x9f",
  },
  {
    out: 0x7cc6102bU,
    inp: b"If the enemy is within range, then so are you.",
    half_state: b"adl\x01_\xe0\b\x1e",
  },
  {
    out: 0x700318e7U,
    inp: b"It's well we cannot hear the screams/That we create in others' dreams.",
    half_state: b"adl\x01\xdb\x98\x0c\x87",
  },
  {
    out: 0x1e601747U,
    inp: b"You remind me of a TV show, but that's all right: I watch it anyway.",
    half_state: b"adl\x01\xcc}\x0b\x83",
  },
  {
    out: 0xb55b0b09U,
    inp: b"C is as portable as Stonehedge!!",
    half_state: b"adl\x01,^\x05\xad",
  },
  {
    out: 0x39111dd0U,
    inp: b"Even if I could be Shakespeare, I think I should still choose to be Faraday. - A. Huxley",
    half_state: b"adl\x01M\xd1\x0e\xc8",
  },
  {
    out: 0x91dd304fU,
    inp: b"The fugacity of a constituent in a mixture of gases at a given temperature is proportional to its mole fraction.  Lewis-Randall Rule",
    half_state: b"adl\x01#\xd8\x17\xd7",
  },
  {
    out: 0x2e5d1316U,
    inp: b"How can you write a big system without C++?  -Paul Glick",
    half_state: b"adl\x01\x8fU\n\x0f",
  },
  {
    out: 0xd0201df6U,
    inp: b"'Invariant assertions' is the most elegant programming technique!  -Tom Szymanski",
    half_state: b"adl\x01/\x98\x0e\xc4",
  },
  {
    out: 0x211297c8U,
    inp: brepeat(b"\xff", 5548, b"8"),
    half_state: b"adl\x01\x9a\xa6\xcb\xc1",
  },
  {
    out: 0xbaa198c8U,
    inp: brepeat(b"\xff", 5549, b"9"),
    half_state: b"adl\x01gu\xcc\xc0",
  },
  {
    out: 0x553499beU,
    inp: brepeat(b"\xff", 5550, b"0"),
    half_state: b"adl\x01gu\xcc\xc0",
  },
  {
    out: 0xf0c19abeU,
    inp: brepeat(b"\xff", 5551, b"1"),
    half_state: b"adl\x015C\xcd\xbf",
  },
  {
    out: 0x8d5c9bbeU,
    inp: brepeat(b"\xff", 5552, b"2"),
    half_state: b"adl\x015C\xcd\xbf",
  },
  {
    out: 0x2af69cbeU,
    inp: brepeat(b"\xff", 5553, b"3"),
    half_state: b"adl\x01\x04\x10\xce\xbe",
  },
  {
    out: 0xc9809dbeU,
    inp: brepeat(b"\xff", 5554, b"4"),
    half_state: b"adl\x01\x04\x10\xce\xbe",
  },
  {
    out: 0x69189ebeU,
    inp: brepeat(b"\xff", 5555, b"5"),
    half_state: b"adl\x01\xd3\xcd\xcf\xbd",
  },
  {
    out: 0x86af0001U,
    inp: brepeat(b"\x00", 100_000, b""),
    half_state: b"adl\x01\xc3P\x00\x01",
  },
  {
    out: 0x79660b4dU,
    inp: brepeat(b"a", 100_000, b""),
    half_state: b"adl\x01\x81k\x05\xa7",
  },
  {
    out: 0x110588eeU,
    inp: brepeat(b"ABCDEFGHIJKLMNOPQRSTUVWXYZ", 10_000, b""),
    half_state: b"adl\x01e\xd2\xc4p",
  },
]

///|
fn brepeat(b : Bytes, count : Int, append : Bytes) -> Bytes {
  let len = b.length() * count + append.length()
  let buf = FixedArray::makei(len, fn(i) {
    let n = i / b.length()
    if n < count {
      return b[i % b.length()]
    }
    append[i - count * b.length()]
  })
  Bytes::from_array(buf)
}

///|
/// MOD is the largest prime that is less than 65536.
const MOD = 65521U

///|
// slow_checksum is a slow but simple implementation of the Adler-32 checksum.
// It is a straight port of the sample code in RFC 1950 section 9.
fn slow_checksum(p : Slice[Byte]) -> UInt {
  let mut s1 = 1U
  let mut s2 = 0U
  for x in p {
    s1 = (s1 + x.to_uint()) % MOD
    s2 = (s2 + s1) % MOD
  }
  (s2 << 16) | s1
}

///|
suberror TestError {
  TestError(String)
}

///|
pub impl Show for TestError with output(self, logger) {
  let TestError(msg) = self
  logger.write_string(
    (
      $|TestError(\{msg.escape(quote=true)})
    ),
  )
}

///|
test "golden" {
  for i, g in golden {
    let p = Slice::new(g.inp.to_array())
    let got = slow_checksum(p)
    if got != g.out {
      raise TestError(
        "test #\{i+1}: simple implementation: checksum = \{got} want \{g.out}",
      )
      continue
    }
    let got = @adler32.checksum(p)
    if got != g.out {
      raise TestError(
        "test #\{i+1}: optimized implementation: checksum = \{got} want \{g.out}",
      )
      continue
    }
  }
}

///|
fn dump(b : Bytes) -> String {
  let arr = b.to_array().map(fn(b) { b.to_int() })
  to_repr(arr).to_string().replace_all(old=",", new="")
}

///|
test "golden marshal" {
  for i, g in golden {
    let h = @adler32.new()
    let h2 = @adler32.new()
    guard h.write(Slice::new(g.inp.to_array())[:g.inp.length() / 2])
      is (_, None)
    let (state, err) = h.marshal_binary()
    if err != None {
      raise TestError("could not marshal: \{err.unwrap().to_repr()}")
      continue
    }
    if state.to_bytes() != g.half_state {
      raise TestError(
        "test #\{i+1}: checksum half state = \{dump(state.to_bytes())}, want \{dump(g.half_state)}",
      )
      continue
    }
    let err = h2.unmarshal_binary(state)
    if err != None {
      raise TestError("could not unmarshal: \{err.unwrap().to_repr()}")
      continue
    }
    let s = Slice::new(g.inp.to_array())[g.inp.length() / 2:]
    guard h.write(s) is (_, None)
    guard h2.write(s) is (_, None)
    if h.sum32() != h2.sum32() {
      raise TestError("checksum = \{h.sum32()} != marshaled \{h2.sum32()}")
    }
  }
}

// func BenchmarkAdler32KB(b *testing.B) {
// 	b.SetBytes(1024)
// 	data := make(Slice[Byte], 1024)
// 	for i := range data {
// 		data[i] = byte(i)
// 	}
// 	h := New()
// 	in := make(Slice[Byte], 0, h.Size())

// 	b.ResetTimer()
// 	for i := 0; i < b.N; i++ {
// 		h.Reset()
// 		h.Write(data)
// 		h.Sum(in)
// 	}
// }
