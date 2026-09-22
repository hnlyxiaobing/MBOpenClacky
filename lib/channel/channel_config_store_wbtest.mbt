///| Tests for channel config persistence and re-application: path expansion,
/// save/load round-trip, enable/disable/remove write-through, and
/// apply_config rebuilding the adapter registry.

///|
test "expand_config_path: expands leading tilde" {
  let home = test_temp_path("fake_home")
  match expand_config_path("~/.mbopenclacky/channels.json", Some(home)) {
    Ok(p) => {
      assert_false(p.has_prefix("~"))
      assert_true(p.has_suffix("channels.json"))
      assert_true(p.contains("fake_home"))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "expand_config_path: bare tilde becomes home" {
  match expand_config_path("~", Some("/home/u")) {
    Ok(p) => @debug.assert_eq(p, "/home/u")
    Err(_) => assert_true(false)
  }
}

///|
test "expand_config_path: plain path unchanged" {
  match expand_config_path("/tmp/channels.json", Some("/home/u")) {
    Ok(p) => @debug.assert_eq(p, "/tmp/channels.json")
    Err(_) => assert_true(false)
  }
}

///|
test "expand_config_path: unresolvable tilde is an error" {
  match expand_config_path("~/x.json", None) {
    Ok(_) => assert_true(false)
    Err(e) => {
      let msg = match e {
        ChannelError(m) => m
      }
      assert_true(msg.contains("Cannot resolve home directory"))
    }
  }
  match expand_config_path("~/x.json", Some("")) {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}

///|
test "expand_config_path: tilde in middle is untouched" {
  match expand_config_path("/a/~/b.json", Some("/home/u")) {
    Ok(p) => @debug.assert_eq(p, "/a/~/b.json")
    Err(_) => assert_true(false)
  }
}

///|
/// Build a fresh manager over a unique temp config path.
fn test_config_path(name : String) -> String {
  test_temp_path("mbopenclacky_test_channel_cfg_" + name + ".json")
}

///|
test "save_config: round-trips platform, enabled and settings" {
  let path = test_config_path("roundtrip")
  @fs.remove_file(path) catch {
    _ => ()
  }
  let settings : Map[String, String] = Map([])
  settings.set("bot_id", "bot_1")
  settings.set("bot_secret", "sec_1")
  let mgr = ChannelManager::new(path)
  match mgr.upsert_platform("feishu", true, settings) {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  assert_true(@fs.path_exists(path))
  let reloaded = ChannelManager::new(path)
  match reloaded.load_config() {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  @debug.assert_eq(reloaded.configs.length(), 1)
  match reloaded.find_platform("feishu") {
    Some(cfg) => {
      assert_true(cfg.enabled)
      @debug.assert_eq(cfg.settings.get("bot_id"), Some("bot_1"))
      @debug.assert_eq(cfg.settings.get("bot_secret"), Some("sec_1"))
    }
    None => assert_true(false)
  }
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "save_config: creates a missing parent directory" {
  let dir_root = test_temp_path("mbopenclacky_test_channel_cfg_nested")
  let path = @path.Path::join(
    @path.Path(dir_root),
    @path.Path("sub/channels.json"),
  ).to_string()
  let mgr = ChannelManager::new(path)
  let settings : Map[String, String] = Map([])
  settings.set("bot_token", "tok")
  match mgr.upsert_platform("telegram", true, settings) {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  assert_true(@fs.path_exists(path))
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "set_platform_enabled: persists and round-trips" {
  let path = test_config_path("toggle")
  @fs.remove_file(path) catch {
    _ => ()
  }
  let mgr = ChannelManager::new(path)
  let settings : Map[String, String] = Map([])
  settings.set("bot_token", "tok")
  match mgr.upsert_platform("telegram", true, settings) {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  match mgr.set_platform_enabled("telegram", false) {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  let reloaded = ChannelManager::new(path)
  match reloaded.load_config() {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  match reloaded.find_platform("telegram") {
    Some(cfg) => assert_false(cfg.enabled)
    None => assert_true(false)
  }
  // preserving settings across an enable/disable round trip
  @debug.assert_eq(
    reloaded.find_platform("telegram").unwrap().settings.get("bot_token"),
    Some("tok"),
  )
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "set_platform_enabled: unconfigured platform is an error" {
  let path = test_config_path("toggle_missing")
  @fs.remove_file(path) catch {
    _ => ()
  }
  let mgr = ChannelManager::new(path)
  match mgr.set_platform_enabled("discord", true) {
    Ok(_) => assert_true(false)
    Err(e) => {
      let msg = match e {
        ChannelError(m) => m
      }
      assert_true(msg.contains("not configured"))
    }
  }
}

///|
test "upsert_platform: unknown platform is an error" {
  let mgr = ChannelManager::new(test_config_path("unknown"))
  let settings : Map[String, String] = Map([])
  match mgr.upsert_platform("slack", true, settings) {
    Ok(_) => assert_true(false)
    Err(e) => {
      let msg = match e {
        ChannelError(m) => m
      }
      assert_true(msg.contains("Unknown platform"))
    }
  }
}

///|
test "remove_platform: persists and errors when absent" {
  let path = test_config_path("remove")
  @fs.remove_file(path) catch {
    _ => ()
  }
  let mgr = ChannelManager::new(path)
  let settings : Map[String, String] = Map([])
  settings.set("bot_token", "tok")
  match mgr.upsert_platform("telegram", true, settings) {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  match mgr.remove_platform("telegram") {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  let reloaded = ChannelManager::new(path)
  match reloaded.load_config() {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  @debug.assert_eq(reloaded.configs.length(), 0)
  match mgr.remove_platform("telegram") {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "apply_config: rebuilds the registry after a config change" {
  let path = test_config_path("apply")
  @fs.remove_file(path) catch {
    _ => ()
  }
  let mgr = ChannelManager::new(path)
  mgr.on_message(event => ignore(event))
  let settings : Map[String, String] = Map([])
  settings.set("bot_id", "bot_1")
  settings.set("bot_secret", "sec_1")
  match mgr.upsert_platform("feishu", true, settings) {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  match mgr.apply_config() {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  assert_true(mgr.registry.has("feishu"))
  assert_true(mgr.is_platform_configured("feishu"))
  // disabling drops the live adapter rather than leaving it stale
  match mgr.set_platform_enabled("feishu", false) {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  match mgr.apply_config() {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  assert_false(mgr.registry.has("feishu"))
  assert_false(mgr.is_platform_configured("feishu"))
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "weixin adapter: constructs from token + uin alone" {
  // The iLink path needs only token + uin; app_id/app_secret are optional
  // (requiring them made a configured Weixin channel unconstructable).
  let settings : Map[String, String] = Map([])
  settings.set("token", "tok")
  settings.set("uin", "u1")
  let config : ChannelConfig = {
    platform: Platform::Weixin,
    enabled: true,
    settings,
  }
  match WeixinAdapter::new(config) {
    Ok(adapter) => {
      assert_true(adapter.api_client is Some(_))
      @debug.assert_eq(adapter.validate_config().length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "weixin adapter: missing uin reports a diagnostic" {
  let settings : Map[String, String] = Map([])
  settings.set("token", "tok")
  let config : ChannelConfig = {
    platform: Platform::Weixin,
    enabled: true,
    settings,
  }
  match WeixinAdapter::new(config) {
    Ok(adapter) => {
      assert_true(adapter.api_client is None)
      let errors = adapter.validate_config()
      @debug.assert_eq(errors.length(), 1)
      assert_true(errors[0].contains("uin"))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "weixin adapter: missing token is still an error" {
  let settings : Map[String, String] = Map([])
  settings.set("uin", "u1")
  let config : ChannelConfig = {
    platform: Platform::Weixin,
    enabled: true,
    settings,
  }
  match WeixinAdapter::new(config) {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}

///|
test "apply_config: a configured weixin channel registers an adapter" {
  let path = test_config_path("apply_weixin")
  @fs.remove_file(path) catch {
    _ => ()
  }
  let mgr = ChannelManager::new(path)
  mgr.on_message(event => ignore(event))
  let settings : Map[String, String] = Map([])
  settings.set("token", "tok")
  settings.set("uin", "u1")
  match mgr.upsert_platform("weixin", true, settings) {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  match mgr.apply_config() {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  assert_true(mgr.registry.has("weixin"))
  @fs.remove_file(path) catch {
    _ => ()
  }
}
