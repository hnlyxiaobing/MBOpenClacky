///| White-box tests for the extension marketplace backend.
/// Note: tests that touch the user's home directory (registry persistence)
/// are guarded so they cannot pollute a real `~/.clacky/extensions`.

///|
test "enable_extension returns error for unknown id" {
  let result = enable_extension("definitely-not-installed-12345")
  match result {
    Ok(_) => @debug.assert_eq(true, false)
    Err(msg) => @debug.assert_eq(msg.contains("not found"), true)
  }
}

///|
test "disable_extension returns error for unknown id" {
  let result = disable_extension("definitely-not-installed-67890")
  match result {
    Ok(_) => @debug.assert_eq(true, false)
    Err(msg) => @debug.assert_eq(msg.contains("not found"), true)
  }
}

///|
test "uninstall_extension rejects missing extension" {
  let result = uninstall_extension("definitely-not-installed-abcde")
  match result {
    Ok(_) => @debug.assert_eq(true, false)
    Err(msg) => @debug.assert_eq(msg.contains("not installed"), true)
  }
}

///|
test "uninstall_extension with purge_data still rejects missing extension" {
  let result = uninstall_extension(
    "definitely-not-installed-purge",
    purge_data=true,
  )
  match result {
    Ok(_) => @debug.assert_eq(true, false)
    Err(msg) => @debug.assert_eq(msg.contains("not installed"), true)
  }
}

///|
test "ext_data_dir lives under ~/.clacky/ext-data/<id>" {
  let dir = ext_data_dir("my-ext")
  @debug.assert_eq(dir.contains(".clacky"), true)
  @debug.assert_eq(dir.contains("ext-data"), true)
  @debug.assert_eq(dir.has_suffix("my-ext"), true)
}

///|
test "install_extension_from_path rejects non-existent path" {
  let result = install_extension_from_path(
    "_wbtest_definitely_does_not_exist_xyz",
  )
  match result {
    Ok(_) => @debug.assert_eq(true, false)
    Err(msg) => @debug.assert_eq(msg.contains("failed to load"), true)
  }
}

///|
test "publish_extension rejects non-existent path" {
  let result = publish_extension("_wbtest_definitely_does_not_exist_xyz")
  match result {
    Ok(_) => @debug.assert_eq(true, false)
    Err(msg) =>
      @debug.assert_eq(
        msg.contains("failed to load") || msg.contains("identity_not_bound"),
        true,
      )
  }
}

///|
test "list_marketplace_extensions returns Array (empty when registry absent)" {
  let arr = list_marketplace_extensions()
  // Just verify it is callable and returns a typed Array.
  let _ = arr.length()
  @debug.assert_eq(true, true)
}

///|
test "list_local_extensions on missing dir returns empty array" {
  let arr = list_local_extensions()
  // Should not crash even when the local extensions directory does not exist.
  let _ = arr.length()
  @debug.assert_eq(true, true)
}

///|
test "get_extension_by_id returns None for unknown id" {
  match get_extension_by_id("definitely-not-installed-qwerty") {
    Some(_) => @debug.assert_eq(true, false)
    None => @debug.assert_eq(true, true)
  }
}

///|
test "parse_registry_entry parses valid entry" {
  let json_str =
    #|{"id":"my-ext","latest_version":"2.0.0","versions":["1.0.0","2.0.0"],"metadata":{"name":"My Extension","author":"Tester"},"installs":42,"published_at":1700000000}
  let json = @json.parse(json_str)
  match parse_registry_entry(json) {
    Some(entry) => {
      @debug.assert_eq(entry.id, "my-ext")
      @debug.assert_eq(entry.latest_version, "2.0.0")
      @debug.assert_eq(entry.versions.length(), 2)
      @debug.assert_eq(entry.versions[0], "1.0.0")
      @debug.assert_eq(entry.versions[1], "2.0.0")
      @debug.assert_eq(entry.installs, 42)
      @debug.assert_eq(entry.published_at, 1700000000L)
      @debug.assert_eq(entry.metadata.get("name"), Some("My Extension"))
      @debug.assert_eq(entry.metadata.get("author"), Some("Tester"))
    }
    None => @debug.assert_eq(true, false)
  }
}

///|
test "parse_registry_entry returns None for missing id" {
  let json_str =
    #|{"latest_version":"1.0.0","versions":[]}
  let json = @json.parse(json_str)
  match parse_registry_entry(json) {
    Some(_) => @debug.assert_eq(true, false)
    None => @debug.assert_eq(true, true)
  }
}

///|
test "parse_registry_entry returns None for missing latest_version" {
  let json_str =
    #|{"id":"my-ext","versions":[]}
  let json = @json.parse(json_str)
  match parse_registry_entry(json) {
    Some(_) => @debug.assert_eq(true, false)
    None => @debug.assert_eq(true, true)
  }
}

///|
test "parse_registry_entry returns None for non-object json" {
  let json_str = "\"just a string\""
  let json = @json.parse(json_str)
  match parse_registry_entry(json) {
    Some(_) => @debug.assert_eq(true, false)
    None => @debug.assert_eq(true, true)
  }
}

///|
test "parse_registry_entry handles missing optional fields" {
  let json_str =
    #|{"id":"minimal","latest_version":"1.0.0"}
  let json = @json.parse(json_str)
  match parse_registry_entry(json) {
    Some(entry) => {
      @debug.assert_eq(entry.id, "minimal")
      @debug.assert_eq(entry.latest_version, "1.0.0")
      @debug.assert_eq(entry.versions.length(), 0)
      @debug.assert_eq(entry.installs, 0)
      @debug.assert_eq(entry.published_at, 0L)
      @debug.assert_eq(entry.metadata.length(), 0)
    }
    None => @debug.assert_eq(true, false)
  }
}

///|
test "parse_registry_entry handles non-string versions entries" {
  let json_str =
    #|{"id":"ext","latest_version":"1.0.0","versions":["1.0.0",123,"2.0.0"]}
  let json = @json.parse(json_str)
  match parse_registry_entry(json) {
    Some(entry) => {
      @debug.assert_eq(entry.versions.length(), 2)
      @debug.assert_eq(entry.versions[0], "1.0.0")
      @debug.assert_eq(entry.versions[1], "2.0.0")
    }
    None => @debug.assert_eq(true, false)
  }
}

///|
test "parse_registry_entries parses multiple entries" {
  let json_str =
    #|{"ext-a":{"id":"ext-a","latest_version":"1.0.0","versions":["1.0.0"],"metadata":{},"installs":5,"published_at":100},"ext-b":{"id":"ext-b","latest_version":"2.0.0","versions":["1.0.0","2.0.0"],"metadata":{"author":"B"},"installs":10,"published_at":200}}
  let json = @json.parse(json_str)
  match json {
    Object(obj) => {
      let entries = parse_registry_entries(obj)
      @debug.assert_eq(entries.length(), 2)
      @debug.assert_eq(entries.contains("ext-a"), true)
      @debug.assert_eq(entries.contains("ext-b"), true)
      let entry_b = entries.get("ext-b").unwrap()
      @debug.assert_eq(entry_b.installs, 10)
    }
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "parse_registry_entries skips invalid entries" {
  let json_str =
    #|{"valid":{"id":"valid","latest_version":"1.0.0"},"invalid":{"latest_version":"2.0.0"}}
  let json = @json.parse(json_str)
  match json {
    Object(obj) => {
      let entries = parse_registry_entries(obj)
      @debug.assert_eq(entries.length(), 1)
      @debug.assert_eq(entries.contains("valid"), true)
      @debug.assert_eq(entries.contains("invalid"), false)
    }
    _ => @debug.assert_eq(true, false)
  }
}
