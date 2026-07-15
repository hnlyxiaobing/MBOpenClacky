///| Brand panel — rabbita replacement for `web/js/brand.js`.
///
/// Renders the license-status / product-name / skills block into the
/// `#brand-content` container mounted by `main.mbt`. State is fetched
/// from the existing MBOpenClacky backend at `/api/brand/*` via the
/// `api_get / api_post / api_del` bridges in `bridge.mbt`, which forward
/// to the `API` wrapper in `web/js/app.js:6`.
///
/// Behaviour parity with `web/js/brand.js`:
///   - On mount, fetch status and skills in parallel.
///   - Activate / deactivate license; install / delete skills.
///   - Notify via `App.showNotification` and confirm via `window.confirm`.
///
/// Deviations from the legacy code (intentional):
///   - The install-skill dialog is rendered **inline** instead of via
///     `App.showModal`, because routing the modal's confirm button back
///     into the rabbita update loop is more code than the visual gain.
///   - Status fetch and skills fetch are still issued in parallel
///     (`@cmd.batch` of two `@cmd.perform` calls).

///|
using @html {span, p, label, h3, h4, input, br}

///|
priv enum BrandMsg {
  /// Mount-time signal: trigger initial fetch of status + skills.
  Init
  /// Status fetch finished.
  StatusLoaded(Result[Json, String])
  /// Skills fetch finished.
  SkillsLoaded(Result[Json, String])
  /// User typed in the license-key input.
  LicenseKeyChanged(String)
  /// User clicked "Activate" with the typed key.
  ClickActivate
  /// Activation result.
  ActivateDone(Result[Json, String])
  /// User clicked "Deactivate".
  ClickDeactivate
  /// Deactivation result.
  DeactivateDone(Result[Json, String])
  /// User clicked "+ Install Skill" — show inline form.
  ClickOpenInstall
  /// User typed in the skill-name input.
  SkillNameChanged(String)
  /// User clicked "Cancel" in the install form.
  ClickCancelInstall
  /// User clicked "Install" in the install form.
  ClickConfirmInstall
  /// Install result.
  InstallDone(Result[Json, String])
  /// User clicked delete on a specific skill.
  ClickDeleteSkill(String)
  /// Delete result.
  DeleteDone(Result[Json, String])
  LocaleChanged
}

///|
priv struct BrandModel {
  status : String // "active" | "inactive" | "trial" | "loading"
  product_name : String // server-supplied product name
  skills : Array[Json] // raw JSON objects from /api/brand/skills
  license_key_input : String // textbox value
  skill_name_input : String // inline-install textbox value
  install_form_open : Bool // whether the inline install form is shown
  busy : Bool // disables actions while a request is in flight
  error : String // last user-facing error message
  pending_license_key : String // license key being activated
  pending_install_name : String // skill name being installed
  locale : String
}

///|
fn initial_brand_model() -> BrandModel {
  {
    status: "loading",
    product_name: "MBOpenClacky",
    skills: [],
    license_key_input: "",
    skill_name_input: "",
    install_form_open: false,
    busy: false,
    error: "",
    pending_license_key: "",
    pending_install_name: "",
    locale: "",
  }
}

///|
/// Wrap an HTTP call so the caller receives `Result[Json, String]` instead
/// of having to declare a `raise` clause (the rabbita update loop is
/// non-raising). The error is stringified so it can be shown directly.
async fn safe_get(path : String) -> Result[Json, String] noraise {
  Ok(api_get(path)) catch {
    e => Err(e.to_string())
  }
}

///|
async fn safe_post(path : String, body : Json) -> Result[Json, String] noraise {
  Ok(api_post(path, body)) catch {
    e => Err(e.to_string())
  }
}

///|
async fn safe_del(path : String) -> Result[Json, String] noraise {
  Ok(api_del(path)) catch {
    e => Err(e.to_string())
  }
}

///|
async fn safe_put(path : String, body : Json) -> Result[Json, String] noraise {
  Ok(api_put(path, body)) catch {
    e => Err(e.to_string())
  }
}

///|
/// Run two fetches in parallel and dispatch a message for each result.
fn fetch_status_and_skills(emit : @cmd.Emit[BrandMsg]) -> @cmd.Cmd {
  let status_cmd = @cmd.perform(r => emit(StatusLoaded(r)), async fn() noraise {
    safe_get("/api/brand/status")
  })
  let skills_cmd = @cmd.perform(r => emit(SkillsLoaded(r)), async fn() noraise {
    safe_get("/api/brand/skills")
  })
  @cmd.batch([status_cmd, skills_cmd])
}

///|
fn update(
  emit : @cmd.Emit[BrandMsg],
  msg : BrandMsg,
  model : BrandModel,
) -> (@cmd.Cmd, BrandModel) {
  match msg {
    Init =>
      (
        @cmd.batch([
          fetch_status_and_skills(emit),
          locale_change_cmd(emit, LocaleChanged),
        ]),
        { ..model, locale: i18n_get_locale() },
      )
    StatusLoaded(Ok(json)) => {
      let status = json_string(json, "license_status", "inactive")
      let pname = json_string(json, "product_name", model.product_name)
      (none, { ..model, status, product_name: pname, error: "" })
    }
    StatusLoaded(Err(e)) => {
      app_notify(t1("brand.failed_load", "error", e), "error")
      (none, { ..model, status: "inactive", error: e })
    }
    SkillsLoaded(Ok(json)) => {
      let skills = match json {
        Object(map) =>
          match map.get("skills") {
            Some(Array(arr)) => arr
            _ => []
          }
        Array(arr) => arr
        _ => []
      }
      (none, { ..model, skills, error: "" })
    }
    SkillsLoaded(Err(e)) => {
      app_notify(t1("brand.failed_skills", "error", e), "error")
      (none, { ..model, skills: [], error: e })
    }
    LicenseKeyChanged(s) => (none, { ..model, license_key_input: s })
    ClickActivate => {
      let key = model.license_key_input.trim().to_string()
      if key == "" {
        app_notify(t("brand.license_key_required"), "warning")
        (none, model)
      } else {
        let body = Json::object(Map::of([("license_key", Json::string(key))]))
        let cmd = @cmd.perform(r => emit(ActivateDone(r)), async fn() noraise {
          safe_post("/api/brand", body)
        })
        (cmd, { ..model, busy: true, pending_license_key: key, error: "" })
      }
    }
    ActivateDone(Ok(json)) => {
      let status = json_string(json, "status", "active")
      let pname = json_string(json, "product_name", model.product_name)
      app_notify(t("brand.activated_success"), "success")
      (
        none,
        {
          ..model,
          status,
          product_name: pname,
          busy: false,
          license_key_input: "",
          pending_license_key: "",
        },
      )
    }
    ActivateDone(Err(e)) => {
      app_notify(t1("brand.activation_failed", "error", e), "error")
      (none, { ..model, busy: false, error: e, pending_license_key: "" })
    }
    ClickDeactivate => {
      let ok = window_confirm(t("brand.deactivate_confirm"))
      if not(ok) {
        (none, model)
      } else {
        let cmd = @cmd.perform(r => emit(DeactivateDone(r)), async fn() noraise {
          safe_del("/api/brand/license")
        })
        (cmd, { ..model, busy: true, error: "" })
      }
    }
    DeactivateDone(_) => {
      app_notify(t("brand.deactivated_success"), "info")
      (
        fetch_status_and_skills(emit),
        { ..model, busy: false, status: "inactive" },
      )
    }
    ClickOpenInstall =>
      (none, { ..model, install_form_open: true, skill_name_input: "" })
    SkillNameChanged(s) => (none, { ..model, skill_name_input: s })
    ClickCancelInstall =>
      (none, { ..model, install_form_open: false, skill_name_input: "" })
    ClickConfirmInstall => {
      let name = model.skill_name_input.trim().to_string()
      if name == "" {
        app_notify(t("brand.skill_name_required"), "warning")
        (none, model)
      } else {
        let body = Json::object(Map::of([("name", Json::string(name))]))
        let cmd = @cmd.perform(r => emit(InstallDone(r)), async fn() noraise {
          safe_post("/api/brand/skills", body)
        })
        (
          cmd,
          {
            ..model,
            busy: true,
            install_form_open: false,
            pending_install_name: name,
            error: "",
          },
        )
      }
    }
    InstallDone(Ok(_)) => {
      app_notify(t("brand.skill_installed"), "success")
      (
        @cmd.perform(r => emit(SkillsLoaded(r)), async fn() noraise {
          safe_get("/api/brand/skills")
        }),
        { ..model, busy: false, pending_install_name: "", skill_name_input: "" },
      )
    }
    InstallDone(Err(e)) => {
      app_notify(t1("brand.skill_install_failed", "error", e), "error")
      (none, { ..model, busy: false, error: e, pending_install_name: "" })
    }
    ClickDeleteSkill(name) => {
      let ok = window_confirm(t1("brand.uninstall_confirm", "name", name))
      if not(ok) {
        (none, model)
      } else {
        let path = "/api/brand/skills/" + js_encode_uri_component(name)
        let cmd = @cmd.perform(r => emit(DeleteDone(r)), async fn() noraise {
          safe_del(path)
        })
        (cmd, { ..model, busy: true, error: "" })
      }
    }
    DeleteDone(_) => {
      app_notify(t("brand.skill_uninstalled"), "success")
      (
        @cmd.perform(r => emit(SkillsLoaded(r)), async fn() noraise {
          safe_get("/api/brand/skills")
        }),
        { ..model, busy: false },
      )
    }
    LocaleChanged => (none, { ..model, locale: i18n_get_locale() })
  }
}

///|
/// View — small inline helper for the status badge.
fn status_badge(status : String) -> @html.Html {
  let (cls, label) = match status {
    "active" => ("brand-status-badge active", t("brand.status_active"))
    "trial" => ("brand-status-badge trial", t("brand.status_trial"))
    _ => ("brand-status-badge inactive", t("brand.status_inactive"))
  }
  span(class=cls, label)
}

///|
/// View — render a single skill row.
fn skill_row(emit : @cmd.Emit[BrandMsg], skill : Json) -> @html.Html {
  let name = match skill {
    Object(map) =>
      match map.get("name") {
        Some(String(s)) => s
        _ => "Unknown"
      }
    String(s) => s
    _ => "Unknown"
  }
  let desc = match skill {
    Object(map) =>
      match map.get("description") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
  div(class="skill-card", [
    div(
      style=[
        "display:flex", "align-items:center", "justify-content:space-between",
      ],
      [
        div([
          div(class="skill-card-name", name),
          if desc == "" {
            @html.nothing
          } else {
            div(class="skill-card-desc", desc)
          },
        ]),
        button(
          class="btn btn-danger btn-sm",
          on_click=emit(ClickDeleteSkill(name)),
          t("common.delete"),
        ),
      ],
    ),
  ])
}

///|
fn view(emit : @cmd.Emit[BrandMsg], model : BrandModel) -> @html.Html {
  let status = model.status
  let show_activate = status != "active"
  let skills_html = if model.skills.length() == 0 {
    [p(class="text-muted", t("brand.no_skills"))]
  } else {
    model.skills.map(s => skill_row(emit, s))
  }
  div([
    // License section.
    div(class="settings-group", [
      div(
        class="settings-group-title",
        style=[
          "display:flex", "align-items:center", "justify-content:space-between",
        ],
        [span(t("brand.status")), status_badge(status)],
      ),
      div(class="brand-info-card", [
        div(class="settings-field", [
          label(t("brand.product_name")),
          div(class="text-muted", model.product_name),
        ]),
        if show_activate {
          div([
            div(class="settings-field", [
              label(t("brand.license_key")),
              input(
                input_type=@html.Text,
                id="brand-license-key",
                placeholder=t("brand.enter_key"),
                value=model.license_key_input,
                on_change=s => emit(LicenseKeyChanged(s)),
              ),
              div(class="help-text", t("brand.license_key_help")),
            ]),
            div(style=["display:flex", "gap:8px", "margin-top:8px"], [
              button(
                class="btn btn-primary",
                on_click=emit(ClickActivate),
                if model.busy && model.pending_license_key != "" {
                  t("brand.activating")
                } else {
                  t("brand.activate")
                },
              ),
            ]),
          ])
        } else {
          div(style=["margin-top:12px"], [
            button(
              class="btn btn-danger btn-sm",
              on_click=emit(ClickDeactivate),
              t("brand.deactivate"),
            ),
          ])
        },
      ]),
    ]),
    // Skills section.
    div(class="settings-group", [
      div(
        class="settings-group-title",
        style=[
          "display:flex", "align-items:center", "justify-content:space-between",
        ],
        [
          span(
            t1("brand.skills_count", "count", model.skills.length().to_string()),
          ),
          button(
            class="btn btn-primary btn-sm",
            on_click=emit(ClickOpenInstall),
            t("brand.install_skill"),
          ),
        ],
      ),
      div(id="brand-skills-list", skills_html),
      if model.install_form_open {
        div(class="settings-field", [
          label(t("brand.skill_name")),
          input(
            input_type=@html.Text,
            id="brand-skill-name",
            placeholder=t("brand.skill_name_placeholder"),
            value=model.skill_name_input,
            on_change=s => emit(SkillNameChanged(s)),
          ),
          div(class="help-text", t("brand.skill_name_help")),
          div(style=["display:flex", "gap:8px", "margin-top:8px"], [
            button(
              class="btn btn-ghost",
              on_click=emit(ClickCancelInstall),
              t("common.cancel"),
            ),
            button(
              class="btn btn-primary",
              on_click=emit(ClickConfirmInstall),
              if model.busy && model.pending_install_name != "" {
                t("brand.installing")
              } else {
                t("brand.install")
              },
            ),
          ]),
        ])
      } else {
        @html.nothing
      },
    ]),
  ])
}

///|
/// Read a string field from a Json object, falling back to `default`.
fn json_string(json : Json, key : String, default : String) -> String {
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
/// Factory used by `main.mbt`. Returns the `(emit, cell)` pair from
/// `cell_with_emit`; `main.mbt` then wires `emit(Init)` as the mount-time
/// command via `App::with_init`.
fn build_brand_cell() -> (@cmd.Emit[BrandMsg], @rabbita.Cell) {
  cell_with_emit(model=initial_brand_model(), update~, view~)
}
