///| FFI bridge — call existing MBOpenClacky JS globals from rabbita (MoonBit).
/// All functions are `extern "js"`; they are synchronous calls into the
/// already-loaded web bundle. The App/NotificationManager globals live on
/// `window` because they are declared with `const` at top level in
/// `web/js/app.js:53` and `web/js/notifications.js:5`.

///|
/// Show a notification toast. `App.showNotification` delegates internally
/// to `NotificationManager.notify` (see `web/js/notifications.js:27`).
/// `type_` is one of: `"info" | "success" | "warning" | "error"`.
#cfg(target="js")
extern "js" fn app_notify(message : String, type_ : String) = "(message, type_) => App.showNotification(message, type_)"

///|
/// Show modal dialog. `body` and `footer` are HTML strings.
#cfg(target="js")
extern "js" fn app_show_modal(title : String, body : String, footer : String) = "(title, body, footer) => App.showModal(title, body, footer)"

///|
/// Hide modal dialog.
#cfg(target="js")
extern "js" fn app_hide_modal() = "() => App.hideModal()"

///|
/// `JSON.stringify` a JS value, exposed so the brand cell can serialize the
/// parsed `API.get/post/put/del` result back into a MoonBit `Json` value
/// (we receive `@js.Value` from a Promise and round-trip via string).
#cfg(target="js")
extern "js" fn js_stringify(v : @js.Value) -> String = "(v) => JSON.stringify(v)"

///|
/// Wrap the existing `API.get` from `web/js/app.js:8` as a `Promise` of
/// `@js.Value`. `API.get` is `async` and returns the parsed JSON body.
#cfg(target="js")
extern "js" fn api_get_promise(path : String) -> @js.Promise = "(path) => API.get(path)"

///|
/// Wrap the existing `API.post` from `web/js/app.js:24`. `body_str` is a
/// JSON string (serialized in MoonBit) and re-parsed on the JS side so we
/// can keep the FFI surface stringly-typed.
#cfg(target="js")
extern "js" fn api_post_promise(
  path : String,
  body_str : String,
) -> @js.Promise = "(path, body_str) => API.post(path, JSON.parse(body_str))"

///|
/// Wrap the existing `API.del` from `web/js/app.js:55`.
#cfg(target="js")
extern "js" fn api_del_promise(path : String) -> @js.Promise = "(path) => API.del(path)"

///|
/// `GET path` → parsed `Json`. Errors propagate as `raise`; callers should
/// wrap with `try .. catch` (or use `fetch_json_safe` from `brand_cell.mbt`).
#cfg(target="js")
pub async fn api_get(path : String) -> Json {
  @json.parse(api_get_promise(path).wait().cast() |> js_stringify)
}

///|
/// `POST path body` → parsed `Json`. `body` is a `Json` value (use
/// `Json::object([...])` or similar to build it).
#cfg(target="js")
pub async fn api_post(path : String, body : Json) -> Json {
  @json.parse(
    api_post_promise(path, body.stringify()).wait().cast() |> js_stringify,
  )
}

///|
/// `DELETE path` → parsed `Json` (or `null` if the server returns 204).
#cfg(target="js")
pub async fn api_del(path : String) -> Json {
  @json.parse(api_del_promise(path).wait().cast() |> js_stringify)
}

///|
/// `encodeURIComponent` for safe path segments. The MBOpenClacky skill
/// names in the legacy UI go through `encodeURIComponent` (see
/// `web/js/brand.js:73`); we mirror that for `/api/brand/skills/:name`.
#cfg(target="js")
extern "js" fn js_encode_uri_component(s : String) -> String = "(s) => encodeURIComponent(s)"

///|
/// Synchronous `window.confirm` for "are you sure?" prompts (e.g. the
/// deactivate / delete-skill confirmations that `web/js/brand.js` uses).
#cfg(target="js")
extern "js" fn window_confirm(msg : String) -> Bool = "(msg) => window.confirm(msg)"
