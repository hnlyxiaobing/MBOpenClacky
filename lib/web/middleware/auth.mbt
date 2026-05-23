///| API Key authentication middleware.

///| Creates middleware that checks X-API-Key header.

///| Returns 401 if key is configured but missing/invalid.
pub fn auth_middleware(api_key : String) -> @crescent.Middleware {
  @crescent.Middleware(fn(event : @crescent.Event, next : @crescent.MiddlewareNext) noraise -> &core.Responder {
    let req = event.req
    let header_key = req.get_header("X-API-Key")
    match header_key {
      Some(k) if k == api_key => next()
      _ => @core.HttpResponse::unauthorized().json_value(
        { "error": { "status": 401, "message": "Invalid or missing API key" } } : Json,
      )
    }
  })
}
