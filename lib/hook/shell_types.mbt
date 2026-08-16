///|
/// Shell hook event types
pub(all) enum ShellHookEvent {
  BeforeToolUse
  AfterToolUse
  OnToolError
  OnStart
  OnIteration
  OnComplete
  SessionRollback
} derive(Eq, Debug, ToJson)

///|
pub extend ShellHookEvent with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ShellHookEvent with Eq::{not_equal, equal}

///|
pub extend ShellHookEvent with ToJson::{to_json}

///|
/// A single shell hook definition
pub(all) struct ShellHook {
  name : String?
  command : String
  timeout : Int
  event : ShellHookEvent
} derive(Eq, Debug, ToJson)

///|
pub extend ShellHook with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ShellHook with Eq::{not_equal, equal}

///|
pub extend ShellHook with ToJson::{to_json}

///|
/// Hook execution result
pub(all) enum HookExecResult {
  Allow
  Deny(String)
  Error(String)
} derive(Eq, Debug, ToJson)

///|
pub extend HookExecResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend HookExecResult with Eq::{not_equal, equal}

///|
pub extend HookExecResult with ToJson::{to_json}

///|
/// Shell hook configuration (from hooks.yml)
pub(all) struct ShellHookConfig {
  hooks : Map[String, Array[ShellHook]]
} derive(Eq, Debug, ToJson)

///|
pub extend ShellHookConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ShellHookConfig with Eq::{not_equal, equal}

///|
pub extend ShellHookConfig with ToJson::{to_json}

///|
/// Parse event name string to ShellHookEvent
pub fn parse_hook_event(name : String) -> ShellHookEvent? {
  match name {
    "before_tool_use" => Some(BeforeToolUse)
    "after_tool_use" => Some(AfterToolUse)
    "on_tool_error" => Some(OnToolError)
    "on_start" => Some(OnStart)
    "on_iteration" => Some(OnIteration)
    "on_complete" => Some(OnComplete)
    "session_rollback" => Some(SessionRollback)
    _ => None
  }
}

///|
/// Get event name as string
pub fn ShellHookEvent::event_name(self : ShellHookEvent) -> String {
  match self {
    BeforeToolUse => "before_tool_use"
    AfterToolUse => "after_tool_use"
    OnToolError => "on_tool_error"
    OnStart => "on_start"
    OnIteration => "on_iteration"
    OnComplete => "on_complete"
    SessionRollback => "session_rollback"
  }
}

///|
const DEFAULT_HOOK_TIMEOUT : Int = 10
