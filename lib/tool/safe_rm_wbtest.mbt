///| White-box tests for the safe-rm interception (safe_rm.mbt).
///
/// The interception sources the embedded safe_rm.sh before every Unix
/// terminal command and injects CLACKY_TRASH_DIR=<project_trash_dir(cwd)>
/// so `rm` moves files into the per-project trash instead of deleting
/// them. These tests exercise the full Tool::execute pipeline.

///|
/// Unique counter for per-test project dirs (concurrent async tests).
let safe_rm_wbtest_seq : @ref.Ref[Int] = @ref.Ref(0)

///|
/// Join two path components.
fn sr_join(a : String, b : String) -> String {
  @path.Path::join(@path.Path(a), @path.Path(b)).to_string()
}

///|
/// Run `f` with a fresh, per-test project dir; always cleans up.
async fn with_temp_project(f : async (String, String) -> Unit) -> Unit {
  let seq = safe_rm_wbtest_seq.val
  safe_rm_wbtest_seq.val = seq + 1
  let proj = sr_join(
    shell_temp_dir_pub(),
    "mb-saferm-project-" + seq.to_string(),
  )
  let trash = @utils.project_trash_dir(proj)
  sr_remove_recursive(proj)
  sr_remove_recursive(trash)
  @fs.create_dir(proj) catch {
    _ => ()
  }
  f(proj, trash)
  sr_remove_recursive(proj)
  sr_remove_recursive(trash)
}

///|
/// Remove a tree recursively (test cleanup helper).
fn sr_remove_recursive(path : String) -> Unit {
  let is_dir = @fs.is_dir(path) catch { _ => false }
  if is_dir {
    let names = @fs.read_dir(path) catch { _ => return }
    for name in names {
      sr_remove_recursive(sr_join(path, name))
    }
    let _ = @fs.remove_dir(path) catch { _ => () }
  } else {
    let _ = @fs.remove_file(path) catch { _ => () }
  }
}

///|
/// File existence check (is_file raises on missing).
fn sr_exists(path : String) -> Bool {
  @fs.is_file(path) catch {
    _ => false
  }
}

///|
/// safe_rm: `rm <file>` moves the file into the per-project trash with a
/// readable metadata sidecar, instead of deleting it.
async test "safe_rm: rm moves file into project trash" {
  // safe_rm.sh interception is Unix-only (bash/zsh); Windows has no
  // shell-function interception, so this behavior cannot be exercised.
  if is_windows_platform() {
    return
  }
  with_temp_project(async fn(proj, trash) {
    let target = sr_join(proj, "hello.txt")
    @fs.write_string_to_file(target, "hello world") catch {
      _ => ()
    }
    let tool = Terminal::new()
    let args : Map[String, Json] = {
      "command": ("rm '" + target + "'").to_json(),
      "cwd": proj.to_json(),
    }
    let result = tool.execute(args)
    assert_false(result.is_error)

    // Original file is gone from the project.
    assert_false(sr_exists(target))
    // Trash dir exists and holds exactly one entry + sidecar.
    let names = @fs.read_dir(trash) catch { _ => [] }
    let trash_files : Array[String] = names.filter(fn(n) {
      !n.has_suffix(".metadata.json")
    })
    assert_true(trash_files.length() >= 1)
    let entry_name = trash_files[0]
    assert_true(entry_name.has_prefix("hello.txt_deleted_"))

    // Sidecar is readable through the MB trash_directory reader.
    let entries = @utils.list_trash_entries(trash)
    assert_true(entries.length() >= 1)
    let entry = entries[0]
    assert_true(entry.original_path.has_suffix("hello.txt"))
  })
}

///|
/// safe_rm: CLACKY_TRASH_DIR is injected into the child env, pointing at
/// the per-project trash (Ruby spawn_shell semantics).
async test "safe_rm: CLACKY_TRASH_DIR injected" {
  if is_windows_platform() {
    return
  }
  with_temp_project(async fn(proj, trash) {
    let tool = Terminal::new()
    let args : Map[String, Json] = {
      "command": "echo $CLACKY_TRASH_DIR".to_json(),
      "cwd": proj.to_json(),
    }
    let result = tool.execute(args)
    assert_false(result.is_error)
    assert_true(result.content.contains(trash))
    assert_true(result.content.contains("exit_code: 0"))
  })
}

///|
/// safe_rm: catastrophic targets are refused (not deleted).
async test "safe_rm: dangerous target refused" {
  if is_windows_platform() {
    return
  }
  let tool = Terminal::new()
  let args : Map[String, Json] = {
    "command": "rm /".to_json(),
    "cwd": ".".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.contains("refused dangerous target"))
}

///|
/// safe_rm: `-f` suppresses "no such file" errors (exit 0).
async test "safe_rm: -f suppresses missing-file errors" {
  if is_windows_platform() {
    return
  }
  with_temp_project(async fn(proj, _trash) {
    let missing = sr_join(proj, "does-not-exist.txt")
    let tool = Terminal::new()
    let args : Map[String, Json] = {
      "command": ("rm -f '" + missing + "'").to_json(),
      "cwd": proj.to_json(),
    }
    let result = tool.execute(args)
    assert_false(result.is_error)
    assert_true(result.content.contains("exit_code: 0"))
  })
}

///|
/// safe_rm: `rm` without -f on a missing file reports an error (rc=1).
async test "safe_rm: missing file without -f errors" {
  if is_windows_platform() {
    return
  }
  with_temp_project(async fn(proj, _trash) {
    let missing = sr_join(proj, "nope.txt")
    let tool = Terminal::new()
    let args : Map[String, Json] = {
      "command": ("rm '" + missing + "'").to_json(),
      "cwd": proj.to_json(),
    }
    let result = tool.execute(args)
    assert_false(result.is_error)
    assert_true(result.content.contains("exit_code: 1"))
  })
}
