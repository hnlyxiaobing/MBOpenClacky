///| Profile panel — rabbita replacement for `web/js/profile.js`.
///
/// Renders the user-profile form (name / email / theme / language /
/// email-notifications toggle + save button) into the
/// `#profile-content` container mounted by `main.mbt`. State is fetched
/// from the existing MBOpenClacky backend at `/api/profile` via the
/// `safe_get / safe_put` bridges in `bridge.mbt` + `brand_cell.mbt`,
/// which forward to the `API` wrapper in `web/js/app.js:6`.
///
/// Behaviour parity with `web/js/profile.js`:
///   - On mount, fetch the profile (GET /api/profile) and render the form.
///   - Save calls PUT /api/profile with the form payload; on success
///     apply the language change via `I18n.setLocale` (external JS) and
///     notify via `App.showNotification`.
///   - Reset re-fetches the profile from the server.
///
/// Deviations from the legacy code (intentional):
///   - **i18n is hard-coded in English** rather than translated. The
///     legacy `profile.js` used `I18n.t('profile.*')` everywhere; spec
///     R5 in `specs/active/2026-07-14_web-ui-rabbita-migration.md` calls
///     rabbita's lack of `data-i18n` a Phase 2+ "system issue" that
///     "has not been investigated". The form is therefore only
///     English; the language dropdown still exists in the form so the
///     user can change their stored language preference, and a future
///     Phase 3+ can re-introduce i18n after the system issue is
///     resolved.
///   - The email-notification toggle is a real `<input type="checkbox">`
///     styled as a `.toggle` rather than a custom `classList.toggle`
///     onClick hack, since rabbita's input supports on_change.
///   - `I18n.setLocale` is invoked from MoonBit via a new FFI bridge
///     `i18n_set_locale(lang)` (see `bridge.mbt`).

///|
/// All `cmd` types are referenced via fully-qualified `@cmd.X` and all
/// top-level fns are prefixed with `profile_` to avoid clashes with the
/// brand cell, backups cell and version cell which share the same moon
/// package. All HTML constructors are fully qualified to avoid
/// "toplevel identifier declared twice" with the other cells' imports.

///|
enum ProfileMsg {
  /// Mount-time signal: trigger initial fetch of profile.
  Init
  /// Initial fetch finished.
  ProfileLoaded(Result[Json, String])
  /// User typed in the name input.
  NameChanged(String)
  /// User typed in the email input.
  EmailChanged(String)
  /// User picked a new theme.
  ThemeChanged(String)
  /// User picked a new language.
  LanguageChanged(String)
  /// User toggled the email-notification switch.
  EmailNotifChanged(Bool)
  /// User clicked "Save".
  ClickSave
  /// Save result.
  SaveDone(Result[Json, String])
  /// User clicked "Reset" — re-fetch from server.
  ClickReset
  /// Re-fetch result.
  ResetDone(Result[Json, String])
}

///|
priv struct ProfileModel {
  /// "" before the first fetch; the actual value after that.
  name : String
  /// "" before the first fetch; the actual value after that.
  email : String
  /// "dark" | "light" | "auto".
  theme : String
  /// "en" | "zh" | "ja".
  language : String
  /// Whether the email-notification toggle is active.
  email_notif : Bool
  /// True while a network call is in flight.
  busy : Bool
  /// Status line under the form (empty when idle, "Loaded" / "Reset" /
  /// "Saving..." / "Failed: ..." otherwise).
  status : String
  /// True after the first fetch has resolved at least once.
  loaded : Bool
}

///|
fn initial_profile_model() -> ProfileModel {
  {
    name: "",
    email: "",
    theme: "dark",
    language: "en",
    email_notif: false,
    busy: false,
    status: "",
    loaded: false,
  }
}

///|
fn profile_json_nested(json : Json, key : String) -> Json {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(v) => v
        _ => Json::null()
      }
    _ => Json::null()
  }
}

///|
fn profile_fetch_cmd(emit : @cmd.Emit[ProfileMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(ProfileLoaded(r)), async fn() noraise {
    safe_get("/api/profile")
  })
}

///|
fn profile_save_cmd(emit : @cmd.Emit[ProfileMsg], body : Json) -> @cmd.Cmd {
  @cmd.perform(r => emit(SaveDone(r)), async fn() noraise {
    safe_put("/api/profile", body)
  })
}

///|
fn profile_build_save_body(model : ProfileModel) -> Json {
  Json::object(
    Map::of([
      ("name", Json::string(model.name)),
      ("email", Json::string(model.email)),
      ("theme", Json::string(model.theme)),
      (
        "preferences",
        Json::object(
          Map::of([
            ("language", Json::string(model.language)),
            ("email_notifications", Json::boolean(model.email_notif)),
          ]),
        ),
      ),
    ]),
  )
}

///|
fn profile_normalize_theme(theme : String) -> String {
  if theme == "dark" || theme == "light" || theme == "auto" {
    theme
  } else {
    "dark"
  }
}

///|
fn profile_update(
  emit : @cmd.Emit[ProfileMsg],
  msg : ProfileMsg,
  model : ProfileModel,
) -> (@cmd.Cmd, ProfileModel) {
  match msg {
    Init => (profile_fetch_cmd(emit), { ..model, busy: true })
    ProfileLoaded(Ok(json)) => {
      let user = profile_json_nested(json, "user")
      let prefs = profile_json_nested(json, "preferences")
      let name = profile_json_string(json, "name", profile_json_string(user, "name", ""))
      let email = profile_json_string(json, "email", profile_json_string(user, "email", ""))
      let theme = profile_normalize_theme(
        profile_json_string(json, "theme", profile_json_string(prefs, "theme", "dark")),
      )
      let language = profile_json_string(prefs, "language", "en")
      let email_notif = profile_json_bool(prefs, "email_notifications", false)
      (
        @cmd.none,
        {
          ..model,
          name,
          email,
          theme,
          language,
          email_notif,
          busy: false,
          status: "Loaded",
          loaded: true,
        },
      )
    }
    ProfileLoaded(Err(e)) => {
      app_notify("Failed to load profile: \{e}", "error")
      (
        @cmd.none,
        { ..model, busy: false, status: "Load failed: " + e, loaded: true },
      )
    }
    NameChanged(v) => (@cmd.none, { ..model, name: v })
    EmailChanged(v) => (@cmd.none, { ..model, email: v })
    ThemeChanged(v) => (@cmd.none, { ..model, theme: profile_normalize_theme(v) })
    LanguageChanged(v) => (@cmd.none, { ..model, language: v })
    EmailNotifChanged(v) => (@cmd.none, { ..model, email_notif: v })
    ClickSave => {
      let body = profile_build_save_body(model)
      (
        profile_save_cmd(emit, body),
        { ..model, busy: true, status: "Saving..." },
      )
    }
    SaveDone(Ok(_)) => {
      i18n_set_locale(model.language)
      app_notify("Profile saved", "success")
      (@cmd.none, { ..model, busy: false, status: "Saved" })
    }
    SaveDone(Err(e)) => {
      app_notify("Failed to save profile: \{e}", "error")
      (@cmd.none, { ..model, busy: false, status: "Save failed: " + e })
    }
    ClickReset => (profile_fetch_cmd(emit), { ..model, busy: true })
    ResetDone(Ok(_)) =>
      // The fetch will dispatch ProfileLoaded next; acknowledge for now.
      (@cmd.none, { ..model, busy: false, status: "Reset" })
    ResetDone(Err(e)) => {
      app_notify("Failed to reset profile: \{e}", "error")
      (@cmd.none, { ..model, busy: false, status: "Reset failed: " + e })
    }
  }
}

///|
fn profile_view(
  emit : @cmd.Emit[ProfileMsg],
  model : ProfileModel,
) -> @html.Html {
  if not(model.loaded) {
    return @html.div(
      class="profile-panel",
      [
        @html.p(
          class="text-muted profile-loading",
          [@html.span("Loading profile...")],
        ),
      ],
    )
  }
  let save_button = if model.busy {
    @html.button(class="btn btn-primary", disabled=true, "Saving...")
  } else {
    @html.button(class="btn btn-primary", on_click=emit(ClickSave), "Save")
  }
  let reset_button = if model.busy {
    @html.button(class="btn btn-ghost", disabled=true, "Resetting...")
  } else {
    @html.button(class="btn btn-ghost", on_click=emit(ClickReset), "Reset")
  }
  let status_line = if model.status.length() > 0 {
    @html.p(class="text-muted profile-status", [@html.span(model.status)])
  } else {
    @html.p(class="profile-status-empty", [@html.span("")])
  }
  let theme_options = [
    @html.option(value="dark", selected=model.theme == "dark", [@html.span("Dark")]),
    @html.option(value="light", selected=model.theme == "light", [@html.span("Light")]),
    @html.option(value="auto", selected=model.theme == "auto", [@html.span("System default")]),
  ]
  let language_options = [
    @html.option(value="en", selected=model.language == "en", [@html.span("English")]),
    @html.option(value="zh", selected=model.language == "zh", [@html.span("中文")]),
    @html.option(value="ja", selected=model.language == "ja", [@html.span("日本語")]),
  ]
  @html.div(class="profile-panel", [
    @html.div(class="settings-group", [
      @html.div(class="settings-group-title", [@html.span("Personal Info")]),
      @html.div(class="settings-field", [
        @html.label(for_="profile-name", [@html.span("Display name")]),
        @html.input(
          input_type=Text,
          id="profile-name",
          value=model.name,
          placeholder="Your name",
          on_input=s => emit(NameChanged(s)),
        ),
        @html.div(class="help-text", [
          @html.span("Shown to your collaborators."),
        ]),
      ]),
      @html.div(class="settings-field", [
        @html.label(for_="profile-email", [@html.span("Email")]),
        @html.input(
          input_type=Text,
          id="profile-email",
          value=model.email,
          placeholder="you@example.com",
          on_input=s => emit(EmailChanged(s)),
        ),
        @html.div(class="help-text", [
          @html.span("Used for notifications and account recovery."),
        ]),
      ]),
    ]),
    @html.div(class="settings-group", [
      @html.div(class="settings-group-title", [@html.span("Preferences")]),
      @html.div(class="settings-field", [
        @html.label(for_="profile-theme", [@html.span("Theme")]),
        @html.select(
          id="profile-theme",
          on_change=s => emit(ThemeChanged(s)),
          theme_options,
        ),
        @html.div(class="help-text", [
          @html.span("Choose how the interface looks."),
        ]),
      ]),
      @html.div(class="settings-field", [
        @html.label(for_="profile-language", [@html.span("Language")]),
        @html.select(
          id="profile-language",
          on_change=s => emit(LanguageChanged(s)),
          language_options,
        ),
        @html.div(class="help-text", [
          @html.span("Currently English-only UI; preference is stored for future i18n."),
        ]),
      ]),
      @html.div(class="settings-field", [
        @html.div(class="toggle-wrapper", [
          @html.label([@html.span("Email notifications")]),
          @html.input(
            input_type=Checkbox,
            id="profile-email-notif",
            checked=model.email_notif,
            class=if model.email_notif {
              "toggle active"
            } else {
              "toggle"
            },
            on_change=_s => emit(EmailNotifChanged(not(model.email_notif))),
          ),
        ]),
        @html.div(class="help-text", [
          @html.span("Receive an email when your tasks complete."),
        ]),
      ]),
    ]),
    @html.div(class="profile-actions", [save_button, reset_button]),
    status_line,
  ])
}

///|
/// Read a string field from a Json object, falling back to `default`.
fn profile_json_string(json : Json, key : String, default : String) -> String {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(String(s)) => s
        _ => default
      }
    _ => default
  }
}

///|
/// Read a bool field from a Json object, falling back to `default`.
fn profile_json_bool(json : Json, key : String, default : Bool) -> Bool {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(True) => true
        Some(False) => false
        _ => default
      }
    _ => default
  }
}

///|
/// Factory used by `main.mbt`. Returns the `(emit, cell)` pair from
/// `cell_with_emit`; `main.mbt` then wires `emit(Init)` as the mount-time
/// command via `app.with_init`.
fn build_profile_cell() -> (@cmd.Emit[ProfileMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_profile_model(),
    update=profile_update,
    view=profile_view,
  )
}
