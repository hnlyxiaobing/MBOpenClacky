///| browser_manager 的运维面（计划 #20，复现用例 20a）。
///
/// 此前 `load_config` 是 TODO（配置永远停在默认值）、`started_at` 恒为 0
/// （uptime 无法计算）、`configure` 不落盘。临时产物一律落 `_build/` 下。

///|
fn bm_tmp_dir(tag : String) -> String {
  let parent = "_build/browser_manager_wbtest"
  if !@fs.path_exists(parent) {
    @fs.create_dir(parent) catch { _ => () }
  }
  let dir = "\{parent}/\{tag}_\{@env.now()}"
  if !@fs.path_exists(dir) {
    @fs.create_dir(dir) catch { _ => () }
  }
  dir
}

///|
fn bm_write(path : String, text : String) -> Unit {
  @fs.write_string_to_file(path, text) catch { _ => () }
}

///|
/// 扁平键布局（本模块写出的形状）被如实读取。
test "browser manager loads a flat browser.yml" {
  let dir = bm_tmp_dir("flat")
  let path = dir + "/browser.yml"
  bm_write(
    path,
    "enabled: true\nchrome_version: \"120.0.6099\"\nmcp_command: custom-mcp\n",
  )
  let mgr = BrowserManager::new(path)
  match mgr.load_config() {
    Err(_) => assert_true(false, msg="load_config failed")
    Ok(_) => ()
  }
  assert_true(mgr.config.enabled, msg="enabled not read")
  @debug.assert_eq(mgr.config.chrome_version, Some("120.0.6099"))
  @debug.assert_eq(mgr.config.mcp_command, "custom-mcp")
}

///|
/// browser-setup 技能写出的是嵌套 `browser: { path: ... }`；该文件只在探测到
/// 浏览器后才写，因此存在非空 path 即视为已启用。
test "browser manager treats a configured browser path as enabled" {
  let dir = bm_tmp_dir("nested")
  let path = dir + "/browser.yml"
  bm_write(
    path,
    "browser:\n  path: \"/usr/bin/google-chrome\"\n  debugging_port: 9222\n",
  )
  let mgr = BrowserManager::new(path)
  match mgr.load_config() {
    Err(_) => assert_true(false, msg="load_config failed")
    Ok(_) => ()
  }
  assert_true(mgr.config.enabled, msg="configured browser path should enable")
}

///|
/// 配置文件不存在是正常的"未设置"状态，不是错误。
test "browser manager keeps defaults when the config file is missing" {
  let dir = bm_tmp_dir("absent")
  let mgr = BrowserManager::new(dir + "/nope.yml")
  match mgr.load_config() {
    Err(_) => assert_true(false, msg="missing file must not error")
    Ok(_) => ()
  }
  assert_false(mgr.config.enabled)
  @debug.assert_eq(mgr.config.chrome_version, None)
}

///|
/// uptime 由真实 started_at 计算（此前 started_at 恒为 0，uptime 恒为 None）。
test "browser manager computes uptime from started_at" {
  let dir = bm_tmp_dir("uptime")
  let mgr = BrowserManager::new(dir + "/browser.yml")
  let now_sec = (@env.now().reinterpret_as_int64() / 1000L).to_int()
  mgr.started_at = Some(now_sec - 30)
  mgr.is_running = true
  let status = mgr.status()
  match status.uptime_seconds {
    Some(s) => assert_true(s >= 29, msg="uptime too small: \{s}")
    None => assert_true(false, msg="uptime was not computed")
  }
}

///|
/// 未运行时没有 uptime（而不是把它报成一个很大的数）。
test "browser manager reports no uptime when not running" {
  let dir = bm_tmp_dir("stopped")
  let mgr = BrowserManager::new(dir + "/browser.yml")
  let now_sec = (@env.now().reinterpret_as_int64() / 1000L).to_int()
  mgr.started_at = Some(now_sec - 30)
  mgr.is_running = false
  @debug.assert_eq(mgr.status().uptime_seconds, None)
}

///|
/// configure 必须落盘，且不回退其它键；重新加载能读到新版本号。
test "browser manager persists the configured chrome version" {
  let dir = bm_tmp_dir("configure")
  let path = dir + "/browser.yml"
  bm_write(path, "enabled: true\nchrome_version: \"120.0.6099\"\n")
  let mgr = BrowserManager::new(path)
  match mgr.configure("121.0.6167") {
    Err(_) => assert_true(false, msg="configure failed")
    Ok(_) => ()
  }
  let reloaded = BrowserManager::new(path)
  match reloaded.load_config() {
    Err(_) => assert_true(false, msg="reload failed")
    Ok(_) => ()
  }
  @debug.assert_eq(reloaded.config.chrome_version, Some("121.0.6167"))
  assert_true(reloaded.config.enabled, msg="unrelated key was dropped")
}