///|
/// Unified Assertion Vocabulary: a shared enum that all eval subsystems can
/// serialize to/from, providing a common language for assertion specifications
/// across TUI, Web, Harness, and Benchmark domains.
///
/// Assertion *evaluation* remains domain-specific (TUI needs screen state,
/// Web needs HTTP response, Harness needs filesystem). This module provides:
/// 1. A unified serialization format for JSON scenario assertions
/// 2. Shared helpers for file-based assertions (used by harness)
/// 3. Conversion to/from the shared EvalAssertionResult type

///|
/// Domain-agnostic assertion specification. Each variant captures the
/// parameters needed to check one condition; the actual check is performed
/// by domain-specific code that has access to the relevant context.
pub(all) enum AssertionKind {
  /// Text (or region) contains the given substring.
  TextContains(text~ : String, region~ : String)
  /// Text does NOT contain the given substring.
  TextNotContains(text~ : String)
  /// Screen or content is empty.
  ScreenEmpty
  /// A specific row (by index) contains the given text.
  RowContains(row~ : Int32, text~ : String)
  /// Status bar contains the given text.
  StatusContains(text~ : String)
  /// Input area contains the given text.
  InputContains(text~ : String)
  /// Output area contains the given text.
  OutputContains(text~ : String)
  /// Dialog region contains the given text.
  DialogContains(text~ : String)
  /// HTTP status code equals the given value.
  HttpStatusEq(status~ : Int32)
  /// HTTP status code is one of the given values.
  HttpStatusIn(statuses~ : Array[Int32])
  /// HTTP body contains the given text.
  BodyContains(text~ : String)
  /// HTTP body does NOT contain the given text.
  BodyNotContains(text~ : String)
  /// JSON body at the given path equals the given value.
  JsonPathEq(path~ : String, value~ : String)
  /// JSON body at the given path does NOT equal the given value.
  /// The path must still resolve — a missing path fails the assertion
  /// (a missing value is not "different", it is absent).
  JsonPathNe(path~ : String, value~ : String)
  /// HTTP header with the given name contains the given text.
  HeaderContains(name~ : String, text~ : String)
  /// Body is valid SSE format (data: lines are valid JSON).
  SseValid
  /// Body length exceeds the given minimum.
  BodyLengthGt(min~ : Int32)
  /// File exists at the given path.
  FileExists(path~ : String)
  /// File does NOT exist at the given path.
  FileMissing(path~ : String)
  /// File at the given path contains the given text.
  FileContains(path~ : String, text~ : String)
  /// File at the given path does NOT contain the given text.
  FileNotContains(path~ : String, text~ : String)
  /// Last child process exit code equals the given value.
  ExitCode(code~ : Int32)
  /// Last child process stdout contains the given text.
  StdoutContains(text~ : String)
  /// Last child process stderr contains the given text.
  StderrContains(text~ : String)
  /// Last child process stdout does NOT contain the given text.
  StdoutNotContains(text~ : String)
  /// Last child process stderr does NOT contain the given text.
  StderrNotContains(text~ : String)
  /// Last stdout JSON line at the given path equals the given value.
  StdoutJsonPathEq(path~ : String, value~ : String)
  /// Any received WebSocket frame (raw text) contains the given substring.
  WsFrameContains(text~ : String)
  /// A WebSocket event with the given `type_name()` was received.
  WsEventReceived(event~ : String)
  /// Count of WebSocket events of the given type is at least `min`.
  WsEventCountAtLeast(event~ : String, min~ : Int32)
  /// Mock upstream request count within [min, max]; max = -1 means unbounded.
  MockRequestCount(min~ : Int32, max~ : Int32)
  /// Mock upstream request body (0-based index) contains the given text.
  MockRequestContains(index~ : Int32, text~ : String)
}

///|
/// Parse an AssertionKind from a JSON assertion spec object.
/// Supports both TUI-style (`"check": "contains"`) and Web-style
/// (`"type": "status_eq"`) field names for backward compatibility.
pub fn parse_assertion_kind(json : Json) -> AssertionKind? {
  let fields = match json {
    Object(f) => f
    _ => return None
  }
  let get_s = fn(k : String) -> String {
    match fields.get(k) {
      Some(String(text)) => text
      _ => ""
    }
  }
  let get_i = fn(k : String) -> Int32 {
    match fields.get(k) {
      Some(Number(n, ..)) => n.to_int()
      _ => 0
    }
  }
  let check_type = {
    let ct = get_s("check")
    if ct.length() > 0 {
      ct
    } else {
      get_s("type")
    }
  }
  let kind = match check_type {
    "contains" =>
      AssertionKind::TextContains(text=get_s("text"), region=get_s("region"))
    "not_contains" => AssertionKind::TextNotContains(text=get_s("text"))
    "screen_empty" => AssertionKind::ScreenEmpty
    "row_contains" =>
      AssertionKind::RowContains(row=get_i("row"), text=get_s("text"))
    "status_contains" => AssertionKind::StatusContains(text=get_s("text"))
    "input_contains" => AssertionKind::InputContains(text=get_s("text"))
    "output_contains" => AssertionKind::OutputContains(text=get_s("text"))
    "dialog_contains" => AssertionKind::DialogContains(text=get_s("text"))
    "status_eq" => AssertionKind::HttpStatusEq(status=get_i("status"))
    "status_in" => {
      let statuses : Array[Int32] = []
      match fields.get("statuses") {
        Some(Array(items)) =>
          for item in items {
            match item {
              Number(n, ..) => statuses.push(n.to_int())
              _ => ()
            }
          }
        _ => ()
      }
      AssertionKind::HttpStatusIn(statuses~)
    }
    "body_contains" => AssertionKind::BodyContains(text=get_s("text"))
    "body_not_contains" => AssertionKind::BodyNotContains(text=get_s("text"))
    "json_path_eq" =>
      AssertionKind::JsonPathEq(path=get_s("path"), value=get_s("value"))
    "json_path_ne" =>
      AssertionKind::JsonPathNe(path=get_s("path"), value=get_s("value"))
    "header_contains" =>
      AssertionKind::HeaderContains(name=get_s("name"), text=get_s("text"))
    "sse_valid" => AssertionKind::SseValid
    "body_length_gt" => AssertionKind::BodyLengthGt(min=get_i("min"))
    "file_exists" => AssertionKind::FileExists(path=get_s("path"))
    "file_missing" => AssertionKind::FileMissing(path=get_s("path"))
    "file_contains" =>
      AssertionKind::FileContains(path=get_s("path"), text=get_s("text"))
    "file_not_contains" =>
      AssertionKind::FileNotContains(path=get_s("path"), text=get_s("text"))
    "exit_code" => AssertionKind::ExitCode(code=get_i("code"))
    "stdout_contains" => AssertionKind::StdoutContains(text=get_s("text"))
    "stderr_contains" => AssertionKind::StderrContains(text=get_s("text"))
    "stdout_not_contains" =>
      AssertionKind::StdoutNotContains(text=get_s("text"))
    "stderr_not_contains" =>
      AssertionKind::StderrNotContains(text=get_s("text"))
    "stdout_json_path_eq" =>
      AssertionKind::StdoutJsonPathEq(path=get_s("path"), value=get_s("value"))
    "ws_frame_contains" => AssertionKind::WsFrameContains(text=get_s("text"))
    "ws_event_received" => AssertionKind::WsEventReceived(event=get_s("event"))
    "ws_event_count_at_least" =>
      AssertionKind::WsEventCountAtLeast(event=get_s("event"), min=get_i("min"))
    "mock_request_count" => {
      let max = match fields.get("max") {
        Some(Number(n, ..)) => n.to_int()
        _ => -1
      }
      AssertionKind::MockRequestCount(min=get_i("min"), max~)
    }
    "mock_request_contains" =>
      AssertionKind::MockRequestContains(
        index=get_i("index"),
        text=get_s("text"),
      )
    _ => return None
  }
  Some(kind)
}

///|
/// Serialize an AssertionKind to a JSON object for scenario files.
pub fn assertion_kind_to_json(kind : AssertionKind) -> Json {
  match kind {
    TextContains(text~, region~) =>
      Json::object({
        "check": Json("contains"),
        "text": Json(text),
        "region": Json(region),
      })
    TextNotContains(text~) =>
      Json::object({ "check": Json("not_contains"), "text": Json(text) })
    ScreenEmpty => Json::object({ "check": Json("screen_empty") })
    RowContains(row~, text~) =>
      Json::object({
        "check": Json("row_contains"),
        "row": Json(row),
        "text": Json(text),
      })
    StatusContains(text~) =>
      Json::object({ "check": Json("status_contains"), "text": Json(text) })
    InputContains(text~) =>
      Json::object({ "check": Json("input_contains"), "text": Json(text) })
    OutputContains(text~) =>
      Json::object({ "check": Json("output_contains"), "text": Json(text) })
    DialogContains(text~) =>
      Json::object({ "check": Json("dialog_contains"), "text": Json(text) })
    HttpStatusEq(status~) =>
      Json::object({ "type": Json("status_eq"), "status": Json(status) })
    HttpStatusIn(statuses~) => {
      let arr : Array[Json] = []
      for s in statuses {
        arr.push(Json(s))
      }
      Json::object({ "type": Json("status_in"), "statuses": Json::array(arr) })
    }
    BodyContains(text~) =>
      Json::object({ "type": Json("body_contains"), "text": Json(text) })
    BodyNotContains(text~) =>
      Json::object({ "type": Json("body_not_contains"), "text": Json(text) })
    JsonPathEq(path~, value~) =>
      Json::object({
        "type": Json("json_path_eq"),
        "path": Json(path),
        "value": Json(value),
      })
    JsonPathNe(path~, value~) =>
      Json::object({
        "type": Json("json_path_ne"),
        "path": Json(path),
        "value": Json(value),
      })
    HeaderContains(name~, text~) =>
      Json::object({
        "type": Json("header_contains"),
        "name": Json(name),
        "text": Json(text),
      })
    SseValid => Json::object({ "type": Json("sse_valid") })
    BodyLengthGt(min~) =>
      Json::object({ "type": Json("body_length_gt"), "min": Json(min) })
    FileExists(path~) =>
      Json::object({ "type": Json("file_exists"), "path": Json(path) })
    FileMissing(path~) =>
      Json::object({ "kind": Json("file_missing"), "path": Json(path) })
    FileContains(path~, text~) =>
      Json::object({
        "kind": Json("file_contains"),
        "path": Json(path),
        "text": Json(text),
      })
    FileNotContains(path~, text~) =>
      Json::object({
        "kind": Json("file_not_contains"),
        "path": Json(path),
        "text": Json(text),
      })
    ExitCode(code~) =>
      Json::object({ "type": Json("exit_code"), "code": Json(code) })
    StdoutContains(text~) =>
      Json::object({ "type": Json("stdout_contains"), "text": Json(text) })
    StderrContains(text~) =>
      Json::object({ "type": Json("stderr_contains"), "text": Json(text) })
    StdoutNotContains(text~) =>
      Json::object({ "type": Json("stdout_not_contains"), "text": Json(text) })
    StderrNotContains(text~) =>
      Json::object({ "type": Json("stderr_not_contains"), "text": Json(text) })
    StdoutJsonPathEq(path~, value~) =>
      Json::object({
        "type": Json("stdout_json_path_eq"),
        "path": Json(path),
        "value": Json(value),
      })
    WsFrameContains(text~) =>
      Json::object({ "type": Json("ws_frame_contains"), "text": Json(text) })
    WsEventReceived(event~) =>
      Json::object({ "type": Json("ws_event_received"), "event": Json(event) })
    WsEventCountAtLeast(event~, min~) =>
      Json::object({
        "type": Json("ws_event_count_at_least"),
        "event": Json(event),
        "min": Json(min),
      })
    MockRequestCount(min~, max~) =>
      Json::object({
        "type": Json("mock_request_count"),
        "min": Json(min),
        "max": Json(max),
      })
    MockRequestContains(index~, text~) =>
      Json::object({
        "type": Json("mock_request_contains"),
        "index": Json(index),
        "text": Json(text),
      })
  }
}

// ── File-based assertion helpers ─────────────────────────────────────────────
//
// These helpers evaluate file-based assertions (FileExists, FileMissing,
// FileContains, FileNotContains) against the filesystem. Used by the harness
// and any other subsystem that needs to check file state.

///|
/// Expand `{sandbox}` placeholders in a path or text.
pub fn expand_sandbox_placeholder(text : String, sandbox : String) -> String {
  text.split("{sandbox}").collect().join(sandbox)
}

///|
/// Evaluate a file-based assertion against the filesystem.
/// Returns an EvalAssertionResult suitable for inclusion in any report.
pub fn evaluate_file_assertion(
  kind : AssertionKind,
  sandbox : String,
) -> EvalAssertionResult {
  match kind {
    FileExists(path~) => {
      let resolved = expand_sandbox_placeholder(path, sandbox)
      let exists = @fs.path_exists(resolved)
      let r : EvalAssertionResult = {
        description: "file exists: \{path}",
        passed: exists,
        detail: if exists {
          ""
        } else {
          "missing"
        },
      }
      r
    }
    FileMissing(path~) => {
      let resolved = expand_sandbox_placeholder(path, sandbox)
      let exists = @fs.path_exists(resolved)
      let r : EvalAssertionResult = {
        description: "file absent: \{path}",
        passed: !exists,
        detail: if exists {
          "still present"
        } else {
          ""
        },
      }
      r
    }
    FileContains(path~, text~) => {
      let resolved = expand_sandbox_placeholder(path, sandbox)
      let exists = @fs.path_exists(resolved)
      let content = @fs.read_file_to_string(resolved) catch { _ => "" }
      let hit = content.contains(expand_sandbox_placeholder(text, sandbox))
      let r : EvalAssertionResult = {
        description: "file_contains: \{path}",
        passed: exists && hit,
        detail: if !exists {
          "missing file"
        } else if hit {
          ""
        } else {
          "content mismatch"
        },
      }
      r
    }
    FileNotContains(path~, text~) => {
      let resolved = expand_sandbox_placeholder(path, sandbox)
      let exists = @fs.path_exists(resolved)
      let content = @fs.read_file_to_string(resolved) catch { _ => "" }
      let hit = content.contains(expand_sandbox_placeholder(text, sandbox))
      let r : EvalAssertionResult = {
        description: "file_not_contains: \{path}",
        passed: exists && !hit,
        detail: if !exists {
          "missing file"
        } else if !hit {
          ""
        } else {
          "content mismatch"
        },
      }
      r
    }
    _ => {
      let r : EvalAssertionResult = {
        description: "not a file-based assertion",
        passed: false,
        detail: "evaluate_file_assertion only handles File* kinds",
      }
      r
    }
  }
}
