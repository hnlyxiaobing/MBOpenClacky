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
/// Returns Err on JSON parse failure, invalid entries, or an unresolvable
/// `~` config path.
pub fn ChannelManager::load_config(
  self : ChannelManager,
) -> Result[Unit, ChannelError] {
  let path = match self.resolved_config_path() {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  if !@fs.path_exists(path) {
    self.configs = []
    return Ok(())
  }
  let content = @fs.read_file_to_string(path) catch {
    e => return Err(ChannelError("Failed to read config file: \{Repr(e)}"))
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
        return Err(
          ChannelError("Invalid channel entry in config: \{entry.stringify()}"),
        )
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
  let settings : Map[String, String] = Map([])
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
  Some({ platform, enabled, settings, })
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
/// Spawn connection loops for adapters that have one (the Discord gateway
/// event + heartbeat loop, the Telegram getUpdates long-poll loop, and the
/// WeCom bot WebSocket receive loop) into the given task group.
///
/// A fresh adapter created by `apply_config` has no loop; call this after
/// re-applying configuration. The previous adapter's `stop()` flips its
/// `is_running` to false and ends its loop, so spawning one loop per apply
/// does not duplicate them.
pub fn ChannelManager::spawn_gateways(
  self : ChannelManager,
  group : @async.TaskGroup[Unit],
) -> Unit {
  match self.registry.find("discord") {
    Some(AnyAdapter::Discord(adapter)) => {
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        adapter.run_gateway_loop()
      })
      ()
    }
    _ => ()
  }
  match self.registry.find("telegram") {
    Some(AnyAdapter::Telegram(adapter)) => {
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        adapter.run_long_poll_loop()
      })
      ()
    }
    _ => ()
  }
  match self.registry.find("dingtalk") {
    Some(AnyAdapter::DingTalk(adapter)) => {
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        adapter.run_stream_loop()
      })
      ()
    }
    _ => ()
  }
  match self.registry.find("wecom") {
    Some(AnyAdapter::WeCom(adapter)) => {
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        adapter.run_ws_loop()
      })
      ()
    }
    _ => ()
  }
}

///|
/// Start all enabled channels and spawn long-running connection loops
/// (currently the Discord gateway event + heartbeat loop) into the given
/// task group.
///
/// Call from an async context that owns a TaskGroup (e.g. WebServer::start);
/// start() alone only flips adapters to running state - without the Discord
/// gateway loop no messages would ever arrive.
pub fn ChannelManager::start_with_gateway(
  self : ChannelManager,
  group : @async.TaskGroup[Unit],
) -> Result[Unit, ChannelError] {
  match self.start() {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  self.spawn_gateways(group)
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
pub async fn ChannelManager::send_to(
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
  let result : Map[String, Array[String]] = Map([])
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
/// Initialize the channel manager: load config and create/register adapters
/// for all enabled platforms. On error, returns the error but leaves the
/// manager in a partially-initialized state (server can still start).
pub fn ChannelManager::init(
  self : ChannelManager,
) -> Result[Array[String], ChannelError] {
  match self.load_config() {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let registered : Array[String] = []
  for config in self.configs {
    if config.enabled {
      let name = config.platform.to_string_value()
      match create_adapter_from_config(config) {
        Ok(adapter) => {
          self.register_adapter(name, adapter)
          registered.push(name)
        }
        Err(e) => {
          ignore(e)
          println("[ChannelManager] adapter create failed for \{name}")
        }
      }
    }
  }
  Ok(registered)
}

///|
/// Get the list of configured (enabled) platform names.
pub fn ChannelManager::configured_platforms(
  self : ChannelManager,
) -> Array[String] {
  let result : Array[String] = []
  for config in self.configs {
    if config.enabled {
      result.push(config.platform.to_string_value())
    }
  }
  result
}

///|
/// Check if a given platform is configured and enabled.
pub fn ChannelManager::is_platform_configured(
  self : ChannelManager,
  platform : String,
) -> Bool {
  for config in self.configs {
    if config.enabled && config.platform.to_string_value() == platform {
      return true
    }
  }
  false
}

///|
/// Look up a configured platform by name (enabled or not).
pub fn ChannelManager::find_platform(
  self : ChannelManager,
  platform : String,
) -> ChannelConfig? {
  for config in self.configs {
    if config.platform.to_string_value() == platform {
      return Some(config)
    }
  }
  None
}

///|
/// Expand a leading `~` in a config path using `home`.
///
/// `moonbitlang/x/fs` does not expand `~`, so the default channel config path
/// (`~/.mbopenclacky/channels.json`) silently resolved to a non-existent file
/// and the runtime loaded zero channels. An unresolvable `~` path is reported
/// as an error rather than degrading to an empty config.
pub fn expand_config_path(
  path : String,
  home : String?,
) -> Result[String, ChannelError] {
  let unresolved : Result[String, ChannelError] = Err(
    ChannelError("Cannot resolve home directory for config path: \{path}"),
  )
  if path == "~" {
    match home {
      Some(h) if h != "" => Ok(h)
      _ => unresolved
    }
  } else if path.has_prefix("~/") || path.has_prefix("~\\") {
    match home {
      Some(h) if h != "" =>
        Ok(
          @path.Path::join(@path.Path(h), @path.Path(path[2:].to_owned())).to_string(),
        )
      _ => unresolved
    }
  } else {
    Ok(path)
  }
}

///|
/// This manager's config path with `~` expanded, for file I/O.
fn ChannelManager::resolved_config_path(
  self : ChannelManager,
) -> Result[String, ChannelError] {
  expand_config_path(self.config_path, @utils.home_dir())
}

///|
/// Persist `configs` to the config path in the schema `load_config` parses:
/// `{ "channels": [ {platform, enabled, settings} ] }`.
pub fn ChannelManager::save_config(
  self : ChannelManager,
) -> Result[Unit, ChannelError] {
  let path = match self.resolved_config_path() {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let entries : Array[Json] = []
  for config in self.configs {
    let settings : Map[String, Json] = Map([])
    for key, value in config.settings {
      settings.set(key, value.to_json())
    }
    entries.push(
      Json::object({
        "platform": config.platform.to_string_value().to_json(),
        "enabled": config.enabled.to_json(),
        "settings": Json::object(settings),
      }),
    )
  }
  let content = Json::object({ "channels": Json::array(entries) }).stringify()
  let dir = @path.Path::dirname(@path.Path(path)).to_string()
  if dir != "" && dir != "." && !@fs.path_exists(dir) {
    @utils.ensure_dir(dir)
  }
  @fs.write_string_to_file(path, content) catch {
    e => return Err(ChannelError("Failed to write config file: \{Repr(e)}"))
  }
  Ok(())
}

///|
/// Replace or append a platform config, then persist. `settings` is stored
/// verbatim: adapters read platform-specific credential keys from it.
pub fn ChannelManager::upsert_platform(
  self : ChannelManager,
  platform : String,
  enabled : Bool,
  settings : Map[String, String],
) -> Result[Unit, ChannelError] {
  let parsed = match Platform::from_string(platform) {
    Some(p) => p
    None => return Err(ChannelError("Unknown platform: " + platform))
  }
  let entry : ChannelConfig = { platform: parsed, enabled, settings, }
  let mut replaced = false
  let next : Array[ChannelConfig] = []
  for config in self.configs {
    if config.platform.to_string_value() == platform {
      next.push(entry)
      replaced = true
    } else {
      next.push(config)
    }
  }
  if !replaced {
    next.push(entry)
  }
  self.configs = next
  self.save_config()
}

///|
/// Enable or disable a configured platform, then persist.
pub fn ChannelManager::set_platform_enabled(
  self : ChannelManager,
  platform : String,
  enabled : Bool,
) -> Result[Unit, ChannelError] {
  let mut found = false
  let next : Array[ChannelConfig] = []
  for config in self.configs {
    if config.platform.to_string_value() == platform {
      found = true
      next.push({
        platform: config.platform,
        enabled,
        settings: config.settings,
      })
    } else {
      next.push(config)
    }
  }
  if !found {
    return Err(
      ChannelError(
        "Platform is not configured: " + platform + " (add it first)",
      ),
    )
  }
  self.configs = next
  self.save_config()
}

///|
/// Remove a configured platform, then persist.
pub fn ChannelManager::remove_platform(
  self : ChannelManager,
  platform : String,
) -> Result[Unit, ChannelError] {
  let next : Array[ChannelConfig] = []
  for config in self.configs {
    if config.platform.to_string_value() != platform {
      next.push(config)
    }
  }
  if next.length() == self.configs.length() {
    return Err(ChannelError("Platform is not configured: " + platform))
  }
  self.configs = next
  self.save_config()
}

///|
/// Re-apply configuration from disk: stop running adapters, drop the registry
/// (so disabled/removed platforms lose their adapters), reload, rebuild and
/// start.
///
/// The message handler must already be set (`on_message`) for `start` to work.
/// Long-running connection loops (Discord gateway) are NOT included here -
/// `lib/web` re-spawns them via `start_with_gateway` inside its task group.
pub fn ChannelManager::apply_config(
  self : ChannelManager,
) -> Result[Unit, ChannelError] {
  match self.stop() {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  self.registry.clear()
  match self.init() {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  self.start()
}

///|
/// Create an AnyAdapter from a ChannelConfig by dispatching to the
/// platform-specific adapter constructor.
fn create_adapter_from_config(
  config : ChannelConfig,
) -> Result[AnyAdapter, ChannelError] {
  match config.platform {
    Feishu =>
      match FeishuAdapter::new(config) {
        Ok(a) => Ok(AnyAdapter::Feishu(a))
        Err(e) => Err(e)
      }
    WeCom =>
      match WeComAdapter::new(config) {
        Ok(a) => Ok(AnyAdapter::WeCom(a))
        Err(e) => Err(e)
      }
    Telegram =>
      match TelegramAdapter::new(config) {
        Ok(a) => Ok(AnyAdapter::Telegram(a))
        Err(e) => Err(e)
      }
    Discord =>
      match DiscordAdapter::new(config) {
        Ok(a) => Ok(AnyAdapter::Discord(a))
        Err(e) => Err(e)
      }
    DingTalk =>
      match DingTalkAdapter::new(config) {
        Ok(a) => Ok(AnyAdapter::DingTalk(a))
        Err(e) => Err(e)
      }
    Weixin =>
      match WeixinAdapter::new(config) {
        Ok(a) => Ok(AnyAdapter::Weixin(a))
        Err(e) => Err(e)
      }
  }
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
