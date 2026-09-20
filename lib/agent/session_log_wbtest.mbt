///| White-box tests for the append-only JSONL session log (P1-2).
///
/// These cover the delivery criteria directly:
/// - a log can be replayed offline (read + project)
/// - truncating the tail still recovers every complete record
/// - compaction appends a summary and leaves the original bytes untouched
/// - the advisory lock behaves and reports stale recovery
/// - legacy whole-JSON sessions project to read-only records

///|
fn sl_log_path(name : String) -> String {
  let dir = "_build/session_log_wbtest"
  ignore(@fs.create_dir(dir) catch { _ => () })
  @path.Path::join(dir, @path.Path(name)).to_string()
}

///|
fn sl_cleanup(path : String) -> Unit {
  @fs.remove_file(path) catch {
    _ => ()
  }
  @fs.remove_file(session_lock_path(path)) catch {
    _ => ()
  }
}

///|
fn sl_progress(phase : String) -> @protocol.Event {
  @protocol.Progress({
    phase,
    message: None,
    progress_type: None,
    metadata: None,
    started_at: None,
  })
}

///|
fn sl_info(message : String) -> @protocol.Event {
  @protocol.Info({ message, })
}

///|
async test "session log: create, append and read roundtrip" {
  let path = sl_log_path("roundtrip.jsonl")
  sl_cleanup(path)
  match create_session_log(path, "sess-1", "2026-09-21T00:00:00+08:00") {
    Ok(_) => ()
    Err(err) => fail("create failed: " + err)
  }
  let seq1 = match append_event(path, sl_progress("active"), 1000L) {
    Ok(seq) => seq
    Err(err) => fail("append failed: " + err)
  }
  let seq2 = match append_event(path, sl_info("hello"), 2000L) {
    Ok(seq) => seq
    Err(err) => fail("append failed: " + err)
  }
  assert_eq(seq1, 1)
  assert_eq(seq2, 2)
  let log = read_session_log(path)
  assert_true(log.header is Some(_))
  assert_eq(log.records.length(), 2)
  assert_eq(log.max_seq(), 2)
  assert_false(log.truncated_tail)
  assert_eq(log.malformed_lines, 0)
  match log.header {
    Some(header) => {
      assert_eq(header.version, session_log_version)
      assert_eq(header.session_id, "sess-1")
    }
    None => fail("missing header")
  }
  // Records are in file order with continuous sequence numbers.
  match log.records[0] {
    EventRecord(event) => {
      assert_eq(event.seq, 1)
      assert_eq(event.unix_ms, 1000L)
      assert_eq(event.event.type_name(), "progress")
    }
    SummaryRecord(_) => fail("expected an event record")
  }
  match log.records[1] {
    EventRecord(event) => assert_eq(event.event.type_name(), "info")
    SummaryRecord(_) => fail("expected an event record")
  }
  // The log file is JSONL: one header + one line per record.
  let lines = @fs.read_file_to_string(path).split("\n").collect()
  let mut non_empty = 0
  for line in lines {
    if line.trim().length() > 0 {
      non_empty = non_empty + 1
    }
  }
  assert_eq(non_empty, 3)
  sl_cleanup(path)
}

///|
async test "session log: truncated tail recovers complete records" {
  let path = sl_log_path("truncated.jsonl")
  sl_cleanup(path)
  ignore(create_session_log(path, "sess-2", "2026-09-21T00:00:00+08:00"))
  ignore(append_event(path, sl_progress("active"), 1000L))
  ignore(append_event(path, sl_progress("done"), 2000L))
  ignore(append_event(path, sl_info("third"), 3000L))
  let content = @fs.read_file_to_string(path)
  // Simulate a torn write: cut the last record mid-JSON.
  let cut = content.length() - 6
  @fs.write_string_to_file(path, content[:cut].to_owned())
  let log = read_session_log(path)
  assert_true(log.truncated_tail)
  assert_eq(log.records.length(), 2)
  assert_eq(log.max_seq(), 2)
  // Appending after a torn tail continues the sequence without collision.
  let next = match append_event(path, sl_info("fourth"), 4000L) {
    Ok(seq) => seq
    Err(err) => fail("append after truncation failed: " + err)
  }
  assert_eq(next, 3)
  let repaired = read_session_log(path)
  assert_eq(repaired.records.length(), 3)
  sl_cleanup(path)
}

///|
async test "session log: compaction appends and preserves original bytes" {
  let path = sl_log_path("compaction.jsonl")
  sl_cleanup(path)
  ignore(create_session_log(path, "sess-3", "2026-09-21T00:00:00+08:00"))
  ignore(append_event(path, sl_progress("active"), 1000L))
  ignore(append_event(path, sl_progress("done"), 2000L))
  ignore(append_event(path, sl_info("kept"), 3000L))
  let before = @fs.read_file_to_string(path)
  let summary_seq = match append_summary(path, 1, 2, 4000L) {
    Ok(seq) => seq
    Err(err) => fail("append_summary failed: " + err)
  }
  assert_eq(summary_seq, 4)
  let after = @fs.read_file_to_string(path)
  // The original bytes are an unchanged prefix of the new file.
  assert_true(after.has_prefix(before))
  let log = read_session_log(path)
  // Originals are all still in the file...
  assert_eq(log.records.length(), 4)
  // ...but the projection skips the two superseded events.
  let projected = log.project()
  assert_eq(projected.length(), 2)
  match projected[0] {
    EventRecord(event) => {
      assert_eq(event.seq, 3)
      assert_eq(event.event.type_name(), "info")
    }
    SummaryRecord(_) => fail("expected the surviving event first")
  }
  match projected[1] {
    SummaryRecord(summary) => {
      assert_eq(summary.from_seq, 1)
      assert_eq(summary.to_seq, 2)
    }
    EventRecord(_) => fail("expected the summary record")
  }
  sl_cleanup(path)
}

///|
async test "session log: advisory lock acquisition and stale recovery" {
  let path = sl_log_path("lock.jsonl")
  sl_cleanup(path)
  let lock_path = session_lock_path(path)
  let first = match acquire_session_lock(lock_path) {
    Ok(lock) => lock
    Err(err) => fail("first lock failed: " + err)
  }
  assert_false(first.recovered_stale)
  first.release()
  // The lock file survives the release, so the next acquisition reports that
  // it recovered a lock left behind by an earlier holder.
  let second = match acquire_session_lock(lock_path) {
    Ok(lock) => lock
    Err(err) => fail("second lock failed: " + err)
  }
  assert_true(second.recovered_stale)
  second.release()
  sl_cleanup(path)
}

///|
test "session log: legacy JSON projects to read-only records" {
  let empty = legacy_session_records(ss_make_session("legacy-1", "Legacy"))
  assert_true(empty.header is Some(_))
  assert_eq(empty.records.length(), 0)
  let data : SessionData = {
    ..ss_make_session("legacy-2", "Legacy with messages"),
    messages: [
      @message.Message::user("hello"),
      @message.Message::assistant("hi"),
    ],
  }
  let log = legacy_session_records(data)
  assert_eq(log.records.length(), 2)
  match log.header {
    Some(header) => assert_eq(header.session_id, "legacy-2")
    None => fail("missing legacy header")
  }
  match log.records[0] {
    EventRecord(event) => {
      assert_eq(event.seq, 1)
      assert_eq(event.event.type_name(), "history_user_message")
    }
    SummaryRecord(_) => fail("expected an event record")
  }
  match log.records[1] {
    EventRecord(event) =>
      assert_eq(event.event.type_name(), "assistant_message")
    SummaryRecord(_) => fail("expected an event record")
  }
}
