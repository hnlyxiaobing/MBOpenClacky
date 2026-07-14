///| Workspace panel - rabbita replacement for `web/js/workspace.js`.
///
/// Directory browser with navigation, set-working-directory, and
/// create-folder actions. All strings through `i18n_t`.
///
/// API endpoints:
///   - `GET /api/dirs?path=` - list directory contents
///   - `POST /api/dirs/mkdir` - create a folder
///   - `POST /api/sessions/:id/working_dir` - set working directory

///|
priv enum WorkspaceMsg {
  Init
  FilesLoaded(Result[Json, String])
  PathInputChanged(String)
  ClickSetDir
  SetDirDone(Result[Json, String])
  ClickNavigateTo(String)
  ClickNavigateUp
  ClickOpenMkdir
  MkdirNameChanged(String)
  ClickCancelMkdir
  ClickConfirmMkdir
  MkdirDone(Result[Json, String])
  ClickSetRecent(String)
  LocaleChanged
}

///|
priv struct WorkspaceModel {
  current_dir : String
  path_input : String
  files : Array[Json]
  recent_dirs : Array[String]
  mkdir_open : Bool
  mkdir_name : String
  busy : Bool
  error : String
  locale : String
}

///|
fn initial_workspace_model() -> WorkspaceModel {
  {
    current_dir: "",
    path_input: "",
    files: [],
    recent_dirs: [],
    mkdir_open: false,
    mkdir_name: "",
    busy: false,
    error: "",
    locale: "",
  }
}

///|
fn fetch_dirs(emit : @cmd.Emit[WorkspaceMsg], path : String) -> @cmd.Cmd {
  let url = "/api/dirs?path=" + js_encode_uri_component(path)
  @cmd.perform(r => emit(FilesLoaded(r)), async fn() noraise {
    safe_get(url)
  })
}

///|
fn workspace_update(
  emit : @cmd.Emit[WorkspaceMsg],
  msg : WorkspaceMsg,
  model : WorkspaceModel,
) -> (@cmd.Cmd, WorkspaceModel) {
  match msg {
    Init =>
      (
        @cmd.batch([
          fetch_dirs(emit, ""),
          locale_change_cmd(emit, LocaleChanged),
        ]),
        { ..model, locale: i18n_get_locale() },
      )
    FilesLoaded(Ok(json)) => {
      let files = match json {
        Object(map) =>
          match map.get("files") {
            Some(Array(arr)) => arr
            _ =>
              match map.get("dirs") {
                Some(Array(arr)) => arr
                _ => []
              }
          }
        Array(arr) => arr
        _ => []
      }
      (@cmd.none, { ..model, files })
    }
    FilesLoaded(Err(e)) => {
      app_notify(
        t1("workspace.fetch_failed", "error", e),
        "error",
      )
      (@cmd.none, { ..model, files: [], error: e })
    }
    PathInputChanged(s) => (@cmd.none, { ..model, path_input: s })
    ClickSetDir => {
      let path = model.path_input.trim().to_owned()
      if path == "" {
        app_notify(t("workspace.enter_path"), "warning")
        (@cmd.none, model)
      } else {
        let session_id = js_current_session_id()
        if session_id == "" {
          app_notify(t("workspace.no_session"), "warning")
          (@cmd.none, model)
        } else {
          let body = Json::object(
            Map::of([("working_dir", Json::string(path))]),
          )
          let cmd = @cmd.perform(r => emit(SetDirDone(r)), async fn() noraise {
            safe_post("/api/sessions/" + session_id + "/working_dir", body)
          })
          (cmd, { ..model, busy: true })
        }
      }
    }
    SetDirDone(Ok(_)) => {
      let new_recent : Array[String] = [model.path_input]
      for d in model.recent_dirs {
        if d != model.path_input {
          new_recent.push(d)
        }
      }
      let trimmed = if new_recent.length() > 10 {
        new_recent.iter().take(10).collect()
      } else {
        new_recent
      }
      app_notify(
        t1("workspace.set_success", "path", model.path_input),
        "success",
      )
      (
        fetch_dirs(emit, model.path_input),
        { ..model, current_dir: model.path_input, recent_dirs: trimmed, busy: false },
      )
    }
    SetDirDone(Err(e)) => {
      app_notify(
        t1("workspace.set_failed", "error", e),
        "error",
      )
      (@cmd.none, { ..model, busy: false, error: e })
    }
    ClickNavigateTo(name) => {
      let new_path = if model.current_dir == "" {
        name
      } else {
        model.current_dir + "/" + name
      }
      (
        fetch_dirs(emit, new_path),
        { ..model, current_dir: new_path, path_input: new_path },
      )
    }
    ClickNavigateUp => {
      let current = model.current_dir
      if current == "" || current == "/" || current == "." {
        (@cmd.none, model)
      } else {
        // Find last '/' and take everything before it
        let mut last_slash = -1
        for i in 0..<current.length() {
          if current[i] == '/' {
            last_slash = i
          }
        }
        let parent = if last_slash <= 0 {
          ""
        } else {
          current.substring(start=0, end=last_slash)
        }
        (
          fetch_dirs(emit, parent),
          { ..model, current_dir: parent, path_input: parent },
        )
      }
    }
    ClickOpenMkdir =>
      (@cmd.none, { ..model, mkdir_open: true, mkdir_name: "" })
    MkdirNameChanged(s) => (@cmd.none, { ..model, mkdir_name: s })
    ClickCancelMkdir =>
      (@cmd.none, { ..model, mkdir_open: false, mkdir_name: "" })
    ClickConfirmMkdir => {
      let name = model.mkdir_name.trim().to_owned()
      if name == "" {
        app_notify(t("workspace.name_required"), "warning")
        (@cmd.none, model)
      } else {
        let body = Json::object(
          Map::of([
            ("path", Json::string(model.current_dir)),
            ("name", Json::string(name)),
          ]),
        )
        let cmd = @cmd.perform(r => emit(MkdirDone(r)), async fn() noraise {
          safe_post("/api/dirs/mkdir", body)
        })
        (cmd, { ..model, busy: true })
      }
    }
    MkdirDone(Ok(_)) => {
      app_notify(
        t1("workspace.folder_created", "name", model.mkdir_name),
        "success",
      )
      (
        fetch_dirs(emit, model.current_dir),
        { ..model, busy: false, mkdir_open: false, mkdir_name: "" },
      )
    }
    MkdirDone(Err(e)) => {
      app_notify(
        t1("workspace.create_failed", "error", e),
        "error",
      )
      (@cmd.none, { ..model, busy: false, error: e })
    }
    ClickSetRecent(path) =>
      (
        fetch_dirs(emit, path),
        { ..model, current_dir: path, path_input: path },
      )
    LocaleChanged => (@cmd.none, { ..model, locale: i18n_get_locale() })
  }
}

///| Get the name of a file entry (string or object with name/path).
fn file_name(f : Json) -> String {
  match f {
    String(s) => s
    Object(map) =>
      match map.get("name") {
        Some(String(s)) => s
        _ =>
          match map.get("path") {
            Some(String(s)) => s
            _ => ""
          }
      }
    _ => ""
  }
}

///| Check if a file entry is a directory.
fn file_is_dir(f : Json) -> Bool {
  match f {
    String(s) => !s.contains(".")
    Object(map) =>
      match map.get("is_dir") {
        Some(True) => true
        Some(False) => false
        _ =>
          match map.get("type") {
            Some(String(s)) => s == "dir"
            _ => false
          }
      }
    _ => false
  }
}

///|
fn workspace_view(
  emit : @cmd.Emit[WorkspaceMsg],
  model : WorkspaceModel,
) -> @html.Html {
  // File list
  let files_html : @html.Html = if model.files.length() == 0 {
    @html.p(
      class="text-muted",
      style=["padding:8px 0", "font-size:13px"],
      t("workspace.empty_dir"),
    )
  } else {
    @html.div(
      class="workspace-file-list",
      model.files.map(f => {
        let name = file_name(f)
        let is_dir = file_is_dir(f)
        let icon = if is_dir { "📁" } else { "📄" }
        if is_dir {
          @html.div(
            class="workspace-file-item",
            style=["cursor:pointer"],
            on_click=emit(ClickNavigateTo(name)),
            [
              @html.span(class="workspace-file-icon", @html.text(icon)),
              @html.span(class="workspace-file-name", name),
            ],
          )
        } else {
          @html.div(class="workspace-file-item", [
            @html.span(class="workspace-file-icon", @html.text(icon)),
            @html.span(class="workspace-file-name", name),
          ])
        }
      }),
    )
  }
  // Recent dirs
  let recent_html : @html.Html = if model.recent_dirs.length() == 0 {
    @html.p(class="text-muted", style=["font-size:12px"], t("workspace.no_recent"))
  } else {
    @html.div(
      id="workspace-recent-list",
      model.recent_dirs.map(d => {
        @html.div(
          class="workspace-recent-item",
          style=["cursor:pointer", "padding:4px 0", "font-size:12px", "color:var(--accent)"],
          on_click=emit(ClickSetRecent(d)),
          d,
        )
      }),
    )
  }
  @html.div([
    // Current Working Directory
    @html.div(class="settings-group", [
      @html.div(class="settings-group-title", t("workspace.current_dir")),
      @html.div(class="settings-field", [
        @html.div(style=["display:flex", "gap:8px", "align-items:center"], [
          @html.input(
            input_type=@html.Text,
            id="workspace-path-input",
            value=model.path_input,
            placeholder="/path/to/project",
            on_change=s => emit(PathInputChanged(s)),
            style=[
              "flex:1",
              "padding:9px 12px",
              "background:var(--bg-tertiary)",
              "border:1px solid var(--border)",
              "border-radius:var(--radius-sm)",
              "color:var(--text-primary)",
              "font-size:13px",
              "font-family:var(--font-mono)",
              "outline:none",
            ],
          ),
          @html.button(
            class="btn btn-primary btn-sm",
            on_click=emit(ClickSetDir),
            t("workspace.set"),
          ),
        ]),
        @html.div(class="help-text", t("workspace.dir_help")),
      ]),
    ]),
    // Directory Browser
    @html.div(class="settings-group", [
      @html.div(
        class="settings-group-title",
        style=["display:flex", "align-items:center", "justify-content:space-between"],
        [
          @html.span(t("workspace.browser")),
          @html.div(style=["display:flex", "gap:6px"], [
            @html.button(
              class="btn btn-ghost btn-sm",
              on_click=emit(ClickNavigateUp),
              t("workspace.up"),
            ),
            @html.button(
              class="btn btn-ghost btn-sm",
              on_click=emit(ClickOpenMkdir),
              t("workspace.new_folder"),
            ),
          ]),
        ],
      ),
      files_html,
      // Inline mkdir form
      if model.mkdir_open {
        @html.div(class="settings-field", style=["margin-top:8px"], [
          @html.label(t("workspace.folder_name")),
          @html.input(
            input_type=@html.Text,
            id="mkdir-name",
            placeholder=t("workspace.folder_placeholder"),
            value=model.mkdir_name,
            on_change=s => emit(MkdirNameChanged(s)),
            style=[
              "width:100%",
              "padding:9px 12px",
              "background:var(--bg-tertiary)",
              "border:1px solid var(--border)",
              "border-radius:var(--radius-sm)",
              "color:var(--text-primary)",
              "font-size:13px",
              "outline:none",
            ],
          ),
          @html.div(style=["display:flex", "gap:8px", "margin-top:8px"], [
            @html.button(
              class="btn btn-ghost",
              on_click=emit(ClickCancelMkdir),
              t("common.cancel"),
            ),
            @html.button(
              class="btn btn-primary",
              on_click=emit(ClickConfirmMkdir),
              if model.busy { "..." } else { t("workspace.create") },
            ),
          ]),
        ])
      } else {
        @html.nothing
      },
    ]),
    // Recent Directories
    @html.div(class="settings-group", [
      @html.div(class="settings-group-title", t("workspace.recent")),
      recent_html,
    ]),
  ])
}

///|
fn build_workspace_cell() -> (@cmd.Emit[WorkspaceMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_workspace_model(),
    update=workspace_update,
    view=workspace_view,
  )
}
