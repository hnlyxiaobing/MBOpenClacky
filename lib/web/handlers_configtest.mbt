///| Model connectivity test REST API handlers.

///|
/// Detect whether a URL ends with a version segment like `/v1`, `/v3`, or
/// `/v10` (optionally with a trailing slash). Many OpenAI-compatible
/// providers embed the API version in their base URL — e.g.
/// `https://ark.cn-beijing.volces.com/api/coding/v3` (Volces Ark Coding
/// Plan) or `https://api.deepseek.com/v1` (DeepSeek). A naïve
/// `has_suffix("/v1")` misses every other version, producing a doubled
/// `/v3/v1/models` probe URL that the upstream then returns 404 for.
///
/// We want to ask the upstream "do you have a /models endpoint at this
/// base?" — which means "should I append /models or /v1/models?" If the
/// base already has a version, we just append /models; otherwise we
/// default to the OpenAI convention /v1/models.
fn has_version_suffix(url : String) -> Bool {
  // Strip a single trailing slash so /v3/ also matches.
  let trimmed = if url.has_suffix("/") {
    String::sub(url, end=url.length() - 1).to_string()
  } else {
    url
  }
  match trimmed.rev_find("/") {
    None => false
    Some(idx) => {
      let tail = String::sub(trimmed, start=idx + 1).to_string()
      if tail.length() < 2 {
        false
      } else {
        match tail.get_char(0) {
          Some('v') | Some('V') => {
            // All remaining chars must be ASCII digits 0-9.
            let mut all_digit = true
            for i in 1..<tail.length() {
              match tail.get_char(i) {
                Some(c) =>
                  if c.to_int() < 48 || c.to_int() > 57 {
                    all_digit = false
                    break
                  }
                None => {
                  all_digit = false
                  break
                }
              }
            }
            all_digit
          }
          _ => false
        }
      }
    }
  }
}

///|
/// Strip a single trailing slash from a URL. Used to normalize base_url
/// before path concatenation so we never produce accidental `//` segments.
fn strip_trailing_slash(url : String) -> String {
  if url.has_suffix("/") {
    String::sub(url, end=url.length() - 1).to_string()
  } else {
    url
  }
}

///|
/// Probe an OpenAI-compatible endpoint with two fallback strategies so a
/// non-standard layout (e.g. Volces Ark Coding Plan, which has no
/// `/models` listing but does respond on `/chat/completions`) doesn't
/// return a misleading 404. The call sequence is:
///
///   1. GET `{base}/models` (or `{base}/v1/models` if no version embedded)
///   2. If that returns 404/405, POST `{base}/chat/completions` with a
///      minimal payload — 1 token, no tools, no stream. The upstream
///      should answer 2xx (real) or 4xx (auth/bad-model), and either
///      outcome tells the user the endpoint and key are reachable.
///
/// The first 2xx is treated as success. If both probes fail we return
/// the more informative of the two errors (network > 4xx > 5xx).
fn probe_openai_compatible(
  base_url : String,
  api_key : String,
  model : String,
  timeout_ms : Int,
) -> Result[@client.HttpResponse, @client.HttpError] {
  let models_path = if has_version_suffix(base_url) {
    base_url + "/models"
  } else {
    base_url + "/v1/models"
  }
  let headers = [("Authorization", "Bearer " + api_key)]
  let get_result = @client.http_get(models_path, headers, timeout_ms)
  match get_result {
    Ok(resp) =>
      if resp.status_code >= 200 && resp.status_code < 300 {
        // /models responded — done.
        Ok(resp)
      } else if resp.status_code == 404 || resp.status_code == 405 {
        // /models missing or method-not-allowed — fall through to
        // /chat/completions probe. Don't return early; that would lose
        // the chance to validate auth and reachability via the real
        // inference path.
        let chat_path = strip_trailing_slash(base_url) + "/chat/completions"
        let body = "{\"model\":\"" +
          model +
          "\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":1,\"stream\":false}"
        let chat_headers = [
          ("Authorization", "Bearer " + api_key),
          ("Content-Type", "application/json"),
        ]
        @client.http_post(chat_path, body, chat_headers, timeout_ms)
      } else {
        // 401/403/4xx/5xx from /models — that's a real signal, no
        // fallback needed.
        Ok(resp)
      }
    Err(e) => Err(e)
  }
}

///|
/// POST /api/config/test
/// Tests connectivity to a model endpoint by sending a lightweight HTTP request.
///
/// Accepts the frontend payload: { model, base_url, api_key, id?, anthropic_format? }
/// - For new (unsaved) models the caller supplies all fields directly.
/// - For existing models the caller may send a masked/empty api_key plus the
///   model `id`; the handler resolves the real api_key (and any missing
///   base_url/model) from the stored config.
///
/// Response shape (matches ModelTester.testConnection expectations):
///   { ok: bool, message: string, effective_base_url?: string }
fn handle_config_test(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  // Extract raw fields from the frontend payload.
  let mut model = extra_json_str(j, "model")
  let mut base_url = extra_json_str(j, "base_url")
  let mut api_key = extra_json_str(j, "api_key")
  let id = extra_json_str_opt(j, "id")
  // Detect masked keys: mask_api_key produces "****" (short) or
  // "xxx...xxxx" (first-3 + "..." + last-4). An empty key also needs
  // resolution when an id is available.
  let key_needs_resolve = api_key.is_empty() ||
    api_key.contains("...") ||
    api_key == "****"
  // When the key is masked/empty and we have a model id, pull the real
  // credentials from the persisted config.
  if key_needs_resolve {
    match id {
      Some(mid) =>
        for m in server_ref.val.config.models {
          if m.id == mid {
            if api_key.is_empty() ||
              api_key.contains("...") ||
              api_key == "****" {
              api_key = m.api_key
            }
            if base_url.is_empty() {
              base_url = m.base_url
            }
            if model.is_empty() {
              model = m.model
            }
            break
          }
        }
      None => ()
    }
  }
  // We need at least base_url and api_key to attempt a connection test.
  // Surface the specific missing field(s) so the user can fix the form
  // without guessing — a bare "required" message is hard to act on.
  if base_url.is_empty() || api_key.is_empty() {
    let missing : Array[String] = []
    if base_url.is_empty() {
      missing.push("base_url")
    }
    if api_key.is_empty() {
      missing.push("api_key")
    }
    let msg = "Missing required field(s): " + missing.join(", ")
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "ok": false.to_json(), "message": msg.to_json() }),
    )
  }
  // Pick test protocol based on anthropic_format. Anthropic-compatible
  // services use a different auth header (x-api-key instead of
  // Authorization: Bearer) and a chat-completions-style endpoint
  // (/v1/messages). Using the OpenAI-shaped /v1/models probe on them
  // yields 404/401, which is misleading.
  let anthropic_format = extra_json_bool(j, "anthropic_format")
  let start = @async.now()
  let result : Result[_, _] = if anthropic_format {
    let url = if has_version_suffix(base_url) {
      strip_trailing_slash(base_url) + "/messages"
    } else {
      base_url + "/v1/messages"
    }
    let headers = [
      ("x-api-key", api_key),
      ("anthropic-version", "2023-06-01"),
      ("Content-Type", "application/json"),
    ]
    // Minimal body — just enough to validate the endpoint & auth without
    // burning tokens. Anthropic returns 400 (bad model) even for valid auth,
    // and 401 specifically for bad/missing keys, so we can still tell them
    // apart.
    let body = "{\"model\":\"" +
      model +
      "\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
    @client.http_post(url, body, headers, 10000)
  } else {
    // OpenAI-compatible probe. The helper tries GET /models first then
    // falls back to POST /chat/completions on 404/405, so a non-standard
    // base URL (e.g. Volces Ark Coding Plan's /api/coding/v3) doesn't
    // surface a misleading "endpoint not found" to the user.
    probe_openai_compatible(base_url, api_key, model, 10000)
  }
  let elapsed = (@async.now() - start).to_int()
  match result {
    Ok(resp) =>
      if resp.status_code >= 200 && resp.status_code < 300 {
        @core.HttpResponse::ok().json_value(
          Json::object({
            "ok": true.to_json(),
            "message": ("Connected (" +
            resp.status_code.to_string() +
            ", " +
            elapsed.to_string() +
            "ms)").to_json(),
            "effective_base_url": base_url.to_json(),
          }),
        )
      } else {
        // Classify by status code so the UI can give a useful message
        // instead of a bare "HTTP 404".
        let (msg, code) : (String, String) = match resp.status_code {
          401 | 403 =>
            (
              "Authentication failed (HTTP " +
              resp.status_code.to_string() +
              "): check API key",
              "auth_failed",
            )
          404 =>
            (
              "Endpoint not found (HTTP 404): probe URL doesn't exist on this provider — try a different base URL",
              "not_found",
            )
          400 =>
            (
              "Bad request (HTTP 400): check model id and provider requirements",
              "bad_request",
            )
          429 => ("Rate limited (HTTP 429)", "rate_limited")
          n if n >= 500 =>
            (
              "Upstream error (HTTP " +
              n.to_string() +
              "): provider unavailable",
              "upstream_error",
            )
          n => ("HTTP " + n.to_string(), "http_" + n.to_string())
        }
        @core.HttpResponse::ok().json_value(
          Json::object({
            "ok": false.to_json(),
            "message": msg.to_json(),
            "error_code": code.to_json(),
            "status_code": resp.status_code.to_json(),
          }),
        )
      }
    Err(e) =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "ok": false.to_json(),
          "message": classify_http_error(e).to_json(),
          "error_code": "network_error".to_json(),
        }),
      )
  }
}

///|
/// Map a low-level HttpError to a human-readable message.
fn classify_http_error(e : @client.HttpError) -> String {
  match e {
    @client.HttpError::Timeout(_) => "Request timed out (10s)"
    @client.HttpError::ConnectionFailed(msg) => "Connection failed: " + msg
    @client.HttpError::ServerError(code, _) =>
      "Server error (HTTP " + code.to_string() + ")"
    @client.HttpError::ClientError(code, _) =>
      "Client error (HTTP " + code.to_string() + ")"
    @client.HttpError::AllHostsFailed(msg) => "All hosts failed: " + msg
  }
}

///|
/// POST /api/config/media/test
/// Tests connectivity to a media model (image/video/audio).
/// Expected body: {"kind": "image" | "video" | "audio"}
fn handle_config_media_test(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let kind = match j {
    Object(obj) =>
      match obj.get("kind") {
        Some(String(k)) => k
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Missing 'kind' field".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let mut model : @config.ModelConfig? = None
  for m in server_ref.val.config.models {
    match m.media_type {
      Some(mt) if mt == kind => {
        model = Some(m)
        break
      }
      _ => ()
    }
  }
  match model {
    Some(mc) => {
      let result = probe_openai_compatible(
        mc.base_url,
        mc.api_key,
        mc.model,
        10000,
      )
      match result {
        Ok(resp) =>
          if resp.status_code >= 200 && resp.status_code < 300 {
            @core.HttpResponse::ok().json_value(
              Json::object({ "ok": true.to_json(), "kind": kind.to_json() }),
            )
          } else {
            @core.HttpResponse::ok().json_value(
              Json::object({
                "ok": false.to_json(),
                "error": ("HTTP " + resp.status_code.to_string()).to_json(),
              }),
            )
          }
        Err(e) =>
          @core.HttpResponse::ok().json_value(
            Json::object({
              "ok": false.to_json(),
              "error": @debug.to_string(e).to_json(),
            }),
          )
      }
    }
    None =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "ok": false.to_json(),
          "error": "No media model configured for kind".to_json(),
          "kind": kind.to_json(),
        }),
      )
  }
}

///|
/// Valid media config kinds (spec web-parity-03/04: five kinds).
fn is_valid_media_kind(kind : String) -> Bool {
  kind == "image" ||
  kind == "video" ||
  kind == "audio" ||
  kind == "stt" ||
  kind == "video_understanding"
}

///|
/// 400 response for an out-of-whitelist media kind.
fn err_invalid_media_kind(kind : String) -> @core.HttpResponse {
  @core.HttpResponse::bad_request().json_value(
    Json::object({
      "ok": false.to_json(),
      "error": ("Unknown media kind: " +
      kind +
      "; use image, video, audio, stt, or video_understanding").to_json(),
    }),
  )
}

///|
/// GET /api/config/media/:kind — Get media configuration for a specific kind.
/// Supported kinds: image, video, audio, stt, video_understanding.
fn handle_config_media_get(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let kind = match event.param("kind") {
    Some(v) => v.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "kind path parameter required".to_json() }),
      )
  }
  if !is_valid_media_kind(kind) {
    return err_invalid_media_kind(kind)
  }
  let config = server_ref.val.config
  // Look for explicit media model.
  match config.find_model_by_type(kind) {
    Some(mc) =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "ok": true.to_json(),
          "kind": kind.to_json(),
          "source": "custom".to_json(),
          "model": mc.model.to_json(),
          "base_url": mc.base_url.to_json(),
        }),
      )
    None =>
      // Try to derive from provider.
      match config.derive_media_model(kind) {
        Some(mc) =>
          @core.HttpResponse::ok().json_value(
            Json::object({
              "ok": true.to_json(),
              "kind": kind.to_json(),
              "source": "auto".to_json(),
              "model": mc.model.to_json(),
              "base_url": mc.base_url.to_json(),
            }),
          )
        None =>
          @core.HttpResponse::ok().json_value(
            Json::object({
              "ok": true.to_json(),
              "kind": kind.to_json(),
              "source": "off".to_json(),
              "model": "".to_json(),
              "base_url": "".to_json(),
            }),
          )
      }
  }
}

///|
/// PATCH /api/config/media/:kind — Update media configuration for a specific kind.
/// Body: {source: "off"|"auto"|"custom", base_url?, api_key?, model?}
fn handle_config_media_patch(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let kind = match event.param("kind") {
    Some(v) => v.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "kind path parameter required".to_json() }),
      )
  }
  if !is_valid_media_kind(kind) {
    return err_invalid_media_kind(kind)
  }
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let source = match j {
    Object(o) =>
      match o.get("source") {
        Some(String(s)) => s
        _ => "auto"
      }
    _ => "auto"
  }
  let config = server_ref.val.config
  match source {
    "off" => {
      // Remove any existing media model for this kind.
      media_remove_model(config, kind)
      match persist_agent_config(config) {
        Ok(_) => ()
        Err(msg) => return err_config_persist(msg)
      }
      @core.HttpResponse::ok().json_value(
        Json::object({
          "ok": true.to_json(),
          "kind": kind.to_json(),
          "source": "off".to_json(),
        }),
      )
    }
    "auto" => {
      media_remove_model(config, kind)
      match config.derive_media_model(kind) {
        Some(mc) => {
          let copy = mc.deep_copy()
          config.models.push(copy)
          match persist_agent_config(config) {
            Ok(_) => ()
            Err(msg) => return err_config_persist(msg)
          }
          @core.HttpResponse::ok().json_value(
            Json::object({
              "ok": true.to_json(),
              "kind": kind.to_json(),
              "source": "auto".to_json(),
              "model": mc.model.to_json(),
            }),
          )
        }
        None => {
          // The removal above still changed the model list — persist it.
          match persist_agent_config(config) {
            Ok(_) => ()
            Err(msg) => return err_config_persist(msg)
          }
          @core.HttpResponse::ok().json_value(
            Json::object({
              "ok": false.to_json(),
              "kind": kind.to_json(),
              "source": "auto".to_json(),
              "error": "Unable to derive media model for kind".to_json(),
            }),
          )
        }
      }
    }
    "custom" => {
      let base_url = media_json_str(j, "base_url")
      let api_key = media_json_str(j, "api_key")
      let model = media_json_str(j, "model")
      if base_url.is_empty() || api_key.is_empty() || model.is_empty() {
        return @core.HttpResponse::bad_request().json_value(
          Json::object({
            "error": "Custom media requires base_url, api_key, and model".to_json(),
          }),
        )
      }
      media_remove_model(config, kind)
      config.models.push({
        id: "media-\{kind}",
        type_: Some(kind),
        api_key,
        base_url,
        model,
        anthropic_format: false,
        runtime_id: "media-\{kind}",
        media_type: Some(kind),
      })
      match persist_agent_config(config) {
        Ok(_) => ()
        Err(msg) => return err_config_persist(msg)
      }
      @core.HttpResponse::ok().json_value(
        Json::object({
          "ok": true.to_json(),
          "kind": kind.to_json(),
          "source": "custom".to_json(),
          "model": model.to_json(),
        }),
      )
    }
    other =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({
          "error": ("Unknown source: " + other + "; use off, auto, or custom").to_json(),
        }),
      )
  }
}

///|
fn media_json_str(j : Json, key : String) -> String {
  match j {
    Object(o) =>
      match o.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
fn media_remove_model(config : @config.AgentConfig, kind : String) -> Unit {
  let kept : Array[@config.ModelConfig] = []
  for m in config.models {
    let is_match = match m.media_type {
      Some(mt) => mt == kind
      _ =>
        match m.type_ {
          Some(t) => t == kind
          _ => false
        }
    }
    if !is_match {
      kept.push(m)
    }
  }
  config.models = kept
}

///|
/// GET /api/config/ocr — Get current OCR configuration.
fn handle_config_ocr_get(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let config = server_ref.val.config
  match config.find_model_by_type("ocr") {
    Some(mc) =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "ok": true.to_json(),
          "source": "custom".to_json(),
          "model": mc.model.to_json(),
          "base_url": mc.base_url.to_json(),
        }),
      )
    None =>
      match config.derive_media_model("ocr") {
        Some(mc) =>
          @core.HttpResponse::ok().json_value(
            Json::object({
              "ok": true.to_json(),
              "source": "auto".to_json(),
              "model": mc.model.to_json(),
              "base_url": mc.base_url.to_json(),
            }),
          )
        None =>
          @core.HttpResponse::ok().json_value(
            Json::object({
              "ok": true.to_json(),
              "source": "off".to_json(),
              "model": "".to_json(),
              "base_url": "".to_json(),
            }),
          )
      }
  }
}

///|
/// GET /api/config/media - Get all media configurations at once.
/// Returns { media: { image: {...}, video: {...}, ... }, default_provider: {...} }
fn handle_config_media_all(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let config = server_ref.val.config
  let media : Map[String, Json] = {}
  for kind in ["image", "video", "audio", "stt", "video_understanding"] {
    let entry = match config.find_model_by_type(kind) {
      Some(mc) =>
        Json::object({
          "source": "custom".to_json(),
          "model": mc.model.to_json(),
          "base_url": mc.base_url.to_json(),
          "configured": true.to_json(),
        })
      None =>
        match config.derive_media_model(kind) {
          Some(mc) =>
            Json::object({
              "source": "auto".to_json(),
              "model": mc.model.to_json(),
              "base_url": mc.base_url.to_json(),
              "configured": false.to_json(),
            })
          None =>
            Json::object({
              "source": "off".to_json(),
              "model": "".to_json(),
              "base_url": "".to_json(),
              "configured": false.to_json(),
            })
        }
    }
    media[kind] = entry
  }
  // default_provider: derive from first model with media_type
  let default_provider : Map[String, Json] = {}
  let mut found_default = false
  for m in config.models {
    match m.media_type {
      Some(mt) => {
        default_provider["model"] = m.model.to_json()
        default_provider["base_url"] = m.base_url.to_json()
        default_provider["kind"] = mt.to_json()
        found_default = true
        break
      }
      _ => ()
    }
  }
  if !found_default {
    default_provider["model"] = "".to_json()
    default_provider["base_url"] = "".to_json()
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "media": Json::object(media),
      "default_provider": Json::object(default_provider),
    }),
  )
}
