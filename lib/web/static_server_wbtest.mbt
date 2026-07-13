///|
/// White-box tests for StaticServer, get_mime_type, is_static_asset, and spa_fallback.

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
  let server = StaticServer::new("./web")
  let resp = server.serve("/")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/html")
}

///|
test "serve: empty path returns index.html with text/html" {
  let server = StaticServer::new("./web")
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
  let server = StaticServer::new("./web")
  let resp = server.serve("/css/style.css")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/css")
}

///|
test "serve: js file returns application/javascript" {
  let server = StaticServer::new("./web")
  let resp = server.serve("/js/app.js")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "application/javascript")
}

///|
test "serve: js file includes cache header" {
  let server = StaticServer::new("./web")
  let resp = server.serve("/js/app.js")
  @debug.assert_eq(resp.status, 200)
  assert_true(resp.headers.length() > 0)
  // Verify Cache-Control header is set for static assets
  let cache_header = resp.headers[0]
  @debug.assert_eq(cache_header.0, "Cache-Control")
  assert_true(cache_header.1.contains("public"))
}

// ══════════════════════════════════════════════════════════════════
// StaticServer::serve – SPA Fallback
// ══════════════════════════════════════════════════════════════════

///|
test "spa_fallback: non-asset path returns index.html content" {
  let server = StaticServer::new("./web")
  let resp = server.serve("/dashboard")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/html")
  // SPA fallback body contains app div
  assert_true(resp.body.contains("app"))
}

///|
test "spa_fallback: nested route returns html" {
  let server = StaticServer::new("./web")
  let resp = server.serve("/settings/advanced")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/html")
}

///|
test "spa_fallback: includes X-SPA-Fallback header" {
  let server = StaticServer::new("./web")
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
test "spa_fallback: Cache-Control is no-cache" {
  let server = StaticServer::new("./web")
  let resp = server.serve("/some/route")
  let mut found = false
  let mut i = 0
  while i < resp.headers.length() {
    if resp.headers[i].0 == "Cache-Control" {
      found = true
      @debug.assert_eq(resp.headers[i].1, "no-cache")
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
  let server = StaticServer::new("./web")
  let resp = server.serve("/../../../etc/passwd")
  @debug.assert_eq(resp.status, 400)
}

///|
test "traversal: simple '..' blocked" {
  let server = StaticServer::new("./web")
  let resp = server.serve("/../secret.txt")
  @debug.assert_eq(resp.status, 400)
}

///|
test "traversal: embedded '..' blocked" {
  let server = StaticServer::new("./web")
  let resp = server.serve("/css/../../etc/shadow")
  @debug.assert_eq(resp.status, 400)
}

///|
test "traversal: body contains 'Invalid path'" {
  let server = StaticServer::new("./web")
  let resp = server.serve("/../../etc/hosts")
  @debug.assert_eq(resp.status, 400)
  assert_true(resp.body.contains("Invalid path"))
}

// ══════════════════════════════════════════════════════════════════
// StaticServer::serve – Non-existent file (placeholder behavior)
// ══════════════════════════════════════════════════════════════════

///|
test "serve: non-existent asset returns 404" {
  // A known static-asset extension that does not exist on disk must 404,
  // not silently return a placeholder — real filesystem I/O is the source
  // of truth for static assets.
  let server = StaticServer::new("./web")
  let resp = server.serve("/nonexistent.css")
  @debug.assert_eq(resp.status, 404)
}

///|
test "serve: non-asset non-existent path triggers SPA fallback" {
  // Paths without known extensions trigger SPA fallback
  let server = StaticServer::new("./web")
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
  let server = StaticServer::new("./web")
  let resp1 = server.serve("/css/style.css")
  let resp2 = server.serve("css/style.css")
  // Both should return same MIME type
  @debug.assert_eq(resp1.content_type, resp2.content_type)
  @debug.assert_eq(resp1.status, resp2.status)
}

///|
test "serve: path without leading slash for asset" {
  let server = StaticServer::new("./web")
  let resp = server.serve("js/app.js")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "application/javascript")
}

// ══════════════════════════════════════════════════════════════════
// spa_fallback function direct tests
// ══════════════════════════════════════════════════════════════════

///|
test "spa_fallback: direct call returns proper response" {
  let server = StaticServer::new("./web")
  let resp = spa_fallback(server)
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/html")
  assert_true(resp.body.contains("<!DOCTYPE html>"))
  assert_true(resp.body.contains("<script"))
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
