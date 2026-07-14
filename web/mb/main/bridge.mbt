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
/// Read a value from `window.localStorage`. Returns the stored string
/// or `""` if the key is missing / unset. Synchronous (no FFI marshalling
/// for `localStorage` is needed because the API is already sync on the
/// browser side). Used by the tasks panel for its client-side todo
/// persistence (`mbopenclacky_tasks` key).
#cfg(target="js")
extern "js" fn local_storage_get(key : String) -> String = "(key) => { try { return window.localStorage.getItem(key) || ''; } catch (e) { return ''; } }"

///|
/// Write a value to `window.localStorage`. Returns `false` on failure
/// (storage quota, private mode, etc.) so the caller can surface an
/// `App.showNotification` warning.
#cfg(target="js")
extern "js" fn local_storage_set(key : String, value : String) -> Bool = "(key, value) => { try { window.localStorage.setItem(key, value); return true; } catch (e) { return false; } }"

///|
/// `new Date().toISOString()` — used by the tasks panel to stamp
/// `created_at` / `completed_at` on each task so the timestamps match
/// the legacy `TaskStore` output bit-for-bit.
#cfg(target="js")
extern "js" fn js_now_iso() -> String = "() => new Date().toISOString()"

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
extern "js" fn api_del_promise(path : String) -> @js.Promise = "(path) => API.del(path)" ///|
/// `GET path` → parsed `Json`. Errors propagate as `raise`; callers should
/// wrap with `try .. catch` (or use `fetch_json_safe` from `brand_cell.mbt`).

///|
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
/// Wrap the existing `API.put` from `web/js/app.js:43`. `body_str` is a
/// JSON string (serialized in MoonBit) and re-parsed on the JS side.
#cfg(target="js")
extern "js" fn api_put_promise(path : String, body_str : String) -> @js.Promise = "(path, body_str) => API.put(path, JSON.parse(body_str))"

///|
/// `PUT path body` → parsed `Json`. `body` is a `Json` value.
#cfg(target="js")
pub async fn api_put(path : String, body : Json) -> Json {
  @json.parse(
    api_put_promise(path, body.stringify()).wait().cast() |> js_stringify,
  )
}

///|
/// `encodeURIComponent` for safe path segments. The MBOpenClacky skill
/// names in the legacy UI go through `encodeURIComponent` (see
/// `web/js/brand.js:73`); we mirror that for `/api/brand/skills/:name`.
#cfg(target="js")
extern "js" fn js_encode_uri_component(s : String) -> String = "(s) => encodeURIComponent(s)"

///|
/// Normalise a raw URL string the way `web/js/browser.js:handleNavigate`
/// does: trim, prepend `https://` when no protocol is present, then
/// validate with `new URL`. Returns `(url, valid)`; `valid` is `false`
/// (and `url` is the prepped string) when the value is empty or not a
/// parseable URL.
#cfg(target="js")
extern "js" fn js_normalize_url(raw : String) -> (String, Bool) = "(raw) => { let u = (raw || '').trim(); if (!u) return ['', false]; let lo = u.toLowerCase(); if (lo.indexOf('http://') !== 0 && lo.indexOf('https://') !== 0) u = 'https://' + u; try { new URL(u); return [u, true]; } catch (e) { return [u, false]; } }"

///|
/// Trigger a browser download of a data URL (used by the browser panel's
/// screenshot Download button). Mirrors `web/js/browser.js:downloadScreenshot`
/// which builds an `<a>` element, sets `href` + `download`, clicks it.
#cfg(target="js")
extern "js" fn js_download_data_url(url : String, filename : String) = "(url, filename) => { const a = document.createElement('a'); a.href = url; a.download = filename; document.body.appendChild(a); a.click(); document.body.removeChild(a); }"

///|
/// Synchronous `window.confirm` for "are you sure?" prompts (e.g. the
/// deactivate / delete-skill confirmations that `web/js/brand.js` uses).
#cfg(target="js")
extern "js" fn window_confirm(msg : String) -> Bool = "(msg) => window.confirm(msg)"

///|
/// `I18n.setLocale(lang)` from `web/js/i18n.js` — apply the user's
/// preferred language immediately after a profile save. The legacy
/// `web/js/profile.js:138` does the same `if (I18n.getLocale() !==
/// language) I18n.setLocale(language)`. We mirror that with a thin FFI
/// wrapper so the rabbita cell can invoke it directly.
#cfg(target="js")
extern "js" fn i18n_set_locale(lang : String) = "(lang) => I18n.setLocale(lang)"

///|
/// Read the current session id from `App.currentSessionId` (see
/// `web/js/app.js:69`). The Share cell renders different markup
/// depending on whether a session is active; we read the global
/// synchronously on `Init` instead of fetching it.
#cfg(target="js")
extern "js" fn js_current_session_id() -> String = "() => App.currentSessionId || ''"

///|
/// Read the current page origin (e.g. `https://app.example.com`) so
/// the Share cell can build an absolute share URL without going
/// through `window.location.href` (which would include the path).
#cfg(target="js")
extern "js" fn js_origin() -> String = "() => window.location.origin"

///|
/// `fetch(path).then(r => r.text())` — used by the Share cell to
/// export a session in `format=md` (a plain text body). The existing
/// `API.get` from `web/js/app.js:8` always parses JSON, so the
/// text-export endpoint needs a separate path. Wraps in `safe_*`
/// style: caller turns the result into `Result[String, String]`.
#cfg(target="js")
extern "js" fn api_get_text_promise(path : String) -> @js.Promise = "(path) => fetch(path).then(r => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.text(); })"

///|
/// `GET path` → response body as `String` (no JSON parsing). Throws
/// if the network layer rejects; callers wrap with `try` and stringify
/// the error.
#cfg(target="js")
pub async fn api_get_text(path : String) -> String {
  api_get_text_promise(path).wait().cast()
}

///|
/// `I18n.t(key, params)` from `web/js/i18n.js` - translate a key with
/// optional `{{param}}` substitution. `params_json` is a JSON string
/// (e.g. `"{}"` or `"{\"name\":\"foo\"}"`) parsed on the JS side.
/// Falls back to the key itself when the key is missing from both
/// the current-locale and English dictionaries.
#cfg(target="js")
extern "js" fn i18n_t(key : String, params_json : String) -> String = "(key, params_json) => { let p; try { p = JSON.parse(params_json || '{}'); } catch(e) { p = {}; } return I18n.t(key, p); }"

///|
/// `I18n.getLocale()` from `web/js/i18n.js` - returns `"en"` or `"zh"`.
#cfg(target="js")
extern "js" fn i18n_get_locale() -> String = "() => I18n.getLocale()"

///|
/// Register a callback for the `i18n:locale-changed` CustomEvent
/// dispatched by `I18n.setLocale()` (see `web/js/i18n.js:62`). The
/// MoonBit closure is wrapped as a JS function automatically by the
/// extern FFI. Used via `@cmd.custom_cmd` to feed `scheduler.add`
/// back into the cell's update loop.
#cfg(target="js")
extern "js" fn i18n_on_locale_changed(callback : () -> Unit) = "(callback) => window.addEventListener('i18n:locale-changed', () => callback())"

///|
/// Parse a date string (epoch-seconds or ISO) and return a
/// relative-time label such as "5m ago" / "3h ago" / "2d ago" /
/// "2024-01-15" for older dates. Mirrors the logic in
/// `web/js/trash.js:531` (`formatTime`). Returns `"—"` if the value
/// is empty or unparseable.
#cfg(target="js")
extern "js" fn js_parse_date(value : String) -> String = "(v) => { if (!v) return '\u2014'; let date; if (/^\\d+$/.test(v)) { date = new Date(parseInt(v) * 1000); } else { date = new Date(v); } if (isNaN(date.getTime())) return '\u2014'; const now = new Date(); const diffMs = now - date; const diffMin = Math.floor(diffMs / 60000); const diffHr = Math.floor(diffMs / 3600000); const diffDay = Math.floor(diffMs / 86400000); if (diffMin < 1) return 'just now'; if (diffMin < 60) return diffMin + 'm ago'; if (diffHr < 24) return diffHr + 'h ago'; if (diffDay < 7) return diffDay + 'd ago'; return date.toLocaleDateString(); }"

///|
/// Parse an expiry date and return `(text, expired)` — the relative
/// label and a flag indicating whether the item has already expired.
/// Mirrors `web/js/trash.js:495` (`formatExpiry`).
#cfg(target="js")
extern "js" fn js_format_expiry(value : String) -> (String, Bool) = "(v) => { if (!v) return ['\u2014', false]; let d; if (/^\\d+$/.test(v)) { d = new Date(parseInt(v) * 1000); } else { d = new Date(v); } if (isNaN(d.getTime())) return ['\u2014', false]; const now = new Date(); const diffMs = d - now; const diffDays = Math.ceil(diffMs / 86400000); if (diffDays < 0) return ['Expired', true]; if (diffDays === 0) return ['Expires today', false]; if (diffDays === 1) return ['1 day left', false]; return [diffDays + ' days left', false]; }"
