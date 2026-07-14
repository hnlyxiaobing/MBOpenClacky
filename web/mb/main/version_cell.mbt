///| Version panel — rabbita replacement for `web/js/versions.js`.
///
/// Renders the current-version / update-available block into the
/// `#version-content` container mounted by `main.mbt`. State is fetched
/// from the existing MBOpenClacky backend at `/api/version` and the
/// upgrade endpoints via the `api_get / api_post` bridges in
/// `bridge.mbt`, which forward to the `API` wrapper in `web/js/app.js:6`.
///
/// Behaviour parity with `web/js/versions.js`:
///   - On mount, fetch version (GET /api/version).
///   - Check for updates (POST /api/version/check); if available, show
///     a green "Update Available" card with changelog + Upgrade button.
///   - Apply update (POST /api/version/upgrade) with confirm() prompt;
///     notify via `App.showNotification`.

///|
/// All `cmd` types are referenced via fully-qualified `@cmd.X` and all
/// top-level fns are prefixed with `version_` to avoid clashes with the
/// brand cell and backups cell which share the same moon package.
/// Note: we also avoid `using @html { ... }` because the same identifiers
/// (div, button, span, p) are already imported by `brand_cell.mbt` and
/// `backups_cell.mbt`; re-importing them at the top level of another
/// file in the same package triggers "toplevel identifier declared
/// twice". All HTML constructors below are therefore fully qualified.

///|
priv enum VersionMsg {
  /// Mount-time signal: trigger initial fetch of version.
  Init
  /// Initial fetch finished.
  VersionLoaded(Result[Json, String])
  /// User clicked "Check for Updates".
  ClickCheck
  /// Check-for-update response returned.
  CheckDone(Result[Json, String])
  /// User clicked "Upgrade Now".
  ClickUpgrade
  /// Upgrade response returned.
  UpgradeDone(Result[Json, String])
}

///|
priv struct UpdateInfo {
  /// Version label of the available release (e.g. "v1.2.3" or "1.2.3").
  version : String
  /// Optional changelog text from the server.
  changelog : String
}

///|
priv struct VersionModel {
  /// "v1.2.3", "unknown", or "" before the first fetch resolves.
  current : String
  /// UpdateInfo if server says a new release is available, else None.
  available : UpdateInfo?
  /// Inline message rendered under the version card after a check
  /// ("You are running the latest version." or an error line).
  check_result : String
  /// True while any network call is in flight.
  busy : Bool
}

///|
fn initial_version_model() -> VersionModel {
  { current: "", available: None, check_result: "", busy: false }
}

///|
fn version_parse_update(json : Json) -> UpdateInfo? {
  match json {
    Object(map) => {
      let version = version_json_string(json, "version", "latest")
      let changelog = version_json_string(json, "changelog", "")
      Some({ version, changelog })
    }
    String(s) => Some({ version: s, changelog: "" })
    _ => None
  }
}

///|
fn version_extract_update(json : Json) -> UpdateInfo? {
  let from_available = match json {
    Object(map) =>
      match map.get("available_update") {
        Some(Object(_)) as obj => obj
        Some(String(_)) as obj => obj
        _ => None
      }
    _ => None
  }
  let from_legacy = match json {
    Object(map) =>
      match map.get("update") {
        Some(Object(_)) as obj => obj
        Some(String(_)) as obj => obj
        _ => None
      }
    _ => None
  }
  match (from_available, from_legacy) {
    (Some(j), _) => version_parse_update(j)
    (None, Some(j)) => version_parse_update(j)
    (None, None) => None
  }
}

///|
fn version_fetch_cmd(emit : @cmd.Emit[VersionMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(VersionLoaded(r)), async fn() noraise {
    safe_get("/api/version")
  })
}

///|
fn version_check_cmd(emit : @cmd.Emit[VersionMsg]) -> @cmd.Cmd {
  let body = Json::object(Map::of([]))
  @cmd.perform(r => emit(CheckDone(r)), async fn() noraise {
    safe_post("/api/version/check", body)
  })
}

///|
fn version_upgrade_cmd(emit : @cmd.Emit[VersionMsg]) -> @cmd.Cmd {
  let body = Json::object(Map::of([]))
  @cmd.perform(r => emit(UpgradeDone(r)), async fn() noraise {
    safe_post("/api/version/upgrade", body)
  })
}

///|
fn version_update(
  emit : @cmd.Emit[VersionMsg],
  msg : VersionMsg,
  model : VersionModel,
) -> (@cmd.Cmd, VersionModel) {
  match msg {
    Init => (version_fetch_cmd(emit), { ..model, busy: true })
    VersionLoaded(Ok(json)) => {
      let v = version_json_string(json, "current_version", version_json_string(
        json, "version", "unknown",
      ))
      let available = version_extract_update(json)
      let changelog = match available {
        Some(u) => u.changelog
        None => ""
      }
      (
        @cmd.none,
        { ..model, current: v, available, busy: false, check_result: "" },
      )
    }
    VersionLoaded(Err(e)) => {
      app_notify("Failed to load version: \{e}", "error")
      (
        @cmd.none,
        {
          ..model,
          busy: false,
          current: "unknown",
          check_result: "Load failed: " + e,
        },
      )
    }
    ClickCheck =>
      if model.busy {
        (@cmd.none, model)
      } else {
        (
          version_check_cmd(emit),
          { ..model, busy: true, check_result: "Checking for updates..." },
        )
      }
    CheckDone(Ok(json)) => {
      let available = version_extract_update(json)
      let cl = version_json_string(json, "changelog", "")
      let merged = match available {
        Some(u) =>
          if cl.length() > 0 {
            Some({ ..u, changelog: cl })
          } else {
            Some(u)
          }
        None => None
      }
      let result_msg = match merged {
        Some(_) => {
          app_notify("Update available!", "success")
          ""
        }
        None => {
          app_notify("No updates available", "info")
          "You are running the latest version."
        }
      }
      (
        @cmd.none,
        { ..model, available: merged, busy: false, check_result: result_msg },
      )
    }
    CheckDone(Err(e)) => {
      app_notify("Update check failed: \{e}", "error")
      (
        @cmd.none,
        { ..model, busy: false, check_result: "Check failed: " + e },
      )
    }
    ClickUpgrade =>
      if model.busy {
        (@cmd.none, model)
      } else {
        let confirmed = window_confirm(
          "Upgrade to the latest version? The server may restart.",
        )
        if not(confirmed) {
          (@cmd.none, model)
        } else {
          (version_upgrade_cmd(emit), { ..model, busy: true })
        }
      }
    UpgradeDone(Ok(json)) => {
      let msg = version_json_string(
        json,
        "message",
        "Upgrade initiated. Server may restart.",
      )
      app_notify(msg, "success")
      (@cmd.none, { ..model, busy: false })
    }
    UpgradeDone(Err(e)) => {
      app_notify("Upgrade failed: \{e}", "error")
      (@cmd.none, { ..model, busy: false })
    }
  }
}

///|
fn version_view(
  emit : @cmd.Emit[VersionMsg],
  model : VersionModel,
) -> @html.Html {
  let current = if model.current.length() == 0 {
    "Loading..."
  } else {
    model.current
  }
  let check_button = if model.busy {
    @html.button(class="btn btn-ghost btn-sm", disabled=true, "Checking...")
  } else {
    button(
      class="btn btn-ghost btn-sm",
      on_click=emit(ClickCheck),
      "Check for Updates",
    )
  }
  let current_card = @html.div(class="settings-group", [
    @html.div(class="settings-group-title", [@html.span("Current Version")]),
    @html.div(class="version-info-card", [
      @html.div(class="version-header", [
        @html.div(class="version-icon", [@html.span("📦")]),
        @html.div(class="version-text", [
          @html.div(class="version-current", [@html.span(current)]),
          @html.div(class="text-muted", [@html.span("MBOpenClacky")]),
        ]),
      ]),
      @html.div(class="version-actions", [check_button]),
    ]),
  ])
  let update_section = match model.available {
    Some(u) => {
      let upgrade_button = if model.busy {
        @html.button(class="btn btn-primary", disabled=true, "Upgrading...")
      } else {
        button(
          class="btn btn-primary",
          on_click=emit(ClickUpgrade),
          "Upgrade Now",
        )
      }
      let changelog_block = if u.changelog.length() > 0 {
        @html.div(class="version-changelog", [
          @html.div(class="version-changelog-label", [@html.span("Changelog:")]),
          @html.div(class="version-changelog-body", [@html.span(u.changelog)]),
        ])
      } else {
        @html.div(class="version-changelog-empty", [@html.span("")])
      }
      @html.div(class="settings-group", [
        @html.div(
          class="settings-group-title version-update-title",
          [@html.span("Update Available")],
        ),
        @html.div(class="version-update-card", [
          @html.div(class="version-update-header", [
            @html.div(class="version-update-text", [
              @html.div(
                class="version-update-name",
                [@html.span("Version " + u.version)],
              ),
              @html.div(class="text-muted", [@html.span("A new version is available")]),
            ]),
            upgrade_button,
          ]),
          changelog_block,
        ]),
      ])
    }
    None =>
      @html.div(class="settings-group", [
        @html.div(
          id="version-check-result",
          class="text-muted version-check-result",
          [@html.span(model.check_result)],
        ),
      ])
  }
  @html.div(class="version-panel", [current_card, update_section])
}

///|
/// Read a string field from a Json object, falling back to `default`.
fn version_json_string(json : Json, key : String, default : String) -> String {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(String(s)) => s
        _ => default
      }
    _ => default
  }
}

///|
/// Factory used by `main.mbt`. Returns the `(emit, cell)` pair from
/// `cell_with_emit`; `main.mbt` then wires `emit(Init)` as the mount-time
/// command via `app.with_init`.
fn build_version_cell() -> (@cmd.Emit[VersionMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_version_model(),
    update=version_update,
    view=version_view,
  )
}
