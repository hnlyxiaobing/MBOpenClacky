///|
/// CLI journey steps: spawn `bin -m ...` children (env-isolated, cwd =
/// sandbox workspace), wait for exit, and crash-simulation kills.
/// Session persistence across `--continue` works because children share
/// the sandbox home (~/.mbopenclacky/sessions/).

///|
/// Build the CLI child argument vector.
fn cli_child_args(
  ctx : JourneyContext,
  message : String,
  json_output : Bool,
  mode : String,
  cont : Bool,
  extra_args : Array[String],
) -> Array[String] {
  let args : Array[String] = []
  if cont {
    args.push("--continue")
  }
  args.push("--message")
  args.push(message)
  if json_output {
    args.push("--json")
  }
  if mode.length() > 0 {
    args.push("--mode")
    args.push(mode)
  }
  args.push("--path")
  args.push(ctx.workspace)
  for a in extra_args {
    args.push(a)
  }
  args
}

///|
async fn spawn_cli_step(
  group : @async.TaskGroup[Unit],
  state : JourneyState,
  message : String,
  json_output : Bool,
  mode : String,
  cont : Bool,
  extra_args : Array[String],
  phase_name : String,
) -> Unit {
  // A previous child still running (e.g. spawn → spawn): kill it first.
  match state.child {
    Some(prev) => {
      prev.kill()
      state.child = None
    }
    None => ()
  }
  let ctx = state.ctx
  let args = cli_child_args(ctx, message, json_output, mode, cont, extra_args)
  let cont_note = if cont { " --continue" } else { "" }
  state.trace.push(
    "[\{phase_name}] spawn cli: -m (\{message.length()} chars)\{cont_note}",
  )
  let handle = spawn_isolated_child(
    group,
    ctx,
    "cli",
    ctx.bin_path,
    args,
    hard_kill=true,
  )
  state.child = Some(handle)
}

///|
async fn wait_child_step(
  state : JourneyState,
  timeout_ms : Int,
  capture : String,
  phase_name : String,
) -> Unit {
  match state.child {
    Some(child) =>
      match child.wait_collect(timeout_ms) {
        Ok((code, stdout, stderr)) => {
          state.trace.push(
            "[\{phase_name}] child \{child.label} exited: \{code} (stdout \{stdout.length()} chars)",
          )
          record_child_output(state, child.label, code, stdout, stderr)
          if capture.length() > 0 {
            if !capture_stdout_json_field(state, capture) {
              state.error = "[\{phase_name}] wait_child: capture field '\{capture}' not found in stdout JSON"
            }
          }
        }
        Err(msg) => state.error = "[\{phase_name}] \{msg}"
      }
    None => state.error = "[\{phase_name}] wait_child: no child process running"
  }
}

///|
/// Extract a top-level field from the child's last stdout JSON line into
/// the context captures (session_id etc.).
fn capture_stdout_json_field(state : JourneyState, field : String) -> Bool {
  let lines = state.last_stdout
    .trim()
    .split("\n")
    .map(fn(s) { s.to_owned() })
    .to_array()
  if lines.length() == 0 {
    return false
  }
  let last = lines[lines.length() - 1]
  let json = @json.parse(last) catch { _ => return false }
  match journey_json_walk(json, field) {
    Some(String(s)) => {
      state.ctx.captures[field] = s
      true
    }
    _ => false
  }
}

///|
/// Spawn the journey binary with arbitrary (placeholder-expanded) args.
async fn spawn_bin_step(
  group : @async.TaskGroup[Unit],
  state : JourneyState,
  args : Array[String],
  phase_name : String,
) -> Unit {
  match state.child {
    Some(prev) => {
      prev.kill()
      state.child = None
    }
    None => ()
  }
  let expanded : Array[String] = []
  for a in args {
    expanded.push(expand_journey_placeholders(a, state.ctx))
  }
  state.trace.push("[\{phase_name}] spawn bin: \{expanded.join(" ")}")
  let handle = spawn_isolated_child(
    group,
    state.ctx,
    "bin",
    state.ctx.bin_path,
    expanded,
    hard_kill=true,
  )
  state.child = Some(handle)
}

///|
async fn kill_child_step(state : JourneyState, phase_name : String) -> Unit {
  match state.child {
    Some(child) => {
      let (code, stdout, stderr) = child.kill_and_collect()
      state.trace.push(
        "[\{phase_name}] child \{child.label} killed: exit \{code}",
      )
      record_child_output(state, child.label, code, stdout, stderr)
      state.child = None
    }
    None => state.error = "[\{phase_name}] kill_child: no child process running"
  }
}

///|
/// Crash simulation: block until the mock upstream has seen N requests,
/// then hard-kill the child (bounded poll; never hangs).
async fn kill_child_mid_run_step(
  state : JourneyState,
  after_mock_request : Int,
  phase_name : String,
) -> Unit {
  match state.child {
    Some(child) => {
      let deadline = @agent.current_time_ms() + 15_000L
      for ;; {
        if state.mock.requests.length() >= after_mock_request {
          break
        }
        if @agent.current_time_ms() >= deadline {
          state.error = "[\{phase_name}] kill_child_mid_run: mock saw only \{state.mock.requests.length()} requests (timeout)"
          return
        }
        @async.sleep(50)
      }
      let (code, stdout, stderr) = child.kill_and_collect()
      state.trace.push(
        "[\{phase_name}] child \{child.label} hard-killed mid-run after \{after_mock_request} mock request(s): exit \{code}",
      )
      record_child_output(state, child.label, code, stdout, stderr)
      state.child = None
    }
    None =>
      state.error = "[\{phase_name}] kill_child_mid_run: no child process running"
  }
}
