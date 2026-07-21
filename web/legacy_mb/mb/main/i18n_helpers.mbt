///| Shared i18n helpers for all rabbita cells.

///|
/// Look up a translation key in the MoonBit dictionary for the current
/// locale, falling back to English, then to the key itself.
fn i18n_lookup(key : String) -> String {
  let locale = i18n_get_locale()
  let dict = if locale == "zh" {
    i18n_dict_zh
  } else {
    i18n_dict_en
  }
  match dict.get(key) {
    Some(v) => v
    None =>
      match i18n_dict_en.get(key) {
        Some(v) => v
        None => key
      }
  }
}

///|
/// Replace `{{param}}` placeholders in text with values from params.
fn i18n_substitute(text : String, params : Map[String, String]) -> String {
  let buf = StringBuilder::new()
  let chars = text.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len {
    if i + 1 < len && chars[i] == '{' && chars[i + 1] == '{' {
      let mut end = i + 2
      while end + 1 < len && not(chars[end] == '}' && chars[end + 1] == '}') {
        end = end + 1
      }
      if end + 1 < len {
        let name = text.substring(start=i + 2, end=end)
        match params.get(name) {
          Some(v) => buf.write_string(v)
          None =>
            match i18n_dict_en.get(name) {
              Some(v) => buf.write_string(v)
              None => {
                buf.write_string("{{")
                buf.write_string(name)
                buf.write_string("}}")
              }
            }
        }
        i = end + 2
      } else {
        buf.write_char(chars[i])
        i = i + 1
      }
    } else {
      buf.write_char(chars[i])
      i = i + 1
    }
  }
  buf.to_string()
}

///|
/// Translate a key with no parameters.
fn t(key : String) -> String {
  i18n_lookup(key)
}

///|
/// Translate a key with a single `{{param}}` substitution.
fn t1(key : String, name : String, value : String) -> String {
  let text = i18n_lookup(key)
  i18n_substitute(text, Map::of([(name, value)]))
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
