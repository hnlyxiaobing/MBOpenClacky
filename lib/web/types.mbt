///| DTO types for Web API request/response.

///|
/// Mask an API key for display: show first 3 and last 4 characters.
/// e.g. "sk-ant-abc123xyz789" -> "sk-...z789"
/// Mirrors lib/tui/dialog_config_menu::mask_api_key.
fn web_mask_api_key(key : String) -> String {
  let len = key.length()
  if len <= 8 {
    "****"
  } else {
    "\{key[0:3]}...\{key[len - 4:]}"
  }
}

///|
/// Convert a ModelConfig to the JSON shape the web frontend expects.
/// Key differences from the derived ToJson:
///   - api_key -> api_key_masked (masked, never exposes the raw key)
///   - type_   -> type (frontend uses `model.type`)
fn model_to_web_json(m : @config.ModelConfig) -> Json {
  // Note: `m.type_.to_json()` would serialize `Some("claude")` as `["claude"]`
  // because MoonBit's `ToJson for T?` uses array form (`[value]`). We want a
  // plain string (or null) for the frontend, matching derived struct behavior.
  let type_json = match m.type_ {
    Some(v) => v.to_json()
    None => Json::null()
  }
  Json::object({
    "id": m.id.to_json(),
    "type": type_json,
    "model": m.model.to_json(),
    "base_url": m.base_url.to_json(),
    "api_key_masked": web_mask_api_key(m.api_key).to_json(),
    "anthropic_format": m.anthropic_format.to_json(),
  })
}

///|
/// Request body for POST /api/sessions/:id/chat
pub(all) struct ChatRequest {
  message : String
} derive(FromJson)

///|
/// Request body for POST /api/sessions
pub(all) struct CreateSessionRequest {
  name : String?
} derive(FromJson)

///|
/// Request body for PUT /api/config
pub(all) struct UpdateConfigRequest {
  permission_mode : String?
  max_tokens : Int?
  verbose : Bool?
  max_tokens_request : Int? // moonbit limitation: field name 'max_tokens' clashes, use workaround
} derive(FromJson)

///|
/// Lightweight session summary returned by GET /api/sessions.
/// Mirrors the upstream SessionSummary contract.
pub(all) struct SessionSummary {
  id : String
  name : String
  working_dir : String
  status : String
  created_at : String
  updated_at : String
  total_tasks : Int
  total_cost : Double
  cost_source : String
  error : String
  model : String?
  source : String
  latest_latency_ms : Int?
  // Extended fields (web-replication-05)
  pinned : Bool
  agent_profile : String
  sub_model : String?
  sub_model_options : Array[String]
  reasoning_effort : String?
}

///|
/// Response for session list (GET /api/sessions).
pub(all) struct SessionListResponse {
  sessions : Array[SessionSummary]
  has_more : Bool
  cron_count : Int
  latest_cron_updated_at : String?
}

///|
/// Tool list entry
pub(all) struct ToolListEntry {
  name : String
  description : String
}

///|
/// Tool list response
pub(all) struct ToolListResponse {
  tools : Array[ToolListEntry]
}

///|
/// Chat response (blocking endpoint)
pub(all) struct ChatResponse {
  session_id : String
  messages : Array[@message.Message]
  total_cost_usd : Double
  iterations : Int
  status : String
}

///|
/// Status response
pub(all) struct StatusResponse {
  session_id : String
  status : String
  iterations : Int
  error : String?
}

///|
/// Cancel response
pub(all) struct CancelResponse {
  cancelled : Bool
}

///|
/// Cost response
pub(all) struct CostResponse {
  session_id : String
  total_cost_usd : Double
  cost_source : String
  cache_creation_input_tokens : Int
  cache_read_input_tokens : Int
  total_requests : Int
  cache_hit_requests : Int
}

///|
/// Global stats response
pub(all) struct StatsResponse {
  total_sessions : Int
  total_cost_usd : Double
  total_iterations : Int
  total_tasks : Int
}

///|
/// Aggregate stats response
pub(all) struct AggregateStatsResponse {
  total_cost_usd : Double
  session_count : Int
  total_messages : Int
}

///|
/// Health response
pub(all) struct HealthResponse {
  status : String
  uptime_seconds : Int64
}

///|
/// Info response
pub(all) struct InfoResponse {
  version : String
  name : String
  uptime_seconds : Int64
  active_sessions : Int
}

///|
/// Config response (wraps AgentConfig)
pub(all) struct ConfigResponse {
  permission_mode : String
  max_tokens : Int
  verbose : Bool
  current_model_id : String?
  models : Array[@config.ModelConfig]
}

///|
/// Model list response
pub(all) struct ModelListResponse {
  models : Array[@config.ModelConfig]
}

///|
/// Permission info response
pub(all) struct PermissionResponse {
  permission_mode : String
  safe_tools : Array[String]
}

// ── JSON serialization for response types ────────────────────────

///|
pub impl ToJson for SessionSummary with fn to_json(self) {
  let latency = match self.latest_latency_ms {
    Some(v) => v.to_json()
    None => Json::null()
  }
  let model = match self.model {
    Some(v) => v.to_json()
    None => Json::null()
  }
  let sub_model = match self.sub_model {
    Some(v) => v.to_json()
    None => Json::null()
  }
  let reasoning_effort = match self.reasoning_effort {
    Some(v) => v.to_json()
    None => Json::null()
  }
  Json::object({
    "id": self.id.to_json(),
    "name": self.name.to_json(),
    "working_dir": self.working_dir.to_json(),
    "status": self.status.to_json(),
    "created_at": self.created_at.to_json(),
    "updated_at": self.updated_at.to_json(),
    "total_tasks": self.total_tasks.to_json(),
    "total_cost": self.total_cost.to_json(),
    "cost_source": self.cost_source.to_json(),
    "error": self.error.to_json(),
    "model": model,
    "source": self.source.to_json(),
    "latest_latency_ms": latency,
    "pinned": self.pinned.to_json(),
    "agent_profile": self.agent_profile.to_json(),
    "sub_model": sub_model,
    "sub_model_options": self.sub_model_options.to_json(),
    "reasoning_effort": reasoning_effort,
  })
}

///|
pub impl ToJson for SessionListResponse with fn to_json(self) {
  let cron_updated = match self.latest_cron_updated_at {
    Some(v) => v.to_json()
    None => Json::null()
  }
  Json::object({
    "sessions": self.sessions.to_json(),
    "has_more": self.has_more.to_json(),
    "cron_count": self.cron_count.to_json(),
    "latest_cron_updated_at": cron_updated,
  })
}

///|
impl ToJson for ToolListEntry with fn to_json(self) {
  Json::object({
    "name": self.name.to_json(),
    "description": self.description.to_json(),
  })
}

///|
impl ToJson for ToolListResponse with fn to_json(self) {
  Json::object({ "tools": self.tools.to_json() })
}

///|
impl ToJson for ChatResponse with fn to_json(self) {
  Json::object({
    "session_id": self.session_id.to_json(),
    "messages": self.messages.to_json(),
    "total_cost_usd": self.total_cost_usd.to_json(),
    "iterations": self.iterations.to_json(),
    "status": self.status.to_json(),
  })
}

///|
impl ToJson for StatusResponse with fn to_json(self) {
  let err = match self.error {
    Some(e) => Some(e.to_json())
    None => None
  }
  Json::object({
    "session_id": self.session_id.to_json(),
    "status": self.status.to_json(),
    "iterations": self.iterations.to_json(),
    "error": err,
  })
}

///|
impl ToJson for CancelResponse with fn to_json(self) {
  Json::object({ "cancelled": self.cancelled.to_json() })
}

///|
impl ToJson for CostResponse with fn to_json(self) {
  Json::object({
    "session_id": self.session_id.to_json(),
    "total_cost_usd": self.total_cost_usd.to_json(),
    "cost_source": self.cost_source.to_json(),
    "cache_creation_input_tokens": self.cache_creation_input_tokens.to_json(),
    "cache_read_input_tokens": self.cache_read_input_tokens.to_json(),
    "total_requests": self.total_requests.to_json(),
    "cache_hit_requests": self.cache_hit_requests.to_json(),
  })
}

///|
impl ToJson for StatsResponse with fn to_json(self) {
  Json::object({
    "total_sessions": self.total_sessions.to_json(),
    "total_cost_usd": self.total_cost_usd.to_json(),
    "total_iterations": self.total_iterations.to_json(),
    "total_tasks": self.total_tasks.to_json(),
  })
}

///|
impl ToJson for AggregateStatsResponse with fn to_json(self) {
  Json::object({
    "total_cost_usd": self.total_cost_usd.to_json(),
    "session_count": self.session_count.to_json(),
    "total_messages": self.total_messages.to_json(),
  })
}

///|
pub impl ToJson for HealthResponse with fn to_json(self) {
  Json::object({
    "status": self.status.to_json(),
    "uptime_seconds": self.uptime_seconds.to_json(),
  })
}

///|
impl ToJson for InfoResponse with fn to_json(self) {
  Json::object({
    "version": self.version.to_json(),
    "name": self.name.to_json(),
    "uptime_seconds": self.uptime_seconds.to_json(),
    "active_sessions": self.active_sessions.to_json(),
  })
}

///|
impl ToJson for ConfigResponse with fn to_json(self) {
  let models_json : Array[Json] = []
  for m in self.models {
    models_json.push(model_to_web_json(m))
  }
  Json::object({
    "permission_mode": self.permission_mode.to_json(),
    "max_tokens": self.max_tokens.to_json(),
    "verbose": self.verbose.to_json(),
    "current_model_id": self.current_model_id.to_json(),
    "models": models_json.to_json(),
  })
}

///|
impl ToJson for ModelListResponse with fn to_json(self) {
  let models_json : Array[Json] = []
  for m in self.models {
    models_json.push(model_to_web_json(m))
  }
  Json::object({ "models": models_json.to_json() })
}

///|
impl ToJson for PermissionResponse with fn to_json(self) {
  Json::object({
    "permission_mode": self.permission_mode.to_json(),
    "safe_tools": self.safe_tools.to_json(),
  })
}
