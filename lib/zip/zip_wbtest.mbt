///| White-box tests for pure MoonBit ZIP implementation.

///|
test "crc32 known vector" {
  // "123456789" -> 0xCBF43926
  let data = @utf8.encode("123456789")
  let result = crc32(data)
  assert_eq(result, 0xCBF43926U)
}

///|
test "create_zip empty entries" {
  let entries : Array[ZipEntry] = []
  let result = create_zip(entries)
  match result {
    Ok(data) => {
      assert_true(data.length() >= 22)
      // Should be a valid ZIP with 0 entries
      let extracted = extract_zip(data)
      match extracted {
        Ok(es) => assert_eq(es.length(), 0)
        Err(e) => fail("extract_zip failed: " + e)
      }
    }
    Err(e) => fail("create_zip failed: " + e)
  }
}

///|
test "create_zip single entry" {
  let entries : Array[ZipEntry] = [
    { name: "hello.txt", data: @utf8.encode("world") },
  ]
  let result = create_zip(entries)
  match result {
    Ok(data) => {
      let extracted = extract_zip(data)
      match extracted {
        Ok(es) => {
          assert_eq(es.length(), 1)
          assert_eq(es[0].name, "hello.txt")
          assert_eq(es[0].data, @utf8.encode("world"))
        }
        Err(e) => fail("extract_zip failed: " + e)
      }
    }
    Err(e) => fail("create_zip failed: " + e)
  }
}

///|
test "create_zip multiple entries" {
  let entries : Array[ZipEntry] = [
    { name: "a.txt", data: @utf8.encode("alpha") },
    { name: "b.txt", data: @utf8.encode("beta") },
    { name: "c.txt", data: @utf8.encode("gamma") },
  ]
  let result = create_zip(entries)
  match result {
    Ok(data) => {
      let extracted = extract_zip(data)
      match extracted {
        Ok(es) => {
          assert_eq(es.length(), 3)
          assert_eq(es[0].name, "a.txt")
          assert_eq(es[1].name, "b.txt")
          assert_eq(es[2].name, "c.txt")
        }
        Err(e) => fail("extract_zip failed: " + e)
      }
    }
    Err(e) => fail("create_zip failed: " + e)
  }
}

///|
test "find_entry found" {
  let entries : Array[ZipEntry] = [
    { name: "target.txt", data: @utf8.encode("found me") },
  ]
  let zip_data = create_zip(entries).unwrap()
  let result = find_entry(zip_data, "target.txt")
  assert_eq(result, Some(@utf8.encode("found me")))
}

///|
test "find_entry not found" {
  let entries : Array[ZipEntry] = [
    { name: "other.txt", data: @utf8.encode("not me") },
  ]
  let zip_data = create_zip(entries).unwrap()
  let result = find_entry(zip_data, "missing.txt")
  assert_eq(result, None)
}

///|
test "extract_zip rejects method 8" {
  // Build a minimal ZIP with compression method 8 manually
  let buf = Buffer()
  let name = @utf8.encode("x")
  let data = @utf8.encode("y")
  let crc = crc32(data)

  // Local header with method 8
  write_le32(buf, zip_local_sig)
  write_le16(buf, 20)
  write_le16(buf, 0)
  write_le16(buf, 8) // method 8 = deflate
  write_le16(buf, 0)
  write_le16(buf, 0)
  write_le32(buf, crc)
  write_le32(buf, data.length().reinterpret_as_uint())
  write_le32(buf, data.length().reinterpret_as_uint())
  write_le16(buf, name.length())
  write_le16(buf, 0)
  buf.write_bytes(name)
  buf.write_bytes(data)

  let cd_offset = buf.length().reinterpret_as_uint()

  // Central directory
  write_le32(buf, zip_central_sig)
  write_le16(buf, 20)
  write_le16(buf, 20)
  write_le16(buf, 0)
  write_le16(buf, 8) // method 8
  write_le16(buf, 0)
  write_le16(buf, 0)
  write_le32(buf, crc)
  write_le32(buf, data.length().reinterpret_as_uint())
  write_le32(buf, data.length().reinterpret_as_uint())
  write_le16(buf, name.length())
  write_le16(buf, 0)
  write_le16(buf, 0)
  write_le16(buf, 0)
  write_le16(buf, 0)
  write_le32(buf, 0)
  write_le32(buf, 0)
  buf.write_bytes(name)

  let cd_size = buf.length().reinterpret_as_uint() - cd_offset

  // EOCD
  write_le32(buf, zip_end_sig)
  write_le16(buf, 0)
  write_le16(buf, 0)
  write_le16(buf, 1)
  write_le16(buf, 1)
  write_le32(buf, cd_size)
  write_le32(buf, cd_offset)
  write_le16(buf, 0)

  let zip_data = buf.to_bytes()
  let result = extract_zip(zip_data)
  match result {
    Ok(_) => fail("should have rejected method 8")
    Err(e) => assert_true(e.contains("Unsupported ZIP compression method"))
  }
}

///|
test "roundtrip binary data" {
  let binary : Array[Byte] = []
  for i = 0; i < 256; i = i + 1 {
    binary.push(i.to_byte())
  }
  let data = Bytes::from_array(binary)
  let entries : Array[ZipEntry] = [{ name: "bin.dat", data }]
  let zip_data = create_zip(entries).unwrap()
  let extracted = extract_zip(zip_data).unwrap()
  assert_eq(extracted.length(), 1)
  assert_eq(extracted[0].data, data)
}
