///| Tests for the Web session-log wiring (WP-3.2).
///
/// The Web path buffers every hook event into the per-session producer and
/// flushes it into `<sessions_dir>/<session_id>.jsonl` when the run ends.
/// Tests drive the real hook registration (`register_ws_hooks`) and the real
/// flush helper (`flush_ws_session_log`) with a scratch sessions directory,
/// so the user's actual `~/.mbopenclacky` is never touched.

///|
/// A scratch sessions directory under `_build`, plus the log path for
/// `session_id`. Any leftover log or lock from a previous run is removed.
fn ws_log_test_path(session_id : String) -> (String, String) {
  let parent = @path.Path::join("_build", @path.Path("wbtest_ws_session_log")).to_string()
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
fn ws_log_test_agent(session_id : String) -> @agent.Agent {
  let client = @client.Client::new(
    "key",
    "https://api.test.com",
    "model",
    @config.OpenAICompletions,
  )
  @agent.Agent::new(
    session_id,
    "ws-log-test",
    ".",
    client,
    @config.AgentConfig::default(),
  )
}

///|
/// The full Web wiring: events emitted through the agent's hook manager land
/// in the per-session producer (including compression, which the broadcast
/// path treats like any other event) and reach the append-only JSONL on
/// flush.
async test "ws hooks feed the session log and flush writes it" {
  let (dir, path) = ws_log_test_path("wbtest-ws-log")
  let server_ref : Ref[WebServer] = Ref(
    WebServer::new(@config.AgentConfig::default(), None),
  )
  let agent = ws_log_test_agent("wbtest-ws-log")
  register_ws_hooks(server_ref, agent, "wbtest-ws-log")
  agent.hook_manager.emit(@agent.InfoMessage("wired"))
  agent.hook_manager.emit(@agent.CompressionPerformed(1))
  agent.hook_manager.emit(@agent.InfoMessage("after"))
  let state = get_ws_state("wbtest-ws-log")
  assert_true(state.producer.buffered() > 0)
  flush_ws_session_log(
    state,
    "wbtest-ws-log",
    "2026-09-22T00:00:00Z",
    sessions_dir=dir,
  )
  let log = @agent.read_session_log(path)
  @debug.assert_eq(log.malformed_lines, 0)
  // Two events plus the summary over the first one.
  @debug.assert_eq(log.records.length(), 3)
  match log.records[1] {
    @agent.SummaryRecord(found) => {
      @debug.assert_eq(found.from_seq, 1)
      @debug.assert_eq(found.to_seq, 1)
    }
    @agent.EventRecord(_) => fail("expected a summary record at index 1")
  }
  // A second flush with an empty buffer must not touch the file.
  flush_ws_session_log(
    state,
    "wbtest-ws-log",
    "2026-09-22T00:00:00Z",
    sessions_dir=dir,
  )
  let again = @agent.read_session_log(path)
  @debug.assert_eq(again.records.length(), 3)
}

///|
async test "flush with an empty buffer creates no ws session log" {
  let (dir, path) = ws_log_test_path("wbtest-ws-empty")
  let state = get_ws_state("wbtest-ws-empty")
  @debug.assert_eq(state.producer.buffered(), 0)
  flush_ws_session_log(
    state,
    "wbtest-ws-empty",
    "2026-09-22T00:00:00Z",
    sessions_dir=dir,
  )
  assert_false(@fs.path_exists(path))
}
