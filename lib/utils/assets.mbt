///|
/// Bundled resource root (`assets/**`) resolution.
///
/// Resources ship with the installation, so lookups must not depend on the
/// process CWD — `--path <dir>` deliberately chdirs away from the launch
/// directory before the agent loop starts, and openclacky anchors the same
/// resources with `File.expand_path("../prompts/base.md", __FILE__)`.
///
/// Resolution order:
///   1. `MBOPENCLACKY_ASSETS_DIR` — explicit override, points at `assets/`
///      itself (packaging and tests).
///   2. The running executable's directory, walking upwards.
///   3. The launch directory, walking upwards.
///   4. CWD-relative `assets` (legacy fallback).
///
/// The first successful step is cached for the rest of the process; call
/// `prewarm_assets_root()` before any `change_dir` so step 3 sees the launch
/// directory rather than the agent's working directory.

///|
/// Explicit override for the bundled `assets/` directory.
const ASSETS_DIR_ENV : String = "MBOPENCLACKY_ASSETS_DIR"

///|
/// Marker file proving a directory is the project root that carries `assets/`.
const ASSETS_MARKER : String = "assets/prompts/base.md"

///|
let assets_root_cache : Ref[String?] = Ref(None)

///|
/// Absolute path of the bundled `assets/` directory.
pub fn assets_root() -> String {
  match assets_root_cache.val {
    Some(root) => root
    None => {
      let root = resolve_assets_root()
      assets_root_cache.val = Some(root)
      root
    }
  }
}

///|
/// Join a path relative to the bundled `assets/` directory.
pub fn assets_path(relative : String) -> String {
  @path.Path::join(@path.Path(assets_root()), @path.Path(relative)).to_string()
}

///|
/// Resolve `assets_root()` now, while the launch directory is still the CWD.
pub fn prewarm_assets_root() -> Unit {
  ignore(assets_root())
}

///|
/// Drop the cached root so tests can exercise resolution again.
pub fn reset_assets_root_for_test() -> Unit {
  assets_root_cache.val = None
}

///|
fn resolve_assets_root() -> String {
  match @env.get_env_var(ASSETS_DIR_ENV) {
    Some(value) => {
      let trimmed = value.trim().to_owned()
      if !trimmed.is_empty() {
        return trimmed
      }
    }
    None => ()
  }
  let starts : Array[String?] = [executable_dir(), @env.current_dir()]
  for start in starts {
    match start {
      Some(dir) =>
        match find_project_root(dir) {
          Some(root) =>
            return @path.Path::join(@path.Path(root), @path.Path("assets")).to_string()
          None => ()
        }
      None => ()
    }
  }
  "assets"
}

///|
/// Directory holding the running executable, resolved against the launch CWD
/// when argv[0] is relative. `None` when argv is unavailable.
fn executable_dir() -> String? {
  let args = @env.args()
  if args.length() == 0 {
    return None
  }
  let arg0 = args[0]
  if arg0.is_empty() {
    return None
  }
  let dir = @path.Path(@path.Path(arg0).resolve().to_string())
    .dirname()
    .to_string()
  if dir.is_empty() {
    None
  } else {
    Some(dir)
  }
}

///|
/// Walk `start` and its ancestors looking for the directory that carries the
/// bundled `assets/`.
fn find_project_root(start : String) -> String? {
  if start.is_empty() {
    return None
  }
  walk_up(@path.Path(start).resolve().to_string())
}

///|
fn walk_up(dir : String) -> String? {
  if carries_assets(dir) {
    return Some(dir)
  }
  let parent = @path.Path(dir).dirname().to_string()
  if parent.is_empty() || parent == dir {
    return None
  }
  walk_up(parent)
}

///|
fn carries_assets(dir : String) -> Bool {
  let marker = @path.Path::join(@path.Path(dir), @path.Path(ASSETS_MARKER)).to_string()
  @fs.path_exists(marker)
}
