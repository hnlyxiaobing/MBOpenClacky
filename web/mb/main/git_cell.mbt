///| Git panel - rabbita replacement for `web/js/git_panel.js`.
///
/// Shows git status, diff, and commit form.
/// API endpoints:
///   - `GET /api/git/status` - branch, changed files, staged/unstaged
///   - `GET /api/git/diff` - diff text
///   - `POST /api/git/commit` - commit with message

///|
priv enum GitMsg {
  Init
  StatusLoaded(Result[Json, String])
  DiffLoaded(Result[Json, String])
  CommitMessageChanged(String)
  ClickCommit
  CommitDone(Result[Json, String])
  ClickRefresh
  LocaleChanged
}

///|
priv struct GitModel {
  status : Json
  diff : String
  has_diff : Bool
  commit_message : String
  loading : Bool
  busy : Bool
  locale : String
}

///|
fn initial_git_model() -> GitModel {
  {
    status: Json::null(),
    diff: "",
    has_diff: false,
    commit_message: "",
    loading: true,
    busy: false,
    locale: "",
  }
}

///|
fn fetch_git_status(emit : @cmd.Emit[GitMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(StatusLoaded(r)), async fn() noraise {
    safe_get("/api/git/status")
  })
}

///|
fn fetch_git_diff(emit : @cmd.Emit[GitMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(DiffLoaded(r)), async fn() noraise {
    safe_get("/api/git/diff")
  })
}

///|
fn git_commit(emit : @cmd.Emit[GitMsg], message : String) -> @cmd.Cmd {
  @cmd.perform(r => emit(CommitDone(r)), async fn() noraise {
    safe_post("/api/git/commit", Json::object(Map::of([("message", Json::string(message))])))
  })
}

///|
fn git_update(
  emit : @cmd.Emit[GitMsg],
  msg : GitMsg,
  model : GitModel,
) -> (@cmd.Cmd, GitModel) {
  match msg {
    Init =>
      (
        @cmd.batch([
          fetch_git_status(emit),
          fetch_git_diff(emit),
          locale_change_cmd(emit, LocaleChanged),
        ]),
        { ..model, loading: true, locale: i18n_get_locale() },
      )
    StatusLoaded(Ok(json)) =>
      (@cmd.none, { ..model, status: json, loading: false })
    StatusLoaded(Err(_)) => (@cmd.none, { ..model, loading: false })
    DiffLoaded(Ok(json)) => {
      let diff_text = match json {
        String(s) => s
        Object(map) =>
          match map.get("diff") {
            Some(String(s)) => s
            _ => ""
          }
        _ => ""
      }
      (@cmd.none, { ..model, diff: diff_text, has_diff: not(diff_text.is_empty()) })
    }
    DiffLoaded(Err(_)) => (@cmd.none, { ..model, diff: "", has_diff: false })
    CommitMessageChanged(v) => (@cmd.none, { ..model, commit_message: v })
    ClickCommit => {
      let msg_text = model.commit_message.trim()
      if msg_text.is_empty() {
        app_notify("Please enter a commit message", "error")
        (@cmd.none, model)
      } else {
        (git_commit(emit, msg_text), { ..model, busy: true })
      }
    }
    CommitDone(Ok(_)) => {
      app_notify("Committed successfully", "success")
      (
        @cmd.batch([fetch_git_status(emit), fetch_git_diff(emit)]),
        { ..model, commit_message: "", busy: false },
      )
    }
    CommitDone(Err(e)) => {
      app_notify("Commit failed: \{e}", "error")
      (@cmd.none, { ..model, busy: false })
    }
    ClickRefresh =>
      (
        @cmd.batch([fetch_git_status(emit), fetch_git_diff(emit)]),
        { ..model, loading: true },
      )
    LocaleChanged => (@cmd.none, { ..model, locale: i18n_get_locale() })
  }
}

// ── Views ────────────────────────────────────────────────────────

///|
fn git_view(
  emit : @cmd.Emit[GitMsg],
  model : GitModel,
) -> @html.Html {
  if model.loading {
    @html.div(class="text-center", [
      @html.div(class="spinner", style=["margin:40px auto"], []),
    ])
  } else {
    let children : Array[@html.Html] = []

    // Header: branch badge + refresh
    let header_children : Array[@html.Html] = []
    header_children.push(@html.h2([], "Git"))
    let branch = git_branch(model.status)
    if not(branch.is_empty()) {
      header_children.push(
        @html.span(
          style=[
            "background:var(--accent-dim)",
            "color:var(--accent)",
            "padding:3px 10px",
            "border-radius:10px",
            "font-size:12px",
            "font-weight:600",
          ],
          "⎇ \{branch}",
        ),
      )
    }
    header_children.push(
      @html.button(
        class="btn btn-ghost btn-sm",
        on_click=emit(ClickRefresh),
        "↻ Refresh",
      ),
    )
    children.push(
      @html.div(
        style=["display:flex", "align-items:center", "gap:10px", "margin-bottom:16px"],
        header_children,
      ),
    )

    // Check if status is null (no git data)
    if git_is_null_status(model.status) {
      children.push(
        @html.div(class="empty-state", [
          @html.div(class="empty-state-icon", "⎇"),
          @html.h3([], "No Git Data"),
          @html.p(class="text-muted", "Could not retrieve git status."),
        ]),
      )
    } else {
      // Changes section
      children.push(git_changes_section(model))
      // Diff section
      if model.has_diff {
        children.push(git_diff_section(model.diff))
      }
      // Commit section
      children.push(git_commit_section(emit, model))
    }

    @html.div([], children)
  }
}

///|
fn git_is_null_status(status : Json) -> Bool {
  match status {
    Null => true
    _ => false
  }
}

///|
fn git_branch(status : Json) -> String {
  json_str(status, "branch", "")
}

///|
fn git_changes_section(model : GitModel) -> @html.Html {
  let files = git_extract_files(model.status)

  let children : Array[@html.Html] = []
  children.push(
    @html.h3(
      style=[
        "font-size:13px",
        "font-weight:600",
        "color:var(--text-secondary)",
        "text-transform:uppercase",
        "letter-spacing:0.8px",
        "margin-bottom:12px",
        "padding-bottom:8px",
        "border-bottom:1px solid var(--border)",
      ],
      "Changed Files",
    ),
  )

  if files.is_empty() {
    children.push(
      @html.p(
        class="text-muted",
        style=["font-size:13px", "padding:16px 0"],
        "No changes detected. Working tree is clean.",
      ),
    )
  } else {
    let rows : Array[@html.Html] = []
    for file in files {
      rows.push(git_file_row(file))
    }
    children.push(
      @html.div(
        style=["display:flex", "flex-direction:column", "gap:2px"],
        rows,
      ),
    )
  }

  @html.div(style=["margin-bottom:24px"], children)
}

///|
priv struct GitFile {
  path : String
  status : String
  staged : Bool
}

///|
fn git_extract_files(status : Json) -> Array[GitFile] {
  let files : Array[GitFile] = []

  // Handle different response shapes
  let changed = match status {
    Object(map) =>
      match map.get("files") {
        Some(Array(arr)) => arr
        _ =>
          match map.get("changed_files") {
            Some(Array(arr)) => arr
            _ =>
              match map.get("changes") {
                Some(Array(arr)) => arr
                _ => []
              }
          }
      }
    _ => []
  }

  for f in changed {
    match f {
      String(s) => files.push({ path: s, status: "modified", staged: false })
      Object(map) => {
        let path = match map.get("path") {
          Some(String(s)) => s
          _ =>
            match map.get("file") {
              Some(String(s)) => s
              _ =>
                match map.get("name") {
                  Some(String(s)) => s
                  _ => "unknown"
                }
            }
        }
        let st = match map.get("status") {
          Some(String(s)) => s.to_lower()
          _ =>
            match map.get("state") {
              Some(String(s)) => s.to_lower()
              _ =>
                match map.get("type") {
                  Some(String(s)) => s.to_lower()
                  _ => "modified"
                }
            }
        }
        let staged = match map.get("staged") {
          Some(True) => true
          _ => false
        }
        files.push({ path, status: st, staged })
      }
      _ => ()
    }
  }

  // Handle separate staged/unstaged arrays
  match status {
    Object(map) =>
      match map.get("staged") {
        Some(Array(staged_arr)) => {
          for f in staged_arr {
            let (path, st) = git_parse_file_entry(f)
            let found = files.iter().find(fn(x) { x.path == path })
            match found {
              Some(_) => ()
              None =>
                files.push({ path, status: st, staged: true })
            }
          }
        }
        _ => ()
      }
    _ => ()
  }

  match status {
    Object(map) =>
      match map.get("unstaged") {
        Some(Array(unstaged_arr)) => {
          for f in unstaged_arr {
            let (path, st) = git_parse_file_entry(f)
            let found = files.iter().find(fn(x) { x.path == path })
            match found {
              Some(_) => ()
              None =>
                files.push({ path, status: st, staged: false })
            }
          }
        }
        _ => ()
      }
    _ => ()
  }

  files
}

///|
fn git_parse_file_entry(f : Json) -> (String, String) {
  match f {
    String(s) => (s, "modified")
    Object(map) => {
      let path = match map.get("path") {
        Some(String(s)) => s
        _ =>
          match map.get("file") {
            Some(String(s)) => s
            _ => "unknown"
          }
      }
      let st = match map.get("status") {
        Some(String(s)) => s.to_lower()
        _ =>
          match map.get("state") {
            Some(String(s)) => s.to_lower()
            _ => "modified"
          }
      }
      (path, st)
    }
    _ => ("unknown", "modified")
  }
}

///|
fn git_file_row(file : GitFile) -> @html.Html {
  let children : Array[@html.Html] = []

  // Status badge
  let (badge_label, badge_style) = git_status_badge(file.status)
  children.push(
    @html.span(
      style=badge_style,
      badge_label,
    ),
  )

  // File path
  children.push(
    @html.span(
      style=[
        "font-size:13px",
        "font-family:var(--font-mono)",
        "color:var(--text-primary)",
        "overflow:hidden",
        "text-overflow:ellipsis",
        "white-space:nowrap",
      ],
      file.path,
    ),
  )

  let row_children : Array[@html.Html] = []
  row_children.push(
    @html.div(
      style=["display:flex", "align-items:center", "gap:10px", "min-width:0", "flex:1"],
      children,
    ),
  )

  // Staged indicator
  if file.staged {
    row_children.push(
      @html.span(
        style=["font-size:11px", "color:var(--success)", "font-weight:500", "white-space:nowrap", "margin-left:8px"],
        "● staged",
      ),
    )
  }

  @html.div(
    style=["display:flex", "align-items:center", "justify-content:space-between", "padding:8px 12px", "border-radius:var(--radius-sm)"],
    row_children,
  )
}

///|
fn git_status_badge(status : String) -> (String, Array[String]) {
  let base : Array[String] = [
    "display:inline-block",
    "width:20px",
    "height:20px",
    "border-radius:var(--radius-sm)",
    "font-size:11px",
    "font-weight:700",
    "text-align:center",
    "line-height:20px",
    "flex-shrink:0",
  ]
  match status {
    "added" | "new" | "untracked" => {
      let s = [...base, "background:rgba(158,206,106,0.15)", "color:var(--success)"]
      ("A", s)
    }
    "deleted" | "removed" => {
      let s = [...base, "background:rgba(247,118,142,0.15)", "color:var(--danger)"]
      ("D", s)
    }
    "renamed" => {
      let s = [...base, "background:rgba(224,175,104,0.15)", "color:var(--warning)"]
      ("R", s)
    }
    _ => {
      let s = [...base, "background:rgba(122,162,247,0.15)", "color:var(--accent)"]
      ("M", s)
    }
  }
}

///|
fn git_diff_section(diff : String) -> @html.Html {
  let lines : Array[@html.Html] = []

  lines.push(
    @html.h3(
      style=[
        "font-size:13px",
        "font-weight:600",
        "color:var(--text-secondary)",
        "text-transform:uppercase",
        "letter-spacing:0.8px",
        "margin-bottom:12px",
        "padding-bottom:8px",
        "border-bottom:1px solid var(--border)",
      ],
      "Diff",
    ),
  )

  // Build diff table with colored lines
  let diff_lines = diff.split("\n").collect()
  let rows : Array[@html.Html] = []
  for i, line in diff_lines {
    if not(line.is_empty()) {
      let style = git_diff_line_style(line)
      rows.push(
        @html.tr([], [
          @html.td(style=style, line),
        ]),
      )
    }
  }
  lines.push(
    @html.div(
      style=[
        "background:var(--bg-primary)",
        "border:1px solid var(--border)",
        "border-radius:var(--radius)",
        "overflow:auto",
        "max-height:400px",
        "font-family:var(--font-mono)",
        "font-size:12px",
        "line-height:1.6",
      ],
      [@html.table(style=["width:100%", "border-collapse:collapse"], rows)],
    ),
  )

  @html.div(style=["margin-bottom:24px"], lines)
}

///|
fn git_diff_line_style(line : String) -> Array[String] {
  let base : Array[String] = ["padding:2px 12px", "white-space:pre"]
  if line.has_prefix("+++") || line.has_prefix("---") {
    [...base, "background:var(--bg-tertiary)", "color:var(--text-secondary)", "font-weight:600"]
  } else if line.has_prefix("@@") {
    [...base, "background:rgba(122,162,247,0.1)", "color:var(--info)"]
  } else if line.has_prefix("+") {
    [...base, "background:rgba(158,206,106,0.12)", "color:var(--success)"]
  } else if line.has_prefix("-") {
    [...base, "background:rgba(247,118,142,0.12)", "color:var(--danger)"]
  } else if line.has_prefix("diff ") || line.has_prefix("index ") {
    [...base, "background:var(--bg-tertiary)", "color:var(--text-muted)", "font-weight:500"]
  } else {
    [...base, "color:var(--text-secondary)"]
  }
}

///|
fn git_commit_section(
  emit : @cmd.Emit[GitMsg],
  model : GitModel,
) -> @html.Html {
  let files = git_extract_files(model.status)
  let disabled = files.is_empty() || model.busy

  @html.div(style=["margin-top:8px"], [
    @html.h3(
      style=[
        "font-size:13px",
        "font-weight:600",
        "color:var(--text-secondary)",
        "text-transform:uppercase",
        "letter-spacing:0.8px",
        "margin-bottom:12px",
        "padding-bottom:8px",
        "border-bottom:1px solid var(--border)",
      ],
      "Commit",
    ),
    @html.div(style=["margin-bottom:12px"], [
      @html.textarea(
        rows=3,
        placeholder="Enter commit message...",
        value=model.commit_message,
        on_change=s => emit(CommitMessageChanged(s)),
        style=[
          "width:100%",
          "min-height:80px",
          "padding:10px 12px",
          "background:var(--bg-tertiary)",
          "border:1px solid var(--border)",
          "border-radius:var(--radius-sm)",
          "color:var(--text-primary)",
          "font-size:13px",
          "font-family:var(--font-sans)",
          "resize:vertical",
          "outline:none",
        ],
      ),
    ]),
    @html.button(
      class="btn btn-primary",
      on_click=emit(ClickCommit),
      style=if disabled { ["opacity:0.5", "pointer-events:none"] } else { [] },
      "✓ Commit",
    ),
  ])
}

///|
fn build_git_cell() -> (@cmd.Emit[GitMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_git_model(),
    update=git_update,
    view=git_view,
  )
}
