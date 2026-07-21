///| Schedules panel - rabbita replacement for `web/js/schedules.js`.
///
/// CRUD for scheduled tasks. API endpoints:
///   - `GET /api/schedules` - list all schedules
///   - `POST /api/schedules` - create schedule
///   - `PUT /api/schedules/:id` - update schedule
///   - `DELETE /api/schedules/:id` - delete schedule
///   - `POST /api/schedules/:id/trigger` - trigger now
///   - `GET /api/schedules/:id/history` - execution history

///|
priv enum SchedulesMsg {
  Init
  Loaded(Result[Json, String])
  ClickAdd
  ClickEdit(Json)
  ClickDelete(String)
  DeleteDone(Result[Json, String])
  ClickTrigger(String)
  TriggerDone(Result[Json, String])
  ClickToggle(String, Json)
  FormNameChanged(String)
  FormMessageChanged(String)
  FormCronChanged(String)
  FormToggleEnabled
  ClickSave
  SaveDone(Result[Json, String])
  ClickCancelForm
  LocaleChanged
}

///|
priv struct SchedulesModel {
  schedules : Array[Json]
  loading : Bool
  show_form : Bool
  editing_id : String
  form_name : String
  form_message : String
  form_cron : String
  form_enabled : Bool
  busy : Bool
  locale : String
}

///|
fn initial_schedules_model() -> SchedulesModel {
  {
    schedules: [],
    loading: true,
    show_form: false,
    editing_id: "",
    form_name: "",
    form_message: "",
    form_cron: "",
    form_enabled: true,
    busy: false,
    locale: "",
  }
}

///|
fn fetch_schedules(emit : @cmd.Emit[SchedulesMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(Loaded(r)), async fn() noraise {
    safe_get("/api/schedules")
  })
}

///|
fn schedules_update(
  emit : @cmd.Emit[SchedulesMsg],
  msg : SchedulesMsg,
  model : SchedulesModel,
) -> (@cmd.Cmd, SchedulesModel) {
  match msg {
    Init =>
      (
        @cmd.batch([
          fetch_schedules(emit),
          locale_change_cmd(emit, LocaleChanged),
        ]),
        { ..model, loading: true, locale: i18n_get_locale() },
      )
    Loaded(Ok(json)) => {
      let items = match json {
        Array(arr) => arr
        Object(map) =>
          match map.get("schedules") {
            Some(Array(arr)) => arr
            _ => []
          }
        _ => []
      }
      (@cmd.none, { ..model, schedules: items, loading: false })
    }
    Loaded(Err(e)) => {
      app_notify(t1("schedules.load_failed", "error", e), "error")
      (@cmd.none, { ..model, schedules: [], loading: false })
    }
    ClickAdd =>
      (
        @cmd.none,
        {
          ..model,
          show_form: true,
          editing_id: "",
          form_name: "",
          form_message: "",
          form_cron: "",
          form_enabled: true,
        },
      )
    ClickEdit(s) => {
      let id = json_str(s, "id", json_str(s, "schedule_id", ""))
      let name = json_str(s, "name", "")
      let message = json_str(s, "message", "")
      let cron = json_str(s, "cron_expression", "")
      let enabled = json_bool(s, "enabled", true)
      (
        @cmd.none,
        {
          ..model,
          show_form: true,
          editing_id: id,
          form_name: name,
          form_message: message,
          form_cron: cron,
          form_enabled: enabled,
        },
      )
    }
    ClickDelete(id) => {
      let ok = window_confirm(t("schedules.delete_confirm"))
      if ok {
        let cmd = @cmd.perform(r => emit(DeleteDone(r)), async fn() noraise {
          safe_del("/api/schedules/" + id)
        })
        (cmd, { ..model, busy: true })
      } else {
        (@cmd.none, model)
      }
    }
    DeleteDone(Ok(_)) => {
      app_notify(t("schedules.deleted"), "success")
      (fetch_schedules(emit), { ..model, busy: false })
    }
    DeleteDone(Err(e)) => {
      app_notify(t1("schedules.delete_failed", "error", e), "error")
      (@cmd.none, { ..model, busy: false })
    }
    ClickTrigger(id) => {
      let cmd = @cmd.perform(r => emit(TriggerDone(r)), async fn() noraise {
        safe_post("/api/schedules/" + id + "/trigger", Json::null())
      })
      (cmd, model)
    }
    TriggerDone(Ok(_)) => {
      app_notify(t("schedules.triggered"), "success")
      (@cmd.none, model)
    }
    TriggerDone(Err(e)) => {
      app_notify(t1("schedules.trigger_failed", "error", e), "error")
      (@cmd.none, model)
    }
    ClickToggle(id, s) => {
      let new_enabled = !json_bool(s, "enabled", true)
      let body = Json::object(
        Map::of([
          ("name", Json::string(json_str(s, "name", ""))),
          ("message", Json::string(json_str(s, "message", ""))),
          ("cron_expression", Json::string(json_str(s, "cron_expression", ""))),
          ("enabled", json_bool_val(new_enabled)),
        ]),
      )
      let cmd = @cmd.perform(r => emit(SaveDone(r)), async fn() noraise {
        safe_put("/api/schedules/" + id, body)
      })
      (cmd, { ..model, busy: true })
    }
    FormNameChanged(v) => (@cmd.none, { ..model, form_name: v })
    FormMessageChanged(v) => (@cmd.none, { ..model, form_message: v })
    FormCronChanged(v) => (@cmd.none, { ..model, form_cron: v })
    FormToggleEnabled => (@cmd.none, { ..model, form_enabled: !model.form_enabled })
    ClickSave => {
      if model.form_name.trim() == "" {
        app_notify(t("schedules.name_required"), "warning")
        (@cmd.none, model)
      } else if model.form_cron.trim() == "" {
        app_notify(t("schedules.cron_required"), "warning")
        (@cmd.none, model)
      } else {
        let body = Json::object(
          Map::of([
            ("name", Json::string(model.form_name.trim().to_owned())),
            ("message", Json::string(model.form_message.trim().to_owned())),
            ("cron_expression", Json::string(model.form_cron.trim().to_owned())),
            ("enabled", json_bool_val(model.form_enabled)),
          ]),
        )
        let path = if model.editing_id != "" {
          "/api/schedules/" + model.editing_id
        } else {
          "/api/schedules"
        }
        let cmd = @cmd.perform(r => emit(SaveDone(r)), async fn() noraise {
          if model.editing_id != "" {
            safe_put(path, body)
          } else {
            safe_post(path, body)
          }
        })
        (cmd, { ..model, busy: true })
      }
    }
    SaveDone(Ok(_)) => {
      let msg = if model.editing_id != "" {
        t("schedules.updated")
      } else {
        t("schedules.created")
      }
      app_notify(msg, "success")
      (
        fetch_schedules(emit),
        {
          ..model,
          busy: false,
          show_form: false,
          editing_id: "",
          form_name: "",
          form_message: "",
          form_cron: "",
          form_enabled: true,
        },
      )
    }
    SaveDone(Err(e)) => {
      app_notify(t1("schedules.save_failed", "error", e), "error")
      (@cmd.none, { ..model, busy: false })
    }
    ClickCancelForm =>
      (
        @cmd.none,
        { ..model, show_form: false, editing_id: "", form_name: "", form_message: "", form_cron: "" },
      )
    LocaleChanged => (@cmd.none, { ..model, locale: i18n_get_locale() })
  }
}

///|
fn schedules_view(
  emit : @cmd.Emit[SchedulesMsg],
  model : SchedulesModel,
) -> @html.Html {
  if model.loading {
    return @html.div(class="text-center", [
      @html.div(class="spinner", style=["margin:40px auto"], @html.nothing),
    ])
  }
  @html.div([
    // Header
    @html.div(
      style=["display:flex", "justify-content:space-between", "align-items:center", "margin-bottom:16px"],
      [
        @html.h3(style=["font-size:14px", "color:var(--text-secondary)"], t("schedules.title")),
        @html.button(
          class="btn btn-primary btn-sm",
          on_click=emit(ClickAdd),
          "+ " + t("schedules.new"),
        ),
      ],
    ),
    // Inline form
    if model.show_form {
      schedules_form(emit, model)
    } else {
      @html.nothing
    },
    // List
    if model.schedules.length() == 0 {
      @html.div(class="empty-state", [
        @html.div(class="empty-state-icon", @html.text("🕐")),
        @html.h3(t("schedules.empty")),
        @html.p(class="text-muted", t("schedules.empty_desc")),
      ])
    } else {
      @html.div(
        style=["display:flex", "flex-direction:column", "gap:12px"],
        model.schedules.map(s => schedules_card(emit, s, model.busy)),
      )
    },
  ])
}

///| Render the inline add/edit form.
fn schedules_form(emit : @cmd.Emit[SchedulesMsg], model : SchedulesModel) -> @html.Html {
  let title = if model.editing_id != "" {
    t("schedules.edit")
  } else {
    t("schedules.new")
  }
  @html.div(class="settings-group", style=["margin-bottom:16px"], [
    @html.div(class="settings-group-title", title),
    @html.div(class="settings-field", [
      @html.label(t("schedules.name")),
      @html.input(
        input_type=@html.Text,
        value=model.form_name,
        placeholder="Daily Summary",
        on_change=s => emit(FormNameChanged(s)),
        style=input_style(),
      ),
    ]),
    @html.div(class="settings-field", [
      @html.label(t("schedules.message")),
      @html.textarea(
        rows=3,
        placeholder=t("schedules.message_placeholder"),
        value=model.form_message,
        on_change=s => emit(FormMessageChanged(s)),
        style=textarea_style(),
        "",
      ),
    ]),
    @html.div(class="settings-field", [
      @html.label(t("schedules.cron")),
      @html.input(
        input_type=@html.Text,
        value=model.form_cron,
        placeholder="0 9 * * *",
        on_change=s => emit(FormCronChanged(s)),
        style=input_style(),
      ),
      @html.div(class="help-text", t("schedules.cron_help")),
    ]),
    @html.div(class="settings-field", [
      @html.div(class="toggle-wrapper", [
        @html.label(t("schedules.enabled")),
        @html.div(
          class=if model.form_enabled { "toggle active" } else { "toggle" },
          on_click=emit(FormToggleEnabled),
          @html.nothing,
        ),
      ]),
    ]),
    @html.div(style=["display:flex", "gap:8px"], [
      @html.button(
        class="btn btn-ghost",
        on_click=emit(ClickCancelForm),
        t("common.cancel"),
      ),
      @html.button(
        class="btn btn-primary",
        on_click=emit(ClickSave),
        if model.busy { "..." } else { title },
      ),
    ]),
  ])
}

///| Render a single schedule card.
fn schedules_card(
  emit : @cmd.Emit[SchedulesMsg],
  s : Json,
  busy : Bool,
) -> @html.Html {
  let id = json_str(s, "id", json_str(s, "schedule_id", ""))
  let name = json_str(s, "name", "Unnamed")
  let cron = json_str(s, "cron_expression", "-")
  let message = json_str(s, "message", "")
  let next_run = json_str(s, "next_execution", "")
  let enabled = json_bool(s, "enabled", true)
  let enabled_cls = if enabled { "status-badge running" } else { "status-badge" }
  let enabled_text = if enabled { t("schedules.enabled") } else { t("schedules.disabled") }
  @html.div(class="skill-card", style=["padding:16px"], [
    @html.div(
      style=["display:flex", "align-items:center", "justify-content:space-between", "margin-bottom:8px"],
      [
        @html.div(style=["font-size:14px", "font-weight:600", "color:var(--text-primary)"], name),
        @html.div(style=["display:flex", "gap:4px", "align-items:center"], [
          @html.div(
            class=enabled_cls,
            on_click=emit(ClickToggle(id, s)),
            style=["font-size:10px", "padding:2px 8px", "border-radius:10px", "cursor:pointer"],
            enabled_text,
          ),
          @html.button(
            class="btn btn-ghost btn-sm",
            on_click=emit(ClickTrigger(id)),
            title=t("schedules.trigger_now"),
            "▶",
          ),
          @html.button(
            class="btn btn-ghost btn-sm",
            on_click=emit(ClickEdit(s)),
            t("common.edit"),
          ),
          @html.button(
            class="btn btn-danger btn-sm",
            on_click=emit(ClickDelete(id)),
            title=t("common.delete"),
            "🗑",
          ),
        ]),
      ],
    ),
    @html.div(style=["font-size:12px", "color:var(--text-secondary)"], [
      @html.div(style=["margin-bottom:4px"], [
        @html.strong(t("schedules.cron_label") + " "),
        @html.code(
          style=["background:var(--bg-tertiary)", "padding:2px 5px", "border-radius:3px", "color:var(--info)", "font-size:12px"],
          cron,
        ),
      ]),
      if next_run != "" {
        @html.div(style=["margin-bottom:4px"], [
          @html.strong(t("schedules.next_run") + " "),
          @html.text(js_parse_date(next_run)),
        ])
      } else {
        @html.nothing
      },
      if message != "" {
        @html.div(
          style=["color:var(--text-muted)", "white-space:nowrap", "overflow:hidden", "text-overflow:ellipsis"],
          message,
        )
      } else {
        @html.nothing
      },
    ]),
  ])
}

///|
fn build_schedules_cell() -> (@cmd.Emit[SchedulesMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_schedules_model(),
    update=schedules_update,
    view=schedules_view,
  )
}
