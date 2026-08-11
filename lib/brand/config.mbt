///|
using @toml {type TomlValue}

///|
/// White-label brand configuration (from brand.toml)
pub(all) struct BrandConfig {
  mut product_name : String?
  mut package_name : String?
  mut logo_url : String?
  mut support_contact : String?
  mut support_qr_url : String?
  mut theme_color : String?
  mut homepage_url : String?
  mut license_key : String?
  mut license_activated_at : String?
  mut license_expires_at : String?
  mut license_last_heartbeat : String?
  mut device_id : String?
  mut license_user_id : String?
  mut distribution_last_refreshed_at : String?
  mut license_last_heartbeat_failure : String?
} derive(Eq, Debug, ToJson)

///|
let brand_dir_name = ".mbopenclacky"

///|
let brand_file_name = "brand.toml"

///|
fn resolve_brand_dir(config_dir : String?) -> String? {
  match config_dir {
    Some(d) if !d.is_empty() => Some(d)
    _ =>
      match @utils.home_dir() {
        Some(home) =>
          Some(@path.Path::join(home, @path.Path(brand_dir_name)).to_string())
        None => None
      }
  }
}

///|
fn resolve_brand_file(config_dir : String?) -> String? {
  match resolve_brand_dir(config_dir) {
    Some(dir) =>
      Some(@path.Path::join(dir, @path.Path(brand_file_name)).to_string())
    None => None
  }
}

///|
/// Load brand configuration from brand.toml.
pub fn BrandConfig::load(config_dir : String) -> BrandConfig {
  let config = match resolve_brand_file(Some(config_dir)) {
    Some(path) =>
      match @fs.path_exists(path) {
        true => {
          let content = @fs.read_file_to_string(path) catch { _ => "" }
          if content.is_empty() {
            BrandConfig::default_config()
          } else {
            let toml_val = @toml.parse(content) catch {
              _ => return BrandConfig::default_config()
            }
            BrandConfig::from_toml(toml_val)
          }
        }
        false => BrandConfig::default_config()
      }
    None => BrandConfig::default_config()
  }
  if config.device_id is None {
    config.device_id = Some(generate_device_id().device_id)
  }
  config
}

///|
/// Default empty config
pub fn BrandConfig::default_config() -> BrandConfig {
  {
    product_name: None,
    package_name: None,
    logo_url: None,
    support_contact: None,
    support_qr_url: None,
    theme_color: None,
    homepage_url: None,
    license_key: None,
    license_activated_at: None,
    license_expires_at: None,
    license_last_heartbeat: None,
    device_id: None,
    license_user_id: None,
    distribution_last_refreshed_at: None,
    license_last_heartbeat_failure: None,
  }
}

///|
fn BrandConfig::from_toml(value : TomlValue) -> BrandConfig {
  let c = BrandConfig::default_config()
  match value {
    TomlTable(root) => {
      fn get_str(m : Map[String, TomlValue], k : String) -> String? {
        match m.get(k) {
          Some(TomlString(s)) => Some(s)
          _ => None
        }
      }
      c.product_name = get_str(root, "product_name")
      c.package_name = get_str(root, "package_name")
      c.logo_url = get_str(root, "logo_url")
      c.support_contact = get_str(root, "support_contact")
      c.support_qr_url = get_str(root, "support_qr_url")
      c.theme_color = get_str(root, "theme_color")
      c.homepage_url = get_str(root, "homepage_url")
      c.license_key = get_str(root, "license_key")
      c.license_activated_at = get_str(root, "license_activated_at")
      c.license_expires_at = get_str(root, "license_expires_at")
      c.license_last_heartbeat = get_str(root, "license_last_heartbeat")
      c.device_id = get_str(root, "device_id")
      c.license_user_id = get_str(root, "license_user_id")
      c.distribution_last_refreshed_at = get_str(
        root, "distribution_last_refreshed_at",
      )
      c.license_last_heartbeat_failure = get_str(
        root, "license_last_heartbeat_failure",
      )
    }
    _ => ()
  }
  c
}

///|
pub fn BrandConfig::is_branded(self : BrandConfig) -> Bool {
  match self.product_name {
    Some(n) => n.length() > 0
    None => false
  }
}

///|
pub fn BrandConfig::display_name(self : BrandConfig) -> String {
  match self.product_name {
    Some(n) => n
    None => "MBOpenClacky"
  }
}

///|
pub fn BrandConfig::activated(self : BrandConfig) -> Bool {
  match self.license_key {
    Some(k) => k.length() > 0
    None => false
  }
}

///|
pub fn BrandConfig::expired(self : BrandConfig, current_time : Int) -> Bool {
  match self.license_expires_at {
    Some(e) =>
      match parse_iso8601_timestamp(e) {
        Some(ts) => current_time > ts
        None => false
      }
    None => false
  }
}

///|
pub fn BrandConfig::user_licensed(self : BrandConfig) -> Bool {
  if !self.activated() {
    return false
  }
  match self.license_user_id {
    Some(u) => u.length() > 0
    None => false
  }
}

///|
pub fn BrandConfig::distribution_refresh_due(
  self : BrandConfig,
  current_time : Int,
) -> Bool {
  if !self.is_branded() {
    return false
  }
  if self.activated() {
    return false
  }
  match self.distribution_last_refreshed_at {
    None => true
    Some(ts) =>
      match parse_iso8601_timestamp(ts) {
        Some(last) => current_time - last >= HEARTBEAT_INTERVAL
        None => true
      }
  }
}

///|
/// Refresh distribution from public endpoint via HTTP GET.
/// Falls back gracefully: on network error returns Err without blocking startup.
pub async fn BrandConfig::refresh_distribution(
  self : BrandConfig,
  current_time : Int,
) -> Result[Unit, String] {
  guard self.is_branded() else { return Err("Not branded") }
  guard !self.activated() else {
    return Err("License activated — use heartbeat")
  }
  let pkg = match self.package_name {
    Some(p) if p.length() > 0 => p
    _ => return Err("package_name not configured")
  }
  // Construct distribution lookup URL.
  // Override via MBOPENCLACKY_DISTRIBUTION_URL env var for custom deployments.
  let base_url = match @env.get_env_var("MBOPENCLACKY_DISTRIBUTION_URL") {
    Some(u) if u.length() > 0 => u
    _ => "https://api.mbopenclacky.com"
  }
  let url = "\{base_url}/api/v1/distributions/lookup?package_name=\{pkg}"
  match brand_http_get(url, 8000) {
    Ok((status, body)) if status >= 200 && status < 300 => {
      // Parse JSON response and apply distribution fields.
      let json = @json.parse(body) catch {
        _ => return Err("Invalid JSON response")
      }
      match json {
        Object(fields) => {
          fn get_str(m : Map[String, Json], k : String) -> String? {
            match m.get(k) {
              Some(String(s)) => Some(s)
              _ => None
            }
          }
          let dist : Map[String, String] = Map([])
          let keys = [
            "product_name", "package_name", "logo_url", "support_contact", "support_qr_url",
            "theme_color", "homepage_url",
          ]
          for key in keys {
            match get_str(fields, key) {
              Some(v) => dist[key] = v
              None => ()
            }
          }
          self.apply_distribution(dist)
        }
        _ => return Err("Unexpected JSON shape")
      }
      self.distribution_last_refreshed_at = Some(format_iso8601(current_time))
      Ok(())
    }
    Ok((status, _)) => Err("HTTP \{status} from distribution endpoint")
    Err(e) => Err(e)
  }
}

///|
/// Apply distribution fields from API response data.
pub fn BrandConfig::apply_distribution(
  self : BrandConfig,
  dist : Map[String, String],
) -> Unit {
  match dist.get("product_name") {
    Some(v) if v.length() > 0 => self.product_name = Some(v)
    _ => ()
  }
  match dist.get("package_name") {
    Some(v) if v.length() > 0 => self.package_name = Some(v)
    _ => ()
  }
  match dist.get("logo_url") {
    Some(v) if v.length() > 0 => self.logo_url = Some(v)
    _ => ()
  }
  match dist.get("support_contact") {
    Some(v) if v.length() > 0 => self.support_contact = Some(v)
    _ => ()
  }
  match dist.get("support_qr_url") {
    Some(v) if v.length() > 0 => self.support_qr_url = Some(v)
    _ => ()
  }
  match dist.get("theme_color") {
    Some(v) if v.length() > 0 => self.theme_color = Some(v)
    _ => ()
  }
  match dist.get("homepage_url") {
    Some(v) if v.length() > 0 => self.homepage_url = Some(v)
    _ => ()
  }
}

///|
/// Save config to brand.toml.
pub fn BrandConfig::save(
  self : BrandConfig,
  config_dir : String,
) -> Result[Unit, String] {
  let dir = match resolve_brand_dir(Some(config_dir)) {
    Some(d) => d
    None => return Err("Cannot determine brand config directory")
  }
  @utils.ensure_dir(dir)
  let path = @path.Path::join(dir, @path.Path(brand_file_name)).to_string()
  let content = self.to_toml_string()
  @fs.write_string_to_file(path, content) catch {
    _ => return Err("Failed to write brand config")
  }
  Ok(())
}

///|
fn BrandConfig::to_toml_string(self : BrandConfig) -> String {
  let root : Map[String, TomlValue] = Map([])
  fn put(m : Map[String, TomlValue], k : String, v : String?) -> Unit {
    match v {
      Some(s) => m[k] = TomlString(s)
      None => ()
    }
  }
  put(root, "product_name", self.product_name)
  put(root, "package_name", self.package_name)
  put(root, "logo_url", self.logo_url)
  put(root, "support_contact", self.support_contact)
  put(root, "support_qr_url", self.support_qr_url)
  put(root, "theme_color", self.theme_color)
  put(root, "homepage_url", self.homepage_url)
  put(root, "license_key", self.license_key)
  put(root, "license_activated_at", self.license_activated_at)
  put(root, "license_expires_at", self.license_expires_at)
  put(root, "license_last_heartbeat", self.license_last_heartbeat)
  put(root, "device_id", self.device_id)
  put(root, "license_user_id", self.license_user_id)
  put(
    root,
    "distribution_last_refreshed_at",
    self.distribution_last_refreshed_at,
  )
  put(
    root,
    "license_last_heartbeat_failure",
    self.license_last_heartbeat_failure,
  )
  @toml.TomlTable(root).to_string()
}

///|
/// Hash representation for JSON serialization.
pub fn BrandConfig::to_h(self : BrandConfig) -> Map[String, String] {
  let r : Map[String, String] = Map([])
  match self.product_name {
    Some(v) => r["product_name"] = v
    None => ()
  }
  match self.package_name {
    Some(v) => r["package_name"] = v
    None => ()
  }
  r["branded"] = self.is_branded().to_string()
  r["activated"] = self.activated().to_string()
  r
}

///|
/// Parse a non-negative integer from a string. Returns None on failure.
fn parse_int_opt(s : String) -> Int? {
  if s.is_empty() {
    return None
  }
  let mut result = 0
  for c in s {
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - '0'.to_int())
    } else {
      return None
    }
  }
  Some(result)
}

///|
/// Parse simplified ISO 8601 timestamp to unix seconds.
fn parse_iso8601_timestamp(s : String) -> Int? {
  guard s.length() >= 19 else { return None }
  let year_str = s[0:4].to_owned()
  let month_str = s[5:7].to_owned()
  let day_str = s[8:10].to_owned()
  let hour_str = s[11:13].to_owned()
  let min_str = s[14:16].to_owned()
  let sec_str = s[17:19].to_owned()
  let year = match parse_int_opt(year_str) {
    Some(v) => v
    None => return None
  }
  let month = match parse_int_opt(month_str) {
    Some(v) => v
    None => return None
  }
  let day = match parse_int_opt(day_str) {
    Some(v) => v
    None => return None
  }
  let hour = match parse_int_opt(hour_str) {
    Some(v) => v
    None => return None
  }
  let min = match parse_int_opt(min_str) {
    Some(v) => v
    None => return None
  }
  let sec = match parse_int_opt(sec_str) {
    Some(v) => v
    None => return None
  }
  let days_from_year = (year - 1970) * 365 + (year - 1969) / 4
  let days_in_month = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
  guard month >= 1 && month <= 12 else { return None }
  let days = days_from_year + days_in_month[month - 1] + day - 1
  Some(days * 86400 + hour * 3600 + min * 60 + sec)
}

///|
/// Format unix timestamp as ISO 8601 string.
pub fn format_iso8601(timestamp : Int) -> String {
  let sec = timestamp % 60
  let min = timestamp / 60 % 60
  let hour = timestamp / 3600 % 24
  let total_days = timestamp / 86400
  let year = 1970 + total_days / 365
  let remaining_days = total_days - (year - 1970) * 365 - (year - 1969) / 4
  let days_in_month = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  let mut month = 1
  let mut day_acc = remaining_days
  for i = 0; i < 12; i = i + 1 {
    if day_acc < days_in_month[i] {
      month = i + 1
      break
    }
    day_acc = day_acc - days_in_month[i]
    if i == 11 {
      month = 12
    }
  }
  let day = day_acc + 1
  fn pad2(n : Int) -> String {
    if n < 10 {
      "0\{n}"
    } else {
      n.to_string()
    }
  }
  fn pad4(n : Int) -> String {
    if n < 10 {
      "000\{n}"
    } else if n < 100 {
      "00\{n}"
    } else if n < 1000 {
      "0\{n}"
    } else {
      n.to_string()
    }
  }
  "\{pad4(year)}-\{pad2(month)}-\{pad2(day)}T\{pad2(hour)}:\{pad2(min)}:\{pad2(sec)}Z"
}

// ── Skill upload metadata (fix-17 publish) ──────────────────────────

///|
/// One skill's upload record: which platform version it was published as and
/// when. Mirrors orig's upload_meta.json entry shape:
///   { "platform_version" => "1.2.0", "uploaded_at" => "2026-04-09T..." }
pub(all) struct UploadMeta {
  platform_version : String
  uploaded_at : String
} derive(Eq, Debug)

///|
/// Path to the upload_meta.json file that tracks which local skills have
/// been published to the platform. Mirrors orig's
/// ~/.clacky/skills/upload_meta.json (skills dir under the config home).
pub fn upload_meta_path(skills_dir : String) -> String {
  skills_dir + "/upload_meta.json"
}

///|
/// Load upload metadata for all published local skills.
/// Returns an empty map when the file is missing or malformed (orig's
/// load_upload_meta rescues to {}).
pub fn load_upload_meta(skills_dir : String) -> Map[String, UploadMeta] {
  let result : Map[String, UploadMeta] = Map([])
  let path = upload_meta_path(skills_dir)
  if !@fs.path_exists(path) {
    return result
  }
  let content = @fs.read_file_to_string(path) catch { _ => return result }
  let json = @json.parse(content) catch { _ => return result }
  guard json is Object(root) else { return result }
  for name, entry in root {
    guard entry is Object(fields) else { continue }
    let version = match fields.get("platform_version") {
      Some(String(v)) => v
      _ => continue
    }
    let uploaded_at = match fields.get("uploaded_at") {
      Some(String(v)) => v
      _ => ""
    }
    result[name] = { platform_version: version, uploaded_at }
  }
  result
}

///|
/// Persist a single skill's upload record (orig's record_upload! semantics:
/// merge into the existing map and rewrite the file). `now` is unix seconds,
/// formatted as ISO 8601 UTC. Write failures are non-fatal — metadata
/// persistence must not break the upload flow (orig rescues StandardError).
pub fn record_upload(
  skills_dir : String,
  skill_name : String,
  platform_version : String,
  now : Int,
) -> Unit {
  let meta = load_upload_meta(skills_dir)
  meta[skill_name] = { platform_version, uploaded_at: format_iso8601(now) }
  let root : Map[String, Json] = Map([])
  for name, entry in meta {
    root[name] = Json::object({
      "platform_version": entry.platform_version.to_json(),
      "uploaded_at": entry.uploaded_at.to_json(),
    })
  }
  @utils.ensure_dir(skills_dir)
  @fs.write_string_to_file(
    upload_meta_path(skills_dir),
    Json::object(root).stringify(),
  ) catch {
    _ => ()
  }
}
