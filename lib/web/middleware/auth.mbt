///| API Key authentication middleware.

///| Creates middleware that checks X-API-Key header.

///|
/// Returns 401 if key is configured but missing/invalid.
pub fn auth_middleware(api_key : String) -> @crescent.Middleware {
  let mw : @crescent.Middleware = (event, next) => {
    let req = event.req
    let header_key = req.get_header("X-API-Key")
    if header_key == Some(api_key) {
      next()
    } else {
      let msg = "Invalid or missing API key"
      @core.HttpResponse::unauthorized().json_value(
        Json::object({
          "error": Json::object({
            "status": (401).to_json(),
            "message": msg.to_json(),
          }),
        }),
      )
    }
  }
  mw
}
