///| Central channel coordinator managing adapter lifecycle and message routing.

///|
/// ChannelManager orchestrates multiple IM channel adapters.
pub(all) struct ChannelManager {
  registry : AdapterRegistry
  mut configs : Array[ChannelConfig]
  mut active_channels : Array[String] // names of running channels
  config_path : String // ~/.mbopenclacky/channels.json
  mut message_handler : ((ChannelEvent) -> Unit)?
  mut recent_digests : Array[(String, Int)] // (digest, sequence) pairs for dedup
  mut digest_counter : Int // monotonically increasing counter for digest ordering
}

///|
/// Create a new ChannelManager with the given config path.
pub fn ChannelManager::new(config_path : String) -> ChannelManager {
  {
    registry: AdapterRegistry::new(),
    configs: [],
    active_channels: [],
    config_path,
    message_handler: None,
    recent_digests: [],
    digest_counter: 0,
  }
}

///|
/// Load channel configurations from the JSON config file at `self.config_path`.
///
/// File format:
/// ```json
/// {
///   "channels": [
///     {
///       "platform": "feishu",
///       "enabled": true,
///       "settings": { "app_id": "...", "app_secret": "..." }
///     }
///   ]
/// }
/// ```
///
/// Returns Ok(()) when the file does not exist (treated as empty config).
/// Returns Err on JSON parse failure or invalid entries.
pub fn ChannelManager::load_config(
  self : ChannelManager,
) -> Result[Unit, ChannelError] {
  if !@fs.path_exists(self.config_path) {
    self.configs = []
    return Ok(())
  }
  let content = @fs.read_file_to_string(self.config_path) catch {
    e => return Err(ChannelError("Failed to read config file: \{e}"))
  }
  let json = @json.parse(content) catch {
    e => return Err(ChannelError("Invalid JSON in config file: \{e}"))
  }
  let root = match json {
    Object(o) => o
    _ => return Err(ChannelError("Config root must be an object"))
  }
  let channels_json = match root.get("channels") {
    Some(Array(arr)) => arr
    Some(_) => return Err(ChannelError("'channels' must be an array"))
    None => []
  }
  let parsed : Array[ChannelConfig] = []
  for entry in channels_json {
    match parse_channel_config_entry(entry) {
      Some(cfg) => parsed.push(cfg)
      None =>
        return Err(ChannelError("Invalid channel entry in config: \{entry}"))
    }
  }
  self.configs = parsed
  Ok(())
}

///|
/// Parse a single channel config entry from JSON.
/// Expected shape: { "platform": "feishu", "enabled": true, "settings": {...} }
fn parse_channel_config_entry(json : Json) -> ChannelConfig? {
  let obj = match json {
    Object(o) => o
    _ => return None
  }
  let platform_str = match obj.get("platform") {
    Some(String(s)) => s
    _ => return None
  }
  let platform = match Platform::from_string(platform_str) {
    Some(p) => p
    None => return None
  }
  let enabled = match obj.get("enabled") {
    Some(True) => true
    _ => false
  }
  let settings : Map[String, String] = {}
  match obj.get("settings") {
    Some(Object(s)) =>
      for k, v in s {
        match v {
          String(str_val) => settings.set(k, str_val)
          _ => ()
        }
      }
    _ => ()
  }
  Some({ platform, enabled, settings })
}

///|
/// Set the message handler callback.
pub fn ChannelManager::on_message(
  self : ChannelManager,
  handler : (ChannelEvent) -> Unit,
) -> Unit {
  self.message_handler = Some(handler)
}

///|
/// Start all enabled channels.
pub fn ChannelManager::start(
  self : ChannelManager,
) -> Result[Unit, ChannelError] {
  let handler = match self.message_handler {
    Some(h) => h
    None =>
      return Err(ChannelError("No message handler set; call on_message first"))
  }
  for config in self.configs {
    if config.enabled {
      let name = config.platform.to_string_value()
      match self.registry.find(name) {
        Some(adapter) =>
          match adapter.start(handler) {
            Ok(_) => self.active_channels.push(name)
            Err(e) => return Err(e)
          }
        None => continue
      }
    }
  }
  Ok(())
}

///|
/// Stop all active channels.
pub fn ChannelManager::stop(
  self : ChannelManager,
) -> Result[Unit, ChannelError] {
  for name in self.active_channels {
    match self.registry.find(name) {
      Some(adapter) =>
        match adapter.stop() {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      None => continue
    }
  }
  self.active_channels = []
  Ok(())
}

///|
/// Reload configuration (stop + reload + start).
pub fn ChannelManager::reload(
  self : ChannelManager,
) -> Result[Unit, ChannelError] {
  match self.stop() {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  match self.load_config() {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  self.start()
}

///|
/// Send a message to a specific channel.
pub fn ChannelManager::send_to(
  self : ChannelManager,
  platform_name : String,
  chat_id : String,
  text : String,
) -> Result[SendResult, ChannelError] {
  match self.registry.find(platform_name) {
    Some(adapter) => adapter.send_text(chat_id, text, None)
    None => Err(ChannelError("Adapter not found: " + platform_name))
  }
}

///|
/// Get status of all channels (name, is_active).
pub fn ChannelManager::status(self : ChannelManager) -> Array[(String, Bool)] {
  let result : Array[(String, Bool)] = []
  let names = self.registry.list_names()
  for name in names {
    let is_active = self.active_channels.contains(name)
    result.push((name, is_active))
  }
  result
}

///|
/// Validate all channel configs.
pub fn ChannelManager::validate_all(
  self : ChannelManager,
) -> Map[String, Array[String]] {
  let result : Map[String, Array[String]] = {}
  for config in self.configs {
    let name = config.platform.to_string_value()
    match self.registry.find(name) {
      Some(adapter) => {
        let errors = adapter.validate_config()
        result.set(name, errors)
      }
      None => result.set(name, ["Adapter not registered"])
    }
  }
  result
}

///|
/// Handle an incoming webhook event from the web server.
/// Routes the event to the appropriate adapter's parse_event method
/// and invokes the message handler callback.
pub fn ChannelManager::handle_webhook(
  self : ChannelManager,
  platform : String,
  body : Json,
) -> Result[Unit, ChannelError] {
  // 1. Check for duplicate (dedup within 2s window)
  let digest = extract_message_digest(platform, body)
  if self.is_duplicate(digest) {
    return Ok(())
  }
  self.record_digest(digest)

  // 2. Route to platform-specific parser and invoke callback
  let event_result = match platform {
    "feishu" => FeishuAdapter::parse_event(body)
    "discord" => DiscordAdapter::parse_event(body)
    "telegram" => TelegramAdapter::parse_event(body)
    "dingtalk" => DingTalkAdapter::parse_event(body)
    "wecom" => WeComAdapter::parse_event(body)
    "weixin" => WeixinAdapter::parse_event(body)
    _ => return Err(ChannelError("Unknown platform: " + platform))
  }
  let event = match event_result {
    Ok(e) => e
    Err(e) => return Err(e)
  }

  match self.message_handler {
    Some(handler) => {
      handler(event)
      Ok(())
    }
    None => Err(ChannelError("No message handler set"))
  }
}

///|
/// Check if a message digest is a recent duplicate.
fn ChannelManager::is_duplicate(self : ChannelManager, digest : String) -> Bool {
  self.recent_digests.iter().any(fn(d) { d.0 == digest })
}

///|
/// Record a new message digest for dedup tracking.
fn ChannelManager::record_digest(
  self : ChannelManager,
  digest : String,
) -> Unit {
  self.digest_counter = self.digest_counter + 1
  // Keep only last 100 entries to prevent unbounded growth
  if self.recent_digests.length() > 100 {
    let new_arr : Array[(String, Int)] = []
    let start = self.recent_digests.length() - 50
    let mut i = start
    while i < self.recent_digests.length() {
      new_arr.push(self.recent_digests[i])
      i = i + 1
    }
    self.recent_digests = new_arr
  }
  self.recent_digests.push((digest, self.digest_counter))
}

///|
/// Register an adapter with the manager.
pub fn ChannelManager::register_adapter(
  self : ChannelManager,
  name : String,
  adapter : AnyAdapter,
) -> Unit {
  self.registry.register(name, adapter)
}

///|
/// Extract a unique message identifier from platform event for dedup.
fn extract_message_digest(platform : String, body : Json) -> String {
  match body {
    Object(obj) => {
      // Try platform-specific message ID fields
      match platform {
        "feishu" =>
          match obj.get("event") {
            Some(Object(ev)) =>
              match ev.get("message") {
                Some(Object(msg)) =>
                  match msg.get("message_id") {
                    Some(String(id)) => return "feishu:" + id
                    _ => ()
                  }
                _ => ()
              }
            _ => ()
          }
        "discord" =>
          match obj.get("d") {
            Some(Object(d)) =>
              match d.get("id") {
                Some(String(id)) => return "discord:" + id
                _ => ()
              }
            _ => ()
          }
        "telegram" =>
          match obj.get("message") {
            Some(Object(msg)) =>
              match msg.get("message_id") {
                Some(Number(n, ..)) =>
                  return "telegram:" + n.to_int().to_string()
                _ => ()
              }
            _ => ()
          }
        "dingtalk" =>
          match obj.get("msgId") {
            Some(String(id)) => return "dingtalk:" + id
            _ => ()
          }
        "wecom" =>
          match obj.get("MsgId") {
            Some(String(id)) => return "wecom:" + id
            _ => ()
          }
        "weixin" =>
          match obj.get("MsgId") {
            Some(String(id)) => return "weixin:" + id
            _ => ()
          }
        _ => ()
      }
      // Fallback: use full body string
      @debug.to_string(body)
    }
    _ => @debug.to_string(body)
  }
}

///|
/// Handle Feishu webhook URL verification challenge.
/// Returns the challenge string if this is a verification request.
pub fn handle_feishu_challenge(body : Json) -> String? {
  match body {
    Object(obj) =>
      match obj.get("type") {
        Some(String(t)) =>
          if t == "url_verification" {
            match obj.get("challenge") {
              Some(String(c)) => Some(c)
              _ => None
            }
          } else {
            None
          }
        _ => None
      }
    _ => None
  }
}
