///| Browser Control panel - rabbita replacement for `web/js/browser.js`.
///
/// Renders the browser-automation panel into `#browser-content` (a
/// child of `#view-browser .view-content`). Talks to the existing
/// backend at `/api/browser/*` via the `safe_get` / `safe_post`
/// bridges from `bridge.mbt`.
///
/// Behaviour parity with `web/js/browser.js`:
///   - On mount, `GET /api/browser/status`; render a status badge
///     (Running/Stopped) plus the daemon endpoint URL.
///   - `Start` / `Stop` issue `POST /api/browser/{start,stop}` then
///     re-fetch status.
///   - `Navigate`: text input + `Go`; the URL is normalised (prepend
///     `https://`, validate with `new URL`) then `POST
///     /api/browser/navigate {url}`.
///   - `Screenshot`: `GET /api/browser/screenshot`; the base64 payload
///     is rendered as `<img src="data:image/png;base64,...">`. A
///     Download button saves the current frame.
///   - `Auto-refresh (5s)`: a toggle that, while on and the daemon is
///     running, re-fetches a screenshot every 5 s via a rabbita
///     `@sub.every` subscription.
///
/// Deviations from the legacy code (intentional):
///   - **Reads `daemon_running` / `endpoint`, not `running` / `url`.**
///     The legacy `browser.js` read `status.running` and `status.url`,
///     but `BrowserStatus` (lib/server/browser_types.mbt) serialises
///     `daemon_running` and `endpoint` - so the legacy panel always
///     showed "Stopped" with no URL. The cell reads the correct fields
///     so the panel actually reflects daemon state.
///   - **Auto-refresh is a declarative `@sub.every` subscription**,
///     not an imperative `setInterval`. rabbita starts/stops the timer
///     automatically as `auto_refresh` and `running` change.
///   - **Download is an FFI call**, not a manual DOM `<a>` click.
///   - **i18n is hard-coded in English** (spec R5, same as every other
///     migrated panel).
///   - **No `innerHTML` rewrite.** The rabbita view is a pure function
///     of the model.

///|
/// All `cmd` types are referenced via fully-qualified `@cmd.X` and all
/// top-level fns are prefixed with `br_` to avoid clashes with the
/// other cells that share the same moon package.

///|
priv struct BrowserModel {
  /// `true` while the browser daemon reports `daemon_running`.
  running : Bool
  /// Daemon endpoint URL (e.g. `http://127.0.0.1:9222`), or `""`.
  url : String
  /// `true` once the initial status fetch resolves.
  loaded : Bool
  /// `""` when idle, else `"starting"` / `"stopping"` / `"navigating"`
  /// / `"screenshot"` to drive button disabled + label state.
  busy : String
  /// Current text in the navigate input.
  nav_input : String
  /// Base64 PNG data of the last screenshot, or `""` when none.
  screenshot : String
  /// Last screenshot fetch error (empty when idle/ok).
  screenshot_error : String
  /// Auto-refresh toggle state.
  auto_refresh : Bool
  /// Last user-facing error (start/stop/navigate failures).
  error : String
  locale : String
}

///|
enum BrowserMsg {
  Init
  StatusLoaded(Result[Json, String])
  ClickStart
  ClickStop
  StartDone(Result[Json, String])
  StopDone(Result[Json, String])
  NavInputChanged(String)
  ClickNavigate
  NavigateDone(Result[Json, String])
  ClickScreenshot
  ScreenshotDone(Result[Json, String])
  ToggleAutoRefresh
  AutoRefreshTick
  ClickDownload
  LocaleChanged
}

///|
fn initial_browser_model() -> BrowserModel {
  {
    running: false,
    url: "",
    loaded: false,
    busy: "",
    nav_input: "",
    screenshot: "",
    screenshot_error: "",
    auto_refresh: false,
    error: "",
    locale: "",
  }
}

// ── helpers ──────────────────────────────────────────────────

///|
/// Decode the `/api/browser/status` JSON into `(running, url, error)`.
/// Reads `daemon_running` / `endpoint` / `last_error` (the real field
/// names from `BrowserStatus`); see the file header for why.
fn br_parse_status(json : Json) -> (Bool, String, String) {
  match json {
    Object(map) => {
      let running = match map.get("daemon_running") {
        Some(True) => true
        _ => false
      }
      let url = match map.get("endpoint") {
        Some(String(s)) => s
        _ => ""
      }
      let err = match map.get("last_error") {
        Some(String(s)) => s
        _ => ""
      }
      (running, url, err)
    }
    _ => (false, "", "")
  }
}

///|
/// Pull the base64 image payload out of a screenshot response. Mirrors
/// the legacy `data.image || data.data || data` fallback.
fn br_extract_screenshot(json : Json) -> String {
  match json {
    Object(map) =>
      match map.get("image") {
        Some(String(s)) => s
        _ =>
          match map.get("data") {
            Some(String(s)) => s
            _ => ""
          }
      }
    String(s) => s
    _ => ""
  }
}

///|
/// Fire a `GET /api/browser/status` and feed the result back as
/// `StatusLoaded`. Used on mount and after start/stop complete.
fn br_fetch_status(emit : @cmd.Emit[BrowserMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(StatusLoaded(r)), async fn() noraise {
    safe_get("/api/browser/status")
  })
}

///|
/// Fire a `GET /api/browser/screenshot` and feed the result back as
/// `ScreenshotDone`.
fn br_fetch_screenshot(emit : @cmd.Emit[BrowserMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(ScreenshotDone(r)), async fn() noraise {
    safe_get("/api/browser/screenshot")
  })
}

///|
/// Build the JSON body for `/api/browser/navigate`: `{ "url": "..." }`.
fn br_navigate_body(url : String) -> Json {
  Json::object(Map::of([("url", Json::string(url))]))
}

// ── update ───────────────────────────────────────────────────

///|
fn browser_update(
  emit : @cmd.Emit[BrowserMsg],
  msg : BrowserMsg,
  model : BrowserModel,
) -> (@cmd.Cmd, BrowserModel) {
  match msg {
    Init =>
      (
        @cmd.batch([
          br_fetch_status(emit),
          locale_change_cmd(emit, LocaleChanged),
        ]),
        { ..model, locale: i18n_get_locale() },
      )
    StatusLoaded(Err(e)) => (@cmd.none, { ..model, loaded: true, error: e })
    StatusLoaded(Ok(json)) => {
      let (running, url, err) = br_parse_status(json)
      (@cmd.none, { ..model, running, url, loaded: true, error: err })
    }
    ClickStart =>
      if model.running || model.busy != "" {
        (@cmd.none, model)
      } else {
        (
          @cmd.perform(r => emit(StartDone(r)), async fn() noraise {
            safe_post("/api/browser/start", Json::object(Map::of([])))
          }),
          { ..model, busy: "starting" },
        )
      }
    ClickStop =>
      if not(model.running) || model.busy != "" {
        (@cmd.none, model)
      } else {
        (
          @cmd.perform(r => emit(StopDone(r)), async fn() noraise {
            safe_post("/api/browser/stop", Json::object(Map::of([])))
          }),
          { ..model, busy: "stopping" },
        )
      }
    StartDone(Err(e)) => {
      app_notify(t1("browser.failed_start", "error", e), "error")
      (@cmd.none, { ..model, busy: "" })
    }
    StartDone(Ok(_)) => (br_fetch_status(emit), { ..model, busy: "" })
    StopDone(Err(e)) => {
      app_notify(t1("browser.failed_stop", "error", e), "error")
      (@cmd.none, { ..model, busy: "" })
    }
    StopDone(Ok(_)) => (br_fetch_status(emit), { ..model, busy: "" })
    NavInputChanged(s) => (@cmd.none, { ..model, nav_input: s })
    ClickNavigate =>
      if not(model.running) || model.busy == "navigating" {
        (@cmd.none, model)
      } else {
        let (url, valid) = js_normalize_url(model.nav_input)
        if not(valid) {
          app_notify(t("browser.invalid_url"), "warning")
          (@cmd.none, model)
        } else {
          (
            @cmd.perform(r => emit(NavigateDone(r)), async fn() noraise {
              safe_post("/api/browser/navigate", br_navigate_body(url))
            }),
            { ..model, busy: "navigating" },
          )
        }
      }
    NavigateDone(Err(e)) => {
      app_notify(e, "error")
      (@cmd.none, { ..model, busy: "" })
    }
    NavigateDone(Ok(_)) => {
      app_notify(t1("browser.navigated", "url", model.nav_input), "success")
      (@cmd.none, { ..model, busy: "" })
    }
    ClickScreenshot =>
      if not(model.running) || model.busy == "screenshot" {
        (@cmd.none, model)
      } else {
        (br_fetch_screenshot(emit), { ..model, busy: "screenshot" })
      }
    ScreenshotDone(Err(e)) =>
      (@cmd.none, { ..model, busy: "", screenshot_error: e, screenshot: "" })
    ScreenshotDone(Ok(json)) => {
      let data = br_extract_screenshot(json)
      let m = if data == "" {
        { ..model, busy: "", screenshot_error: t("browser.no_image") }
      } else {
        { ..model, busy: "", screenshot: data, screenshot_error: "" }
      }
      (@cmd.none, m)
    }
    ToggleAutoRefresh =>
      (@cmd.none, { ..model, auto_refresh: not(model.auto_refresh) })
    // Periodic tick from @sub.every: refresh the screenshot while the
    // daemon is running. Doesn't touch `busy` so a manual capture can
    // run concurrently without flickering the buttons.
    AutoRefreshTick =>
      if model.running && model.busy != "screenshot" {
        (br_fetch_screenshot(emit), model)
      } else {
        (@cmd.none, model)
      }
    ClickDownload =>
      if model.screenshot == "" {
        (@cmd.none, model)
      } else {
        js_download_data_url(
          "data:image/png;base64," + model.screenshot,
          "screenshot.png",
        )
        (@cmd.none, model)
      }
    LocaleChanged => (@cmd.none, { ..model, locale: i18n_get_locale() })
  }
}

// ── subscriptions ────────────────────────────────────────────

///|
/// While auto-refresh is on and the daemon is running, re-fetch a
/// screenshot every 5 s. rabbita re-evaluates this on every model
/// change, so toggling off (or the daemon stopping) cancels the timer.
fn browser_subscriptions(
  emit : @cmd.Emit[BrowserMsg],
  model : BrowserModel,
) -> @sub.Sub {
  if model.auto_refresh && model.running {
    @sub.every(5000, emit(AutoRefreshTick))
  } else {
    @sub.none
  }
}

// ── view ─────────────────────────────────────────────────────

///|
fn browser_view(
  emit : @cmd.Emit[BrowserMsg],
  model : BrowserModel,
) -> @html.Html {
  @html.div(class="settings-group", [
    br_status_card(model),
    br_controls_card(emit, model),
    br_screenshot_card(emit, model),
  ])
}

///|
fn br_status_card(model : BrowserModel) -> @html.Html {
  let (status_text, badge_cls, badge_style) = if model.running {
    (t("browser.running"), "status-badge running", ([] : Array[String]))
  } else {
    (
      t("browser.stopped"),
      "status-badge",
      ["background:rgba(247,118,142,0.15)", "color:var(--danger)"],
    )
  }
  let url_line = if model.url == "" {
    @html.text("")
  } else {
    @html.text(t("browser.url_prefix") + model.url)
  }
  @html.div(
    class="stat-card",
    style=["margin-bottom:20px", "text-align:left", "padding:20px"],
    [
      @html.div(class="settings-group-title", [
        @html.text(t("browser.status_title")),
      ]),
      @html.div(
        style=[
          "display:flex", "align-items:center", "gap:16px", "margin-bottom:12px",
        ],
        [
          @html.span(
            class=badge_cls,
            style=badge_style,
            @html.text(status_text),
          ),
        ],
      ),
      @html.div(style=["font-size:12px", "color:var(--text-muted)"], [url_line]),
    ],
  )
}

///|
fn br_controls_card(
  emit : @cmd.Emit[BrowserMsg],
  model : BrowserModel,
) -> @html.Html {
  let start_disabled = model.running || model.busy == "starting"
  let stop_disabled = not(model.running) || model.busy == "stopping"
  let start_label = if model.busy == "starting" {
    t("browser.starting")
  } else {
    t("browser.start")
  }
  let stop_label = if model.busy == "stopping" {
    t("browser.stopping")
  } else {
    t("browser.stop")
  }
  let go_disabled = not(model.running) || model.busy == "navigating"
  let go_label = if model.busy == "navigating" {
    "..."
  } else {
    t("browser.go")
  }
  @html.div(
    class="stat-card",
    style=["margin-bottom:20px", "text-align:left", "padding:20px"],
    [
      @html.div(class="settings-group-title", [
        @html.text(t("browser.controls")),
      ]),
      @html.div(style=["display:flex", "gap:8px", "margin-bottom:16px"], [
        @html.button(
          class="btn btn-primary",
          on_click=emit(ClickStart),
          disabled=start_disabled,
          @html.text(start_label),
        ),
        @html.button(
          class="btn btn-danger",
          on_click=emit(ClickStop),
          disabled=stop_disabled,
          @html.text(stop_label),
        ),
      ]),
      @html.div(class="settings-group-title", style=["margin-top:16px"], [
        @html.text(t("browser.navigate")),
      ]),
      @html.div(style=["display:flex", "gap:8px"], [
        @html.input(
          input_type=@html.Text,
          placeholder="https://example.com",
          value=model.nav_input,
          on_input=s => emit(NavInputChanged(s)),
          style=[
            "flex:1", "padding:9px 12px", "background:var(--bg-tertiary)", "border:1px solid var(--border)",
            "border-radius:var(--radius-sm)", "color:var(--text-primary)", "font-size:13px",
            "outline:none",
          ],
        ),
        @html.button(
          class="btn btn-primary",
          on_click=emit(ClickNavigate),
          disabled=go_disabled,
          @html.text(go_label),
        ),
      ]),
    ],
  )
}

///|
fn br_screenshot_card(
  emit : @cmd.Emit[BrowserMsg],
  model : BrowserModel,
) -> @html.Html {
  let ss_disabled = not(model.running) || model.busy == "screenshot"
  let toggle_cls = if model.auto_refresh { "toggle active" } else { "toggle" }
  let preview = if model.screenshot == "" {
    if model.screenshot_error == "" {
      @html.span(class="text-muted", @html.text(t("browser.no_screenshot")))
    } else {
      @html.span(class="text-danger", @html.text(model.screenshot_error))
    }
  } else {
    @html.img(
      src="data:image/png;base64," + model.screenshot,
      alt=t("browser.screenshot"),
      style=["max-width:100%", "height:auto", "display:block"],
    )
  }
  let download_btn = if model.screenshot == "" {
    ([] : Array[@html.Html])
  } else {
    [
      @html.button(
        class="btn btn-ghost btn-sm",
        on_click=emit(ClickDownload),
        @html.text(t("browser.download")),
      ),
    ]
  }
  @html.div(class="stat-card", style=["text-align:left", "padding:20px"], [
    @html.div(class="settings-group-title", [
      @html.text(t("browser.screenshot")),
    ]),
    @html.div(
      style=[
        "display:flex", "gap:8px", "align-items:center", "margin-bottom:16px",
      ],
      [
        @html.button(
          class="btn btn-primary",
          on_click=emit(ClickScreenshot),
          disabled=ss_disabled,
          @html.text(t("browser.take_screenshot")),
        ),
        @html.div(
          class="toggle-wrapper",
          style=["flex:1", "display:flex", "align-items:center", "gap:8px"],
          [
            @html.span(
              style=["font-size:13px", "color:var(--text-primary)"],
              @html.text(t("browser.auto_refresh")),
            ),
            @html.div(
              class=toggle_cls,
              on_click=emit(ToggleAutoRefresh),
              ([] : Array[@html.Html]),
            ),
          ],
        ),
      ],
    ),
    @html.div(
      style=[
        "min-height:200px", "background:var(--bg-tertiary)", "border:1px solid var(--border)",
        "border-radius:var(--radius)", "display:flex", "align-items:center", "justify-content:center",
        "overflow:hidden",
      ],
      [preview],
    ),
    @html.div(style=["margin-top:8px", "display:flex", "gap:8px"], download_btn),
  ])
}

// ── factory ──────────────────────────────────────────────────

///|
fn build_browser_cell() -> (@cmd.Emit[BrowserMsg], @rabbita.Cell) {
  @rabbita.cell_with_emit(
    model=initial_browser_model(),
    update=browser_update,
    view=browser_view,
    subscriptions=browser_subscriptions,
  )
}
