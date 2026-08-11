///| White-box contract tests for fix-18 (brand / onboard / version
/// system-info APIs): orig key shapes, license_key non-leakage, onboard gate
/// fields, and the version latest-cache TTL.

///|
fn bw_make_event(
  http_method : @crescent.HttpMethod,
  url : String,
) -> @crescent.Event {
  {
    req: @crescent.HttpRequest::HttpRequest(
      http_method,
      url,
      Map([]),
      raw_body=b"",
    ),
    res: @crescent.HttpResponse::HttpResponse(status_code=OK),
    params: Map([]),
  }
}

///|
fn bw_server_ref(config : @config.AgentConfig) -> Ref[WebServer] {
  Ref(WebServer::new(config, None))
}

///|
fn bw_json(resp : @core.HttpResponse) -> Json {
  @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => Json::object(Map([]))
  }
}

///|
/// Run f with USERPROFILE pointing at an isolated (non-existent) home so
/// brand.toml / onboard.json lookups resolve to defaults; restores the
/// original value afterwards.
async fn bw_with_isolated_home(home : String, f : async () -> Unit) -> Unit {
  let old = @env.get_env_var("USERPROFILE")
  @env.set_env_var("USERPROFILE", home)
  f()
  match old {
    Some(v) => @env.set_env_var("USERPROFILE", v)
    None => @env.set_env_var("USERPROFILE", "")
  }
}

///|
/// Write a brand.toml under the isolated home's config dir.
fn bw_write_brand_toml(home : String, content : String) -> Unit {
  let dir = @path.Path::join(@path.Path(home), @path.Path(".mbopenclacky")).to_string()
  @utils.ensure_dir(dir)
  @fs.write_string_to_file(
    @path.Path::join(@path.Path(dir), @path.Path("brand.toml")).to_string(),
    content,
  ) catch {
    _ => ()
  }
}

///|
fn bw_cleanup_home(home : String) -> Unit {
  @fs.remove_dir(
    @path.Path::join(@path.Path(home), @path.Path(".mbopenclacky")).to_string(),
  ) catch {
    _ => ()
  }
}

// ── GET /api/brand (I-022) ────────────────────────────────────────

///|
async test "fix18 brand config returns orig 13 keys under empty config" {
  bw_with_isolated_home("_build/wbtest18_empty", fn() raise {
    let resp = handle_brand_config(
      bw_server_ref(@config.AgentConfig::default()),
      bw_make_event(Get, "/api/brand"),
    )
    @debug.assert_eq(resp.status_code.to_int(), 200)
    let j = bw_json(resp)
    guard! j is Json::Object(obj)
    let keys = [
      "product_name", "package_name", "logo_url", "support_contact", "support_qr_url",
      "theme_color", "homepage_url", "branded", "activated", "expired", "license_expires_at",
      "user_licensed", "license_user_id",
    ]
    for k in keys {
      assert_true(obj.contains(k))
    }
    // Unset strings serialize as null with the key present (orig to_h shape).
    @debug.assert_eq(obj.get("product_name"), Some(Json::null()))
    @debug.assert_eq(obj.get("license_expires_at"), Some(Json::null()))
    @debug.assert_eq(obj.get("license_user_id"), Some(Json::null()))
    // Derived booleans default to false.
    @debug.assert_eq(obj.get("branded"), Some(false.to_json()))
    @debug.assert_eq(obj.get("activated"), Some(false.to_json()))
    @debug.assert_eq(obj.get("expired"), Some(false.to_json()))
    @debug.assert_eq(obj.get("user_licensed"), Some(false.to_json()))
    // Internal fields are never exposed.
    assert_true(!obj.contains("license_key"))
  })
}

///|
async test "fix18 brand config does not leak license_key and derives booleans" {
  let home = "_build/wbtest18_leak"
  bw_write_brand_toml(
    home,
    (
      #|product_name = "Acme"
      #|package_name = "acme-cli"
      #|theme_color = "#123456"
      #|homepage_url = "https://acme.example"
      #|license_key = "SECRET-KEY-123"
      #|license_expires_at = "2000-01-01T00:00:00Z"
      #|license_user_id = "user-42"
      #|
    ),
  )
  bw_with_isolated_home(home, fn() raise {
    let resp = handle_brand_config(
      bw_server_ref(@config.AgentConfig::default()),
      bw_make_event(Get, "/api/brand"),
    )
    @debug.assert_eq(resp.status_code.to_int(), 200)
    let j = bw_json(resp)
    guard! j is Json::Object(obj)
    @debug.assert_eq(obj.get("product_name"), Some("Acme".to_json()))
    @debug.assert_eq(obj.get("package_name"), Some("acme-cli".to_json()))
    @debug.assert_eq(obj.get("theme_color"), Some("#123456".to_json()))
    @debug.assert_eq(obj.get("branded"), Some(true.to_json()))
    @debug.assert_eq(obj.get("activated"), Some(true.to_json()))
    // Expiry timestamp is in the past → expired.
    @debug.assert_eq(obj.get("expired"), Some(true.to_json()))
    @debug.assert_eq(obj.get("user_licensed"), Some(true.to_json()))
    @debug.assert_eq(
      obj.get("license_expires_at"),
      Some("2000-01-01T00:00:00Z".to_json()),
    )
    @debug.assert_eq(obj.get("license_user_id"), Some("user-42".to_json()))
    // license_key must not appear as a key or anywhere in the body.
    assert_true(!obj.contains("license_key"))
    assert_true(!@utf8.decode(resp.raw_body).contains("SECRET-KEY-123"))
  })
  bw_cleanup_home(home)
}

// ── GET /api/onboard/status (I-023) ───────────────────────────────

///|
async test "fix18 onboard status needs_onboard true without models" {
  bw_with_isolated_home("_build/wbtest18_ob1", fn() raise {
    let resp = handle_onboard_status(
      bw_server_ref(@config.AgentConfig::default()),
      bw_make_event(Get, "/api/onboard/status"),
    )
    @debug.assert_eq(resp.status_code.to_int(), 200)
    let j = bw_json(resp)
    guard! j is Json::Object(obj)
    @debug.assert_eq(obj.get("needs_onboard"), Some(true.to_json()))
    @debug.assert_eq(obj.get("branded"), Some(false.to_json()))
    // web-ui2-10 BUG-018: only needs_onboard + branded.
    assert_true(!obj.contains("phase"))
    assert_true(!obj.contains("completed"))
    assert_true(!obj.contains("step"))
    assert_true(!obj.contains("skipped"))
  })
}

///|
async test "fix18 onboard status needs_onboard false with configured model" {
  let config = @config.AgentConfig::default()
  config.models.push(
    @config.ModelConfig::new("m1", "sk-test", "https://api.test.com", "model-x"),
  )
  bw_with_isolated_home("_build/wbtest18_ob2", fn() raise {
    let resp = handle_onboard_status(
      bw_server_ref(config),
      bw_make_event(Get, "/api/onboard/status"),
    )
    @debug.assert_eq(resp.status_code.to_int(), 200)
    let j = bw_json(resp)
    guard! j is Json::Object(obj)
    @debug.assert_eq(obj.get("needs_onboard"), Some(false.to_json()))
    // phase is only emitted when needs_onboard=true (orig shape).
    assert_true(!obj.contains("phase"))
    assert_true(obj.contains("branded"))
    // web-ui2-10 BUG-018: legacy state keys removed.
    assert_true(!obj.contains("completed"))
    assert_true(!obj.contains("step"))
    assert_true(!obj.contains("skipped"))
  })
}

// ── GET /api/version (I-024) ──────────────────────────────────────

///|
async test "fix18 version info returns orig five keys plus legacy keys" {
  let old_launcher = @env.get_env_var("CLACKY_LAUNCHER")
  @env.set_env_var("CLACKY_LAUNCHER", "")
  bw_with_isolated_home("_build/wbtest18_ver", async fn() {
    // Prime the cache so the handler never touches the network.
    latest_version_cache.val = (Some("9.9.9"), now_seconds())
    let resp = handle_version_info(
      bw_server_ref(@config.AgentConfig::default()),
      bw_make_event(Get, "/api/version"),
    )
    @debug.assert_eq(resp.status_code.to_int(), 200)
    let j = bw_json(resp)
    guard! j is Json::Object(obj)
    @debug.assert_eq(obj.get("current"), Some(VERSION.to_json()))
    @debug.assert_eq(obj.get("latest"), Some("9.9.9".to_json()))
    @debug.assert_eq(obj.get("needs_update"), Some(true.to_json()))
    @debug.assert_eq(obj.get("launcher"), Some("cli".to_json()))
    // Unbranded fallback uses this project's binary name.
    @debug.assert_eq(obj.get("cli_command"), Some("mbopenclacky".to_json()))
    // web-ui2-10 BUG-012: legacy keys removed.
    assert_true(!obj.contains("current_version"))
    assert_true(!obj.contains("version"))
    assert_true(!obj.contains("available_update"))
    assert_true(!obj.contains("changelog"))
  })
  latest_version_cache.val = (None, 0)
  match old_launcher {
    Some(v) => @env.set_env_var("CLACKY_LAUNCHER", v)
    None => @env.set_env_var("CLACKY_LAUNCHER", "")
  }
}

///|
async test "fix18 version info launcher honors CLACKY_LAUNCHER" {
  let old_launcher = @env.get_env_var("CLACKY_LAUNCHER")
  @env.set_env_var("CLACKY_LAUNCHER", "desktop")
  bw_with_isolated_home("_build/wbtest18_ver2", async fn() {
    latest_version_cache.val = (Some("0.1.0"), now_seconds())
    let resp = handle_version_info(
      bw_server_ref(@config.AgentConfig::default()),
      bw_make_event(Get, "/api/version"),
    )
    let j = bw_json(resp)
    guard! j is Json::Object(obj)
    @debug.assert_eq(obj.get("launcher"), Some("desktop".to_json()))
    @debug.assert_eq(obj.get("needs_update"), Some(false.to_json()))
  })
  latest_version_cache.val = (None, 0)
  match old_launcher {
    Some(v) => @env.set_env_var("CLACKY_LAUNCHER", v)
    None => @env.set_env_var("CLACKY_LAUNCHER", "")
  }
}

///|
async test "fix18 version info cli_command uses brand package_name" {
  let home = "_build/wbtest18_ver3"
  bw_write_brand_toml(
    home,
    (
      #|product_name = "Acme"
      #|package_name = "acme-cli"
      #|
    ),
  )
  bw_with_isolated_home(home, async fn() {
    latest_version_cache.val = (None, now_seconds())
    let resp = handle_version_info(
      bw_server_ref(@config.AgentConfig::default()),
      bw_make_event(Get, "/api/version"),
    )
    let j = bw_json(resp)
    guard! j is Json::Object(obj)
    @debug.assert_eq(obj.get("cli_command"), Some("acme-cli".to_json()))
    // web-ui2-10 BUG-012: latest falls back to current (not null).
    @debug.assert_eq(obj.get("latest"), Some(VERSION.to_json()))
    @debug.assert_eq(obj.get("needs_update"), Some(false.to_json()))
  })
  latest_version_cache.val = (None, 0)
  bw_cleanup_home(home)
}

///|
async test "fix18 latest version cache returns cached value within TTL" {
  latest_version_cache.val = (Some("1.2.3"), 1000)
  // One second before expiry → cache hit, no remote fetch, entry untouched.
  let got = fetch_latest_version_cached(1000 + LATEST_VERSION_CACHE_TTL - 1)
  @debug.assert_eq(got, Some("1.2.3"))
  @debug.assert_eq(latest_version_cache.val, (Some("1.2.3"), 1000))
  latest_version_cache.val = (None, 0)
}
