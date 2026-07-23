///| Request logging middleware.

///|
/// Creates middleware that logs method, path, and duration.
pub fn logging_middleware() -> @crescent.Middleware {
  let mw : @crescent.Middleware = (event, next) => {
    let start = @env.now().reinterpret_as_int64()
    let result = next()
    let elapsed = @env.now().reinterpret_as_int64() - start
    let http_method = event.req.http_method.to_string()
    let url = event.req.url
    println("[web] \{http_method} \{url} - \{elapsed}ms")
    result
  }
  mw
}
