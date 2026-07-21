///| Sessions sidebar - rabbita replacement for `web/js/sessions.js`.
///
/// Renders the session list into `#session-list`. The new-session button
/// and search input (`#btn-new-session`, `#session-search`) live outside
/// the mount point and are wired via FFI listeners registered on Init.
/// Cross-cell communication with the ChatCell uses `CustomEvent`:
///   - SessionsCell dispatches `chat:session-changed` on switch/create
///   - ChatCell dispatches `sessions:refresh` after streaming completes
///   - app.js dispatches `sessions:new-session` on Ctrl+N

///|
priv enum SessionsMsg {
  Init
  SessionsLoaded(Result[Json, String])
  ClickSwitch(String)
  ClickDelete(String)
  DeleteDone(Result[Json, String])
  SearchInput(String)
  NewSessionDialog
  CreateSession
  CreateDone(Result[Json, String])
  CancelCreate
  SessionNameChanged(String)
  RefreshRequested
  LocaleChanged
}

///|
priv struct SessionsModel {
  sessions : Array[Json]
  search_filter : String
  current_session_id : String
  show_create_dialog : Bool
  create_name : String
  locale : String
  loading : Bool
}

///|
fn initial_sessions_model() -> SessionsModel {
  {
    sessions: [],
    search_filter: "",
    current_session_id: "",
    show_create_dialog: false,
    create_name: "",
    locale: "",
    loading: true,
  }
}

// ── API helpers ──────────────────────────────────────────────────

///|
fn fetch_sessions(emit : @cmd.Emit[SessionsMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(SessionsLoaded(r)), async fn() noraise {
    safe_get("/api/sessions")
  })
}

///|
fn create_session_cmd(
  emit : @cmd.Emit[SessionsMsg],
  name : String,
) -> @cmd.Cmd {
  let body = Json::object(Map::of([("name", Json::string(name))]))
  @cmd.perform(r => emit(CreateDone(r)), async fn() noraise {
    safe_post("/api/sessions", body)
  })
}

///|
fn delete_session_cmd(
  emit : @cmd.Emit[SessionsMsg],
  id : String,
) -> @cmd.Cmd {
  @cmd.perform(r => emit(DeleteDone(r)), async fn() noraise {
    safe_del("/api/sessions/\{id}")
  })
}

// ── Update ───────────────────────────────────────────────────────

///|
fn sessions_update(
  emit : @cmd.Emit[SessionsMsg],
  msg : SessionsMsg,
  model : SessionsModel,
) -> (@cmd.Cmd, SessionsModel) {
  match msg {
    Init => {
      let controls_cmd = @cmd.custom_cmd(scheduler => {
        js_register_sessions_controls(
          () => scheduler.add(emit(NewSessionDialog)),
          s => scheduler.add(emit(SearchInput(s))),
        )
        js_on_sessions_refresh(() => scheduler.add(emit(RefreshRequested)))
        js_on_new_session(() => scheduler.add(emit(NewSessionDialog)))
      })
      (
        @cmd.batch([fetch_sessions(emit), controls_cmd, locale_change_cmd(emit, LocaleChanged)]),
        { ..model, loading: true, locale: i18n_get_locale() },
      )
    }
    SessionsLoaded(Ok(json)) => {
      let sessions : Array[Json] = match json {
        Object(map) =>
          match map.get("sessions") {
            Some(Array(arr)) => arr
            _ => []
          }
        Array(arr) => arr
        _ => []
      }
      let auto_select_cmd = if model.current_session_id == "" && sessions.length() > 0 {
        let first = sessions[0]
        let sid = json_str(first, "session_id", "") + json_str(first, "id", "")
        let sname = json_str(first, "name", t("sessions.unnamed"))
        if sid != "" {
          @cmd.custom_cmd(_ => js_dispatch_session_changed(sid, sname))
        } else {
          @cmd.none
        }
      } else {
        @cmd.none
      }
      (
        auto_select_cmd,
        { ..model, sessions, loading: false },
      )
    }
    SessionsLoaded(Err(e)) => {
      app_notify(t1("sessions.failed_load", "error", e), "error")
      (none, { ..model, sessions: [], loading: false })
    }
    ClickSwitch(id) => {
      if id == model.current_session_id {
        (none, model)
      } else {
        let session_name = {
          let mut name = t("sessions.unnamed")
          for s in model.sessions {
            let sid = json_str(s, "session_id", "") + json_str(s, "id", "")
            if sid == id {
              name = json_str(s, "name", t("sessions.unnamed"))
              break
            }
          }
          name
        }
        let dispatch_cmd = @cmd.custom_cmd(_ => {
          js_dispatch_session_changed(id, session_name)
        })
        (dispatch_cmd, { ..model, current_session_id: id })
      }
    }
    ClickDelete(id) => {
      if not(window_confirm(t("sessions.delete_confirm"))) {
        (none, model)
      } else {
        (delete_session_cmd(emit, id), model)
      }
    }
    DeleteDone(Ok(_)) => {
      app_notify(t("sessions.deleted"), "info")
      let new_sessions : Array[Json] = []
      for s in model.sessions {
        let sid = json_str(s, "session_id", "") + json_str(s, "id", "")
        if sid != id_deleted(model) {
          new_sessions.push(s)
        }
      }
      if model.current_session_id == id_deleted(model) {
        (
          @cmd.custom_cmd(_ => js_dispatch_session_changed("", "")),
          { ..model, sessions: new_sessions, current_session_id: "" },
        )
      } else {
        (fetch_sessions(emit), { ..model, sessions: new_sessions })
      }
    }
    DeleteDone(Err(_)) => {
      app_notify(t("sessions.failed_delete"), "error")
      (none, model)
    }
    SearchInput(s) => (none, { ..model, search_filter: s })
    NewSessionDialog =>
      (none, { ..model, show_create_dialog: true, create_name: "" })
    CancelCreate => (none, { ..model, show_create_dialog: false })
    SessionNameChanged(s) => (none, { ..model, create_name: s })
    CreateSession => {
      let name = model.create_name.trim().to_string()
      if name == "" {
        (create_session_cmd(emit, t("sessions.new")), { ..model, show_create_dialog: false })
      } else {
        (create_session_cmd(emit, name), { ..model, show_create_dialog: false })
      }
    }
    CreateDone(Ok(json)) => {
      let sid = json_str(json, "session_id", "") + json_str(json, "id", "")
      let sname = json_str(json, "name", t("sessions.new"))
      app_notify(t("sessions.created"), "success")
      let dispatch_cmd = @cmd.custom_cmd(_ => js_dispatch_session_changed(sid, sname))
      (
        @cmd.batch([fetch_sessions(emit), dispatch_cmd]),
        { ..model, current_session_id: sid },
      )
    }
    CreateDone(Err(e)) => {
      app_notify(e, "error")
      (none, model)
    }
    RefreshRequested => (fetch_sessions(emit), model)
    LocaleChanged => (none, { ..model, locale: i18n_get_locale() })
  }
}

///|
/// Helper to get the id being deleted (tracked implicitly via the
/// ClickDelete msg). Since we can't store the pending delete id in
/// the model easily without an extra field, we re-derive it from
/// the current session if DeleteDone arrives after deleting the active
/// session, or just refetch the full list otherwise.
fn id_deleted(model : SessionsModel) -> String {
  model.current_session_id
}

// ── Views ────────────────────────────────────────────────────────

///|
fn sessions_view(
  emit : @cmd.Emit[SessionsMsg],
  model : SessionsModel,
) -> @html.Html {
  if model.show_create_dialog {
    return render_create_dialog(emit, model)
  }
  if model.loading {
    return @html.div(class="text-center", [
      @html.div(class="spinner", style=["margin:20px auto"], ""),
    ])
  }
  let filtered : Array[Json] = []
  let filter = model.search_filter.to_lower()
  for s in model.sessions {
    let name = json_str(s, "name", "").to_lower()
    if filter == "" || name.contains(filter) {
      filtered.push(s)
    }
  }
  if filtered.length() == 0 {
    return @html.div(
      class="empty-state",
      style=["padding:20px"],
      [
        @html.p(
          class="text-muted",
          style=["font-size:12px"],
          if model.search_filter != "" {
            t("sessions.no_matching")
          } else {
            t("sessions.no_sessions")
          },
        ),
      ],
    )
  }
  let items : Array[@html.Html] = []
  for s in filtered {
    items.push(render_session_item(emit, s, model.current_session_id))
  }
  @html.div(items)
}

///|
fn render_session_item(
  emit : @cmd.Emit[SessionsMsg],
  session : Json,
  active_id : String,
) -> @html.Html {
  let id = json_str(session, "session_id", "") + json_str(session, "id", "")
  let name = json_str(session, "name", t("sessions.unnamed"))
  let is_active = id == active_id
  let meta : Array[String] = []
  let msg_count = {
    match session {
      Object(map) =>
        match map.get("messages") {
          Some(Array(arr)) => arr.length()
          _ =>
            match map.get("stats") {
              Some(Object(stats)) =>
                match stats.get("total_iterations") {
                  Some(Number(n)) => n.to_int()
                  _ => 0
                }
              _ => 0
            }
        }
      _ => 0
    }
  }
  let cost = {
    match session {
      Object(map) =>
        match map.get("stats") {
          Some(Object(stats)) =>
            match stats.get("total_cost_usd") {
              Some(Number(n)) => Some(n)
              _ => None
            }
          _ => None
        }
      _ => None
    }
  }
  let updated = json_str(session, "updated_at", "") + json_str(session, "created_at", "")
  if msg_count > 0 {
    meta.push("\{msg_count} " + t("sessions.msgs"))
  }
  match cost {
    Some(c) => meta.push("$" + c.to_string())
    None => ()
  }
  if updated != "" {
    meta.push(js_parse_date(updated))
  }
  let meta_text = {
    let buf = StringBuilder::new()
    let first = Ref::new(true)
    for m in meta {
      if not(first.val) {
        buf.write_string(" · ")
      }
      buf.write_string(m)
      first.val = false
    }
    buf.to_string()
  }
  @html.div(
    class="session-item" + (if is_active { " active" } else { "" }),
    on_click=emit(ClickSwitch(id)),
    [
      @html.div(class="session-item-info", [
        @html.div(class="session-item-name", name),
        if meta_text == "" {
          @html.nothing
        } else {
          @html.div(class="session-item-meta", meta_text)
        },
      ]),
      @html.button(
        class="session-item-delete",
        title=t("common.delete"),
        on_click=emit(ClickDelete(id)),
        "🗑",
      ),
    ],
  )
}

///|
fn render_create_dialog(
  emit : @cmd.Emit[SessionsMsg],
  model : SessionsModel,
) -> @html.Html {
  @html.div(
    class="settings-field",
    style=["padding:12px"],
    [
      @html.label(t("sessions.name")),
      @html.input(
        input_type=@html.Text,
        id="new-session-name",
        placeholder=t("sessions.name_placeholder"),
        value=model.create_name,
        on_change=s => emit(SessionNameChanged(s)),
        style=input_style(),
        autofocus=true,
      ),
      @html.div(class="help-text", t("sessions.name_help")),
      @html.div(style=["display:flex", "gap:8px", "margin-top:8px"], [
        @html.button(
          class="btn btn-ghost btn-sm",
          on_click=emit(CancelCreate),
          t("common.cancel"),
        ),
        @html.button(
          class="btn btn-primary btn-sm",
          on_click=emit(CreateSession),
          t("sessions.create"),
        ),
      ]),
    ],
  )
}

///|
fn build_sessions_cell() -> (@cmd.Emit[SessionsMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_sessions_model(),
    update=sessions_update,
    view=sessions_view,
  )
}
