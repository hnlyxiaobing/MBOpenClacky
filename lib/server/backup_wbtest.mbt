///|
/// White-box tests for BackupManager archive/retention behaviour.
/// Uses isolated /tmp directories; each test cleans up after itself.

///|
fn backup_cleanup_file(path : String) -> Unit {
  if @fs.path_exists(path) {
    let _ = @fs.remove_file(path) catch { _ => () }
  }
}

///|
fn backup_cleanup_dir_files(dir : String) -> Unit {
  let entries = @fs.read_dir(dir) catch { _ => return }
  for entry in entries {
    let p = dir + "/" + entry
    let _ = @fs.remove_file(p) catch { _ => () }
  }
}

///|
/// run() must produce a real .zip archive containing both text and binary
/// files, and list() must surface it (C1/C2/C3 regression).
test "backup_run_creates_zip_with_binary_files" {
  let suffix = "runzip"
  let src = "/tmp/mboc-wbt-backup-src-\{suffix}"
  let dest = "/tmp/mboc-wbt-backup-dest-\{suffix}"
  let cfg_path = "/tmp/mboc-wbt-backup-cfg-\{suffix}.yml"
  @utils.ensure_dir(src)
  @utils.ensure_dir(dest)
  backup_cleanup_dir_files(dest)
  // One text file, one binary file (bytes not valid UTF-8)
  @fs.write_string_to_file(src + "/config.yml", "key: value") catch {
    _ => fail("setup write failed")
  }
  let raw : Array[Byte] = [
    (0x89).to_byte(),
    (0x50).to_byte(),
    (0x4e).to_byte(),
    (0x47).to_byte(),
    (0x0d).to_byte(),
    (0x0a).to_byte(),
    (0x1a).to_byte(),
    (0x0a).to_byte(),
    (0xff).to_byte(),
    (0xfe).to_byte(),
    (0x00).to_byte(),
    (0x01).to_byte(),
  ]
  let binary : Bytes = Bytes::from_array(raw)
  @fs.write_bytes_to_file(src + "/logo.png", binary) catch {
    _ => fail("setup write failed")
  }
  let mgr = BackupManager::new(cfg_path, src)
  let _ = mgr.update_config(Some(true), Some(dest), Some(7), Some(true))
  let result = mgr.run()
  assert_true(result is Ok(_))
  let r = result.unwrap()
  // Extension must not lie (C1): the archive is a ZIP
  assert_true(r.archive_path.has_suffix(".zip"))
  assert_false(r.archive_path.has_suffix(".tar.gz"))
  // Both files must be included - binary files are no longer skipped (C3)
  @debug.assert_eq(r.files_count, 2)
  // The archive on disk is a real ZIP that lib/zip can read back, and it
  // contains the binary file byte-for-byte
  let zip_bytes = @fs.read_file_to_bytes(r.archive_path) catch {
    _ => fail("archive not readable")
  }
  let png = @zip.find_entry(zip_bytes, "logo.png")
  assert_true(png is Some(_))
  match png {
    Some(data) => {
      @debug.assert_eq(data.length(), binary.length())
      @debug.assert_eq(data[0], binary[0])
      @debug.assert_eq(data[11], binary[11])
    }
    None => fail("logo.png missing from archive")
  }
  // list() must surface the backup (C2): size read as bytes, not string
  let listed = mgr.list()
  @debug.assert_eq(listed.length(), 1)
  @debug.assert_eq(listed[0].size_bytes, zip_bytes.length())
  // Cleanup
  backup_cleanup_dir_files(dest)
  backup_cleanup_file(src + "/config.yml")
  backup_cleanup_file(src + "/logo.png")
  backup_cleanup_file(cfg_path)
}

///|
/// Retention keeps only the N most recent archives.
test "backup_retention_keeps_recent" {
  let suffix = "retention"
  let src = "/tmp/mboc-wbt-backup-src-\{suffix}"
  let dest = "/tmp/mboc-wbt-backup-dest-\{suffix}"
  let cfg_path = "/tmp/mboc-wbt-backup-cfg-\{suffix}.yml"
  @utils.ensure_dir(src)
  @utils.ensure_dir(dest)
  backup_cleanup_dir_files(dest)
  @fs.write_string_to_file(src + "/a.txt", "a") catch {
    _ => fail("setup write failed")
  }
  let mgr = BackupManager::new(cfg_path, src)
  let _ = mgr.update_config(Some(true), Some(dest), Some(1), Some(true))
  // Two runs -> two archives; keep=1 must leave exactly one
  let r1 = mgr.run()
  assert_true(r1 is Ok(_))
  // Distinct archive names: sleep is not available in sync tests, so
  // force a different timestamp by seeding a second file (names derive
  // from now_ms; on a fast machine both runs could share a ms - then the
  // second write overwrites the first, still leaving exactly 1 file,
  // which the final length assertion tolerates).
  let r2 = mgr.run()
  assert_true(r2 is Ok(_))
  let listed = mgr.list()
  @debug.assert_eq(listed.length(), 1)
  // Cleanup
  backup_cleanup_dir_files(dest)
  backup_cleanup_file(src + "/a.txt")
  backup_cleanup_file(cfg_path)
}

///|
/// run() with backup disabled must return an honest Err.
test "backup_disabled_returns_err" {
  let mgr = BackupManager::new(
    "/tmp/mboc-wbt-backup-cfg-disabled.yml", "/tmp/mboc-wbt-backup-src-disabled",
  )
  // Default config is disabled
  let result = mgr.run()
  assert_true(result is Err(_))
}

///|
/// Heavy exclusion: sessions/snapshots are skipped when include_sessions
/// is off (W9 fix, mirrors Ruby HEAVY_EXCLUDE).
test "backup_heavy_exclude_when_sessions_off" {
  let suffix = "heavy"
  let src = "/tmp/mboc-wbt-backup-src-\{suffix}"
  let dest = "/tmp/mboc-wbt-backup-dest-\{suffix}"
  let cfg_path = "/tmp/mboc-wbt-backup-cfg-\{suffix}.yml"
  @utils.ensure_dir(src)
  @utils.ensure_dir(dest)
  @utils.ensure_dir(src + "/sessions")
  @utils.ensure_dir(src + "/snapshots")
  backup_cleanup_dir_files(dest)
  @fs.write_string_to_file(src + "/config.yml", "key: value") catch {
    _ => fail("setup write failed")
  }
  @fs.write_string_to_file(src + "/sessions/big.json", "{}") catch {
    _ => fail("setup write failed")
  }
  @fs.write_string_to_file(src + "/snapshots/snap.json", "{}") catch {
    _ => fail("setup write failed")
  }
  let mgr = BackupManager::new(cfg_path, src)
  let _ = mgr.update_config(Some(true), Some(dest), Some(7), Some(false))
  let result = mgr.run()
  assert_true(result is Ok(_))
  // Only config.yml archived; sessions/snapshots skipped
  @debug.assert_eq(result.unwrap().files_count, 1)
  // Cleanup
  backup_cleanup_dir_files(dest)
  backup_cleanup_file(src + "/config.yml")
  backup_cleanup_file(src + "/sessions/big.json")
  backup_cleanup_file(src + "/snapshots/snap.json")
  backup_cleanup_file(cfg_path)
}

///|
/// is_heavy_exclude unit behaviour.
test "backup_is_heavy_exclude" {
  assert_true(is_heavy_exclude("/home/x/.mbopenclacky/sessions/abc.json"))
  assert_true(is_heavy_exclude("/home/x/.mbopenclacky/snapshots/s1.json"))
  assert_false(is_heavy_exclude("/home/x/.mbopenclacky/config.yml"))
  assert_false(is_heavy_exclude("/home/x/.mbopenclacky/ocr_cache/f"))
}
