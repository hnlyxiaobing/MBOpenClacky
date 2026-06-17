///| Central channel coordinator managing adapter lifecycle and message routing.

///|
/// ChannelManager orchestrates multiple IM channel adapters.
pub(all) struct ChannelManager {
  registry : AdapterRegistry
  mut configs : Array[ChannelConfig]
  mut active_channels : Array[String] // names of running channels
  config_path : String // ~/.mbopenclacky/channels.yml
  mut message_handler : ((ChannelEvent) -> Unit)?
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
  }
}

///|
/// Load channel configurations from channels.yml.
/// TODO: Implement YAML/JSON file reading via FFI.
pub fn ChannelManager::load_config(
  self : ChannelManager,
) -> Result[Unit, ChannelError] {
  // Placeholder: In production this reads from self.config_path
  let _ = self.config_path
  self.configs = []
  Ok(())
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
    Some(adapter) => Ok(adapter.send_text(chat_id, text, None))
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
