///| Share panel — rabbita replacement for `web/js/share.js`.
///
/// Renders the export / share-link form into `#share-content` (a child of
/// `#view-share .view-content`). Talks to the existing MBOpenClacky
/// backend at `/api/sessions/:id/export` via a new `api_get_text`
/// bridge in `bridge.mbt` (text body for `format=md`) plus the
/// `safe_get` JSON bridge (for `format=json`).
///
/// Behaviour parity with `web/js/share.js`:
///   - On mount, read `App.currentSessionId` to discover the active
///     session; render the export / copy-link sections.
///   - Export the session in `md` (plain text) or `json` (parsed JSON
///     re-stringified for display) format; show the result in a `<pre>`
///     block under the form.
///   - Copy the share link (`{origin}/share/{session_id}`) to the
///     clipboard via `navigator.clipboard.writeText`.
///
/// Deviations from the legacy code (intentional):
///   - **QR code rendering is omitted.** The legacy code calls
///     `QRCode.toCanvas` from a CDN global (`qrcode@1.5.4`) and threads
///     the resulting `<canvas>` into a container; that requires DOM
///     side-effects on mount. We render a plain `<code>` link in its
///     place; the URL is still scannable by the user manually.
///   - **Download is omitted.** The legacy code wraps the rendered
///     `<pre>` content in a `Blob` and triggers a hidden `<a>` click;
///     that uses the DOM as a side-channel. The export text is still
///     visible and copy-pasteable. A future Phase 3+ could add a
///     `js_download_text` FFI when the spec calls for it.
///   - **i18n is hard-coded in English** (spec R5, same as
///     `profile_cell.mbt`).
///   - **Only `format=md` uses the new text bridge**; `format=json`
///     reuses `safe_get` and the `ExportResult` is then stringified
///     with `.stringify(indent=2)`.

///|
/// All `cmd` types are referenced via fully-qualified `@cmd.X` and all
/// top-level fns are prefixed with `share_` to avoid clashes with the
/// brand / backups / version / profile cells which share the same moon
/// package. All HTML constructors are fully qualified to avoid
/// "toplevel identifier declared twice" with the other cells' imports.

///|
enum ShareMsg {
  /// Mount-time signal: read `App.currentSessionId` into the model.
  Init
  /// User picked a new export format.
  FormatChanged(String)
  /// User clicked "Export".
  ClickExport
  /// Export result (always stored as a String so md and json can share
  /// one field; json is pretty-printed with `Json::stringify(indent=2)`).
  ExportDone(Result[String, String])
  /// User clicked "Copy Share Link".
  ClickCopyLink
  /// Result of the clipboard write.
  CopyDone(Result[Unit, String])
  LocaleChanged
}

///|
priv struct ShareModel {
  /// `App.currentSessionId` at mount time; "" if no session is active.
  session_id : String
  /// "md" | "json".
  format : String
  /// Disables Export / Copy buttons while a request is in flight.
  busy : Bool
  /// Last export result (empty when no export has been done yet).
  result : String
  /// User-facing error message (empty when idle).
  error : String
  /// Whether the last Copy succeeded (button briefly says "Copied!").
  copy_success : Bool
  locale : String
}

///|
fn initial_share_model() -> ShareModel {
  {
    session_id: "",
    format: "md",
    busy: false,
    result: "",
    error: "",
    copy_success: false,
    locale: "",
  }
}

///|
fn share_export_cmd(
  emit : @cmd.Emit[ShareMsg],
  session_id : String,
  format : String,
) -> @cmd.Cmd {
  let path = "/api/sessions/" +
    js_encode_uri_component(session_id) +
    "/export?format=" +
    format
  if format == "md" {
    @cmd.perform(r => emit(ExportDone(r)), async fn() noraise {
      Ok(api_get_text(path)) catch {
        e => Err(e.to_string())
      }
    })
  } else {
    @cmd.perform(
      r => {
        let s : Result[String, String] = match r {
          Ok(json) => Ok((json : Json).stringify(indent=2))
          Err(e) => Err(e)
        }
        emit(ExportDone(s))
      },
      async fn() noraise { safe_get(path) },
    )
  }
}

///|
fn share_copy_cmd(emit : @cmd.Emit[ShareMsg], url : String) -> @cmd.Cmd {
  @clipboard.copy(@clipboard.Text(url), copied=emit(CopyDone(Ok(()))), failed=e => {
    emit(CopyDone(Err(e)))
  })
}

///|
fn share_update(
  emit : @cmd.Emit[ShareMsg],
  msg : ShareMsg,
  model : ShareModel,
) -> (@cmd.Cmd, ShareModel) {
  match msg {
    Init =>
      (
        @cmd.batch([locale_change_cmd(emit, LocaleChanged)]),
        {
          ..model,
          session_id: js_current_session_id(),
          locale: i18n_get_locale(),
        },
      )
    FormatChanged(v) => (@cmd.none, { ..model, format: v })
    ClickExport =>
      if model.session_id == "" {
        app_notify(t("share.select_session_export"), "warning")
        (@cmd.none, model)
      } else {
        (
          share_export_cmd(emit, model.session_id, model.format),
          { ..model, busy: true, error: "", result: "" },
        )
      }
    ExportDone(Ok(s)) =>
      (@cmd.none, { ..model, busy: false, result: s, error: "" })
    ExportDone(Err(e)) => {
      app_notify(t1("share.export_failed", "error", e), "error")
      (@cmd.none, { ..model, busy: false, error: e })
    }
    ClickCopyLink =>
      if model.session_id == "" {
        app_notify(t("share.select_session_first"), "warning")
        (@cmd.none, model)
      } else {
        let url = js_origin() + "/share/" + model.session_id
        (share_copy_cmd(emit, url), { ..model, busy: true })
      }
    CopyDone(Ok(_)) => {
      app_notify(t("share.link_copied_notif"), "success")
      (@cmd.none, { ..model, busy: false, copy_success: true })
    }
    CopyDone(Err(e)) => {
      app_notify(t1("share.copy_failed", "error", e), "error")
      (@cmd.none, { ..model, busy: false, error: e })
    }
    LocaleChanged => (@cmd.none, { ..model, locale: i18n_get_locale() })
  }
}

///|
fn share_view(emit : @cmd.Emit[ShareMsg], model : ShareModel) -> @html.Html {
  let has_session = model.session_id != ""
  let export_button = if model.busy {
    @html.button(class="btn btn-primary", disabled=true, t("share.exporting"))
  } else {
    @html.button(
      class="btn btn-primary",
      on_click=emit(ClickExport),
      t("share.export"),
    )
  }
  let copy_button = if model.busy {
    @html.button(class="btn btn-ghost", disabled=true, t("share.copying"))
  } else if model.copy_success {
    @html.button(class="btn btn-ghost", disabled=true, t("share.copied"))
  } else {
    @html.button(
      class="btn btn-ghost",
      on_click=emit(ClickCopyLink),
      t("share.copy_link"),
    )
  }
  let session_info = if has_session {
    @html.div(class="settings-field", [
      @html.label(for_="share-session", [@html.span(t("share.session"))]),
      @html.div(class="text-muted", [@html.span(model.session_id)]),
    ])
  } else {
    @html.p(class="text-muted", [
      @html.span(t("share.select_session_export_hint")),
    ])
  }
  let format_select = @html.select(
    id="share-format",
    on_change=s => emit(FormatChanged(s)),
    [
      @html.option(value="md", selected=model.format == "md", [
        @html.span(t("share.format_md")),
      ]),
      @html.option(value="json", selected=model.format == "json", [
        @html.span(t("share.format_json")),
      ]),
    ],
  )
  let result_block = if model.result.length() > 0 {
    @html.div(id="share-result", class="settings-group", [
      @html.div(class="settings-group-title", [
        @html.span(t("share.export_result")),
      ]),
      @html.pre(
        style=[
          "background:var(--bg-tertiary)", "padding:12px", "border-radius:var(--radius-sm)",
          "font-size:12px", "font-family:var(--font-mono)", "overflow-x:auto", "white-space:pre-wrap",
          "max-height:400px", "overflow-y:auto",
        ],
        [@html.span(model.result)],
      ),
    ])
  } else {
    @html.nothing
  }
  let error_block = if model.error.length() > 0 {
    @html.p(class="text-muted share-error", [@html.span(model.error)])
  } else {
    @html.nothing
  }
  let link_url = if has_session {
    js_origin() + "/share/" + model.session_id
  } else {
    ""
  }
  let link_block = if has_session {
    @html.div(
      style=[
        "display:flex", "align-items:center", "gap:8px", "padding:8px", "background:var(--bg-tertiary)",
        "border-radius:var(--radius-sm)",
      ],
      [
        @html.code(style=["font-size:12px", "word-break:break-all", "flex:1"], [
          @html.span(link_url),
        ]),
        copy_button,
      ],
    )
  } else {
    @html.p(class="text-muted", [@html.span(t("share.select_session_hint"))])
  }
  @html.div(class="share-panel", [
    @html.div(class="settings-group", [
      @html.div(class="settings-group-title", [
        @html.span(t("share.export_session")),
      ]),
      session_info,
      if has_session {
        @html.div(class="settings-field", [
          @html.label(for_="share-format", [
            @html.span(t("share.export_format")),
          ]),
          format_select,
          @html.div(class="help-text", [
            @html.span(t("share.export_format_help")),
          ]),
        ])
      } else {
        @html.nothing
      },
      if has_session {
        @html.div(style=["display:flex", "gap:8px", "margin-top:12px"], [
          export_button,
        ])
      } else {
        @html.nothing
      },
    ]),
    result_block,
    @html.div(class="settings-group", [
      @html.div(class="settings-group-title", [
        @html.span(t("share.share_link_title")),
      ]),
      link_block,
    ]),
    error_block,
  ])
}

///|
/// Factory used by `main.mbt`. Returns the `(emit, cell)` pair from
/// `cell_with_emit`; `main.mbt` then wires `emit(Init)` as the
/// mount-time command via `app.with_init`.
fn build_share_cell() -> (@cmd.Emit[ShareMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_share_model(),
    update=share_update,
    view=share_view,
  )
}
