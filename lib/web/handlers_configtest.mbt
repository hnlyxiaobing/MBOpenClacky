///| Model connectivity test REST API handlers.

///|
/// POST /api/config/test
/// Tests connectivity to a model endpoint by sending a lightweight HTTP request.
/// Expected body: {"model_id": "model-id"}
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
  let model_id = match j {
    Object(obj) =>
      match obj.get("model_id") {
        Some(String(id)) => id
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Missing 'model_id' field".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let mut model : @config.ModelConfig? = None
  for m in server_ref.val.config.models {
    if m.id == model_id {
      model = Some(m)
      break
    }
  }
  match model {
    Some(mc) => {
      let url = mc.base_url + "/v1/models"
      let headers = [("Authorization", "Bearer " + mc.api_key)]
      let start = @async.now()
      let result = @client.http_get(url, headers, 10000)
      let elapsed = (@async.now() - start).to_int()
      match result {
        Ok(resp) =>
          if resp.status_code >= 200 && resp.status_code < 300 {
            @core.HttpResponse::ok().json_value(
              Json::object({
                "ok": true.to_json(),
                "latency_ms": elapsed.to_json(),
                "status_code": resp.status_code.to_json(),
              }),
            )
          } else {
            @core.HttpResponse::ok().json_value(
              Json::object({
                "ok": false.to_json(),
                "error": ("HTTP " + resp.status_code.to_string()).to_json(),
                "latency_ms": elapsed.to_json(),
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
      @core.HttpResponse::bad_request().json_value(
        Json::object({
          "error": "Model not found".to_json(),
          "model_id": model_id.to_json(),
        }),
      )
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
      let url = mc.base_url + "/v1/models"
      let headers = [("Authorization", "Bearer " + mc.api_key)]
      let result = @client.http_get(url, headers, 10000)
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
