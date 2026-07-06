///| Git panel REST API handlers.
///  Each handler receives a Ref[WebServer] and a crescent Event,
///  following the new-style handler pattern (see handlers_browser.mbt).
///  Command execution helpers are in git_exec.mbt.

// ── Internal Helpers ──────────────────────────────────────────────

///|
/// Parse porcelain status into a JSON array of file objects.
fn parse_git_files(porcelain : String) -> Json {
  let files : Array[Json] = []
  let lines = git_split_lines(porcelain)
  for line in lines {
    if line.length() < 4 {
      continue
    }
    let chars = line.to_array()
    let x = chars[0]
    let y = chars[1]
    let file_path = line[3:].to_owned()
    let status = if x == '?' && y == '?' {
      "untracked"
    } else if x == 'A' || y == 'A' {
      "added"
    } else if x == 'D' || y == 'D' {
      "deleted"
    } else if x == 'R' || y == 'R' {
      "renamed"
    } else {
      "modified"
    }
    let staged = x != ' ' && x != '?'
    files.push(
      Json::object({
        "path": file_path.to_json(),
        "status": status.to_json(),
        "staged": staged.to_json(),
      }),
    )
  }
  Json::array(files)
}

///|
/// Split string into lines (local helper).
fn git_split_lines(s : String) -> Array[String] {
  let result : Array[String] = []
  let current = StringBuilder::new()
  for ch in s {
    if ch == '\n' {
      let line = current.to_string()
      if line.length() > 0 {
        result.push(line)
      }
      current.reset()
    } else if ch != '\r' {
      current.write_char(ch)
    }
  }
  let last = current.to_string()
  if last.length() > 0 {
    result.push(last)
  }
  result
}

///|
/// Helper: build JSON error response.
fn git_error_resp(msg : String) -> @core.HttpResponse {
  @core.HttpResponse::bad_request().json_value(
    Json::object({ "error": msg.to_json() }),
  )
}

///|
/// Helper: build JSON success response.
fn git_ok_resp(msg : String) -> @core.HttpResponse {
  @core.HttpResponse::ok().json_value(
    Json::object({ "status": "ok".to_json(), "message": msg.to_json() }),
  )
}

///|
/// Escape a string for safe inclusion in shell commands.
fn git_shell_escape(s : String) -> String {
  let is_win = @sys.get_env_var("OS") is Some(v) && v == "Windows_NT"
  if is_win {
    "\"" + s + "\""
  } else {
    "'" + s + "'"
  }
}

// ── Git Handlers ──────────────────────────────────────────────────

///|
/// GET /api/git/status — Get full git working tree status.
pub fn handle_git_status(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let porcelain = git_run("status --porcelain")
  let branch_out = git_run("branch -vv")
  let log_out = git_run("log --oneline -1")
  let time_out = git_run("log -1 --format=%ci")
  let status = @server.build_git_status(
    porcelain,
    branch_out,
    log_out,
    commit_time=time_out.trim().to_owned(),
  )
  let files = parse_git_files(porcelain)
  @core.HttpResponse::ok().json_value(
    Json::object({
      "branch": status.branch.to_json(),
      "ahead": status.ahead.to_json(),
      "behind": status.behind.to_json(),
      "staged": status.staged.to_json(),
      "modified": status.modified.to_json(),
      "untracked": status.untracked.to_json(),
      "deleted": status.deleted.to_json(),
      "conflicts": status.conflicts.to_json(),
      "last_commit_msg": status.last_commit_msg.to_json(),
      "last_commit_hash": status.last_commit_hash.to_json(),
      "last_commit_time": status.last_commit_time.to_json(),
      "is_dirty": status.is_dirty.to_json(),
      "is_detached": status.is_detached.to_json(),
      "files": files,
    }),
  )
}

///|
/// GET /api/git/diff — Get diff output (optionally for a specific file via ?file= query).
pub fn handle_git_diff(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let file = event.req.get_query("file").unwrap_or("")
  let args = if file.is_empty() {
    "diff HEAD"
  } else {
    "diff HEAD -- " + git_shell_escape(file)
  }
  let output = git_run(args)
  @core.HttpResponse::ok().json_value(
    Json::object({ "diff": output.to_json() }),
  )
}

///|
/// POST /api/git/stage — Stage files. Body: { "files": ["path1", "path2"] }
pub fn handle_git_stage(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch {
    _ => return git_error_resp("Request body is required")
  }
  let files = match body {
    { "files": Array(arr), .. } => arr
    _ => return git_error_resp("Missing 'files' array in request body")
  }
  if files.length() == 0 {
    return git_error_resp("No files specified")
  }
  let mut args = "add"
  for f in files {
    match f {
      String(s) => args = args + " " + git_shell_escape(s)
      _ => ()
    }
  }
  let output = git_run(args)
  if git_output_is_error(output) {
    return git_error_resp(output.trim().to_owned())
  }
  git_ok_resp("Staged \{files.length()} file(s)")
}

///|
/// POST /api/git/unstage — Unstage files. Body: { "files": ["path1", "path2"] }
pub fn handle_git_unstage(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch {
    _ => return git_error_resp("Request body is required")
  }
  let files = match body {
    { "files": Array(arr), .. } => arr
    _ => return git_error_resp("Missing 'files' array in request body")
  }
  if files.length() == 0 {
    return git_error_resp("No files specified")
  }
  let mut args = "reset HEAD"
  for f in files {
    match f {
      String(s) => args = args + " " + git_shell_escape(s)
      _ => ()
    }
  }
  let output = git_run(args)
  if git_output_is_error(output) {
    return git_error_resp(output.trim().to_owned())
  }
  git_ok_resp("Unstaged \{files.length()} file(s)")
}

///|
/// POST /api/git/commit — Commit staged changes. Body: { "message": "..." }
pub fn handle_git_commit(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch {
    _ => return git_error_resp("Request body is required")
  }
  let message = match body {
    { "message": String(m), .. } => m
    _ => return git_error_resp("Missing 'message' field in request body")
  }
  if message.is_empty() {
    return git_error_resp("Commit message cannot be empty")
  }
  let args = "commit -m " + git_shell_escape(message)
  let output = git_run(args)
  if git_output_is_error(output) {
    return git_error_resp(output.trim().to_owned())
  }
  git_ok_resp(output.trim().to_owned())
}

///|
/// POST /api/git/push — Push commits to the remote.
pub fn handle_git_push(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let output = git_run("push")
  if git_output_is_error(output) {
    return git_error_resp(output.trim().to_owned())
  }
  git_ok_resp(output.trim().to_owned())
}

///|
/// POST /api/git/pull — Pull changes from the remote.
pub fn handle_git_pull(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let output = git_run("pull")
  if git_output_is_error(output) {
    return git_error_resp(output.trim().to_owned())
  }
  git_ok_resp(output.trim().to_owned())
}

///|
/// GET /api/git/branches — List all local branches.
pub fn handle_git_branches(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let output = git_run("branch")
  let lines = git_split_lines(output)
  let branches : Array[Json] = []
  let mut current = ""
  for line in lines {
    let trimmed = line.trim().to_owned()
    if trimmed.length() == 0 {
      continue
    }
    if line.length() > 1 && line.to_array()[0] == '*' {
      let name = line[2:].to_owned().trim().to_owned()
      current = name
      branches.push(
        Json::object({ "name": name.to_json(), "current": true.to_json() }),
      )
    } else {
      branches.push(
        Json::object({ "name": trimmed.to_json(), "current": false.to_json() }),
      )
    }
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "branches": Json::array(branches),
      "current": current.to_json(),
    }),
  )
}

///|
/// POST /api/git/checkout — Switch to a branch. Body: { "branch": "..." }
pub fn handle_git_checkout(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch {
    _ => return git_error_resp("Request body is required")
  }
  let branch = match body {
    { "branch": String(b), .. } => b
    _ => return git_error_resp("Missing 'branch' field in request body")
  }
  if branch.is_empty() {
    return git_error_resp("Branch name cannot be empty")
  }
  let args = "checkout " + git_shell_escape(branch)
  let output = git_run(args)
  if git_output_is_error(output) {
    return git_error_resp(output.trim().to_owned())
  }
  git_ok_resp(output.trim().to_owned())
}
