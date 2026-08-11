///|
/// White-box tests for StaticServer, get_mime_type, is_static_asset, and spa_fallback.

///|
/// Build a temporary, OS-portable static web root with fixture assets
/// (js/app.js, css/style.css) so the serve/MIME tests don't depend on the
/// repository's built `./web` directory, which is absent on many checkouts
/// (notably Windows). Uses the system TEMP dir rather than a hardcoded /tmp.
fn wbtest_web_root() -> String {
  let base = match @env.get_env_var("TEMP") {
    Some(d) => d
    None =>
      match @env.get_env_var("TMPDIR") {
        Some(d) => d
        None => "/tmp"
      }
  }
  let root = base + "/_wbtest_web_" + @env.now().to_string()
  @utils.ensure_dir(root + "/js")
  @utils.ensure_dir(root + "/css")
  @fs.write_string_to_file(root + "/js/app.js", "console.log('app');") catch {
    _ => ()
  }
  @fs.write_string_to_file(root + "/css/style.css", "body { color: red; }") catch {
    _ => ()
  }
  root
}

// ══════════════════════════════════════════════════════════════════
// get_mime_type Tests
// ══════════════════════════════════════════════════════════════════

///|
test "mime: .html returns text/html" {
  @debug.assert_eq(get_mime_type("page.html"), "text/html")
}

///|
test "mime: .htm returns text/html" {
  @debug.assert_eq(get_mime_type("page.htm"), "text/html")
}

///|
test "mime: .css returns text/css" {
  @debug.assert_eq(get_mime_type("style.css"), "text/css")
}

///|
test "mime: .js returns application/javascript" {
  @debug.assert_eq(get_mime_type("app.js"), "application/javascript")
}

///|
test "mime: .json returns application/json" {
  @debug.assert_eq(get_mime_type("data.json"), "application/json")
}

///|
test "mime: .png returns image/png" {
  @debug.assert_eq(get_mime_type("logo.png"), "image/png")
}

///|
test "mime: .svg returns image/svg+xml" {
  @debug.assert_eq(get_mime_type("icon.svg"), "image/svg+xml")
}

///|
test "mime: .jpg returns image/jpeg" {
  @debug.assert_eq(get_mime_type("photo.jpg"), "image/jpeg")
}

///|
test "mime: .jpeg returns image/jpeg" {
  @debug.assert_eq(get_mime_type("photo.jpeg"), "image/jpeg")
}

///|
test "mime: .gif returns image/gif" {
  @debug.assert_eq(get_mime_type("anim.gif"), "image/gif")
}

///|
test "mime: .ico returns image/x-icon" {
  @debug.assert_eq(get_mime_type("favicon.ico"), "image/x-icon")
}

///|
test "mime: .woff returns font/woff2" {
  @debug.assert_eq(get_mime_type("font.woff"), "font/woff2")
}

///|
test "mime: .woff2 returns font/woff2" {
  @debug.assert_eq(get_mime_type("font.woff2"), "font/woff2")
}

///|
test "mime: unknown extension returns octet-stream" {
  @debug.assert_eq(get_mime_type("file.xyz"), "application/octet-stream")
}

///|
test "mime: no extension returns octet-stream" {
  @debug.assert_eq(get_mime_type("Makefile"), "application/octet-stream")
}

///|
test "mime: full path with extension works" {
  @debug.assert_eq(get_mime_type("web/css/style.css"), "text/css")
}

// ══════════════════════════════════════════════════════════════════
// is_static_asset Tests
// ══════════════════════════════════════════════════════════════════

///|
test "is_static_asset: html file" {
  assert_true(is_static_asset("index.html"))
}

///|
test "is_static_asset: css file" {
  assert_true(is_static_asset("css/style.css"))
}

///|
test "is_static_asset: js file" {
  assert_true(is_static_asset("js/app.js"))
}

///|
test "is_static_asset: json file" {
  assert_true(is_static_asset("data.json"))
}

///|
test "is_static_asset: png file" {
  assert_true(is_static_asset("img/logo.png"))
}

///|
test "is_static_asset: svg file" {
  assert_true(is_static_asset("icon.svg"))
}

///|
test "is_static_asset: jpg file" {
  assert_true(is_static_asset("photo.jpg"))
}

///|
test "is_static_asset: gif file" {
  assert_true(is_static_asset("anim.gif"))
}

///|
test "is_static_asset: ico file" {
  assert_true(is_static_asset("favicon.ico"))
}

///|
test "is_static_asset: woff file" {
  assert_true(is_static_asset("font.woff"))
}

///|
test "is_static_asset: bare path without extension" {
  assert_false(is_static_asset("dashboard"))
}

///|
test "is_static_asset: route-like path" {
  assert_false(is_static_asset("some/route"))
}

// ══════════════════════════════════════════════════════════════════
// StaticServer::serve – Root Path
// ══════════════════════════════════════════════════════════════════

///|
test "serve: root '/' returns index.html with text/html" {
  let server = StaticServer::new(wbtest_web_root())
  let resp = server.serve("/")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/html")
}

///|
test "serve: empty path returns index.html with text/html" {
  let server = StaticServer::new(wbtest_web_root())
  let resp = server.serve("")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/html")
}

///|
test "serve: custom index_file" {
  let server = StaticServer::new("./web", index_file="main.html")
  // Root path should resolve to custom index file (main.html)
  let resp = server.serve("/")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/html")
}

// ══════════════════════════════════════════════════════════════════
// StaticServer::serve – CSS & JS MIME Types
// ══════════════════════════════════════════════════════════════════

///|
test "serve: css file returns text/css" {
  let server = StaticServer::new(wbtest_web_root())
  let resp = server.serve("/css/style.css")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/css")
}

///|
test "serve: js file returns application/javascript" {
  let server = StaticServer::new(wbtest_web_root())
  let resp = server.serve("/js/app.js")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "application/javascript")
}

///|
test "serve: js file includes no-store cache header" {
  let server = StaticServer::new(wbtest_web_root())
  let resp = server.serve("/js/app.js")
  @debug.assert_eq(resp.status, 200)
  assert_true(resp.headers.length() > 0)
  // Spec web-parity-01: ALL static assets get Cache-Control: no-store,
  // aligned with the original project's FileHandler.
  let cache_header = resp.headers[0]
  @debug.assert_eq(cache_header.0, "Cache-Control")
  @debug.assert_eq(cache_header.1, "no-store")
}

// ══════════════════════════════════════════════════════════════════
// StaticServer::serve – SPA Fallback
// ══════════════════════════════════════════════════════════════════

///|
test "spa_fallback: non-asset path returns index.html content" {
  let server = StaticServer::new(wbtest_web_root())
  let resp = server.serve("/dashboard")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/html")
  // SPA fallback body contains app div
  assert_true(resp.body.contains("app"))
}

///|
test "spa_fallback: nested route returns html" {
  let server = StaticServer::new(wbtest_web_root())
  let resp = server.serve("/settings/advanced")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/html")
}

///|
test "spa_fallback: includes X-SPA-Fallback header" {
  let server = StaticServer::new(wbtest_web_root())
  let resp = server.serve("/some/route")
  @debug.assert_eq(resp.status, 200)
  // Find the X-SPA-Fallback header
  let mut found = false
  let mut i = 0
  while i < resp.headers.length() {
    if resp.headers[i].0 == "X-SPA-Fallback" {
      found = true
      @debug.assert_eq(resp.headers[i].1, "index.html")
    }
    i = i + 1
  }
  assert_true(found)
}

///|
test "spa_fallback: Cache-Control is no-store" {
  let server = StaticServer::new(wbtest_web_root())
  let resp = server.serve("/some/route")
  let mut found = false
  let mut i = 0
  while i < resp.headers.length() {
    if resp.headers[i].0 == "Cache-Control" {
      found = true
      @debug.assert_eq(resp.headers[i].1, "no-store")
    }
    i = i + 1
  }
  assert_true(found)
}

// ══════════════════════════════════════════════════════════════════
// StaticServer::serve – Directory Traversal Protection
// ══════════════════════════════════════════════════════════════════

///|
test "traversal: '../etc/passwd' blocked with 400" {
  let server = StaticServer::new(wbtest_web_root())
  let resp = server.serve("/../../../etc/passwd")
  @debug.assert_eq(resp.status, 400)
}

///|
test "traversal: simple '..' blocked" {
  let server = StaticServer::new(wbtest_web_root())
  let resp = server.serve("/../secret.txt")
  @debug.assert_eq(resp.status, 400)
}

///|
test "traversal: embedded '..' blocked" {
  let server = StaticServer::new(wbtest_web_root())
  let resp = server.serve("/css/../../etc/shadow")
  @debug.assert_eq(resp.status, 400)
}

///|
test "traversal: body contains 'Invalid path'" {
  let server = StaticServer::new(wbtest_web_root())
  let resp = server.serve("/../../etc/hosts")
  @debug.assert_eq(resp.status, 400)
  assert_true(resp.body.contains("Invalid path"))
}

///|
test "traversal: percent-encoded %2e%2e never escapes web root" {
  // Pins the URL-decoding assumption behind the contains("..") check:
  // serve() operates on the already-decoded path — once "%2e%2e" is decoded
  // to "..", the traversal guard above blocks it with 400. If a path still
  // arrives percent-encoded, "%2e%2e" is just a literal filename under the
  // web root: it resolves to a missing file (SPA fallback / 404), never to
  // a file outside the root.
  let server = StaticServer::new(wbtest_web_root())
  // Decoded form is blocked outright:
  let decoded = server.serve("/../../etc/passwd")
  @debug.assert_eq(decoded.status, 400)
  // Encoded form must never serve the target file's content:
  let encoded = server.serve("/%2e%2e/%2e%2e/etc/passwd")
  assert_false(encoded.body.contains("root:"))
  // It either resolves to the SPA fallback shell or a 4xx:
  assert_true(
    encoded.status == 400 ||
    encoded.status == 404 ||
    encoded.body.contains("<!DOCTYPE html>"),
  )
}

// ══════════════════════════════════════════════════════════════════
// StaticServer::serve – Non-existent file (placeholder behavior)
// ══════════════════════════════════════════════════════════════════

///|
test "serve: non-existent asset returns 404" {
  // A known static-asset extension that does not exist on disk must 404,
  // not silently return a placeholder — real filesystem I/O is the source
  // of truth for static assets.
  let server = StaticServer::new(wbtest_web_root())
  let resp = server.serve("/nonexistent.css")
  @debug.assert_eq(resp.status, 404)
}

///|
test "serve: non-asset non-existent path triggers SPA fallback" {
  // Paths without known extensions trigger SPA fallback
  let server = StaticServer::new(wbtest_web_root())
  let resp = server.serve("/nonexistent_page")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/html")
  assert_true(resp.body.contains("app"))
}

// ══════════════════════════════════════════════════════════════════
// StaticServer::serve – Path Normalization
// ══════════════════════════════════════════════════════════════════

///|
test "serve: leading slash stripped for asset path" {
  let server = StaticServer::new(wbtest_web_root())
  let resp1 = server.serve("/css/style.css")
  let resp2 = server.serve("css/style.css")
  // Both should return same MIME type
  @debug.assert_eq(resp1.content_type, resp2.content_type)
  @debug.assert_eq(resp1.status, resp2.status)
}

///|
test "serve: path without leading slash for asset" {
  let server = StaticServer::new(wbtest_web_root())
  let resp = server.serve("js/app.js")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "application/javascript")
}

// ══════════════════════════════════════════════════════════════════
// spa_fallback function direct tests
// ══════════════════════════════════════════════════════════════════

///|
test "spa_fallback: direct call returns proper response" {
  let server = StaticServer::new(wbtest_web_root())
  let resp = spa_fallback(server)
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/html")
  assert_true(resp.body.contains("<!DOCTYPE html>"))
  assert_true(resp.body.contains("app"))
}

///|
test "spa_fallback: uses custom index_file in header" {
  let server = StaticServer::new("./web", index_file="main.html")
  let resp = spa_fallback(server)
  let mut found = false
  let mut i = 0
  while i < resp.headers.length() {
    if resp.headers[i].0 == "X-SPA-Fallback" {
      found = true
      @debug.assert_eq(resp.headers[i].1, "main.html")
    }
    i = i + 1
  }
  assert_true(found)
}

// ══════════════════════════════════════════════════════════════════
// Binary Asset Tests (mp3, woff2, png, ico)
// ══════════════════════════════════════════════════════════════════

///|
test "mime: .mp3 returns audio/mpeg" {
  @debug.assert_eq(get_mime_type("notify.mp3"), "audio/mpeg")
}

///|
test "is_static_asset: mp3 file" {
  assert_true(is_static_asset("assets/notify.mp3"))
}

///|
test "is_static_asset: woff2 file" {
  assert_true(is_static_asset("fonts/KaTeX_Main-Regular.woff2"))
}

///|
test "is_binary_asset: woff2 file" {
  assert_true(is_binary_asset("fonts/KaTeX_Main-Regular.woff2"))
}

///|
test "is_binary_asset: woff file" {
  assert_true(is_binary_asset("fonts/KaTeX_Main-Regular.woff"))
}

///|
test "is_binary_asset: mp3 file" {
  assert_true(is_binary_asset("assets/notify.mp3"))
}

///|
test "is_binary_asset: png file" {
  assert_true(is_binary_asset("img/logo.png"))
}

///|
test "is_binary_asset: ico file" {
  assert_true(is_binary_asset("favicon.ico"))
}

///|
test "is_binary_asset: jpg file" {
  assert_true(is_binary_asset("photo.jpg"))
}

///|
test "is_binary_asset: gif file" {
  assert_true(is_binary_asset("anim.gif"))
}

///|
test "is_binary_asset: css file (text, not binary)" {
  assert_false(is_binary_asset("css/style.css"))
}

///|
test "is_binary_asset: js file (text, not binary)" {
  assert_false(is_binary_asset("js/app.js"))
}

///|
test "is_binary_asset: html file (text, not binary)" {
  assert_false(is_binary_asset("index.html"))
}

///|
test "serve: binary png preserves byte integrity with null bytes" {
  let root = wbtest_web_root()
  let png_data = b"\x89PNG\x0d\x0a\x1a\x0a\x00\x00\x00\x0dIHDR\x00\x00\x00\xff\x00\x00\x00\xff"
  @fs.write_bytes_to_file(root + "/test.png", png_data) catch {
    _ => ()
  }
  let server = StaticServer::new(root)
  let resp = server.serve("/test.png")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "image/png")
  @debug.assert_eq(resp.body, "")
  match resp.body_bytes {
    Some(bytes) => assert_eq(bytes, png_data)
    None => abort("Expected body_bytes to be Some for binary asset")
  }
}

///|
test "serve: mp3 returns audio/mpeg with binary body_bytes" {
  let root = wbtest_web_root()
  let mp3_data = b"\xff\xfb\x90\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  @fs.write_bytes_to_file(root + "/notify.mp3", mp3_data) catch {
    _ => ()
  }
  let server = StaticServer::new(root)
  let resp = server.serve("/notify.mp3")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "audio/mpeg")
  @debug.assert_eq(resp.body, "")
  match resp.body_bytes {
    Some(bytes) => assert_eq(bytes, mp3_data)
    None => abort("Expected body_bytes to be Some for binary asset")
  }
}

///|
test "serve: woff2 returns font/woff2 with binary body_bytes" {
  let root = wbtest_web_root()
  let woff2_data = b"\x00\x01\x02\xff\xfe\x00\x42\x80\x81\x00"
  @fs.write_bytes_to_file(root + "/font.woff2", woff2_data) catch {
    _ => ()
  }
  let server = StaticServer::new(root)
  let resp = server.serve("/font.woff2")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "font/woff2")
  @debug.assert_eq(resp.body, "")
  match resp.body_bytes {
    Some(bytes) => assert_eq(bytes, woff2_data)
    None => abort("Expected body_bytes to be Some for binary asset")
  }
}

///|
test "serve: text asset still uses body string (not body_bytes)" {
  let root = wbtest_web_root()
  let server = StaticServer::new(root)
  let resp = server.serve("/css/style.css")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/css")
  assert_true(resp.body.contains("color"))
  match resp.body_bytes {
    Some(_) => abort("Expected body_bytes to be None for text asset")
    None => ()
  }
}
