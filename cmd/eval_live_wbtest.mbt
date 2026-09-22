///| Tests for the live eval's model resolution (`cmd/eval_live.mbt`).
///
/// This is the path that decides whether `eval --live` runs or reports honestly
/// that nothing is configured, so the precedence and the fallback defaults are
/// pinned here instead of depending on whatever the developer's machine has.
/// The environment is saved and restored around each case.

///|
/// Keys the resolver consults; all of them are cleared before a case runs.
let live_env_keys : Array[String] = [
  "MBOPENCLACKY_API_KEY", "MBOPENCLACKY_BASE_URL", "MBOPENCLACKY_MODEL", "CLACKY_API_KEY",
  "DEEPSEEK_API_KEY", "DEEPSEEK", "DEEPSEEK_BASE_URL", "DEEPSEEK_MODEL", "USERPROFILE",
  "HOME",
]

///|
fn live_env_snapshot() -> Map[String, String] {
  let saved : Map[String, String] = Map([])
  for key in live_env_keys {
    match @env.get_env_var(key) {
      Some(value) => saved[key] = value
      None => ()
    }
  }
  saved
}

///|
fn live_env_clear() -> Unit {
  for key in live_env_keys {
    @env.unset_env_var(key)
  }
}

///|
fn live_env_restore(saved : Map[String, String]) -> Unit {
  live_env_clear()
  for entry in saved {
    @env.set_env_var(entry.0, entry.1)
  }
}

///|
/// Point the home directory at an empty directory so `config.toml` cannot be
/// found (the resolver falls back to env-only in that case).
fn live_env_isolate_home() -> Unit {
  live_env_clear()
  @env.set_env_var("USERPROFILE", "_build/live_resolver_home")
  @env.set_env_var("HOME", "_build/live_resolver_home")
}

///|
/// Write a minimal `config.toml` under a fake home, so precedence can be tested
/// on a machine that also has a real one.
fn live_env_write_config_toml(home : String) -> Unit {
  let dir = @path.Path::join(@path.Path(home), @path.Path(".mbopenclacky")).to_string()
  @utils.ensure_dir(dir)
  let file = @path.Path::join(@path.Path(dir), @path.Path("config.toml")).to_string()
  @fs.write_string_to_file(
    file, "[settings]\npermission_mode = \"confirm_safes\"\n\n[[models]]\ntype = \"default\"\napi_key = \"sk-toml\"\nbase_url = \"https://toml.example.com\"\nmodel = \"toml-model\"\n",
  ) catch {
    _ => ()
  }
}

///|
/// A `config.toml` model is used when no explicit env override is set — and it
/// beats the DeepSeek fallback, because silent surprises about which model a
/// benchmark ran on are worse than requiring an explicit override.
test "live resolver: config.toml beats the DeepSeek fallback" {
  let saved = live_env_snapshot()
  live_env_clear()
  let home = @path.Path::join(
    @utils.current_dir(),
    @path.Path("_build/live_resolver_home_toml"),
  ).to_string()
  live_env_write_config_toml(home)
  @env.set_env_var("USERPROFILE", home)
  @env.set_env_var("HOME", home)
  @env.set_env_var("DEEPSEEK", "sk-deepseek")
  let resolved = match resolve_live_model() {
    Some(found) => found
    None => {
      live_env_restore(saved)
      fail("expected the config.toml model to resolve")
      return
    }
  }
  @debug.assert_eq(resolved.model, "toml-model")
  @debug.assert_eq(resolved.source, "~/.mbopenclacky/config.toml")
  live_env_restore(saved)
}

///|
/// The explicit override must win over `config.toml`: this is what lets a
/// benchmark be pointed at a specific model regardless of what is on disk.
test "live resolver: MBOPENCLACKY_* overrides a config.toml model" {
  let saved = live_env_snapshot()
  live_env_clear()
  let home = @path.Path::join(
    @utils.current_dir(),
    @path.Path("_build/live_resolver_home_toml"),
  ).to_string()
  live_env_write_config_toml(home)
  @env.set_env_var("USERPROFILE", home)
  @env.set_env_var("HOME", home)
  @env.set_env_var("MBOPENCLACKY_API_KEY", "sk-mb")
  @env.set_env_var("MBOPENCLACKY_BASE_URL", "https://api.deepseek.com")
  @env.set_env_var("MBOPENCLACKY_MODEL", "deepseek-flash")
  @env.set_env_var("MBOPENCLACKY_ANTHROPIC_FORMAT", "false")
  let resolved = match resolve_live_model() {
    Some(found) => found
    None => {
      live_env_restore(saved)
      fail("expected the MBOPENCLACKY_* model to resolve")
      return
    }
  }
  @debug.assert_eq(resolved.model, "deepseek-flash")
  @debug.assert_eq(resolved.source, "MBOPENCLACKY_* env")
  live_env_restore(saved)
}

///|
test "live resolver: MBOPENCLACKY_* wins over the DeepSeek fallback" {
  let saved = live_env_snapshot()
  live_env_isolate_home()
  @env.set_env_var("MBOPENCLACKY_API_KEY", "sk-mb")
  @env.set_env_var("MBOPENCLACKY_BASE_URL", "https://mb.example.com")
  @env.set_env_var("MBOPENCLACKY_MODEL", "mb-model")
  @env.set_env_var("DEEPSEEK_API_KEY", "sk-deepseek")
  let resolved = match resolve_live_model() {
    Some(found) => found
    None => {
      live_env_restore(saved)
      fail("expected a resolved model")
      return
    }
  }
  @debug.assert_eq(resolved.source, "MBOPENCLACKY_* env")
  @debug.assert_eq(resolved.model, "mb-model")
  @debug.assert_eq(resolved.base_url, "https://mb.example.com")
  live_env_restore(saved)
}

///|
test "live resolver: the DeepSeek fallback carries verified defaults" {
  let saved = live_env_snapshot()
  live_env_isolate_home()
  @env.set_env_var("DEEPSEEK", "sk-deepseek")
  let resolved = match resolve_live_model() {
    Some(found) => found
    None => {
      live_env_restore(saved)
      fail("expected the DeepSeek fallback to resolve")
      return
    }
  }
  @debug.assert_eq(resolved.source, "DEEPSEEK_* env (fallback)")
  @debug.assert_eq(resolved.model, "deepseek-flash")
  @debug.assert_eq(resolved.base_url, "https://api.deepseek.com")
  live_env_restore(saved)
}

///|
test "live resolver: DEEPSEEK_API_KEY is accepted and overridable" {
  let saved = live_env_snapshot()
  live_env_isolate_home()
  @env.set_env_var("DEEPSEEK_API_KEY", "sk-deepseek")
  @env.set_env_var("DEEPSEEK_BASE_URL", "https://proxy.example.com")
  @env.set_env_var("DEEPSEEK_MODEL", "deepseek-v4-pro")
  let resolved = match resolve_live_model() {
    Some(found) => found
    None => {
      live_env_restore(saved)
      fail("expected a resolved model")
      return
    }
  }
  @debug.assert_eq(resolved.model, "deepseek-v4-pro")
  @debug.assert_eq(resolved.base_url, "https://proxy.example.com")
  live_env_restore(saved)
}

///|
test "live resolver: nothing configured resolves to None (honest, no fake run)" {
  let saved = live_env_snapshot()
  live_env_isolate_home()
  let resolved = resolve_live_model()
  live_env_restore(saved)
  match resolved {
    Some(_) => fail("expected None when nothing is configured")
    None => ()
  }
}
