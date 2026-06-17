///|
/// Telemetry event types
pub(all) enum TelemetryEventType {
  Startup
  Task
  Share
} derive(Eq, Show, Debug, ToJson)

///|
/// Startup event payload
pub(all) struct StartupPayload {
  device_id : String
  version : String
  brand : String?
  container : String?
} derive(Eq, Show, Debug, ToJson)

///|
/// Task completion event payload
pub(all) struct TaskPayload {
  device_id : String
  version : String
  brand : String?
  model : String
  provider : String
  status : String
  iterations : Int
  duration_ms : Int
  cost_usd : Double
  prompt_tokens : Int
  completion_tokens : Int
  cache_creation_tokens : Int
  cache_read_tokens : Int
} derive(Eq, Show, Debug, ToJson)

///|
/// Share event payload
pub(all) struct SharePayload {
  device_id : String
  event : String
  extra : Map[String, String]?
} derive(Eq, Show, Debug, ToJson)

///|
/// Unified telemetry event
pub(all) enum TelemetryEvent {
  StartupEvent(StartupPayload)
  TaskEvent(TaskPayload)
  ShareEvent(SharePayload)
} derive(Eq, Show, Debug, ToJson)
