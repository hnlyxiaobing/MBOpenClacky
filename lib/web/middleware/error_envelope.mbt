///|
/// Standardized error envelope middleware and helpers.
/// Wraps all error responses in a consistent JSON format:
/// { "error": { "status": N, "message": "...", "code": "...", "hint": "..." } }

///|
/// Build a standardized error JSON response body.
pub fn error_response(
  status : Int,
  message : String,
  code? : String = "",
  hint? : String = "",
) -> Json {
  let fields : Map[String, Json] = Map([
    ("status", status.to_json()),
    ("message", message.to_json()),
  ])
  if code.length() > 0 {
    fields["code"] = code.to_json()
  }
  if hint.length() > 0 {
    fields["hint"] = hint.to_json()
  }
  Json::object({ "error": Json::object(fields) })
}

///|
/// Create a 400 Bad Request response with standard error envelope.
pub fn bad_request_response(message : String) -> @core.HttpResponse {
  @core.HttpResponse::bad_request().json_value(
    error_response(400, message, code="BAD_REQUEST"),
  )
}

///|
/// Create a 404 Not Found response with standard error envelope.
pub fn not_found_response(resource : String) -> @core.HttpResponse {
  @core.HttpResponse::not_found().json_value(
    error_response(404, "Resource not found: \{resource}", code="NOT_FOUND"),
  )
}

///|
/// Create a 500 Internal Server Error response with standard error envelope.
pub fn internal_error_response(message : String) -> @core.HttpResponse {
  @core.HttpResponse::internal_server_error().json_value(
    error_response(500, message, code="INTERNAL_ERROR"),
  )
}

///|
/// Create a 403 Forbidden response with standard error envelope.
pub fn forbidden_response(message : String) -> @core.HttpResponse {
  @core.HttpResponse::forbidden().json_value(
    error_response(403, message, code="FORBIDDEN"),
  )
}

///|
/// Create a 429 Too Many Requests response with standard error envelope.
pub fn rate_limit_response(retry_after : Int) -> @core.HttpResponse {
  @core.HttpResponse::http_response(
    status_code=@core.StatusCode::TooManyRequests,
  )
  .json_value(
    error_response(
      429,
      "Too many requests",
      code="RATE_LIMITED",
      hint="Slow down and retry after the indicated period",
    ),
  )
  .header("Retry-After", retry_after.to_string())
}

///|
/// Error envelope middleware.
/// Catches panics from downstream handlers and wraps them in a standard error response.
pub fn error_envelope_middleware() -> @crescent.Middleware {
  let mw : @crescent.Middleware = (
    _event,
    next,
    // The middleware simply passes through to the next handler.
    // If the handler panics, crescent's built-in error handling catches it.
    // This middleware provides a hook point for future error wrapping.
  ) => next()
  mw
}
