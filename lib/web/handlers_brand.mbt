///| Brand and license management REST API handlers.
/// Provides endpoints for brand configuration, license activation,
/// status checking, and heartbeat.

// ── Helpers ──────────────────────────────────────────────────────

///|
/// Resolve the brand config directory.
/// Fix: [H2] brand_config_dir降级为"."不安全 — 改用home目录下的.mbopenclacky/brand作为fallback
fn brand_config_dir() -> String {
  match @utils.config_dir() {
    Some(d) => d
    None =>
      match @utils.home_dir() {
        Some(home) =>
          @path.Path(home).join(@path.Path(".mbopenclacky/brand")).to_string()
        None => ".mbopenclacky/brand"
      }
  }
}

///|
/// Return the current wall-clock time as an Int (seconds since epoch).
fn now_seconds() -> Int {
  (@async.now() / 1000L).to_int()
}

///|
/// Convert an Option[String] to Json (None → null).
fn opt_str_json(opt : String?) -> Json {
  match opt {
    Some(s) => s.to_json()
    None => Json::null()
  }
}

///|
/// Build a JSON envelope for a LicenseStatus value.
fn license_status_json(status : @brand.LicenseStatus) -> Json {
  let status_str = match status {
    @brand.Valid => "valid"
    @brand.Expired => "expired"
    @brand.GracePeriod => "grace_period"
    @brand.GraceExceeded => "grace_exceeded"
    @brand.Invalid => "invalid"
    @brand.NotConfigured => "not_configured"
  }
  Json::object({
    "status": status_str.to_json(),
    "valid": (status == @brand.Valid).to_json(),
  })
}

// ── Brand Handlers ───────────────────────────────────────────────

///|
/// GET /api/brand/config — Return the current brand configuration.
fn handle_brand_config(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let dir = brand_config_dir()
  let cfg = @brand.BrandConfig::load(dir)
  @core.HttpResponse::ok().json_value(cfg.to_json())
}

///|
/// POST /api/brand/activate — Activate a license key.
/// Expected body: {"license_key": "XXXXXXXX-XXXXXXXX-..."}
fn handle_brand_activate(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let license_key : String = match j {
    Object(obj) =>
      match obj.get("license_key") {
        Some(String(k)) => k
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Missing 'license_key' field".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let dir = brand_config_dir()
  let cfg = @brand.BrandConfig::load(dir)
  let validator = @brand.LicenseValidator::new(cfg)
  let ts = now_seconds()
  match validator.activate(license_key, ts) {
    Ok(_) => {
      let _ = cfg.save(dir)
      @core.HttpResponse::ok().json_value(
        Json::object({
          "activated": true.to_json(),
          "product_name": cfg.display_name().to_json(),
          "expires_at": opt_str_json(cfg.license_expires_at),
        }),
      )
    }
    Err(msg) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": msg.to_json(), "activated": false.to_json() }),
      )
  }
}

///|
/// GET /api/brand/status — Get current license validation status.
fn handle_brand_status(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let dir = brand_config_dir()
  let cfg = @brand.BrandConfig::load(dir)
  let validator = @brand.LicenseValidator::new(cfg)
  let ts = now_seconds()
  let status = validator.validate(ts)
  let activated = cfg.activated()
  let branded = cfg.is_branded()
  @core.HttpResponse::ok().json_value(
    Json::object({
      "activated": activated.to_json(),
      "branded": branded.to_json(),
      "product_name": cfg.display_name().to_json(),
      "license_status": license_status_json(status),
      "expires_at": opt_str_json(cfg.license_expires_at),
      "device_id": opt_str_json(cfg.device_id),
    }),
  )
}

///|
/// GET /api/brand/heartbeat — Trigger a license heartbeat check.
/// Returns success if the heartbeat fires, or the current status if not due.
fn handle_brand_heartbeat(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let dir = brand_config_dir()
  let cfg = @brand.BrandConfig::load(dir)
  let validator = @brand.LicenseValidator::new(cfg)
  let ts = now_seconds()
  if !cfg.activated() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "License not activated".to_json() }),
    )
  }
  if validator.needs_heartbeat(ts) {
    match validator.heartbeat(ts) {
      Ok(_) => {
        let _ = cfg.save(dir)
        @core.HttpResponse::ok().json_value(
          Json::object({
            "heartbeat": "sent".to_json(),
            "last_heartbeat": opt_str_json(cfg.license_last_heartbeat),
          }),
        )
      }
      Err(msg) =>
        @core.HttpResponse::bad_request().json_value(
          Json::object({ "error": msg.to_json() }),
        )
    }
  } else {
    @core.HttpResponse::ok().json_value(
      Json::object({
        "heartbeat": "not_due".to_json(),
        "last_heartbeat": opt_str_json(cfg.license_last_heartbeat),
      }),
    )
  }
}
