///| Billing panel - rabbita replacement for `web/js/billing.js`.
///
/// Shows subscription status, activate form, and usage statistics.
/// API endpoints:
///   - `GET /api/billing/status` - subscription status
///   - `GET /api/billing/usage` - usage statistics
///   - `POST /api/billing/activate` - activate subscription

///|
priv enum BillingMsg {
  Init
  StatusLoaded(Result[Json, String])
  UsageLoaded(Result[Json, String])
  PlanChanged(String)
  KeyChanged(String)
  ClickActivate
  ActivateDone(Result[Json, String])
  LocaleChanged
}

///|
priv struct BillingModel {
  status : Json
  usage : Json
  loading : Bool
  form_plan : String
  form_key : String
  busy : Bool
  locale : String
}

///|
fn initial_billing_model() -> BillingModel {
  {
    status: Json::null(),
    usage: Json::null(),
    loading: true,
    form_plan: "monthly",
    form_key: "",
    busy: false,
    locale: "",
  }
}

///|
fn fetch_billing_status(emit : @cmd.Emit[BillingMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(StatusLoaded(r)), async fn() noraise {
    safe_get("/api/billing/status")
  })
}

///|
fn fetch_billing_usage(emit : @cmd.Emit[BillingMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(UsageLoaded(r)), async fn() noraise {
    safe_get("/api/billing/usage")
  })
}

///|
fn billing_update(
  emit : @cmd.Emit[BillingMsg],
  msg : BillingMsg,
  model : BillingModel,
) -> (@cmd.Cmd, BillingModel) {
  match msg {
    Init =>
      (
        @cmd.batch([
          fetch_billing_status(emit),
          fetch_billing_usage(emit),
          locale_change_cmd(emit, LocaleChanged),
        ]),
        { ..model, loading: true, locale: i18n_get_locale() },
      )
    StatusLoaded(Ok(json)) => (@cmd.none, { ..model, status: json, loading: false })
    StatusLoaded(Err(_e)) =>
      (@cmd.none, { ..model, status: Json::null(), loading: false })
    UsageLoaded(Ok(json)) => (@cmd.none, { ..model, usage: json })
    UsageLoaded(Err(_e)) => (@cmd.none, { ..model, usage: Json::null() })
    PlanChanged(v) => (@cmd.none, { ..model, form_plan: v })
    KeyChanged(v) => (@cmd.none, { ..model, form_key: v })
    ClickActivate => {
      let body = Json::object(
        Map::of([
          ("plan", Json::string(model.form_plan)),
          ("key", Json::string(model.form_key.trim().to_owned())),
        ]),
      )
      let cmd = @cmd.perform(r => emit(ActivateDone(r)), async fn() noraise {
        safe_post("/api/billing/activate", body)
      })
      (cmd, { ..model, busy: true })
    }
    ActivateDone(Ok(_)) => {
      app_notify(t("billing.activated"), "success")
      (
        @cmd.batch([fetch_billing_status(emit), fetch_billing_usage(emit)]),
        { ..model, busy: false, form_key: "" },
      )
    }
    ActivateDone(Err(e)) => {
      let msg = if e != "" { e } else { t("billing.activation_failed") }
      app_notify(msg, "error")
      (@cmd.none, { ..model, busy: false })
    }
    LocaleChanged => (@cmd.none, { ..model, locale: i18n_get_locale() })
  }
}

///| Format a number with K/M suffix.
fn billing_format_num(n : Int) -> String {
  if n >= 1_000_000 {
    let m = (n.to_double() / 1_000_000.0)
    billing_truncate_dec(m.to_string()) + "M"
  } else if n >= 1_000 {
    let k = (n.to_double() / 1_000.0)
    billing_truncate_dec(k.to_string()) + "K"
  } else {
    n.to_string()
  }
}

fn billing_truncate_dec(s : String) -> String {
  let parts = s.split(".").to_array().map(fn(sv) { sv.to_string() })
  if parts.length() >= 2 {
    let dec = parts[1]
    parts[0] + "." + (if dec.length() >= 1 { dec[:1].to_string() } else { "" })
  } else {
    s
  }
}

///| Format cost as $X.XXXX
fn billing_format_cost(cost : Double) -> String {
  "$" + cost.to_string()
}

///|
fn billing_view(
  emit : @cmd.Emit[BillingMsg],
  model : BillingModel,
) -> @html.Html {
  if model.loading {
    return @html.div(class="text-center", [
      @html.div(class="spinner", style=["margin:40px auto"], @html.nothing),
    ])
  }

  // Extract status data
  let is_active = json_bool(model.status, "active", false)
  let plan = json_str(model.status, "plan", "N/A")
  let expires = json_str(model.status, "expires_at", "N/A")

  // Extract usage data
  let total_tokens = json_int(model.usage, "total_tokens", 0)
  let model_count = billing_count_keys(model.usage, "by_model")
  let day_count = billing_count_keys(model.usage, "by_day")

  // Build children
  let children : Array[@html.Html] = []

  // Status card
  let status_text = if is_active { t("billing.active") } else { t("billing.inactive") }
  let status_cls = if is_active { "status-badge running" } else { "status-badge" }
  let status_style = if is_active {
    ["font-size:10px", "padding:2px 8px", "border-radius:10px"]
  } else {
    ["font-size:10px", "padding:2px 8px", "border-radius:10px", "background:rgba(247,118,142,0.15)", "color:var(--danger)"]
  }
  children.push(
    @html.div(class="stat-card", style=["margin-bottom:20px", "text-align:left", "padding:20px"], [
      @html.div(class="settings-group-title", t("billing.subscription")),
      @html.div(
        style=["display:grid", "grid-template-columns:1fr 1fr 1fr", "gap:16px", "align-items:center"],
        [
          @html.div([
            @html.div(
              style=["font-size:11px", "color:var(--text-muted)", "text-transform:uppercase", "letter-spacing:0.5px", "margin-bottom:4px"],
              t("billing.status"),
            ),
            @html.span(class=status_cls, style=status_style, status_text),
          ]),
          @html.div([
            @html.div(
              style=["font-size:11px", "color:var(--text-muted)", "text-transform:uppercase", "letter-spacing:0.5px", "margin-bottom:4px"],
              t("billing.plan"),
            ),
            @html.div(style=["font-size:14px", "font-weight:600", "color:var(--text-primary)"], plan),
          ]),
          @html.div([
            @html.div(
              style=["font-size:11px", "color:var(--text-muted)", "text-transform:uppercase", "letter-spacing:0.5px", "margin-bottom:4px"],
              t("billing.expires"),
            ),
            @html.div(style=["font-size:14px", "color:var(--text-secondary)"], expires),
          ]),
        ],
      ),
    ]),
  )

  // Activate section (only if not active)
  if !is_active {
    let plan_options = [
      @html.option(value="monthly", selected=model.form_plan == "monthly", t("billing.monthly")),
      @html.option(value="yearly", selected=model.form_plan == "yearly", t("billing.yearly")),
      @html.option(value="pro", selected=model.form_plan == "pro", t("billing.pro")),
    ]
    children.push(
      @html.div(class="stat-card", style=["margin-bottom:20px", "text-align:left", "padding:20px"], [
        @html.div(class="settings-group-title", t("billing.activate")),
        @html.div(class="settings-field", [
          @html.label(t("billing.plan")),
          @html.select(on_change=s => emit(PlanChanged(s)), plan_options),
        ]),
        @html.div(class="settings-field", [
          @html.label(t("billing.license_key")),
          @html.input(
            input_type=@html.Text,
            value=model.form_key,
            placeholder=t("billing.license_placeholder"),
            on_change=s => emit(KeyChanged(s)),
            style=input_style(),
          ),
        ]),
        @html.button(
          class="btn btn-primary",
          on_click=emit(ClickActivate),
          if model.busy { "..." } else { t("billing.activate_btn") },
        ),
      ]),
    )
  }

  // Usage stats
  children.push(
    @html.div(class="stats-grid", style=["margin-bottom:20px"], [
      @html.div(class="stat-card", [
        @html.div(class="stat-card-value", billing_format_num(total_tokens)),
        @html.div(class="stat-card-label", t("billing.total_tokens")),
      ]),
      @html.div(class="stat-card", [
        @html.div(class="stat-card-value", model_count.to_string()),
        @html.div(class="stat-card-label", t("billing.models_used")),
      ]),
      @html.div(class="stat-card", [
        @html.div(class="stat-card-value", day_count.to_string()),
        @html.div(class="stat-card-label", t("billing.active_days")),
      ]),
    ]),
  )

  // Model breakdown table
  let model_table = billing_model_table(model.usage)
  match model_table {
    Some(html) => children.push(html)
    None => ()
  }

  // Daily usage chart
  let chart = billing_usage_chart(model.usage)
  match chart {
    Some(html) => children.push(html)
    None => ()
  }

  @html.div(children)
}

///| Count keys in a JSON object field.
fn billing_count_keys(json : Json, field : String) -> Int {
  let count = Ref::new(0)
  match json {
    Object(map) =>
      match map.get(field) {
        Some(Object(inner)) => inner.each(fn(_k, _v) { count.val += 1 })
        _ => ()
      }
    _ => ()
  }
  count.val
}

///| Build per-model cost breakdown table.
fn billing_model_table(usage : Json) -> @html.Html? {
  let entries : Array[(String, Int, Double)] = []
  match usage {
    Object(map) =>
      match map.get("by_model") {
        Some(Object(inner)) =>
          inner.each(fn(k, v) {
            let (tokens, cost) = match v {
              Object(m) =>
                (
                  json_int_from(v, "tokens", 0),
                  json_double_from(v, "cost", 0.0),
                )
              Number(n, ..) => (n.to_int(), 0.0)
              _ => (0, 0.0)
            }
            entries.push((k, tokens, cost))
          })
        _ => ()
      }
    _ => ()
  }
  if entries.is_empty() {
    return None
  }
  let rows = entries.map(fn(entry) {
    let (model, tokens, cost) = entry
    @html.tr([
      @html.td(style=["padding:8px 12px", "color:var(--text-primary)", "font-weight:500"], model),
      @html.td(style=["padding:8px 12px", "color:var(--text-secondary)"], billing_format_num(tokens)),
      @html.td(style=["padding:8px 12px", "color:var(--accent)"], billing_format_cost(cost)),
    ])
  })
  Some(
    @html.div(class="stat-card", style=["margin-bottom:20px", "text-align:left", "padding:20px"], [
      @html.div(class="settings-group-title", t("billing.cost_by_model")),
      @html.table(
        style=["width:100%", "border-collapse:collapse", "font-size:13px"],
        [
          @html.thead([
            @html.tr([
              @html.th(
                style=["text-align:left", "padding:8px 12px", "border-bottom:1px solid var(--border)", "color:var(--text-secondary)", "font-size:11px", "text-transform:uppercase", "letter-spacing:0.5px"],
                t("billing.model"),
              ),
              @html.th(
                style=["text-align:left", "padding:8px 12px", "border-bottom:1px solid var(--border)", "color:var(--text-secondary)", "font-size:11px", "text-transform:uppercase", "letter-spacing:0.5px"],
                t("billing.tokens"),
              ),
              @html.th(
                style=["text-align:left", "padding:8px 12px", "border-bottom:1px solid var(--border)", "color:var(--text-secondary)", "font-size:11px", "text-transform:uppercase", "letter-spacing:0.5px"],
                t("billing.est_cost"),
              ),
            ]),
          ]),
          @html.tbody(rows),
        ],
      ),
    ]),
  )
}

///| Build daily usage bar chart.
fn billing_usage_chart(usage : Json) -> @html.Html? {
  let entries : Array[(String, Int)] = []
  match usage {
    Object(map) =>
      match map.get("by_day") {
        Some(Object(inner)) =>
          inner.each(fn(k, v) {
            let tokens = match v {
              Object(m) => json_int_from(v, "tokens", 0)
              Number(n, ..) => n.to_int()
              _ => 0
            }
            entries.push((k, tokens))
          })
        _ => ()
      }
    _ => ()
  }
  if entries.is_empty() {
    return None
  }
  // Sort by date (entries.sort is available)
  entries.sort_by(fn(a, b) { a.0.compare(b.0) })
  // Find max for bar scaling
  let max_val = Ref::new(1)
  entries.each(fn(entry) { if entry.1 > max_val.val { max_val.val = entry.1 } })
  let bars = entries.map(fn(entry) {
    let (day, tokens) = entry
    let pct = if max_val.val > 0 {
      (tokens.to_double() / max_val.val.to_double() * 100.0)
    } else {
      0.0
    }
    let pct_str = if pct < 2.0 { "2" } else { pct.to_string() }
    let day_label = if day.length() >= 5 { day.substring(start=5) } else { day }
    @html.div(
      style=["flex:1", "display:flex", "flex-direction:column", "align-items:center", "gap:4px"],
      [
        @html.div(
          style=["width:100%", "min-width:8px", "height:" + pct_str + "%", "background:var(--accent)", "border-radius:3px 3px 0 0", "transition:height 0.3s ease"],
          title=day + ": " + billing_format_num(tokens) + " tokens",
          @html.nothing,
        ),
        @html.div(
          style=["font-size:9px", "color:var(--text-muted)", "white-space:nowrap", "overflow:hidden", "text-overflow:ellipsis", "max-width:100%"],
          day_label,
        ),
      ],
    )
  })
  Some(
    @html.div(class="stat-card", style=["text-align:left", "padding:20px"], [
      @html.div(class="settings-group-title", t("billing.daily_usage")),
      @html.div(
        style=["display:flex", "align-items:flex-end", "gap:4px", "height:120px", "padding-top:8px"],
        bars,
      ),
    ]),
  )
}

///| Extract a Double from a JSON object field.
fn json_double_from(json : Json, key : String, default : Double) -> Double {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(Number(n, ..)) => n
        _ => default
      }
    _ => default
  }
}

///| Extract an Int from a JSON object field (alias for shared json_int).
fn json_int_from(json : Json, key : String, default : Int) -> Int {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(Number(n, ..)) => n.to_int()
        _ => default
      }
    _ => default
  }
}

///|
fn build_billing_cell() -> (@cmd.Emit[BillingMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_billing_model(),
    update=billing_update,
    view=billing_view,
  )
}
