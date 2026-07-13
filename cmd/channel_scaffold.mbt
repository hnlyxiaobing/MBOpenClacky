///|
/// Channel scaffold - generates template files for new channel adapters.
/// Supported platforms: feishu, wecom, telegram, discord, dingtalk, weixin.

///|
let supported_platforms : Array[String] = [
  "feishu", "wecom", "telegram", "discord", "dingtalk", "weixin",
]

///|
/// Generate scaffold files for a new channel adapter.
pub fn scaffold_channel(
  platform : String,
  output_dir? : String? = None,
) -> Result[Unit, String] {
  let platform_lower = platform.to_lower()
  if !is_supported_platform(platform_lower) {
    return Err(
      "Unsupported platform: \{platform}. Supported: \{supported_platforms.join(", ")}",
    )
  }
  let base_dir = match output_dir {
    Some(d) => d
    None => "."
  }
  let channel_dir = @path.Path::join(base_dir, @path.Path(platform_lower)).to_string()
  // Create directory
  @fs.create_dir(channel_dir) catch {
    err =>
      return Err(
        "Failed to create directory \{channel_dir}: \{@debug.to_string(err)}",
      )
  }
  // Write adapter.mbt
  let adapter_path = @path.Path::join(channel_dir, @path.Path("adapter.mbt")).to_string()
  @fs.write_string_to_file(adapter_path, gen_adapter_template(platform_lower)) catch {
    err => return Err("Failed to write adapter.mbt: \{@debug.to_string(err)}")
  }
  // Write types.mbt
  let types_path = @path.Path::join(channel_dir, @path.Path("types.mbt")).to_string()
  @fs.write_string_to_file(types_path, gen_types_template(platform_lower)) catch {
    err => return Err("Failed to write types.mbt: \{@debug.to_string(err)}")
  }
  // Write moon.pkg
  let pkg_path = @path.Path::join(channel_dir, @path.Path("moon.pkg")).to_string()
  @fs.write_string_to_file(pkg_path, gen_pkg_template(platform_lower)) catch {
    err => return Err("Failed to write moon.pkg: \{@debug.to_string(err)}")
  }
  println(
    "[ChannelScaffold] Generated channel adapter for '\{platform_lower}' in \{channel_dir}/",
  )
  Ok(())
}

///|
/// List available channel template platforms.
pub fn list_channel_templates() -> Array[String] {
  supported_platforms
}

///|
fn is_supported_platform(platform : String) -> Bool {
  for p in supported_platforms {
    if p == platform {
      return true
    }
  }
  false
}

///|
fn gen_adapter_template(platform : String) -> String {
  "///|\n/// \{platform} channel adapter implementation.\npub(all) struct \{platform}_Adapter {\n  config : \{platform}_Config\n} derive(Debug)\n\n///|\npub fn \{platform}_Adapter::new(config : \{platform}_Config) -> \{platform}_Adapter {\n  { config }\n}\n\n///|\n/// Start the adapter (stub: connect to \{platform} API).\npub fn \{platform}_Adapter::start(self : \{platform}_Adapter) -> Result[Unit, String] {\n  println(\"[\{platform}] Adapter started\")\n  let _ = self\n  Ok(())\n}\n\n///|\n/// Send a message through the adapter (stub).\npub fn \{platform}_Adapter::send_message(\n  self : \{platform}_Adapter,\n  _channel_id : String,\n  _message : String,\n) -> Result[Unit, String] {\n  println(\"[\{platform}] send_message (stub)\")\n  Ok(())\n}\n"
}

///|
fn gen_types_template(platform : String) -> String {
  "///|\n/// Configuration for the \{platform} channel adapter.\npub(all) struct \{platform}_Config {\n  pub app_id : String\n  pub app_secret : String\n  pub webhook_url : String?\n} derive(Debug)\n\n///|\n/// Incoming message from \{platform}.\npub(all) struct \{platform}_Message {\n  pub sender_id : String\n  pub content : String\n  pub timestamp : String\n} derive(Debug)\n"
}

///|
fn gen_pkg_template(_platform : String) -> String {
  "import {\n  \"moonbitlang/core/json\",\n}\n"
}
