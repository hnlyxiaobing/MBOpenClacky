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
  let current = StringBuilder()
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

// ── Session-scoped Git Helpers ─────────────────────────────────────

///|
/// Resolve the working directory for a session.
/// Returns None when the session does not exist — callers must answer 404
/// rather than silently falling back to the server's own repository.
fn session_working_dir(
  server_ref : Ref[WebServer],
  session_id : String,
) -> String? {
  match @agent.load_session(session_id) {
    Some(data) =>
      Some(if data.working_dir.is_empty() { "." } else { data.working_dir })
    None =>
      match server_ref.val.active_agents.get(session_id) {
        Some(agent) => {
          let wd = agent.to_session_data().working_dir
          Some(if wd.is_empty() { "." } else { wd })
        }
        None => None
      }
  }
}

///|
/// Check if a directory is a git repository.
async fn is_git_repo(dir : String) -> Bool {
  @fs.path_exists(dir + "/.git") ||
  ({
    let out = git_run_in_dir(dir, ["rev-parse", "--is-inside-work-tree"])
    out.trim().to_owned() == "true"
  })
}

///|
/// Build a {repo:false} response for non-git directories.
fn git_no_repo_response() -> @core.HttpResponse {
  @core.HttpResponse::ok().json_value(Json::object({ "repo": false.to_json() }))
}

///|
/// 404 response for an unknown session id in session-scoped git endpoints.
fn git_session_not_found() -> @core.HttpResponse {
  @core.HttpResponse::not_found().json_value(
    Json::object({ "error": "Session not found".to_json() }),
  )
}

// ── Session-scoped Git Handlers ────────────────────────────────────

///|
/// GET /api/sessions/:id/git/status — Session-scoped git status.
pub async fn handle_session_git_status(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let session_id = match event.param("id") {
    Some(v) => v.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing session id".to_json() }),
      )
  }
  let dir = match session_working_dir(server_ref, session_id) {
    Some(d) => d
    None => return git_session_not_found()
  }
  if !is_git_repo(dir) {
    return git_no_repo_response()
  }
  let porcelain = git_run_in_dir(dir, ["status", "--porcelain"])
  let branch_out = git_run_in_dir(dir, ["branch", "-vv"])
  let log_out = git_run_in_dir(dir, ["log", "--oneline", "-1"])
  let time_out = git_run_in_dir(dir, ["log", "-1", "--format=%ci"])
  let status = @server.build_git_status(
    porcelain,
    branch_out,
    log_out,
    commit_time=time_out.trim().to_owned(),
  )
  let files = parse_git_files(porcelain)
  @core.HttpResponse::ok().json_value(
    Json::object({
      "repo": true.to_json(),
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
/// GET /api/sessions/:id/git/diff — Session-scoped git diff.
pub async fn handle_session_git_diff(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let session_id = match event.param("id") {
    Some(v) => v.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing session id".to_json() }),
      )
  }
  let dir = match session_working_dir(server_ref, session_id) {
    Some(d) => d
    None => return git_session_not_found()
  }
  if !is_git_repo(dir) {
    return git_no_repo_response()
  }
  let file = event.req.get_query("file").unwrap_or("")
  let args = if file.is_empty() {
    ["diff", "HEAD"]
  } else {
    ["diff", "HEAD", "--", file]
  }
  let output = git_run_in_dir(dir, args)
  @core.HttpResponse::ok().json_value(
    Json::object({ "repo": true.to_json(), "diff": output.to_json() }),
  )
}

///|
/// GET /api/sessions/:id/git/log — Session-scoped git log.
pub async fn handle_session_git_log(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let session_id = match event.param("id") {
    Some(v) => v.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing session id".to_json() }),
      )
  }
  let dir = match session_working_dir(server_ref, session_id) {
    Some(d) => d
    None => return git_session_not_found()
  }
  if !is_git_repo(dir) {
    return git_no_repo_response()
  }
  let output = git_run_in_dir(dir, ["log", "--oneline", "-50"])
  let lines = git_split_lines(output)
  let entries : Array[Json] = []
  for line in lines {
    let trimmed = line.trim().to_owned()
    if trimmed.length() > 8 {
      let hash = trimmed[0:7].to_owned()
      let message = trimmed[8:].to_owned()
      entries.push(
        Json::object({ "hash": hash.to_json(), "message": message.to_json() }),
      )
    }
  }
  @core.HttpResponse::ok().json_value(
    Json::object({ "repo": true.to_json(), "log": Json::array(entries) }),
  )
}

///|
/// GET /api/sessions/:id/git/branches — Session-scoped branch list.
pub async fn handle_session_git_branches(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let session_id = match event.param("id") {
    Some(v) => v.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing session id".to_json() }),
      )
  }
  let dir = match session_working_dir(server_ref, session_id) {
    Some(d) => d
    None => return git_session_not_found()
  }
  if !is_git_repo(dir) {
    return git_no_repo_response()
  }
  let output = git_run_in_dir(dir, ["branch"])
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
      "repo": true.to_json(),
      "branches": Json::array(branches),
      "current": current.to_json(),
    }),
  )
}

///|
/// POST /api/sessions/:id/git/commit — Session-scoped git commit.
pub async fn handle_session_git_commit(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let session_id = match event.param("id") {
    Some(v) => v.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing session id".to_json() }),
      )
  }
  let dir = match session_working_dir(server_ref, session_id) {
    Some(d) => d
    None => return git_session_not_found()
  }
  if !is_git_repo(dir) {
    return git_no_repo_response()
  }
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
  let output = git_run_in_dir(dir, ["commit", "-m", message])
  if git_output_is_error(output) {
    return git_error_resp(output.trim().to_owned())
  }
  git_ok_resp(output.trim().to_owned())
}
