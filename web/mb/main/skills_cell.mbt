///| Skills panel - rabbita replacement for `web/js/skills_enhanced.js`.
///
/// Three-tab skill manager (Installed / Store / My Skills) with an inline
/// skill content editor.
/// API endpoints:
///   - `GET /api/skills`                   - list installed skills
///   - `GET /api/store/skills`             - list store skills
///   - `GET /api/creator/skills`           - list creator skills
///   - `GET /api/skills/:name/content`     - fetch skill content
///   - `PUT /api/skills/:name/content`     - save skill content
///   - `POST /api/skills/:name/toggle`     - toggle enable/disable
///   - `DELETE /api/skills/:name`          - delete skill
///   - `POST /api/skills/install`          - install from store

///|
priv enum SkillsMsg {
  Init
  InstalledLoaded(Result[Json, String])
  StoreLoaded(Result[Json, String])
  CreatorLoaded(Result[Json, String])
  SwitchTab(String)
  // Editor
  OpenEditor(String)
  EditorContentLoaded(String, Result[Json, String])
  EditorContentChanged(String)
  ClickSave
  SaveDone(Result[Json, String])
  CloseEditor
  // Actions
  ClickToggle(String, Bool)
  ToggleDone(String, Bool, Result[Json, String])
  ClickDelete(String)
  DeleteDone(String, Result[Json, String])
  ClickInstall(String)
  InstallDone(String, Result[Json, String])
  // Locale
  LocaleChanged
}

///|
priv struct SkillsModel {
  skills_list : Array[Json]
  store_skills : Array[Json]
  creator_skills : Array[Json]
  active_tab : String
  loading : Bool
  busy : Bool
  editor_visible : Bool
  editor_skill_name : String
  editor_content : String
  modified : Bool
  locale : String
}

///|
fn initial_skills_model() -> SkillsModel {
  {
    skills_list: [],
    store_skills: [],
    creator_skills: [],
    active_tab: "installed",
    loading: true,
    busy: false,
    editor_visible: false,
    editor_skill_name: "",
    editor_content: "",
    modified: false,
    locale: "",
  }
}

// ── API fetch helpers ─────────────────────────────────────────────

///|
fn fetch_installed_skills(emit : @cmd.Emit[SkillsMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(InstalledLoaded(r)), async fn() noraise {
    safe_get("/api/skills")
  })
}

///|
fn fetch_store_skills(emit : @cmd.Emit[SkillsMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(StoreLoaded(r)), async fn() noraise {
    safe_get("/api/store/skills")
  })
}

///|
fn fetch_creator_skills(emit : @cmd.Emit[SkillsMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(CreatorLoaded(r)), async fn() noraise {
    safe_get("/api/creator/skills")
  })
}

///|
fn fetch_skill_content(
  emit : @cmd.Emit[SkillsMsg],
  name : String,
) -> @cmd.Cmd {
  let path = "/api/skills/\{js_encode_uri_component(name)}/content"
  @cmd.perform(
    r => emit(EditorContentLoaded(name, r)),
    async fn() noraise {
      safe_get(path)
    },
  )
}

///|
fn save_skill_content(
  emit : @cmd.Emit[SkillsMsg],
  name : String,
  content : String,
) -> @cmd.Cmd {
  let path = "/api/skills/\{js_encode_uri_component(name)}/content"
  let body = Json::object(Map::of([("content", Json::string(content))]))
  @cmd.perform(r => emit(SaveDone(r)), async fn() noraise {
    safe_put(path, body)
  })
}

///|
fn toggle_skill(
  emit : @cmd.Emit[SkillsMsg],
  name : String,
  enabled : Bool,
) -> @cmd.Cmd {
  let path = "/api/skills/\{js_encode_uri_component(name)}/toggle"
  let body = Json::object(Map::of([("enabled", Json::boolean(enabled))]))
  @cmd.perform(
    r => emit(ToggleDone(name, enabled, r)),
    async fn() noraise {
      safe_post(path, body)
    },
  )
}

///|
fn delete_skill(emit : @cmd.Emit[SkillsMsg], name : String) -> @cmd.Cmd {
  let path = "/api/skills/\{js_encode_uri_component(name)}"
  @cmd.perform(r => emit(DeleteDone(name, r)), async fn() noraise {
    safe_del(path)
  })
}

///|
fn install_skill(emit : @cmd.Emit[SkillsMsg], name : String) -> @cmd.Cmd {
  let body = Json::object(Map::of([("name", Json::string(name))]))
  @cmd.perform(
    r => emit(InstallDone(name, r)),
    async fn() noraise {
      safe_post("/api/skills/install", body)
    },
  )
}

///|
fn refresh_skills(emit : @cmd.Emit[SkillsMsg]) -> @cmd.Cmd {
  @cmd.batch([
    fetch_installed_skills(emit),
    fetch_store_skills(emit),
    fetch_creator_skills(emit),
  ])
}

// ── Update ────────────────────────────────────────────────────────

///|
fn skills_update(
  emit : @cmd.Emit[SkillsMsg],
  msg : SkillsMsg,
  model : SkillsModel,
) -> (@cmd.Cmd, SkillsModel) {
  match msg {
    Init =>
      (
        @cmd.batch([
          fetch_installed_skills(emit),
          fetch_store_skills(emit),
          fetch_creator_skills(emit),
          locale_change_cmd(emit, LocaleChanged),
          skill_open_cmd(emit, name => OpenEditor(name)),
        ]),
        { ..model, loading: true, locale: i18n_get_locale() },
      )
    InstalledLoaded(Ok(json)) => {
      let items = skills_array(json)
      (@cmd.none, { ..model, skills_list: items, loading: false })
    }
    InstalledLoaded(Err(_)) =>
      (@cmd.none, { ..model, skills_list: [], loading: false })
    StoreLoaded(Ok(json)) => {
      let items = skills_array(json)
      (@cmd.none, { ..model, store_skills: items })
    }
    StoreLoaded(Err(_)) => (@cmd.none, { ..model, store_skills: [] })
    CreatorLoaded(Ok(json)) => {
      let items = skills_array(json)
      (@cmd.none, { ..model, creator_skills: items })
    }
    CreatorLoaded(Err(_)) => (@cmd.none, { ..model, creator_skills: [] })
    SwitchTab(tab) => (@cmd.none, { ..model, active_tab: tab })
    OpenEditor(name) =>
      (fetch_skill_content(emit, name), { ..model, busy: true })
    EditorContentLoaded(name, Ok(json)) => {
      let content = match json {
        Object(map) =>
          match map.get("content") {
            Some(String(s)) => s
            _ =>
              match map.get("text") {
                Some(String(s)) => s
                _ => ""
              }
          }
        _ => ""
      }
      (
        @cmd.none,
        {
          ..model,
          editor_visible: true,
          editor_skill_name: name,
          editor_content: content,
          modified: false,
          busy: false,
        },
      )
    }
    EditorContentLoaded(_, Err(_)) => {
      app_notify("Failed to load skill content", "error")
      (@cmd.none, { ..model, busy: false })
    }
    EditorContentChanged(v) =>
      (@cmd.none, { ..model, editor_content: v, modified: true })
    ClickSave =>
      (
        save_skill_content(emit, model.editor_skill_name, model.editor_content),
        { ..model, busy: true },
      )
    SaveDone(Ok(_)) => {
      app_notify("Skill saved", "success")
      (@cmd.none, { ..model, busy: false, modified: false })
    }
    SaveDone(Err(_)) => {
      app_notify("Save failed", "error")
      (@cmd.none, { ..model, busy: false })
    }
    CloseEditor =>
      (
        @cmd.none,
        {
          ..model,
          editor_visible: false,
          editor_skill_name: "",
          editor_content: "",
          modified: false,
        },
      )
    ClickToggle(name, current_enabled) => {
      let new_enabled = not(current_enabled)
      (toggle_skill(emit, name, new_enabled), { ..model, busy: true })
    }
    ToggleDone(name, new_enabled, Ok(_)) => {
      app_notify(
        "Skill \{name} \{if new_enabled { "enabled" } else { "disabled" }}",
        "info",
      )
      // Update the enabled flag in the local list
      let updated = model.skills_list.map(s => {
        let n = skill_name(s)
        if n == name {
          set_skill_enabled(s, new_enabled)
        } else {
          s
        }
      })
      (@cmd.none, { ..model, skills_list: updated, busy: false })
    }
    ToggleDone(_, _, Err(_)) => {
      app_notify("Toggle failed", "error")
      (@cmd.none, { ..model, busy: false })
    }
    ClickDelete(name) => (delete_skill(emit, name), { ..model, busy: true })
    DeleteDone(name, Ok(_)) => {
      app_notify("Skill \{name} deleted", "success")
      let updated = model.skills_list.filter(s => skill_name(s) != name)
      // Close editor if editing the deleted skill
      let close_editor = model.editor_skill_name == name
      (
        refresh_skills(emit),
        {
          ..model,
          skills_list: updated,
          busy: false,
          editor_visible: if close_editor { false } else { model.editor_visible },
          editor_skill_name: if close_editor {
            ""
          } else {
            model.editor_skill_name
          },
        },
      )
    }
    DeleteDone(_, Err(_)) => {
      app_notify("Delete failed", "error")
      (@cmd.none, { ..model, busy: false })
    }
    ClickInstall(name) =>
      (install_skill(emit, name), { ..model, busy: true })
    InstallDone(name, Ok(_)) => {
      app_notify("Skill \{name} installed", "success")
      (refresh_skills(emit), { ..model, busy: false })
    }
    InstallDone(_, Err(_)) => {
      app_notify("Install failed", "error")
      (@cmd.none, { ..model, busy: false })
    }
    LocaleChanged => (@cmd.none, { ..model, locale: i18n_get_locale() })
  }
}

// ── Views ────────────────────────────────────────────────────────

///|
fn skills_view(
  emit : @cmd.Emit[SkillsMsg],
  model : SkillsModel,
) -> @html.Html {
  if model.loading {
    @html.div(class="text-center", [
      @html.div(class="spinner", style=["margin:40px auto"], []),
    ])
  } else {
    let children : Array[@html.Html] = []
    // Tab bar
    children.push(skills_tab_bar(emit, model))
    // Tab content
    children.push(skills_tab_content(emit, model))
    // Editor area (conditional)
    if model.editor_visible {
      children.push(skills_editor_area(emit, model))
    }
    @html.div([], children)
  }
}

///|
fn skills_tab_bar(
  emit : @cmd.Emit[SkillsMsg],
  model : SkillsModel,
) -> @html.Html {
  let tabs = ["installed", "store", "creator"]
  let labels = ["Installed", "Store", "My Skills"]
  let buttons : Array[@html.Html] = []
  for i, tab in tabs {
    let label = labels[i]
    let cls = if tab == model.active_tab {
      "skills-tab active"
    } else {
      "skills-tab"
    }
    buttons.push(
      @html.button(
        class=cls,
        on_click=emit(SwitchTab(tab)),
        label,
      ),
    )
  }
  @html.div(class="skills-tabs", buttons)
}

///|
fn skills_tab_content(
  emit : @cmd.Emit[SkillsMsg],
  model : SkillsModel,
) -> @html.Html {
  match model.active_tab {
    "installed" => skills_installed_tab(emit, model)
    "store" => skills_store_tab(emit, model)
    "creator" => skills_creator_tab(emit, model)
    _ => @html.div([], [])
  }
}

///|
fn skills_installed_tab(
  emit : @cmd.Emit[SkillsMsg],
  model : SkillsModel,
) -> @html.Html {
  if model.skills_list.is_empty() {
    @html.p(
      class="text-muted",
      style=["padding:16px 0"],
      "No skills installed. Browse the store to find skills.",
    )
  } else {
    let cards : Array[@html.Html] = []
    for s in model.skills_list {
      cards.push(skill_card_installed(emit, s, model.busy))
    }
    @html.div(class="skills-grid", cards)
  }
}

///|
fn skills_store_tab(
  emit : @cmd.Emit[SkillsMsg],
  model : SkillsModel,
) -> @html.Html {
  if model.store_skills.is_empty() {
    @html.p(
      class="text-muted",
      style=["padding:16px 0"],
      "No skills available in the store.",
    )
  } else {
    let cards : Array[@html.Html] = []
    for s in model.store_skills {
      cards.push(skill_card_store(emit, s, model.busy))
    }
    @html.div(class="skills-grid", cards)
  }
}

///|
fn skills_creator_tab(
  emit : @cmd.Emit[SkillsMsg],
  model : SkillsModel,
) -> @html.Html {
  if model.creator_skills.is_empty() {
    @html.p(
      class="text-muted",
      style=["padding:16px 0"],
      "You haven't created any skills yet.",
    )
  } else {
    let cards : Array[@html.Html] = []
    for s in model.creator_skills {
      cards.push(skill_card_creator(emit, s, model.busy))
    }
    @html.div(class="skills-grid", cards)
  }
}

///|
fn skill_card_installed(
  emit : @cmd.Emit[SkillsMsg],
  s : Json,
  busy : Bool,
) -> @html.Html {
  let name = skill_name(s)
  let desc = json_str(s, "description", "No description")
  let enabled = json_bool(s, "enabled", true)
  let truncated = if desc.length() > 120 { desc.substring(end=120) } else { desc }
  // Toggle switch
  let toggle_style = [
    "width:36px",
    "height:20px",
    "border-radius:10px",
    if enabled { "background:var(--accent)" } else { "background:var(--bg-tertiary)" },
    "border:1px solid var(--border)",
    "position:relative",
    "cursor:pointer",
    "transition:background 0.2s",
    if busy { "opacity:0.5" } else { "" },
  ]
  let dot_style = [
    "width:14px",
    "height:14px",
    "border-radius:50%",
    "background:white",
    "position:absolute",
    "top:2px",
    if enabled { "right:2px" } else { "left:2px" },
    "transition:left 0.2s, right 0.2s",
  ]
  @html.div(class="skill-card", [
    @html.div(
      style=["display:flex", "align-items:center", "justify-content:space-between", "margin-bottom:8px"],
      [
        @html.div(class="skill-card-name", name),
        @html.div(
          on_click=emit(ClickToggle(name, enabled)),
          style=toggle_style,
          [@html.div(style=dot_style, [])],
        ),
      ],
    ),
    @html.div(class="skill-card-desc", truncated),
    @html.div(
      style=["display:flex", "gap:6px", "margin-top:10px"],
      [
        @html.button(
          class="btn btn-ghost btn-sm",
          on_click=emit(OpenEditor(name)),
          "Edit",
        ),
        @html.button(
          class="btn btn-danger btn-sm",
          on_click=emit(ClickDelete(name)),
          "Delete",
        ),
      ],
    ),
  ])
}

///|
fn skill_card_store(
  emit : @cmd.Emit[SkillsMsg],
  s : Json,
  busy : Bool,
) -> @html.Html {
  let name = json_str(s, "name", "Unknown")
  let desc = json_str(s, "description", "")
  let author = json_str(s, "author", "")
  let truncated = if desc.length() > 120 {
    desc.substring(end=120)
  } else {
    desc
  }
  let children : Array[@html.Html] = []
  children.push(@html.div(class="skill-card-name", name))
  if not(author.is_empty()) {
    children.push(
      @html.div(
        class="skill-card-desc",
        style=["color:var(--accent)"],
        "by \{author}",
      ),
    )
  }
  children.push(@html.div(class="skill-card-desc", truncated))
  children.push(
    @html.button(
      class="btn btn-primary btn-sm",
      style=["margin-top:10px"],
      on_click=emit(ClickInstall(name)),
      disabled=busy,
      "Install",
    ),
  )
  @html.div(class="skill-card", children)
}

///|
fn skill_card_creator(
  emit : @cmd.Emit[SkillsMsg],
  s : Json,
  busy : Bool,
) -> @html.Html {
  let name = json_str(s, "name", "Unknown")
  let desc = json_str(s, "description", "")
  let published = json_bool(s, "published", false)
  let truncated = if desc.length() > 120 {
    desc.substring(end=120)
  } else {
    desc
  }
  let badge = if published {
    @html.span(class="brand-status-badge active", "Published")
  } else {
    @html.span(class="brand-status-badge inactive", "Draft")
  }
  @html.div(class="skill-card", [
    @html.div(
      style=["display:flex", "align-items:center", "gap:8px", "margin-bottom:6px"],
      [
        @html.div(class="skill-card-name", name),
        badge,
      ],
    ),
    @html.div(class="skill-card-desc", truncated),
    @html.div(
      style=["display:flex", "gap:6px", "margin-top:10px"],
      [
        @html.button(
          class="btn btn-ghost btn-sm",
          on_click=emit(OpenEditor(name)),
          disabled=busy,
          "Edit",
        ),
      ],
    ),
  ])
}

///|
fn skills_editor_area(
  emit : @cmd.Emit[SkillsMsg],
  model : SkillsModel,
) -> @html.Html {
  let save_style = if model.busy {
    ["opacity:0.5", "pointer-events:none"]
  } else {
    []
  }
  @html.div(class="skill-editor-area", [
    @html.div(class="skill-editor-header", [
      @html.span(class="skill-editor-title", model.editor_skill_name),
      @html.div(class="skill-editor-actions", [
        @html.button(
          class="btn btn-primary btn-sm",
          on_click=emit(ClickSave),
          style=save_style,
          "Save",
        ),
        @html.button(
          class="btn btn-ghost btn-sm",
          on_click=emit(CloseEditor),
          "Close",
        ),
      ]),
    ]),
    @html.textarea(
      rows=16,
      value=model.editor_content,
      on_change=s => emit(EditorContentChanged(s)),
      style=["width:100%", "min-height:400px", "font-family:var(--font-mono)", "font-size:12px", "background:var(--bg-tertiary)", "border:1px solid var(--border)", "border-radius:var(--radius-sm)", "color:var(--text-primary)", "padding:9px 12px", "resize:vertical", "outline:none"],
    ),
  ])
}

// ── Helpers ───────────────────────────────────────────────────────

///| Extract the skills array from a JSON response.
///| Handles both `{ skills: [...] }` and `[...]` shapes.
fn skills_array(json : Json) -> Array[Json] {
  match json {
    Object(map) =>
      match map.get("skills") {
        Some(Array(arr)) => arr
        _ =>
          match map.get("data") {
            Some(Array(arr)) => arr
            _ => []
          }
      }
    Array(arr) => arr
    _ => []
  }
}

///| Get the name of a skill (from `name` field, or the string itself).
fn skill_name(s : Json) -> String {
  match s {
    Object(map) =>
      match map.get("name") {
        Some(String(n)) => n
        _ => "Unknown"
      }
    String(n) => n
    _ => "Unknown"
  }
}

///| Return a copy of the skill JSON with the `enabled` field updated.
fn set_skill_enabled(s : Json, enabled : Bool) -> Json {
  match s {
    Object(map) => {
      let new_map = Map::new()
      map.each((k, v) => {
        if k == "enabled" {
          new_map.set(k, Json::boolean(enabled))
        } else {
          new_map.set(k, v)
        }
      })
      // Ensure `enabled` exists even if it wasn't in the original
      if not(new_map.contains("enabled")) {
        new_map.set("enabled", Json::boolean(enabled))
      }
      Object(new_map)
    }
    _ => s
  }
}

///|
fn build_skills_cell() -> (@cmd.Emit[SkillsMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_skills_model(),
    update=skills_update,
    view=skills_view,
  )
}
