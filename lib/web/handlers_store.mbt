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
  obj["id"] = m.id.to_json()
  obj["name"] = m.name.to_json()
  obj["version"] = m.version.to_json()
  obj["description"] = m.description.to_json()
  obj["author"] = m.author.to_json()
  obj["license"] = m.license.to_json()
  obj["enabled"] = ext.enabled.to_json()
  obj["installed"] = (ext.source is @extension.ExtensionSource::Installed).to_json()
  obj["source"] = match ext.source {
    Builtin => "builtin".to_json()
    Installed => "installed".to_json()
    Local => "local".to_json()
  }
  obj["root_path"] = ext.root_path.to_json()
  obj["loaded_at"] = ext.loaded_at.to_json()
  match m.homepage {
    Some(h) => obj["homepage"] = h.to_json()
    None => ()
  }
  match m.repository {
    Some(r) => obj["repository"] = r.to_json()
    None => ()
  }
  obj["enabled_by_default"] = m.enabled_by_default.to_json()
  // Keywords
  let kw : Array[Json] = []
  m.keywords.each(fn(k) { kw.push(k.to_json()) })
  obj["keywords"] = Json::array(kw)
  Json::object(obj)
}

///|
/// Serialize a RegistryEntry to a JSON object for the store catalog.
fn registry_entry_to_store_json(entry : @extension.RegistryEntry) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["id"] = entry.id.to_json()
  let name = match entry.metadata.get("name") {
    Some(s) => s
    None => entry.id
  }
  obj["name"] = name.to_json()
  let name_zh = match entry.metadata.get("name_zh") {
    Some(s) => s
    None => ""
  }
  obj["name_zh"] = name_zh.to_json()
  let desc = match entry.metadata.get("description") {
    Some(s) => s
    None => ""
  }
  obj["description"] = desc.to_json()
  obj["version"] = entry.latest_version.to_json()
  obj["latest_version"] = entry.latest_version.to_json()
  let author = match entry.metadata.get("author") {
    Some(s) => s
    None => ""
  }
  obj["author"] = author.to_json()
  obj["installs"] = entry.installs.to_json()
  obj["published_at"] = entry.published_at.to_json()
  // Versions array
  let vers : Array[Json] = []
  entry.versions.each(fn(v) { vers.push(v.to_json()) })
  obj["versions"] = Json::array(vers)
  // download_url from metadata if present
  match entry.metadata.get("download_url") {
    Some(url) => obj["download_url"] = url.to_json()
    None => ()
  }
  obj["installed"] = false.to_json()
  obj["enabled"] = false.to_json()
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
          obj["installed"] = true.to_json()
          obj["enabled"] = @extension.is_extension_enabled(e.id).to_json()
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
  let resp = Json::object({ "extensions": Json::array(filtered) }).stringify()
  HttpResponse::ok(resp)
}

///|
/// GET /api/store/extensions/installed - List installed extensions.
pub fn handle_store_installed(_request : HttpRequest) -> HttpResponse {
  let installed = @extension.list_installed_extensions()
  let arr : Array[Json] = []
  installed.each(fn(e) { arr.push(extension_to_store_json(e)) })
  let resp = Json::object({ "extensions": Json::array(arr) }).stringify()
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
        "ok": true.to_json(),
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
            "ok": true.to_json(),
            "extension": registry_entry_to_store_json(entry),
          }).stringify()
          HttpResponse::ok(resp)
        }
        None =>
          HttpResponse::not_found(
            Json::object({
              "ok": false.to_json(),
              "error": "Extension not found".to_json(),
              "id": id.to_json(),
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
        "ok": false.to_json(),
        "error": "unimplemented".to_json(),
        "message": "Remote extension download is not yet supported. Install from local path instead.".to_json(),
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
        "ok": true.to_json(),
        "extension": extension_to_store_json(ext),
        "message": "Extension installed successfully".to_json(),
      }).stringify()
      HttpResponse::ok(resp)
    }
    Err(e) =>
      HttpResponse::{
        status: 400,
        body: Json::object({ "ok": false.to_json(), "error": e.to_json() }).stringify(),
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
        "ok": true.to_json(),
        "extension": extension_to_store_json(ext),
      }).stringify()
      HttpResponse::ok(resp)
    }
    Err(e) =>
      HttpResponse::{
        status: 400,
        body: Json::object({ "ok": false.to_json(), "error": e.to_json() }).stringify(),
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
        "ok": true.to_json(),
        "extension": extension_to_store_json(ext),
      }).stringify()
      HttpResponse::ok(resp)
    }
    Err(e) =>
      HttpResponse::{
        status: 400,
        body: Json::object({ "ok": false.to_json(), "error": e.to_json() }).stringify(),
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
        "ok": true.to_json(),
        "message": "Extension uninstalled successfully".to_json(),
      }).stringify()
      HttpResponse::ok(resp)
    }
    Err(e) =>
      HttpResponse::{
        status: 400,
        body: Json::object({ "ok": false.to_json(), "error": e.to_json() }).stringify(),
        body_bytes: None,
        content_type: "application/json",
        headers: [],
      }
  }
}
