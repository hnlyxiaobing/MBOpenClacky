///| FFI bridge — call existing MBOpenClacky JS globals from rabbita (MoonBit).
/// All functions are `extern "js"`; they are synchronous calls into the
/// already-loaded web bundle. After Phase 4 the `App` / `NotificationManager`
/// / `I18n` globals are gone (replaced by rabbita cells), so most FFIs now
/// use native DOM APIs (localStorage, fetch, CustomEvent) directly.

///| ── Notifications (Task Pack A) ──────────────────────────────

///|
/// Dispatch an `app:notify` CustomEvent. The notification_cell listens
/// for this event and renders the toast in its update loop. `type_` is
/// one of: `"info" | "success" | "warning" | "error"`.
#cfg(target="js")
extern "js" fn app_notify(message : String, type_ : String) = "(message, type_) => { window.dispatchEvent(new CustomEvent('app:notify', { detail: { message, type: type_ } })); }"

///|
/// Register a callback for the `app:notify` CustomEvent. The MoonBit
/// closure is wrapped as a JS function automatically by the extern FFI.
/// Used via `@cmd.custom_cmd` to feed `scheduler.add` back into the
/// notification_cell's update loop.
#cfg(target="js")
extern "js" fn on_app_notify(callback : (String, String) -> Unit) = "(callback) => { window.addEventListener('app:notify', (e) => { const d = e.detail || {}; callback(d.message || '', d.type || 'info'); }); }"

///|
/// `setTimeout(ms, callback)` — fire-and-forget delayed action.
/// Used by notification_cell for auto-dismiss of toasts.
#cfg(target="js")
extern "js" fn js_set_timeout(ms : Int, callback : () -> Unit) -> Unit = "(ms, callback) => setTimeout(callback, ms)"

///| ── Markdown / escape helpers (chat_cell) ─────────────────────

///|
/// `JSON.stringify` a JS value, exposed so the chat cell can serialize
/// the parsed `api_get_promise` result back into a MoonBit `Json` value
/// (we receive `@js.Value` from a Promise and round-trip via string).
#cfg(target="js")
extern "js" fn js_stringify(v : @js.Value) -> String = "(v) => JSON.stringify(v)"

///|
/// Escape HTML special characters. Used for user messages (displayed
/// as escaped text, not rendered Markdown).
#cfg(target="js")
extern "js" fn js_escape_html(text : String) -> String = "(text) => { const div = document.createElement('div'); div.textContent = text; return div.innerHTML; }"

///|
/// Auto-resize a textarea to fit content (up to 150px max).
#cfg(target="js")
extern "js" fn js_auto_resize_textarea(id : String) = "(id) => { const el = document.getElementById(id); if (el) { el.style.height = 'auto'; el.style.height = Math.min(el.scrollHeight, 150) + 'px'; } }"

///| ── localStorage helpers ──────────────────────────────────────

///|
/// Read a value from `window.localStorage`. Returns the stored string
/// or `""` if the key is missing / unset.
#cfg(target="js")
extern "js" fn local_storage_get(key : String) -> String = "(key) => { try { return window.localStorage.getItem(key) || ''; } catch (e) { return ''; } }"

///|
/// Write a value to `window.localStorage`. Returns `false` on failure
/// (storage quota, private mode, etc.).
#cfg(target="js")
extern "js" fn local_storage_set(key : String, value : String) -> Bool = "(key, value) => { try { window.localStorage.setItem(key, value); return true; } catch (e) { return false; } }"

///|
/// `new Date().toISOString()` — used by the tasks panel to stamp
/// `created_at` / `completed_at` on each task.
#cfg(target="js")
extern "js" fn js_now_iso() -> String = "() => new Date().toISOString()"

///| ── HTTP (Task Pack D) ────────────────────────────────────────
/// Inline `fetch()` calls replace the former `API.get/post/put/del`
/// wrapper from `web/js/app.js`. The signatures return `@js.Promise`
/// which `.wait()`s to `@js.Value`; we round-trip via `JSON.stringify`
/// to get a MoonBit `Json` value.

///|
/// `GET path` -> parsed JSON response.
#cfg(target="js")
extern "js" fn api_get_promise(path : String) -> @js.Promise = "(path) => fetch(path).then(res => { if (!res.ok) throw new Error('HTTP ' + res.status); return res.json(); })"

///|
/// `POST path body_str` -> parsed JSON response. `body_str` is a JSON
/// string (serialized in MoonBit).
#cfg(target="js")
extern "js" fn api_post_promise(path : String, body_str : String) -> @js.Promise = "(path, body_str) => fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: body_str }).then(res => { if (!res.ok) throw new Error('HTTP ' + res.status); if (res.status === 204) return null; return res.json(); })"

///|
/// `DELETE path` -> parsed JSON response (or null for 204).
#cfg(target="js")
extern "js" fn api_del_promise(path : String) -> @js.Promise = "(path) => fetch(path, { method: 'DELETE' }).then(res => { if (!res.ok) throw new Error('HTTP ' + res.status); if (res.status === 204) return null; return res.json().catch(() => null); })"

///|
/// `PUT path body_str` -> parsed JSON response.
#cfg(target="js")
extern "js" fn api_put_promise(path : String, body_str : String) -> @js.Promise = "(path, body_str) => fetch(path, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: body_str }).then(res => { if (!res.ok) throw new Error('HTTP ' + res.status); return res.json(); })"

///|
/// `GET path` → parsed `Json`. Errors propagate as `raise`; callers
/// should wrap with `try .. catch` (or use `fetch_json_safe` from
/// `brand_cell.mbt`).
#cfg(target="js")
pub async fn api_get(path : String) -> Json {
  @json.parse(api_get_promise(path).wait().cast() |> js_stringify) catch {
    _ => Json::null()
  }
}

///|
/// `POST path body` → parsed `Json`. `body` is a `Json` value (use
/// `Json::object([...])` or similar to build it).
#cfg(target="js")
pub async fn api_post(path : String, body : Json) -> Json {
  @json.parse(api_post_promise(path, body.stringify()).wait().cast() |> js_stringify) catch {
    _ => Json::null()
  }
}

///|
/// `DELETE path` → parsed `Json` (or `null` if the server returns 204).
#cfg(target="js")
pub async fn api_del(path : String) -> Json {
  @json.parse(api_del_promise(path).wait().cast() |> js_stringify)
}

///|
/// `PUT path body` → parsed `Json`. `body` is a `Json` value.
#cfg(target="js")
pub async fn api_put(path : String, body : Json) -> Json {
  @json.parse(api_put_promise(path, body.stringify()).wait().cast() |> js_stringify)
}

///|
/// `fetch(path).then(r => r.text())` — used by the Share cell to export
/// a session in `format=md` (plain text body).
#cfg(target="js")
extern "js" fn api_get_text_promise(path : String) -> @js.Promise = "(path) => fetch(path).then(r => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.text(); })"

///|
/// `GET path` → response body as `String` (no JSON parsing). Throws if
/// the network layer rejects; callers wrap with `try`.
#cfg(target="js")
pub async fn api_get_text(path : String) -> String {
  api_get_text_promise(path).wait().cast()
}

///| ── URL / window helpers ──────────────────────────────────────

///|
/// `encodeURIComponent` for safe path segments. The MBOpenClacky skill
/// names in the legacy UI go through `encodeURIComponent`.
#cfg(target="js")
extern "js" fn js_encode_uri_component(s : String) -> String = "(s) => encodeURIComponent(s)"

///|
/// Normalise a raw URL string: trim, prepend `https://` when no
/// protocol is present, then validate with `new URL`. Returns
/// `(url, valid)`; `valid` is `false` when the value is empty or not
/// a parseable URL.
#cfg(target="js")
extern "js" fn js_normalize_url(raw : String) -> (String, Bool) = "(raw) => { let u = (raw || '').trim(); if (!u) return ['', false]; let lo = u.toLowerCase(); if (lo.indexOf('http://') !== 0 && lo.indexOf('https://') !== 0) u = 'https://' + u; try { new URL(u); return [u, true]; } catch (e) { return [u, false]; } }"

///|
/// Trigger a browser download of a data URL. Builds an `<a>` element,
/// sets `href` + `download`, clicks it.
#cfg(target="js")
extern "js" fn js_download_data_url(url : String, filename : String) = "(url, filename) => { const a = document.createElement('a'); a.href = url; a.download = filename; document.body.appendChild(a); a.click(); document.body.removeChild(a); }"

///|
/// Synchronous `window.confirm` for "are you sure?" prompts.
#cfg(target="js")
extern "js" fn window_confirm(msg : String) -> Bool = "(msg) => window.confirm(msg)"

///|
/// Read the current page origin (e.g. `https://app.example.com`) so
/// the Share cell can build an absolute share URL.
#cfg(target="js")
extern "js" fn js_origin() -> String = "() => window.location.origin"

///| ── i18n (Task Pack F) ────────────────────────────────────────
/// After Phase 4 the i18n dictionaries live in MoonBit `Map`s
/// (`i18n_dict_en.mbt`, `i18n_dict_zh.mbt`); the active locale is
/// stored in `localStorage` under `mbopenclacky_locale`.

///|
/// Read the current locale from `localStorage`. Returns `"en"` or
/// `"zh"`. Falls back to `"en"` if unset.
#cfg(target="js")
extern "js" fn i18n_get_locale() -> String = "() => localStorage.getItem('mbopenclacky_locale') || 'en'"

///|
/// Set the active locale: write to `localStorage` and dispatch
/// `i18n:locale-changed` so all rabbita cells can re-translate.
#cfg(target="js")
extern "js" fn i18n_set_locale(lang : String) = "(lang) => { localStorage.setItem('mbopenclacky_locale', lang); window.dispatchEvent(new CustomEvent('i18n:locale-changed', { detail: { locale: lang } })); }"

///|
/// Register a callback for the `i18n:locale-changed` CustomEvent
/// dispatched by `i18n_set_locale`. Used via `@cmd.custom_cmd` to feed
/// `scheduler.add` back into the cell's update loop.
#cfg(target="js")
extern "js" fn i18n_on_locale_changed(callback : () -> Unit) = "(callback) => window.addEventListener('i18n:locale-changed', () => callback())"

///|
/// Walk the DOM and re-translate all elements with `data-i18n`,
/// `data-i18n-placeholder`, or `data-i18n-title` attributes. The
/// MoonBit callback is invoked with the i18n key; it returns the
/// translated string.
#cfg(target="js")
extern "js" fn js_translate_dom(callback : (String) -> String) -> Unit = "(callback) => { document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = callback(el.getAttribute('data-i18n')); }); document.querySelectorAll('[data-i18n-placeholder]').forEach(el => { el.setAttribute('placeholder', callback(el.getAttribute('data-i18n-placeholder'))); }); document.querySelectorAll('[data-i18n-title]').forEach(el => { el.setAttribute('title', callback(el.getAttribute('data-i18n-title'))); }); }"

///| ── Session / Markdown / WebSocket helpers ─────────────────────

///|
/// Read the current session id from `window.__mbSessionId` (set by
/// chat_cell when a session loads). The Share cell reads this
/// synchronously on `Init`.
#cfg(target="js")
extern "js" fn js_current_session_id() -> String = "() => window.__mbSessionId || ''"

///|
/// Set the current session id (called by chat_cell when a session loads).
#cfg(target="js")
extern "js" fn js_set_current_session_id(id : String) -> Unit = "(id) => { window.__mbSessionId = id; }"

///|
/// Copy code to clipboard (used by rendered Markdown code blocks).
/// Resolves the nearest `<code>` element and writes its text content.
#cfg(target="js")
extern "js" fn js_copy_code(btn_id : String) -> Unit = "(btn_id) => { const btn = document.getElementById(btn_id) || (typeof event !== 'undefined' ? event.target : null); const codeBlock = btn && btn.closest && btn.closest('.code-block-header') && btn.closest('.code-block-header').nextElementSibling && btn.closest('.code-block-header').nextElementSibling.querySelector('code'); if (codeBlock) { navigator.clipboard.writeText(codeBlock.textContent).then(() => { btn.textContent = 'Copied!'; btn.classList.add('copied'); setTimeout(() => { btn.textContent = 'Copy'; btn.classList.remove('copied'); }, 2000); }); } }"

///|
/// Set innerHTML of a DOM element by ID. Used by bootstrap.mbt to
/// inject the sidebar + view containers.
#cfg(target="js")
extern "js" fn js_set_inner_html(id : String, html : String) -> Unit = "(id, html) => { const el = document.getElementById(id); if (el) el.innerHTML = html; }"

///| ── Shell (Task Pack E) ───────────────────────────────────────

///|
/// Dispatch an `app:show-view` CustomEvent so the shell_cell
/// (listening via `js_on_show_view`) can perform the view switch.
#cfg(target="js")
extern "js" fn app_show_view(view : String) = "(view) => { window.dispatchEvent(new CustomEvent('app:show-view', { detail: view })); }"

///|
/// Directly manipulate the DOM to show/hide views (replaces the
/// legacy `App.showView`).
#cfg(target="js")
extern "js" fn js_show_view(view : String) = "(view) => { document.querySelectorAll('.view').forEach(v => v.classList.remove('active')); const el = document.getElementById('view-' + view); if (el) el.classList.add('active'); }"

///|
/// Register a callback for the `app:show-view` CustomEvent.
#cfg(target="js")
extern "js" fn js_on_show_view(callback : (String) -> Unit) = "(callback) => { window.addEventListener('app:show-view', (e) => callback(e.detail || 'chat')); }"

///|
/// Bind click handlers to all sidebar nav buttons and close-panel
/// buttons. `callback(view_name)` is invoked when any button is
/// clicked. Also wires the sidebar toggle and main-content
/// close-sidebar-on-click.
#cfg(target="js")
extern "js" fn js_bind_nav_buttons(callback : (String) -> Unit) = "(callback) => { const navMap = { 'btn-settings': 'settings', 'btn-stats': 'stats', 'btn-mcp': 'mcp', 'btn-channels': 'channels', 'btn-schedules': 'schedules', 'btn-backups': 'backups', 'btn-billing': 'billing', 'btn-browser': 'browser', 'btn-git': 'git', 'btn-trash': 'trash', 'btn-brand': 'brand', 'btn-profile': 'profile', 'btn-share': 'share', 'btn-model-test': 'model-test', 'btn-workspace': 'workspace', 'btn-creator': 'creator', 'btn-version': 'version', 'btn-onboard': 'onboard', 'btn-tasks': 'tasks', 'btn-media': 'media', 'btn-marketplace': 'marketplace', 'btn-meeting': 'meeting' }; Object.entries(navMap).forEach(([id, view]) => { const el = document.getElementById(id); if (el) el.addEventListener('click', () => callback(view)); }); document.querySelectorAll('.btn-close-panel').forEach(btn => { btn.addEventListener('click', () => callback(btn.dataset.view || 'chat')); }); document.getElementById('sidebar-toggle')?.addEventListener('click', () => { document.getElementById('sidebar')?.classList.toggle('open'); }); document.getElementById('main-content')?.addEventListener('click', () => { document.getElementById('sidebar')?.classList.remove('open'); }); }"

///|
/// Listen for Escape key (close sidebar on mobile).
#cfg(target="js")
extern "js" fn js_on_key_escape(callback : () -> Unit) = "(callback) => { document.addEventListener('keydown', (e) => { if (e.key === 'Escape') callback(); }); }"

///|
/// Listen for Ctrl+N / Cmd+N (new session).
#cfg(target="js")
extern "js" fn js_on_key_ctrl_n(callback : () -> Unit) = "(callback) => { document.addEventListener('keydown', (e) => { if ((e.ctrlKey || e.metaKey) && e.key === 'n') { e.preventDefault(); callback(); } }); }"

///|
/// Close the sidebar (remove `open` class, for mobile).
#cfg(target="js")
extern "js" fn js_close_sidebar() = "() => { document.getElementById('sidebar')?.classList.remove('open'); }"

///|
/// Dispatch the `sessions:new-session` CustomEvent.
#cfg(target="js")
extern "js" fn js_dispatch_new_session() = "() => { window.dispatchEvent(new CustomEvent('sessions:new-session')); }"

///| ── Date helpers (trash / schedules) ──────────────────────────

///|
/// Parse a date string (epoch-seconds or ISO) and return a
/// relative-time label such as "5m ago" / "3h ago" / "2d ago" /
/// "2024-01-15" for older dates. Returns `"—"` if the value is
/// empty or unparseable.
#cfg(target="js")
extern "js" fn js_parse_date(value : String) -> String = "(v) => { if (!v) return '\u2014'; let date; if (/^\d+$/.test(v)) { date = new Date(parseInt(v) * 1000); } else { date = new Date(v); } if (isNaN(date.getTime())) return '\u2014'; const now = new Date(); const diffMs = now - date; const diffMin = Math.floor(diffMs / 60000); const diffHr = Math.floor(diffMs / 3600000); const diffDay = Math.floor(diffMs / 86400000); if (diffMin < 1) return 'just now'; if (diffMin < 60) return diffMin + 'm ago'; if (diffHr < 24) return diffHr + 'h ago'; if (diffDay < 7) return diffDay + 'd ago'; return date.toLocaleDateString(); }"

///|
/// Parse an expiry date and return `(text, expired)` — the relative
/// label and a flag indicating whether the item has already expired.
#cfg(target="js")
extern "js" fn js_format_expiry(value : String) -> (String, Bool) = "(v) => { if (!v) return ['\u2014', false]; let d; if (/^\d+$/.test(v)) { d = new Date(parseInt(v) * 1000); } else { d = new Date(v); } if (isNaN(d.getTime())) return ['\u2014', false]; const now = new Date(); const diffMs = d - now; const diffDays = Math.ceil(diffMs / 86400000); if (diffDays < 0) return ['Expired', true]; if (diffDays === 0) return ['Expires today', false]; if (diffDays === 1) return ['1 day left', false]; return [diffDays + ' days left', false]; }"

///| ── Markdown rendering (chat_cell) ────────────────────────────

///|
/// Render Markdown to HTML using marked.js + highlight.js + KaTeX.
/// Inlines the `Chat.renderMarkdown()` logic from `web/js/chat.js`.
#cfg(target="js")
extern "js" fn js_render_markdown(text : String) -> String = "(text) => { if (!text) return ''; if (typeof marked !== 'undefined') { marked.setOptions({ breaks: true, gfm: true, highlight: function(code, lang) { if (typeof hljs !== 'undefined') { if (lang && hljs.getLanguage(lang)) { try { return hljs.highlight(code, { language: lang }).value; } catch(e){} } try { return hljs.highlightAuto(code).value; } catch(e){} } return code; } }); let html = marked.parse(text); html = html.replace(/<pre><code(?:\s+class=\"language-(\w+)\")?>([^]*)<\/code><\/pre>/g, function(match, lang, code) { const langLabel = lang || 'code'; return '<div class=\"code-block-header\"><span>' + langLabel + '</span><button class=\"btn-copy-code\" onclick=\"mbCopyCode(this)\">Copy</button></div><pre><code class=\"' + (lang ? 'language-' + lang : '') + '\">' + code + '</code></pre>'; }); if (typeof katex !== 'undefined') { html = html.replace(/\$\$([\s\S]+?)\$\$/g, function(_, tex) { try { return katex.renderToString(tex.trim(), { displayMode: true, throwOnError: false }); } catch(e) { return '<span style=\"color:var(--danger)\">' + tex + '</span>'; } }); html = html.replace(/\$([^\$\n]+?)\$/g, function(_, tex) { try { return katex.renderToString(tex.trim(), { displayMode: false, throwOnError: false }); } catch(e) { return '<code>' + tex + '</code>'; } }); } return html; } let html = text.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); html = html.replace(/```(\w*)\n([\s\S]*?)```/g, function(_, lang, code) { return '<pre><code>' + code + '</code></pre>'; }); html = html.replace(/`([^`]+)`/g, '<code>$1</code>'); html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>'); html = html.replace(/\*(.+?)\*/g, '<em>$1</em>'); html = html.replace(/\n/g, '<br>'); return html; }"

///| ── SSE streaming (chat_cell) ──────────────────────────────────

///|
/// Start SSE streaming for a chat message. Uses `fetch(POST) +
/// ReadableStream.getReader()` to read the response stream chunk by
/// chunk. Each SSE event is JSON-decoded; the resulting object is
/// re-serialized and passed to `on_chunk`. On stream end, `on_done` is
/// called. On error, `on_error` is called with the error message.
#cfg(target="js")
extern "js" fn js_connect_sse(session_id : String, message : String, on_chunk : (String) -> Unit, on_done : () -> Unit, on_error : (String) -> Unit) = "(sessionId, message, onChunk, onDone, onError) => { const url = '/api/sessions/' + sessionId + '/chat/stream'; fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ message: message }) }).then(function(response) { if (!response.ok) { response.json().catch(function() { return {}; }).then(function(err) { onError(err.error || ('HTTP ' + response.status)); }); return; } const reader = response.body.getReader(); const decoder = new TextDecoder(); let buffer = ''; function processSSE(buf) { const lines = buf.split('\n'); let eventType = 'message'; let data = ''; for (let i = 0; i < lines.length; i++) { const line = lines[i]; if (line.startsWith('event: ')) { eventType = line.slice(7).trim(); } else if (line.startsWith('data: ')) { data += (data ? '\n' : '') + line.slice(6); } else if (line === 'data:') { data += '\n'; } } if (data) { try { const parsed = JSON.parse(data); onChunk(JSON.stringify(Object.assign({ type: eventType }, parsed))); } catch(e) { onChunk(JSON.stringify({ type: eventType, raw: data })); } } } async function read() { while (true) { const r = await reader.read(); if (r.done) { if (buffer.trim()) processSSE(buffer); onDone(); break; } buffer += decoder.decode(r.value, { stream: true }); const parts = buffer.split('\n\n'); buffer = parts.pop() || ''; for (let i = 0; i < parts.length; i++) { const part = parts[i]; if (part.trim()) processSSE(part); } } } read().catch(function(err) { if (err.name !== 'AbortError') onError(err.message || 'Stream error'); }); }).catch(function(err) { onError(err.message || 'Network error'); }); }"

///|
/// Cancel an in-progress generation by POSTing to the cancel endpoint.
#cfg(target="js")
extern "js" fn js_cancel_generation(session_id : String) = "(sessionId) => { fetch('/api/sessions/' + sessionId + '/cancel', { method: 'POST' }).catch(function() {}); }"

///|
/// Scroll the `#chat-messages` container to the bottom.
#cfg(target="js")
extern "js" fn js_scroll_chat_to_bottom() = "() => { const c = document.getElementById('chat-messages'); if (c) { requestAnimationFrame(function() { c.scrollTop = c.scrollHeight; }); } }"

///| ── Session event plumbing (chat/sessions cells) ──────────────

///|
/// Dispatch a `chat:session-changed` CustomEvent so the chat_cell can
/// react to a session switch or creation initiated by the sessions_cell.
#cfg(target="js")
extern "js" fn js_dispatch_session_changed(session_id : String, session_name : String) = "(sessionId, sessionName) => { window.dispatchEvent(new CustomEvent('chat:session-changed', { detail: { sessionId: sessionId, sessionName: sessionName } })); }"

///|
/// Register a callback for the `chat:session-changed` CustomEvent.
#cfg(target="js")
extern "js" fn js_on_session_changed(callback : (String, String) -> Unit) = "(callback) => { window.addEventListener('chat:session-changed', function(e) { const d = e.detail || {}; callback(d.sessionId || '', d.sessionName || ''); }); }"

///|
/// Dispatch a `sessions:refresh` CustomEvent so the sessions_cell can
/// reload its list.
#cfg(target="js")
extern "js" fn js_dispatch_sessions_refresh() = "() => { window.dispatchEvent(new CustomEvent('sessions:refresh', {})); }"

///|
/// Register a callback for the `sessions:refresh` CustomEvent.
#cfg(target="js")
extern "js" fn js_on_sessions_refresh(callback : () -> Unit) = "(callback) => { window.addEventListener('sessions:refresh', function() { callback(); }); }"

///|
/// Register a callback for the `sessions:new-session` CustomEvent
/// dispatched by shell_cell on Ctrl+N.
#cfg(target="js")
extern "js" fn js_on_new_session(callback : () -> Unit) = "(callback) => { window.addEventListener('sessions:new-session', function() { callback(); }); }"

///|
/// Build the WebSocket URL for a session. Uses the page protocol/host.
#cfg(target="js")
extern "js" fn js_ws_url(session_id : String) -> String = "(sessionId) => { const proto = location.protocol === 'https:' ? 'wss:' : 'ws:'; return proto + '//' + location.host + '/ws/sessions/' + sessionId; }"

///|
/// Register click + input handlers for the sidebar session controls
/// (`#btn-new-session` and `#session-search`).
#cfg(target="js")
extern "js" fn js_register_sessions_controls(on_new : () -> Unit, on_search : (String) -> Unit) = "(onNew, onSearch) => { const btn = document.getElementById('btn-new-session'); if (btn) btn.addEventListener('click', function() { onNew(); }); const search = document.getElementById('session-search'); if (search) search.addEventListener('input', function(e) { onSearch(e.target.value); }); }"

///| ── Skill editor (creator → skills) ───────────────────────────

///|
/// Dispatch a `skill:open-editor` CustomEvent so the skills rabbita cell
/// can open the editor for the given skill name.
#cfg(target="js")
extern "js" fn skill_editor_open(name : String) = "(name) => { window.dispatchEvent(new CustomEvent('skill:open-editor', { detail: { name: name } })); }"

///|
/// Register a callback for the `skill:open-editor` CustomEvent.
#cfg(target="js")
extern "js" fn on_skill_open_editor(callback : (String) -> Unit) = "(callback) => { window.addEventListener('skill:open-editor', function(e) { const name = (e.detail && e.detail.name) || ''; if (name) callback(name); }); }"

///| ── Code editor (CodeMirror 6) ────────────────────────────────
/// Pushed by `web/mb/public/editor.js` (loaded as an ES module in
/// `index.html`). No-op when the editor host is not yet mounted, so it is
/// safe to call from a cell `update` before the DOM node exists — the loader
/// reads the bound <textarea> value on first mount.

///|
#cfg(target="js")
extern "js" fn cm_set_doc(id : String, value : String) -> Unit = "(id, value) => { if (window.MBEditor) window.MBEditor.setDoc(id, value); }"
