///| Extension store handlers (spec-09): marketplace browse + install/enable/disable/uninstall.
/// All 7 endpoints serve the frontend features/extensions/store.js panel.
/// Read endpoints delegate to lib/extension marketplace API.
/// Write endpoints (install) return 501 if no download_url; enable/disable/uninstall
/// delegate to lib/extension.

///|
/// Serialize an Extension to a JSON object for the store API.
fn extension_to_store_json(ext : @extension.Extension) -> Json {
  let m = ext.manifest
  let obj : Map[String, Json] = Map([])
  obj["id"] = Json(m.id)
  obj["name"] = Json(m.name)
  obj["version"] = Json(m.version)
  obj["description"] = Json(m.description)
  obj["author"] = Json(m.author)
  obj["license"] = Json(m.license)
  obj["enabled"] = Json(ext.enabled)
  obj["installed"] = Json(ext.source is @extension.ExtensionSource::Installed)
  obj["source"] = match ext.source {
    Builtin => Json("builtin")
    Installed => Json("installed")
    Local => Json("local")
  }
  obj["root_path"] = Json(ext.root_path)
  obj["loaded_at"] = Json(ext.loaded_at)
  match m.homepage {
    Some(h) => obj["homepage"] = Json(h)
    None => ()
  }
  match m.repository {
    Some(r) => obj["repository"] = Json(r)
    None => ()
  }
  obj["enabled_by_default"] = Json(m.enabled_by_default)
  // Keywords
  let kw : Array[Json] = []
  m.keywords.each(fn(k) { kw.push(Json(k)) })
  obj["keywords"] = Json::array(kw)
  Json::object(obj)
}

///|
/// Serialize a RegistryEntry to a JSON object for the store catalog.
fn registry_entry_to_store_json(entry : @extension.RegistryEntry) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["id"] = Json(entry.id)
  let name = match entry.metadata.get("name") {
    Some(s) => s
    None => entry.id
  }
  obj["name"] = Json(name)
  let name_zh = match entry.metadata.get("name_zh") {
    Some(s) => s
    None => ""
  }
  obj["name_zh"] = Json(name_zh)
  let desc = match entry.metadata.get("description") {
    Some(s) => s
    None => ""
  }
  obj["description"] = Json(desc)
  obj["version"] = Json(entry.latest_version)
  obj["latest_version"] = Json(entry.latest_version)
  let author = match entry.metadata.get("author") {
    Some(s) => s
    None => ""
  }
  obj["author"] = Json(author)
  obj["installs"] = Json(entry.installs)
  obj["published_at"] = Json(entry.published_at)
  // Versions array
  let vers : Array[Json] = []
  entry.versions.each(fn(v) { vers.push(Json(v)) })
  obj["versions"] = Json::array(vers)
  // download_url from metadata if present
  match entry.metadata.get("download_url") {
    Some(url) => obj["download_url"] = Json(url)
    None => ()
  }
  obj["installed"] = Json(false)
  obj["enabled"] = Json(false)
  Json::object(obj)
}

///|
/// GET /api/store/extensions - List marketplace extensions.
/// Query params: q (search), sort (newest|updated|downloads).
pub fn handle_store_list(request : HttpRequest) -> HttpResponse {
  let entries = @extension.list_marketplace_extensions()
  // Mark installed extensions
  let installed = @extension.list_installed_extensions()
  let installed_ids : Map[String, Unit] = Map([])
  installed.each(fn(e) { installed_ids[e.manifest.id] = () })
  let arr : Array[Json] = []
  entries.each(fn(e) {
    let json = match registry_entry_to_store_json(e) {
      Object(obj) =>
        if installed_ids.contains(e.id) {
          obj["installed"] = Json(true)
          obj["enabled"] = Json(@extension.is_extension_enabled(e.id))
          Json::object(obj)
        } else {
          Json::object(obj)
        }
      other => other
    }
    arr.push(json)
  })
  // Apply search filter if q param present
  let q = match request.get_param("q") {
    Some(query) => query.to_lower()
    None => ""
  }
  let filtered = if q == "" {
    arr
  } else {
    let result : Array[Json] = []
    arr.each(fn(j) {
      match j {
        Object(obj) =>
          match (obj.get("name"), obj.get("description")) {
            (Some(String(n)), Some(String(d))) =>
              if n.to_lower().contains(q) || d.to_lower().contains(q) {
                result.push(j)
              }
            _ => ()
          }
        _ => ()
      }
    })
    result
  }
  // fix-20 (I-033): read endpoints carry ok:true like the write endpoints.
  let resp = Json::object({
    "ok": Json(true),
    "extensions": Json::array(filtered),
  }).stringify()
  HttpResponse::ok(resp)
}

///|
/// GET /api/store/extensions/installed - List installed extensions.
pub fn handle_store_installed(_request : HttpRequest) -> HttpResponse {
  let installed = @extension.list_installed_extensions()
  let arr : Array[Json] = []
  installed.each(fn(e) { arr.push(extension_to_store_json(e)) })
  let resp = Json::object({ "ok": Json(true), "extensions": Json::array(arr) }).stringify()
  HttpResponse::ok(resp)
}

///|
/// GET /api/store/extension?id= - Get extension detail.
pub fn handle_store_detail(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing 'id' query parameter")
  }
  // Check installed extensions first
  let installed = @extension.list_installed_extensions()
  match installed.iter().find_first(fn(e) { e.manifest.id == id }) {
    Some(ext) => {
      let resp = Json::object({
        "ok": Json(true),
        "extension": extension_to_store_json(ext),
      }).stringify()
      HttpResponse::ok(resp)
    }
    None => {
      // Check marketplace registry
      let entries = @extension.list_marketplace_extensions()
      match entries.iter().find_first(fn(e) { e.id == id }) {
        Some(entry) => {
          let resp = Json::object({
            "ok": Json(true),
            "extension": registry_entry_to_store_json(entry),
          }).stringify()
          HttpResponse::ok(resp)
        }
        None =>
          HttpResponse::not_found(
            Json::object({
              "ok": Json(false),
              "error": Json("Extension not found"),
              "id": Json(id),
            }).stringify(),
          )
      }
    }
  }
}

///|
/// POST /api/store/extension/install - Install extension from download URL.
/// Body: {download_url, name}.
/// Since we don't support remote download yet, returns 501 if no local path.
pub fn handle_store_install(request : HttpRequest) -> HttpResponse {
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  let body_json : Json = @json.parse(request.body) catch {
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  let (download_url, _) = match body_json {
    Object(obj) => {
      let url = match obj.get("download_url") {
        Some(String(s)) => s
        _ => ""
      }
      let n = match obj.get("name") {
        Some(String(s)) => s
        _ => ""
      }
      (url, n)
    }
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  if download_url == "" {
    return HttpResponse::{
      status: 501,
      body: Json::object({
        "ok": Json(false),
        "error": Json("unimplemented"),
        "message": Json(
          "Remote extension download is not yet supported. Install from local path instead.",
        ),
      }).stringify(),
      body_bytes: None,
      content_type: "application/json",
      headers: [],
    }
  }
  // Try to install from the path (local file path)
  match @extension.install_extension_from_path(download_url) {
    Ok(ext) => {
      let resp = Json::object({
        "ok": Json(true),
        "extension": extension_to_store_json(ext),
        "message": Json("Extension installed successfully"),
      }).stringify()
      HttpResponse::ok(resp)
    }
    Err(e) =>
      HttpResponse::{
        status: 400,
        body: Json::object({ "ok": Json(false), "error": Json(e) }).stringify(),
        body_bytes: None,
        content_type: "application/json",
        headers: [],
      }
  }
}

///|
/// POST /api/store/extension/enable - Enable an extension.
/// Body: {id}.
pub fn handle_store_enable(request : HttpRequest) -> HttpResponse {
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  let body_json : Json = @json.parse(request.body) catch {
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  let id = match body_json {
    Object(obj) =>
      match obj.get("id") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
  if id == "" {
    return HttpResponse::bad_request("Missing 'id' in request body")
  }
  match @extension.enable_extension(id) {
    Ok(ext) => {
      let resp = Json::object({
        "ok": Json(true),
        "extension": extension_to_store_json(ext),
      }).stringify()
      HttpResponse::ok(resp)
    }
    Err(e) =>
      HttpResponse::{
        status: 400,
        body: Json::object({ "ok": Json(false), "error": Json(e) }).stringify(),
        body_bytes: None,
        content_type: "application/json",
        headers: [],
      }
  }
}

///|
/// POST /api/store/extension/disable - Disable an extension.
/// Body: {id}.
pub fn handle_store_disable(request : HttpRequest) -> HttpResponse {
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  let body_json : Json = @json.parse(request.body) catch {
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  let id = match body_json {
    Object(obj) =>
      match obj.get("id") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
  if id == "" {
    return HttpResponse::bad_request("Missing 'id' in request body")
  }
  match @extension.disable_extension(id) {
    Ok(ext) => {
      let resp = Json::object({
        "ok": Json(true),
        "extension": extension_to_store_json(ext),
      }).stringify()
      HttpResponse::ok(resp)
    }
    Err(e) =>
      HttpResponse::{
        status: 400,
        body: Json::object({ "ok": Json(false), "error": Json(e) }).stringify(),
        body_bytes: None,
        content_type: "application/json",
        headers: [],
      }
  }
}

///|
/// DELETE /api/store/extension - Uninstall an extension.
/// Body: {id, purge_data?}. purge_data=true also deletes the extension's
/// package-external user data (~/.clacky/ext-data/<id>).
pub fn handle_store_uninstall(request : HttpRequest) -> HttpResponse {
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  let body_json : Json = @json.parse(request.body) catch {
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  let id = match body_json {
    Object(obj) =>
      match obj.get("id") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
  let purge_data = match body_json {
    Object(obj) =>
      match obj.get("purge_data") {
        Some(True) => true
        _ => false
      }
    _ => false
  }
  if id == "" {
    return HttpResponse::bad_request("Missing 'id' in request body")
  }
  match @extension.uninstall_extension(id, purge_data~) {
    Ok(_) => {
      let resp = Json::object({
        "ok": Json(true),
        "message": Json("Extension uninstalled successfully"),
      }).stringify()
      HttpResponse::ok(resp)
    }
    Err(e) =>
      HttpResponse::{
        status: 400,
        body: Json::object({ "ok": Json(false), "error": Json(e) }).stringify(),
        body_bytes: None,
        content_type: "application/json",
        headers: [],
      }
  }
}

///|
/// GET /api/store/extensions/brand — List brand-private marketplace extensions.
/// The frontend (web/features/extensions/store.js#loadBrandExtensions)
/// expects `{ extensions: [], warning: string|null }`. Until a
/// brand-scoped registry is wired (B3/brand spec), this returns an
/// empty list with a warning so the panel can render the empty state
/// rather than failing the fetch. See spec 2026-08-18_17 task pack 3.
pub fn handle_store_brand_list(_request : HttpRequest) -> HttpResponse {
  let resp = Json::object({
    "ok": Json(true),
    "extensions": Json::array([]),
    "warning": Json("No brand-private extension registry configured"),
  }).stringify()
  HttpResponse::ok(resp)
}
