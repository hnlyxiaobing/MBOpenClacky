///|
/// White-box tests for MediaOutputDir (ensure_exists / cleanup /
/// total_size) - W1/W2/W3 regression coverage.

///|
fn output_dir_cleanup(dir : String) -> Unit {
  if !@fs.path_exists(dir) {
    return
  }
  let entries = @fs.read_dir(dir) catch { _ => return }
  for entry in entries {
    let p = dir + "/" + entry
    let _ = @fs.remove_file(p) catch { _ => () }
  }
}

///|
test "output_dir_ensure_exists_creates_dir" {
  let base = "/tmp/mboc-wbt-media-exists"
  output_dir_cleanup(base + "/media")
  let dir = MediaOutputDir::new(base)
  let result = dir.ensure_exists()
  assert_true(result is Ok(_))
  let created = @fs.is_dir(dir.get_path()) catch { _ => false }
  assert_true(created)
  output_dir_cleanup(base + "/media")
}

///|
test "output_dir_ensure_exists_reports_failure" {
  // /proc/<x>/media cannot be created - ensure_exists must say so
  // instead of always returning Ok (W3).
  let dir = MediaOutputDir::new("/proc/mboc-wbt-media-impossible")
  let result = dir.ensure_exists()
  assert_true(result is Err(_))
}

///|
test "output_dir_total_size_counts_binary_bytes" {
  let base = "/tmp/mboc-wbt-media-size"
  let dir = MediaOutputDir::new(base)
  output_dir_cleanup(dir.get_path())
  let _ = dir.ensure_exists()
  // Write a binary file: 12 bytes, mostly invalid UTF-8
  let raw : Array[Byte] = [
    (0x89).to_byte(),
    (0xff).to_byte(),
    (0xfe).to_byte(),
    (0x00).to_byte(),
    (0x01).to_byte(),
    (0x02).to_byte(),
    (0x80).to_byte(),
    (0x81).to_byte(),
    (0x7f).to_byte(),
    (0x00).to_byte(),
    (0x0a).to_byte(),
    (0x0d).to_byte(),
  ]
  let binary : Bytes = Bytes::from_array(raw)
  @fs.write_bytes_to_file(dir.get_path() + "/blob.bin", binary) catch {
    _ => fail("setup write failed")
  }
  // W2: byte count, not UTF-8 code unit count
  @debug.assert_eq(dir.total_size(), 12L)
  output_dir_cleanup(dir.get_path())
}

///|
test "output_dir_cleanup_keeps_max_files" {
  let base = "/tmp/mboc-wbt-media-cleanup"
  let dir = MediaOutputDir::new(base)
  output_dir_cleanup(dir.get_path())
  let _ = dir.ensure_exists()
  // Create 5 files: media_1..media_5 (single digits keep the name sort
  // stable)
  for i = 1; i <= 5; i = i + 1 {
    let name = "media_\{i}.png"
    @fs.write_string_to_file(dir.get_path() + "/" + name, "x") catch {
      _ => fail("setup write failed")
    }
  }
  @debug.assert_eq(dir.list_files().length(), 5)
  // Keep at most 3: the 2 lowest-numbered files must go (W1: max_files
  // is a file-count cap, not an age in hours).
  let removed = dir.cleanup(3)
  @debug.assert_eq(removed, 2)
  let remaining = dir.list_files()
  @debug.assert_eq(remaining.length(), 3)
  // The newest (highest-counter) files survive
  assert_true(remaining[2].has_suffix("media_5.png"))
  output_dir_cleanup(dir.get_path())
}
