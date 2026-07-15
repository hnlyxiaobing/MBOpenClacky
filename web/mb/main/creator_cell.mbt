///| Creator panel - rabbita replacement for `web/js/creator.js`.
///
/// Skills list + scaffold preview + package preview + guidelines.
/// API endpoints:
///   - `GET /api/creator/skills` - list my skills
///   - `POST /api/my-skills/:name/publish` - publish a skill
///   - `POST /api/creator/skills` - create a new skill

///|
priv enum CreatorMsg {
  Init
  SkillsLoaded(Result[Json, String])
  ClickCreate
  CreateNameChanged(String)
  CreateDescChanged(String)
  ClickDoCreate
  CreateDone(Result[Json, String])
  ClickCancelCreate
  ClickPublish(String)
  PublishDone(String, Result[Json, String])
  ClickEdit(String)
  TemplateChanged(String)
  ScaffoldNameChanged(String)
  ClickScaffold
  ClickPackage
  LocaleChanged
}

///|
priv struct CreatorModel {
  skills : Array[Json]
  loading : Bool
  busy : Bool
  show_create_form : Bool
  create_name : String
  create_desc : String
  scaffold_template : String
  scaffold_name : String
  scaffold_preview : String
  show_scaffold_preview : Bool
  show_package_preview : Bool
  package_preview : String
  locale : String
}

///|
fn initial_creator_model() -> CreatorModel {
  {
    skills: [],
    loading: true,
    busy: false,
    show_create_form: false,
    create_name: "",
    create_desc: "",
    scaffold_template: "basic",
    scaffold_name: "",
    scaffold_preview: "",
    show_scaffold_preview: false,
    show_package_preview: false,
    package_preview: "",
    locale: "",
  }
}

///|
fn fetch_creator_skills(emit : @cmd.Emit[CreatorMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(SkillsLoaded(r)), async fn() noraise {
    safe_get("/api/creator/skills")
  })
}

///|
fn publish_skill(emit : @cmd.Emit[CreatorMsg], name : String) -> @cmd.Cmd {
  @cmd.perform(r => emit(PublishDone(name, r)), async fn() noraise {
    safe_post("/api/my-skills/\{name}/publish", Json::null())
  })
}

///|
fn create_skill(emit : @cmd.Emit[CreatorMsg], name : String, desc : String) -> @cmd.Cmd {
  @cmd.perform(r => emit(CreateDone(r)), async fn() noraise {
    let fields : Array[(String, Json)] = [("name", Json::string(name))]
    if not(desc.is_empty()) {
      fields.push(("description", Json::string(desc)))
    }
    safe_post("/api/creator/skills", Json::object(Map::from_array(fields)))
  })
}

///|
fn creator_update(
  emit : @cmd.Emit[CreatorMsg],
  msg : CreatorMsg,
  model : CreatorModel,
) -> (@cmd.Cmd, CreatorModel) {
  match msg {
    Init =>
      (
        @cmd.batch([fetch_creator_skills(emit), locale_change_cmd(emit, LocaleChanged)]),
        { ..model, loading: true, locale: i18n_get_locale() },
      )
    SkillsLoaded(Ok(json)) => {
      let items = match json {
        Array(arr) => arr
        Object(map) =>
          match map.get("skills") {
            Some(Array(arr)) => arr
            _ => []
          }
        _ => []
      }
      (@cmd.none, { ..model, skills: items, loading: false })
    }
    SkillsLoaded(Err(_)) => (@cmd.none, { ..model, skills: [], loading: false })
    ClickCreate =>
      (
        @cmd.none,
        { ..model, show_create_form: true, create_name: "", create_desc: "" },
      )
    CreateNameChanged(v) => (@cmd.none, { ..model, create_name: v })
    CreateDescChanged(v) => (@cmd.none, { ..model, create_desc: v })
    ClickDoCreate => {
      let name = model.create_name.trim().to_string()
      if name.is_empty() {
        app_notify("Skill name is required", "warning")
        (@cmd.none, model)
      } else if not(is_valid_skill_name(name)) {
        app_notify("Name must be lowercase with hyphens only", "warning")
        (@cmd.none, model)
      } else {
        (
          create_skill(emit, name, model.create_desc),
          { ..model, busy: true },
        )
      }
    }
    CreateDone(Ok(_)) => {
      app_notify("Skill created", "success")
      (
        fetch_creator_skills(emit),
        {
          ..model,
          show_create_form: false,
          busy: false,
          create_name: "",
          create_desc: "",
        },
      )
    }
    CreateDone(Err(e)) => {
      app_notify("Create failed: \{e}", "error")
      (@cmd.none, { ..model, busy: false })
    }
    ClickCancelCreate => (@cmd.none, { ..model, show_create_form: false })
    ClickPublish(name) => (publish_skill(emit, name), { ..model, busy: true })
    PublishDone(name, Ok(json)) => {
      let ok = match json {
        Object(map) =>
          match map.get("ok") {
            Some(True) => true
            _ =>
              match map.get("published") {
                Some(True) => true
                _ => false
              }
          }
        _ => false
      }
      if ok {
        app_notify("Skill \"\{name}\" published successfully!", "success")
        (
          fetch_creator_skills(emit),
          { ..model, busy: false },
        )
      } else {
        let err_msg = json_str(json, "error", "Publish failed")
        app_notify(err_msg, "error")
        (@cmd.none, { ..model, busy: false })
      }
    }
    PublishDone(_, Err(e)) => {
      app_notify("Publish failed: \{e}", "error")
      (@cmd.none, { ..model, busy: false })
    }
    ClickEdit(name) => {
      app_show_view("skills-enhanced")
      skill_editor_open(name)
      (@cmd.none, model)
    }
    TemplateChanged(v) => (@cmd.none, { ..model, scaffold_template: v })
    ScaffoldNameChanged(v) => (@cmd.none, { ..model, scaffold_name: v })
    ClickScaffold => {
      let name = model.scaffold_name.trim().to_string()
      if name.is_empty() {
        app_notify("Skill name is required for scaffold", "warning")
        (@cmd.none, model)
      } else if not(is_valid_skill_name(name)) {
        app_notify("Name must be lowercase with hyphens only", "warning")
        (@cmd.none, model)
      } else {
        let tree = scaffold_tree(model.scaffold_template, name)
        app_notify("Scaffold preview for \"\{name}\" (\{model.scaffold_template})", "success")
        (
          @cmd.none,
          { ..model, scaffold_preview: tree, show_scaffold_preview: true },
        )
      }
    }
    ClickPackage => {
      if model.skills.is_empty() {
        app_notify("No skills to package. Create a skill first.", "warning")
        (@cmd.none, model)
      } else {
        // Find first unpublished skill or first one
        let pkg_name = creator_pick_skill_name(model.skills)
        let tree = package_tree(pkg_name)
        app_notify("Package preview for \"\{pkg_name}\"", "info")
        (
          @cmd.none,
          { ..model, package_preview: tree, show_package_preview: true },
        )
      }
    }
    LocaleChanged => (@cmd.none, { ..model, locale: i18n_get_locale() })
  }
}

///|
fn is_valid_skill_name(name : String) -> Bool {
  let chars = name.to_array()
  if chars.is_empty() {
    return false
  }
  // First char must be lowercase letter or digit
  let first = chars[0]
  if not(is_lower_or_digit(first)) {
    return false
  }
  for c in chars {
    if not(is_lower_or_digit(c) || c == '-') {
      return false
    }
  }
  true
}

///|
fn is_lower_or_digit(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
}

///|
fn scaffold_tree(template : String, name : String) -> String {
  match template {
    "tool" =>
      "\{name}/\n├── SKILL.md            # Skill manifest with tool definitions\n├── tools/\n│   └── main.json       # Tool schema definitions\n├── prompts/\n│   ├── system.md       # System prompt\n│   └── tool_use.md     # Tool usage instructions\n├── examples/\n│   └── tool_usage.md   # Tool invocation examples\n└── README.md"
    "mcp" =>
      "\{name}/\n├── SKILL.md            # Skill manifest with MCP config\n├── mcp/\n│   ├── server.json     # MCP server configuration\n│   └── tools.json      # MCP tool definitions\n├── prompts/\n│   └── system.md       # System prompt\n├── examples/\n│   └── mcp_usage.md    # MCP integration examples\n└── README.md"
    _ =>
      "\{name}/\n├── SKILL.md            # Skill manifest & documentation\n├── prompts/\n│   └── system.md       # System prompt template\n├── examples/\n│   └── basic.md        # Usage examples\n└── README.md           # User-facing documentation"
  }
}

///|
fn package_tree(name : String) -> String {
  "\{name}.skill-pack/\n├── manifest.json       # Package metadata\n├── SKILL.md            # Skill documentation\n├── prompts/            # Bundled prompts\n├── tools/              # Tool definitions (if any)\n└── assets/             # Static assets (if any)\n\nPackage size: ~estimated\nTarget: marketplace distribution"
}

///|
fn creator_pick_skill_name(skills : Array[Json]) -> String {
  // Find first unpublished skill, or fall back to first skill
  let mut name = "unknown"
  for skill in skills {
    let is_published = match skill {
      Object(map) =>
        match map.get("published") {
          Some(True) => true
          _ => false
        }
      _ => false
    }
    if not(is_published) {
      name = json_str(skill, "name", "unknown")
      break
    }
  }
  if name == "unknown" && not(skills.is_empty()) {
    name = json_str(skills[0], "name", "unknown")
  }
  name
}

// ── Views ────────────────────────────────────────────────────────

///|
fn creator_view(
  emit : @cmd.Emit[CreatorMsg],
  model : CreatorModel,
) -> @html.Html {
  if model.loading {
    @html.div(class="text-center", [
      @html.div(class="spinner", style=["margin:40px auto"], ""),
    ])
  } else {
    @html.div([
      creator_skills_section(emit, model),
      creator_scaffold_section(emit, model),
      creator_package_section(emit, model),
      creator_guidelines_section(),
    ])
  }
}

///|
fn creator_skills_section(
  emit : @cmd.Emit[CreatorMsg],
  model : CreatorModel,
) -> @html.Html {
  let children : Array[@html.Html] = []

  // Header with Create Skill button
  children.push(
    @html.div(
      class="settings-group-title",
      style=["display:flex", "align-items:center", "justify-content:space-between"],
      [
        @html.span("My Skills (\{model.skills.length()})"),
        @html.button(
          class="btn btn-primary btn-sm",
          on_click=emit(ClickCreate),
          "+ Create Skill",
        ),
      ],
    ),
  )

  // Create form (toggle)
  if model.show_create_form {
    children.push(creator_create_form(emit, model))
  }

  // Skills grid
  if model.skills.is_empty() {
    children.push(
      @html.div(class="empty-state", style=["padding:32px"], [
        @html.div(class="empty-state-icon", "📋"),
        @html.h3("No Skills Created"),
        @html.p(
          style=["color:var(--text-secondary)"],
          "Create skills using the skill editor to publish them to the store.",
        ),
      ]),
    )
  } else {
    let cards : Array[@html.Html] = []
    for skill in model.skills {
      cards.push(creator_skill_card(emit, skill, model.busy))
    }
    children.push(@html.div(class="skills-grid", cards))
  }

  @html.div(class="settings-group", children)
}

///|
fn creator_create_form(
  emit : @cmd.Emit[CreatorMsg],
  model : CreatorModel,
) -> @html.Html {
  @html.div(
    style=["margin-bottom:16px", "padding:16px", "background:var(--bg-tertiary)", "border-radius:var(--radius-sm)"],
    [
      @html.div(class="settings-field", [
        @html.label("Skill Name"),
        @html.input(
          input_type=@html.Text,
          value=model.create_name,
          placeholder="my-awesome-skill",
          on_change=s => emit(CreateNameChanged(s)),
          style=input_style(),
        ),
        @html.div(class="help-text", "Use lowercase with hyphens (e.g., my-skill-name)"),
      ]),
      @html.div(class="settings-field", [
        @html.label("Description"),
        @html.textarea(
          rows=3,
          placeholder="What does this skill do?",
          value=model.create_desc,
          on_change=s => emit(CreateDescChanged(s)),
          style=textarea_style(),
          "",
        ),
      ]),
      @html.div(
        style=["display:flex", "gap:8px"],
        [
          @html.button(
            class="btn btn-primary btn-sm",
            on_click=emit(ClickDoCreate),
            "Create",
          ),
          @html.button(
            class="btn btn-ghost btn-sm",
            on_click=emit(ClickCancelCreate),
            "Cancel",
          ),
        ],
      ),
    ],
  )
}

///|
fn creator_skill_card(
  emit : @cmd.Emit[CreatorMsg],
  skill : Json,
  busy : Bool,
) -> @html.Html {
  let name = json_str(skill, "name", "Unknown")
  let desc = json_str(skill, "description", "")
  let published = json_bool(skill, "published", false)
  let downloads = json_int(skill, "downloads", 0)
  let version = json_str(skill, "version", "")

  let children : Array[@html.Html] = []

  // Name + status badge
  children.push(
    @html.div(
      style=["display:flex", "align-items:center", "gap:8px", "margin-bottom:6px"],
      [
        @html.div(class="skill-card-name", name),
        @html.span(
          class=if published {
            "brand-status-badge active"
          } else {
            "brand-status-badge inactive"
          },
          if published { "Published" } else { "Draft" },
        ),
      ],
    ),
  )

  // Description
  if not(desc.is_empty()) {
    children.push(@html.div(class="skill-card-desc", desc))
  }

  // Version
  if not(version.is_empty()) {
    children.push(
      @html.div(
        class="skill-card-desc",
        style=["font-size:11px"],
        "v\{version}",
      ),
    )
  }

  // Downloads
  if published {
    children.push(
      @html.div(
        class="skill-card-desc",
        style=["font-size:11px", "color:var(--text-muted)"],
        "\{downloads} downloads",
      ),
    )
  }

  // Action buttons
  let btns : Array[@html.Html] = []
  if not(published) {
    btns.push(
      @html.button(
        class="btn btn-primary btn-sm",
        on_click=emit(ClickPublish(name)),
        style=if busy { ["opacity:0.5", "pointer-events:none"] } else { [] },
        "Publish",
      ),
    )
  }
  btns.push(
    @html.button(
      class="btn btn-ghost btn-sm",
      on_click=emit(ClickEdit(name)),
      "Edit",
    ),
  )
  children.push(@html.div(style=["display:flex", "gap:6px", "margin-top:10px"], btns))

  @html.div(class="skill-card", children)
}

///|
fn creator_scaffold_section(
  emit : @cmd.Emit[CreatorMsg],
  model : CreatorModel,
) -> @html.Html {
  let children : Array[@html.Html] = []

  children.push(
    @html.div(class="settings-group-title", t("creator.scaffold_title")),
  )

  children.push(
    @html.div(
      style=["font-size:13px", "color:var(--text-secondary)", "line-height:1.6", "padding:8px 0"],
      [
        @html.div(class="settings-field", style=["margin-bottom:10px"], [
          @html.label(t("creator.template")),
          @html.select(
            on_change=s => emit(TemplateChanged(s)),
            style=input_style(),
            [
              @html.option(
                value="basic",
                selected=model.scaffold_template == "basic",
                t("creator.template_basic"),
              ),
              @html.option(
                value="tool",
                selected=model.scaffold_template == "tool",
                t("creator.template_tool"),
              ),
              @html.option(
                value="mcp",
                selected=model.scaffold_template == "mcp",
                t("creator.template_mcp"),
              ),
            ],
          ),
        ]),
        @html.div(class="settings-field", style=["margin-bottom:10px"], [
          @html.label("Skill Name"),
          @html.input(
            input_type=@html.Text,
            value=model.scaffold_name,
            placeholder="my-awesome-skill",
            on_change=s => emit(ScaffoldNameChanged(s)),
            style=input_style(),
          ),
        ]),
        @html.button(
          class="btn btn-primary btn-sm",
          on_click=emit(ClickScaffold),
          t("creator.scaffold_btn"),
        ),
      ],
    ),
  )

  if model.show_scaffold_preview {
    children.push(
      @html.div(style=["margin-top:12px"], [
        @html.div(
          class="settings-group-title",
          style=["font-size:13px"],
          t("creator.preview_structure"),
        ),
        @html.pre(
          style=[
            "background:var(--bg-tertiary)",
            "padding:12px",
            "border-radius:var(--radius-sm)",
            "font-size:12px",
            "line-height:1.5",
            "overflow-x:auto",
            "color:var(--text-secondary)",
            "border:1px solid var(--border)",
          ],
          model.scaffold_preview,
        ),
      ]),
    )
  }

  @html.div(class="settings-group", children)
}

///|
fn creator_package_section(
  emit : @cmd.Emit[CreatorMsg],
  model : CreatorModel,
) -> @html.Html {
  let children : Array[@html.Html] = []

  children.push(
    @html.div(class="settings-group-title", t("creator.pack_title")),
  )

  children.push(
    @html.div(
      style=["font-size:13px", "color:var(--text-secondary)", "line-height:1.6", "padding:8px 0"],
      [
        @html.p(
          style=["margin-bottom:10px"],
          "Package your skill for distribution and publishing to the marketplace.",
        ),
        @html.button(
          class="btn btn-ghost btn-sm",
          on_click=emit(ClickPackage),
          t("creator.pack_btn"),
        ),
      ],
    ),
  )

  if model.show_package_preview {
    children.push(
      @html.div(style=["margin-top:12px"], [
        @html.pre(
          style=[
            "background:var(--bg-tertiary)",
            "padding:12px",
            "border-radius:var(--radius-sm)",
            "font-size:12px",
            "line-height:1.5",
            "overflow-x:auto",
            "color:var(--text-secondary)",
            "border:1px solid var(--border)",
          ],
          model.package_preview,
        ),
      ]),
    )
  }

  @html.div(class="settings-group", children)
}

///|
fn creator_guidelines_section() -> @html.Html {
  @html.div(class="settings-group", [
    @html.div(class="settings-group-title", "Creator Guidelines"),
    @html.div(
      style=["font-size:13px", "color:var(--text-secondary)", "line-height:1.6", "padding:8px 0"],
      [
        @html.ul(
          style=["padding-left:20px"],
          [
            @html.li("Skills must include a valid SKILL.md manifest"),
            @html.li("Test your skill thoroughly before publishing"),
            @html.li("Follow the skill naming conventions"),
            @html.li("Provide clear descriptions and usage examples"),
          ],
        ),
      ],
    ),
  ])
}

///|
fn build_creator_cell() -> (@cmd.Emit[CreatorMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_creator_model(),
    update=creator_update,
    view=creator_view,
  )
}
