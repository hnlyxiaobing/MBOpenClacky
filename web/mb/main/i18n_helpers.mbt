///| Shared i18n helpers for all rabbita cells.

///|
/// Translate a key with no parameters. Shorthand for
/// `i18n_t(key, "{}")`.
fn t(key : String) -> String {
  i18n_t(key, "{}")
}

///|
/// Translate a key with a single `{{param}}` substitution.
/// Builds `{"name":"value"}` as the params JSON.
fn t1(key : String, name : String, value : String) -> String {
  let body = Json::object(Map::of([(name, Json::string(value))]))
  i18n_t(key, body.stringify())
}

///|
/// Build a `@cmd.Cmd` that registers a one-time DOM listener for the
/// `i18n:locale-changed` event. When the locale changes, the listener
/// calls `scheduler.add(emit(msg))`, feeding `msg` back into the
/// cell's update loop. The cell should handle `msg` by refreshing
/// `model.locale` so the view re-renders with new translations.
fn[Msg] locale_change_cmd(emit : @cmd.Emit[Msg], msg : Msg) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    i18n_on_locale_changed(() => scheduler.add(emit(msg)))
  })
}

///|
/// Build a `@cmd.Cmd` that registers a DOM listener for the
/// `skill:open-editor` CustomEvent dispatched by `skill_editor_open`.
/// When the event fires, the listener calls
/// `scheduler.add(emit(to_msg(name)))`, feeding an `OpenEditor(name)`
/// message back into the cell's update loop.
fn[Msg] skill_open_cmd(
  emit : @cmd.Emit[Msg],
  to_msg : (String) -> Msg,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    on_skill_open_editor(name => scheduler.add(emit(to_msg(name))))
  })
}
