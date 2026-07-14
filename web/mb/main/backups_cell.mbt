///| Backups panel — rabbita replacement for `web/js/backups.js`.
///
/// Renders the backup-archives table into `#backups-content` (a child of
/// `#view-backups .view-content`). State is fetched from the existing
/// MBOpenClacky backend at `/api/backups/*` via the `api_get / api_post /
/// api_del` bridges in `bridge.mbt`, which forward to the `API` wrapper
/// in `web/js/app.js:6`.
///
/// Behaviour parity with `web/js/backups.js`:
///   - On mount, fetch the list and render a table.
///   - Create a new backup; restore from an existing one; delete.
///   - Notify via `App.showNotification` and confirm via `window.confirm`.

///|
/// Note: cannot redeclare `Emit / Cmd / perform / none` (already used by
/// `brand_cell.mbt`'s `using @cmd`), so all `cmd` types are referenced via
/// fully-qualified `@cmd.X` and all top-level fns are prefixed with
/// `backups_` to avoid clashes with the brand cell's `update / view /
/// status_badge / json_string`.
using @html {table, tbody, td, th, thead, tr, button, div}

///|
priv enum BackupsMsg {
  /// Mount-time signal: trigger initial fetch.
  Init
  /// Manually re-fetch (after create/delete).
  Reload
  /// List fetch finished.
  BackupsLoaded(Result[Json, String])
  /// User clicked "Create Backup".
  ClickCreate
  /// Create result.
  CreateDone(Result[Json, String])
  /// User clicked "Restore" on a specific id.
  ClickRestore(String)
  /// Restore result.
  RestoreDone(Result[Json, String])
  /// User clicked delete on a specific id.
  ClickDelete(String)
  /// Delete result.
  DeleteDone(Result[Json, String])
}

///|
priv struct Backup {
  id : String
  created_at : String
  label : String
  size : Int
  status : String
} derive(Show)

///|
priv struct BackupsModel {
  backups : Array[Backup]
  loading : Bool
  /// "" if idle, "create" while creating, "<id>:restore" / "<id>:delete" while busy.
  busy : String
  error : String
}

///|
fn initial_backups_model() -> BackupsModel {
  { backups: [], loading: false, busy: "", error: "" }
}

///|
fn backups_parse_backup(json : Json) -> Backup {
  let id = backups_json_string(json, "id", backups_json_string(json, "backup_id", ""))
  let created_at = backups_json_string(json, "created_at", backups_json_string(json, "timestamp", ""))
  let label = backups_json_string(json, "label", backups_json_string(json, "name", "—"))
  let size = backups_json_int(json, "size", backups_json_int(json, "size_bytes", 0))
  let status = backups_json_string(json, "status", "completed")
  { id, created_at, label, size, status }
}

///|
fn backups_parse_backups(json : Json) -> Array[Backup] {
  let arr = match json {
    Object(map) =>
      match map.get("backups") {
        Some(Array(a)) => a
        _ => []
      }
    Array(a) => a
    _ => []
  }
  arr.map(backups_parse_backup)
}

///|
fn backups_fetch_cmd(emit : @cmd.Emit[BackupsMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(BackupsLoaded(r)), async fn() noraise {
    safe_get("/api/backups")
  })
}

///|
fn backups_update(
  emit : @cmd.Emit[BackupsMsg],
  msg : BackupsMsg,
  model : BackupsModel,
) -> (@cmd.Cmd, BackupsModel) {
  match msg {
    Init | Reload =>
      (backups_fetch_cmd(emit), { ..model, loading: true, error: "" })
    BackupsLoaded(Ok(json)) =>
      (@cmd.none, { ..model, backups: backups_parse_backups(json), loading: false })
    BackupsLoaded(Err(e)) => {
      app_notify("Failed to load backups: \{e}", "error")
      (@cmd.none, { ..model, loading: false, error: e, backups: [] })
    }
    ClickCreate => {
      let body = Json::object(Map::of([]))
      let cmd = @cmd.perform(r => emit(CreateDone(r)), async fn() noraise {
        safe_post("/api/backups", body)
      })
      (cmd, { ..model, busy: "create" })
    }
    CreateDone(Ok(_)) => {
      app_notify("Backup created successfully", "success")
      (backups_fetch_cmd(emit), { ..model, busy: "" })
    }
    CreateDone(Err(e)) => {
      app_notify("Failed to create backup: \{e}", "error")
      (backups_fetch_cmd(emit), { ..model, busy: "" })
    }
    ClickRestore(id) => {
      let ok = window_confirm(
        "This will overwrite current data with this backup. Are you sure?",
      )
      if not(ok) {
        (@cmd.none, model)
      } else {
        let body = Json::object(Map::of([]))
        let path = "/api/backups/" + js_encode_uri_component(id) + "/restore"
        let cmd = @cmd.perform(r => emit(RestoreDone(r)), async fn() noraise {
          safe_post(path, body)
        })
        (cmd, { ..model, busy: id + ":restore" })
      }
    }
    RestoreDone(Ok(_)) => {
      app_notify("Backup restored successfully", "success")
      (@cmd.none, { ..model, busy: "" })
    }
    RestoreDone(Err(e)) => {
      app_notify("Failed to restore backup: \{e}", "error")
      (@cmd.none, { ..model, busy: "" })
    }
    ClickDelete(id) => {
      let ok = window_confirm("Delete this backup? This cannot be undone.")
      if not(ok) {
        (@cmd.none, model)
      } else {
        let path = "/api/backups/" + js_encode_uri_component(id)
        let cmd = @cmd.perform(r => emit(DeleteDone(r)), async fn() noraise {
          safe_del(path)
        })
        (cmd, { ..model, busy: id + ":delete" })
      }
    }
    DeleteDone(Ok(_)) => {
      app_notify("Backup deleted", "success")
      (backups_fetch_cmd(emit), { ..model, busy: "" })
    }
    DeleteDone(Err(e)) => {
      app_notify("Failed to delete backup: \{e}", "error")
      (@cmd.none, { ..model, busy: "" })
    }
  }
}

///|
fn backups_status_badge(status : String) -> @html.Html {
  let s = status.to_lower()
  let cls = match s {
    "completed" | "ok" => "completed"
    "failed" | "error" => "failed"
    _ => "other"
  }
  @html.span(class="backup-status-badge \{cls}", status)
}

///|
fn backups_format_time(iso : String) -> String {
  if iso == "" {
    "—"
  } else {
    iso
  }
}

///|
fn backups_format_size(bytes : Int) -> String {
  if bytes <= 0 {
    "—"
  } else if bytes < 1024 {
    "\{bytes} B"
  } else if bytes < 1048576 {
    "\{(bytes / 1024).to_double().to_string()} KB"
  } else {
    "\{(bytes / 1048576).to_double().to_string()} MB"
  }
}

///|
fn backups_row(
  emit : @cmd.Emit[BackupsMsg],
  b : Backup,
  busy : String,
) -> @html.Html {
  let restoring = busy == b.id + ":restore"
  let deleting = busy == b.id + ":delete"
  let create_busy = busy == "create"
  tr([
    td(class="backup-cell", backups_format_time(b.created_at)),
    td(class="backup-cell", b.label),
    td(class="backup-cell", backups_format_size(b.size)),
    td(class="backup-cell", [backups_status_badge(b.status)]),
    td(class="backup-cell", [
      button(
        class="btn btn-ghost btn-sm",
        disabled=create_busy || restoring || deleting,
        on_click=emit(ClickRestore(b.id)),
        if restoring {
          "Restoring..."
        } else {
          "Restore"
        },
      ),
      button(
        class="btn btn-danger btn-sm",
        disabled=create_busy || restoring || deleting,
        on_click=emit(ClickDelete(b.id)),
        if deleting {
          "Deleting..."
        } else {
          "🗑"
        },
      ),
    ]),
  ])
}

///|
fn backups_view(emit : @cmd.Emit[BackupsMsg], model : BackupsModel) -> @html.Html {
  let create_busy = model.busy == "create"
  let header = div(class="backups-header", [
    @html.span(class="backups-header-title", "Backup Archives"),
    button(
      class="btn btn-primary btn-sm",
      disabled=create_busy,
      on_click=emit(ClickCreate),
      if create_busy {
        "Creating..."
      } else {
        "+ Create Backup"
      },
    ),
  ])
  if model.loading && model.backups.length() == 0 {
    return div([header, @html.p(class="text-muted", "Loading backups...")])
  }
  if model.backups.length() == 0 {
    return div([
      header,
      div(class="empty-state", [
        div(class="empty-state-icon", "💾"),
        @html.p(class="empty-state-title", "No Backups"),
        @html.p(class="text-muted", "Create a backup to protect your data."),
      ]),
    ])
  }
  let rows = model.backups.map(b => backups_row(emit, b, model.busy))
  let table_html = table(class="backups-table", [
    thead([
      tr([
        th(class="backup-th", "Created"),
        th(class="backup-th", "Label"),
        th(class="backup-th", "Size"),
        th(class="backup-th", "Status"),
        th(class="backup-th", "Actions"),
      ]),
    ]),
    tbody(rows),
  ])
  div([header, table_html])
}

///|
/// Read a string field from a Json object, falling back to `default`.
fn backups_json_string(json : Json, key : String, default : String) -> String {
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
/// Read an int field from a Json object, falling back to `default`.
fn backups_json_int(json : Json, key : String, default : Int) -> Int {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(Number(d, ..)) => d.to_int()
        _ => default
      }
    _ => default
  }
}

///|
/// Factory used by `main.mbt`. Returns the `(emit, cell)` pair from
/// `cell_with_emit`; `main.mbt` then wires `emit(Init)` as the mount-time
/// command via `app.with_init`.
fn build_backups_cell() -> (@cmd.Emit[BackupsMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_backups_model(),
    update=backups_update,
    view=backups_view,
  )
}
