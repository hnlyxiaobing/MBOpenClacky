///|
test "redirect sets location header" {
  let res = HttpResponse::redirect("/new-path")
  @debug.debug_inspect(res.status_code, content="MovedPermanently")
  @debug.debug_inspect(res.headers.get("Location"), content="Some(\"/new-path\")")
}

///|
test "redirect_temporary sets location header" {
  let res = HttpResponse::redirect_temporary("/temp-path")
  @debug.debug_inspect(res.status_code, content="Found")
  @debug.debug_inspect(res.headers.get("Location"), content="Some(\"/temp-path\")")
}

///|
test "redirect_307 sets location header" {
  let res = HttpResponse::redirect_307("/preserve-method")
  @debug.debug_inspect(res.status_code, content="TemporaryRedirect")
  @debug.debug_inspect(res.headers.get("Location"), content="Some(\"/preserve-method\")")
}

///|
test "redirect_308 sets location header" {
  let res = HttpResponse::redirect_308("/permanent-preserve")
  @debug.debug_inspect(res.status_code, content="PermanentRedirect")
  @debug.debug_inspect(res.headers.get("Location"), content="Some(\"/permanent-preserve\")")
}
