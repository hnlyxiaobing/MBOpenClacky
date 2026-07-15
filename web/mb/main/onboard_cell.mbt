///| Onboard wizard panel - rabbita replacement for `web/js/onboard.js`.
///
/// 3-step onboarding wizard: welcome → configure → complete.
/// API endpoints:
///   - `GET /api/onboard/status` - check completion + step
///   - `POST /api/onboard/start` - start the wizard
///   - `POST /api/onboard/complete` - mark complete
///   - `POST /api/onboard/skip` - skip setup
///   - `PUT /api/config` - save api key + model

///|
priv enum OnboardMsg {
  Init
  StatusLoaded(Result[Json, String])
  ClickStart
  StartDone(Result[Json, String])
  ClickSkip
  SkipDone(Result[Json, String])
  ClickBack
  ClickNext
  ConfigSaved(Result[Json, String])
  ClickFinish
  CompleteDone(Result[Json, String])
  ApiKeyChanged(String)
  ModelChanged(String)
  LocaleChanged
}

///|
priv struct OnboardModel {
  step : Int
  completed : Bool
  device_code : String
  api_key : String
  model : String
  busy : Bool
  locale : String
}

///|
fn initial_onboard_model() -> OnboardModel {
  {
    step: 0,
    completed: false,
    device_code: "",
    api_key: "",
    model: "",
    busy: false,
    locale: "",
  }
}

///|
fn fetch_onboard_status(emit : @cmd.Emit[OnboardMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(StatusLoaded(r)), async fn() noraise {
    safe_get("/api/onboard/status")
  })
}

///|
fn start_onboard(emit : @cmd.Emit[OnboardMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(StartDone(r)), async fn() noraise {
    safe_post("/api/onboard/start", Json::null())
  })
}

///|
fn skip_onboard(emit : @cmd.Emit[OnboardMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(SkipDone(r)), async fn() noraise {
    safe_post("/api/onboard/skip", Json::null())
  })
}

///|
fn complete_onboard(emit : @cmd.Emit[OnboardMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(CompleteDone(r)), async fn() noraise {
    safe_post("/api/onboard/complete", Json::null())
  })
}

///|
fn save_config(emit : @cmd.Emit[OnboardMsg], api_key : String, model : String) -> @cmd.Cmd {
  @cmd.perform(r => emit(ConfigSaved(r)), async fn() noraise {
    let fields : Array[(String, Json)] = [("api_key", Json::string(api_key))]
    if not(model.is_empty()) {
      fields.push(("current_model_id", Json::string(model)))
    }
    safe_put("/api/config", Json::object(Map::from_array(fields)))
  })
}

///|
fn onboard_update(
  emit : @cmd.Emit[OnboardMsg],
  msg : OnboardMsg,
  model : OnboardModel,
) -> (@cmd.Cmd, OnboardModel) {
  match msg {
    Init =>
      (
        @cmd.batch([fetch_onboard_status(emit), locale_change_cmd(emit, LocaleChanged)]),
        { ..model, locale: i18n_get_locale() },
      )
    StatusLoaded(Ok(json)) => {
      let completed = json_bool(json, "completed", false)
      let step = json_int(json, "step", 0)
      let device_code = json_str(json, "device_code", "")
      (@cmd.none, { ..model, completed, step, device_code })
    }
    StatusLoaded(Err(_)) => (@cmd.none, { ..model, busy: false })
    ClickStart => (start_onboard(emit), { ..model, busy: true })
    StartDone(Ok(json)) => {
      let device_code = json_str(json, "device_code", "")
      (@cmd.none, { ..model, step: 1, device_code, busy: false })
    }
    StartDone(Err(_)) =>
      // Even if API fails, proceed to configure step
      (@cmd.none, { ..model, step: 1, busy: false })
    ClickSkip => (skip_onboard(emit), { ..model, busy: true })
    SkipDone(_) => {
      app_show_view("chat")
      app_notify(t("onboard.skip_notice"), "info")
      (@cmd.none, { ..model, completed: true, busy: false })
    }
    ClickBack => {
      let prev = if model.step > 0 { model.step - 1 } else { 0 }
      (@cmd.none, { ..model, step: prev })
    }
    ClickNext =>
      if not(model.api_key.is_empty()) {
        (
          save_config(emit, model.api_key, model.model),
          { ..model, busy: true },
        )
      } else {
        // No API key - just go to complete step
        (@cmd.none, { ..model, step: 2 })
      }
    ConfigSaved(Ok(_)) => {
      (@cmd.none, { ..model, step: 2, busy: false })
    }
    ConfigSaved(Err(e)) => {
      app_notify(t1("onboard.config_failed", "error", e), "warning")
      (@cmd.none, { ..model, busy: false })
    }
    ClickFinish => (complete_onboard(emit), { ..model, busy: true })
    CompleteDone(_) => {
      app_show_view("chat")
      app_notify(t("onboard.welcome_notif"), "success")
      (@cmd.none, { ..model, completed: true, busy: false })
    }
    ApiKeyChanged(v) => (@cmd.none, { ..model, api_key: v })
    ModelChanged(v) => (@cmd.none, { ..model, model: v })
    LocaleChanged => (@cmd.none, { ..model, locale: i18n_get_locale() })
  }
}

// ── Views ────────────────────────────────────────────────────────

///|
fn onboard_view(
  emit : @cmd.Emit[OnboardMsg],
  model : OnboardModel,
) -> @html.Html {
  if model.completed {
    onboard_complete_view(emit, model)
  } else {
    match model.step {
      0 => onboard_welcome_view(emit, model)
      1 => onboard_configure_view(emit, model)
      2 => onboard_complete_view(emit, model)
      _ => onboard_welcome_view(emit, model)
    }
  }
}

///|
fn onboard_progress(active : Int) -> Array[@html.Html] {
  let dots : Array[@html.Html] = []
  for i in 0..<3 {
    let cls = if i < active {
      "onboard-dot done"
    } else if i == active {
      "onboard-dot active"
    } else {
      "onboard-dot"
    }
    dots.push(
      @html.div(class=cls, style=["width:10px", "height:10px", "border-radius:50%", "background:var(--border)"], ""),
    )
  }
  dots
}

///|
fn onboard_welcome_view(
  emit : @cmd.Emit[OnboardMsg],
  _ : OnboardModel,
) -> @html.Html {
  @html.div(class="onboard-wizard", [
    @html.div(class="onboard-step", [
      @html.div(
        style=["font-size:48px", "margin-bottom:16px", "text-align:center"],
        "👋",
      ),
      @html.h3(
        style=["font-size:22px", "margin-bottom:8px", "text-align:center"],
        t("onboard.welcome"),
      ),
      @html.p(
        style=[
          "color:var(--text-secondary)",
          "margin-bottom:24px",
          "max-width:400px",
          "line-height:1.6",
          "text-align:center",
        ],
        t("onboard.subtitle"),
      ),
      @html.div(
        style=["text-align:left", "max-width:380px", "margin:0 auto 24px"],
        [
          onboard_feature_row("💬", t("onboard.feature_chat")),
          onboard_feature_row("🔧", t("onboard.feature_tools")),
          onboard_feature_row("🛠️", t("onboard.feature_skills")),
          onboard_feature_row("🔗", t("onboard.feature_mcp")),
        ],
      ),
      @html.div(
        style=["display:flex", "gap:10px", "justify-content:center"],
        [
          @html.button(
            class="btn btn-primary",
            on_click=emit(ClickStart),
            style=["padding:10px 28px", "font-size:14px"],
            t("onboard.get_started"),
          ),
          @html.button(
            class="btn btn-ghost",
            on_click=emit(ClickSkip),
            t("onboard.skip"),
          ),
        ],
      ),
      @html.div(
        style=["display:flex", "gap:6px", "justify-content:center", "margin-top:32px"],
        onboard_progress(0),
      ),
    ]),
  ])
}

///|
fn onboard_feature_row(emoji : String, text : String) -> @html.Html {
  @html.div(
    style=["display:flex", "align-items:center", "gap:10px", "margin-bottom:12px"],
    [
      @html.span(style=["font-size:18px"], emoji),
      @html.span(
        style=["font-size:13px", "color:var(--text-secondary)"],
        text,
      ),
    ],
  )
}

///|
fn onboard_configure_view(
  emit : @cmd.Emit[OnboardMsg],
  model : OnboardModel,
) -> @html.Html {
  let children : Array[@html.Html] = [
    @html.div(
      style=["font-size:48px", "margin-bottom:16px", "text-align:center"],
      "⚙️",
    ),
    @html.h3(
      style=["font-size:20px", "margin-bottom:8px", "text-align:center"],
      t("onboard.config_title"),
    ),
    @html.p(
      style=[
        "color:var(--text-secondary)",
        "margin-bottom:24px",
        "max-width:400px",
        "line-height:1.6",
        "text-align:center",
      ],
      t("onboard.config_desc"),
    ),
    @html.div(
      style=["max-width:420px", "margin:0 auto", "text-align:left"],
      [
        @html.div(class="settings-field", [
          @html.label(t("onboard.api_key")),
          @html.input(
            input_type=@html.Password,
            value=model.api_key,
            placeholder="sk-...",
            on_change=s => emit(ApiKeyChanged(s)),
            style=input_style(),
          ),
          @html.div(class="help-text", t("onboard.api_key_help")),
        ]),
        @html.div(class="settings-field", [
          @html.label(t("onboard.preferred_model")),
          @html.select(
            on_change=s => emit(ModelChanged(s)),
            style=input_style(),
            [
              @html.option(value="", selected=model.model == "", t("onboard.default")),
              @html.option(
                value="claude-sonnet-4-20250514",
                selected=model.model == "claude-sonnet-4-20250514",
                "Claude Sonnet 4",
              ),
              @html.option(
                value="gpt-4o",
                selected=model.model == "gpt-4o",
                "GPT-4o",
              ),
              @html.option(
                value="gemini-2.0-flash",
                selected=model.model == "gemini-2.0-flash",
                "Gemini 2.0 Flash",
              ),
            ],
          ),
          @html.div(class="help-text", t("onboard.model_help")),
        ]),
      ],
    ),
  ]

  // Show device code if present
  if not(model.device_code.is_empty()) {
    children.push(
      @html.div(
        style=["max-width:420px", "margin:16px auto 0", "text-align:left"],
        [
          @html.div(class="settings-field", [
            @html.label(t("onboard.device_code")),
            @html.div(
              style=[
                "font-family:var(--font-mono)",
                "font-size:14px",
                "color:var(--accent)",
                "padding:8px 12px",
                "background:var(--bg-tertiary)",
                "border-radius:var(--radius-sm)",
                "letter-spacing:2px",
              ],
              model.device_code,
            ),
            @html.div(class="help-text", t("onboard.device_code_help")),
          ]),
        ],
      ),
    )
  }

  children.push(
    @html.div(
      style=["display:flex", "gap:10px", "justify-content:center", "margin-top:24px"],
      [
        @html.button(
          class="btn btn-ghost",
          on_click=emit(ClickBack),
          t("onboard.back"),
        ),
        @html.button(
          class="btn btn-primary",
          on_click=emit(ClickNext),
          style=["padding:10px 28px"],
          t("onboard.next"),
        ),
      ],
    ),
  )

  children.push(
    @html.div(
      style=["display:flex", "gap:6px", "justify-content:center", "margin-top:32px"],
      onboard_progress(1),
    ),
  )

  @html.div(class="onboard-wizard", [
    @html.div(class="onboard-step", children),
  ])
}

///|
fn onboard_complete_view(
  emit : @cmd.Emit[OnboardMsg],
  _ : OnboardModel,
) -> @html.Html {
  @html.div(class="onboard-wizard", [
    @html.div(class="onboard-step", [
      @html.div(
        style=["font-size:48px", "margin-bottom:16px", "text-align:center"],
        "🎉",
      ),
      @html.h3(
        style=["font-size:22px", "margin-bottom:8px", "text-align:center"],
        t("onboard.all_set"),
      ),
      @html.p(
        style=[
          "color:var(--text-secondary)",
          "margin-bottom:24px",
          "max-width:400px",
          "line-height:1.6",
          "text-align:center",
        ],
        t("onboard.all_set_desc"),
      ),
      @html.div(
        style=["display:flex", "gap:10px", "justify-content:center"],
        [
          @html.button(
            class="btn btn-primary",
            on_click=emit(ClickFinish),
            style=["padding:10px 28px", "font-size:14px"],
            t("onboard.start_coding"),
          ),
        ],
      ),
      @html.div(
        style=["display:flex", "gap:6px", "justify-content:center", "margin-top:32px"],
        onboard_progress(2),
      ),
    ]),
  ])
}

///|
fn build_onboard_cell() -> (@cmd.Emit[OnboardMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_onboard_model(),
    update=onboard_update,
    view=onboard_view,
  )
}
