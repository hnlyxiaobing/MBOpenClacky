///| Tests for the CLI session-log producer (T5 / T6).
///
/// These cover the wiring the unit tests in `lib/agent/session_log_wbtest.mbt`
/// cannot: that a compression is projected as a `summary` record over the
/// events it supersedes, while those events stay byte-identical in the file.

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
fn producer_test_agent(session_id : String) -> @agent.Agent {
  let client = @client.Client::new(
    "key",
    "https://api.test.com",
    "model",
    @config.OpenAICompletions,
  )
  @agent.Agent::new(
    session_id,
    "producer-test",
    ".",
    client,
    @config.AgentConfig::default(),
  )
}

///|
async test "session log producer projects a compression as a summary" {
  let (dir, path) = producer_test_path("wbtest-summary")
  let producer = SessionLogProducer::new()
  producer.on_hook_event(@agent.InfoMessage("first"))
  producer.on_hook_event(@agent.InfoMessage("second"))
  producer.on_hook_event(@agent.CompressionPerformed(2))
  producer.on_hook_event(@agent.InfoMessage("third"))
  producer.flush("wbtest-summary", "2026-09-21T00:00:00Z", dir)
  let log = @agent.read_session_log(path)
  @debug.assert_eq(log.malformed_lines, 0)
  @debug.assert_eq(log.truncated_tail, false)
  // Three events plus the compaction marker.
  @debug.assert_eq(log.records.length(), 4)
  let summary = match log.records[2] {
    @agent.SummaryRecord(found) => found
    @agent.EventRecord(_) => {
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
  producer.on_hook_event(@agent.InfoMessage("a"))
  producer.on_hook_event(@agent.CompressionPerformed(1))
  producer.on_hook_event(@agent.InfoMessage("b"))
  producer.on_hook_event(@agent.CompressionPerformed(1))
  producer.on_hook_event(@agent.InfoMessage("c"))
  producer.flush("wbtest-two-summaries", "2026-09-21T00:00:00Z", dir)
  let log = @agent.read_session_log(path)
  let summaries : Array[@agent.LogSummary] = []
  for record in log.records {
    match record {
      @agent.SummaryRecord(found) => summaries.push(found)
      @agent.EventRecord(_) => ()
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
/// The CLI wiring as `run_agent` uses it: the producer is registered on the
/// agent's hook manager and flushed by the run path. This is the only test
/// that touches the process-global producer, so it cannot race another test.
async test "attach_session_log + flush_session_log write the run's log" {
  let (dir, path) = producer_test_path("wbtest-cli-wiring")
  let agent = producer_test_agent("wbtest-cli-wiring")
  attach_session_log(agent)
  agent.hook_manager.emit(@agent.InfoMessage("wired"))
  agent.hook_manager.emit(@agent.CompressionPerformed(1))
  flush_session_log(agent.session_id, agent.created_at, sessions_dir=dir)
  let log = @agent.read_session_log(path)
  @debug.assert_eq(log.records.length(), 2)
  match log.records[1] {
    @agent.SummaryRecord(found) => {
      @debug.assert_eq(found.from_seq, 1)
      @debug.assert_eq(found.to_seq, 1)
    }
    @agent.EventRecord(_) => fail("expected a trailing summary record")
  }
  // A second flush with an empty buffer must not create or touch the file.
  flush_session_log(agent.session_id, agent.created_at, sessions_dir=dir)
  let again = @agent.read_session_log(path)
  @debug.assert_eq(again.records.length(), 2)
}
