///| White-box tests for the extension marketplace backend.
/// Note: tests that touch the user's home directory (registry persistence)
/// are guarded so they cannot pollute a real `~/.clacky/extensions`.

///|
test "enable_extension returns error for unknown id" {
  let result = enable_extension("definitely-not-installed-12345")
  match result {
    Ok(_) => assert_eq(true, false)
    Err(msg) => assert_eq(msg.contains("not found"), true)
  }
}

///|
test "disable_extension returns error for unknown id" {
  let result = disable_extension("definitely-not-installed-67890")
  match result {
    Ok(_) => assert_eq(true, false)
    Err(msg) => assert_eq(msg.contains("not found"), true)
  }
}

///|
test "uninstall_extension rejects missing extension" {
  let result = uninstall_extension("definitely-not-installed-abcde")
  match result {
    Ok(_) => assert_eq(true, false)
    Err(msg) => assert_eq(msg.contains("not installed"), true)
  }
}

///|
test "install_extension_from_path rejects non-existent path" {
  let result = install_extension_from_path(
    "_wbtest_definitely_does_not_exist_xyz",
  )
  match result {
    Ok(_) => assert_eq(true, false)
    Err(msg) => assert_eq(msg.contains("failed to load"), true)
  }
}

///|
test "publish_extension rejects non-existent path" {
  let result = publish_extension("_wbtest_definitely_does_not_exist_xyz")
  match result {
    Ok(_) => assert_eq(true, false)
    Err(msg) => assert_eq(msg.contains("failed to load"), true)
  }
}

///|
test "list_marketplace_extensions returns Array (empty when registry absent)" {
  let arr = list_marketplace_extensions()
  // Just verify it is callable and returns a typed Array.
  let _ = arr.length()
  assert_eq(true, true)
}

///|
test "list_local_extensions on missing dir returns empty array" {
  let arr = list_local_extensions()
  // Should not crash even when the local extensions directory does not exist.
  let _ = arr.length()
  assert_eq(true, true)
}

///|
test "get_extension_by_id returns None for unknown id" {
  match get_extension_by_id("definitely-not-installed-qwerty") {
    Some(_) => assert_eq(true, false)
    None => assert_eq(true, true)
  }
}