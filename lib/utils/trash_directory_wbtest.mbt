///| White-box tests for trash_directory.mbt pure functions.

///|
test "trash_filename: inserts timestamp before extension" {
  let result = trash_filename("file.txt", "2024-01-15T10:30:00Z")
  assert_eq(result, "file_20240115_103000Z.txt")
}

///|
test "trash_filename: handles path with directories" {
  let result = trash_filename("/home/user/doc.pdf", "2024-01-15T10:30:00Z")
  assert_eq(result, "doc_20240115_103000Z.pdf")
}

///|
test "trash_filename: handles windows path" {
  let result = trash_filename(
    "C:\\Users\\test\\image.png", "2024-06-01T12:00:00Z",
  )
  assert_eq(result, "image_20240601_120000Z.png")
}

///|
test "trash_filename: empty timestamp returns basename unchanged" {
  let result = trash_filename("file.txt", "")
  assert_eq(result, "file.txt")
}

///|
test "trash_filename: no extension appends timestamp" {
  let result = trash_filename("noext", "2024-01-15T10:30:00Z")
  assert_eq(result, "noext_20240115_103000Z")
}

///|
test "trash_filename: hidden file gets timestamp appended" {
  let result = trash_filename(".hidden", "2024-01-15T10:30:00Z")
  assert_eq(result, ".hidden_20240115_103000Z")
}

///|
test "trash_filename: multiple dots uses last dot" {
  let result = trash_filename("archive.tar.gz", "2024-01-15T10:30:00Z")
  assert_eq(result, "archive.tar_20240115_103000Z.gz")
}

///|
test "find_in_trash: matches original_path" {
  let entries = [
    {
      original_path: "/home/user/test_file.txt",
      trash_path: "/trash/test_file_123.txt",
      deleted_at: "2024-01-01T00:00:00Z",
      size_bytes: 100,
    },
    {
      original_path: "/home/user/other.txt",
      trash_path: "/trash/other_456.txt",
      deleted_at: "2024-01-02T00:00:00Z",
      size_bytes: 200,
    },
  ]
  let results = find_in_trash(entries, "test_file")
  assert_eq(results.length(), 1)
  assert_eq(results[0].original_path, "/home/user/test_file.txt")
}

///|
test "find_in_trash: matches trash_path" {
  let entries = [
    {
      original_path: "/home/user/doc.txt",
      trash_path: "/trash/special_999.txt",
      deleted_at: "2024-01-01T00:00:00Z",
      size_bytes: 50,
    },
  ]
  let results = find_in_trash(entries, "special")
  assert_eq(results.length(), 1)
}

///|
test "find_in_trash: no match returns empty" {
  let entries = [
    {
      original_path: "/home/user/a.txt",
      trash_path: "/trash/a.txt",
      deleted_at: "2024-01-01T00:00:00Z",
      size_bytes: 10,
    },
  ]
  let results = find_in_trash(entries, "nonexistent")
  assert_eq(results.length(), 0)
}

///|
test "find_in_trash: multiple matches" {
  let entries = [
    {
      original_path: "/home/user/report.txt",
      trash_path: "/trash/report_1.txt",
      deleted_at: "2024-01-01T00:00:00Z",
      size_bytes: 100,
    },
    {
      original_path: "/home/user/report_v2.txt",
      trash_path: "/trash/report_2.txt",
      deleted_at: "2024-01-02T00:00:00Z",
      size_bytes: 200,
    },
  ]
  let results = find_in_trash(entries, "report")
  assert_eq(results.length(), 2)
}

///|
test "find_in_trash: empty entries returns empty" {
  let entries : Array[TrashEntry] = []
  let results = find_in_trash(entries, "anything")
  assert_eq(results.length(), 0)
}

///|
test "expired_entries: filters old entries" {
  let entries = [
    {
      original_path: "/old.txt",
      trash_path: "/trash/old.txt",
      deleted_at: "2024-05-01T00:00:00Z",
      size_bytes: 10,
    },
    {
      original_path: "/recent.txt",
      trash_path: "/trash/recent.txt",
      deleted_at: "2024-06-01T00:00:00Z",
      size_bytes: 20,
    },
  ]
  let results = expired_entries(entries, 30, "2024-06-15")
  assert_eq(results.length(), 1)
  assert_eq(results[0].original_path, "/old.txt")
}

///|
test "expired_entries: none expired returns empty" {
  let entries = [
    {
      original_path: "/a.txt",
      trash_path: "/trash/a.txt",
      deleted_at: "2024-06-14T00:00:00Z",
      size_bytes: 10,
    },
  ]
  let results = expired_entries(entries, 30, "2024-06-15")
  assert_eq(results.length(), 0)
}

///|
test "expired_entries: cutoff boundary is exclusive" {
  let entries = [
    {
      original_path: "/boundary.txt",
      trash_path: "/trash/boundary.txt",
      deleted_at: "2024-05-16T00:00:00Z",
      size_bytes: 10,
    },
  ]
  let results = expired_entries(entries, 30, "2024-06-15")
  assert_eq(results.length(), 0)
}

///|
test "expired_entries: year rollback" {
  let entries = [
    {
      original_path: "/old.txt",
      trash_path: "/trash/old.txt",
      deleted_at: "2023-12-30T00:00:00Z",
      size_bytes: 10,
    },
  ]
  let results = expired_entries(entries, 1, "2024-01-01")
  assert_eq(results.length(), 1)
}

///|
test "expired_entries: one day expiry" {
  let entries = [
    {
      original_path: "/day_old.txt",
      trash_path: "/trash/day_old.txt",
      deleted_at: "2024-02-27T00:00:00Z",
      size_bytes: 10,
    },
  ]
  let results = expired_entries(entries, 1, "2024-03-01")
  assert_eq(results.length(), 1)
}

///|
test "format_trash_summary: empty entries" {
  let entries : Array[TrashEntry] = []
  let result = format_trash_summary(entries)
  assert_eq(result, "Trash is empty.")
}

///|
test "format_trash_summary: single entry" {
  let entries = [
    {
      original_path: "/file.txt",
      trash_path: "/trash/file.txt",
      deleted_at: "2024-01-01T00:00:00Z",
      size_bytes: 512,
    },
  ]
  let result = format_trash_summary(entries)
  assert_eq(result, "Trash: 1 item(s), 512 bytes total")
}

///|
test "format_trash_summary: multiple entries sums bytes" {
  let entries = [
    {
      original_path: "/a.txt",
      trash_path: "/trash/a.txt",
      deleted_at: "2024-01-01T00:00:00Z",
      size_bytes: 100,
    },
    {
      original_path: "/b.txt",
      trash_path: "/trash/b.txt",
      deleted_at: "2024-01-02T00:00:00Z",
      size_bytes: 200,
    },
  ]
  let result = format_trash_summary(entries)
  assert_eq(result, "Trash: 2 item(s), 300 bytes total")
}

///|
test "create_trash_entry: with timestamp" {
  let entry = create_trash_entry(
    "/home/user/file.txt",
    timestamp="2024-01-15T10:30:00Z",
  )
  assert_eq(entry.original_path, "/home/user/file.txt")
  assert_eq(entry.deleted_at, "2024-01-15T10:30:00Z")
  assert_eq(entry.size_bytes, 0)
  assert_true(entry.trash_path.contains("file_20240115_103000Z.txt"))
}

///|
test "create_trash_entry: without timestamp uses epoch default" {
  let entry = create_trash_entry("/home/user/doc.pdf")
  assert_eq(entry.original_path, "/home/user/doc.pdf")
  assert_eq(entry.deleted_at, "1970-01-01T00:00:00Z")
  assert_eq(entry.size_bytes, 0)
  assert_true(entry.trash_path.contains("doc_19700101_000000Z.pdf"))
}

///|
test "create_trash_entry: trash_path contains trash dir" {
  let entry = create_trash_entry("test.txt", timestamp="2024-06-01T00:00:00Z")
  assert_true(entry.trash_path.contains("trash"))
  assert_true(entry.trash_path.contains("test_20240601_000000Z.txt"))
}

///|
test "TrashEntry: to_json and from_json roundtrip" {
  let entry : TrashEntry = {
    original_path: "/home/file.txt",
    trash_path: "/trash/file_123.txt",
    deleted_at: "2024-01-01T00:00:00Z",
    size_bytes: 1024,
  }
  let json = entry.to_json()
  let parsed : TrashEntry = @json.from_json(json)
  assert_eq(parsed, entry)
}
