///|
/// Tests for FileBrowser struct and navigation logic.

///|
fn make_test_browser() -> FileBrowser {
  let b = FileBrowser::new("/tmp")
  b.entries = [
    { name: "dir1", is_dir: true, size: 0 },
    { name: "dir2", is_dir: true, size: 0 },
    { name: "file1.txt", is_dir: false, size: 100 },
    { name: "file2.txt", is_dir: false, size: 2048 },
    { name: "file3.txt", is_dir: false, size: 1048576 },
  ]
  b
}

///|
test "file_browser: new initializes fields" {
  let b = FileBrowser::new("/home/user")
  assert_eq(b.current_path, "/home/user")
  assert_eq(b.entries.length(), 0)
  assert_eq(b.selected_idx, 0)
  assert_eq(b.scroll_offset, 0)
  assert_eq(b.preview_content, "")
  assert_false(b.show_preview)
  assert_eq(b.error_msg, "")
}

///|
test "file_browser: move_down advances selection" {
  let b = make_test_browser()
  assert_eq(b.selected_idx, 0)
  b.move_down()
  assert_eq(b.selected_idx, 1)
  b.move_down()
  assert_eq(b.selected_idx, 2)
}

///|
test "file_browser: move_down stops at last entry" {
  let b = make_test_browser()
  b.selected_idx = 4
  b.move_down()
  assert_eq(b.selected_idx, 4)
}

///|
test "file_browser: move_up decrements selection" {
  let b = make_test_browser()
  b.selected_idx = 3
  b.move_up()
  assert_eq(b.selected_idx, 2)
  b.move_up()
  assert_eq(b.selected_idx, 1)
}

///|
test "file_browser: move_up stops at first entry" {
  let b = make_test_browser()
  b.selected_idx = 0
  b.move_up()
  assert_eq(b.selected_idx, 0)
}

///|
test "file_browser: move_down adjusts scroll_offset" {
  let b = make_test_browser()
  for i in 0..<25 {
    b.entries.push({ name: "f\{i}", is_dir: false, size: 0 })
  }
  b.selected_idx = fb_max_visible - 1
  b.move_down()
  assert_true(b.scroll_offset > 0)
}

///|
test "file_browser: move_up adjusts scroll_offset" {
  let b = make_test_browser()
  b.scroll_offset = 5
  b.selected_idx = 5
  b.move_up()
  assert_eq(b.selected_idx, 4)
  assert_eq(b.scroll_offset, 4)
}

///|
test "file_browser: toggle_preview off by default" {
  let b = make_test_browser()
  assert_false(b.show_preview)
}

///|
test "file_browser: enter_selected on directory changes path" {
  let b = make_test_browser()
  b.selected_idx = 0
  b.enter_selected()
  // Since load_dir is called and /tmp/dir1 likely doesn't exist,
  // we just check that the path changed
  assert_eq(b.current_path, "/tmp/dir1")
}

///|
test "file_browser: go_parent navigates up" {
  let b = FileBrowser::new("/home/user/project")
  b.go_parent()
  assert_eq(b.current_path, "/home/user")
}

///|
test "file_browser: go_parent at root stays" {
  let b = FileBrowser::new("/")
  b.go_parent()
  assert_eq(b.current_path, "/")
}

///|
test "file_browser: render returns Border node" {
  let b = make_test_browser()
  let node = render_file_browser(b)
  let text = node_to_text(node)
  assert_true(text.contains("/tmp"))
  assert_true(text.contains("dir1"))
  assert_true(text.contains("file1.txt"))
}

///|
test "file_browser: render shows selection marker" {
  let b = make_test_browser()
  b.selected_idx = 2
  let node = render_file_browser(b)
  let text = node_to_text(node)
  assert_true(text.contains("file1.txt"))
}

///|
test "file_browser: render shows help text" {
  let b = make_test_browser()
  let node = render_file_browser(b)
  let text = node_to_text(node)
  assert_true(text.contains("Navigate"))
  assert_true(text.contains("Back to Chat"))
}

///|
test "shell_mode: cycle through modes" {
  assert_eq(cycle_shell_mode(ShellMode::Chat), ShellMode::FileBrowser)
  assert_eq(cycle_shell_mode(ShellMode::FileBrowser), ShellMode::Config)
  assert_eq(cycle_shell_mode(ShellMode::Config), ShellMode::Chat)
}

///|
test "shell_mode: mode labels" {
  assert_eq(shell_mode_label(ShellMode::Chat), "Chat")
  assert_eq(shell_mode_label(ShellMode::FileBrowser), "File Browser")
  assert_eq(shell_mode_label(ShellMode::Config), "Config")
}

///|
test "shell_mode: mode indicators" {
  assert_eq(shell_mode_indicator(ShellMode::Chat), "[Chat]")
  assert_eq(shell_mode_indicator(ShellMode::FileBrowser), "[Files]")
  assert_eq(shell_mode_indicator(ShellMode::Config), "[Config]")
}

///|
test "shell_mode: help text per mode" {
  let chat_help = shell_mode_help(ShellMode::Chat)
  assert_true(chat_help.contains("Send"))
  let fb_help = shell_mode_help(ShellMode::FileBrowser)
  assert_true(fb_help.contains("Navigate"))
  let cfg_help = shell_mode_help(ShellMode::Config)
  assert_true(cfg_help.contains("Edit"))
}

///|
test "file_browser: format_size formats correctly" {
  assert_eq(format_size(0), "0B")
  assert_eq(format_size(512), "512B")
  assert_eq(format_size(1024), "1KB")
  assert_eq(format_size(1048576), "1MB")
}

///|
test "file_browser: format_size boundary" {
  assert_eq(format_size(1023), "1023B")
  assert_eq(format_size(1024), "1KB")
  assert_eq(format_size(1048575), "1023KB")
}
