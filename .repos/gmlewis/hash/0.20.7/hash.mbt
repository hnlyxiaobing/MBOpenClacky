///|
/// This file is based on the Go implementation found here:
/// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/hash/hash.go;l=26
/// which has the copyright notice:
/// Copyright 2009 The Go Authors. All rights reserved.
/// Use of this source code is governed by a BSD-style
/// license that can be found in the LICENSE file.
///
/// Package hash provides interfaces for hash functions.
using @io {type Slice}

///|
using @io {type IOError}

///|
/// Hash is the common interface implemented by all hash functions.
///
/// Hash implementations in the standard library (e.g. [hash/crc32] and
/// [crypto/sha256]) implement the [encoding.BinaryMarshaler] and
/// [encoding.BinaryUnmarshaler] interfaces. Marshaling a hash implementation
/// allows its internal state to be saved and used for additional processing
/// later, without having to re-write the data previously written to the hash.
/// The hash state may contain portions of the input in its original form,
/// which users are expected to handle for any possible security implications.
///
/// Compatibility: Any future changes to hash or crypto packages will endeavor
/// to maintain compatibility with state encoded using previous versions.
/// That is, any released versions of the packages should be able to
/// decode data written with any previously released version,
/// subject to issues such as security fixes.
/// See the Go compatibility document for background: https://golang.org/doc/go1compat
pub(open) trait Hash {
  /// Write (via the embedded io.Writer interface) adds more data to the running hash.
  /// It never returns an error.
  /// @io.Writer
  write(Self, Slice[Byte]) -> (Int, IOError?)

  /// sum appends the current hash to b and returns the resulting slice.
  /// It does not change the underlying hash state.
  sum(Self, Slice[Byte]) -> Slice[Byte]

  /// reset resets the Hash to its initial state.
  reset(Self) -> Unit

  /// size returns the number of bytes sum will return.
  size(Self) -> Int

  /// block_size returns the hash's underlying block size.
  /// The Write method must be able to accept any amount
  /// of data, but it may operate more efficiently if all writes
  /// are a multiple of the block size.
  block_size(Self) -> Int
}

///|
/// Hash32 is the common interface implemented by all 32-bit hash functions.
pub(open) trait Hash32 {
  sum32(Self) -> UInt
  // Hash
  write(Self, Slice[Byte]) -> (Int, IOError?)
  sum(Self, Slice[Byte]) -> Slice[Byte]
  reset(Self) -> Unit
  size(Self) -> Int
  block_size(Self) -> Int
}

///|
/// Hash64 is the common interface implemented by all 64-bit hash functions.
pub(open) trait Hash64 {
  sum64() -> UInt64
  // Hash
  write(Self, Slice[Byte]) -> (Int, IOError?)
  sum(Self, Slice[Byte]) -> Slice[Byte]
  reset(Self) -> Unit
  size(Self) -> Int
  block_size(Self) -> Int
}
