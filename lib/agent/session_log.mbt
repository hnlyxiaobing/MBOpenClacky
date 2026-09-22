///| Append-only JSONL session log (P1-2).
///
/// Format — one JSON object per LF-terminated line:
///
/// - line 1, header: `{"version":1,"session_id":"...","created_at":"..."}`
/// - events: `{"seq":1,"unix_ms":1719...,"type":"...", ...event fields}`
/// - compaction: `{"seq":n,"unix_ms":...,"type":"summary","from_seq":a,"to_seq":b}`
///
/// Guarantees:
/// - appends never rewrite, reorder or truncate existing bytes (the file is
///   opened in append mode); `seq` is strictly increasing and continuous
/// - compaction only APPENDS a `summary` record; the projection skips events
///   covered by any summary and never mutates the originals
/// - a half-written final line is dropped on read, so a truncated tail still
///   recovers every complete record
/// - additional writers are excluded with an advisory exclusive lock on
///   `session.lock`; a lock whose owner died is detected and recovered
/// - every append re-reads the file to pick `max(seq) + 1`, so a stale
///   in-memory view can never collide with another writer's sequence
///
/// Legacy whole-JSON sessions are never rewritten: `legacy_records` projects
/// them into the same record shape for read-only replay.

///|
/// Current log format version.
pub let session_log_version : Int = 1

///|
/// Log header (first line).
pub(all) struct SessionLogHeader {
  version : Int
  session_id : String
  created_at : String
}

///|
/// One appended engine event.
pub(all) struct LoggedEvent {
  seq : Int
  unix_ms : Int64
  event : @protocol.Event
}

///|
/// A compaction marker: events `from_seq..=to_seq` are superseded. The
/// originals stay in the file untouched.
pub(all) struct LogSummary {
  seq : Int
  unix_ms : Int64
  from_seq : Int
  to_seq : Int
}

///|
/// One record in a session log.
pub(all) enum LogRecord {
  EventRecord(LoggedEvent)
  SummaryRecord(LogSummary)
}

///|
/// Result of reading a session log.
pub(all) struct SessionLogFile {
  /// Parsed header, or None when the first line was not a header.
  header : SessionLogHeader?
  /// Records in file order.
  records : Array[LogRecord]
  /// A partial final line was dropped (crash / truncation).
  truncated_tail : Bool
  /// Non-final lines that did not parse (reported, never hidden).
  malformed_lines : Int
}

///|
/// The JSONL path that sits next to a session's `.json` file.
pub fn session_log_path(json_path : String) -> String {
  if json_path.has_suffix(".json") {
    json_path[:json_path.length() - 5].to_owned() + ".jsonl"
  } else {
    json_path + ".jsonl"
  }
}

///|
/// The advisory lock path used while appending.
pub fn session_lock_path(jsonl_path : String) -> String {
  jsonl_path + ".lock"
}

// ── Serialization ───────────────────────────────────────────────────────────

///|
fn header_to_json(header : SessionLogHeader) -> Json {
  Json::object({
    "version": header.version.to_json(),
    "session_id": header.session_id.to_json(),
    "created_at": header.created_at.to_json(),
  })
}

///|
/// Serialize an event record: the protocol event body plus the log's
/// `seq` / `unix_ms` envelope.
fn event_to_json(record : LoggedEvent) -> Json {
  let out : Map[String, Json] = Map([])
  out["seq"] = record.seq.to_json()
  // Written as an explicit JSON number: Int64's generic ToJson encoding is not
  // guaranteed to be a plain number, and the reader expects one.
  out["unix_ms"] = Json::number(record.unix_ms.to_double())
  match record.event.to_json() {
    Object(fields) =>
      for entry in fields {
        out[entry.0] = entry.1
      }
    _ => ()
  }
  Json::object(out)
}

///|
fn summary_to_json(summary : LogSummary) -> Json {
  Json::object({
    "seq": summary.seq.to_json(),
    "unix_ms": Json::number(summary.unix_ms.to_double()),
    "type": "summary".to_json(),
    "from_seq": summary.from_seq.to_json(),
    "to_seq": summary.to_seq.to_json(),
  })
}

///|
fn record_to_line(record : LogRecord) -> String {
  let json = match record {
    EventRecord(event) => event_to_json(event)
    SummaryRecord(summary) => summary_to_json(summary)
  }
  json.stringify() + "\n"
}

///|
fn parse_header_json(json : Json?) -> SessionLogHeader? {
  let fields = match json {
    Some(Object(fields)) => fields
    _ => return None
  }
  let version = match fields.get("version") {
    Some(Number(n, ..)) => n.to_int()
    _ => return None
  }
  let session_id = match fields.get("session_id") {
    Some(String(s)) => s
    _ => return None
  }
  Some({
    version,
    session_id,
    created_at: match fields.get("created_at") {
      Some(String(s)) => s
      _ => ""
    },
  })
}

///|
/// Parse one record line from an already-parsed JSON value. Returns None when
/// the line is not a valid record (the caller decides whether that means a
/// truncated tail or a corrupt line).
fn parse_record_json(json : Json?) -> LogRecord? {
  let fields = match json {
    Some(Object(fields)) => fields
    _ => return None
  }
  let seq = match fields.get("seq") {
    Some(Number(n, ..)) => n.to_int()
    _ => return None
  }
  let unix_ms : Int64 = match fields.get("unix_ms") {
    Some(Number(n, ..)) => n.to_int64()
    _ => 0L
  }
  match (fields.get("from_seq"), fields.get("to_seq")) {
    (Some(Number(from, ..)), Some(Number(to, ..))) =>
      Some(
        SummaryRecord({
          seq,
          unix_ms,
          from_seq: from.to_int(),
          to_seq: to.to_int(),
        }),
      )
    _ =>
      match @protocol.Event::parse(Json::object(fields)) {
        Some(event) => Some(EventRecord({ seq, unix_ms, event, }))
        None => None
      }
  }
}

// 鈹€鈹€ Reading 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

///|
/// Read a session log from disk, tolerating a truncated final line.
pub fn read_session_log(path : String) -> SessionLogFile {
  let content = @fs.read_file_to_string(path) catch {
    _ =>
      return {
        header: None,
        records: [],
        truncated_tail: false,
        malformed_lines: 0,
      }
  }
  let records : Array[LogRecord] = []
  let mut header : SessionLogHeader? = None
  let mut malformed = 0
  let mut truncated = false
  let ends_with_newline = content.has_suffix("\n")
  let lines = content.split("\n").collect()
  let count = lines.length()
  let mut index = 0
  for raw in lines {
    index = index + 1
    let line = raw.trim().to_owned()
    if line.length() == 0 {
      continue
    }
    let is_last = index == count
    if is_last && !ends_with_newline {
      // A final line without its newline is a partial write.
      truncated = true
      continue
    }
    let parsed : Json? = Some(@json.parse(line)) catch { _ => None }
    if index == 1 {
      match parse_header_json(parsed) {
        Some(found) => {
          header = Some(found)
          continue
        }
        None => ()
      }
    }
    match parse_record_json(parsed) {
      Some(record) => records.push(record)
      None => if is_last { truncated = true } else { malformed = malformed + 1 }
    }
  }
  { header, records, truncated_tail: truncated, malformed_lines: malformed, }
}

///|
/// Project the readable record stream: every event not covered by a summary,
/// in file order. Original bytes are never touched.
pub fn SessionLogFile::project(self : SessionLogFile) -> Array[LogRecord] {
  let out : Array[LogRecord] = []
  for record in self.records {
    match record {
      SummaryRecord(_) => out.push(record)
      EventRecord(event) => {
        let mut covered = false
        for other in self.records {
          match other {
            SummaryRecord(summary) =>
              if event.seq >= summary.from_seq && event.seq <= summary.to_seq {
                covered = true
              }
            EventRecord(_) => ()
          }
        }
        if !covered {
          out.push(record)
        }
      }
    }
  }
  out
}

///|
/// The highest sequence number in a log (0 when empty).
pub fn SessionLogFile::max_seq(self : SessionLogFile) -> Int {
  let mut max = 0
  for record in self.records {
    let seq = match record {
      EventRecord(event) => event.seq
      SummaryRecord(summary) => summary.seq
    }
    if seq > max {
      max = seq
    }
  }
  max
}

// ── Writing (append-only) ───────────────────────────────────────────────────

///|
/// Append raw text to a file without touching existing bytes. A torn final
/// line (no trailing newline) is terminated first so the new record starts on
/// its own line and stays parseable.
async fn append_text(path : String, text : String) -> Result[Unit, String] {
  let mut payload = text
  let existing = @fs.read_file_to_string(path) catch { _ => "" }
  if existing.length() > 0 && !existing.has_suffix("\n") {
    payload = "\n" + text
  }
  @afs.write_file(path, payload, append=true, create_mode=OpenOrCreate) catch {
    err => return Err("failed to append to \{path}: \{err}")
  }
  Ok(())
}

///|
/// Create a fresh log with its header. Fails when the file already exists so
/// an existing session log is never overwritten.
pub async fn create_session_log(
  path : String,
  session_id : String,
  created_at : String,
) -> Result[Unit, String] {
  if @fs.path_exists(path) {
    return Err("session log already exists: \{path}")
  }
  let header : SessionLogHeader = {
    version: session_log_version,
    session_id,
    created_at,
  }
  @afs.write_file(
    path,
    header_to_json(header).stringify() + "\n",
    create_mode=CreateNew,
  ) catch {
    err => return Err("failed to create \{path}: \{err}")
  }
  Ok(())
}

///|
/// Append one engine event and return its sequence number. The next sequence
/// is derived from the current file, so a stale in-memory view cannot collide.
pub async fn append_event(
  path : String,
  event : @protocol.Event,
  unix_ms : Int64,
) -> Result[Int, String] {
  let current = read_session_log(path)
  let seq = current.max_seq() + 1
  let record = EventRecord({ seq, unix_ms, event, })
  match append_text(path, record_to_line(record)) {
    Ok(_) => Ok(seq)
    Err(err) => Err(err)
  }
}

///|
/// Append a compaction marker covering `from_seq..=to_seq`. The covered
/// events stay byte-identical in the file; only the projection skips them.
pub async fn append_summary(
  path : String,
  from_seq : Int,
  to_seq : Int,
  unix_ms : Int64,
) -> Result[Int, String] {
  let current = read_session_log(path)
  let seq = current.max_seq() + 1
  let record = SummaryRecord({ seq, unix_ms, from_seq, to_seq, })
  match append_text(path, record_to_line(record)) {
    Ok(_) => Ok(seq)
    Err(err) => Err(err)
  }
}

// ── Locking ─────────────────────────────────────────────────────────────────

///|
/// An acquired advisory session lock.
pub(all) struct SessionLock {
  file : @afs.File
  path : String
  /// True when the lock file already existed but nobody held the lock, i.e.
  /// a previous writer died without releasing it.
  recovered_stale : Bool
}

///|
/// Acquire the exclusive advisory lock for a session log. Concurrent writers
/// are rejected; a lock left behind by a dead writer is recovered.
pub async fn acquire_session_lock(
  lock_path : String,
) -> Result[SessionLock, String] {
  let recovered_stale = @fs.path_exists(lock_path)
  let file = @afs.open(lock_path, mode=ReadWrite, create_mode=OpenOrCreate) catch {
    err => return Err("failed to open lock \{lock_path}: \{err}")
  }
  let acquired = file.try_lock(Exclusive) catch { _ => false }
  if !acquired {
    file.close()
    return Err("session is locked by another writer: \{lock_path}")
  }
  Ok({ file, path: lock_path, recovered_stale, })
}

///|
/// Release the session lock.
pub fn SessionLock::release(self : SessionLock) -> Unit {
  self.file.unlock()
  self.file.close()
}

// ── Producer (CLI / TUI / Web run paths) ────────────────────────────────────

///|
/// A buffered run of protocol events that a compression either does or does
/// not supersede. A run is appended in order; when a segment is marked
/// `superseded`, its events get a `summary` record covering them so replay
/// hides them behind the compaction projection (the original bytes stay).
pub(all) struct SessionLogSegment {
  events : Array[(@protocol.Event, Int64)]
  mut superseded : Bool
}

///|
/// Session-log producer state: the buffered events of one run, split at
/// compression boundaries. Held as a value rather than a bare global so each
/// frontend (CLI process, TUI, Web per-session state) can own its instance
/// and the wiring can be exercised without shared process state.
pub(all) struct SessionLogProducer {
  segments : Array[SessionLogSegment]
}

///|
pub fn SessionLogProducer::new() -> SessionLogProducer {
  { segments: [], }
}

///|
/// The segment currently accepting events.
pub fn SessionLogProducer::open_segment(
  self : SessionLogProducer,
) -> SessionLogSegment {
  if self.segments.length() == 0 {
    self.segments.push({ events: [], superseded: false, })
  }
  self.segments[self.segments.length() - 1]
}

///|
/// Feed one engine hook event into the buffer.
pub fn SessionLogProducer::on_hook_event(
  self : SessionLogProducer,
  evt : HookEvent,
) -> Unit {
  match evt {
    CompressionPerformed(_) => {
      // Everything buffered so far is superseded by this compaction. The
      // summary record itself is appended at flush time, so the append-only
      // write path stays in one place.
      let segment = self.open_segment()
      if segment.events.length() > 0 {
        segment.superseded = true
        self.segments.push({ events: [], superseded: false, })
      }
    }
    _ =>
      self.open_segment().events.push(
        (hook_event_to_protocol(evt), current_time_ms()),
      )
  }
}

///|
pub fn SessionLogProducer::buffered(self : SessionLogProducer) -> Int {
  let mut total = 0
  for segment in self.segments {
    total = total + segment.events.length()
  }
  total
}

///|
/// Append the buffered events into `<dir>/<session_id>.jsonl`, creating it on
/// first use, and append a `summary` record for every superseded segment.
/// Never raises: the run's exit code must not depend on logging.
pub async fn SessionLogProducer::flush(
  self : SessionLogProducer,
  session_id : String,
  created_at : String,
  dir : String,
) -> Unit {
  // An eventless run must not create an empty log file.
  if self.buffered() == 0 {
    return
  }
  let path = @path.Path::join(dir, @path.Path(session_id + ".jsonl")).to_string()
  if !@fs.path_exists(path) {
    match create_session_log(path, session_id, created_at) {
      Ok(_) => ()
      Err(_) => return
    }
  }
  for segment in self.segments {
    if segment.events.length() == 0 {
      continue
    }
    let (first_seq, last_seq) = append_segment_events(path, segment.events)
    if segment.superseded && first_seq > 0 && last_seq >= first_seq {
      let result : Result[Int, String] = append_summary(
        path,
        first_seq,
        last_seq,
        current_time_ms(),
      ) catch {
        _ => Ok(0)
      }
      ignore(result)
    }
  }
  self.segments.clear()
}

///|
/// Append one segment's events in order; returns the sequence range written
/// (both 0 when nothing could be written).
async fn append_segment_events(
  path : String,
  events : Array[(@protocol.Event, Int64)],
) -> (Int, Int) {
  let mut first_seq = 0
  let mut last_seq = 0
  for item in events {
    let result : Result[Int, String] = append_event(path, item.0, item.1) catch {
      _ => Ok(0)
    }
    let seq = match result {
      Ok(value) => value
      Err(_) => 0
    }
    if seq > 0 {
      if first_seq == 0 {
        first_seq = seq
      }
      last_seq = seq
    }
  }
  (first_seq, last_seq)
}

// ── Legacy import (read-only) ───────────────────────────────────────────────

///|
/// Load a legacy whole-JSON session from an arbitrary path (read-only),
/// reporting why a file could not be read. The second element of the `Ok`
/// names the on-disk format ("legacy json" or "legacy debug-repr") so the
/// caller can report which projection was applied.
pub fn load_session_file(
  path : String,
) -> Result[(SessionData, String), String] {
  let content = @fs.read_file_to_string(path) catch {
    err => return Err("cannot read file: " + @debug.to_string(err))
  }
  decode_session_document(content)
}

///|
/// Project a legacy whole-JSON session into log records for read-only
/// replay. Nothing is written: the caller renders these in memory.
pub fn legacy_session_records(data : SessionData) -> SessionLogFile {
  let records : Array[LogRecord] = []
  let mut seq = 1
  for msg in data.messages {
    let content = match msg.content {
      @message.Text(text) => text
      @message.Blocks(parts) => {
        let buffer : Array[String] = []
        for part in parts {
          match part {
            @message.Text(block) => buffer.push(block.text)
            _ => ()
          }
        }
        buffer.join("\n")
      }
    }
    let event : @protocol.Event = match msg.role {
      @message.User =>
        @protocol.HistoryUserMessage({
          content,
          role: "user",
          created_at: msg.created_at,
          system_injected: None,
        })
      @message.Assistant =>
        @protocol.AssistantMessage({
          content,
          role: Some("assistant"),
          partial: None,
          created_at: msg.created_at,
        })
      @message.Tool =>
        @protocol.ToolResult({ result: content, created_at: msg.created_at, })
      @message.System =>
        @protocol.HistoryUserMessage({
          content,
          role: "system",
          created_at: msg.created_at,
          system_injected: Some(true),
        })
    }
    records.push(EventRecord({ seq, unix_ms: 0L, event, }))
    seq = seq + 1
    match msg.tool_calls {
      Some(calls) =>
        for call in calls {
          let args : Json = @json.parse(call.function.arguments) catch {
            _ => call.function.arguments.to_json()
          }
          records.push(
            EventRecord({
              seq,
              unix_ms: 0L,
              event: @protocol.ToolCall({
                name: call.function.name,
                args,
                summary: None,
                created_at: msg.created_at,
              }),
            }),
          )
          seq = seq + 1
        }
      None => ()
    }
  }
  {
    header: Some({
      version: session_log_version,
      session_id: data.session_id,
      created_at: data.created_at,
    }),
    records,
    truncated_tail: false,
    malformed_lines: 0,
  }
}
