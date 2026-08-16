///| ZIP archive support for MBOpenClacky.
///
/// Pure MoonBit implementation of stored-only (method 0) ZIP archives.
/// Replaces the previous C FFI (miniz_zip.c) which was also stored-only.

///|
/// A ZIP archive entry with name and data.
pub(all) struct ZipEntry {
  name : String
  data : Bytes
} derive(Eq, Debug)

///|
pub extend ZipEntry with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ZipEntry with Eq::{not_equal, equal}

// ── CRC-32 (IEEE 802.3 polynomial, table-driven) ─────────────────────

///|
let crc32_table : FixedArray[UInt] = {
  let table : FixedArray[UInt] = FixedArray::make(256, 0U)
  for i = 0; i < 256; i = i + 1 {
    let mut c = i.reinterpret_as_uint()
    let mut j = 0
    while j < 8 {
      c = if (c & 1U) != 0U { 0xEDB88320U ^ (c >> 1) } else { c >> 1 }
      j = j + 1
    }
    table[i] = c
  }
  table
}

///|
fn crc32(data : Bytes) -> UInt {
  let mut crc = 0xFFFFFFFFU
  for i = 0; i < data.length(); i = i + 1 {
    let idx = ((crc ^ data[i].to_uint()) & 0xFFU).reinterpret_as_int()
    crc = crc32_table[idx] ^ (crc >> 8)
  }
  crc ^ 0xFFFFFFFFU
}

// ── Little-endian helpers ────────────────────────────────────────────

///|
fn write_le16(buf : Buffer, val : Int) -> Unit {
  buf.write_byte((val & 0xFF).to_byte())
  buf.write_byte(((val >> 8) & 0xFF).to_byte())
}

///|
fn write_le32(buf : Buffer, val : UInt) -> Unit {
  buf.write_byte((val & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((val >> 8) & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((val >> 16) & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((val >> 24) & 0xFFU).reinterpret_as_int().to_byte())
}

///|
fn read_le16(data : Bytes, offset : Int) -> Int {
  data[offset].to_int() | (data[offset + 1].to_int() << 8)
}

///|
fn read_le32(data : Bytes, offset : Int) -> UInt {
  data[offset].to_uint() |
  (data[offset + 1].to_uint() << 8) |
  (data[offset + 2].to_uint() << 16) |
  (data[offset + 3].to_uint() << 24)
}

// ── ZIP signatures ───────────────────────────────────────────────────

///|
let zip_local_sig : UInt = 0x04034B50U

///|
let zip_central_sig : UInt = 0x02014B50U

///|
let zip_end_sig : UInt = 0x06054B50U

// ── High-level API ───────────────────────────────────────────────────

///|
/// Create a ZIP archive from entries.
///
/// Returns the ZIP data as Bytes on success.
pub fn create_zip(entries : Array[ZipEntry]) -> Result[Bytes, String] {
  if entries.length() > 1024 {
    return Err("Too many entries (max 1024)")
  }

  let buf = Buffer()
  let central_entries : Array[(String, UInt, UInt, UInt, UInt)] = []

  for entry in entries {
    let name_bytes = @utf8.encode(entry.name)
    if name_bytes.length() > 256 {
      return Err("Entry name too long: " + entry.name)
    }
    let crc = crc32(entry.data)
    let local_offset = buf.length().reinterpret_as_uint()

    // Local File Header (30 bytes fixed + name)
    write_le32(buf, zip_local_sig)
    write_le16(buf, 20) // version needed
    write_le16(buf, 0) // flags
    write_le16(buf, 0) // compression (stored)
    write_le16(buf, 0) // mod time
    write_le16(buf, 0) // mod date
    write_le32(buf, crc)
    write_le32(buf, entry.data.length().reinterpret_as_uint())
    write_le32(buf, entry.data.length().reinterpret_as_uint())
    write_le16(buf, name_bytes.length())
    write_le16(buf, 0) // extra len
    buf.write_bytes(name_bytes)
    buf.write_bytes(entry.data)

    central_entries.push(
      (
        entry.name,
        crc,
        entry.data.length().reinterpret_as_uint(),
        local_offset,
        name_bytes.length().reinterpret_as_uint(),
      ),
    )
  }

  let cd_offset = buf.length().reinterpret_as_uint()

  // Central Directory
  for e in central_entries {
    let (name, crc, size, local_offset, name_len) = e
    let name_bytes = @utf8.encode(name)
    write_le32(buf, zip_central_sig)
    write_le16(buf, 20) // version made by
    write_le16(buf, 20) // version needed
    write_le16(buf, 0) // flags
    write_le16(buf, 0) // compression (stored)
    write_le16(buf, 0) // mod time
    write_le16(buf, 0) // mod date
    write_le32(buf, crc)
    write_le32(buf, size)
    write_le32(buf, size)
    write_le16(buf, name_len.reinterpret_as_int())
    write_le16(buf, 0) // extra len
    write_le16(buf, 0) // comment len
    write_le16(buf, 0) // disk start
    write_le16(buf, 0) // internal attr
    write_le32(buf, 0) // external attr
    write_le32(buf, local_offset)
    buf.write_bytes(name_bytes)
  }

  let cd_size = buf.length().reinterpret_as_uint() - cd_offset

  // End of Central Directory Record
  write_le32(buf, zip_end_sig)
  write_le16(buf, 0) // disk number
  write_le16(buf, 0) // disk with CD
  write_le16(buf, entries.length())
  write_le16(buf, entries.length())
  write_le32(buf, cd_size)
  write_le32(buf, cd_offset)
  write_le16(buf, 0) // comment len

  Ok(buf.to_bytes())
}

///|
/// Extract all entries from a ZIP archive.
///
/// Returns an array of ZipEntry on success.
pub fn extract_zip(zip_data : Bytes) -> Result[Array[ZipEntry], String] {
  if zip_data.length() < 22 {
    return Err("ZIP data too short")
  }

  // Find EOCD (scan backwards from end for signature)
  let mut eocd_offset = -1
  let max_scan = if zip_data.length() > 65557 {
    65557
  } else {
    zip_data.length()
  }
  for i = zip_data.length() - 22; i >= zip_data.length() - max_scan; i = i - 1 {
    if i >= 0 && read_le32(zip_data, i) == zip_end_sig {
      eocd_offset = i
      break
    }
  }
  if eocd_offset < 0 {
    return Err("Invalid ZIP: no end of central directory")
  }

  let cd_offset = read_le32(zip_data, eocd_offset + 16).reinterpret_as_int()
  let entry_count = read_le16(zip_data, eocd_offset + 10)

  let entries : Array[ZipEntry] = []
  let mut pos = cd_offset

  let mut i = 0
  while i < entry_count {
    if pos + 46 > zip_data.length() {
      return Err("Invalid ZIP: central directory truncated")
    }
    if read_le32(zip_data, pos) != zip_central_sig {
      return Err("Invalid ZIP: bad central directory signature")
    }

    let name_len = read_le16(zip_data, pos + 28)
    let extra_len = read_le16(zip_data, pos + 30)
    let comment_len = read_le16(zip_data, pos + 32)
    let local_offset = read_le32(zip_data, pos + 42).reinterpret_as_int()

    let name_start = pos + 46
    if name_start + name_len > zip_data.length() {
      return Err("Invalid ZIP: entry name truncated")
    }
    let name_bytes = zip_data[name_start:name_start + name_len].to_owned()
    let name = @utf8.decode_lossy(name_bytes)

    // Jump to Local File Header to find data
    if local_offset + 30 > zip_data.length() {
      return Err("Invalid ZIP: local header truncated")
    }
    if read_le32(zip_data, local_offset) != zip_local_sig {
      return Err("Invalid ZIP: bad local file signature")
    }

    let local_name_len = read_le16(zip_data, local_offset + 26)
    let local_extra_len = read_le16(zip_data, local_offset + 28)
    let data_offset = local_offset + 30 + local_name_len + local_extra_len
    let comp_size = read_le32(zip_data, local_offset + 18).reinterpret_as_int()
    let comp_method = read_le16(zip_data, local_offset + 8)

    if comp_method != 0 {
      return Err(
        "Unsupported ZIP compression method: " +
        comp_method.to_string() +
        " (only stored/method 0 supported)",
      )
    }

    if data_offset + comp_size > zip_data.length() {
      return Err("Invalid ZIP: entry data truncated")
    }

    let data = zip_data[data_offset:data_offset + comp_size].to_owned()
    entries.push({ name, data })

    pos = pos + 46 + name_len + extra_len + comment_len
    i = i + 1
  }

  Ok(entries)
}

///|
/// Find an entry by name in a ZIP archive.
///
/// Returns the entry data if found, None otherwise.
pub fn find_entry(zip_data : Bytes, target_name : String) -> Bytes? {
  match extract_zip(zip_data) {
    Ok(entries) => {
      for entry in entries {
        if entry.name == target_name {
          return Some(entry.data)
        }
      }
      None
    }
    Err(_) => None
  }
}
