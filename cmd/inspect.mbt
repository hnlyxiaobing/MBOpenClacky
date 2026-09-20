///| Offline session replay and the append-only session log producer (P1-2).
///
/// `mbopenclacky inspect <session.jsonl | session.json>` renders a session
/// timeline without touching it:
///
/// - a `.jsonl` session log is projected (compaction summaries hide the events
///   they cover) and printed with sequence numbers and timestamps
/// - a legacy whole-JSON session is imported **read-only** into the same record
///   shape, so both formats render identically
///
/// The producer side buffers the engine's protocol events during a run and
/// flushes them into `<sessions dir>/<session_id>.jsonl` when the run ends.

///|
/// Buffered protocol events for this process's session log.
let session_log_events : Array[(@proto.Event, Int64)] = []

///|
/// Buffer the engine's events for the session log. Registered for every run;
/// the flush happens when the run ends.
pub fn attach_session_log(agent : @agent.Agent) -> Unit {
  agent.hook_manager.register(fn(evt : @agent.HookEvent) {
    session_log_events.push(
      (@agent.hook_event_to_protocol(evt), @agent.current_time_ms()),
    )
  })
}

///|
/// Flush buffered events into the append-only session log, creating it on
/// first use. Never raises: the run's exit code must not depend on logging.
pub async fn flush_session_log(
  session_id : String,
  created_at : String,
) -> Unit {
  if session_log_events.length() == 0 {
    return
  }
  let dir = @agent.ensure_sessions_dir() catch { _ => return }
  let path = @path.Path::join(dir, @path.Path(session_id + ".jsonl")).to_string()
  if !@fs.path_exists(path) {
    match @agent.create_session_log(path, session_id, created_at) {
      Ok(_) => ()
      Err(_) => return
    }
  }
  for item in session_log_events {
    ignore(@agent.append_event(path, item.0, item.1) catch { _ => Ok(0) })
  }
  session_log_events.clear()
}

///|
fn truncate_text(text : String) -> String {
  let trimmed = text.trim().to_owned()
  if trimmed.length() <= 60 {
    trimmed
  } else {
    trimmed[:60].to_owned() + "..."
  }
}

///|
/// One-line human summary of a protocol event. Exhaustive by design: adding
/// an `Event` variant fails compilation here until inspect renders it.
fn summarize_event(event : @proto.Event) -> String {
  match event {
    @proto.Progress(p) =>
      match p.progress_type {
        Some(kind) => "phase=\{p.phase} type=\{kind}"
        None => "phase=\{p.phase}"
      }
    @proto.PhaseStart(p) => "start \{p.phase_id}"
    @proto.PhaseEnd(p) => "end \{p.phase_id}"
    @proto.ToolCall(c) => "tool=\{c.name}"
    @proto.ToolResult(r) => truncate_text(r.result)
    @proto.ToolError(e) => e.error
    @proto.ErrorMessage(e) => e.message
    @proto.Complete(c) => "iterations=\{c.iterations} cost=\{c.cost}"
    @proto.AssistantMessage(m) => truncate_text(m.content)
    @proto.TokenUsage(u) => "cost=\{u.cost}"
    @proto.TokenDelta(_) => "token delta"
    @proto.Info(m) | @proto.Warning(m) | @proto.Success(m) => m.message
    @proto.FilePreview(p) => "\{p.op} \{p.path}"
    @proto.ToolStdout(s) => truncate_text(s.lines)
    @proto.RequestFeedback(f) => f.question
    @proto.RequestConfirmation(c) => c.message
    @proto.SessionUpdate(u) =>
      match u.status {
        Some(status) => "status=\{status}"
        None => "session patch"
      }
    @proto.HistoryUserMessage(m) => truncate_text(m.content)
    @proto.SessionRenamed(r) => "renamed to \{r.name}"
    @proto.SessionList(l) => "sessions=\{l.sessions.length()}"
    @proto.Interrupted
    | @proto.SessionDeleted
    | @proto.Pong
    | @proto.SessionRestored(_)
    | @proto.TaskFinished(_)
    | @proto.FeedbackResponse(_)
    | @proto.ConfirmationResponse(_)
    | @proto.Connected(_)
    | @proto.Subscribed(_) => event.type_name()
  }
}

///|
fn record_line(record : @agent.LogRecord) -> String {
  match record {
    @agent.EventRecord(event) =>
      "\{event.seq}\t\{event.unix_ms}\t\{event.event.type_name()}\t\{summarize_event(event.event)}"
    @agent.SummaryRecord(summary) =>
      "\{summary.seq}\t\{summary.unix_ms}\tsummary\tcovers seq \{summary.from_seq}..=\{summary.to_seq}"
  }
}

///|
fn render_session_file(
  path : String,
  format : String,
  log : @agent.SessionLogFile,
) -> Unit {
  println("Session: \{path}")
  println("format: \{format}")
  match log.header {
    Some(header) =>
      println(
        "header: version=\{header.version} session_id=\{header.session_id} created_at=\{header.created_at}",
      )
    None => println("header: (missing)")
  }
  let projected = log.project()
  println(
    "records: \{log.records.length()} total, \{projected.length()} after projection, truncated_tail=\{log.truncated_tail}, malformed_lines=\{log.malformed_lines}",
  )
  println("")
  println("seq\tunix_ms\ttype\tsummary")
  for record in projected {
    println(record_line(record))
  }
}

///|
/// `cmd inspect <path>` — offline session timeline replay.
pub fn handle_inspect(sub : @clap.SimpleValue) -> Unit {
  let path = if sub.positional_args.length() > 0 {
    sub.positional_args[0]
  } else {
    get_named_arg(sub, "path").unwrap_or("")
  }
  if path.length() == 0 {
    println("usage: mbopenclacky inspect <session.jsonl|session.json>")
    @sys.exit(2)
    return
  }
  if !@fs.path_exists(path) {
    println("inspect: file not found: \{path}")
    @sys.exit(1)
    return
  }
  // An append-only session log always starts with its version header.
  let as_log = @agent.read_session_log(path)
  if as_log.header is Some(_) {
    render_session_file(path, "jsonl (append-only session log)", as_log)
    return
  }
  // Otherwise try the legacy whole-JSON session (read-only import).
  let data = match @agent.load_session_file(path) {
    Ok(parsed) => parsed
    Err(reason) => {
      println("inspect: \{path} is neither a session log nor a session file:")
      println("  \{reason}")
      @sys.exit(1)
      return
    }
  }
  render_session_file(
    path,
    "legacy json (read-only import; nothing was written)",
    @agent.legacy_session_records(data),
  )
}
