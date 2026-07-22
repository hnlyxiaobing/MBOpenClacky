///| User profile REST API handlers.
/// Persists profile data to ~/.clacky/profile.json.
/// Supports user/soul content editing via PUT {kind, content}.

///|
fn profile_json_path() -> String? {
  match @utils.config_dir() {
    Some(d) =>
      Some(
        @path.Path::join(@path.Path(d), @path.Path("profile.json")).to_string(),
      )
    None => None
  }
}

///|
fn load_profile() -> Json {
  match profile_json_path() {
    Some(path) => {
      let content = @fs.read_file_to_string(path) catch {
        _ => return default_profile_json()
      }
      if content.is_empty() {
        return default_profile_json()
      }
      @json.parse(content) catch {
        _ => default_profile_json()
      }
    }
    None => default_profile_json()
  }
}

///|
fn default_profile_json() -> Json {
  Json::object({
    "name": "".to_json(),
    "email": "".to_json(),
    "preferences": Json::object({}),
    "theme": "dark".to_json(),
  })
}

///|
fn save_profile(j : Json) -> Result[Unit, String] {
  match profile_json_path() {
    Some(path) => {
      match @utils.config_dir() {
        Some(dir) => @utils.ensure_dir(dir)
        None => ()
      }
      @fs.write_string_to_file(path, j.stringify()) catch {
        e => return Err(@debug.to_string(e))
      }
      Ok(())
    }
    None => Err("Unable to determine config directory")
  }
}

///|
fn json_get_str(j : Json, key : String) -> String {
  match j {
    Object(obj) =>
      match obj.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
fn json_get_obj(j : Json, key : String) -> Json {
  match j {
    Object(obj) =>
      match obj.get(key) {
        Some(o) => o
        _ => Json::object({})
      }
    _ => Json::object({})
  }
}

// ── User/Soul content helpers ────────────────────────────

///|
/// Path for user content file (user-editable override).
fn profile_user_md_path() -> String? {
  match @utils.config_dir() {
    Some(d) =>
      Some(@path.Path::join(@path.Path(d), @path.Path("USER.md")).to_string())
    None => None
  }
}

///|
/// Path for soul content file (user-editable override).
fn profile_soul_md_path() -> String? {
  match @utils.config_dir() {
    Some(d) =>
      Some(@path.Path::join(@path.Path(d), @path.Path("SOUL.md")).to_string())
    None => None
  }
}

///|
/// Read a profile markdown file, falling back to builtin default.
fn read_profile_md(
  user_path : String?,
  builtin_path : String,
) -> (String, Bool) {
  // Try user override first.
  match user_path {
    Some(p) =>
      if @fs.path_exists(p) {
        let content = @fs.read_file_to_string(p) catch { _ => "" }
        if !content.is_empty() {
          return (content, false)
        }
      }
    None => ()
  }
  // Fall back to builtin.
  let content = @fs.read_file_to_string(builtin_path) catch { _ => "" }
  (content, true)
}

///|
/// Save profile markdown content to user path.
fn save_profile_md(path : String?, content : String) -> Result[Unit, String] {
  match path {
    Some(p) => {
      match @utils.config_dir() {
        Some(dir) => @utils.ensure_dir(dir)
        None => ()
      }
      @fs.write_string_to_file(p, content) catch {
        e => return Err(@debug.to_string(e))
      }
      Ok(())
    }
    None => Err("Unable to determine config directory")
  }
}

// ── Handlers ──────────────────────────────────────────────

///|
/// GET /api/profile
/// Returns profile data including user/soul content sections.
fn handle_profile_get(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let profile = load_profile()
  // Read user/soul content.
  let (user_content, user_is_default) = read_profile_md(
    profile_user_md_path(),
    "assets/agents/USER.md",
  )
  let (soul_content, soul_is_default) = read_profile_md(
    profile_soul_md_path(),
    "assets/agents/SOUL.md",
  )
  let user_path = match profile_user_md_path() {
    Some(p) => p
    None => ""
  }
  let soul_path = match profile_soul_md_path() {
    Some(p) => p
    None => ""
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "ok": true.to_json(),
      "name": json_get_str(profile, "name").to_json(),
      "email": json_get_str(profile, "email").to_json(),
      "preferences": json_get_obj(profile, "preferences"),
      "theme": json_get_str(profile, "theme").to_json(),
      "user": Json::object({
        "path": user_path.to_json(),
        "content": user_content.to_json(),
        "is_default": user_is_default.to_json(),
      }),
      "soul": Json::object({
        "path": soul_path.to_json(),
        "content": soul_content.to_json(),
        "is_default": soul_is_default.to_json(),
      }),
    }),
  )
}

///|
/// PUT /api/profile
/// Supports two modes:
///   1. Legacy: {name?, email?, preferences?, theme?}
///   2. Kind-based: {kind: "user"|"soul", content: "..."}
fn handle_profile_put(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  // Check for kind-based update (user/soul content).
  let kind = json_get_str(j, "kind")
  if kind == "user" || kind == "soul" {
    let content = json_get_str(j, "content")
    let path = if kind == "user" {
      profile_user_md_path()
    } else {
      profile_soul_md_path()
    }
    match save_profile_md(path, content) {
      Ok(_) =>
        return @core.HttpResponse::ok().json_value(
          Json::object({ "ok": true.to_json(), "kind": kind.to_json() }),
        )
      Err(msg) =>
        return @core.HttpResponse::internal_server_error().json_value(
          Json::object({
            "error": "Failed to save profile content".to_json(),
            "detail": msg.to_json(),
          }),
        )
    }
  }
  // Legacy profile update.
  let existing = load_profile()
  let name = if json_has_key(j, "name") {
    json_get_str(j, "name")
  } else {
    json_get_str(existing, "name")
  }
  let email = if json_has_key(j, "email") {
    json_get_str(j, "email")
  } else {
    json_get_str(existing, "email")
  }
  let preferences = if json_has_key(j, "preferences") {
    json_get_obj(j, "preferences")
  } else {
    json_get_obj(existing, "preferences")
  }
  let theme = if json_has_key(j, "theme") {
    json_get_str(j, "theme")
  } else {
    json_get_str(existing, "theme")
  }
  let merged = Json::object({
    "name": name.to_json(),
    "email": email.to_json(),
    "preferences": preferences,
    "theme": theme.to_json(),
  })
  match save_profile(merged) {
    Ok(_) =>
      @core.HttpResponse::ok().json_value(
        Json::object({ "ok": true.to_json(), "profile": merged }),
      )
    Err(msg) =>
      @core.HttpResponse::internal_server_error().json_value(
        Json::object({
          "error": "Failed to save profile".to_json(),
          "detail": msg.to_json(),
        }),
      )
  }
}

///|
fn json_has_key(j : Json, key : String) -> Bool {
  match j {
    Object(obj) => obj.contains(key)
    _ => false
  }
}
