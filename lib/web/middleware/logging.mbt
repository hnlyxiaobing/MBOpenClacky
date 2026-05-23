///| Request logging middleware.

///| Creates middleware that logs method, path, and duration.
pub fn logging_middleware() -> @crescent.Middleware {
  @crescent.Middleware(fn(event : @crescent.Event, next : @crescent.MiddlewareNext) noraise -> &core.Responder {
    let start = @async.now()
    let result = next()
    let elapsed = @async.now() - start
    let method = event.req.http_method.to_string()
    let url = event.req.url
    println("[web] \{method} \{url} - \{elapsed}ms")
    result
  })
}
