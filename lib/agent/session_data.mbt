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
} derive(Eq, Debug, Show)

///|
impl ToJson for ChannelInfo with fn to_json(self) {
  Json::object({
    "platform": self.platform.to_json(),
    "channel_id": self.channel_id.to_json(),
    "user_id": self.user_id.to_json(),
    "webhook_url": self.webhook_url.to_json(),
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
} derive(Eq, Debug, Show)

///|
impl ToJson for SessionTaskMeta with fn to_json(self) {
  Json::object({
    "title": self.title.to_json(),
    "started_at": self.started_at.to_json(),
    "ended_at": self.ended_at.to_json(),
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
} derive(Eq, Debug, Show)

///|
impl ToJson for SessionTimeMachine with fn to_json(self) {
  let parents_json : Map[String, Json] = {}
  self.task_parents.each(fn(k, v) { parents_json[k] = v.to_json() })
  let meta_json : Map[String, Json] = {}
  self.task_meta.each(fn(k, v) { meta_json[k] = v.to_json() })
  Json::object({
    "task_parents": Json::object(parents_json),
    "task_meta": Json::object(meta_json),
    "current_task_id": self.current_task_id.to_json(),
    "active_task_id": self.active_task_id.to_json(),
  })
}

///|
impl FromJson for SessionTimeMachine with fn from_json(json, path) {
  match json {
    Object(map) => {
      let task_parents : Map[String, String] = {}
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
      let task_meta : Map[String, SessionTaskMeta] = {}
      match map.get("task_meta") {
        Some(Object(mm)) =>
          mm.each(fn(k, v) {
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
  // Enhanced fields for channel/latency/TimeMachine/error recovery
  channel_info : ChannelInfo?
  latest_latency_ms : Int?
  latest_ttft_ms : Int?
  time_machine : SessionTimeMachine?
  pending_error_rollback : Bool
  model_base_url : String
  last_status : String
  last_error : String
} derive(Eq, Debug)

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
    messages: self.history.map(m => m.to_api_message()),
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
  }
}

///|
/// Restore agent state from a SessionData snapshot.
///
/// Resets runtime counters and rebuilds conversation history.
pub fn Agent::restore_from_session(self : Agent, data : SessionData) -> Unit {
  // Restore identity
  self.working_dir = data.working_dir

  // Restore conversation history
  self.history.clear()
  for msg in data.messages {
    self.history.push(msg)
  }

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

  // Reset transient state
  self.status = Idle
  self.error = None
  self.latest_latency = None
  self.fallback_state = PrimaryOk
  self.compression_level = 0
  self.previous_total_tokens = 0
  self.mock_responses.clear()
}

///|
impl ToJson for SessionStats with fn to_json(self) {
  Json::object({
    "total_iterations": self.total_iterations.to_json(),
    "total_cost_usd": self.total_cost_usd.to_json(),
    "total_tasks": self.total_tasks.to_json(),
    "cost_source": self.cost_source.to_json(),
    "cache_creation_input_tokens": self.cache_creation_input_tokens.to_json(),
    "cache_read_input_tokens": self.cache_read_input_tokens.to_json(),
    "total_requests": self.total_requests.to_json(),
    "cache_hit_requests": self.cache_hit_requests.to_json(),
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
    "session_id": self.session_id.to_json(),
    "name": self.name.to_json(),
    "messages": msgs_json.to_json(),
    "stats": self.stats.to_json(),
    "working_dir": self.working_dir.to_json(),
    "created_at": self.created_at.to_json(),
    "source": self.source.to_json(),
    "reasoning_effort": self.reasoning_effort.to_json(),
    "model_name": self.model_name.to_json(),
    "pending_error_rollback": self.pending_error_rollback.to_json(),
    "model_base_url": self.model_base_url.to_json(),
    "last_status": self.last_status.to_json(),
    "last_error": self.last_error.to_json(),
  }
  match self.channel_info {
    Some(ci) => obj["channel_info"] = ci.to_json()
    None => ()
  }
  match self.latest_latency_ms {
    Some(ms) => obj["latest_latency_ms"] = ms.to_json()
    None => ()
  }
  match self.latest_ttft_ms {
    Some(ms) => obj["latest_ttft_ms"] = ms.to_json()
    None => ()
  }
  match self.time_machine {
    Some(tm) => obj["time_machine"] = tm.to_json()
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
        Some(s) => SessionStats::from_json(s, path.add_key("stats"))
        _ => raise JsonDecodeError((path, "SessionData: missing 'stats'"))
      }
      let working_dir = match map.get("working_dir") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "SessionData: missing 'working_dir'"))
      }
      let created_at = match map.get("created_at") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "SessionData: missing 'created_at'"))
      }
      let source = match map.get("source") {
        Some(String(s)) => s
        _ => "manual"
      }
      let reasoning_effort = match map.get("reasoning_effort") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let model_name = match map.get("model_name") {
        Some(String(s)) => Some(s)
        _ => None
      }
      // Enhanced fields — backward compatible (default if missing)
      let channel_info : ChannelInfo? = match map.get("channel_info") {
        Some(Object(_) as obj) =>
          Some(ChannelInfo::from_json(obj, path.add_key("channel_info")))
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
          Some(SessionTimeMachine::from_json(obj, path.add_key("time_machine")))
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
        channel_info,
        latest_latency_ms,
        latest_ttft_ms,
        time_machine,
        pending_error_rollback,
        model_base_url,
        last_status,
        last_error,
      }
    }
    _ => raise JsonDecodeError((path, "SessionData: expected object"))
  }
}

///|
/// Generate a unique session ID based on the current timestamp.
pub fn generate_session_id() -> String {
  "s_" + current_time_ms().to_string()
}

///|
/// Get the current timestamp as a millisecond string.
pub fn current_timestamp_ms() -> String {
  current_time_ms().to_string()
}
