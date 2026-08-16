///|
/// Telemetry event types
pub(all) enum TelemetryEventType {
  Startup
  Task
  Share
} derive(Eq, Debug, ToJson)

///|
pub extend TelemetryEventType with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TelemetryEventType with Eq::{not_equal, equal}

///|
pub extend TelemetryEventType with ToJson::{to_json}

///|
/// Startup event payload
pub(all) struct StartupPayload {
  device_id : String
  version : String
  brand : String?
  container : String?
} derive(Eq, Debug, ToJson)

///|
pub extend StartupPayload with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend StartupPayload with Eq::{not_equal, equal}

///|
pub extend StartupPayload with ToJson::{to_json}

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
} derive(Eq, Debug, ToJson)

///|
pub extend TaskPayload with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TaskPayload with Eq::{not_equal, equal}

///|
pub extend TaskPayload with ToJson::{to_json}

///|
/// Share event payload
pub(all) struct SharePayload {
  device_id : String
  event : String
  extra : Map[String, String]?
} derive(Eq, Debug, ToJson)

///|
pub extend SharePayload with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SharePayload with Eq::{not_equal, equal}

///|
pub extend SharePayload with ToJson::{to_json}

///|
/// Unified telemetry event
pub(all) enum TelemetryEvent {
  StartupEvent(StartupPayload)
  TaskEvent(TaskPayload)
  ShareEvent(SharePayload)
} derive(Eq, Debug, ToJson)

///|
pub extend TelemetryEvent with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TelemetryEvent with Eq::{not_equal, equal}

///|
pub extend TelemetryEvent with ToJson::{to_json}
