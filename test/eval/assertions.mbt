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
  RowContains(row~ : Int, text~ : String)
  /// Status bar contains the given text.
  StatusContains(text~ : String)
  /// Input area contains the given text.
  InputContains(text~ : String)
  /// Output area contains the given text.
  OutputContains(text~ : String)
  /// Dialog region contains the given text.
  DialogContains(text~ : String)
  /// HTTP status code equals the given value.
  HttpStatusEq(status~ : Int)
  /// HTTP status code is one of the given values.
  HttpStatusIn(statuses~ : Array[Int])
  /// HTTP body contains the given text.
  BodyContains(text~ : String)
  /// HTTP body does NOT contain the given text.
  BodyNotContains(text~ : String)
  /// JSON body at the given path equals the given value.
  JsonPathEq(path~ : String, value~ : String)
  /// HTTP header with the given name contains the given text.
  HeaderContains(name~ : String, text~ : String)
  /// Body is valid SSE format (data: lines are valid JSON).
  SseValid
  /// Body length exceeds the given minimum.
  BodyLengthGt(min~ : Int)
  /// File exists at the given path.
  FileExists(path~ : String)
  /// File does NOT exist at the given path.
  FileMissing(path~ : String)
  /// File at the given path contains the given text.
  FileContains(path~ : String, text~ : String)
  /// File at the given path does NOT contain the given text.
  FileNotContains(path~ : String, text~ : String)
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
  let get_i = fn(k : String) -> Int {
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
      let statuses : Array[Int] = []
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
        "check": "contains".to_json(),
        "text": text.to_json(),
        "region": region.to_json(),
      })
    TextNotContains(text~) =>
      Json::object({ "check": "not_contains".to_json(), "text": text.to_json() })
    ScreenEmpty => Json::object({ "check": "screen_empty".to_json() })
    RowContains(row~, text~) =>
      Json::object({
        "check": "row_contains".to_json(),
        "row": row.to_json(),
        "text": text.to_json(),
      })
    StatusContains(text~) =>
      Json::object({
        "check": "status_contains".to_json(),
        "text": text.to_json(),
      })
    InputContains(text~) =>
      Json::object({
        "check": "input_contains".to_json(),
        "text": text.to_json(),
      })
    OutputContains(text~) =>
      Json::object({
        "check": "output_contains".to_json(),
        "text": text.to_json(),
      })
    DialogContains(text~) =>
      Json::object({
        "check": "dialog_contains".to_json(),
        "text": text.to_json(),
      })
    HttpStatusEq(status~) =>
      Json::object({ "type": "status_eq".to_json(), "status": status.to_json() })
    HttpStatusIn(statuses~) => {
      let arr : Array[Json] = []
      for s in statuses {
        arr.push(s.to_json())
      }
      Json::object({
        "type": "status_in".to_json(),
        "statuses": Json::array(arr),
      })
    }
    BodyContains(text~) =>
      Json::object({ "type": "body_contains".to_json(), "text": text.to_json() })
    BodyNotContains(text~) =>
      Json::object({
        "type": "body_not_contains".to_json(),
        "text": text.to_json(),
      })
    JsonPathEq(path~, value~) =>
      Json::object({
        "type": "json_path_eq".to_json(),
        "path": path.to_json(),
        "value": value.to_json(),
      })
    HeaderContains(name~, text~) =>
      Json::object({
        "type": "header_contains".to_json(),
        "name": name.to_json(),
        "text": text.to_json(),
      })
    SseValid => Json::object({ "type": "sse_valid".to_json() })
    BodyLengthGt(min~) =>
      Json::object({ "type": "body_length_gt".to_json(), "min": min.to_json() })
    FileExists(path~) =>
      Json::object({ "kind": "file_exists".to_json(), "path": path.to_json() })
    FileMissing(path~) =>
      Json::object({ "kind": "file_missing".to_json(), "path": path.to_json() })
    FileContains(path~, text~) =>
      Json::object({
        "kind": "file_contains".to_json(),
        "path": path.to_json(),
        "text": text.to_json(),
      })
    FileNotContains(path~, text~) =>
      Json::object({
        "kind": "file_not_contains".to_json(),
        "path": path.to_json(),
        "text": text.to_json(),
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
