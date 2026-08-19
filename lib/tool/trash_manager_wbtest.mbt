///| White-box tests for trash_manager real filesystem behavior.

///|
test "format_bytes_zero" {
  assert_eq(format_bytes(0), "0 B")
}

///|
test "format_bytes_small" {
  assert_eq(format_bytes(1), "1 B")
  assert_eq(format_bytes(100), "100 B")
  assert_eq(format_bytes(512), "512 B")
  assert_eq(format_bytes(1023), "1023 B")
}

///|
test "format_bytes_exactly_1kb" {
  let result = format_bytes(1024)
  assert_eq(result, "1.0 KB")
}

///|
test "format_bytes_2kb" {
  let result = format_bytes(2048)
  assert_eq(result, "2.0 KB")
}

///|
test "format_bytes_1_5kb" {
  let result = format_bytes(1536)
  assert_eq(result, "1.5 KB")
}

///|
test "format_bytes_large_values" {
  let mb = format_bytes(1048576)
  assert_eq(mb, "1.0 MB")
}

///|
test "format_bytes_gb" {
  // 1.5 GiB — keep the literal within 32-bit Int range.
  let result = format_bytes(1536 * 1024 * 1024)
  assert_eq(result, "1.5 GB")
}

// ── Filesystem-level tests ────────────────────────────────────────────────
// These build a throwaway trash tree under the platform temp dir and run
// the real action handlers against it. The trash root is pointed at the
// temp dir by overriding CLACKY_CONFIG_DIR, which utils::config_dir reads.

///|
async test "list: empty trash dir" {
  with_temp_trash(fn(trash, _proj) raise {
    let result = list_deleted_files(trash, "")
    // Ruby reference returns success with an empty message for an empty trash.
    assert_false(result.is_error)
    assert_true(result.content.contains("Trash is empty"))
  })
}

///|
async test "list: single entry" {
  with_temp_trash(fn(trash, proj) raise {
    seed_trash_entry(trash, proj, "hello.txt", "2026-08-01T10:00:00Z")
    let result = list_deleted_files(trash, "")
    assert_false(result.is_error)
    assert_true(result.content.contains("hello.txt"))
    assert_true(result.content.contains("🗑️  Deleted Files:"))
  })
}

///|
async test "list: skips orphaned metadata" {
  with_temp_trash(fn(trash, proj) raise {
    seed_trash_entry(trash, proj, "alive.txt", "2026-08-01T10:00:00Z")
    // Orphan: metadata without a trash file — must be skipped.
    seed_trash_entry(trash, proj, "ghost.txt", "2026-07-01T00:00:00Z")
    @fs.remove_file(trash_path(trash, "ghost.txt")) catch {
      _ => ()
    }
    let result = list_deleted_files(trash, "")
    assert_false(result.is_error)
    assert_true(result.content.contains("alive.txt"))
    assert_false(result.content.contains("ghost.txt"))
  })
}

///|
async test "list: newest first ordering" {
  with_temp_trash(fn(trash, proj) raise {
    seed_trash_entry(trash, proj, "old.txt", "2026-01-01T00:00:00Z")
    seed_trash_entry(trash, proj, "new.txt", "2026-08-01T00:00:00Z")
    let result = list_deleted_files(trash, "")
    let entries = @utils.list_trash_entries(trash)
    assert_eq(entries.length(), 2)
    assert_eq(entries[0].original_path, new_original_path(proj, "new.txt"))
    assert_eq(entries[1].original_path, new_original_path(proj, "old.txt"))
    assert_true(result.content.contains("new.txt"))
  })
}

///|
async test "status: empty trash" {
  with_temp_trash(fn(trash, _proj) raise {
    let result = show_trash_status(trash, "")
    assert_false(result.is_error)
    assert_true(result.content.contains("Trash is empty"))
  })
}

///|
async test "status: summary with totals and grouping" {
  with_temp_trash(fn(trash, proj) raise {
    seed_trash_entry(trash, proj, "a.txt", "2026-08-01T10:00:00Z", size=100)
    seed_trash_entry(trash, proj, "b.txt", "2026-08-02T10:00:00Z", size=200)
    seed_trash_entry(trash, proj, "c.md", "2026-08-03T10:00:00Z", size=300)
    let result = show_trash_status(trash, "")
    assert_false(result.is_error)
    assert_true(result.content.contains("Files: 3"))
    assert_true(result.content.contains("Total size: 600 B"))
    assert_true(result.content.contains(".txt: 2 files"))
    assert_true(result.content.contains(".md: 1 files"))
    assert_true(result.content.contains("Recently deleted:"))
  })
}

///|
async test "restore: moves file back and removes metadata" {
  with_temp_trash(async fn(trash, proj) {
    seed_trash_entry(trash, proj, "hello.txt", "2026-08-01T10:00:00Z")
    // A real trashed file is gone from its original location; simulate that.
    @fs.remove_file(new_original_path(proj, "hello.txt")) catch {
      _ => ()
    }
    let result = restore_file(trash, new_original_path(proj, "hello.txt"), proj)
    assert_false(result.is_error)
    assert_true(result.content.contains("Successfully restored"))
    // Trash file and metadata gone; original restored.
    assert_false(@fs.path_exists(trash_path(trash, "hello.txt")))
    assert_false(
      @fs.path_exists(trash_path(trash, "hello.txt") + ".metadata.json"),
    )
    assert_true(@fs.path_exists(new_original_path(proj, "hello.txt")))
  })
}

///|
async test "restore: relative path resolves against project root" {
  with_temp_trash(async fn(trash, proj) {
    seed_trash_entry(trash, proj, "rel.txt", "2026-08-01T10:00:00Z")
    @fs.remove_file(new_original_path(proj, "rel.txt")) catch {
      _ => ()
    }
    let result = restore_file(trash, "rel.txt", proj)
    assert_false(result.is_error)
    assert_true(@fs.path_exists(new_original_path(proj, "rel.txt")))
  })
}

///|
async test "restore: target already exists fails" {
  with_temp_trash(async fn(trash, proj) {
    seed_trash_entry(trash, proj, "conflict.txt", "2026-08-01T10:00:00Z")
    @fs.write_string_to_file(
      new_original_path(proj, "conflict.txt"),
      "occupied",
    ) catch {
      _ => ()
    }
    let result = restore_file(
      trash,
      new_original_path(proj, "conflict.txt"),
      proj,
    )
    assert_true(result.is_error)
    assert_true(result.content.contains("already exists"))
  })
}

///|
async test "restore: unknown path suggests similar basename" {
  with_temp_trash(async fn(trash, proj) {
    seed_trash_entry(trash, proj, "report.txt", "2026-08-01T10:00:00Z")
    // Same basename but a different directory → exact path match fails,
    // basename suggestion kicks in (mirrors Ruby's File.basename ==).
    let result = restore_file(trash, "nested/report.txt", proj)
    assert_true(result.is_error)
    assert_true(result.content.contains("Did you mean one of these?"))
    assert_true(result.content.contains("report.txt"))
  })
}

///|
async test "restore: unknown path with no suggestion" {
  with_temp_trash(async fn(trash, proj) {
    seed_trash_entry(trash, proj, "report.txt", "2026-08-01T10:00:00Z")
    let result = restore_file(trash, "/nowhere/zzz.txt", proj)
    assert_true(result.is_error)
    assert_true(result.content.contains("Use trash_manager with action='list'"))
  })
}

///|
async test "empty: deletes only old files" {
  with_temp_trash(async fn(trash, proj) {
    seed_trash_entry(trash, proj, "old.txt", "2020-01-01T00:00:00Z")
    seed_trash_entry(trash, proj, "recent.txt", "2099-01-01T00:00:00Z")
    let result = empty_trash(trash, 7, "")
    assert_false(result.is_error)
    assert_true(result.content.contains("Permanently deleted 1 files"))
    assert_false(@fs.path_exists(trash_path(trash, "old.txt")))
    assert_true(@fs.path_exists(trash_path(trash, "recent.txt")))
  })
}

///|
async test "empty: nothing old" {
  with_temp_trash(async fn(trash, proj) {
    seed_trash_entry(trash, proj, "recent.txt", "2099-01-01T00:00:00Z")
    let result = empty_trash(trash, 7, "")
    assert_false(result.is_error)
    assert_true(result.content.contains("No files older than 7 days"))
  })
}

///|
test "help: contains actions" {
  let result = trash_help_text()
  assert_true(result.contains("list"))
  assert_true(result.contains("restore"))
  assert_true(result.contains("status"))
  assert_true(result.contains("empty"))
}

// ── Test scaffolding ───────────────────────────────────────────────────────

///|
/// Path to the temp trash dir used by the current test.

///|
/// Path to the fake project root used by the current test.

///|
/// Trash path for a seed file name.
fn trash_path(trash : String, name : String) -> String {
  @path.Path::join(@path.Path(trash), @path.Path(name)).to_string()
}

///|
/// The original path recorded in metadata for a seed file.
fn new_original_path(proj : String, name : String) -> String {
  @path.Path::join(@path.Path(proj), @path.Path(name)).to_string()
}

///|
/// Run `f` with a fresh temp trash dir; always cleans up afterwards.
let wbtest_seq : @ref.Ref[Int] = @ref.Ref(0)

///|
/// Run `f` with a fresh, per-test temp trash dir; always cleans up afterwards.
/// Each invocation gets a unique dir so concurrently-scheduled async tests
/// never share state.
async fn with_temp_trash(f : async (String, String) -> Unit) -> Unit {
  let seq = wbtest_seq.val
  wbtest_seq.val = seq + 1
  let trash = @path.Path::join(
    @path.Path(shell_temp_dir_pub()),
    @path.Path("mb-trash-wbtest-" + seq.to_string()),
  ).to_string()
  let proj = @path.Path::join(
    @path.Path(shell_temp_dir_pub()),
    @path.Path("mb-trash-project-wbtest-" + seq.to_string()),
  ).to_string()
  remove_recursive(trash)
  remove_recursive(proj)
  @fs.create_dir(trash) catch {
    _ => ()
  }
  @fs.create_dir(proj) catch {
    _ => ()
  }
  f(trash, proj)
  remove_recursive(trash)
  remove_recursive(proj)
}

///|
/// Remove a tree recursively (test cleanup helper).
fn remove_recursive(path : String) -> Unit {
  let is_dir = @fs.is_dir(path) catch { _ => false }
  if is_dir {
    let names = @fs.read_dir(path) catch { _ => return }
    for name in names {
      let full = @path.Path::join(path, @path.Path(name)).to_string()
      remove_recursive(full)
    }
    let _ = @fs.remove_dir(path) catch { _ => () }
  } else {
    let _ = @fs.remove_file(path) catch { _ => () }
  }
}

///|
/// Seed one trash entry: writes the trash file, the project copy (so
/// restore can move back), and the metadata sidecar.
fn seed_trash_entry(
  trash : String,
  proj : String,
  name : String,
  deleted_at : String,
  size? : Int = 0,
) -> Unit {
  let content = if size == 0 {
    "content of \{name}"
  } else {
    // Pad to the requested byte count.
    let pad : String = "x".repeat(size)
    pad
  }
  @fs.write_string_to_file(trash_path(trash, name), content) catch {
    _ => ()
  }
  @fs.write_string_to_file(new_original_path(proj, name), content) catch {
    _ => ()
  }
  let meta = "{\"original_path\":\"" +
    new_original_path(proj, name) +
    "\",\"trash_directory\":\"" +
    trash +
    "\",\"deleted_at\":\"" +
    deleted_at +
    "\",\"deleted_by\":\"wbtest\",\"file_size\":" +
    content.length().to_string() +
    ",\"file_type\":\"" +
    file_type_of(name) +
    "\",\"file_mode\":\"644\"}"
  @fs.write_string_to_file(
    trash_path(trash, name) + ".metadata.json",
    meta.to_string(),
  ) catch {
    _ => ()
  }
}

// ── Tool trait end-to-end (execute) tests ─────────────────────────────────
// These exercise the full Tool::execute pipeline through the real config
// trash location for the current working directory. Only our own seed files
// are created and removed; pre-existing trash contents are left untouched.

///|
async test "execute: list action via Tool trait" {
  let trash_dir = @utils.project_trash_dir(@utils.current_dir())
  ensure_dir(trash_dir)
  let seed_file = @path.Path::join(
    @path.Path(trash_dir),
    @path.Path("e2e-seed.txt"),
  ).to_string()
  let seed_meta = seed_file + ".metadata.json"
  @fs.write_string_to_file(seed_file, "e2e") catch {
    _ => ()
  }
  let meta = "{\"original_path\":\"/tmp/e2e-seed.txt\",\"trash_directory\":\"" +
    trash_dir +
    "\",\"deleted_at\":\"2026-08-01T10:00:00Z\",\"deleted_by\":\"wbtest\",\"file_size\":3,\"file_type\":\".txt\",\"file_mode\":\"644\"}"
  @fs.write_string_to_file(seed_meta, meta) catch {
    _ => ()
  }
  let tool = TrashManager::{  }
  let args : Map[String, Json] = { "action": "list".to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.contains("e2e-seed.txt"))
  @fs.remove_file(seed_file) catch {
    _ => ()
  }
  @fs.remove_file(seed_meta) catch {
    _ => ()
  }
}

///|
async test "execute: restore requires file_path" {
  let trash_dir = @utils.project_trash_dir(@utils.current_dir())
  ensure_dir(trash_dir)
  let tool = TrashManager::{  }
  let args : Map[String, Json] = { "action": "restore".to_json() }
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.contains("file_path"))
}

///|
async test "execute: help shows usage when trash exists" {
  let trash_dir = @utils.project_trash_dir(@utils.current_dir())
  ensure_dir(trash_dir)
  let tool = TrashManager::{  }
  let args : Map[String, Json] = { "action": "help".to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.contains("Trash Manager Help"))
  assert_true(result.content.contains("list"))
  assert_true(result.content.contains("restore"))
  assert_true(result.content.contains("status"))
  assert_true(result.content.contains("empty"))
}

///|
async test "execute: unknown action" {
  let trash_dir = @utils.project_trash_dir(@utils.current_dir())
  ensure_dir(trash_dir)
  let tool = TrashManager::{  }
  let args : Map[String, Json] = { "action": "unknown".to_json() }
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.contains("Unknown action"))
}
