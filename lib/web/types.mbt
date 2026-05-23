///| DTO types for Web API request/response.

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
/// Response for session list
pub(all) struct SessionListResponse {
  sessions : Array[@agent.SessionData]
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
impl ToJson for SessionListResponse with to_json(self) {
  Json::object({ "sessions": self.sessions.to_json() })
}

///|
impl ToJson for ToolListEntry with to_json(self) {
  Json::object({
    "name": self.name.to_json(),
    "description": self.description.to_json(),
  })
}

///|
impl ToJson for ToolListResponse with to_json(self) {
  Json::object({ "tools": self.tools.to_json() })
}

///|
impl ToJson for ChatResponse with to_json(self) {
  Json::object({
    "session_id": self.session_id.to_json(),
    "messages": self.messages.to_json(),
    "total_cost_usd": self.total_cost_usd.to_json(),
    "iterations": self.iterations.to_json(),
    "status": self.status.to_json(),
  })
}

///|
impl ToJson for StatusResponse with to_json(self) {
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
impl ToJson for CancelResponse with to_json(self) {
  Json::object({ "cancelled": self.cancelled.to_json() })
}

///|
impl ToJson for CostResponse with to_json(self) {
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
impl ToJson for StatsResponse with to_json(self) {
  Json::object({
    "total_sessions": self.total_sessions.to_json(),
    "total_cost_usd": self.total_cost_usd.to_json(),
    "total_iterations": self.total_iterations.to_json(),
    "total_tasks": self.total_tasks.to_json(),
  })
}

///|
impl ToJson for AggregateStatsResponse with to_json(self) {
  Json::object({
    "total_cost_usd": self.total_cost_usd.to_json(),
    "session_count": self.session_count.to_json(),
    "total_messages": self.total_messages.to_json(),
  })
}

///|
impl ToJson for HealthResponse with to_json(self) {
  Json::object({
    "status": self.status.to_json(),
    "uptime_seconds": self.uptime_seconds.to_json(),
  })
}

///|
impl ToJson for InfoResponse with to_json(self) {
  Json::object({
    "version": self.version.to_json(),
    "name": self.name.to_json(),
    "uptime_seconds": self.uptime_seconds.to_json(),
    "active_sessions": self.active_sessions.to_json(),
  })
}

///|
impl ToJson for ConfigResponse with to_json(self) {
  Json::object({
    "permission_mode": self.permission_mode.to_json(),
    "max_tokens": self.max_tokens.to_json(),
    "verbose": self.verbose.to_json(),
    "current_model_id": self.current_model_id.to_json(),
  })
}

///|
impl ToJson for ModelListResponse with to_json(self) {
  Json::object({ "models": self.models.to_json() })
}

///|
impl ToJson for PermissionResponse with to_json(self) {
  Json::object({
    "permission_mode": self.permission_mode.to_json(),
    "safe_tools": self.safe_tools.to_json(),
  })
}
