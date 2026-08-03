///| White-box tests for the skill publish pipeline (fix-17).
/// The platform HTTP call is mocked via set_multipart_transport_override;
/// every test that installs the override must restore None afterwards.

// ── Helpers ─────────────────────────────────────────────────────────

///|
fn licensed_test_brand() -> @brand.BrandConfig {
  let b = @brand.BrandConfig::default_config()
  b.license_key = Some("wbtest-license-key")
  b.license_user_id = Some("user-42")
  b.device_id = Some("device-xyz")
  b
}

///|
/// Extract a text field value from a (lossily decoded) multipart body.
fn mp_field(text : String, field : String) -> String? {
  let marker = "name=\"" + field + "\"\r\n\r\n"
  match text.find(marker) {
    Some(i) => {
      let start = i + marker.length()
      let rest = text[start:].to_owned()
      match rest.find("\r\n") {
        Some(e) => Some(rest[:e].to_owned())
        None => None
      }
    }
    None => None
  }
}

///|
/// Captured transport call for assertions.
priv struct CapturedCall {
  http_method : String
  url : String
  headers : Array[(String, String)]
  body : Bytes
}

///|
/// Install a mock transport that captures the call and replies with the
/// given result. Returns the capture cell.
fn install_mock_transport(
  result : Result[(Int, String), String],
) -> Ref[CapturedCall?] {
  let captured : Ref[CapturedCall?] = { val: None }
  set_multipart_transport_override(
    Some(fn(
      http_method : String,
      url : String,
      headers : Array[(String, String)],
      body : Bytes,
      _timeout : Int,
    ) -> Result[(Int, String), String] {
      captured.val = Some({ http_method, url, headers, body })
      result
    }),
  )
  captured
}

///|
fn cleanup_dir(dir : String) -> Unit {
  if @fs.path_exists(dir) {
    match remove_dir_recursive(dir) {
      Ok(_) => ()
      Err(_) => ()
    }
  }
}

// ── Multipart body builder ──────────────────────────────────────────

///|
test "multipart body: fields and binary file part in orig order, NUL bytes preserved" {
  let file_data = Bytes::from_array([b'P', b'K', 0, 255])
  let body = build_multipart_body(
    "BOUND",
    [("a", "1"), ("b", "2")],
    "skill_zip",
    "s.zip",
    file_data,
  )
  let expected_head = "--BOUND\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n1\r\n--BOUND\r\nContent-Disposition: form-data; name=\"b\"\r\n\r\n2\r\n--BOUND\r\nContent-Disposition: form-data; name=\"skill_zip\"; filename=\"s.zip\"\r\nContent-Type: application/zip\r\n\r\n"
  let tail = "\r\n--BOUND--\r\n"
  let expected : Array[Byte] = []
  let head_bytes = @utf8.encode(expected_head)
  for i = 0; i < head_bytes.length(); i = i + 1 {
    expected.push(head_bytes[i])
  }
  for i = 0; i < file_data.length(); i = i + 1 {
    expected.push(file_data[i])
  }
  let tail_bytes = @utf8.encode(tail)
  for i = 0; i < tail_bytes.length(); i = i + 1 {
    expected.push(tail_bytes[i])
  }
  @debug.assert_eq(body, Bytes::from_array(expected))
}

// ── ZIP building ────────────────────────────────────────────────────

///|
test "publish exclusions: orig file patterns" {
  assert_true(publish_is_excluded_file("a/b.pyc"))
  assert_true(publish_is_excluded_file("mod.rbc"))
  assert_true(publish_is_excluded_file("C.class"))
  assert_true(publish_is_excluded_file("obj.o"))
  assert_true(publish_is_excluded_file("lib.so"))
  assert_true(publish_is_excluded_file("lib.dylib"))
  assert_true(publish_is_excluded_file("x.dll"))
  assert_true(publish_is_excluded_file("tool.EXE"))
  assert_true(publish_is_excluded_file("sub/.DS_Store"))
  assert_true(publish_is_excluded_file("Thumbs.db"))
  assert_false(publish_is_excluded_file("SKILL.md"))
  assert_false(publish_is_excluded_file("scripts/tool.py"))
  assert_false(publish_is_excluded_file("data.json"))
}

///|
test "build_skill_zip: sorted entries, exclusions, binary round-trip" {
  let base = ".wbtest_pubzip_" + @env.now().to_string()
  let skill_dir = base + "/myskill"
  @utils.ensure_dir(skill_dir + "/sub")
  @utils.ensure_dir(skill_dir + "/__pycache__")
  @utils.ensure_dir(skill_dir + "/.git")
  @utils.ensure_dir(skill_dir + "/node_modules/pkg")
  @fs.write_string_to_file(skill_dir + "/SKILL.md", "---\nname: myskill\n---\n")
  |> ignore
  @fs.write_string_to_file(skill_dir + "/sub/tool.py", "print('hi')\n")
  |> ignore
  @fs.write_string_to_file(skill_dir + "/__pycache__/tool.pyc", "bytecode")
  |> ignore
  @fs.write_string_to_file(skill_dir + "/.git/config", "[core]") |> ignore
  @fs.write_string_to_file(skill_dir + "/node_modules/pkg/index.js", "x")
  |> ignore
  @fs.write_string_to_file(skill_dir + "/.disabled", "") |> ignore
  @fs.write_string_to_file(skill_dir + "/Thumbs.db", "thumbs") |> ignore
  @fs.write_string_to_file(skill_dir + "/obj.o", "obj") |> ignore
  let bin_data = Bytes::from_array([0, 159, 146, 150, 0, 255])
  @fs.write_bytes_to_file(skill_dir + "/bin.dat", bin_data) |> ignore

  let zip_result = build_skill_zip("myskill", skill_dir)
  guard! zip_result is Ok(zip_data)
  let extracted = @zip.extract_zip(zip_data)
  cleanup_dir(base)
  guard! extracted is Ok(entries)
  let names : Array[String] = []
  for e in entries {
    names.push(e.name)
  }
  @debug.assert_eq(names, [
    "myskill/SKILL.md", "myskill/bin.dat", "myskill/sub/tool.py",
  ])
  // Binary content must round-trip byte-for-byte through the ZIP.
  for e in entries {
    if e.name == "myskill/bin.dat" {
      @debug.assert_eq(e.data, bin_data)
    }
  }
}

// ── upload_meta store (lib/brand) ───────────────────────────────────

///|
test "upload_meta: missing file loads empty map" {
  assert_true(@brand.load_upload_meta(".wbtest-no-such-dir-xyz").is_empty())
}

///|
test "upload_meta: record_upload then load round trip in orig file shape" {
  let dir = ".wbtest_pubmeta_" + @env.now().to_string()
  @utils.ensure_dir(dir)
  @brand.record_upload(dir, "skill-a", "1.2.0", 1712345678)
  let meta = @brand.load_upload_meta(dir)
  let raw = @fs.read_file_to_string(@brand.upload_meta_path(dir)) catch {
    _ => panic()
  }
  cleanup_dir(dir)
  guard! meta.get("skill-a") is Some(m)
  @debug.assert_eq(m.platform_version, "1.2.0")
  @debug.assert_eq(m.uploaded_at, @brand.format_iso8601(1712345678))
  // On-disk shape matches orig: {name: {platform_version, uploaded_at}}.
  let j : Json = @json.parse(raw) catch { _ => panic() }
  guard! j is Object(root)
  guard! root.get("skill-a") is Some(Object(entry))
  @debug.assert_eq(entry.get("platform_version"), Some("1.2.0".to_json()))
  assert_true(entry.get("uploaded_at") is Some(String(_)))
}

// ── upload_skill_zip (mocked platform) ──────────────────────────────

///|
async test "upload: success sends HMAC-signed multipart POST to orig path" {
  let captured = install_mock_transport(
    Ok((200, "{\"skill\":{\"version\":\"1.2.0\"}}")),
  )
  let outcome = upload_skill_zip(
    licensed_test_brand(),
    "demo",
    Bytes::from_array([b'P', b'K', b'f', b'a', b'k', b'e']),
    false,
  )
  set_multipart_transport_override(None)
  assert_true(outcome.success)
  @debug.assert_eq(outcome.platform_version, Some("1.2.0"))
  guard! captured.val is Some(call)
  @debug.assert_eq(call.http_method, "POST")
  assert_true(call.url.has_suffix("/api/v1/client/skills"))
  // Content-Type boundary must match the body framing.
  let mut boundary = ""
  for pair in call.headers {
    if pair.0 == "Content-Type" {
      boundary = pair.1.replace(old="multipart/form-data; boundary=", new="")
    }
  }
  assert_true(boundary.has_prefix("----ClackySkillUpload"))
  let text = @utf8.decode_lossy(call.body)
  assert_true(text.has_prefix("--" + boundary + "\r\n"))
  assert_true(text.has_suffix("\r\n--" + boundary + "--\r\n"))
  // All orig fields present, in order.
  @debug.assert_eq(
    mp_field(text, "key_hash"),
    Some(@brand.sha256_hex("wbtest-license-key")),
  )
  @debug.assert_eq(mp_field(text, "user_id"), Some("user-42"))
  @debug.assert_eq(mp_field(text, "device_id"), Some("device-xyz"))
  @debug.assert_eq(mp_field(text, "name"), Some("demo"))
  guard! mp_field(text, "timestamp") is Some(ts)
  guard! mp_field(text, "nonce") is Some(nonce)
  guard! mp_field(text, "signature") is Some(sig)
  // Signature must be HMAC-SHA256(license_key, "user_id:device_id:ts:nonce").
  @debug.assert_eq(
    sig,
    @brand.hmac_sha256(
      "wbtest-license-key",
      "user-42:device-xyz:" + ts + ":" + nonce,
    ),
  )
  // The license key itself must never appear in the body.
  assert_false(text.contains("wbtest-license-key"))
  // File part present.
  assert_true(text.contains("name=\"skill_zip\"; filename=\"demo.zip\""))
  assert_true(text.contains("PKfake"))
}

///|
async test "upload: force=true switches to PATCH on the :name path" {
  let captured = install_mock_transport(
    Ok((200, "{\"skill\":{\"version\":\"2.0.0\"}}")),
  )
  let outcome = upload_skill_zip(
    licensed_test_brand(),
    "demo",
    Bytes::from_array([b'Z']),
    true,
  )
  set_multipart_transport_override(None)
  assert_true(outcome.success)
  guard! captured.val is Some(call)
  @debug.assert_eq(call.http_method, "PATCH")
  assert_true(call.url.has_suffix("/api/v1/client/skills/demo"))
}

///|
async test "upload: HTTP 409 name_taken maps to already_exists" {
  let _ = install_mock_transport(
    Ok(
      (
        409, "{\"code\":\"name_taken\",\"errors\":[\"Name has already been taken\"]}",
      ),
    ),
  )
  let outcome = upload_skill_zip(
    licensed_test_brand(),
    "demo",
    Bytes::from_array([b'Z']),
    false,
  )
  set_multipart_transport_override(None)
  assert_false(outcome.success)
  assert_true(outcome.already_exists)
  assert_true(outcome.error.contains("name_taken"))
  assert_true(outcome.error.contains("Name has already been taken"))
}

///|
async test "upload: generic HTTP error composes orig message and is not already_exists" {
  let _ = install_mock_transport(Ok((500, "{\"error\":\"internal\"}")))
  let outcome = upload_skill_zip(
    licensed_test_brand(),
    "demo",
    Bytes::from_array([b'Z']),
    false,
  )
  set_multipart_transport_override(None)
  assert_false(outcome.success)
  assert_false(outcome.already_exists)
  @debug.assert_eq(outcome.error, "internal")
}

///|
async test "upload: transport failure surfaces as Network error" {
  let _ = install_mock_transport(Err("connection refused"))
  let outcome = upload_skill_zip(
    licensed_test_brand(),
    "demo",
    Bytes::from_array([b'Z']),
    false,
  )
  set_multipart_transport_override(None)
  assert_false(outcome.success)
  assert_true(outcome.error.contains("Network error"))
  assert_true(outcome.error.contains("connection refused"))
}

///|
async test "upload: license guards mirror orig" {
  let not_activated = @brand.BrandConfig::default_config()
  let o1 = upload_skill_zip(
    not_activated,
    "demo",
    Bytes::from_array([b'Z']),
    false,
  )
  assert_false(o1.success)
  @debug.assert_eq(o1.error, "License not activated")
  let activated_not_user = @brand.BrandConfig::default_config()
  activated_not_user.license_key = Some("k")
  let o2 = upload_skill_zip(
    activated_not_user,
    "demo",
    Bytes::from_array([b'Z']),
    false,
  )
  assert_false(o2.success)
  @debug.assert_eq(o2.error, "User license required to upload skills")
}

// ── publish_skill five-step flow ────────────────────────────────────

///|
async test "publish: step 1 unlicensed returns 403 in orig shape" {
  let resp = publish_skill(
    "demo",
    false,
    @brand.BrandConfig::default_config(),
    ".wbtest-none-u",
    ".wbtest-none-b",
  )
  @debug.assert_eq(resp.status, 403)
  let j : Json = @json.parse(resp.body) catch { _ => panic() }
  guard! j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
  @debug.assert_eq(
    obj.get("error"),
    Some("User license required to publish skills".to_json()),
  )
}

///|
async test "publish: step 2 unknown skill returns 404 in orig shape" {
  let base = ".wbtest_pub404_" + @env.now().to_string()
  @utils.ensure_dir(base + "/user")
  @utils.ensure_dir(base + "/builtin")
  let resp = publish_skill(
    "demo",
    false,
    licensed_test_brand(),
    base + "/user",
    base + "/builtin",
  )
  cleanup_dir(base)
  @debug.assert_eq(resp.status, 404)
  let j : Json = @json.parse(resp.body) catch { _ => panic() }
  guard! j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
  @debug.assert_eq(obj.get("error"), Some("Skill 'demo' not found".to_json()))
}

///|
async test "publish: step 3 builtin skill returns 422 in orig shape" {
  let base = ".wbtest_pub422_" + @env.now().to_string()
  @utils.ensure_dir(base + "/user")
  @utils.ensure_dir(base + "/builtin/demo")
  @fs.write_string_to_file(
    base + "/builtin/demo/SKILL.md",
    "---\nname: demo\n---\n",
  )
  |> ignore
  let resp = publish_skill(
    "demo",
    false,
    licensed_test_brand(),
    base + "/user",
    base + "/builtin",
  )
  cleanup_dir(base)
  @debug.assert_eq(resp.status, 422)
  let j : Json = @json.parse(resp.body) catch { _ => panic() }
  guard! j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
  @debug.assert_eq(
    obj.get("error"),
    Some("Built-in system skills cannot be published".to_json()),
  )
}

///|
async test "publish: success returns {ok,name,platform_version} and records upload_meta" {
  let base = ".wbtest_pubok_" + @env.now().to_string()
  let user_dir = base + "/user"
  @utils.ensure_dir(user_dir + "/demo")
  @fs.write_string_to_file(
    user_dir + "/demo/SKILL.md",
    "---\nname: demo\ndescription: d\n---\n",
  )
  |> ignore
  let _ = install_mock_transport(
    Ok((200, "{\"skill\":{\"version\":\"9.9.9\"}}")),
  )
  let resp = publish_skill(
    "demo",
    false,
    licensed_test_brand(),
    user_dir,
    base + "/builtin",
  )
  set_multipart_transport_override(None)
  let meta = @brand.load_upload_meta(user_dir)
  cleanup_dir(base)
  @debug.assert_eq(resp.status, 200)
  let j : Json = @json.parse(resp.body) catch { _ => panic() }
  guard! j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  @debug.assert_eq(obj.get("name"), Some("demo".to_json()))
  @debug.assert_eq(obj.get("platform_version"), Some("9.9.9".to_json()))
  // Step 5 side effect: platform version persisted for creator/skills.
  guard! meta.get("demo") is Some(m)
  @debug.assert_eq(m.platform_version, "9.9.9")
  assert_false(m.uploaded_at.is_empty())
}

///|
async test "publish: already_exists upload failure returns 422 with flag" {
  let base = ".wbtest_pubdup_" + @env.now().to_string()
  let user_dir = base + "/user"
  @utils.ensure_dir(user_dir + "/demo")
  @fs.write_string_to_file(
    user_dir + "/demo/SKILL.md",
    "---\nname: demo\n---\n",
  )
  |> ignore
  let _ = install_mock_transport(Ok((409, "{\"code\":\"name_taken\"}")))
  let resp = publish_skill(
    "demo",
    false,
    licensed_test_brand(),
    user_dir,
    base + "/builtin",
  )
  set_multipart_transport_override(None)
  cleanup_dir(base)
  @debug.assert_eq(resp.status, 422)
  let j : Json = @json.parse(resp.body) catch { _ => panic() }
  guard! j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
  @debug.assert_eq(obj.get("already_exists"), Some(true.to_json()))
  @debug.assert_eq(obj.get("error"), Some("name_taken".to_json()))
}

///|
async test "publish: platform 500 upload failure returns 422 already_exists false" {
  let base = ".wbtest_pubfail_" + @env.now().to_string()
  let user_dir = base + "/user"
  @utils.ensure_dir(user_dir + "/demo")
  @fs.write_string_to_file(
    user_dir + "/demo/SKILL.md",
    "---\nname: demo\n---\n",
  )
  |> ignore
  let _ = install_mock_transport(Ok((500, "{\"error\":\"boom\"}")))
  let resp = publish_skill(
    "demo",
    false,
    licensed_test_brand(),
    user_dir,
    base + "/builtin",
  )
  set_multipart_transport_override(None)
  cleanup_dir(base)
  @debug.assert_eq(resp.status, 422)
  let j : Json = @json.parse(resp.body) catch { _ => panic() }
  guard! j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
  @debug.assert_eq(obj.get("already_exists"), Some(false.to_json()))
  @debug.assert_eq(obj.get("error"), Some("boom".to_json()))
}

// ── handler-level checks ────────────────────────────────────────────

///|
async test "handler: publish rejects invalid skill name" {
  let req = {
    ..HttpRequest::new(POST, "/api/my-skills/x/publish"),
    params: [("name", "../evil")],
  }
  let resp = handle_my_skill_publish(req)
  @debug.assert_eq(resp.status, 400)
}

// ── upload_meta wiring into skill list entries ──────────────────────

///|
test "entries: upload_meta wires platform_version/uploaded_at, absent record stays null" {
  let entry : SkillScanEntry = {
    name: "demo",
    content: "---\nname: demo\ndescription: d\n---\n",
    source: "user",
    enabled: true,
  }
  let meta : Map[String, @brand.UploadMeta] = Map([])
  meta["demo"] = {
    platform_version: "3.1.4",
    uploaded_at: "2026-07-25T00:00:00Z",
  }
  let listed = skill_list_entry_json(entry, meta)
  guard! listed is Object(l)
  @debug.assert_eq(l.get("platform_version"), Some("3.1.4".to_json()))
  @debug.assert_eq(l.get("uploaded_at"), Some("2026-07-25T00:00:00Z".to_json()))
  let creator = creator_local_entry_json(entry, meta)
  guard! creator is Object(c)
  @debug.assert_eq(c.get("platform_version"), Some("3.1.4".to_json()))
  @debug.assert_eq(c.get("uploaded_at"), Some("2026-07-25T00:00:00Z".to_json()))
  // No record → orig empty-value rule (null).
  let other : SkillScanEntry = {
    name: "other",
    content: "---\nname: other\n---\n",
    source: "user",
    enabled: true,
  }
  let listed2 = skill_list_entry_json(other, meta)
  guard! listed2 is Object(l2)
  @debug.assert_eq(l2.get("platform_version"), Some(Json::null()))
  @debug.assert_eq(l2.get("uploaded_at"), Some(Json::null()))
}
