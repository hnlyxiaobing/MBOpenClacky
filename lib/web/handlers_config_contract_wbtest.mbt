///| White-box contract tests for the config-domain endpoints aligned with

///| the original Ruby server (spec 2026-07-24_web-ui-fix-11-config-api-contract):

///|   GET   /api/config          — current_id / current_index / media_capabilities

///|   GET   /api/config/media    — per-kind media_state + default_provider

///|   GET   /api/config/ocr      — { ocr, default_provider } nesting

///|   GET/PATCH /api/config/settings — flat AgentConfig-backed switches

///|

///| Key sets are asserted exactly (sorted) so any drift from the orig

///| contract fails loudly. Handlers are invoked directly (no live server).

///|
/// Assert that a JSON object has exactly the given key set (order-free).
fn ccfg_assert_keys(j : Json, expected : Array[String]) -> Unit raise {
  match j {
    Object(o) => {
      let keys : Array[String] = []
      for k, _ in o {
        keys.push(k)
      }
      keys.sort()
      let exp = expected.copy()
      exp.sort()
      assert_true(keys == exp)
    }
    _ => assert_true(false)
  }
}

///|
/// Extract a nested object field, failing the test when absent/not an object.
fn ccfg_obj_field(j : Json, key : String) -> Json raise {
  match j {
    Object(o) =>
      match o.get(key) {
        Some(v) => v
        None => {
          assert_true(false)
          Json::null()
        }
      }
    _ => {
      assert_true(false)
      Json::null()
    }
  }
}

///|
/// Read a boolean field; fails the test when absent/not a boolean.
fn ccfg_bool_field(j : Json, key : String) -> Bool raise {
  match ccfg_obj_field(j, key) {
    True => true
    False => false
    _ => {
      assert_true(false)
      false
    }
  }
}

///|
/// Whether the field exists and is JSON null.
fn ccfg_is_null(j : Json, key : String) -> Bool {
  match j {
    Object(o) =>
      match o.get(key) {
        Some(Null) => true
        _ => false
      }
    _ => false
  }
}

///|
/// Build a bare chat-model entry for tests.
fn ccfg_chat_model(id : String, type_ : String?) -> @config.ModelConfig {
  {
    id,
    type_,
    api_key: "sk-test-1234567890",
    // Unresolvable base_url keeps provider derivation (auto mode) out of
    // the picture: derive_media_model returns None for unknown providers.
    base_url: "https://example.com/v1",
    model: "test-model-" + id,
    anthropic_format: false,
    runtime_id: id,
    media_type: None,
  }
}

// ── GET /api/config/media ────────────────────────────────────────────

///|
/// Orig contract: `{ media, default_provider }` with five media kinds each.
/// Per-kind state mirrors Ruby media_state (10 keys); default_provider has
/// 4 keys (provider / model / available / aliases).
test "config media all: orig contract shape with empty config" {
  let resp = handle_config_media_all(
    ex_make_server_ref(),
    ex_make_event(Get, "/api/config/media"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let body = ex_response_json(resp)
  ccfg_assert_keys(body, ["media", "default_provider"])
  let media = ccfg_obj_field(body, "media")
  let kinds = ["image", "video", "audio", "stt", "video_understanding"]
  ccfg_assert_keys(media, kinds)
  for kind in kinds {
    let entry = ccfg_obj_field(media, kind)
    ccfg_assert_keys(entry, [
      "source", "model", "base_url", "api_key_masked", "provider", "available", "aliases",
      "stale", "requested_model", "configured",
    ])
    // No models configured -> everything off, configured=false, model null
    // (orig emits null, not "", for unconfigured kinds).
    @debug.assert_eq(ex_str_field(entry, "source"), "off")
    @debug.assert_eq(ccfg_bool_field(entry, "configured"), false)
    assert_true(ccfg_is_null(entry, "model"))
    assert_true(ccfg_is_null(entry, "base_url"))
    assert_true(ccfg_is_null(entry, "provider"))
    assert_true(ccfg_is_null(entry, "api_key_masked"))
    @debug.assert_eq(ccfg_bool_field(entry, "stale"), false)
    assert_true(ccfg_is_null(entry, "requested_model"))
  }
  let defaults = ccfg_obj_field(body, "default_provider")
  ccfg_assert_keys(defaults, kinds)
  for kind in kinds {
    let preview = ccfg_obj_field(defaults, kind)
    ccfg_assert_keys(preview, ["provider", "model", "available", "aliases"])
  }
}

///|
/// An explicitly configured media entry is reported as source=custom with
/// a masked api key, mirroring Ruby media_state's custom branch.
test "config media all: explicit entry reports custom state" {
  let sref = ex_make_server_ref()
  let custom = @config.ModelConfig::{
    id: "img-1",
    type_: None,
    api_key: "sk-ant-abc123xyz789",
    base_url: "https://api.anthropic.com",
    model: "claude-image-1",
    anthropic_format: false,
    runtime_id: "img-1",
    media_type: Some("image"),
  }
  sref.val.config.models.push(custom)
  let resp = handle_config_media_all(
    sref,
    ex_make_event(Get, "/api/config/media"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let body = ex_response_json(resp)
  let image = ccfg_obj_field(ccfg_obj_field(body, "media"), "image")
  @debug.assert_eq(ex_str_field(image, "source"), "custom")
  @debug.assert_eq(ex_str_field(image, "model"), "claude-image-1")
  @debug.assert_eq(ccfg_bool_field(image, "configured"), true)
  // api_key_masked mirrors mask_api_key: first 3 + last 4 chars.
  @debug.assert_eq(ex_str_field(image, "api_key_masked"), "sk-...z789")
}

// ── GET /api/config/ocr ──────────────────────────────────────────────

///|
/// Orig contract: `{ ocr, default_provider }` — nested, no top-level `ok`.
/// The ocr state has 10 keys (incl. `primary`); the preview has 3.
test "config ocr get: orig contract shape with empty config" {
  let resp = handle_config_ocr_get(
    ex_make_server_ref(),
    ex_make_event(Get, "/api/config/ocr"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let body = ex_response_json(resp)
  ccfg_assert_keys(body, ["ocr", "default_provider"])
  let ocr = ccfg_obj_field(body, "ocr")
  ccfg_assert_keys(ocr, [
    "source", "model", "base_url", "api_key_masked", "provider", "available", "stale",
    "requested_model", "configured", "primary",
  ])
  @debug.assert_eq(ex_str_field(ocr, "source"), "off")
  @debug.assert_eq(ccfg_bool_field(ocr, "configured"), false)
  @debug.assert_eq(ccfg_bool_field(ocr, "primary"), false)
  assert_true(ccfg_is_null(ocr, "model"))
  let preview = ccfg_obj_field(body, "default_provider")
  ccfg_assert_keys(preview, ["provider", "model", "available"])
}

// ── GET/PATCH /api/config/settings ───────────────────────────────────

///|
/// Orig contract: flat `{ ok, enable_compression, enable_prompt_caching,
/// memory_update_enabled, proxy_url }` read from the live AgentConfig —
/// no nested `settings` object.
test "config settings get: flat orig shape from agent config" {
  let sref = ex_make_server_ref()
  sref.val.config.enable_compression = false
  sref.val.config.proxy_url = "http://127.0.0.1:7890"
  let resp = handle_config_settings_get(
    sref,
    ex_make_event(Get, "/api/config/settings"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let body = ex_response_json(resp)
  ccfg_assert_keys(body, [
    "ok", "enable_compression", "enable_prompt_caching", "memory_update_enabled",
    "proxy_url",
  ])
  @debug.assert_eq(ccfg_bool_field(body, "ok"), true)
  @debug.assert_eq(ccfg_bool_field(body, "enable_compression"), false)
  // Untouched switches keep their AgentConfig defaults.
  @debug.assert_eq(ccfg_bool_field(body, "enable_prompt_caching"), true)
  @debug.assert_eq(ccfg_bool_field(body, "memory_update_enabled"), true)
  @debug.assert_eq(ex_str_field(body, "proxy_url"), "http://127.0.0.1:7890")
}

///|
/// PATCH applies the known switches to the live AgentConfig, persists it,
/// and answers `{ ok: true }` like the Ruby api_update_settings.
test "config settings patch: updates agent config and returns ok" {
  let old = ex_push_profile()
  let sref = ex_make_server_ref()
  let resp = handle_config_settings_patch(
    sref,
    ex_make_event(
      Patch,
      "/api/config/settings",
      body="{\"enable_compression\":false,\"memory_update_enabled\":true,\"proxy_url\":\"http://proxy:8080\"}",
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let body = ex_response_json(resp)
  ccfg_assert_keys(body, ["ok"])
  @debug.assert_eq(ccfg_bool_field(body, "ok"), true)
  // Live config mutated.
  @debug.assert_eq(sref.val.config.enable_compression, false)
  @debug.assert_eq(sref.val.config.memory_update_enabled, true)
  @debug.assert_eq(sref.val.config.proxy_url, "http://proxy:8080")
  // Untouched switch keeps its default.
  @debug.assert_eq(sref.val.config.enable_prompt_caching, true)
  // GET round-trip reflects the patch.
  let get = handle_config_settings_get(
    sref,
    ex_make_event(Get, "/api/config/settings"),
  )
  let get_body = ex_response_json(get)
  @debug.assert_eq(ccfg_bool_field(get_body, "enable_compression"), false)
  @debug.assert_eq(ccfg_bool_field(get_body, "memory_update_enabled"), true)
  @debug.assert_eq(ex_str_field(get_body, "proxy_url"), "http://proxy:8080")
  ex_pop_profile(old)
}

// ── GET /api/config ──────────────────────────────────────────────────

///|
/// Orig contract: models carry their raw-list `index`, media/OCR-managed
/// entries are excluded from the chat-model list, and the response adds
/// `current_id` / `current_index` / `media_capabilities`.
test "config get: current id/index, model index and media_capabilities" {
  let sref = ex_make_server_ref()
  sref.val.config.models.push(ccfg_chat_model("m1", Some("default")))
  sref.val.config.models.push(ccfg_chat_model("m2", None))
  sref.val.config.models.push({
    id: "img-1",
    type_: None,
    api_key: "sk-ant-abc123xyz789",
    base_url: "https://example.com/v1",
    model: "image-model-1",
    anthropic_format: false,
    runtime_id: "img-1",
    media_type: Some("image"),
  })
  sref.val.config.current_model_id = Some("m2")
  let resp = handle_get_config(sref, ex_make_event(Get, "/api/config"))
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let body = ex_response_json(resp)
  // Orig top-level keys present (pre-existing extra keys are kept).
  // p6 id-first semantics (aligned with Ruby agent_config.rb#current_model):
  // current_model_id is authoritative - with a (legacy-style) drifted
  // config where the badge and current_model_id disagree, current_id
  // follows current_model_id.
  assert_true(ccfg_obj_field(body, "current_id") is String(_))
  @debug.assert_eq(ex_str_field(body, "current_id"), "m2")
  match ccfg_obj_field(body, "current_index") {
    Number(n, ..) => @debug.assert_eq(n.to_int(), 1)
    _ => assert_true(false)
  } // Models: media-managed entry excluded; remaining keep raw indexes 0/1.
  let models = ex_arr_field(body, "models")
  @debug.assert_eq(models.length(), 2)
  @debug.assert_eq(ex_str_field(models[0], "id"), "m1")
  @debug.assert_eq(ex_str_field(models[1], "id"), "m2")
  for i, m in models {
    match ccfg_obj_field(m, "index") {
      Number(n, ..) => @debug.assert_eq(n.to_int(), i)
      _ => assert_true(false)
    }
  }
  // media_capabilities: vision + five media kinds.
  let caps = ccfg_obj_field(body, "media_capabilities")
  ccfg_assert_keys(caps, [
    "vision", "image", "video", "audio", "stt", "video_understanding",
  ])
  let vision = ccfg_obj_field(caps, "vision")
  ccfg_assert_keys(vision, ["configured", "primary", "model"])
  @debug.assert_eq(ccfg_bool_field(vision, "configured"), false)
  @debug.assert_eq(ccfg_bool_field(vision, "primary"), false)
  // The explicit image entry surfaces as configured with its model name.
  let image = ccfg_obj_field(caps, "image")
  ccfg_assert_keys(image, ["configured", "model"])
  @debug.assert_eq(ccfg_bool_field(image, "configured"), true)
  @debug.assert_eq(ex_str_field(image, "model"), "image-model-1")
  // Kinds without any entry are unconfigured with null model.
  let video = ccfg_obj_field(caps, "video")
  @debug.assert_eq(ccfg_bool_field(video, "configured"), false)
  assert_true(ccfg_is_null(video, "model"))
}
