///| Session data serialization for persisting and restoring Agent state.

///| Phase 4 implements the data structures and conversion methods.

///| Actual file I/O persistence is deferred to Phase 6.

///| Reference: openclacky/lib/clacky/agent/session_serializer.rb

///|

///|
/// IM channel information for platform session restoration.
pub(all) struct ChannelInfo {
  platform : String // "feishu", "wecom", "telegram", "discord", "dingtalk", "weixin"
  channel_id : String // Platform-specific channel identifier
  user_id : String // Platform user ID (empty string if unknown)
  webhook_url : String // Webhook URL (empty string if not configured)
} derive(Eq, Debug)

///|
pub extend ChannelInfo with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ChannelInfo with Eq::{not_equal, equal}

///|
pub extend ChannelInfo with ToJson::{to_json}

///|
pub impl ToJson for ChannelInfo with fn to_json(self) {
  Json::object({
    "platform": ToJson::to_json(self.platform),
    "channel_id": ToJson::to_json(self.channel_id),
    "user_id": ToJson::to_json(self.user_id),
    "webhook_url": ToJson::to_json(self.webhook_url),
  })
}

///|
impl FromJson for ChannelInfo with fn from_json(json, path) {
  match json {
    Object(map) => {
      let platform = match map.get("platform") {
        Some(String(s)) => s
        _ => ""
      }
      let channel_id = match map.get("channel_id") {
        Some(String(s)) => s
        _ => ""
      }
      let user_id = match map.get("user_id") {
        Some(String(s)) => s
        _ => ""
      }
      let webhook_url = match map.get("webhook_url") {
        Some(String(s)) => s
        _ => ""
      }
      { platform, channel_id, user_id, webhook_url }
    }
    _ => raise JsonDecodeError((path, "ChannelInfo: expected object"))
  }
}

///|
/// Task metadata for Time Machine session serialization.
pub(all) struct SessionTaskMeta {
  title : String // Task title (empty if unnamed)
  started_at : String // ISO timestamp when started
  ended_at : String // ISO timestamp when ended (empty if ongoing)
} derive(Eq, Debug)

///|
pub extend SessionTaskMeta with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SessionTaskMeta with Eq::{not_equal, equal}

///|
impl ToJson for SessionTaskMeta with fn to_json(self) {
  Json::object({
    "title": ToJson::to_json(self.title),
    "started_at": ToJson::to_json(self.started_at),
    "ended_at": ToJson::to_json(self.ended_at),
  })
}

///|
impl FromJson for SessionTaskMeta with fn from_json(json, path) {
  match json {
    Object(map) => {
      let title = match map.get("title") {
        Some(String(s)) => s
        _ => ""
      }
      let started_at = match map.get("started_at") {
        Some(String(s)) => s
        _ => ""
      }
      let ended_at = match map.get("ended_at") {
        Some(String(s)) => s
        _ => ""
      }
      { title, started_at, ended_at }
    }
    _ => raise JsonDecodeError((path, "SessionTaskMeta: expected object"))
  }
}

///|
/// Time Machine state for task branching/restore (serializable form).
pub(all) struct SessionTimeMachine {
  task_parents : Map[String, String] // task_id -> parent_task_id mapping
  task_meta : Map[String, SessionTaskMeta] // task_id -> metadata
  current_task_id : Int // Current active task ID
  active_task_id : Int // Active branch task ID
} derive(Eq, Debug)

///|
pub extend SessionTimeMachine with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SessionTimeMachine with Eq::{not_equal, equal}

///|
impl ToJson for SessionTimeMachine with fn to_json(self) {
  let parents_json : Map[String, Json] = Map([])
  self.task_parents.each(fn(k, v) { parents_json[k] = ToJson::to_json(v) })
  let meta_json : Map[String, Json] = Map([])
  self.task_meta.each(fn(k, v) { meta_json[k] = ToJson::to_json(v) })
  Json::object({
    "task_parents": Json::object(parents_json),
    "task_meta": Json::object(meta_json),
    "current_task_id": ToJson::to_json(self.current_task_id),
    "active_task_id": ToJson::to_json(self.active_task_id),
  })
}

///|
impl FromJson for SessionTimeMachine with fn from_json(json, path) {
  match json {
    Object(map) => {
      let task_parents : Map[String, String] = Map([])
      match map.get("task_parents") {
        Some(Object(pm)) =>
          pm.each(fn(k, v) {
            match v {
              String(s) => task_parents[k] = s
              _ => ()
            }
          })
        _ => ()
      }
      let task_meta : Map[String, SessionTaskMeta] = Map([])
      match map.get("task_meta") {
        Some(Object(mm)) =>
          mm.each(fn(k, v) raise @json.JsonDecodeError {
            let meta : SessionTaskMeta = FromJson::from_json(
              v,
              path.add_key("task_meta"),
            )
            task_meta[k] = meta
          })
        _ => ()
      }
      let current_task_id = match map.get("current_task_id") {
        Some(Number(d, ..)) => d.to_int()
        _ => 0
      }
      let active_task_id = match map.get("active_task_id") {
        Some(Number(d, ..)) => d.to_int()
        _ => 0
      }
      { task_parents, task_meta, current_task_id, active_task_id }
    }
    _ => raise JsonDecodeError((path, "SessionTimeMachine: expected object"))
  }
}

///|
/// Snapshot of an Agent session's statistics.
pub(all) struct SessionStats {
  total_iterations : Int
  total_cost_usd : Double
  total_tasks : Int
  cost_source : String
  cache_creation_input_tokens : Int
  cache_read_input_tokens : Int
  total_requests : Int
  cache_hit_requests : Int
} derive(Eq, Debug)

///|
pub extend SessionStats with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SessionStats with Eq::{not_equal, equal}

///|
/// Complete serializable snapshot of an Agent session.
pub(all) struct SessionData {
  session_id : String
  name : String
  messages : Array[@message.Message]
  stats : SessionStats
  working_dir : String
  created_at : String
  source : String
  reasoning_effort : String?
  model_name : String?
  // Config id of the selected model (ModelConfig.id); None for legacy files.
  model_config_id : String?
  // Enhanced fields for channel/latency/TimeMachine/error recovery
  channel_info : ChannelInfo?
  latest_latency_ms : Int?
  latest_ttft_ms : Int?
  time_machine : SessionTimeMachine?
  pending_error_rollback : Bool
  model_base_url : String
  last_status : String
  last_error : String
  error_code : String?
  top_up_url : String?
  raw_message : String?
  // Fork and chunk tracking
  forked_from : String?
  chunk_count : Int
  // Session model switch & agent profile (web-replication-05)
  agent_profile : String
  sub_model : String?
  // Persistence alignment (decision 3/5): pinned exemption for capacity
  // cleanup, serialized todo list, last-updated timestamp for list
  // ordering, token baseline for compression, soft-delete marker.
  pinned : Bool
  todos : Json?
  updated_at : String
  previous_total_tokens : Int
  deleted_at : String?
} derive(Eq, Debug)

///|
pub extend SessionData with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SessionData with Eq::{not_equal, equal}

///|
pub extend SessionData with ToJson::{to_json}

///|
/// Export the current agent state as a SessionData snapshot.
pub fn Agent::to_session_data(self : Agent) -> SessionData {
  let latency_ms = match self.latest_latency {
    Some(lat) => Some(lat.duration_ms)
    None => None
  }
  let ttft_ms = match self.latest_latency {
    Some(lat) => lat.ttft_ms
    None => None
  }
  {
    session_id: self.session_id,
    name: self.name,
    // Persistence view: keep all internal fields (token_usage,
    // compressed_summary, task_id, ...) and drop transient messages
    // (decision 5/13: transient never hits disk). created_at and
    // system_injected survive so history pagination and the web dedup
    // keep working across a save/load round trip.
    messages: self.history
    .all()
    .filter(fn(m) { m.transient != Some(true) })
    .map(m => m.to_persist_message()),
    stats: {
      total_iterations: self.iterations,
      total_cost_usd: self.total_cost,
      total_tasks: self.total_tasks,
      cost_source: self.cost_source.to_string_value(),
      cache_creation_input_tokens: self.cache_stats.cache_creation_input_tokens,
      cache_read_input_tokens: self.cache_stats.cache_read_input_tokens,
      total_requests: self.cache_stats.total_requests,
      cache_hit_requests: self.cache_stats.cache_hit_requests,
    },
    working_dir: self.working_dir,
    created_at: self.created_at,
    source: self.source.to_string_value(),
    reasoning_effort: self.reasoning_effort,
    model_name: Some(self.client.model),
    // session_model_overlay normalizes current_model_id to the config id.
    model_config_id: self.config.current_model_id,
    channel_info: None,
    latest_latency_ms: latency_ms,
    latest_ttft_ms: ttft_ms,
    time_machine: None,
    pending_error_rollback: self.status == Error,
    model_base_url: self.client.base_url,
    last_status: self.status.to_string_value(),
    last_error: match self.error {
      Some(e) => e
      None => ""
    },
    error_code: self.error_code,
    top_up_url: self.top_up_url,
    raw_message: self.raw_message,
    forked_from: None,
    chunk_count: 0,
    agent_profile: "general",
    sub_model: self.session_sub_model,
    pinned: self.pinned,
    todos: Some(self.todo_manager.to_json()),
    updated_at: current_timestamp_iso(),
    previous_total_tokens: self.previous_total_tokens,
    deleted_at: None,
  }
}

///|
/// Restore agent state from a SessionData snapshot.
///
/// Runs the enhanced restore path (decision 6): model recovery against the
/// current config, error-state rollback, and a system-prompt refresh to the
/// current version. Resets runtime counters and rebuilds conversation
/// history.
pub fn Agent::restore_from_session(self : Agent, data : SessionData) -> Unit {
  let result = restore_session_enhanced(self.config, data)

  // Restore identity
  self.working_dir = result.working_dir

  // Model recovery: if the saved model still exists in config, rebuild the
  // client on it (Ruby open_ai.rb:187-191); otherwise keep the current
  // default the agent was constructed with.
  if result.model_recovered && !result.recovered_model_name.is_empty() {
    self.rebuild_client_for_model(result.recovered_model_name)
  }

  // Restore conversation history: when the saved session ended in an error
  // state, roll back past the failed run first (apply_error_rollback), then
  // repair any dangling tool_calls left by interrupted runs (Ruby
  // message_history.rb:348-380 pairing guarantee).
  let messages = if result.needs_error_rollback {
    apply_error_rollback(result.messages)
  } else {
    result.messages
  }
  self.history.replace_all(messages)
  self.history.repair_dangling_tool_calls()

  // Restore statistics
  self.iterations = data.stats.total_iterations
  self.total_cost = data.stats.total_cost_usd
  self.total_tasks = data.stats.total_tasks

  // Restore cache stats
  self.cache_stats = CacheStats::new()
  self.cache_stats.cache_creation_input_tokens = data.stats.cache_creation_input_tokens
  self.cache_stats.cache_read_input_tokens = data.stats.cache_read_input_tokens
  self.cache_stats.total_requests = data.stats.total_requests
  self.cache_stats.cache_hit_requests = data.stats.cache_hit_requests

  // Restore reasoning effort
  self.reasoning_effort = data.reasoning_effort

  // Restore the per-session sub-model overlay
  self.session_sub_model = data.sub_model

  // Restore pinned flag and the task list (decision 5: both survive
  // a save/load round trip).
  self.pinned = data.pinned
  match data.todos {
    Some(todos_json) => self.todo_manager.load_from_json(todos_json)
    None => ()
  }

  // Restore the token baseline so compression does not misfire right
  // after restore (decision 6; Ruby restores previous_total_tokens).
  self.previous_total_tokens = data.previous_total_tokens

  // Reset transient state
  self.status = Idle
  self.error = None
  self.latest_latency = None
  self.fallback_state = PrimaryOk
  self.compression_level = 0
  self.mock_responses.clear()

  // Refresh the system prompt to the current version (decision 6): the
  // archived copy may reference stale models, skills, or rules.
  self.history.replace_system_prompt(self.build_system_prompt())
}

///|
impl ToJson for SessionStats with fn to_json(self) {
  Json::object({
    "total_iterations": ToJson::to_json(self.total_iterations),
    "total_cost_usd": ToJson::to_json(self.total_cost_usd),
    "total_tasks": ToJson::to_json(self.total_tasks),
    "cost_source": ToJson::to_json(self.cost_source),
    "cache_creation_input_tokens": ToJson::to_json(
      self.cache_creation_input_tokens,
    ),
    "cache_read_input_tokens": ToJson::to_json(self.cache_read_input_tokens),
    "total_requests": ToJson::to_json(self.total_requests),
    "cache_hit_requests": ToJson::to_json(self.cache_hit_requests),
  })
}

///|
impl FromJson for SessionStats with fn from_json(json, path) {
  match json {
    Object(map) => {
      let total_iterations = match map.get("total_iterations") {
        Some(Number(d, ..)) => d.to_int()
        _ =>
          raise JsonDecodeError(
            (path, "SessionStats: missing 'total_iterations'"),
          )
      }
      let total_cost_usd = match map.get("total_cost_usd") {
        Some(Number(d, ..)) => d
        _ => 0.0
      }
      let total_tasks = match map.get("total_tasks") {
        Some(Number(d, ..)) => d.to_int()
        _ =>
          raise JsonDecodeError((path, "SessionStats: missing 'total_tasks'"))
      }
      let cost_source = match map.get("cost_source") {
        Some(String(s)) => s
        _ =>
          raise JsonDecodeError((path, "SessionStats: missing 'cost_source'"))
      }
      let cache_creation_input_tokens = match
        map.get("cache_creation_input_tokens") {
        Some(Number(d, ..)) => d.to_int()
        _ => 0
      }
      let cache_read_input_tokens = match map.get("cache_read_input_tokens") {
        Some(Number(d, ..)) => d.to_int()
        _ => 0
      }
      let total_requests = match map.get("total_requests") {
        Some(Number(d, ..)) => d.to_int()
        _ => 0
      }
      let cache_hit_requests = match map.get("cache_hit_requests") {
        Some(Number(d, ..)) => d.to_int()
        _ => 0
      }
      {
        total_iterations,
        total_cost_usd,
        total_tasks,
        cost_source,
        cache_creation_input_tokens,
        cache_read_input_tokens,
        total_requests,
        cache_hit_requests,
      }
    }
    _ => raise JsonDecodeError((path, "SessionStats: expected object"))
  }
}

///|
pub impl ToJson for SessionData with fn to_json(self) {
  let msgs_json : Array[Json] = self.messages.map(m => ToJson::to_json(m))
  let obj : Map[String, Json] = {
    "session_id": ToJson::to_json(self.session_id),
    "name": ToJson::to_json(self.name),
    "messages": ToJson::to_json(msgs_json),
    "stats": ToJson::to_json(self.stats),
    "working_dir": ToJson::to_json(self.working_dir),
    "created_at": ToJson::to_json(self.created_at),
    "source": ToJson::to_json(self.source),
    "reasoning_effort": opt_string_json(self.reasoning_effort),
    "model_name": opt_string_json(self.model_name),
    "model_config_id": opt_string_json(self.model_config_id),
    "pending_error_rollback": ToJson::to_json(self.pending_error_rollback),
    "model_base_url": ToJson::to_json(self.model_base_url),
    "last_status": ToJson::to_json(self.last_status),
    "last_error": ToJson::to_json(self.last_error),
    "error_code": opt_string_json(self.error_code),
    "top_up_url": opt_string_json(self.top_up_url),
    "raw_message": opt_string_json(self.raw_message),
    "chunk_count": ToJson::to_json(self.chunk_count),
    "agent_profile": ToJson::to_json(self.agent_profile),
    "sub_model": opt_string_json(self.sub_model),
    "pinned": ToJson::to_json(self.pinned),
    "updated_at": ToJson::to_json(self.updated_at),
    "previous_total_tokens": ToJson::to_json(self.previous_total_tokens),
  }
  match self.todos {
    Some(t) => obj["todos"] = t
    None => ()
  }
  match self.deleted_at {
    Some(ts) => obj["deleted_at"] = ts.to_json()
    None => ()
  }
  match self.forked_from {
    Some(f) => obj["forked_from"] = ToJson::to_json(f)
    None => ()
  }
  match self.channel_info {
    Some(ci) => obj["channel_info"] = ToJson::to_json(ci)
    None => ()
  }
  match self.latest_latency_ms {
    Some(ms) => obj["latest_latency_ms"] = ToJson::to_json(ms)
    None => ()
  }
  match self.latest_ttft_ms {
    Some(ms) => obj["latest_ttft_ms"] = ToJson::to_json(ms)
    None => ()
  }
  match self.time_machine {
    Some(tm) => obj["time_machine"] = ToJson::to_json(tm)
    None => ()
  }
  Json::object(obj)
}

///|
impl FromJson for SessionData with fn from_json(json, path) {
  match json {
    Object(map) => {
      let session_id = match map.get("session_id") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "SessionData: missing 'session_id'"))
      }
      let name = match map.get("name") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "SessionData: missing 'name'"))
      }
      let messages = match map.get("messages") {
        Some(Array(items)) => {
          let msgs : Array[@message.Message] = []
          for item in items {
            msgs.push(FromJson::from_json(item, path.add_key("messages")))
          }
          msgs
        }
        _ => raise JsonDecodeError((path, "SessionData: missing 'messages'"))
      }
      let stats = match map.get("stats") {
        Some(s) => FromJson::from_json(s, path.add_key("stats"))
        _ => raise JsonDecodeError((path, "SessionData: missing 'stats'"))
      }
      let working_dir = match map.get("working_dir") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "SessionData: missing 'working_dir'"))
      }
      let created_at = match map.get("created_at") {
        Some(String(s)) => normalize_created_at(s)
        _ => raise JsonDecodeError((path, "SessionData: missing 'created_at'"))
      }
      let source = match map.get("source") {
        Some(String(s)) => s
        _ => "manual"
      }
      let reasoning_effort = opt_string_field(map, "reasoning_effort")
      let model_name = opt_string_field(map, "model_name")
      let model_config_id = opt_string_field(map, "model_config_id")
      // Enhanced fields — backward compatible (default if missing)
      let channel_info : ChannelInfo? = match map.get("channel_info") {
        Some(Object(_) as obj) =>
          Some(FromJson::from_json(obj, path.add_key("channel_info")))
        _ => None
      }
      let latest_latency_ms = match map.get("latest_latency_ms") {
        Some(Number(d, ..)) => Some(d.to_int())
        _ => None
      }
      let latest_ttft_ms = match map.get("latest_ttft_ms") {
        Some(Number(d, ..)) => Some(d.to_int())
        _ => None
      }
      let time_machine : SessionTimeMachine? = match map.get("time_machine") {
        Some(Object(_) as obj) =>
          Some(FromJson::from_json(obj, path.add_key("time_machine")))
        _ => None
      }
      let pending_error_rollback = match map.get("pending_error_rollback") {
        Some(True) => true
        _ => false
      }
      let model_base_url = match map.get("model_base_url") {
        Some(String(s)) => s
        _ => ""
      }
      let last_status = match map.get("last_status") {
        Some(String(s)) => s
        _ => ""
      }
      let last_error = match map.get("last_error") {
        Some(String(s)) => s
        _ => ""
      }
      let error_code = opt_string_field(map, "error_code")
      let top_up_url = opt_string_field(map, "top_up_url")
      let raw_message = opt_string_field(map, "raw_message")
      let forked_from = match map.get("forked_from") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let chunk_count = match map.get("chunk_count") {
        Some(Number(d, ..)) => d.to_int()
        _ => 0
      }
      let agent_profile = match map.get("agent_profile") {
        Some(String(s)) => s
        _ => "general"
      }
      let sub_model = opt_string_field(map, "sub_model")
      let pinned = match map.get("pinned") {
        Some(True) => true
        _ => false
      }
      let todos = match map.get("todos") {
        Some(Null) | None => None
        Some(j) => Some(j)
      }
      let updated_at = match map.get("updated_at") {
        Some(String(s)) => s
        _ => created_at
      }
      let previous_total_tokens = match map.get("previous_total_tokens") {
        Some(Number(d, ..)) => d.to_int()
        _ => 0
      }
      let deleted_at = match map.get("deleted_at") {
        Some(String(s)) => Some(s)
        _ => None
      }
      {
        session_id,
        name,
        messages,
        stats,
        working_dir,
        created_at,
        source,
        reasoning_effort,
        model_name,
        model_config_id,
        channel_info,
        latest_latency_ms,
        latest_ttft_ms,
        time_machine,
        pending_error_rollback,
        model_base_url,
        last_status,
        last_error,
        error_code,
        top_up_url,
        raw_message,
        forked_from,
        chunk_count,
        agent_profile,
        sub_model,
        pinned,
        todos,
        updated_at,
        previous_total_tokens,
        deleted_at,
      }
    }
    _ => raise JsonDecodeError((path, "SessionData: expected object"))
  }
}

///|
/// Generate a unique, unpredictable session ID: 16 lowercase hex chars
/// (64 bits of entropy), matching the Ruby reference's random-hex
/// semantics. Millisecond timestamps could collide under rapid session
/// creation, silently overwriting an existing session file.
pub fn generate_session_id() -> String {
  let rng = @random.Rand::new()
  let hex_chars = "0123456789abcdef"
  let mut id = ""
  for _i = 0; _i < 16; _i = _i + 1 {
    let idx = rng.int(limit=16)
    id = id + hex_chars[idx:idx + 1].to_owned()
  }
  id
}

///|
/// Get the current timestamp as an ISO 8601 local-time string
/// (e.g. "2026-07-24T12:22:34+08:00"), matching the reference
/// implementation's serialized timestamp format.
pub fn current_timestamp_iso() -> String {
  current_iso8601()
}

///|
/// Normalize a persisted `created_at` value to ISO 8601 local format.
/// Handles two legacy dirty formats produced by earlier builds:
/// - Windows-epoch ms strings (1601-based, > 1e13): subtract the
///   1601→1970 offset, then convert to ISO.
/// - Unix epoch ms strings (plain digits): convert to ISO directly.
/// Non-numeric values are assumed to already be ISO and kept as-is.
fn normalize_created_at(s : String) -> String {
  if s.is_empty() {
    return s
  }
  let mut ms = 0L
  for i in 0..<s.length() {
    let c = s[i]
    if c < '0' || c > '9' {
      return s
    }
    ms = ms * 10L + (c.to_int() - '0'.to_int()).to_int64()
    // Bail out far below Int64 overflow; no real timestamp is this large.
    if ms > 100000000000000L {
      return s
    }
  }
  if ms > 10000000000000L {
    ms = ms - 11644473600000L
  }
  ms_to_iso8601(ms)
}

///|
/// Parse an optional-string field that may have been persisted either as a
/// plain string or (by a previous broken Option serializer) as `[string]`.
fn opt_string_field(map : Map[String, Json], key : String) -> String? {
  match map.get(key) {
    Some(String(s)) => Some(s)
    Some(Array([String(s)])) => Some(s)
    _ => None
  }
}

///|
/// Serialize a `String?` field as a plain string or null (never an array).
fn opt_string_json(value : String?) -> Json {
  match value {
    Some(s) => s.to_json()
    None => Json::null()
  }
}
