///| User profile REST API handlers.
/// Persists profile data to ~/.clacky/profile.json.

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
        e => return Err(e.to_string())
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

///|
/// GET /api/profile
fn handle_profile_get(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let profile = load_profile()
  @core.HttpResponse::ok().json_value(profile)
}

///|
/// PUT /api/profile
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
