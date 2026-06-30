///|
fn handle_not_found() -> HttpHandler {
  (_ : Event) => HttpResponse(status_code=@core.StatusCode::NotFound).body("Not Found")
}
