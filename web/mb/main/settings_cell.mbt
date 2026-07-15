///| Settings panel - rabbita replacement for `web/js/settings.js`.
///
/// Model config (model select, permission mode, max tokens, verbose toggle),
/// server info display, and save settings.
/// API endpoints:
///   - `GET /api/config` - load current config
///   - `GET /api/config/models` - list available models
///   - `PUT /api/config` - save config
///   - `GET /api/info` - server info

///|
priv enum SettingsMsg {
  Init
  ConfigLoaded(Result[Json, String])
  ModelsLoaded(Result[Json, String])
  ClickSave
  SaveDone(Result[Json, String])
  ServerInfoLoaded(Result[Json, String])
  ModelChanged(String)
  PermissionChanged(String)
  MaxTokensChanged(String)
  ToggleVerbose
  LocaleChanged
}

///|
priv struct SettingsModel {
  config : Json
  models : Array[Json]
  server_info : Json
  loading : Bool
  busy : Bool
  selected_model : String
  permission_mode : String
  max_tokens : String
  verbose : Bool
  locale : String
}

///|
fn initial_settings_model() -> SettingsModel {
  {
    config: Json::null(),
    models: [],
    server_info: Json::null(),
    loading: true,
    busy: false,
    selected_model: "",
    permission_mode: "confirm_safes",
    max_tokens: "4096",
    verbose: false,
    locale: "",
  }
}

///|
fn fetch_config(emit : @cmd.Emit[SettingsMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(ConfigLoaded(r)), async fn() noraise {
    safe_get("/api/config")
  })
}

///|
fn fetch_models(emit : @cmd.Emit[SettingsMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(ModelsLoaded(r)), async fn() noraise {
    safe_get("/api/config/models")
  })
}

///|
fn fetch_server_info(emit : @cmd.Emit[SettingsMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(ServerInfoLoaded(r)), async fn() noraise {
    safe_get("/api/info")
  })
}

///|
fn save_config(emit : @cmd.Emit[SettingsMsg], body : Json) -> @cmd.Cmd {
  @cmd.perform(r => emit(SaveDone(r)), async fn() noraise {
    safe_put("/api/config", body)
  })
}

///|
fn settings_update(
  emit : @cmd.Emit[SettingsMsg],
  msg : SettingsMsg,
  model : SettingsModel,
) -> (@cmd.Cmd, SettingsModel) {
  match msg {
    Init =>
      (
        @cmd.batch([
          fetch_config(emit),
          fetch_models(emit),
          fetch_server_info(emit),
          locale_change_cmd(emit, LocaleChanged),
        ]),
        { ..model, loading: true, locale: i18n_get_locale() },
      )
    ConfigLoaded(Ok(json)) => {
      let cfg = json
      let model_id = json_str(cfg, "current_model_id", "")
      let perm = json_str(cfg, "permission_mode", "confirm_safes")
      let tokens = json_int(cfg, "max_tokens", 4096).to_string()
      let verb = json_bool(cfg, "verbose", false)
      (
        @cmd.none,
        {
          ..model,
          config: cfg,
          loading: false,
          selected_model: model_id,
          permission_mode: perm,
          max_tokens: tokens,
          verbose: verb,
        },
      )
    }
    ConfigLoaded(Err(_)) => {
      app_notify(t("settings.failed_load"), "error")
      (@cmd.none, { ..model, loading: false })
    }
    ModelsLoaded(Ok(json)) => {
      let items = match json {
        Object(map) =>
          match map.get("models") {
            Some(Array(arr)) => arr
            _ => []
          }
        Array(arr) => arr
        _ => []
      }
      (@cmd.none, { ..model, models: items })
    }
    ModelsLoaded(Err(_)) => (@cmd.none, model)
    ServerInfoLoaded(Ok(json)) => (@cmd.none, { ..model, server_info: json })
    ServerInfoLoaded(Err(_)) => (@cmd.none, model)
    ClickSave => {
      let tokens_int = match model.max_tokens.parse_int() {
        Ok(n) => n
        Err(_) => 4096
      }
      let body = Json::object(
        Map::of([
          ("permission_mode", Json::string(model.permission_mode)),
          ("max_tokens", Json::number(tokens_int.to_double())),
          ("verbose", Json::boolean(model.verbose)),
          ("current_model_id", Json::string(model.selected_model)),
        ]),
      )
      (save_config(emit, body), { ..model, busy: true })
    }
    SaveDone(Ok(json)) => {
      app_notify(t("settings.saved"), "success")
      (@cmd.none, { ..model, config: json, busy: false })
    }
    SaveDone(Err(_)) => {
      app_notify(t("settings.failed"), "error")
      (@cmd.none, { ..model, busy: false })
    }
    ModelChanged(v) => (@cmd.none, { ..model, selected_model: v })
    PermissionChanged(v) => (@cmd.none, { ..model, permission_mode: v })
    MaxTokensChanged(v) => (@cmd.none, { ..model, max_tokens: v })
    ToggleVerbose => (@cmd.none, { ..model, verbose: not(model.verbose) })
    LocaleChanged => (@cmd.none, { ..model, locale: i18n_get_locale() })
  }
}

// ── Views ────────────────────────────────────────────────────────

///|
fn settings_view(
  emit : @cmd.Emit[SettingsMsg],
  model : SettingsModel,
) -> @html.Html {
  if model.loading {
    @html.div(class="text-center", [
      @html.div(class="spinner", style=["margin:40px auto"], []),
    ])
  } else {
    let children : Array[@html.Html] = []
    // Model configuration
    children.push(settings_model_section(emit, model))
    // Permissions
    children.push(settings_permissions_section(emit, model))
    // Generation
    children.push(settings_generation_section(emit, model))
    // Server info
    children.push(settings_server_info_section(emit, model))
    // Save button
    children.push(
      @html.div(
        style=["padding-top:12px"],
        [
          @html.button(
            class="btn btn-primary",
            on_click=emit(ClickSave),
            style=if model.busy { ["opacity:0.5", "pointer-events:none"] } else { [] },
            t("settings.save"),
          ),
        ],
      ),
    )
    @html.div([], children)
  }
}

///|
fn settings_model_section(
  emit : @cmd.Emit[SettingsMsg],
  model : SettingsModel,
) -> @html.Html {
  let children : Array[@html.Html] = []
  children.push(@html.div(class="settings-group-title", t("settings.model_config")))

  if model.models.is_empty() {
    // No models configured - show readonly text
    let current = json_str(model.config, "current_model_id", "")
    let display = if current.is_empty() {
      t("settings.not_configured")
    } else {
      current
    }
    children.push(
      @html.div(class="settings-field", [
        @html.label([], t("settings.current_model")),
        @html.input(
          input_type=@html.Text,
          value=display,
          read_only=true,
          style=input_style(),
        ),
        @html.div(class="help-text", t("settings.no_models")),
      ]),
    )
  } else {
    // Model select dropdown
    let options : Array[@html.Html] = []
    for m in model.models {
      let id = json_str(m, "id", "")
      let label = if id.is_empty() {
        json_str(m, "name", "")
      } else {
        id
      }
      let display = if label.is_empty() {
        json_str(m, "model", "")
      } else {
        label
      }
      options.push(
        @html.option(
          value=id,
          selected=id == model.selected_model,
          display,
        ),
      )
    }
    children.push(
      @html.div(class="settings-field", [
        @html.label([], t("settings.active_model")),
        @html.select(
          on_change=s => emit(ModelChanged(s)),
          style=input_style(),
          options,
        ),
        @html.div(class="help-text", t("settings.select_model")),
      ]),
    )
  }

  @html.div(class="settings-group", children)
}

///|
fn settings_permissions_section(
  emit : @cmd.Emit[SettingsMsg],
  model : SettingsModel,
) -> @html.Html {
  let children : Array[@html.Html] = []
  children.push(@html.div(class="settings-group-title", t("settings.permissions")))

  let options : Array[@html.Html] = []
  options.push(
    @html.option(
      value="auto_approve",
      selected=model.permission_mode == "auto_approve",
      t("settings.auto_approve"),
    ),
  )
  options.push(
    @html.option(
      value="confirm_safes",
      selected=model.permission_mode == "confirm_safes",
      t("settings.confirm_safe"),
    ),
  )
  options.push(
    @html.option(
      value="confirm_all",
      selected=model.permission_mode == "confirm_all",
      t("settings.confirm_all"),
    ),
  )

  // Description for current mode
  let desc = match model.permission_mode {
    "auto_approve" => t("settings.auto_approve_desc")
    "confirm_safes" => t("settings.confirm_safe_desc")
    "confirm_all" => t("settings.confirm_all_desc")
    _ => ""
  }

  children.push(
    @html.div(class="settings-field", [
      @html.label([], t("settings.permission_mode")),
      @html.select(
        on_change=s => emit(PermissionChanged(s)),
        style=input_style(),
        options,
      ),
      @html.div(class="help-text", desc),
    ]),
  )

  @html.div(class="settings-group", children)
}

///|
fn settings_generation_section(
  emit : @cmd.Emit[SettingsMsg],
  model : SettingsModel,
) -> @html.Html {
  let children : Array[@html.Html] = []
  children.push(@html.div(class="settings-group-title", t("settings.generation")))

  // Max tokens
  children.push(
    @html.div(class="settings-field", [
      @html.label([], t("settings.max_tokens")),
      @html.input(
        input_type=@html.Number,
        value=model.max_tokens,
        min=Some(256.0),
        max=Some(200000.0),
        step=Some(256.0),
        on_change=s => emit(MaxTokensChanged(s)),
        style=input_style(),
      ),
      @html.div(class="help-text", t("settings.max_tokens_help")),
    ]),
  )

  // Verbose toggle
  let toggle_style = [
    "width:40px",
    "height:22px",
    "border-radius:11px",
    "background:var(--bg-tertiary)",
    "border:1px solid var(--border)",
    "position:relative",
    "cursor:pointer",
    "transition:background 0.2s",
    if model.verbose { "background:var(--accent)" } else { "" },
  ]

  let dot_style = [
    "width:16px",
    "height:16px",
    "border-radius:50%",
    "background:white",
    "position:absolute",
    "top:2px",
    if model.verbose { "right:2px" } else { "left:2px" },
    "transition:left 0.2s, right 0.2s",
  ]

  children.push(
    @html.div(class="settings-field", [
      @html.div(class="toggle-wrapper", style=["display:flex", "align-items:center", "justify-content:space-between"], [
        @html.label([], t("settings.verbose_mode")),
        @html.div(
          on_click=emit(ToggleVerbose),
          style=toggle_style,
          [
            @html.div(style=dot_style, ""),
          ],
        ),
      ]),
      @html.div(class="help-text", t("settings.verbose_help")),
    ]),
  )

  @html.div(class="settings-group", children)
}

///|
fn settings_server_info_section(
  emit : @cmd.Emit[SettingsMsg],
  model : SettingsModel,
) -> @html.Html {
  let children : Array[@html.Html] = []
  children.push(@html.div(class="settings-group-title", t("settings.server_info")))

  // Check if server_info has any data
  let is_null = match model.server_info {
    Null => true
    _ => false
  }

  if is_null {
    children.push(
      @html.div(
        class="text-muted",
        style=["font-size:12px"],
        t("settings.loading"),
      ),
    )
  } else {
    let version = json_str(model.server_info, "version", "unknown")
    let uptime_sec = json_int(model.server_info, "uptime_seconds", 0)
    let active_sessions = json_int(model.server_info, "active_sessions", 0)
    let name = json_str(model.server_info, "name", "MBOpenClacky")
    let uptime_str = format_uptime(uptime_sec)

    children.push(
      @html.div(
        style=["display:grid", "grid-template-columns:1fr 1fr", "gap:8px", "font-size:12px"],
        [
          @html.div([], [
            @html.strong([], "\{t("settings.version")} "),
            version,
          ]),
          @html.div([], [
            @html.strong([], "\{t("settings.uptime")} "),
            uptime_str,
          ]),
          @html.div([], [
            @html.strong([], "\{t("settings.active_sessions")} "),
            active_sessions.to_string(),
          ]),
          @html.div([], [
            @html.strong([], "\{t("settings.name")} "),
            name,
          ]),
        ],
      ),
    )
  }

  @html.div(class="settings-group", children)
}

///| Format uptime seconds to human-readable string.
fn format_uptime(seconds : Int) -> String {
  let h = seconds / 3600
  let m = (seconds % 3600) / 60
  let s = seconds % 60
  if h > 0 {
    "\{h}h \{m}m"
  } else if m > 0 {
    "\{m}m \{s}s"
  } else {
    "\{s}s"
  }
}

///|
fn build_settings_cell() -> (@cmd.Emit[SettingsMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_settings_model(),
    update=settings_update,
    view=settings_view,
  )
}
