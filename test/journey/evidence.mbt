///|
/// Evidence bundle writer: dumps the journey's machine-readable summary
/// and all captured artifacts into the run dir. The sandbox home (seeded
/// config), the workspace (file effects), and TUI screenshots live inside
/// the same run dir, so a failed journey's directory is a self-contained
/// repro bundle.

///|
/// Write the evidence bundle for one journey.
pub fn write_journey_evidence(
  state : JourneyState,
  scenario_id : String,
  passed : Bool,
  error : String,
) -> Unit {
  let dir = state.ctx.run_dir
  @utils.ensure_dir(dir)
  // ── journey.json: machine summary ─────────────────────────────────
  let assertions_json : Array[Json] = []
  for a in state.assertions {
    assertions_json.push(
      Json::object({
        "description": Json(a.description),
        "passed": Json::boolean(a.passed),
        "detail": Json(a.detail),
      }),
    )
  }
  let trace_json : Array[Json] = []
  for line in state.trace {
    trace_json.push(Json(line))
  }
  let summary = Json::object({
    "id": Json(scenario_id),
    "passed": Json::boolean(passed),
    "error": Json(error),
    "bin": Json(state.ctx.bin_path),
    "server_port": Json(state.ctx.server_port),
    "mock_port": Json(state.ctx.mock_port),
    "trace": Json::array(trace_json),
    "assertions": Json::array(assertions_json),
  })
  @fs.write_string_to_file("\{dir}/journey.json", summary.stringify()) catch {
    _ => ()
  }
  // ── mock_requests.jsonl: recorded upstream requests ────────────────
  let lines : Array[String] = []
  for i = 0; i < state.mock.requests.length(); i = i + 1 {
    let r = state.mock.requests[i]
    lines.push(
      Json::object({
        "seq": Json((i + 1)),
        "at_ms": Json(r.at_ms),
        "body": Json(r.body),
      }).stringify(),
    )
  }
  @fs.write_string_to_file(
    "\{dir}/mock_requests.jsonl",
    lines.join("\n") + "\n",
  ) catch {
    _ => ()
  }
  // ── rest_log.json: HTTP exchanges ──────────────────────────────────
  @fs.write_string_to_file(
    "\{dir}/rest_log.jsonl",
    state.rest_log.join("\n") + "\n",
  ) catch {
    _ => ()
  }
  // ── child outputs ──────────────────────────────────────────────────
  for i = 0; i < state.child_outputs.length(); i = i + 1 {
    let (label, code, stdout, stderr) = state.child_outputs[i]
    let prefix = "\{dir}/child_\{i}_\{label}"
    @fs.write_string_to_file("\{prefix}_exit.txt", "\{code}\n") catch {
      _ => ()
    }
    @fs.write_string_to_file("\{prefix}_stdout.txt", stdout) catch {
      _ => ()
    }
    @fs.write_string_to_file("\{prefix}_stderr.txt", stderr) catch {
      _ => ()
    }
  }
  // ── ws_frames.jsonl: journaled WebSocket traffic ────────────────────
  match state.journal {
    Some(j) => {
      let frame_lines : Array[String] = []
      for i = 0; i < j.frames_out.length(); i = i + 1 {
        frame_lines.push(
          Json::object({
            "dir": Json("out"),
            "text": Json(j.frames_out[i]),
          }).stringify(),
        )
      }
      for i = 0; i < j.frames_in.length(); i = i + 1 {
        frame_lines.push(
          Json::object({
            "dir": Json("in"),
            "event": Json(j.events[i]),
            "text": Json(j.frames_in[i]),
          }).stringify(),
        )
      }
      @fs.write_string_to_file(
        "\{dir}/ws_frames.jsonl",
        frame_lines.join("\n") + "\n",
      ) catch {
        _ => ()
      }
    }
    None => ()
  }
  // ── TUI screenshots + final screen ─────────────────────────────────
  match state.tui {
    Some(sim) => {
      @utils.ensure_dir("\{dir}/screenshots")
      for i = 0; i < sim.screenshots.length(); i = i + 1 {
        @fs.write_string_to_file(
          "\{dir}/screenshots/\{i + 1}.txt",
          sim.screenshots[i],
        ) catch {
          _ => ()
        }
      }
      @fs.write_string_to_file("\{dir}/final_screen.txt", sim.screen.content()) catch {
        _ => ()
      }
    }
    None => ()
  }
}
