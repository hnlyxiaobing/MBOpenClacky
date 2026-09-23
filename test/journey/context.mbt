///|
/// Journey runtime context: sandbox paths, ports, and captured values.
///
/// Every journey runs in an isolated sandbox under
/// `<repo>/_build/journey/<stamp>/<scenario_id>/`:
///   home/      → USERPROFILE/HOME for child processes (contains .mbopenclacky)
///   workspace/ → CLACKY_WORKSPACE_DIR + child cwd (seed files, tool effects)
/// The evidence bundle for the journey is written to the scenario directory
/// itself (journey.json, ws_frames.jsonl, ...).

///|
/// Normalize path separators to forward slashes (evidence/ledger text must
/// stay identical across Windows and Linux).
pub fn journey_normalize_path(p : String) -> String {
  p.replace_all(old="\\", new="/")
}

///|
/// Filesystem-safe run stamp: ISO 8601 with `:` replaced by `-`.
pub fn journey_stamp_now() -> String {
  let iso = @agent.ms_to_iso8601(@agent.current_time_ms())
  let mut out = ""
  for c in iso {
    if c == ':' {
      out = out + "-"
    } else {
      out = out + c.to_string()
    }
  }
  out
}

///|
/// Per-journey runtime context.
pub(all) struct JourneyContext {
  /// Absolute repo path (forward slashes).
  repo_abs : String
  /// Path to the release binary under test.
  bin_path : String
  scenario_id : String
  /// Run stamp shared by all journeys in one batch.
  stamp : String
  /// Evidence bundle root: `<repo>/_build/journey/<stamp>/<scenario_id>`
  run_dir : String
  /// Sandbox home for child processes (`<run_dir>/home`).
  home : String
  /// Sandbox workspace (`<run_dir>/workspace`).
  workspace : String
  /// Web server port chosen for this journey (probe-adjusted).
  mut server_port : Int
  /// Mock upstream port (set when the mock server binds).
  mut mock_port : Int
  /// Values captured from HTTP responses (`{capture:<name>}` placeholders).
  mut captures : Map[String, String]
}

///|
/// Create the sandbox directories and return the journey context.
pub fn create_journey_context(
  repo_abs : String,
  bin_path : String,
  scenario_id : String,
  stamp : String,
  server_port : Int,
) -> JourneyContext {
  let repo_abs = journey_normalize_path(repo_abs)
  let run_dir = "\{repo_abs}/_build/journey/\{stamp}/\{scenario_id}"
  let home = "\{run_dir}/home"
  let workspace = "\{run_dir}/workspace"
  @utils.ensure_dir("\{home}/.mbopenclacky")
  @utils.ensure_dir(workspace)
  {
    repo_abs,
    bin_path,
    scenario_id,
    stamp,
    run_dir,
    home,
    workspace,
    server_port,
    mock_port: 0,
    captures: Map([]),
  }
}

///|
/// Seed workspace files from the scenario's `seed` list.
pub fn seed_workspace_files(
  ctx : JourneyContext,
  seed : Array[(String, String)],
) -> Unit {
  for pair in seed {
    let (rel, content) = pair
    let path = "\{ctx.workspace}/\{rel}"
    let dir = @path.Path::dirname(@path.Path(path)).to_string()
    @utils.ensure_dir(journey_normalize_path(dir))
    @fs.write_string_to_file(path, content) catch {
      _ => ()
    }
  }
}

///|
/// Write the seeded `~/.mbopenclacky/config.toml` pointing the default
/// model at the mock upstream. One model = the default model; children
/// never touch the real user config.
pub fn write_seed_config(
  ctx : JourneyContext,
  mock_port : Int,
  permission_mode : String,
) -> Unit {
  ctx.mock_port = mock_port
  let mode = if permission_mode.is_empty() {
    "confirm_safes"
  } else {
    permission_mode
  }
  let content = "[[models]]\n" +
    "id = \"mock\"\n" +
    "api_key = \"mock-key\"\n" +
    "base_url = \"http://127.0.0.1:\{mock_port}\"\n" +
    "model = \"mock-model\"\n" +
    "type = \"default\"\n" +
    "\n" +
    "[settings]\n" +
    "permission_mode = \"\{mode}\"\n"
  @fs.write_string_to_file("\{ctx.home}/.mbopenclacky/config.toml", content) catch {
    _ => ()
  }
}

///|
/// Expand journey placeholders in a path or text:
///   {port} {mock_port} {workspace} {home} {run_dir} {capture:<name>}
pub fn expand_journey_placeholders(
  text : String,
  ctx : JourneyContext,
) -> String {
  let mut out = text
  out = out.replace_all(old="{port}", new="\{ctx.server_port}")
  out = out.replace_all(old="{mock_port}", new="\{ctx.mock_port}")
  out = out.replace_all(old="{workspace}", new=ctx.workspace)
  out = out.replace_all(old="{home}", new=ctx.home)
  out = out.replace_all(old="{run_dir}", new=ctx.run_dir)
  // {capture:<name>} — captured values from HTTP responses
  for entry in ctx.captures {
    out = out.replace_all(old="{capture:\{entry.0}}", new=entry.1)
  }
  out
}

///|
/// Walk a dot-separated path through JSON object keys
/// (e.g. "session.id"). Object keys only, no arrays.
pub fn journey_json_walk(json : Json, path : String) -> Json? {
  let parts = path.split(".").map(fn(s) { s.to_owned() }).to_array()
  let mut current = json
  for part in parts {
    match current {
      Object(obj) =>
        match obj.get(part) {
          Some(v) => current = v
          None => return None
        }
      _ => return None
    }
  }
  Some(current)
}

///|
/// Capture a JSON field (dot path supported, e.g. "session.id") from an
/// HTTP response body into the context (used by `capture` on http steps).
/// String values are stored raw (unquoted).
pub fn capture_json_field(
  ctx : JourneyContext,
  body : String,
  field : String,
) -> Bool {
  if field.is_empty() {
    return true
  }
  let json = @json.parse(body) catch { _ => return false }
  match journey_json_walk(json, field) {
    Some(String(s)) => {
      ctx.captures[field] = s
      true
    }
    _ => false
  }
}
