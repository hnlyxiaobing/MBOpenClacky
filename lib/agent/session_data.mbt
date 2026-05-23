///| Session data serialization for persisting and restoring Agent state.

///| Phase 4 implements the data structures and conversion methods.

///| Actual file I/O persistence is deferred to Phase 6.

///| Reference: openclacky/lib/clacky/agent/session_serializer.rb

///|

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
} derive(Eq, Debug)

///|
/// Export the current agent state as a SessionData snapshot.
pub fn Agent::to_session_data(self : Agent) -> SessionData {
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
impl ToJson for SessionStats with to_json(self) {
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
impl FromJson for SessionStats with from_json(json, path) {
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
impl ToJson for SessionData with to_json(self) {
  let msgs_json : Array[Json] = self.messages.map(fn(m) { ToJson::to_json(m) })
  Json::object({
    "session_id": self.session_id.to_json(),
    "name": self.name.to_json(),
    "messages": msgs_json.to_json(),
    "stats": self.stats.to_json(),
    "working_dir": self.working_dir.to_json(),
    "created_at": self.created_at.to_json(),
    "source": self.source.to_json(),
    "reasoning_effort": self.reasoning_effort.to_json(),
    "model_name": self.model_name.to_json(),
  })
}

///|
impl FromJson for SessionData with from_json(json, path) {
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
