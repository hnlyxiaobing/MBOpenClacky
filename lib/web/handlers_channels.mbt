///| IM Channel management REST API handlers.
/// Provides CRUD operations for channel configurations backed by an in-memory
/// store, with connectivity testing via the channel adapter registry.

// ── Channel Store ─────────────────────────────────────────────────

///|
/// A stored channel configuration entry for the web panel.
pub(all) struct ChannelEntry {
  mut id : String
  mut platform : String
  mut name : String
  mut webhook_url : String
  mut api_key : String
  mut secret : String
  mut enabled : Bool
  mut status : String
  mut created_at : Int64
  mut updated_at : Int64
}

///|
/// In-memory channel configuration store.
let channels_store : Ref[Array[ChannelEntry]] = Ref([])

///|
/// Auto-incrementing counter for generating unique channel IDs.
let channel_id_counter : Ref[Int] = Ref(0)

///|
/// Generate a new unique channel ID.
fn next_channel_id() -> String {
  channel_id_counter.val = channel_id_counter.val + 1
  "ch-\{channel_id_counter.val}"
}

///|
/// Find a channel entry by ID, falling back to platform name.
/// This dual-key lookup allows routes like /:id to accept either a
/// channel ID (e.g. "ch-1") or a platform name (e.g. "telegram").
fn find_channel_index(id_or_platform : String) -> Int? {
  let arr = channels_store.val
  let mut i = 0
  while i < arr.length() {
    if arr[i].id == id_or_platform || arr[i].platform == id_or_platform {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// Convert a ChannelEntry to a JSON object for API responses.
fn channel_entry_to_json(ch : ChannelEntry) -> Json {
  Json::object({
    "id": ch.id.to_json(),
    "platform": ch.platform.to_json(),
    "name": ch.name.to_json(),
    "status": ch.status.to_json(),
    "enabled": ch.enabled.to_json(),
    "config": Json::object({
      "webhook_url": ch.webhook_url.to_json(),
      "api_key": ch.api_key.to_json(),
      "secret": ch.secret.to_json(),
    }),
    "created_at": ch.created_at.to_string().to_json(),
    "updated_at": ch.updated_at.to_string().to_json(),
  })
}

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

// ── Channel Handlers ──────────────────────────────────────────────

///|
/// GET /api/channels — List all configured IM channels.
pub fn handle_channels_list(request : HttpRequest) -> HttpResponse {
  ignore(request)
  let items : Array[Json] = []
  for ch in channels_store.val {
    items.push(channel_entry_to_json(ch))
  }
  let body = Json::array(items).stringify()
  HttpResponse::ok(body)
}

///|
/// POST /api/channels — Create a new IM channel configuration.
/// Expects body: {"platform":"feishu|wecom|telegram|discord|dingtalk|weixin","name":"...","config":{...}}
pub fn handle_channels_create(request : HttpRequest) -> HttpResponse {
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  let body_json : Json = @json.parse(request.body) catch {
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  let (platform, name, webhook_url, api_key, secret) = match body_json {
    Object(obj) => {
      let p = channel_json_str(obj, "platform")
      let n = channel_json_str(obj, "name")
      let (wu, ak, sc) = match channel_json_obj(obj, "config") {
        Some(cfg) =>
          (
            channel_json_str(cfg, "webhook_url"),
            channel_json_str(cfg, "api_key"),
            channel_json_str(cfg, "secret"),
          )
        None => ("", "", "")
      }
      (p, n, wu, ak, sc)
    }
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  if platform == "" {
    return HttpResponse::bad_request("platform is required")
  }
  if name == "" {
    return HttpResponse::bad_request("name is required")
  }
  match normalize_platform(platform) {
    None =>
      return HttpResponse::bad_request(
        "Invalid platform: \{platform}. Supported: feishu, wecom, telegram, discord, dingtalk, weixin",
      )
    Some(_) => ()
  }
  let now = @env.now().reinterpret_as_int64()
  let id = next_channel_id()
  let entry : ChannelEntry = {
    id,
    platform,
    name,
    webhook_url,
    api_key,
    secret,
    enabled: true,
    status: "disconnected",
    created_at: now,
    updated_at: now,
  }
  channels_store.val.push(entry)
  let body = Json::object({
    "id": id.to_json(),
    "status": "created".to_json(),
    "message": "Channel created successfully".to_json(),
  }).stringify()
  HttpResponse::created(body)
}

///|
/// PUT /api/channels/:id — Update an existing channel configuration.
pub fn handle_channels_update(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  match find_channel_index(id) {
    None => HttpResponse::not_found("Channel not found: \{id}")
    Some(idx) => {
      let body_json : Json = @json.parse(request.body) catch {
        _ => return HttpResponse::bad_request("Invalid JSON body")
      }
      match body_json {
        Object(obj) => {
          let arr = channels_store.val
          // Handle enabled field (for PATCH /:id/enabled toggle).
          match obj.get("enabled") {
            Some(True) => arr[idx].enabled = true
            Some(False) => arr[idx].enabled = false
            _ => ()
          }
          let platform = channel_json_str(obj, "platform")
          if platform != "" {
            match normalize_platform(platform) {
              None =>
                return HttpResponse::bad_request(
                  "Invalid platform: \{platform}",
                )
              Some(_) => arr[idx].platform = platform
            }
          }
          let name = channel_json_str(obj, "name")
          if name != "" {
            arr[idx].name = name
          }
          match channel_json_obj(obj, "config") {
            Some(cfg) => {
              arr[idx].webhook_url = channel_json_str(cfg, "webhook_url")
              arr[idx].api_key = channel_json_str(cfg, "api_key")
              arr[idx].secret = channel_json_str(cfg, "secret")
            }
            None => ()
          }
          arr[idx].updated_at = @env.now().reinterpret_as_int64()
        }
        _ => return HttpResponse::bad_request("Invalid JSON body")
      }
      let body = Json::object({
        "id": id.to_json(),
        "status": "updated".to_json(),
        "message": "Channel updated successfully".to_json(),
      }).stringify()
      HttpResponse::ok(body)
    }
  }
}

///|
/// DELETE /api/channels/:id — Delete a channel configuration.
pub fn handle_channels_delete(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  match find_channel_index(id) {
    None => HttpResponse::not_found("Channel not found: \{id}")
    Some(idx) => {
      ignore(channels_store.val.remove(idx))
      HttpResponse::no_content()
    }
  }
}

///|
/// POST /api/channels/:id/test — Test channel connectivity.
/// Builds a temporary adapter from the stored config and validates it.
pub fn handle_channels_test(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  match find_channel_index(id) {
    None => HttpResponse::not_found("Channel not found: \{id}")
    Some(idx) => {
      let arr = channels_store.val
      let ch = arr[idx]
      let start_time = @env.now().reinterpret_as_int64()
      let platform_enum = match ch.platform {
        "feishu" => @channel.Platform::Feishu
        "wecom" => @channel.Platform::WeCom
        "telegram" => @channel.Platform::Telegram
        "discord" => @channel.Platform::Discord
        "dingtalk" => @channel.Platform::DingTalk
        "weixin" => @channel.Platform::Weixin
        _ =>
          return HttpResponse::ok(
            Json::object({
              "channel_id": id.to_json(),
              "test_result": "failed".to_json(),
              "error": "Unknown platform".to_json(),
            }).stringify(),
          )
      }
      let settings : Map[String, String] = Map([])
      if ch.webhook_url != "" {
        settings.set("webhook_url", ch.webhook_url)
      }
      if ch.api_key != "" {
        settings.set("api_key", ch.api_key)
      }
      if ch.secret != "" {
        settings.set("secret", ch.secret)
      }
      let config = @channel.ChannelConfig::{
        platform: platform_enum,
        enabled: ch.enabled,
        settings,
      }
      let (test_result, error_msg) = test_channel_adapter(ch.platform, config)
      let end_time = @env.now().reinterpret_as_int64()
      let latency = (end_time - start_time).to_int()
      // Update channel status based on test result
      if test_result == "success" {
        arr[idx].status = "connected"
      } else {
        arr[idx].status = "error"
      }
      arr[idx].updated_at = end_time
      let resp_obj = Json::object({
        "channel_id": id.to_json(),
        "test_result": test_result.to_json(),
        "latency_ms": latency.to_json(),
        "error": error_msg.to_json(),
      })
      HttpResponse::ok(resp_obj.stringify())
    }
  }
}

///|
/// Extract the error message string from a ChannelError.
fn channel_error_msg(err : @channel.ChannelError) -> String {
  match err {
    @channel.ChannelError(msg) => msg
  }
}

///|
/// Test a channel adapter by constructing it from config and validating.
fn test_channel_adapter(
  platform : String,
  config : @channel.ChannelConfig,
) -> (String, String) {
  match platform {
    "feishu" =>
      match @channel.FeishuAdapter::new(config) {
        Ok(adapter) => {
          let errors = adapter.validate_config()
          if errors.length() == 0 {
            ("success", "")
          } else {
            ("failed", errors.join(", "))
          }
        }
        Err(e) => ("failed", channel_error_msg(e))
      }
    "wecom" =>
      match @channel.WeComAdapter::new(config) {
        Ok(adapter) => {
          let errors = adapter.validate_config()
          if errors.length() == 0 {
            ("success", "")
          } else {
            ("failed", errors.join(", "))
          }
        }
        Err(e) => ("failed", channel_error_msg(e))
      }
    "telegram" =>
      match @channel.TelegramAdapter::new(config) {
        Ok(adapter) => {
          let errors = adapter.validate_config()
          if errors.length() == 0 {
            ("success", "")
          } else {
            ("failed", errors.join(", "))
          }
        }
        Err(e) => ("failed", channel_error_msg(e))
      }
    "discord" =>
      match @channel.DiscordAdapter::new(config) {
        Ok(adapter) => {
          let errors = adapter.validate_config()
          if errors.length() == 0 {
            ("success", "")
          } else {
            ("failed", errors.join(", "))
          }
        }
        Err(e) => ("failed", channel_error_msg(e))
      }
    "dingtalk" =>
      match @channel.DingTalkAdapter::new(config) {
        Ok(adapter) => {
          let errors = adapter.validate_config()
          if errors.length() == 0 {
            ("success", "")
          } else {
            ("failed", errors.join(", "))
          }
        }
        Err(e) => ("failed", channel_error_msg(e))
      }
    "weixin" =>
      match @channel.WeixinAdapter::new(config) {
        Ok(adapter) => {
          let errors = adapter.validate_config()
          if errors.length() == 0 {
            ("success", "")
          } else {
            ("failed", errors.join(", "))
          }
        }
        Err(e) => ("failed", channel_error_msg(e))
      }
    _ => ("failed", "Unknown platform")
  }
}

///|
/// GET /api/channels/:id/status — Get channel connection status.
pub fn handle_channels_status(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  match find_channel_index(id) {
    None => HttpResponse::not_found("Channel not found: \{id}")
    Some(idx) => {
      let ch = channels_store.val[idx]
      let body = Json::object({
        "channel_id": id.to_json(),
        "status": ch.status.to_json(),
        "enabled": ch.enabled.to_json(),
        "platform": ch.platform.to_json(),
        "name": ch.name.to_json(),
        "updated_at": ch.updated_at.to_string().to_json(),
      }).stringify()
      HttpResponse::ok(body)
    }
  }
}

///|
/// POST /api/channels/:id/send — Send a message through the channel.
pub fn handle_channels_send(request : HttpRequest) -> HttpResponse {
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
  match find_channel_index(id) {
    None => HttpResponse::not_found("Channel not found: \{id}")
    Some(idx) => {
      let ch = channels_store.val[idx]
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
      // For now, return success. In a real implementation, we would call the channel adapter.
      HttpResponse::ok(
        Json::object({
          "success": true.to_json(),
          "channel_id": id.to_json(),
          "chat_id": chat_id.to_json(),
          "message": message.to_json(),
        }).stringify(),
      )
    }
  }
}

///|
/// GET /api/channels/group_history/:chat_id — Get group chat history.
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
/// The :id param accepts either a channel ID or a platform name.
pub fn handle_channels_users(request : HttpRequest) -> HttpResponse {
  let id_or_platform = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  match find_channel_index(id_or_platform) {
    None => HttpResponse::not_found("Channel not found: \{id_or_platform}")
    Some(idx) => {
      let ch = channels_store.val[idx]
      // For now, return empty users. In a real implementation, we would query the channel adapter.
      HttpResponse::ok(
        Json::object({
          "platform": ch.platform.to_json(),
          "channel_id": ch.id.to_json(),
          "users": Json::array([]),
        }).stringify(),
      )
    }
  }
}
