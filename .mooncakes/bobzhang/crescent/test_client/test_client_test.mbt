///|
async test "test client GET returns text" {
  let app = @crescent.App()
  app.get("/hello", _ => "Hello!")
  let client = @test_client.TestClient(app)
  let res = client.get("/hello")
  guard (res.status, res.body_text()) is (OK, "Hello!") else {
    fail(
      "Expected 200 OK with body 'Hello!', got status \{res.status} and body '\{res.body_text()}'",
    )
  }
}

///|
async test "test client GET returns json" {
  let app = @crescent.App()
  app.get("/data", _ => ({ "key": "value" } : Json))
  let client = @test_client.TestClient(app)
  let res = client.get("/data")
  @debug.assert_eq(res.status, OK)
  @debug.debug_inspect(
    res.headers.get("Content-Type"),
    content="Some(\"application/json; charset=utf-8\")",
  )
}

///|
async test "test client POST with body" {
  let app = @crescent.App()
  app.post("/echo", event => {
    let text : String = event.req.body() catch { _ => "error" }
    text
  })
  let client = @test_client.TestClient(app)
  let res = client.post("/echo", body=b"hello world")
  @debug.assert_eq(res.status, OK)
  @debug.assert_eq(res.body_text(), "hello world")
}

///|
async test "test client route params" {
  let app = @crescent.App()
  app.get("/users/:id", event => event.param("id").unwrap_or("?"))
  let client = @test_client.TestClient(app)
  let res = client.get("/users/42")
  @debug.assert_eq(res.status, OK)
  @debug.assert_eq(res.body_text(), "42")
}

///|
async test "test client 404 for missing route" {
  let app = @crescent.App()
  app.get("/exists", _ => "ok")
  let client = @test_client.TestClient(app)
  let res = client.get("/missing")
  @debug.assert_eq(res.status, NotFound)
}

///|
async test "test client custom not found handler" {
  let app = @crescent.App()
  app.set_not_found_handler(_ => {
    @crescent.HttpResponse::not_found().body("custom 404")
  })
  let client = @test_client.TestClient(app)
  let res = client.get("/anything")
  @debug.assert_eq(res.status, NotFound)
  @debug.assert_eq(res.body_text(), "custom 404")
}

///|
async test "test client runs middleware" {
  // Uses an inline custom middleware rather than a named one from
  // bobzhang/crescent/middleware — this test verifies that @test_client.TestClient
  // dispatches requests through the middleware chain, not that any
  // particular middleware behaves correctly.
  let mut ran = false
  let app = @crescent.App()
  app.use_middleware((_event, next) => {
    ran = true
    next()
  })
  app.get("/test", _ => "ok")
  let client = @test_client.TestClient(app)
  let res = client.get("/test")
  @debug.assert_eq(res.status, OK)
  @debug.assert_eq(ran, true)
}

///|
async test "test client with error handling handler" {
  let app = @crescent.App()
  app.post("/users", event => {
    let _ : Json = event.req.json()
    "created"
  })
  let client = @test_client.TestClient(app)
  // Valid request
  let res = client.post("/users", body=b"{\"name\":\"Alice\"}")
  @debug.assert_eq(res.status, OK)
  // Invalid JSON
  let res2 = client.post("/users", body=b"not json")
  @debug.assert_eq(res2.status, BadRequest)
}

///|
async test "test client method not allowed" {
  let app = @crescent.App()
  app.get("/only-get", _ => "ok")
  let client = @test_client.TestClient(app)
  let res = client.post("/only-get")
  @debug.assert_eq(res.status, MethodNotAllowed)
}

///|
async test "test client PUT and DELETE" {
  let app = @crescent.App()
  app.put("/item", _ => "updated")
  app.delete("/item", _ => "deleted")
  let client = @test_client.TestClient(app)
  let res_put = client.put("/item")
  @debug.assert_eq(res_put.body_text(), "updated")
  let res_del = client.delete("/item")
  @debug.assert_eq(res_del.body_text(), "deleted")
}

///|
async test "test client with custom headers" {
  let app = @crescent.App()
  app.get("/auth", event => {
    match event.req.get_header("authorization") {
      Some(token) => "token: " + token
      None => "no auth"
    }
  })
  let client = @test_client.TestClient(app)
  let res = client.get("/auth")
  @debug.assert_eq(res.body_text(), "no auth")
  let res2 = client.get("/auth", headers={ "Authorization": "Bearer abc123" })
  @debug.assert_eq(res2.body_text(), "token: Bearer abc123")
}

///|
async test "test client with path-scoped middleware" {
  let order : Array[String] = []
  let app = @crescent.App()
  app.use_middleware(
    (_, next) => {
      order.push("api-mw")
      next()
    },
    base_path="/api",
  )
  app.get("/api/data", _ => "data")
  app.get("/other", _ => "other")
  let client = @test_client.TestClient(app)
  // Should trigger middleware
  ignore(client.get("/api/data"))
  @debug.assert_eq(order.length(), 1)
  // Should NOT trigger middleware
  ignore(client.get("/other"))
  @debug.assert_eq(order.length(), 1)
}
