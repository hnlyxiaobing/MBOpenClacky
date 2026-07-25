///| Skill publish pipeline (fix-17): POST /api/my-skills/:name/publish.
/// Mirrors orig's api_publish_my_skill five-step flow:
///   1. licensed gate            → 403 { ok: false, error }
///   2. skill not found          → 404 { ok: false, error }
///   3. builtin/brand source     → 422 { ok: false, error }
///   4. ZIP the skill directory with orig's exclusion rules
///   5. HMAC-signed multipart upload (POST, or PATCH when force=true),
///      then record_upload! and return { ok, name, platform_version };
///      upload failure → 422 { ok: false, error, already_exists }

// ── Platform endpoint ───────────────────────────────────────────────

///|
/// Platform base URL for the client skills API. Defaults to orig's
/// PlatformHttpClient PRIMARY_HOST; override via MBOPENCLACKY_PLATFORM_URL
/// for staging or self-hosted deployments (mirrors the
/// MBOPENCLACKY_DISTRIBUTION_URL convention in lib/brand).
fn platform_base_url() -> String {
  match @sys.get_env_var("MBOPENCLACKY_PLATFORM_URL") {
    Some(u) if u.length() > 0 => u
    _ => "https://www.openclacky.com"
  }
}

// ── ZIP building (orig step 4) ──────────────────────────────────────

///|
/// Directories excluded from the published ZIP, anywhere in the path
/// (orig: %w[__pycache__ .git .svn node_modules .cache]).
let publish_excluded_dirs : Array[String] = [
  "__pycache__", ".git", ".svn", "node_modules", ".cache",
]

///|
/// File patterns excluded from the published ZIP (orig:
/// /\.(pyc|rbc|class|o|so|dylib|dll|exe)$|\.DS_Store$|Thumbs\.db$/i).
/// Compiled bytecode and shared libraries are excluded because binary
/// payloads cause server-side errors (orig comment re: PostgreSQL nulls).
fn publish_is_excluded_file(rel : String) -> Bool {
  let lower = rel.to_lower()
  let suffixes = [
    ".pyc", ".rbc", ".class", ".o", ".so", ".dylib", ".dll", ".exe", ".ds_store",
  ]
  for s in suffixes {
    if lower.has_suffix(s) {
      return true
    }
  }
  lower.has_suffix("thumbs.db")
}

///|
/// Recursively collect publishable files under `dir`. `prefix` is the
/// current relative path ("" at the root). Mirrors orig's Dir.glob("**/*")
/// semantics: dot-entries are skipped at every level (Ruby's glob does not
/// match leading dots without FNM_DOTMATCH), excluded directories are not
/// descended into, and excluded file patterns are dropped.
fn collect_publish_files(
  dir : String,
  prefix : String,
  out : Array[(String, Bytes)],
) -> Result[Unit, String] {
  let entries = @fs.read_dir(dir) catch { e => return Err(@debug.to_string(e)) }
  for entry in entries {
    // Ruby's Dir.glob("**/*") never yields dot-entries.
    if entry.has_prefix(".") {
      continue
    }
    let full = dir + "/" + entry
    let rel = if prefix == "" { entry } else { prefix + "/" + entry }
    let is_sub_dir = @fs.is_dir(full) catch { _ => false }
    if is_sub_dir {
      if publish_excluded_dirs.contains(entry) {
        continue
      }
      match collect_publish_files(full, rel, out) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
    } else {
      if publish_is_excluded_file(rel) {
        continue
      }
      let data = @fs.read_file_to_bytes(full) catch {
        e => return Err(@debug.to_string(e))
      }
      out.push((rel, data))
    }
  }
  Ok(())
}

///|
/// Byte-order (UTF-16 code unit) string comparison. Ruby's Array#sort on
/// strings is bytewise (uppercase before lowercase), unlike MoonBit's
/// String::compare; orig's ZIP entry order follows Ruby semantics.
fn ruby_str_compare(a : String, b : String) -> Int {
  let la = a.length()
  let lb = b.length()
  let n = if la < lb { la } else { lb }
  for i = 0; i < n; i = i + 1 {
    let ca = a.code_unit_at(i).to_int()
    let cb = b.code_unit_at(i).to_int()
    if ca != cb {
      return ca - cb
    }
  }
  la - lb
}

///|
/// Build the publish ZIP for a skill directory. Entries are named
/// "{name}/{rel}" and sorted by relative path (orig sorts the glob).
fn build_skill_zip(name : String, skill_dir : String) -> Result[Bytes, String] {
  let files : Array[(String, Bytes)] = []
  match collect_publish_files(skill_dir, "", files) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  files.sort_by(fn(a, b) { ruby_str_compare(a.0, b.0) })
  let entries : Array[@zip.ZipEntry] = []
  for f in files {
    let (rel, data) = f
    entries.push({ name: name + "/" + rel, data })
  }
  @zip.create_zip(entries)
}

// ── Platform upload (orig step 5) ───────────────────────────────────

///|
/// Outcome of a platform skill upload, mirroring orig's upload_skill!
/// result shape: { success, skill/error, already_exists }.
priv struct SkillUploadOutcome {
  success : Bool
  error : String
  already_exists : Bool
  platform_version : String?
}

///|
fn upload_fail(
  error : String,
  already_exists? : Bool = false,
) -> SkillUploadOutcome {
  { success: false, error, already_exists, platform_version: None }
}

///|
/// Lowercase hex encode (for nonce and multipart boundary).
fn bytes_to_hex(bytes : Array[Byte]) -> String {
  let hex_digits = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let buf = StringBuilder::new()
  for b in bytes {
    let v = b.to_int()
    buf.write_char(hex_digits[v / 16])
    buf.write_char(hex_digits[v % 16])
  }
  buf.to_string()
}

///|
/// Parse the platform upload response. Success (2xx) extracts
/// skill.version as platform_version. Failure composes orig's message:
/// code/error field plus errors array joined with ", ", defaulting to
/// "HTTP {status}"; already_exists mirrors orig's detection
/// (code contains "name_taken"/"already", or HTTP 409).
fn parse_upload_response(status : Int, body : String) -> SkillUploadOutcome {
  let parsed : Json? = Some(@json.parse(body)) catch { _ => None }
  if status >= 200 && status < 300 {
    let mut version : String? = None
    match parsed {
      Some(Object(root)) =>
        match root.get("skill") {
          Some(Object(skill)) =>
            match skill.get("version") {
              Some(String(v)) => version = Some(v)
              _ => ()
            }
          _ => ()
        }
      _ => ()
    }
    return {
      success: true,
      error: "",
      already_exists: false,
      platform_version: version,
    }
  }
  let mut code = ""
  let mut errors_joined = ""
  match parsed {
    Some(Object(root)) => {
      match root.get("code") {
        Some(String(v)) => code = v
        _ =>
          match root.get("error") {
            Some(String(v)) => code = v
            _ => ()
          }
      }
      match root.get("errors") {
        Some(Array(items)) => {
          let parts : Array[String] = []
          for item in items {
            match item {
              String(s) => parts.push(s)
              _ => ()
            }
          }
          errors_joined = parts.join(", ")
        }
        _ => ()
      }
    }
    _ => ()
  }
  let detail = if code != "" && errors_joined != "" {
    code + ": " + errors_joined
  } else if code != "" {
    code
  } else {
    errors_joined
  }
  let msg = if detail == "" { "HTTP " + status.to_string() } else { detail }
  let already_exists = code.contains("name_taken") ||
    code.contains("already") ||
    status == 409
  upload_fail(msg, already_exists~)
}

///|
/// Upload a skill ZIP to the platform (orig's BrandConfig#upload_skill!).
/// HMAC-SHA256 signature: license_key over "user_id:device_id:ts:nonce";
/// the license key itself never leaves the process — only its SHA-256 hash
/// (key_hash field) and the HMAC signature are transmitted. force=true
/// switches POST /api/v1/client/skills → PATCH /api/v1/client/skills/:name.
async fn upload_skill_zip(
  brand : @brand.BrandConfig,
  name : String,
  zip_data : Bytes,
  force : Bool,
) -> SkillUploadOutcome {
  if !brand.activated() {
    return upload_fail("License not activated")
  }
  if !brand.user_licensed() {
    return upload_fail("User license required to upload skills")
  }
  let license_key = brand.license_key.unwrap_or("")
  let user_id = brand.license_user_id.unwrap_or("")
  let device_id = brand.device_id.unwrap_or("")
  let key_hash = @brand.sha256_hex(license_key)
  let ts = now_seconds().to_string()
  let nonce_bytes = match @brand.generate_nonce() {
    Ok(b) => b
    Err(e) => return upload_fail(e)
  }
  let nonce = bytes_to_hex(nonce_bytes)
  let message = user_id + ":" + device_id + ":" + ts + ":" + nonce
  let signature = @brand.hmac_sha256(license_key, message)
  // name is validated to [a-zA-Z0-9._-] upstream, so no URL encoding needed.
  let path = if force {
    "/api/v1/client/skills/" + name
  } else {
    "/api/v1/client/skills"
  }
  let boundary = "----ClackySkillUpload" + nonce[:16].to_owned()
  // Field order mirrors orig exactly.
  let fields = [
    ("key_hash", key_hash),
    ("user_id", user_id),
    ("device_id", device_id),
    ("timestamp", ts),
    ("nonce", nonce),
    ("signature", signature),
    ("name", name),
  ]
  let body = build_multipart_body(
    boundary,
    fields,
    "skill_zip",
    name + ".zip",
    zip_data,
  )
  let headers = [("Content-Type", "multipart/form-data; boundary=" + boundary)]
  let http_method = if force { "PATCH" } else { "POST" }
  // Uploads can be slow — orig allows a 60-second read timeout.
  match
    multipart_send(
      http_method,
      platform_base_url() + path,
      headers,
      body,
      60000,
    ) {
    Err(e) => upload_fail("Network error: " + e)
    Ok((status, resp_body)) => parse_upload_response(status, resp_body)
  }
}

// ── Publish flow ────────────────────────────────────────────────────

///|
/// Build a JSON error body in the orig publish shape.
fn publish_error_json(error : String, already_exists? : Bool = false) -> String {
  Json::object({
    "ok": false.to_json(),
    "error": error.to_json(),
    "already_exists": already_exists.to_json(),
  }).stringify()
}

///|
/// Locate a publishable skill directory. User dir takes precedence over
/// builtin (same rule as find_skill_dir, parameterized for testability).
fn find_publish_skill_dir(
  name : String,
  user_dir : String,
  builtin_dir : String,
) -> (String, String)? {
  let user_path = user_dir + "/" + name
  if @fs.path_exists(user_path + "/SKILL.md") {
    return Some((user_path, "user"))
  }
  let builtin_path = builtin_dir + "/" + name
  if @fs.path_exists(builtin_path + "/SKILL.md") {
    return Some((builtin_path, "builtin"))
  }
  None
}

///|
/// Core publish flow, parameterized for white-box testing.
/// Mirrors orig's api_publish_my_skill step order and response shapes.
async fn publish_skill(
  name : String,
  force : Bool,
  brand : @brand.BrandConfig,
  user_dir : String,
  builtin_dir : String,
) -> HttpResponse {
  // Step 1: licensed gate.
  if !brand.user_licensed() {
    return {
      status: 403,
      body: publish_error_json("User license required to publish skills"),
      body_bytes: None,
      content_type: "application/json",
      headers: [],
    }
  }
  // Step 2: skill must exist.
  let (skill_dir, source) = match
    find_publish_skill_dir(name, user_dir, builtin_dir) {
    Some(pair) => pair
    None =>
      return {
        status: 404,
        body: publish_error_json("Skill '" + name + "' not found"),
        body_bytes: None,
        content_type: "application/json",
        headers: [],
      }
  }
  // Step 3: only user-owned custom skills can be published. "builtin"
  // covers orig's :default; encrypted brand skills do not exist in this
  // runtime, so orig's :brand branch has no counterpart here.
  if source == "builtin" {
    return {
      status: 422,
      body: publish_error_json("Built-in system skills cannot be published"),
      body_bytes: None,
      content_type: "application/json",
      headers: [],
    }
  }
  // Step 3b (orig): skill directory must exist on disk.
  if !@fs.path_exists(skill_dir) {
    return {
      status: 422,
      body: publish_error_json("Skill directory not found: " + skill_dir),
      body_bytes: None,
      content_type: "application/json",
      headers: [],
    }
  }
  // Step 4: ZIP the skill directory.
  let zip_data = match build_skill_zip(name, skill_dir) {
    Ok(data) => data
    Err(e) =>
      return {
        status: 500,
        body: publish_error_json(e),
        body_bytes: None,
        content_type: "application/json",
        headers: [],
      }
  }
  // Step 5: signed multipart upload; record platform version on success.
  let outcome = upload_skill_zip(brand, name, zip_data, force)
  if outcome.success {
    match outcome.platform_version {
      Some(v) => @brand.record_upload(user_dir, name, v, now_seconds())
      None => ()
    }
    let version_json = match outcome.platform_version {
      Some(v) => v.to_json()
      None => Json::null()
    }
    {
      status: 200,
      body: Json::object({
        "ok": true.to_json(),
        "name": name.to_json(),
        "platform_version": version_json,
      }).stringify(),
      body_bytes: None,
      content_type: "application/json",
      headers: [],
    }
  } else {
    {
      status: 422,
      body: publish_error_json(
        outcome.error,
        already_exists=outcome.already_exists,
      ),
      body_bytes: None,
      content_type: "application/json",
      headers: [],
    }
  }
}

// ── HTTP handler & bridge ───────────────────────────────────────────

///|
/// POST /api/my-skills/:name/publish — publish a user skill to the market.
/// Query: ?force=true to overwrite an existing platform skill (PATCH path).
pub async fn handle_my_skill_publish(request : HttpRequest) -> HttpResponse {
  let name = match validated_name(request) {
    Ok(n) => n
    Err(resp) => return resp
  }
  let force = request.get_param("force") == Some("true")
  publish_skill(
    name,
    force,
    @brand.BrandConfig::load(brand_config_dir()),
    user_skills_dir(),
    BUILTIN_SKILLS_DIR,
  )
}

///|
/// Convert a publish HttpResponse to crescent's response type, preserving
/// the exact status code (the generic response_to_core only maps a subset).
fn publish_response_to_core(resp : HttpResponse) -> @core.HttpResponse {
  let status = match resp.status {
    200 => @core.StatusCode::OK
    400 => @core.StatusCode::BadRequest
    403 => @core.StatusCode::Forbidden
    404 => @core.StatusCode::NotFound
    422 => @core.StatusCode::UnprocessableEntity
    500 => @core.StatusCode::InternalServerError
    503 => @core.StatusCode::ServiceUnavailable
    _ => @core.StatusCode::InternalServerError
  }
  @core.HttpResponse::HttpResponse(status_code=status)
  .header("Content-Type", resp.content_type)
  .body(resp.body)
}

///|
/// Bridge: crescent event → publish handler. Forwards the ?force query
/// parameter alongside the :name path parameter.
async fn handle_my_skill_publish_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let params = extract_name_param(event)
  match event.req.get_query("force") {
    Some(v) => params.push(("force", v))
    None => ()
  }
  let req = event_to_request(event, params)
  publish_response_to_core(handle_my_skill_publish(req))
}
