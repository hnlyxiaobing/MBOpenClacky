///| Evolution log — persisted record of skill reflection outcomes.

///|
/// Maximum number of entries retained (newest first). Older entries are
/// dropped on append so the log cannot grow without bound.
let max_log_entries : Int = 500

///|
/// One reflection outcome, persisted to `~/.mbopenclacky/skills/evolution_log.json`.
///
/// `action` is one of `"no_change"`, `"proposed"`, `"applied"`, `"error"` —
/// stored as a string because the log is a serialization boundary that must
/// keep reading old files after the engine's enums evolve.
///
/// `to_json`/`from_json` are hand-written (not derived) so that parsing tolerates
/// missing fields: a log written by an older build stays readable.
pub(all) struct EvolutionLogEntry {
  mut id : String
  mut created_at : Int
  mut skill_name : String
  mut source : String
  mut score : Int
  mut should_improve : Bool
  mut action : String
  mut suggestions : Array[String]
  mut backup_path : String?
  mut model : String?
  mut error : String?
} derive(Debug)

///|
pub extend EvolutionLogEntry with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Create a log entry for `skill_name`, filling outcome fields with defaults
/// (`action`/`suggestions`/`backup_path`/`model`/`error` are set by the caller).
pub fn EvolutionLogEntry::new(
  skill_name : String,
  source : String,
  score : Int,
  should_improve : Bool,
  action : String,
) -> EvolutionLogEntry {
  {
    id: "evo-" + @utils.now_ms().to_string(),
    created_at: @utils.now_seconds(),
    skill_name,
    source,
    score,
    should_improve,
    action,
    suggestions: [],
    backup_path: None,
    model: None,
    error: None,
  }
}

///|
pub fn EvolutionLogEntry::to_json(self : EvolutionLogEntry) -> Json {
  Json::object({
    "id": self.id.to_json(),
    "created_at": self.created_at.to_json(),
    "skill_name": self.skill_name.to_json(),
    "source": self.source.to_json(),
    "score": self.score.to_json(),
    "should_improve": self.should_improve.to_json(),
    "action": self.action.to_json(),
    "suggestions": Json::array(self.suggestions.map(fn(s) { s.to_json() })),
    "backup_path": optional_str_json(self.backup_path),
    "model": optional_str_json(self.model),
    "error": optional_str_json(self.error),
  })
}

///|
/// Tolerant decode: only a non-object payload is rejected; missing or
/// mistyped fields fall back to defaults.
pub fn EvolutionLogEntry::from_json(json : Json) -> EvolutionLogEntry? {
  let obj = match json {
    Object(o) => o
    _ => return None
  }
  let get_str : (String, String) -> String = fn(key : String, dflt : String) {
    match obj.get(key) {
      Some(String(s)) => s
      _ => dflt
    }
  }
  let get_opt_str : (String) -> String? = fn(key : String) {
    match obj.get(key) {
      Some(String(s)) => Some(s)
      _ => None
    }
  }
  let get_int : (String, Int) -> Int = fn(key : String, dflt : Int) {
    match obj.get(key) {
      Some(Number(n, ..)) => n.to_int()
      _ => dflt
    }
  }
  let get_bool : (String, Bool) -> Bool = fn(key : String, dflt : Bool) {
    match obj.get(key) {
      Some(True) => true
      Some(False) => false
      _ => dflt
    }
  }
  let suggestions : Array[String] = match obj.get("suggestions") {
    Some(Array(arr)) => {
      let out : Array[String] = []
      for item in arr {
        match item {
          String(s) => out.push(s)
          _ => ()
        }
      }
      out
    }
    _ => []
  }
  Some({
    id: get_str("id", ""),
    created_at: get_int("created_at", 0),
    skill_name: get_str("skill_name", ""),
    source: get_str("source", "user"),
    score: get_int("score", 0),
    should_improve: get_bool("should_improve", false),
    action: get_str("action", "no_change"),
    suggestions,
    backup_path: get_opt_str("backup_path"),
    model: get_opt_str("model"),
    error: get_opt_str("error"),
  })
}

///|
/// Path of the evolution log: `~/.mbopenclacky/skills/evolution_log.json`.
pub fn evolution_log_path() -> String {
  match @utils.skills_dir() {
    Some(d) =>
      @path.Path::join(@path.Path(d), @path.Path("evolution_log.json")).to_string()
    None => "evolution_log.json"
  }
}

///|
/// Load the evolution log from the default location, newest first.
pub fn load_evolution_log() -> Array[EvolutionLogEntry] {
  load_evolution_log_at(evolution_log_path())
}

///|
/// Load an evolution log from an explicit path, newest first.
///
/// Returns an empty array on any failure (missing file, malformed JSON)
/// **without modifying the file** — a damaged log is left in place for
/// inspection rather than being silently overwritten. Individual entries that
/// fail to decode are skipped.
pub fn load_evolution_log_at(path : String) -> Array[EvolutionLogEntry] {
  let content = @fs.read_file_to_string(path) catch { _ => return [] }
  let json = @json.parse(content) catch { _ => return [] }
  let arr = match json {
    Array(a) => a
    _ => return []
  }
  let out : Array[EvolutionLogEntry] = []
  for item in arr {
    match EvolutionLogEntry::from_json(item) {
      Some(e) => out.push(e)
      None => ()
    }
  }
  out
}

///|
/// Prepend an entry to the log at the default location.
pub fn append_evolution_log(entry : EvolutionLogEntry) -> Result[Unit, String] {
  append_evolution_log_at(evolution_log_path(), entry)
}

///|
/// Prepend an entry to the log at an explicit path (newest first), truncating
/// to `max_log_entries`.
///
/// `moonbitlang/x/fs` exposes no rename or append primitive, so this is a
/// read-modify-write and the write is **not atomic**; a crash mid-write can
/// leave a partial file (which `load_evolution_log_at` then reports as empty
/// without destroying it).
pub fn append_evolution_log_at(
  path : String,
  entry : EvolutionLogEntry,
) -> Result[Unit, String] {
  @utils.ensure_dir(dir_name(path))
  let entries : Array[EvolutionLogEntry] = [entry]
  for e in load_evolution_log_at(path) {
    if entries.length() >= max_log_entries {
      break
    }
    entries.push(e)
  }
  let json = Json::array(entries.map(fn(e) { e.to_json() }))
  @fs.write_string_to_file(path, json.stringify()) catch {
    e => return Err("Failed to write evolution log: " + @debug.to_string(e))
  }
  Ok(())
}

///|
fn dir_name(path : String) -> String {
  @path.Path::dirname(@path.Path(path)).to_string()
}

///|
fn optional_str_json(v : String?) -> Json {
  match v {
    Some(s) => s.to_json()
    None => Json::null()
  }
}
