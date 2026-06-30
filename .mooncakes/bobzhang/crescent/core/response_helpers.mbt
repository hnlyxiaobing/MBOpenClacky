///|
/// Creates a 200 OK response.
pub fn HttpResponse::ok() -> HttpResponse {
  HttpResponse::http_response(status_code=OK)
}

///|
/// Creates a 201 Created response.
pub fn HttpResponse::created() -> HttpResponse {
  HttpResponse::http_response(status_code=Created)
}

///|
/// Creates a 204 No Content response.
pub fn HttpResponse::no_content() -> HttpResponse {
  HttpResponse::http_response(status_code=NoContent)
}

///|
/// Creates a 400 Bad Request response.
pub fn HttpResponse::bad_request() -> HttpResponse {
  HttpResponse::http_response(status_code=BadRequest)
}

///|
/// Creates a 401 Unauthorized response.
pub fn HttpResponse::unauthorized() -> HttpResponse {
  HttpResponse::http_response(status_code=Unauthorized)
}

///|
/// Creates a 403 Forbidden response.
pub fn HttpResponse::forbidden() -> HttpResponse {
  HttpResponse::http_response(status_code=Forbidden)
}

///|
/// Creates a 404 Not Found response.
pub fn HttpResponse::not_found() -> HttpResponse {
  HttpResponse::http_response(status_code=NotFound)
}

///|
/// Creates a 500 Internal Server Error response.
pub fn HttpResponse::internal_server_error() -> HttpResponse {
  HttpResponse::http_response(status_code=InternalServerError)
}

///|
/// Creates an error response with a JSON body containing status and message.
pub fn HttpResponse::error(
  status : StatusCode,
  message : String,
) -> HttpResponse {
  let res = HttpResponse::http_response(status_code=status)
  let json : Json = {
    "error": {
      "status": status.to_int().to_json(),
      "message": message.to_json(),
    },
  }
  res.headers.set("Content-Type", "application/json; charset=utf-8")
  res.raw_body = @utf8.encode(json.stringify())
  res
}
