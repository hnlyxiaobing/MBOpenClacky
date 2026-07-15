///| Stats panel - rabbita replacement for `App.loadStats` in `web/js/app.js`.

///|
priv enum StatsMsg {
  Init
  StatsLoaded(Result[Json, String])
  LocaleChanged
}

///|
priv struct StatsModel {
  stats : Json
  loading : Bool
  error : String
  locale : String
}

///|
fn initial_stats_model() -> StatsModel {
  { stats: Json::null(), loading: true, error: "", locale: "" }
}

///|
fn stats_update(
  emit : @cmd.Emit[StatsMsg],
  msg : StatsMsg,
  model : StatsModel,
) -> (@cmd.Cmd, StatsModel) {
  match msg {
    Init =>
      (
        @cmd.batch([
          @cmd.perform(r => emit(StatsLoaded(r)), async fn() noraise {
            safe_get("/api/stats")
          }),
          locale_change_cmd(emit, LocaleChanged),
        ]),
        { ..model, locale: i18n_get_locale() },
      )
    StatsLoaded(Ok(json)) =>
      (none, { ..model, stats: json, loading: false, error: "" })
    StatsLoaded(Err(e)) =>
      (none, { ..model, loading: false, error: e })
    LocaleChanged => (none, { ..model, locale: i18n_get_locale() })
  }
}

///|
fn json_num(json : Json, key : String) -> Double {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(Number(n)) => n
        Some(True) => 1.0
        Some(False) => 0.0
        _ => 0.0
      }
    _ => 0.0
  }
}

///|
fn stats_view(
  emit : @cmd.Emit[StatsMsg],
  model : StatsModel,
) -> @html.Html {
  if model.loading {
    return @html.div(class="text-center", [
      @html.div(class="spinner", style=["margin:40px auto"], ""),
    ])
  }
  if model.error != "" {
    return @html.p(class="text-muted text-center", t("stats.failed_load"))
  }
  let s = model.stats
  @html.div(class="stats-grid", [
    @html.div(class="stat-card", [
      @html.div(
        class="stat-card-value",
        json_num(s, "total_sessions").to_int().to_string(),
      ),
      @html.div(class="stat-card-label", t("stats.total_sessions")),
    ]),
    @html.div(class="stat-card", [
      @html.div(
        class="stat-card-value",
        "$" + json_num(s, "total_cost_usd").to_string(),
      ),
      @html.div(class="stat-card-label", t("stats.total_cost")),
    ]),
    @html.div(class="stat-card", [
      @html.div(
        class="stat-card-value",
        json_num(s, "total_iterations").to_int().to_string(),
      ),
      @html.div(class="stat-card-label", t("stats.total_iterations")),
    ]),
    @html.div(class="stat-card", [
      @html.div(
        class="stat-card-value",
        json_num(s, "total_tasks").to_int().to_string(),
      ),
      @html.div(class="stat-card-label", t("stats.total_tasks")),
    ]),
  ])
}

///|
fn build_stats_cell() -> (@cmd.Emit[StatsMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_stats_model(),
    update=stats_update,
    view=stats_view,
  )
}
