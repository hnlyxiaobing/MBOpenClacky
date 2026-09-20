///| Typed engine protocol: the `Event` enum (engine → consumer).
///
/// This is a **leaf** package: it depends only on `moonbitlang/core/json` and
/// knows nothing about the agent, the web server or the TUI. It is the single
/// author of the wire JSON for every engine/frontend event:
///
/// - `Event::to_json` builds the event body (flat object, `type` discriminator)
/// - `Event::parse` is its inverse (`parse(to_json(e)) == e`)
/// - `Event::to_wire` frames the body for a connection: `type` first, optional
///   `session_id`, then the event fields (payload wins on key collisions,
///   matching the historical `build_event` merge order)
///
/// Wire compatibility notes:
/// - Optional payload fields are **omitted** when absent instead of emitted as
///   `null`. Every frontend consumer reads them through falsy checks
///   (`ev.context || ""`, `ev.summary && ...`), so omission is behaviour
///   preserving; `to_json`/`parse` stay exact inverses either way.
/// - Engine events that the wire cannot distinguish (`AfterIteration` vs
///   `MessageAdded`, `SessionStarted` vs `StatusChanged`) intentionally share a
///   single protocol variant. Consumers that need that distinction keep
///   matching on the engine's own `HookEvent`; the wire sees one event, which
///   is what today's frontend already observes.

///|
/// Cache statistics carried by the `complete` event.
pub(all) struct CacheStats {
  total_requests : Int
  cache_hit_requests : Int
  cache_read_input_tokens : Int
}

///|
/// Partial `session_update` patch: any subset of status / cost / latency /
/// full session snapshot. The agent emits status transitions; the web layer
/// also emits cost, latency and snapshot patches for the same wire type.
pub(all) struct SessionUpdate {
  status : String?
  session_id : String?
  cost : Double?
  cost_source : String?
  latency : Json?
  session : Json?
}

///|
/// Progress update. `phase` is always present; the rest depends on the kind
/// (`thinking`, `retry`, plain `done`).
pub(all) struct Progress {
  phase : String
  message : String?
  progress_type : String?
  metadata : Json?
  started_at : String?
}

///|
/// Phase start (llm_call / thinking / subagent).
pub(all) struct PhaseStart {
  phase_id : String
  kind : String?
  label : String?
}

///|
/// Phase end.
pub(all) struct PhaseEnd {
  phase_id : String
  summary : String?
}

///|
/// Tool invocation announced.
pub(all) struct ToolCall {
  name : String
  args : Json
  summary : Json?
  created_at : String?
}

///|
/// Tool execution result.
pub(all) struct ToolResult {
  result : String
  created_at : String?
}

///|
/// Tool execution error (also used for denied tools).
pub(all) struct ToolError {
  error : String
}

///|
/// Generic error message.
pub(all) struct ErrorMessage {
  message : String
}

///|
/// Agent run completed.
pub(all) struct Complete {
  iterations : Int
  cost : Double
  cost_source : String
  cache_stats : CacheStats
}

///|
/// Complete or partial assistant message.
pub(all) struct AssistantMessage {
  content : String
  role : String?
  partial : Bool?
  created_at : String?
}

///|
/// Token usage / cost update.
pub(all) struct TokenUsage {
  cost : Double
  prompt_tokens : Int?
  completion_tokens : Int?
  delta_tokens : Int?
  total_tokens : Int?
  cost_source : String?
  cache_read : Int?
  cache_write : Int?
}

///|
/// Token-level streaming delta.
pub(all) struct TokenDelta {
  content : String
}

///|
/// A single user-facing message (info / warning / success).
pub(all) struct TextMessage {
  message : String
}

///|
/// File preview.
pub(all) struct FilePreview {
  path : String
  op : String
}

///|
/// Tool stdout lines.
pub(all) struct ToolStdout {
  lines : String
}

///|
/// Agent asks for user feedback.
pub(all) struct RequestFeedback {
  question : String
  id : String?
  context : String?
  options : Array[String]?
}

///|
/// Agent asks for tool confirmation.
pub(all) struct RequestConfirmation {
  id : String
  message : String
}

///|
/// Session snapshot restored.
pub(all) struct SessionRestored {
  session : Json
}

///|
/// Session renamed.
pub(all) struct SessionRenamed {
  name : String
}

///|
/// Echo of a user message in the history.
pub(all) struct HistoryUserMessage {
  content : String
  role : String
  created_at : String?
  system_injected : Bool?
}

///|
/// Background task finished (global broadcast).
pub(all) struct TaskFinished {
  session_id : String
}

///|
/// Feedback reply acknowledged (global).
pub(all) struct FeedbackResponse {
  request_id : String
  received : Bool
}

///|
/// Confirmation reply acknowledged (global).
pub(all) struct ConfirmationResponse {
  request_id : String
  confirmed : Bool
}

///|
/// Connection established (global).
pub(all) struct Connected {
  session_id : String
}

///|
/// Subscription confirmed (global).
pub(all) struct Subscribed {
  session_id : String
}

///|
/// Session list snapshot (global).
pub(all) struct SessionList {
  sessions : Array[Json]
  has_more : Bool
  cron_count : Int
  latest_cron_updated_at : Json?
}

///|
/// The typed engine/protocol event vocabulary.
pub(all) enum Event {
  /// `session_update` — status / cost / latency patch.
  SessionUpdate(SessionUpdate)
  /// `progress`
  Progress(Progress)
  /// `phase_start`
  PhaseStart(PhaseStart)
  /// `phase_end`
  PhaseEnd(PhaseEnd)
  /// `tool_call`
  ToolCall(ToolCall)
  /// `tool_result`
  ToolResult(ToolResult)
  /// `tool_error`
  ToolError(ToolError)
  /// `error`
  ErrorMessage(ErrorMessage)
  /// `complete`
  Complete(Complete)
  /// `assistant_message`
  AssistantMessage(AssistantMessage)
  /// `token_usage`
  TokenUsage(TokenUsage)
  /// `token_delta`
  TokenDelta(TokenDelta)
  /// `warning`
  Warning(TextMessage)
  /// `info`
  Info(TextMessage)
  /// `success`
  Success(TextMessage)
  /// `file_preview`
  FilePreview(FilePreview)
  /// `tool_stdout`
  ToolStdout(ToolStdout)
  /// `request_feedback`
  RequestFeedback(RequestFeedback)
  /// `request_confirmation`
  RequestConfirmation(RequestConfirmation)
  /// `interrupted`
  Interrupted
  /// `session_restored`
  SessionRestored(SessionRestored)
  /// `session_renamed`
  SessionRenamed(SessionRenamed)
  /// `session_deleted`
  SessionDeleted
  /// `history_user_message`
  HistoryUserMessage(HistoryUserMessage)
  /// `task_finished` (global broadcast)
  TaskFinished(TaskFinished)
  /// `feedback_response` (global)
  FeedbackResponse(FeedbackResponse)
  /// `confirmation_response` (global)
  ConfirmationResponse(ConfirmationResponse)
  /// `connected` (global)
  Connected(Connected)
  /// `subscribed` (global)
  Subscribed(Subscribed)
  /// `session_list` (global)
  SessionList(SessionList)
  /// `pong` (global)
  Pong
}

///|
/// The wire `type` discriminator for an event.
pub fn Event::type_name(self : Event) -> String {
  match self {
    SessionUpdate(_) => "session_update"
    Progress(_) => "progress"
    PhaseStart(_) => "phase_start"
    PhaseEnd(_) => "phase_end"
    ToolCall(_) => "tool_call"
    ToolResult(_) => "tool_result"
    ToolError(_) => "tool_error"
    ErrorMessage(_) => "error"
    Complete(_) => "complete"
    AssistantMessage(_) => "assistant_message"
    TokenUsage(_) => "token_usage"
    TokenDelta(_) => "token_delta"
    Warning(_) => "warning"
    Info(_) => "info"
    Success(_) => "success"
    FilePreview(_) => "file_preview"
    ToolStdout(_) => "tool_stdout"
    RequestFeedback(_) => "request_feedback"
    RequestConfirmation(_) => "request_confirmation"
    Interrupted => "interrupted"
    SessionRestored(_) => "session_restored"
    SessionRenamed(_) => "session_renamed"
    SessionDeleted => "session_deleted"
    HistoryUserMessage(_) => "history_user_message"
    TaskFinished(_) => "task_finished"
    FeedbackResponse(_) => "feedback_response"
    ConfirmationResponse(_) => "confirmation_response"
    Connected(_) => "connected"
    Subscribed(_) => "subscribed"
    SessionList(_) => "session_list"
    Pong => "pong"
  }
}

///|
/// Whether this event is a connection-global broadcast (no session framing)
/// rather than a session-scoped event.
pub fn Event::is_global(self : Event) -> Bool {
  match self {
    SessionUpdate(_)
    | Progress(_)
    | PhaseStart(_)
    | PhaseEnd(_)
    | ToolCall(_)
    | ToolResult(_)
    | ToolError(_)
    | ErrorMessage(_)
    | Complete(_)
    | AssistantMessage(_)
    | TokenUsage(_)
    | TokenDelta(_)
    | Warning(_)
    | Info(_)
    | Success(_)
    | FilePreview(_)
    | ToolStdout(_)
    | RequestFeedback(_)
    | RequestConfirmation(_)
    | Interrupted
    | SessionRestored(_)
    | SessionRenamed(_)
    | SessionDeleted
    | HistoryUserMessage(_) => false
    TaskFinished(_)
    | FeedbackResponse(_)
    | ConfirmationResponse(_)
    | Connected(_)
    | Subscribed(_)
    | SessionList(_)
    | Pong => true
  }
}

// ── JSON helpers ────────────────────────────────────────────────────────────

///|
fn put_string(out : Map[String, Json], key : String, value : String) -> Unit {
  out[key] = value.to_json()
}

///|
fn put_int(out : Map[String, Json], key : String, value : Int) -> Unit {
  out[key] = value.to_json()
}

///|
fn put_double(out : Map[String, Json], key : String, value : Double) -> Unit {
  out[key] = value.to_json()
}

///|
fn put_bool(out : Map[String, Json], key : String, value : Bool) -> Unit {
  out[key] = value.to_json()
}

///|
fn put_json(out : Map[String, Json], key : String, value : Json) -> Unit {
  out[key] = value
}

///|
fn put_opt_string(
  out : Map[String, Json],
  key : String,
  value : String?,
) -> Unit {
  match value {
    Some(v) => out[key] = v.to_json()
    None => ()
  }
}

///|
fn put_opt_int(out : Map[String, Json], key : String, value : Int?) -> Unit {
  match value {
    Some(v) => out[key] = v.to_json()
    None => ()
  }
}

///|
fn put_opt_double(
  out : Map[String, Json],
  key : String,
  value : Double?,
) -> Unit {
  match value {
    Some(v) => out[key] = v.to_json()
    None => ()
  }
}

///|
fn put_opt_bool(out : Map[String, Json], key : String, value : Bool?) -> Unit {
  match value {
    Some(v) => out[key] = v.to_json()
    None => ()
  }
}

///|
fn put_opt_json(out : Map[String, Json], key : String, value : Json?) -> Unit {
  match value {
    Some(v) => out[key] = v
    None => ()
  }
}

///|
/// Read a required string field.
fn get_string(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
/// Read an optional string field (absent / null / wrong type → None).
fn get_opt_string(fields : Map[String, Json], key : String) -> String? {
  get_string(fields, key)
}

///|
/// Read an optional int field.
fn get_opt_int(fields : Map[String, Json], key : String) -> Int? {
  match fields.get(key) {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
}

///|
/// Read an optional double field.
fn get_opt_double(fields : Map[String, Json], key : String) -> Double? {
  match fields.get(key) {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
}

///|
/// Read an optional bool field.
fn get_opt_bool(fields : Map[String, Json], key : String) -> Bool? {
  match fields.get(key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
/// Read an optional raw JSON field (absent / null → None).
fn get_opt_json(fields : Map[String, Json], key : String) -> Json? {
  match fields.get(key) {
    Some(Null) | None => None
    Some(value) => Some(value)
  }
}

// ── Serialization ───────────────────────────────────────────────────────────

///|
/// Build the event body: a flat JSON object with a `type` discriminator.
/// This is the single author of every event JSON shape in the codebase.
pub fn Event::to_json(self : Event) -> Json {
  let out : Map[String, Json] = Map([])
  put_string(out, "type", self.type_name())
  match self {
    SessionUpdate(u) => {
      put_opt_string(out, "status", u.status)
      put_opt_string(out, "session_id", u.session_id)
      put_opt_double(out, "cost", u.cost)
      put_opt_string(out, "cost_source", u.cost_source)
      put_opt_json(out, "latency", u.latency)
      put_opt_json(out, "session", u.session)
    }
    Progress(p) => {
      put_string(out, "phase", p.phase)
      put_opt_string(out, "message", p.message)
      put_opt_string(out, "progress_type", p.progress_type)
      put_opt_json(out, "metadata", p.metadata)
      put_opt_string(out, "started_at", p.started_at)
    }
    PhaseStart(p) => {
      put_string(out, "phase_id", p.phase_id)
      put_opt_string(out, "kind", p.kind)
      put_opt_string(out, "label", p.label)
    }
    PhaseEnd(p) => {
      put_string(out, "phase_id", p.phase_id)
      put_opt_string(out, "summary", p.summary)
    }
    ToolCall(c) => {
      put_string(out, "name", c.name)
      put_json(out, "args", c.args)
      put_opt_json(out, "summary", c.summary)
      put_opt_string(out, "created_at", c.created_at)
    }
    ToolResult(r) => {
      put_string(out, "result", r.result)
      put_opt_string(out, "created_at", r.created_at)
    }
    ToolError(e) => put_string(out, "error", e.error)
    ErrorMessage(e) => put_string(out, "message", e.message)
    Complete(c) => {
      put_int(out, "iterations", c.iterations)
      put_double(out, "cost", c.cost)
      put_string(out, "cost_source", c.cost_source)
      put_json(
        out,
        "cache_stats",
        Json::object({
          "total_requests": c.cache_stats.total_requests.to_json(),
          "cache_hit_requests": c.cache_stats.cache_hit_requests.to_json(),
          "cache_read_input_tokens": c.cache_stats.cache_read_input_tokens.to_json(),
        }),
      )
    }
    AssistantMessage(m) => {
      put_string(out, "content", m.content)
      put_opt_string(out, "role", m.role)
      put_opt_bool(out, "partial", m.partial)
      put_opt_string(out, "created_at", m.created_at)
    }
    TokenUsage(u) => {
      put_double(out, "cost", u.cost)
      put_opt_int(out, "prompt_tokens", u.prompt_tokens)
      put_opt_int(out, "completion_tokens", u.completion_tokens)
      put_opt_int(out, "delta_tokens", u.delta_tokens)
      put_opt_int(out, "total_tokens", u.total_tokens)
      put_opt_string(out, "cost_source", u.cost_source)
      put_opt_int(out, "cache_read", u.cache_read)
      put_opt_int(out, "cache_write", u.cache_write)
    }
    TokenDelta(d) => put_string(out, "content", d.content)
    Warning(m) | Info(m) | Success(m) => put_string(out, "message", m.message)
    FilePreview(p) => {
      put_string(out, "path", p.path)
      put_string(out, "op", p.op)
    }
    ToolStdout(s) => put_string(out, "lines", s.lines)
    RequestFeedback(f) => {
      put_string(out, "question", f.question)
      put_opt_string(out, "id", f.id)
      put_opt_string(out, "context", f.context)
      match f.options {
        Some(options) =>
          put_json(
            out,
            "options",
            Json::array(options.map(fn(o) { o.to_json() })),
          )
        None => ()
      }
    }
    RequestConfirmation(c) => {
      put_string(out, "id", c.id)
      put_string(out, "message", c.message)
    }
    Interrupted => ()
    SessionRestored(r) => put_json(out, "session", r.session)
    SessionRenamed(r) => put_string(out, "name", r.name)
    SessionDeleted => ()
    HistoryUserMessage(m) => {
      put_string(out, "content", m.content)
      put_string(out, "role", m.role)
      put_opt_string(out, "created_at", m.created_at)
      put_opt_bool(out, "system_injected", m.system_injected)
    }
    TaskFinished(t) => put_string(out, "session_id", t.session_id)
    FeedbackResponse(r) => {
      put_string(out, "request_id", r.request_id)
      put_bool(out, "received", r.received)
    }
    ConfirmationResponse(r) => {
      put_string(out, "request_id", r.request_id)
      put_bool(out, "confirmed", r.confirmed)
    }
    Connected(c) => put_string(out, "session_id", c.session_id)
    Subscribed(s) => put_string(out, "session_id", s.session_id)
    SessionList(l) => {
      put_json(out, "sessions", Json::array(l.sessions))
      put_bool(out, "has_more", l.has_more)
      put_int(out, "cron_count", l.cron_count)
      put_opt_json(out, "latest_cron_updated_at", l.latest_cron_updated_at)
    }
    Pong => ()
  }
  Json::object(out)
}

///|
/// Parse an event body (the inverse of `to_json`). Returns None for an
/// unknown `type` or a body missing a required field.
pub fn Event::parse(json : Json) -> Event? {
  let fields = match json {
    Object(o) => o
    _ => return None
  }
  let kind = match get_string(fields, "type") {
    Some(t) => t
    None => return None
  }
  match kind {
    "session_update" =>
      Some(
        SessionUpdate({
          status: get_opt_string(fields, "status"),
          session_id: get_opt_string(fields, "session_id"),
          cost: get_opt_double(fields, "cost"),
          cost_source: get_opt_string(fields, "cost_source"),
          latency: get_opt_json(fields, "latency"),
          session: get_opt_json(fields, "session"),
        }),
      )
    "progress" =>
      match get_string(fields, "phase") {
        None => None
        Some(phase) =>
          Some(
            Progress({
              phase,
              message: get_opt_string(fields, "message"),
              progress_type: get_opt_string(fields, "progress_type"),
              metadata: get_opt_json(fields, "metadata"),
              started_at: get_opt_string(fields, "started_at"),
            }),
          )
      }
    "phase_start" =>
      match get_string(fields, "phase_id") {
        None => None
        Some(phase_id) =>
          Some(
            PhaseStart({
              phase_id,
              kind: get_opt_string(fields, "kind"),
              label: get_opt_string(fields, "label"),
            }),
          )
      }
    "phase_end" =>
      match get_string(fields, "phase_id") {
        None => None
        Some(phase_id) =>
          Some(
            PhaseEnd({ phase_id, summary: get_opt_string(fields, "summary"), }),
          )
      }
    "tool_call" =>
      match get_string(fields, "name") {
        None => None
        Some(name) =>
          Some(
            ToolCall({
              name,
              args: get_opt_json(fields, "args").unwrap_or(Json::null()),
              summary: get_opt_json(fields, "summary"),
              created_at: get_opt_string(fields, "created_at"),
            }),
          )
      }
    "tool_result" =>
      match get_string(fields, "result") {
        None => None
        Some(result) =>
          Some(
            ToolResult({
              result,
              created_at: get_opt_string(fields, "created_at"),
            }),
          )
      }
    "tool_error" =>
      match get_string(fields, "error") {
        None => None
        Some(error) => Some(ToolError({ error, }))
      }
    "error" =>
      match get_string(fields, "message") {
        None => None
        Some(message) => Some(ErrorMessage({ message, }))
      }
    "complete" =>
      match
        (get_opt_int(fields, "iterations"), get_opt_double(fields, "cost")) {
        (Some(iterations), Some(cost)) =>
          Some(
            Complete({
              iterations,
              cost,
              cost_source: get_opt_string(fields, "cost_source").unwrap_or(""),
              cache_stats: parse_cache_stats(fields),
            }),
          )
        _ => None
      }
    "assistant_message" =>
      match get_string(fields, "content") {
        None => None
        Some(content) =>
          Some(
            AssistantMessage({
              content,
              role: get_opt_string(fields, "role"),
              partial: get_opt_bool(fields, "partial"),
              created_at: get_opt_string(fields, "created_at"),
            }),
          )
      }
    "token_usage" =>
      match get_opt_double(fields, "cost") {
        None => None
        Some(cost) =>
          Some(
            TokenUsage({
              cost,
              prompt_tokens: get_opt_int(fields, "prompt_tokens"),
              completion_tokens: get_opt_int(fields, "completion_tokens"),
              delta_tokens: get_opt_int(fields, "delta_tokens"),
              total_tokens: get_opt_int(fields, "total_tokens"),
              cost_source: get_opt_string(fields, "cost_source"),
              cache_read: get_opt_int(fields, "cache_read"),
              cache_write: get_opt_int(fields, "cache_write"),
            }),
          )
      }
    "token_delta" =>
      match get_string(fields, "content") {
        None => None
        Some(content) => Some(TokenDelta({ content, }))
      }
    "warning" =>
      match get_string(fields, "message") {
        None => None
        Some(message) => Some(Warning({ message, }))
      }
    "info" =>
      match get_string(fields, "message") {
        None => None
        Some(message) => Some(Info({ message, }))
      }
    "success" =>
      match get_string(fields, "message") {
        None => None
        Some(message) => Some(Success({ message, }))
      }
    "file_preview" =>
      match (get_string(fields, "path"), get_string(fields, "op")) {
        (Some(path), Some(op)) => Some(FilePreview({ path, op, }))
        _ => None
      }
    "tool_stdout" =>
      match get_string(fields, "lines") {
        None => None
        Some(lines) => Some(ToolStdout({ lines, }))
      }
    "request_feedback" =>
      match get_string(fields, "question") {
        None => None
        Some(question) =>
          Some(
            RequestFeedback({
              question,
              id: get_opt_string(fields, "id"),
              context: get_opt_string(fields, "context"),
              options: parse_string_array(fields, "options"),
            }),
          )
      }
    "request_confirmation" =>
      match (get_string(fields, "id"), get_string(fields, "message")) {
        (Some(id), Some(message)) => Some(RequestConfirmation({ id, message, }))
        _ => None
      }
    "interrupted" => Some(Interrupted)
    "session_restored" =>
      match fields.get("session") {
        Some(session) => Some(SessionRestored({ session, }))
        None => None
      }
    "session_renamed" =>
      match get_string(fields, "name") {
        None => None
        Some(name) => Some(SessionRenamed({ name, }))
      }
    "session_deleted" => Some(SessionDeleted)
    "history_user_message" =>
      match get_string(fields, "content") {
        None => None
        Some(content) =>
          Some(
            HistoryUserMessage({
              content,
              role: get_opt_string(fields, "role").unwrap_or("user"),
              created_at: get_opt_string(fields, "created_at"),
              system_injected: get_opt_bool(fields, "system_injected"),
            }),
          )
      }
    "task_finished" =>
      match get_string(fields, "session_id") {
        None => None
        Some(session_id) => Some(TaskFinished({ session_id, }))
      }
    "feedback_response" =>
      match get_string(fields, "request_id") {
        None => None
        Some(request_id) =>
          Some(
            FeedbackResponse({
              request_id,
              received: get_opt_bool(fields, "received").unwrap_or(false),
            }),
          )
      }
    "confirmation_response" =>
      match get_string(fields, "request_id") {
        None => None
        Some(request_id) =>
          Some(
            ConfirmationResponse({
              request_id,
              confirmed: get_opt_bool(fields, "confirmed").unwrap_or(false),
            }),
          )
      }
    "connected" =>
      match get_string(fields, "session_id") {
        None => None
        Some(session_id) => Some(Connected({ session_id, }))
      }
    "subscribed" =>
      match get_string(fields, "session_id") {
        None => None
        Some(session_id) => Some(Subscribed({ session_id, }))
      }
    "session_list" =>
      Some(
        SessionList({
          sessions: match fields.get("sessions") {
            Some(Array(items)) => items
            _ => []
          },
          has_more: get_opt_bool(fields, "has_more").unwrap_or(false),
          cron_count: get_opt_int(fields, "cron_count").unwrap_or(0),
          latest_cron_updated_at: get_opt_json(fields, "latest_cron_updated_at"),
        }),
      )
    "pong" => Some(Pong)
    _ => None
  }
}

///|
/// Read the nested `cache_stats` object (all fields default to 0).
fn parse_cache_stats(fields : Map[String, Json]) -> CacheStats {
  match fields.get("cache_stats") {
    Some(Object(stats)) =>
      {
        total_requests: get_opt_int(stats, "total_requests").unwrap_or(0),
        cache_hit_requests: get_opt_int(stats, "cache_hit_requests").unwrap_or(
          0,
        ),
        cache_read_input_tokens: get_opt_int(stats, "cache_read_input_tokens").unwrap_or(
          0,
        ),
      }
    _ =>
      { total_requests: 0, cache_hit_requests: 0, cache_read_input_tokens: 0, }
  }
}

///|
/// Read an optional array of strings.
fn parse_string_array(
  fields : Map[String, Json],
  key : String,
) -> Array[String]? {
  match fields.get(key) {
    Some(Array(items)) => {
      let out : Array[String] = []
      for item in items {
        match item {
          String(s) => out.push(s)
          _ => ()
        }
      }
      Some(out)
    }
    _ => None
  }
}

///|
/// Frame the event body: `type` first, then the optional `session_id`, then
/// the event fields. Payload fields win on key collisions, matching the
/// historical `build_event` merge order. Use this (rather than `to_json`) when
/// the framed object is embedded in a larger JSON document, e.g. the REST
/// history events array.
pub fn Event::to_framed_json(self : Event, session_id : String?) -> Json {
  let out : Map[String, Json] = Map([])
  put_string(out, "type", self.type_name())
  match session_id {
    Some(sid) => put_string(out, "session_id", sid)
    None => ()
  }
  match self.to_json() {
    Object(fields) =>
      for entry in fields {
        if entry.0 != "type" {
          out[entry.0] = entry.1
        }
      }
    _ => ()
  }
  Json::object(out)
}

///|
/// Frame the event body for a connection as a wire string.
pub fn Event::to_wire(self : Event, session_id : String?) -> String {
  self.to_framed_json(session_id).stringify()
}

///|
/// Parse a framed wire message back into an event. Framing fields that the
/// event body does not own (`session_id`) are ignored by `parse`.
pub fn Event::from_wire(text : String) -> Event? {
  let json = @json.parse(text) catch { _ => return None }
  Event::parse(json)
}
