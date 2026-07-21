///|
/// Shell cell - handles view routing, keyboard shortcuts, and sidebar
/// navigation. Mounts to `#mb-root`; does not render visible content
/// itself (the sidebar HTML stays in index.html until Task Pack G).
struct ShellModel {
  active_view : String
} derive(Show)

///|
enum ShellMsg {
  Init
  SwitchView(String)
  KeyEscape
  KeyCtrlN
  LocaleChanged
} derive(Show)

///|
fn initial_shell_model() -> ShellModel {
  { active_view: "chat" }
}

///|
fn shell_update(
  emit : @cmd.Emit[ShellMsg],
  msg : ShellMsg,
  model : ShellModel,
) -> (@cmd.Cmd, ShellModel) {
  match msg {
    Init =>
      (
        @cmd.custom_cmd(scheduler => {
          js_on_show_view(view => scheduler.add(emit(SwitchView(view))))
          js_bind_nav_buttons(view => scheduler.add(emit(SwitchView(view))))
          js_on_key_escape(() => scheduler.add(emit(KeyEscape)))
          js_on_key_ctrl_n(() => scheduler.add(emit(KeyCtrlN)))
          i18n_on_locale_changed(() => scheduler.add(emit(LocaleChanged)))
          js_translate_dom(t)
        }),
        model,
      )
    SwitchView(view) => {
      js_show_view(view)
      (none, { ..model, active_view: view })
    }
    KeyEscape => {
      js_close_sidebar()
      (none, model)
    }
    KeyCtrlN => {
      js_dispatch_new_session()
      (none, model)
    }
    LocaleChanged => {
      js_translate_dom(t)
      (none, model)
    }
  }
}

///|
fn shell_view(_emit : @cmd.Emit[ShellMsg], _model : ShellModel) -> @html.Html {
  @html.text("")
}

///|
fn build_shell_cell() -> (@cmd.Emit[ShellMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_shell_model(),
    update=shell_update,
    view=shell_view,
  )
}
