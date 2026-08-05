///|
/// Unit tests for OutputBuffer commit semantics (#2) and scrolling support (#3).

///|
test "commit_through commits the entry with the given id AND all earlier entries" {
  let buf = OutputBuffer::new()
  let id1 = buf.append(["a1"], OutputKind::Text)
  let id2 = buf.append(["a2"], OutputKind::Text)
  let id3 = buf.append(["a3"], OutputKind::Text)
  // Commit through the middle entry: id1 and id2 become committed, id3 stays live.
  buf.commit_through(id2)
  assert_true(buf.get_entry(id1).unwrap().is_committed())
  assert_true(buf.get_entry(id2).unwrap().is_committed())
  assert_true(buf.get_entry(id3).unwrap().is_live())
}

///|
test "commit_through with unknown id commits nothing" {
  let buf = OutputBuffer::new()
  let id1 = buf.append(["a1"], OutputKind::Text)
  buf.commit_through(9999)
  assert_true(buf.get_entry(id1).unwrap().is_live())
}

///|
test "commit_through only affects entries up to the id, later appends stay live" {
  let buf = OutputBuffer::new()
  let id1 = buf.append(["a1"], OutputKind::Text)
  buf.commit_through(id1)
  let id2 = buf.append(["a2"], OutputKind::Text)
  assert_true(buf.get_entry(id1).unwrap().is_committed())
  assert_true(buf.get_entry(id2).unwrap().is_live())
}

///|
test "last_entry_id tracks the newest entry and survives trimming" {
  let buf = OutputBuffer::new(max_entries=3)
  ignore(buf.append(["a1"], OutputKind::Text))
  let id2 = buf.append(["a2"], OutputKind::Text)
  assert_eq(buf.last_entry_id(), Some(id2))
  // Commit everything, then overflow max_entries to force trimming.
  match buf.last_entry_id() {
    Some(id) => buf.commit_through(id)
    None => ()
  }
  let id3 = buf.append(["a3"], OutputKind::Text)
  let id4 = buf.append(["a4"], OutputKind::Text)
  let id5 = buf.append(["a5"], OutputKind::Text)
  // Oldest committed entries trimmed; last id must still be the newest entry,
  // and entry_count() must NOT be used as an id.
  assert_eq(buf.last_entry_id(), Some(id5))
  assert_true(buf.entry_count() < id5)
  // Entries appended after the commit stay live...
  assert_true(buf.get_entry(id3).unwrap().is_live())
  assert_true(buf.get_entry(id4).unwrap().is_live())
  // ...and committing through the (trim-aware) last id commits everything.
  match buf.last_entry_id() {
    Some(id) => buf.commit_through(id)
    None => ()
  }
  assert_true(buf.get_entry(id3).unwrap().is_committed())
  assert_true(buf.get_entry(id4).unwrap().is_committed())
  assert_true(buf.get_entry(id5).unwrap().is_committed())
}

///|
test "commit_oldest_lines commits line-by-line from the oldest entry" {
  let buf = OutputBuffer::new()
  let id1 = buf.append(["a1", "a2", "a3"], OutputKind::Text)
  let id2 = buf.append(["b1", "b2"], OutputKind::Text)
  // Commit 4 lines: id1 fully (3 lines) + 1 line of id2.
  let committed = buf.commit_oldest_lines(4)
  assert_eq(committed, 4)
  assert_true(buf.get_entry(id1).unwrap().is_committed())
  let e2 = buf.get_entry(id2).unwrap()
  assert_true(e2.is_live())
  assert_eq(e2.live_lines(), ["b2"])
  // Entry with partial commit is no longer replaceable.
  assert_eq(buf.replace(id2, ["x"]), None)
}

///|
test "commit_oldest_lines caps at available uncommitted lines" {
  let buf = OutputBuffer::new()
  ignore(buf.append(["a1", "a2"], OutputKind::Text))
  let committed = buf.commit_oldest_lines(100)
  assert_eq(committed, 2)
  assert_eq(buf.total_live_lines(), 0)
}

///|
test "replace_live keeps committed prefix and replaces live suffix" {
  let buf = OutputBuffer::new()
  let id = buf.append(["l1", "l2", "l3", "l4"], OutputKind::Text)
  // Commit the first two lines (they scrolled into the terminal scrollback).
  ignore(buf.commit_oldest_lines(2))
  // Full replace is rejected for partially committed entries...
  assert_eq(buf.replace(id, ["l1", "l2", "l3-x", "l4", "l5"]), None)
  // ...but the live suffix can still be replaced (streaming growth).
  assert_true(buf.replace_live(id, ["l1", "l2", "l3-x", "l4", "l5"]))
  let entry = buf.get_entry(id).unwrap()
  assert_eq(entry.live_lines(), ["l3-x", "l4", "l5"])
  // Committed prefix kept verbatim.
  assert_eq(entry.committed_line_offset, 2)
  assert_eq(entry.line_count(), 5)
}

///|
test "replace_live fails when new content is shorter than the committed prefix" {
  let buf = OutputBuffer::new()
  let id = buf.append(["l1", "l2", "l3"], OutputKind::Text)
  ignore(buf.commit_oldest_lines(2))
  assert_true(!buf.replace_live(id, ["only"]))
  // Unknown id also fails.
  assert_true(!buf.replace_live(9999, ["a", "b", "c"]))
  // Entry untouched on failure.
  assert_eq(buf.get_entry(id).unwrap().live_lines(), ["l3"])
}

///|
test "live_display_lines excludes committed lines" {
  let buf = OutputBuffer::new()
  ignore(buf.append(["a1", "a2"], OutputKind::Text))
  ignore(buf.append(["b1", "b2"], OutputKind::Text))
  ignore(buf.commit_oldest_lines(3))
  assert_eq(buf.live_display_lines(), ["b2"])
}

///|
test "live_display_lines projects collapsed entries to 5 rows" {
  let buf = OutputBuffer::new()
  let lines : Array[String] = []
  for i in 1..<=20 {
    lines.push("sys\{i}")
  }
  // System entries above the collapse threshold auto-collapse on append.
  ignore(buf.append(lines, OutputKind::System))
  let display = buf.live_display_lines()
  assert_eq(display.length(), 5)
  assert_eq(display[0], "sys1")
  assert_eq(display[2], "sys3")
  assert_eq(display[4], "sys20")
}

///|
test "commit_oldest_display_lines commits collapsed entries whole" {
  let buf = OutputBuffer::new()
  ignore(buf.append(["a1", "a2"], OutputKind::Text))
  let lines : Array[String] = []
  for i in 1..<=20 {
    lines.push("sys\{i}")
  }
  let sys_id = buf.append(lines, OutputKind::System)
  ignore(buf.append(["z1"], OutputKind::Text))
  // Commit 4 display rows: a1, a2 (2 raw rows) + the collapsed entry's
  // 5-row projection, committed whole → returns 7, not 4.
  let committed = buf.commit_oldest_display_lines(4)
  assert_eq(committed, 7)
  assert_true(buf.get_entry(sys_id).unwrap().is_committed())
  assert_eq(buf.live_display_lines(), ["z1"])
}
