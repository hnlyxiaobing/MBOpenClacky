///| Channels panel - rabbita replacement for `web/js/channels.js`.
///
/// CRUD for IM channels + test/status.
/// API endpoints:
///   - `GET /api/channels` - list all channels
///   - `POST /api/channels` - create channel
///   - `PUT /api/channels/:id` - update channel
///   - `DELETE /api/channels/:id` - delete channel
///   - `POST /api/channels/:id/test` - send test message
///   - `GET /api/channels/:id/status` - check connection status

///|
priv enum ChannelsMsg {
  Init
  ChannelsLoaded(Result[Json, String])
  ClickAdd
  ClickEdit(Json)
  ClickCancelForm
  FormPlatformChanged(String)
  FormNameChanged(String)
  FormWebhookChanged(String)
  FormApiKeyChanged(String)
  FormSecretChanged(String)
  ClickSave
  SaveDone(Result[Json, String])
  ClickDelete(String)
  DeleteDone(Result[Json, String])
  ClickTest(String)
  TestDone(String, Result[Json, String])
  ClickStatus(String)
  StatusDone(String, Result[Json, String])
  LocaleChanged
}

///|
priv struct ChannelsModel {
  channels : Array[Json]
  loading : Bool
  busy : Bool
  show_form : Bool
  editing_id : String
  form_platform : String
  form_name : String
  form_webhook : String
  form_api_key : String
  form_secret : String
  locale : String
}

///|
fn initial_channels_model() -> ChannelsModel {
  {
    channels: [],
    loading: true,
    busy: false,
    show_form: false,
    editing_id: "",
    form_platform: "feishu",
    form_name: "",
    form_webhook: "",
    form_api_key: "",
    form_secret: "",
    locale: "",
  }
}

///|
fn fetch_channels(emit : @cmd.Emit[ChannelsMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(ChannelsLoaded(r)), async fn() noraise {
    safe_get("/api/channels")
  })
}

///|
fn save_channel(
  emit : @cmd.Emit[ChannelsMsg],
  editing_id : String,
  platform : String,
  name : String,
  config : Json,
) -> @cmd.Cmd {
  let body = Json::object(
    Map::of([("platform", Json::string(platform)), ("name", Json::string(name)), ("config", config)]),
  )
  if editing_id.is_empty() {
    @cmd.perform(r => emit(SaveDone(r)), async fn() noraise {
      safe_post("/api/channels", body)
    })
  } else {
    @cmd.perform(r => emit(SaveDone(r)), async fn() noraise {
      safe_put("/api/channels/\{editing_id}", body)
    })
  }
}

///|
fn delete_channel(emit : @cmd.Emit[ChannelsMsg], id : String) -> @cmd.Cmd {
  @cmd.perform(r => emit(DeleteDone(r)), async fn() noraise {
    safe_del("/api/channels/\{id}")
  })
}

///|
fn test_channel(emit : @cmd.Emit[ChannelsMsg], id : String) -> @cmd.Cmd {
  @cmd.perform(r => emit(TestDone(id, r)), async fn() noraise {
    safe_post("/api/channels/\{id}/test", Json::null())
  })
}

///|
fn status_channel(emit : @cmd.Emit[ChannelsMsg], id : String) -> @cmd.Cmd {
  @cmd.perform(r => emit(StatusDone(id, r)), async fn() noraise {
    safe_get("/api/channels/\{id}/status")
  })
}

///|
fn channels_update(
  emit : @cmd.Emit[ChannelsMsg],
  msg : ChannelsMsg,
  model : ChannelsModel,
) -> (@cmd.Cmd, ChannelsModel) {
  match msg {
    Init =>
      (
        @cmd.batch([fetch_channels(emit), locale_change_cmd(emit, LocaleChanged)]),
        { ..model, loading: true, locale: i18n_get_locale() },
      )
    ChannelsLoaded(Ok(json)) => {
      let items = match json {
        Array(arr) => arr
        _ => []
      }
      (@cmd.none, { ..model, channels: items, loading: false })
    }
    ChannelsLoaded(Err(e)) => {
      app_notify(t1("channels.failed_load", "error", e), "error")
      (@cmd.none, { ..model, channels: [], loading: false })
    }
    ClickAdd =>
      (
        @cmd.none,
        {
          ..model,
          show_form: true,
          editing_id: "",
          form_platform: "feishu",
          form_name: "",
          form_webhook: "",
          form_api_key: "",
          form_secret: "",
        },
      )
    ClickEdit(ch) => {
      let id = json_str(ch, "id", "")
      let id_val = if id.is_empty() {
        json_str(ch, "channel_id", "")
      } else {
        id
      }
      let platform = json_str(ch, "platform", "feishu")
      let name = json_str(ch, "name", "")
      let config = match ch {
        Object(map) =>
          match map.get("config") {
            Some(c) => c
            None => Json::null()
          }
        _ => Json::null()
      }
      let webhook = json_str(config, "webhook_url", "")
      let api_key = json_str(config, "api_key", "")
      let secret = json_str(config, "secret", "")
      (
        @cmd.none,
        {
          ..model,
          show_form: true,
          editing_id: id_val,
          form_platform: platform,
          form_name: name,
          form_webhook: webhook,
          form_api_key: api_key,
          form_secret: secret,
        },
      )
    }
    ClickCancelForm => (@cmd.none, { ..model, show_form: false })
    FormPlatformChanged(v) => (@cmd.none, { ..model, form_platform: v })
    FormNameChanged(v) => (@cmd.none, { ..model, form_name: v })
    FormWebhookChanged(v) => (@cmd.none, { ..model, form_webhook: v })
    FormApiKeyChanged(v) => (@cmd.none, { ..model, form_api_key: v })
    FormSecretChanged(v) => (@cmd.none, { ..model, form_secret: v })
    ClickSave => {
      if model.form_platform.is_empty() {
        app_notify(t("channels.required_platform"), "error")
        (@cmd.none, model)
      } else if model.form_name.trim().is_empty() {
        app_notify(t("channels.required_name"), "error")
        (@cmd.none, model)
      } else {
        let cfg_fields : Array[(String, Json)] = []
        if not(model.form_webhook.is_empty()) {
          cfg_fields.push(("webhook_url", Json::string(model.form_webhook)))
        }
        if not(model.form_api_key.is_empty()) {
          cfg_fields.push(("api_key", Json::string(model.form_api_key)))
        }
        if not(model.form_secret.is_empty()) {
          cfg_fields.push(("secret", Json::string(model.form_secret)))
        }
        let config = Json::object(Map::of(cfg_fields))
        (
          save_channel(emit, model.editing_id, model.form_platform, model.form_name.trim(), config),
          { ..model, busy: true },
        )
      }
    }
    SaveDone(Ok(_)) => {
      let msg = if model.editing_id.is_empty() {
        t("channels.created")
      } else {
        t("channels.updated")
      }
      app_notify(msg, "success")
      (
        fetch_channels(emit),
        { ..model, show_form: false, busy: false },
      )
    }
    SaveDone(Err(e)) => {
      app_notify(e, "error")
      (@cmd.none, { ..model, busy: false })
    }
    ClickDelete(id) => (delete_channel(emit, id), { ..model, busy: true })
    DeleteDone(Ok(_)) => {
      app_notify(t("channels.deleted"), "success")
      (fetch_channels(emit), { ..model, busy: false })
    }
    DeleteDone(Err(e)) => {
      app_notify(e, "error")
      (@cmd.none, { ..model, busy: false })
    }
    ClickTest(id) => (test_channel(emit, id), { ..model, busy: true })
    TestDone(_, Ok(_)) => {
      app_notify(t("channels.test_sent"), "success")
      (@cmd.none, { ..model, busy: false })
    }
    TestDone(_, Err(e)) => {
      app_notify(t1("channels.test_failed", "error", e), "error")
      (@cmd.none, { ..model, busy: false })
    }
    ClickStatus(id) => (status_channel(emit, id), { ..model, busy: true })
    StatusDone(_, Ok(json)) => {
      let status = json_str(json, "status", t("channels.status_unknown"))
      let is_connected = status == "connected" || status == "active"
      app_notify(
        "\{t("common.status")}: \{status}",
        if is_connected { "success" } else { "info" },
      )
      (fetch_channels(emit), { ..model, busy: false })
    }
    StatusDone(_, Err(e)) => {
      app_notify(t1("channels.status_check_failed", "error", e), "error")
      (@cmd.none, { ..model, busy: false })
    }
    LocaleChanged => (@cmd.none, { ..model, locale: i18n_get_locale() })
  }
}

// ── Platform metadata ────────────────────────────────────────────

///|
fn channel_platform_meta(platform : String) -> (String, String) {
  match platform {
    "feishu" => ("Feishu", "💬")
    "wecom" => ("WeCom", "💼")
    "telegram" => ("Telegram", "✈")
    "discord" => ("Discord", "🎮")
    "dingtalk" => ("DingTalk", "🔔")
    "weixin" => ("WeChat", "📱")
    _ => (platform, "📡")
  }
}

// ── Views ────────────────────────────────────────────────────────

///|
fn channels_view(
  emit : @cmd.Emit[ChannelsMsg],
  model : ChannelsModel,
) -> @html.Html {
  if model.loading {
    @html.div(class="text-center", [
      @html.div(class="spinner", style=["margin:40px auto"], []),
    ])
  } else {
    let children : Array[@html.Html] = []

    // Header with Add button
    children.push(
      @html.div(class="settings-group", [
        @html.div(
          class="settings-group-title",
          style=["display:flex", "align-items:center", "justify-content:space-between"],
          [
            @html.span([], "\{t("channels.title")} (\{model.channels.length()})"),
            @html.button(
              class="btn btn-primary btn-sm",
              on_click=emit(ClickAdd),
              t("channels.add"),
            ),
          ],
        ),
      ]),
    )

    // Inline form (when show_form is true)
    if model.show_form {
      children.push(channels_form_view(emit, model))
    }

    // Channel list
    if model.channels.is_empty() {
      children.push(
        @html.p(
          class="text-muted",
          style=["font-size:13px", "padding:16px 0"],
          t("channels.no_channels"),
        ),
      )
    } else {
      let cards : Array[@html.Html] = []
      for ch in model.channels {
        cards.push(channels_card_view(emit, ch, model.busy))
      }
      children.push(@html.div(class="skills-grid", cards))
    }

    @html.div([], children)
  }
}

///|
fn channels_form_view(
  emit : @cmd.Emit[ChannelsMsg],
  model : ChannelsModel,
) -> @html.Html {
  let is_edit = not(model.editing_id.is_empty())
  let title = if is_edit { t("channels.edit") } else { t("channels.add_title") }

  @html.div(
    class="settings-group",
    style=["margin-bottom:16px"],
    [
      @html.div(class="settings-group-title", title),
      @html.div(
        style=["padding:8px 0"],
        [
          @html.div(class="settings-field", [
            @html.label([], t("channels.platform")),
            @html.select(
              on_change=s => emit(FormPlatformChanged(s)),
              style=input_style(),
              [
                @html.option(
                  value="feishu",
                  selected=model.form_platform == "feishu",
                  "💬 Feishu",
                ),
                @html.option(
                  value="wecom",
                  selected=model.form_platform == "wecom",
                  "💼 WeCom",
                ),
                @html.option(
                  value="telegram",
                  selected=model.form_platform == "telegram",
                  "✈ Telegram",
                ),
                @html.option(
                  value="discord",
                  selected=model.form_platform == "discord",
                  "🎮 Discord",
                ),
                @html.option(
                  value="dingtalk",
                  selected=model.form_platform == "dingtalk",
                  "🔔 DingTalk",
                ),
                @html.option(
                  value="weixin",
                  selected=model.form_platform == "weixin",
                  "📱 WeChat",
                ),
              ],
            ),
            @html.div(class="help-text", t("channels.platform_help")),
          ]),
          @html.div(class="settings-field", [
            @html.label([], t("channels.name")),
            @html.input(
              input_type=@html.Text,
              value=model.form_name,
              placeholder=t("channels.name_placeholder"),
              on_change=s => emit(FormNameChanged(s)),
              style=input_style(),
            ),
            @html.div(class="help-text", t("channels.name_help")),
          ]),
          @html.div(class="settings-field", [
            @html.label([], t("channels.webhook")),
            @html.input(
              input_type=@html.Text,
              value=model.form_webhook,
              placeholder="https://...",
              on_change=s => emit(FormWebhookChanged(s)),
              style=input_style(),
            ),
            @html.div(class="help-text", t("channels.webhook_help")),
          ]),
          @html.div(class="settings-field", [
            @html.label([], t("channels.apikey")),
            @html.input(
              input_type=@html.Text,
              value=model.form_api_key,
              placeholder="Optional",
              on_change=s => emit(FormApiKeyChanged(s)),
              style=input_style(),
            ),
            @html.div(class="help-text", t("channels.apikey_help")),
          ]),
          @html.div(class="settings-field", [
            @html.label([], t("channels.secret")),
            @html.input(
              input_type=@html.Password,
              value=model.form_secret,
              placeholder="Optional",
              on_change=s => emit(FormSecretChanged(s)),
              style=input_style(),
            ),
            @html.div(class="help-text", t("channels.secret_help")),
          ]),
          @html.div(
            style=["display:flex", "gap:8px", "margin-top:12px"],
            [
              @html.button(
                class="btn btn-primary btn-sm",
                on_click=emit(ClickSave),
                style=if model.busy { ["opacity:0.5", "pointer-events:none"] } else { [] },
                if is_edit { t("channels.update") } else { t("channels.create") },
              ),
              @html.button(
                class="btn btn-ghost btn-sm",
                on_click=emit(ClickCancelForm),
                t("common.cancel"),
              ),
            ],
          ),
        ],
      ),
    ],
  )
}

///|
fn channels_card_view(
  emit : @cmd.Emit[ChannelsMsg],
  ch : Json,
  busy : Bool,
) -> @html.Html {
  let platform = json_str(ch, "platform", "")
  let (plat_label, plat_icon) = channel_platform_meta(platform)
  let name = json_str(ch, "name", plat_label)
  let ch_id = {
    let id = json_str(ch, "id", "")
    if id.is_empty() { json_str(ch, "channel_id", "") } else { id }
  }
  let status = json_str(ch, "status", t("channels.disconnected"))
  let is_connected = status == "connected" || status == "active"
  let last_activity = {
    let la = json_str(ch, "last_activity", "")
    if la.is_empty() { json_str(ch, "updated_at", "") } else { la }
  }

  let children : Array[@html.Html] = []

  // Header row: icon + name + status dot
  let header_children : Array[@html.Html] = []
  header_children.push(@html.span(style=["font-size:18px"], plat_icon))
  header_children.push(
    @html.div(
      class="skill-card-name",
      style=["margin-bottom:0"],
      name,
    ),
  )
  header_children.push(
    @html.span(
      style=[
        "width:8px",
        "height:8px",
        "border-radius:50%",
        "display:inline-block",
        "margin-left:auto",
        "flex-shrink:0",
        if is_connected { "background:var(--success)" } else {
          "background:var(--text-muted)"
        },
      ],
      "",
    ),
  )
  children.push(
    @html.div(
      style=["display:flex", "align-items:center", "gap:8px", "margin-bottom:8px"],
      header_children,
    ),
  )

  // Platform label
  children.push(@html.div(class="skill-card-desc", plat_label))

  // Status text
  children.push(
    @html.div(
      class="skill-card-desc",
      style=["margin-top:2px", "font-size:11px", if is_connected { "color:var(--success)" } else { "color:var(--text-muted)" }],
      if is_connected { t("channels.connected") } else { status },
    ),
  )

  // Last activity
  if not(last_activity.is_empty()) {
    children.push(
      @html.div(
        class="skill-card-desc",
        style=["margin-top:4px", "font-size:11px", "color:var(--text-muted)"],
        "\{t("channels.last")}\{last_activity}",
      ),
    )
  }

  // Action buttons
  let btns : Array[@html.Html] = []
  btns.push(
    @html.button(
      class="btn btn-ghost btn-sm",
      on_click=emit(ClickEdit(ch)),
      style=["padding:3px 8px", "font-size:11px"],
      t("common.edit"),
    ),
  )
  btns.push(
    @html.button(
      class="btn btn-ghost btn-sm",
      on_click=emit(ClickTest(ch_id)),
      style=["padding:3px 8px", "font-size:11px", "color:var(--info)"],
      t("channels.test"),
    ),
  )
  btns.push(
    @html.button(
      class="btn btn-ghost btn-sm",
      on_click=emit(ClickStatus(ch_id)),
      style=["padding:3px 8px", "font-size:11px"],
      t("channels.status"),
    ),
  )
  btns.push(
    @html.button(
      class="btn btn-danger btn-sm",
      on_click=emit(ClickDelete(ch_id)),
      style=["padding:3px 8px", "font-size:11px", if busy { "opacity:0.5" } else { "" }],
      t("common.delete"),
    ),
  )
  children.push(
    @html.div(style=["display:flex", "gap:6px", "margin-top:12px", "flex-wrap:wrap"], btns),
  )

  @html.div(class="skill-card", children)
}

///|
fn build_channels_cell() -> (@cmd.Emit[ChannelsMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_channels_model(),
    update=channels_update,
    view=channels_view,
  )
}
