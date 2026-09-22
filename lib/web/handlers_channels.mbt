///| IM Channel management REST API handlers.
///
/// Channels have exactly one configuration source: the ChannelManager's config
/// file (`~/.mbopenclacky/channels.json`). These handlers project that config
/// for the web panel and write changes back through the manager - there is no
/// web-side store of its own. Credential-valued settings are never serialized;
/// see `masked_settings_json`.
/// (Spec: specs/active/2026-09-22_channel-config-single-source-of-truth.md)

// ── Platform + settings helpers ───────────────────────────────────

///|
/// All supported channel platforms (canonical list, mirrors normalize_platform).
let supported_platforms : Array[String] = [
  "feishu", "wecom", "telegram", "discord", "dingtalk", "weixin",
]

///|
/// Validate a platform string. Returns the canonical name or None.
fn normalize_platform(platform : String) -> String? {
  match platform {
    "feishu" | "wecom" | "telegram" | "discord" | "dingtalk" | "weixin" =>
      Some(platform)
    _ => None
  }
}

///|
/// Extract string field from a JSON object map.
fn channel_json_str(obj : Map[String, Json], key : String) -> String {
  match obj.get(key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
/// Extract a nested JSON object from a parent JSON object map.
fn channel_json_obj(
  obj : Map[String, Json],
  key : String,
) -> Map[String, Json]? {
  match obj.get(key) {
    Some(Object(m)) => Some(m)
    _ => None
  }
}

///|
/// Settings keys whose values must never appear in an API response. Anything
/// ending in `_secret`/`_token` counts too (app_secret, bot_token, ...).
fn is_secret_setting_key(key : String) -> Bool {
  match key {
    "secret"
    | "api_key"
    | "token"
    | "uin"
    | "access_token"
    | "encoding_aes_key"
    | "client_secret" => true
    _ => key.has_suffix("_secret") || key.has_suffix("_token")
  }
}

///|
/// Serialize settings for a response: credential values become `has_<key>`
/// booleans, every other key is passed through.
fn masked_settings_json(settings : Map[String, String]) -> Json {
  let out : Map[String, Json] = Map([])
  for key, value in settings {
    if is_secret_setting_key(key) {
      out.set("has_" + key, true.to_json())
    } else {
      out.set(key, value.to_json())
    }
  }
  Json::object(out)
}

///|
/// Whether the settings carry at least one credential.
fn settings_have_credential(settings : Map[String, String]) -> Bool {
  for key, _value in settings {
    if is_secret_setting_key(key) {
      return true
    }
  }
  false
}

///|
/// `token_updated_at` as a JSON number when the setting holds one, else null.
/// The Weixin QR pairing page compares it against the time it started polling.
fn token_updated_at_json(settings : Map[String, String]) -> Json {
  match settings.get("token_updated_at") {
    None => Json::null()
    Some(raw) => {
      let parsed : Json = @json.parse(raw) catch { _ => return Json::null() }
      match parsed {
        Number(_, ..) => parsed
        _ => Json::null()
      }
    }
  }
}

///|
/// Collect string-valued settings from a JSON object. Non-string values are
/// dropped: adapters read settings as strings.
fn channel_settings_from_json(obj : Map[String, Json]) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  for key, value in obj {
    match value {
      String(s) => out.set(key, s)
      _ => ()
    }
  }
  out
}

///|
/// Read settings from a request object, accepting either `settings` (current)
/// or `config` (the shape this endpoint used to take).
fn channel_settings_field(obj : Map[String, Json]) -> Map[String, String]? {
  match channel_json_obj(obj, "settings") {
    Some(m) => Some(channel_settings_from_json(m))
    None =>
      match channel_json_obj(obj, "config") {
        Some(m) => Some(channel_settings_from_json(m))
        None => None
      }
  }
}

// ── Projection ────────────────────────────────────────────────────

///|
/// Platform-specific parity fields the panel and skill docs expect beyond the
/// real settings (web-ui2-05 contract). Values start as placeholders and are
/// overlaid by the configured settings when a platform has any.
fn platform_extra_fields(platform : String) -> Array[(String, Json)] {
  match platform {
    "feishu" =>
      [
        ("app_id", "".to_json()),
        ("domain", "".to_json()),
        ("allowed_users", Json::array([])),
      ]
    "wecom" => [("bot_id", "".to_json()), ("allowed_users", Json::array([]))]
    "weixin" => [("base_url", "".to_json()), ("allowed_users", Json::array([]))]
    "discord" | "telegram" | "dingtalk" => [("allowed_users", Json::array([]))]
    _ => []
  }
}

///|
/// Project one platform's configuration into the panel's channel shape.
/// `has_config`/`enabled` come from the stored config, `running` from the
/// manager's active set, and credentials are reduced to booleans (never
/// plaintext).
fn channel_status_json(
  mgr : @channel.ChannelManager,
  platform : String,
) -> Json {
  let base : Map[String, Json] = Map([])
  for kv in platform_extra_fields(platform) {
    base.set(kv.0, kv.1)
  }
  match mgr.find_platform(platform) {
    None => {
      base.set("platform", platform.to_json())
      base.set("enabled", false.to_json())
      base.set("running", false.to_json())
      base.set("has_config", false.to_json())
      base.set("has_token", false.to_json())
      base.set("token_updated_at", Json::null())
      base.set("settings", Json::object(Map([])))
      base.set("status", "disconnected".to_json())
      Json::object(base)
    }
    Some(cfg) => {
      let running = cfg.enabled && mgr.active_channels.contains(platform)
      // Real settings overlay the parity placeholders; credentials become flags.
      for key, value in cfg.settings {
        if is_secret_setting_key(key) {
          base.set("has_" + key, true.to_json())
        } else {
          base.set(key, value.to_json())
        }
      }
      base.set("platform", platform.to_json())
      base.set("enabled", cfg.enabled.to_json())
      base.set("running", running.to_json())
      base.set("has_config", true.to_json())
      base.set("has_token", settings_have_credential(cfg.settings).to_json())
      base.set("token_updated_at", token_updated_at_json(cfg.settings))
      base.set("settings", masked_settings_json(cfg.settings))
      base.set(
        "status",
        (if running { "connected" } else { "disconnected" }).to_json(),
      )
      Json::object(base)
    }
  }
}

// ── Config mutation ───────────────────────────────────────────────

///|
/// Apply the persisted config to the running adapters and report the outcome.
///
/// The config file is already written by the time this runs, so a runtime
/// failure is reported as a diagnostic string rather than silently swallowed -
/// callers must not claim the change took effect when it did not.
fn apply_config_after_change(cm_ref : Ref[@channel.ChannelManager]) -> String {
  match cm_ref.val.apply_config() {
    Ok(_) => {
      respawn_channel_gateway(cm_ref)
      "applied"
    }
    Err(e) => {
      let msg = channel_error_msg(e)
      println("[channels] config saved but runtime apply failed: " + msg)
      "saved; runtime apply failed: " + msg
    }
  }
}

///|
/// Re-spawn the Discord gateway loop for the rebuilt adapter set. The previous
/// adapter's stop() ends its loop, so this does not duplicate loops.
fn respawn_channel_gateway(cm_ref : Ref[@channel.ChannelManager]) -> Unit {
  match ws_task_group.val {
    None => ()
    Some(group) => cm_ref.val.spawn_gateways(group)
  }
}

// ── Channel Handlers ──────────────────────────────────────────────

///|
/// GET /api/channels - List all supported IM channel platforms.
/// Returns {channels: [...]} with one item per supported platform, projected
/// from the channel manager's configuration.
pub fn handle_channels_list(
  cm_ref : Ref[@channel.ChannelManager],
) -> HttpResponse {
  let mgr = cm_ref.val
  let items : Array[Json] = []
  for platform in supported_platforms {
    items.push(channel_status_json(mgr, platform))
  }
  HttpResponse::ok(Json::object({ "channels": Json::array(items) }).stringify())
}

///|
/// POST /api/channels - Create or replace an IM channel configuration.
/// Expects body: {"platform":"feishu|...","enabled":true,"settings":{...}}
/// (`config` is accepted as an alias of `settings`).
pub fn handle_channels_create(
  cm_ref : Ref[@channel.ChannelManager],
  request : HttpRequest,
) -> HttpResponse {
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  let body_json : Json = @json.parse(request.body) catch {
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  let (platform, settings, enabled) = match body_json {
    Object(obj) => {
      let p = channel_json_str(obj, "platform")
      let s = match channel_settings_field(obj) {
        Some(m) => m
        None => Map([])
      }
      let e = match obj.get("enabled") {
        Some(False) => false
        _ => true
      }
      (p, s, e)
    }
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  if platform == "" {
    return HttpResponse::bad_request("platform is required")
  }
  match normalize_platform(platform) {
    None =>
      return HttpResponse::bad_request(
        "Invalid platform: \{platform}. Supported: feishu, wecom, telegram, discord, dingtalk, weixin",
      )
    Some(_) => ()
  }
  match cm_ref.val.upsert_platform(platform, enabled, settings) {
    Err(e) => HttpResponse::bad_request(channel_error_msg(e))
    Ok(_) => {
      let note = apply_config_after_change(cm_ref)
      HttpResponse::created(
        Json::object({
          "platform": platform.to_json(),
          "status": "created".to_json(),
          "message": "Channel created successfully".to_json(),
          "runtime": note.to_json(),
        }).stringify(),
      )
    }
  }
}

///|
/// PUT /api/channels/:id - Update an existing channel configuration.
/// Also serves PATCH /api/channels/:id/enabled (the panel's toggle): when only
/// `enabled` is present the existing settings are kept.
pub fn handle_channels_update(
  cm_ref : Ref[@channel.ChannelManager],
  request : HttpRequest,
) -> HttpResponse {
  let platform = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  let existing = match cm_ref.val.find_platform(platform) {
    Some(c) => c
    None => return HttpResponse::not_found("Channel not found: \{platform}")
  }
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  let body_json : Json = @json.parse(request.body) catch {
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  let (enabled, settings) = match body_json {
    Object(obj) => {
      let e = match obj.get("enabled") {
        Some(True) => true
        Some(False) => false
        _ => existing.enabled
      }
      let s = match channel_settings_field(obj) {
        Some(m) => m
        None => existing.settings
      }
      (e, s)
    }
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  match cm_ref.val.upsert_platform(platform, enabled, settings) {
    Err(e) => HttpResponse::bad_request(channel_error_msg(e))
    Ok(_) => {
      let note = apply_config_after_change(cm_ref)
      HttpResponse::ok(
        Json::object({
          "platform": platform.to_json(),
          "status": "updated".to_json(),
          "message": "Channel updated successfully".to_json(),
          "runtime": note.to_json(),
        }).stringify(),
      )
    }
  }
}

///|
/// DELETE /api/channels/:id - Delete a channel configuration.
pub fn handle_channels_delete(
  cm_ref : Ref[@channel.ChannelManager],
  request : HttpRequest,
) -> HttpResponse {
  let platform = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  match cm_ref.val.remove_platform(platform) {
    Err(e) => HttpResponse::not_found(channel_error_msg(e))
    Ok(_) => {
      ignore(apply_config_after_change(cm_ref))
      HttpResponse::no_content()
    }
  }
}

///|
/// GET /api/channels/:id/status - Get a channel's configuration status.
pub fn handle_channels_status(
  cm_ref : Ref[@channel.ChannelManager],
  request : HttpRequest,
) -> HttpResponse {
  let platform = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  HttpResponse::ok(channel_status_json(cm_ref.val, platform).stringify())
}

// ── Connectivity probing ──────────────────────────────────────────

///|
/// POST /api/channels/:id/test - Test channel connectivity (async, real probing).
/// The probe is built from the platform's stored configuration, so it uses the
/// credentials the runtime would actually send with. Every platform is probed
/// with a read-only call against its real API: Feishu and DingTalk request an
/// access token, WeCom requests a corp token, Telegram calls getMe, Discord
/// calls GET /users/@me, and Weixin runs a 1s getupdates round trip.
/// A probe reports "failed" with the platform's own error message when
/// credentials are missing or rejected.
pub async fn handle_channels_test_async(
  cm_ref : Ref[@channel.ChannelManager],
  request : HttpRequest,
) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  let platform = match normalize_platform(id) {
    Some(p) => p
    None =>
      return HttpResponse::bad_request(
        "Unknown platform: \{id}. Supported: feishu, wecom, telegram, discord, dingtalk, weixin",
      )
  }
  let config = match cm_ref.val.find_platform(platform) {
    Some(c) => c
    None =>
      return HttpResponse::ok(
        Json::object({
          "channel_id": platform.to_json(),
          "test_result": "failed".to_json(),
          "error": "Platform is not configured: \{platform}".to_json(),
        }).stringify(),
      )
  }
  let start_time = @env.now().reinterpret_as_int64()
  let (test_result, error_msg) = match platform {
    "feishu" => test_feishu_connectivity(config)
    "discord" => test_discord_connectivity(config)
    "telegram" => test_telegram_connectivity(config)
    "wecom" => test_wecom_connectivity(config)
    "weixin" => test_weixin_connectivity(config)
    "dingtalk" => test_dingtalk_connectivity(config)
    _ => ("failed", "Unknown platform")
  }
  let end_time = @env.now().reinterpret_as_int64()
  let latency = (end_time - start_time).to_int()
  HttpResponse::ok(
    Json::object({
      "channel_id": platform.to_json(),
      "test_result": test_result.to_json(),
      "latency_ms": latency.to_json(),
      "error": error_msg.to_json(),
    }).stringify(),
  )
}

///|
/// Test Feishu connectivity by requesting a tenant_access_token.
/// Uses the real FeishuApiClient::request_token path.
async fn test_feishu_connectivity(
  config : @channel.ChannelConfig,
) -> (String, String) {
  let app_id = match config.settings.get("app_id") {
    Some(v) => v
    None =>
      match config.settings.get("bot_id") {
        Some(v) => v
        None => return ("failed", "Missing app_id/bot_id setting")
      }
  }
  let app_secret = match config.settings.get("app_secret") {
    Some(v) => v
    None =>
      match config.settings.get("bot_secret") {
        Some(v) => v
        None => return ("failed", "Missing app_secret/bot_secret setting")
      }
  }
  let client = @channel.FeishuApiClient::new(app_id, app_secret)
  match client.request_token() {
    Ok(_) => ("success", "")
    Err(e) => ("failed", channel_error_msg(e))
  }
}

///|
/// Test Discord connectivity by calling GET /users/@me.
/// Probes the endpoint directly rather than through
/// DiscordApiClient::get_current_user, which is a registered gap (WP-1.6).
async fn test_discord_connectivity(
  config : @channel.ChannelConfig,
) -> (String, String) {
  let bot_token = match config.settings.get("bot_token") {
    Some(v) => v
    None =>
      match config.settings.get("api_key") {
        Some(v) => v
        None => return ("failed", "Missing bot_token/api_key setting")
      }
  }
  let url = "https://discord.com/api/v10/users/@me"
  let headers = @channel.HttpHeaders::new()
    .bot_token(bot_token)
    .set("User-Agent", "DiscordBot (MBOpenClacky, 1.0)")
    .to_array()
  match @channel.http_get_json(url, headers) {
    Ok(_) => ("success", "")
    Err(e) => ("failed", channel_error_msg(e))
  }
}

///|
/// Test Telegram connectivity by calling the Bot API getMe method.
async fn test_telegram_connectivity(
  config : @channel.ChannelConfig,
) -> (String, String) {
  let bot_token = match config.settings.get("bot_token") {
    Some(v) => v
    None =>
      match config.settings.get("api_key") {
        Some(v) => v
        None => return ("failed", "Missing bot_token/api_key setting")
      }
  }
  let client = @channel.TelegramApiClient::new(bot_token)
  match @channel.http_get_json(client.get_me_url(), client.request_headers()) {
    Ok(_) => ("success", "")
    Err(e) => ("failed", channel_error_msg(e))
  }
}

///|
/// Test WeCom connectivity by requesting a corp access_token.
async fn test_wecom_connectivity(
  config : @channel.ChannelConfig,
) -> (String, String) {
  let corp_id = match config.settings.get("corp_id") {
    Some(v) => v
    None =>
      match config.settings.get("api_key") {
        Some(v) => v
        None => return ("failed", "Missing corp_id/api_key setting")
      }
  }
  let corp_secret = match config.settings.get("secret") {
    Some(v) => v
    None => return ("failed", "Missing secret setting")
  }
  let client = @channel.WeComApiClient::new(corp_id, corp_secret)
  match client.get_access_token() {
    Ok(_) => ("success", "")
    Err(e) => ("failed", channel_error_msg(e))
  }
}

///|
/// Test Weixin connectivity with a short-timeout getupdates round trip.
async fn test_weixin_connectivity(
  config : @channel.ChannelConfig,
) -> (String, String) {
  let token = match config.settings.get("token") {
    Some(v) => v
    None => return ("failed", "Missing token setting")
  }
  let uin = match config.settings.get("uin") {
    Some(v) => v
    None => return ("failed", "Missing uin setting")
  }
  let client = @channel.WeixinApiClient::new(token, uin)
  match client.probe_connectivity() {
    Ok(_) => ("success", "")
    Err(e) => ("failed", channel_error_msg(e))
  }
}

///|
/// Test DingTalk connectivity by requesting a new-API access_token.
async fn test_dingtalk_connectivity(
  config : @channel.ChannelConfig,
) -> (String, String) {
  let app_key = match config.settings.get("app_key") {
    Some(v) => v
    None =>
      match config.settings.get("api_key") {
        Some(v) => v
        None => return ("failed", "Missing app_key/api_key setting")
      }
  }
  let app_secret = match config.settings.get("app_secret") {
    Some(v) => v
    None => return ("failed", "Missing app_secret setting")
  }
  let client = @channel.DingTalkApiClient::new(app_key, app_secret)
  match client.request_access_token() {
    Ok(_) => ("success", "")
    Err(e) => ("failed", channel_error_msg(e))
  }
}

///|
/// Extract the error message string from a ChannelError.
pub fn channel_error_msg(err : @channel.ChannelError) -> String {
  match err {
    @channel.ChannelError(msg) => msg
  }
}

// ── Message dispatch ──────────────────────────────────────────────

///|
/// POST /api/channels/:id/send - Send a message through the channel.
/// Async version that calls ChannelManager::send_to for real adapter dispatch.
pub async fn handle_channels_send_async(
  cm_ref : Ref[@channel.ChannelManager],
  request : HttpRequest,
) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  let body_json : Json = @json.parse(request.body) catch {
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  let platform = match normalize_platform(id) {
    Some(p) => p
    None => return HttpResponse::not_found("Channel not found: \{id}")
  }
  match cm_ref.val.find_platform(platform) {
    None => HttpResponse::not_found("Channel not found: \{platform}")
    Some(ch) => {
      if !ch.enabled {
        return HttpResponse::bad_request("Channel is disabled")
      }
      let (message, chat_id) = match body_json {
        Object(obj) => {
          let m = channel_json_str(obj, "message")
          let c = channel_json_str(obj, "chat_id")
          (m, c)
        }
        _ => return HttpResponse::bad_request("Invalid JSON body")
      }
      if message == "" {
        return HttpResponse::bad_request("Missing message field")
      }
      if chat_id == "" {
        return HttpResponse::bad_request("Missing chat_id field")
      }
      match cm_ref.val.send_to(platform, chat_id, message) {
        Ok(result) =>
          HttpResponse::ok(
            Json::object({
              "success": result.success.to_json(),
              "channel_id": platform.to_json(),
              "chat_id": chat_id.to_json(),
              "message_id": result.message_id.to_json(),
              "error": result.error.to_json(),
            }).stringify(),
          )
        Err(e) =>
          HttpResponse::ok(
            Json::object({
              "success": false.to_json(),
              "channel_id": platform.to_json(),
              "chat_id": chat_id.to_json(),
              "error": channel_error_msg(e).to_json(),
            }).stringify(),
          )
      }
    }
  }
}

// ── Membership / history (unchanged behavior) ─────────────────────

///|
/// GET /api/channels/group_history/:chat_id - Get group chat history.
pub fn handle_channels_group_history(request : HttpRequest) -> HttpResponse {
  let chat_id = match request.get_param("chat_id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: chat_id")
  }
  // For now, return empty history. In a real implementation, we would query the channel adapter.
  HttpResponse::ok(
    Json::object({ "chat_id": chat_id.to_json(), "messages": Json::array([]) }).stringify(),
  )
}

///|
/// GET /api/channels/:id/users - Get users for a channel.
/// The :id param accepts a platform name.
pub fn handle_channels_users(
  cm_ref : Ref[@channel.ChannelManager],
  request : HttpRequest,
) -> HttpResponse {
  let platform = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  match cm_ref.val.find_platform(platform) {
    None => HttpResponse::not_found("Channel not found: \{platform}")
    Some(_ch) =>
      // For now, return empty users. In a real implementation, we would query the channel adapter.
      HttpResponse::ok(
        Json::object({
          "platform": platform.to_json(),
          "users": Json::array([]),
        }).stringify(),
      )
  }
}
