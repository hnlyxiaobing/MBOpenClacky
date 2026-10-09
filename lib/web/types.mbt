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
  // Note: `Json(m.type_)` would serialize `Some("claude")` as `["claude"]`
  // because MoonBit's `ToJson for T?` uses array form (`[value]`). We want a
  // plain string (or null) for the frontend, matching derived struct behavior.
  let type_json = match m.type_ {
    Some(v) => Json(v)
    None => Json::null()
  }
  Json::object({
    "id": Json(m.id),
    "type": type_json,
    "model": Json(m.model),
    "base_url": Json(m.base_url),
    "api_key_masked": Json(web_mask_api_key(m.api_key)),
    "anthropic_format": Json(m.anthropic_format),
  })
}

///|
/// Request body for POST /api/sessions/:id/chat
pub(all) struct ChatRequest {
  message : String
} derive(FromJson)

///|
pub extend ChatRequest with @moonbitlang/core/json.FromJson::{from_json}

///|
/// Request body for POST /api/sessions
pub(all) struct CreateSessionRequest {
  name : String?
} derive(FromJson)

///|
pub extend CreateSessionRequest with @moonbitlang/core/json.FromJson::{
  from_json,
}

///|
/// Request body for PUT /api/config
pub(all) struct UpdateConfigRequest {
  permission_mode : String?
  max_tokens : Int?
  verbose : Bool?
  max_tokens_request : Int? // moonbit limitation: field name 'max_tokens' clashes, use workaround
} derive(FromJson)

///|
pub extend UpdateConfigRequest with @moonbitlang/core/json.FromJson::{from_json}

///|
/// Latency summary embedded in SessionSummary as `latest_latency`.
/// The frontend reads `lat.ttft_ms` as the visibility condition for the
/// latency signal, so the object shape (not a bare ms number) is required.
pub(all) struct SessionLatency {
  ttft_ms : Int?
  duration_ms : Int?
} derive(Eq, Debug)

///|
pub extend SessionLatency with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SessionLatency with Eq::{not_equal, equal}

///|
/// Build the latency summary from a SessionData snapshot.
/// None when neither ttft nor duration is known (frontend hides the signal).
pub fn SessionLatency::from_session_data(
  sd : @agent.SessionData,
) -> SessionLatency? {
  match (sd.latest_ttft_ms, sd.latest_latency_ms) {
    (None, None) => None
    (ttft_ms, duration_ms) => Some({ ttft_ms, duration_ms, })
  }
}

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
  latest_latency : SessionLatency?
  // Extended fields (web-replication-05)
  pinned : Bool
  agent_profile : String
  sub_model : String?
  sub_model_options : Array[String]
  reasoning_effort : String?
  // fix-09: additional fields for frontend parity
  model_id : String?
  card_model : String?
  channel_info : @agent.ChannelInfo?
  error_code : String?
  top_up_url : String?
  raw_message : String?
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

///|
pub extend SessionSummary with ToJson::{to_json}

// ── JSON serialization for response types ────────────────────────

///|
pub impl ToJson for SessionSummary with fn to_json(self) {
  let latest_latency = match self.latest_latency {
    Some(lat) => {
      let ttft = match lat.ttft_ms {
        Some(v) => Json(v)
        None => Json::null()
      }
      let duration = match lat.duration_ms {
        Some(v) => Json(v)
        None => Json::null()
      }
      Json::object({ "ttft_ms": ttft, "duration_ms": duration })
    }
    None => Json::null()
  }
  let model = match self.model {
    Some(v) => Json(v)
    None => Json::null()
  }
  let sub_model = match self.sub_model {
    Some(v) => Json(v)
    None => Json::null()
  }
  let reasoning_effort = match self.reasoning_effort {
    Some(v) => Json(v)
    None => Json::null()
  }
  let model_id = match self.model_id {
    Some(v) => Json(v)
    None => Json::null()
  }
  let card_model = match self.card_model {
    Some(v) => Json(v)
    None => Json::null()
  }
  let channel_info = match self.channel_info {
    Some(ci) => ToJson::to_json(ci)
    None => Json::null()
  }
  let error_code = match self.error_code {
    Some(v) => Json(v)
    None => Json::null()
  }
  let top_up_url = match self.top_up_url {
    Some(v) => Json(v)
    None => Json::null()
  }
  let raw_message = match self.raw_message {
    Some(v) => Json(v)
    None => Json::null()
  }
  Json::object({
    "id": Json(self.id),
    "name": Json(self.name),
    "working_dir": Json(self.working_dir),
    "status": Json(self.status),
    "created_at": Json(self.created_at),
    "updated_at": Json(self.updated_at),
    "total_tasks": Json(self.total_tasks),
    "total_cost": Json(self.total_cost),
    "cost_source": Json(self.cost_source),
    "error": Json(self.error),
    "model": model,
    "source": Json(self.source),
    "latest_latency": latest_latency,
    "pinned": Json(self.pinned),
    "agent_profile": Json(self.agent_profile),
    "sub_model": sub_model,
    "sub_model_options": Json(self.sub_model_options),
    "reasoning_effort": reasoning_effort,
    "model_id": model_id,
    "card_model": card_model,
    "channel_info": channel_info,
    "error_code": error_code,
    "top_up_url": top_up_url,
    "raw_message": raw_message,
  })
}

///|
pub extend SessionListResponse with ToJson::{to_json}

///|
pub impl ToJson for SessionListResponse with fn to_json(self) {
  let cron_updated = match self.latest_cron_updated_at {
    Some(v) => Json(v)
    None => Json::null()
  }
  Json::object({
    "sessions": Json(self.sessions),
    "has_more": Json(self.has_more),
    "cron_count": Json(self.cron_count),
    "latest_cron_updated_at": cron_updated,
  })
}

///|
impl ToJson for ToolListEntry with fn to_json(self) {
  Json::object({
    "name": Json(self.name),
    "description": Json(self.description),
  })
}

///|
impl ToJson for ToolListResponse with fn to_json(self) {
  Json::object({ "tools": Json(self.tools) })
}

///|
impl ToJson for StatusResponse with fn to_json(self) {
  let err = match self.error {
    Some(e) => Some(Json(e))
    None => None
  }
  Json::object({
    "session_id": Json(self.session_id),
    "status": Json(self.status),
    "iterations": Json(self.iterations),
    "error": err,
  })
}

///|
impl ToJson for CancelResponse with fn to_json(self) {
  Json::object({ "cancelled": Json(self.cancelled) })
}

///|
impl ToJson for CostResponse with fn to_json(self) {
  Json::object({
    "session_id": Json(self.session_id),
    "total_cost_usd": Json(self.total_cost_usd),
    "cost_source": Json(self.cost_source),
    "cache_creation_input_tokens": Json(self.cache_creation_input_tokens),
    "cache_read_input_tokens": Json(self.cache_read_input_tokens),
    "total_requests": Json(self.total_requests),
    "cache_hit_requests": Json(self.cache_hit_requests),
  })
}

///|
impl ToJson for StatsResponse with fn to_json(self) {
  Json::object({
    "total_sessions": Json(self.total_sessions),
    "total_cost_usd": Json(self.total_cost_usd),
    "total_iterations": Json(self.total_iterations),
    "total_tasks": Json(self.total_tasks),
  })
}

///|
impl ToJson for AggregateStatsResponse with fn to_json(self) {
  Json::object({
    "total_cost_usd": Json(self.total_cost_usd),
    "session_count": Json(self.session_count),
    "total_messages": Json(self.total_messages),
  })
}

///|
pub extend HealthResponse with ToJson::{to_json}

///|
pub impl ToJson for HealthResponse with fn to_json(self) {
  Json::object({
    "status": Json(self.status),
    "uptime_seconds": Json(self.uptime_seconds),
  })
}

///|
impl ToJson for InfoResponse with fn to_json(self) {
  Json::object({
    "version": Json(self.version),
    "name": Json(self.name),
    "uptime_seconds": Json(self.uptime_seconds),
    "active_sessions": Json(self.active_sessions),
  })
}

///|
impl ToJson for ModelListResponse with fn to_json(self) {
  let models_json : Array[Json] = []
  for m in self.models {
    models_json.push(model_to_web_json(m))
  }
  Json::object({ "models": Json(models_json) })
}

///|
impl ToJson for PermissionResponse with fn to_json(self) {
  Json::object({
    "permission_mode": Json(self.permission_mode),
    "safe_tools": Json(self.safe_tools),
  })
}
