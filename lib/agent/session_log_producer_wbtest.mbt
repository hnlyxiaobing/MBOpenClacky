///| Tests for the shared session-log producer (WP-3.2).
///
/// The producer is a value type consumed by the CLI process, the TUI and the
/// Web per-session state. These tests cover the invariants the write
/// primitives alone cannot: compression splits segments and projects as a
/// `summary` record, the covered events stay byte-identical in the file, and
/// a flush never creates an empty log.

///|
/// A scratch sessions directory under `_build`, plus the log path for
/// `session_id`. Any leftover log or lock from a previous run is removed, so
/// the assertions hold no matter how often the suite is re-run.
fn producer_test_path(session_id : String) -> (String, String) {
  let parent = @path.Path::join("_build", @path.Path("wbtest_session_log")).to_string()
  if !@fs.path_exists(parent) {
    @fs.create_dir(parent) catch {
      _ => ()
    }
  }
  let dir = @path.Path::join(parent, @path.Path(session_id)).to_string()
  if !@fs.path_exists(dir) {
    @fs.create_dir(dir) catch {
      _ => ()
    }
  }
  let path = @path.Path::join(dir, @path.Path(session_id + ".jsonl")).to_string()
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
  let lock = path + ".lock"
  if @fs.path_exists(lock) {
    @fs.remove_file(lock) catch {
      _ => ()
    }
  }
  (dir, path)
}

///|
async test "session log producer projects a compression as a summary" {
  let (dir, path) = producer_test_path("wbtest-summary")
  let producer = SessionLogProducer::new()
  producer.on_hook_event(InfoMessage("first"))
  producer.on_hook_event(InfoMessage("second"))
  producer.on_hook_event(CompressionPerformed(2))
  producer.on_hook_event(InfoMessage("third"))
  producer.flush("wbtest-summary", "2026-09-21T00:00:00Z", dir)
  let log = read_session_log(path)
  @debug.assert_eq(log.malformed_lines, 0)
  @debug.assert_eq(log.truncated_tail, false)
  // Three events plus the compaction marker.
  @debug.assert_eq(log.records.length(), 4)
  let summary = match log.records[2] {
    SummaryRecord(found) => found
    EventRecord(_) => {
      fail("expected a summary record at index 2")
      return
    }
  }
  @debug.assert_eq(summary.from_seq, 1)
  @debug.assert_eq(summary.to_seq, 2)
  // The covered events are hidden by the projection, the later one is not.
  @debug.assert_eq(log.project().length(), 2)
  // ... but their original bytes are still in the file, untouched.
  let raw = @fs.read_file_to_string(path) catch { _ => "" }
  assert_true(raw.contains("\"first\""))
  assert_true(raw.contains("\"second\""))
  assert_true(raw.contains("\"third\""))
  assert_true(raw.contains("\"type\":\"summary\""))
}

///|
async test "two compressions in one run produce two disjoint summaries" {
  let (dir, path) = producer_test_path("wbtest-two-summaries")
  let producer = SessionLogProducer::new()
  producer.on_hook_event(InfoMessage("a"))
  producer.on_hook_event(CompressionPerformed(1))
  producer.on_hook_event(InfoMessage("b"))
  producer.on_hook_event(CompressionPerformed(1))
  producer.on_hook_event(InfoMessage("c"))
  producer.flush("wbtest-two-summaries", "2026-09-21T00:00:00Z", dir)
  let log = read_session_log(path)
  let summaries : Array[LogSummary] = []
  for record in log.records {
    match record {
      SummaryRecord(found) => summaries.push(found)
      EventRecord(_) => ()
    }
  }
  @debug.assert_eq(summaries.length(), 2)
  // Summary markers consume sequence numbers too, so the covered events are
  // seq 1 (first segment) and seq 3 (second segment).
  @debug.assert_eq(summaries[0].from_seq, 1)
  @debug.assert_eq(summaries[0].to_seq, 1)
  @debug.assert_eq(summaries[1].from_seq, 3)
  @debug.assert_eq(summaries[1].to_seq, 3)
  // Only the event after the last compression survives projection, plus the
  // two summary markers.
  @debug.assert_eq(log.project().length(), 3)
}

///|
async test "flush with an empty buffer creates no file" {
  let (dir, path) = producer_test_path("wbtest-empty-buffer")
  let producer = SessionLogProducer::new()
  @debug.assert_eq(producer.buffered(), 0)
  producer.flush("wbtest-empty-buffer", "2026-09-21T00:00:00Z", dir)
  assert_false(@fs.path_exists(path))
}

///|
/// A log started by another writer (e.g. the CLI in an earlier run) must be
/// appended to with a continuing sequence, never overwritten.
async test "flush continues an existing log's sequence" {
  let (dir, path) = producer_test_path("wbtest-continuation")
  let existing_event : @protocol.Event = @protocol.Info({ message: "from cli", })
  let _ = append_event(path, existing_event, 1000L)
  let producer = SessionLogProducer::new()
  producer.on_hook_event(InfoMessage("from web"))
  producer.flush("wbtest-continuation", "2026-09-21T00:00:00Z", dir)
  let log = read_session_log(path)
  @debug.assert_eq(log.records.length(), 2)
  match log.records[1] {
    EventRecord(event) => @debug.assert_eq(event.seq, 2)
    SummaryRecord(_) => fail("expected an event record at index 1")
  }
}
