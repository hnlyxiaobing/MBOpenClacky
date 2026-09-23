///|
/// Journey assertion evaluation: dispatches the shared AssertionKind
/// vocabulary against the journey state (last HTTP response, WS journal,
/// child output, mock upstream requests, sandbox filesystem).
///
/// Evaluation semantics mirror the L4 adapters: file kinds delegate to
/// @eval.evaluate_file_assertion after journey placeholder expansion;
/// json_path comparisons use stringified JSON (string values carry quotes,
/// so expected values are written like "\"ok\"" in scenarios).

///|
fn journey_assert(
  description : String,
  passed : Bool,
  detail : String,
) -> @eval.EvalAssertionResult {
  { description, passed, detail, }
}

///|
/// Extract a value from JSON by a simple dot-separated path
/// (object keys only, matching the web adapter's semantics).
fn journey_json_path_value(json : Json, path : String) -> String? {
  match journey_json_walk(json, path) {
    Some(v) => Some(v.stringify())
    None => None
  }
}

///|
/// Evaluate one assertion against the journey state.
pub fn evaluate_journey_assertion(
  state : JourneyState,
  kind : @eval.AssertionKind,
) -> @eval.EvalAssertionResult {
  let ctx = state.ctx
  match kind {
    // ── File kinds: expand placeholders, delegate to the shared helper ──
    FileExists(path~) =>
      @eval.evaluate_file_assertion(
        @eval.FileExists(path=expand_journey_placeholders(path, ctx)),
        "",
      )
    FileMissing(path~) =>
      @eval.evaluate_file_assertion(
        @eval.FileMissing(path=expand_journey_placeholders(path, ctx)),
        "",
      )
    FileContains(path~, text~) =>
      @eval.evaluate_file_assertion(
        @eval.FileContains(
          path=expand_journey_placeholders(path, ctx),
          text=expand_journey_placeholders(text, ctx),
        ),
        "",
      )
    FileNotContains(path~, text~) =>
      @eval.evaluate_file_assertion(
        @eval.FileNotContains(
          path=expand_journey_placeholders(path, ctx),
          text=expand_journey_placeholders(text, ctx),
        ),
        "",
      )
    // ── HTTP response kinds (web steps) ──
    HttpStatusEq(status~) => {
      let passed = state.last_http_status == status
      journey_assert(
        "status is \{status}",
        passed,
        if passed {
          ""
        } else {
          "status: \{state.last_http_status}"
        },
      )
    }
    HttpStatusIn(statuses~) => {
      let passed = statuses.contains(state.last_http_status)
      let status_list = statuses.map(fn(s) { s.to_string() }).join(", ")
      journey_assert(
        "status in [\{status_list}]",
        passed,
        if passed {
          ""
        } else {
          "status: \{state.last_http_status}"
        },
      )
    }
    BodyContains(text~) => {
      let needle = expand_journey_placeholders(text, ctx)
      let passed = state.last_http_body.contains(needle)
      journey_assert(
        "body contains '\{needle}'",
        passed,
        if passed {
          ""
        } else {
          "body (\{state.last_http_body.length()} chars) lacks it"
        },
      )
    }
    BodyNotContains(text~) => {
      let needle = expand_journey_placeholders(text, ctx)
      let passed = !state.last_http_body.contains(needle)
      journey_assert(
        "body lacks '\{needle}'",
        passed,
        if passed {
          ""
        } else {
          "body unexpectedly contains it"
        },
      )
    }
    JsonPathEq(path~, value~) => {
      let j = @json.parse(state.last_http_body) catch {
        _ => Json::object(Map([]))
      }
      let actual = journey_json_path_value(j, path)
      let expected = expand_journey_placeholders(value, ctx)
      let passed = actual == Some(expected)
      journey_assert(
        "json path '\{path}' equals '\{expected}'",
        passed,
        if passed {
          ""
        } else {
          "actual: \{actual.unwrap_or("(missing)")}"
        },
      )
    }
    HeaderContains(name~, text~) => {
      let mut header_value = ""
      for pair in state.last_http_headers {
        if pair.0.to_lower() == name.to_lower() {
          header_value = pair.1
        }
      }
      let passed = header_value.to_lower().contains(text.to_lower())
      journey_assert(
        "header '\{name}' contains '\{text}'",
        passed,
        if passed {
          ""
        } else {
          "header value: '\{header_value}'"
        },
      )
    }
    SseValid => {
      let mut passed = true
      let mut detail = ""
      let lines = state.last_http_body
        .split("\n")
        .map(fn(s) { s.to_owned() })
        .to_array()
      let mut data_lines = 0
      for line in lines {
        if line.has_prefix("data:") {
          data_lines = data_lines + 1
          let payload = line[5:].to_owned().trim()
          if payload.length() > 0 && payload != "[DONE]" {
            let parsed : Json? = Some(@json.parse(payload)) catch { _ => None }
            match parsed {
              Some(_) => ()
              None => {
                passed = false
                detail = "invalid JSON in data: line"
              }
            }
          }
        }
      }
      if data_lines == 0 {
        passed = false
        detail = "no data: lines found"
      }
      journey_assert("body is valid SSE", passed, detail)
    }
    BodyLengthGt(min~) => {
      let passed = state.last_http_body.length() > min
      journey_assert(
        "body length > \{min}",
        passed,
        if passed {
          ""
        } else {
          "body length: \{state.last_http_body.length()}"
        },
      )
    }
    // ── TUI screen kinds (tui journeys) ──
    TextContains(text~, region~) =>
      evaluate_tui_screen_assertion(state, "contains", text, region)
    TextNotContains(text~) =>
      evaluate_tui_screen_assertion(state, "not_contains", text, "")
    ScreenEmpty => evaluate_tui_screen_assertion(state, "screen_empty", "", "")
    RowContains(row~, text~) =>
      if state.tui is Some(_) {
        evaluate_tui_row_assertion(state, row, text)
      } else {
        journey_assert(
          "row \{row} contains '\{text}'",
          false,
          "no TUI simulator",
        )
      }
    StatusContains(text~) =>
      evaluate_tui_screen_assertion(state, "status_contains", text, "")
    InputContains(text~) =>
      evaluate_tui_screen_assertion(state, "input_contains", text, "")
    OutputContains(text~) =>
      evaluate_tui_screen_assertion(state, "output_contains", text, "")
    DialogContains(text~) =>
      evaluate_tui_screen_assertion(state, "dialog_contains", text, "")
    // ── Child process kinds (cli/persistence journeys) ──
    ExitCode(code~) => {
      let passed = state.last_exit_code == Some(code)
      let code_note = match state.last_exit_code {
        Some(c) => c.to_string()
        None => "(no exited child)"
      }
      journey_assert(
        "exit code == \{code}",
        passed,
        if passed {
          ""
        } else {
          "exit code: \{code_note}"
        },
      )
    }
    StdoutContains(text~) => {
      let passed = state.last_stdout.contains(text)
      journey_assert(
        "stdout contains '\{text}'",
        passed,
        if passed {
          ""
        } else {
          "stdout (\{state.last_stdout.length()} chars) lacks it"
        },
      )
    }
    StderrContains(text~) => {
      let passed = state.last_stderr.contains(text)
      journey_assert(
        "stderr contains '\{text}'",
        passed,
        if passed {
          ""
        } else {
          "stderr (\{state.last_stderr.length()} chars) lacks it"
        },
      )
    }
    StdoutJsonPathEq(path~, value~) => {
      let lines = state.last_stdout
        .trim()
        .split("\n")
        .map(fn(s) { s.to_owned() })
        .to_array()
      let line = if lines.length() > 0 { lines[lines.length() - 1] } else { "" }
      let j = @json.parse(line) catch { _ => Json::object(Map([])) }
      let actual = journey_json_path_value(j, path)
      let passed = actual == Some(value)
      journey_assert(
        "stdout json '\{path}' equals '\{value}'",
        passed,
        if passed {
          ""
        } else {
          "actual: \{actual.unwrap_or("(missing)")}"
        },
      )
    }
    // ── WebSocket kinds (web journeys) ──
    WsFrameContains(text~) => {
      let needle = expand_journey_placeholders(text, ctx)
      let mut hit = false
      match state.journal {
        Some(j) =>
          for frame in j.frames_in {
            if frame.contains(needle) {
              hit = true
              break
            }
          }
        None => ()
      }
      journey_assert(
        "ws frame contains '\{needle}'",
        hit,
        if hit {
          ""
        } else {
          match state.journal {
            Some(j) => "\{j.frames_in.length()} frames received, none matched"
            None => "no ws connection"
          }
        },
      )
    }
    WsEventReceived(event~) => {
      let count = match state.journal {
        Some(j) => j.event_count(event)
        None => 0
      }
      journey_assert(
        "ws event '\{event}' received",
        count >= 1,
        if count >= 1 {
          ""
        } else {
          "event count: 0"
        },
      )
    }
    WsEventCountAtLeast(event~, min~) => {
      let count = match state.journal {
        Some(j) => j.event_count(event)
        None => 0
      }
      journey_assert(
        "ws event '\{event}' count >= \{min}",
        count >= min,
        if count >= min {
          ""
        } else {
          "event count: \{count}"
        },
      )
    }
    // ── Mock upstream kinds ──
    MockRequestCount(min~, max~) => {
      let n = state.mock.requests.length()
      let passed = n >= min && (max < 0 || n <= max)
      let max_label = if max < 0 { "∞" } else { max.to_string() }
      journey_assert(
        "mock request count in [\{min}, \{max_label}]",
        passed,
        if passed {
          ""
        } else {
          "request count: \{n}"
        },
      )
    }
    MockRequestContains(index~, text~) => {
      let n = state.mock.requests.length()
      if index < 0 || index >= n {
        journey_assert(
          "mock request[\{index}] contains '\{text}'",
          false,
          "request count: \{n}",
        )
      } else {
        let body = state.mock.requests[index].body
        let passed = body.contains(text)
        journey_assert(
          "mock request[\{index}] contains '\{text}'",
          passed,
          if passed {
            ""
          } else {
            "body (\{body.length()} chars) lacks it"
          },
        )
      }
    }
  }
}
