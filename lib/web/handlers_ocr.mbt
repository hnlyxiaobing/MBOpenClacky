///| OCR configuration and internal OCR REST API handlers.

// ── Types ─────────────────────────────────────────────────────────

///|
struct OCRConfigUpdateRequest {
  source : String?
  model : String?
  base_url : String?
  api_key : String?
  anthropic_format : Bool?
} derive(FromJson)

///|
struct OCRConfigResponse {
  ok : Bool
  source : String
  model : String?
  message : String?
} derive(ToJson)

///|
struct OCRTestResponse {
  ok : Bool
  text : String?
  error : String?
} derive(ToJson)

///|
struct OCRImageRequest {
  data_url : String?
  path : String?
  prompt : String?
} derive(FromJson)

// ── Helpers ───────────────────────────────────────────────────────

///|
/// Find the currently configured OCR model, or derive one when source=auto.
fn find_or_derive_ocr_model(
  config : @config.AgentConfig,
) -> @config.ModelConfig? {
  // Explicit OCR model takes precedence.
  match config.find_model_by_type("ocr") {
    Some(m) => Some(m)
    None => config.derive_media_model("ocr")
  }
}

///|
/// Build a VisionResolver from a model config.
fn build_ocr_resolver(model : @config.ModelConfig) -> @vision.VisionResolver {
  let vision_config = @vision.VisionConfig::new(
    model.api_key,
    model.base_url,
    model.model,
  )
  @vision.VisionResolver::with_config(vision_config)
}

///|
/// Remove any existing OCR model from the config.
fn remove_ocr_model(config : @config.AgentConfig) -> Unit {
  let kept : Array[@config.ModelConfig] = []
  for m in config.models {
    let is_ocr = match m.media_type {
      Some("ocr") => true
      _ =>
        match m.type_ {
          Some("ocr") => true
          _ => false
        }
    }
    if !is_ocr {
      kept.push(m)
    }
  }
  config.models = kept
}

///|
/// Upsert an OCR model into the config.
fn upsert_ocr_model(
  config : @config.AgentConfig,
  base_url : String,
  api_key : String,
  model : String,
  anthropic_format : Bool,
) -> Unit {
  remove_ocr_model(config)
  config.models.push({
    id: "ocr-model",
    type_: Some("ocr"),
    api_key,
    base_url,
    model,
    anthropic_format,
    runtime_id: "ocr-model",
    media_type: Some("ocr"),
  })
}

///|
/// Detect the requested OCR source mode from the update request.
fn detect_ocr_source(req : OCRConfigUpdateRequest) -> String {
  match req.source {
    Some(s) => s
    None =>
      if has_value(req.base_url) ||
        has_value(req.api_key) ||
        has_value(req.model) {
        "custom"
      } else {
        "auto"
      }
  }
}

///|
fn has_value(o : String?) -> Bool {
  match o {
    Some(s) => !s.is_empty()
    None => false
  }
}

// ── Handlers ──────────────────────────────────────────────────────

///|
/// PATCH /api/config/ocr
/// Updates the OCR sidecar configuration: off, auto, or custom model.
fn handle_config_ocr_update(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let req : OCRConfigUpdateRequest = match j {
    Object(_) =>
      @json.from_json(j) catch {
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Invalid OCR config request".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let source = detect_ocr_source(req)
  let config = server_ref.val.config
  match source {
    "off" => {
      remove_ocr_model(config)
      @core.HttpResponse::ok().json_value(
        OCRConfigResponse::{
          ok: true,
          source: "off",
          model: None,
          message: None,
        }.to_json(),
      )
    }
    "auto" => {
      remove_ocr_model(config)
      match config.derive_media_model("ocr") {
        Some(model) => {
          let copy = model.deep_copy()
          config.models.push(copy)
          @core.HttpResponse::ok().json_value(
            OCRConfigResponse::{
              ok: true,
              source: "auto",
              model: Some(model.model),
              message: None,
            }.to_json(),
          )
        }
        None =>
          @core.HttpResponse::internal_server_error().json_value(
            OCRConfigResponse::{
              ok: false,
              source: "auto",
              model: None,
              message: Some("Unable to derive OCR model from current provider"),
            }.to_json(),
          )
      }
    }
    "custom" => {
      let base_url = req.base_url.unwrap_or("")
      let api_key = req.api_key.unwrap_or("")
      let model = req.model.unwrap_or("")
      if base_url.is_empty() || api_key.is_empty() || model.is_empty() {
        return @core.HttpResponse::bad_request().json_value(
          OCRConfigResponse::{
            ok: false,
            source: "custom",
            model: None,
            message: Some("Custom OCR requires base_url, api_key, and model"),
          }.to_json(),
        )
      }
      let anthropic_format = req.anthropic_format.unwrap_or(false)
      upsert_ocr_model(config, base_url, api_key, model, anthropic_format)
      @core.HttpResponse::ok().json_value(
        OCRConfigResponse::{
          ok: true,
          source: "custom",
          model: Some(model),
          message: None,
        }.to_json(),
      )
    }
    other =>
      @core.HttpResponse::bad_request().json_value(
        OCRConfigResponse::{
          ok: false,
          source: other,
          model: None,
          message: Some("Unknown source; use off, auto, or custom"),
        }.to_json(),
      )
  }
}

///|
/// POST /api/config/ocr/test
/// Validates the OCR configuration by running a minimal vision call.
fn handle_config_ocr_test(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let config = server_ref.val.config
  match find_or_derive_ocr_model(config) {
    Some(model) => {
      let resolver = build_ocr_resolver(model)
      // 1x1 transparent PNG as a minimal test payload.
      let minimal_image = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
      let result = resolver.describe(
        @vision.VisionInput::DataUrl(minimal_image),
        Some("Extract any text."),
      )
      match result.status {
        @vision.Ok =>
          @core.HttpResponse::ok().json_value(
            OCRTestResponse::{ ok: true, text: result.text, error: None }.to_json(),
          )
        _ =>
          @core.HttpResponse::ok().json_value(
            OCRTestResponse::{ ok: false, text: None, error: result.error }.to_json(),
          )
      }
    }
    None =>
      @core.HttpResponse::internal_server_error().json_value(
        OCRTestResponse::{
          ok: false,
          text: None,
          error: Some("No OCR model configured"),
        }.to_json(),
      )
  }
}

///|
/// POST /api/internal/ocr-image
/// Internal endpoint used by document parsers to OCR an image.
fn handle_internal_ocr_image(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let req : OCRImageRequest = match j {
    Object(_) =>
      @json.from_json(j) catch {
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Invalid OCR image request".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let input = match (req.data_url, req.path) {
    (Some(url), _) if !url.is_empty() => @vision.VisionInput::DataUrl(url)
    (_, Some(path)) if !path.is_empty() => @vision.VisionInput::FilePath(path)
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing data_url or path".to_json() }),
      )
  }
  let config = server_ref.val.config
  match find_or_derive_ocr_model(config) {
    Some(model) => {
      let resolver = build_ocr_resolver(model)
      let result = resolver.describe(input, req.prompt)
      match result.status {
        @vision.Ok =>
          @core.HttpResponse::ok().json_value(
            Json::object({
              "ok": true.to_json(),
              "text": result.text.unwrap_or("").to_json(),
            }),
          )
        _ =>
          @core.HttpResponse::internal_server_error().json_value(
            Json::object({
              "ok": false.to_json(),
              "message": result.error.unwrap_or("OCR failed").to_json(),
            }),
          )
      }
    }
    None =>
      @core.HttpResponse::internal_server_error().json_value(
        Json::object({
          "ok": false.to_json(),
          "message": "No OCR model configured".to_json(),
        }),
      )
  }
}
