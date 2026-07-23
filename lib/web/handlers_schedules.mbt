///| Scheduled task (Cron/Scheduler) REST API handlers.
/// Provides CRUD, toggle, manual trigger, and execution history for cron schedules.

// ── Schedule State Types ──────────────────────────────────────────

///|
/// A single execution history record.
priv struct ExecutionRecord {
  schedule_name : String
  status : String // "success" or "failed"
  executed_at : String // ISO 8601 timestamp
  output : String
}

///|
/// In-memory schedule state (augments the Scheduler for API features).
priv struct ScheduleState {
  scheduler : @server.Scheduler
  messages : Map[String, String] // schedule name -> prompt/message
  executions : Array[ExecutionRecord]
  mut loaded : Bool
  mut next_id : Int
}

///|
/// Global schedule state singleton (module-level mutable).

///|
/// Initialize a fresh schedule state.
fn init_schedule_state() -> ScheduleState {
  {
    scheduler: @server.Scheduler::new({
      schedules: [],
      tasks_dir: "",
      config_path: "",
    }),
    messages: Map([("_", "")]),
    executions: [],
    loaded: false,
    next_id: 1,
  }
}

///|
/// Global schedule state singleton (module-level mutable).
let schedule_state : Ref[ScheduleState] = Ref(init_schedule_state())

// ── Persistence ───────────────────────────────────────────────────

///|
/// Path to the schedule state file.
fn schedule_file_path() -> String {
  match @utils.config_dir() {
    Some(dir) => @path.Path::join(dir, @path.Path("schedules.json")).to_string()
    None => ".mbopenclacky/schedules.json"
  }
}

///|
/// Load schedule state from disk if not already loaded.
fn ensure_schedules_loaded() -> Unit {
  if schedule_state.val.loaded {
    return
  }
  let path = schedule_file_path()
  if @fs.path_exists(path) {
    let content = @fs.read_file_to_string(path) catch { _ => return }
    let json : Json = @json.parse(content) catch { _ => return }
    match json {
      Object(obj) => {
        // Load schedules
        match obj.get("schedules") {
          Some(Array(arr)) =>
            for item in arr {
              match item {
                Object(sobj) => {
                  let name = json_str(sobj, "name")
                  let cron_expr = json_str(sobj, "cron_expression")
                  let enabled = json_bool(sobj, "enabled")
                  let message = json_str(sobj, "message")
                  if name != "" && cron_expr != "" {
                    let _ = schedule_state.val.scheduler.add_schedule(
                      name, name, cron_expr, enabled,
                    )
                    if message != "" {
                      schedule_state.val.messages.set(name, message)
                    }
                  }
                }
                _ => ()
              }
            }
          _ => ()
        }
        // Load execution history
        match obj.get("executions") {
          Some(Array(arr)) =>
            for item in arr {
              match item {
                Object(eobj) =>
                  schedule_state.val.executions.push({
                    schedule_name: json_str(eobj, "schedule_name"),
                    status: json_str(eobj, "status"),
                    executed_at: json_str(eobj, "executed_at"),
                    output: json_str(eobj, "output"),
                  })
                _ => ()
              }
            }
          _ => ()
        }
        // Load next_id counter
        match obj.get("next_id") {
          Some(Number(n, ..)) => schedule_state.val.next_id = n.to_int()
          _ => ()
        }
      }
      _ => ()
    }
  }
  schedule_state.val.loaded = true
}

///|
/// Persist current schedule state to disk.
fn save_schedule_state() -> Unit {
  let path = schedule_file_path()
  let schedules_json : Array[Json] = []
  for s in schedule_state.val.scheduler.list_schedules() {
    let msg = schedule_state.val.messages.get(s.name).unwrap_or("")
    schedules_json.push(schedule_to_api_json(s, msg))
  }
  let execs_json : Array[Json] = []
  for e in schedule_state.val.executions {
    execs_json.push(execution_to_json(e))
  }
  let data = Json::object({
    "schedules": schedules_json.to_json(),
    "executions": execs_json.to_json(),
    "next_id": schedule_state.val.next_id.to_json(),
  })
  @fs.write_string_to_file(path, data.stringify()) catch {
    _ => ()
  }
}

// ── JSON Helpers ──────────────────────────────────────────────────

///|
/// Extract a string from a JSON object field.
fn json_str(obj : Map[String, Json], key : String) -> String {
  match obj.get(key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
/// Extract a boolean from a JSON object field.
fn json_bool(obj : Map[String, Json], key : String) -> Bool {
  match obj.get(key) {
    Some(True) => true
    Some(False) => false
    _ => true
  }
}

///|
/// Convert a Schedule to the JSON format expected by the frontend.
/// Frontend expects: {id, name, cron_expression, enabled, next_execution, message}
fn schedule_to_api_json(s : @server.Schedule, message : String) -> Json {
  let next_exec = match s.next_run_at {
    Some(ts) => ts.to_string()
    None => ""
  }
  Json::object({
    "id": s.name.to_json(),
    "schedule_id": s.name.to_json(),
    "name": s.name.to_json(),
    "cron_expression": s.cron.raw.to_json(),
    "enabled": s.enabled.to_json(),
    "next_execution": next_exec.to_json(),
    "message": message.to_json(),
    "run_count": s.run_count.to_json(),
  })
}

///|
/// Convert an ExecutionRecord to JSON.
fn execution_to_json(e : ExecutionRecord) -> Json {
  Json::object({
    "status": e.status.to_json(),
    "executed_at": e.executed_at.to_json(),
    "timestamp": e.executed_at.to_json(),
    "output": e.output.to_json(),
  })
}

///|
/// Format an Int64 millisecond timestamp as ISO-8601 UTC string.
fn format_timestamp_ms(ms : Int64) -> String {
  let total_secs = ms / 1000L
  let millis = ms % 1000L
  let secs = total_secs % 60L
  let total_mins = total_secs / 60L
  let mins = total_mins % 60L
  let total_hours = total_mins / 60L
  let hours = total_hours % 24L
  let total_days = total_hours / 24L
  // Simplified date calculation from Unix epoch days
  let (y, m, d) = days_to_ymd(total_days.to_int())
  let ys = pad_int(y, 4)
  let ms_str = pad_int(m, 2)
  let ds = pad_int(d, 2)
  let hs = pad_int(hours.to_int(), 2)
  let mis = pad_int(mins.to_int(), 2)
  let ss = pad_int(secs.to_int(), 2)
  let mss = pad_int(millis.to_int(), 3)
  "\{ys}-\{ms_str}-\{ds}T\{hs}:\{mis}:\{ss}.\{mss}Z"
}

///|
/// Convert days since Unix epoch to (year, month, day).
fn days_to_ymd(days : Int) -> (Int, Int, Int) {
  // Algorithm from http://howardhinnant.github.io/date_algorithms.html
  let z = days + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  let year = if m <= 2 { y + 1 } else { y }
  (year, m, d)
}

///|
/// Pad an integer to the given width with leading zeros.
fn pad_int(n : Int, width : Int) -> String {
  let s = if n < 0 { "0" } else { n.to_string() }
  let mut result = s
  while result.length() < width {
    result = "0" + result
  }
  result
}

// ── Schedule Handlers ─────────────────────────────────────────────

///|
/// GET /api/schedules — List all scheduled tasks.
pub fn handle_schedules_list(request : HttpRequest) -> HttpResponse {
  ignore(request)
  ensure_schedules_loaded()

  let schedules_json : Array[Json] = []
  for s in schedule_state.val.scheduler.list_schedules() {
    let msg = schedule_state.val.messages.get(s.name).unwrap_or("")
    schedules_json.push(schedule_to_api_json(s, msg))
  }

  HttpResponse::ok(schedules_json.to_json().stringify())
}

///|
/// POST /api/schedules — Create a new scheduled task.
pub fn handle_schedules_create(request : HttpRequest) -> HttpResponse {
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  let body_json : Json = @json.parse(request.body) catch {
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  let (name, cron_expr, enabled, message) = match body_json {
    Object(obj) => {
      let n = json_str(obj, "name")
      let c = json_str(obj, "cron_expression")
      let e = json_bool(obj, "enabled")
      let m = json_str(obj, "message")
      (n, c, e, m)
    }
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }

  if name == "" {
    return HttpResponse::bad_request("Name is required")
  }
  if cron_expr == "" {
    return HttpResponse::bad_request("Cron expression is required")
  }

  // Validate cron expression
  match @server.CronExpression::parse(cron_expr) {
    Ok(_) => ()
    Err(e) => return HttpResponse::bad_request("Invalid cron expression: " + e)
  }

  ensure_schedules_loaded()

  // Generate unique ID
  let id = name
  let _id_check = schedule_state.val.next_id
  schedule_state.val.next_id = schedule_state.val.next_id + 1

  // Add to scheduler
  match
    schedule_state.val.scheduler.add_schedule(id, name, cron_expr, enabled) {
    Ok(_) => ()
    Err(e) => {
      let @server.SchedulerError(msg) = e
      return HttpResponse::bad_request(msg)
    }
  }

  // Store message
  if message != "" {
    schedule_state.val.messages.set(id, message)
  }

  save_schedule_state()

  let run_count : Int = 0
  // Build response matching frontend expectations
  let resp = Json::object({
    "id": id.to_json(),
    "schedule_id": id.to_json(),
    "name": name.to_json(),
    "cron_expression": cron_expr.to_json(),
    "enabled": enabled.to_json(),
    "next_execution": "".to_json(),
    "message": message.to_json(),
    "run_count": run_count.to_json(),
  })
  HttpResponse::created(resp.stringify())
}

///|
/// PUT /api/schedules/:id — Update an existing scheduled task.
pub fn handle_schedules_update(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  let body_json : Json = @json.parse(request.body) catch {
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }

  ensure_schedules_loaded()

  let (name, cron_expr, enabled, message) = match body_json {
    Object(obj) => {
      let n = json_str(obj, "name")
      let c = json_str(obj, "cron_expression")
      let e = match obj.get("enabled") {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
      let m = json_str(obj, "message")
      (n, c, e, m)
    }
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }

  // Validate cron expression if provided
  if cron_expr != "" {
    match @server.CronExpression::parse(cron_expr) {
      Ok(_) => ()
      Err(e) =>
        return HttpResponse::bad_request("Invalid cron expression: " + e)
    }
  }

  // Update enabled state via scheduler
  match schedule_state.val.scheduler.update_schedule(id, None, enabled) {
    Ok(_) => ()
    Err(e) => {
      let @server.SchedulerError(msg) = e
      return HttpResponse::not_found(msg)
    }
  }

  // Update message
  if message != "" {
    schedule_state.val.messages.set(id, message)
  } else if name != "" && name != id {
    // Name changed: migrate message
    match schedule_state.val.messages.get(id) {
      Some(old_msg) => {
        schedule_state.val.messages.remove(id)
        schedule_state.val.messages.set(name, old_msg)
      }
      None => ()
    }
  }

  save_schedule_state()

  // Build response
  let sched = schedule_state.val.scheduler.get_schedule(id)
  let msg = schedule_state.val.messages.get(id).unwrap_or(message)
  let resp = match sched {
    Some(s) => schedule_to_api_json(s, msg)
    None =>
      Json::object({
        "id": id.to_json(),
        "name": (if name != "" { name } else { id }).to_json(),
        "cron_expression": cron_expr.to_json(),
        "enabled": enabled.unwrap_or(true).to_json(),
        "message": msg.to_json(),
      })
  }
  HttpResponse::ok(resp.stringify())
}

///|
/// DELETE /api/schedules/:id — Delete a scheduled task.
pub fn handle_schedules_delete(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }

  ensure_schedules_loaded()

  match schedule_state.val.scheduler.remove_schedule(id) {
    Ok(_) => ()
    Err(e) => {
      let @server.SchedulerError(msg) = e
      return HttpResponse::not_found(msg)
    }
  }

  // Clean up associated message
  schedule_state.val.messages.remove(id)

  save_schedule_state()
  HttpResponse::no_content()
}

///|
/// POST /api/schedules/:id/trigger — Manually trigger a scheduled task.
pub fn handle_schedules_trigger(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }

  ensure_schedules_loaded()

  // Verify schedule exists
  match schedule_state.val.scheduler.get_schedule(id) {
    Some(schedule) => {
      // Record execution
      let now = @env.now().reinterpret_as_int64()
      let ts_str = format_timestamp_ms(now)
      schedule_state.val.executions.push({
        schedule_name: id,
        status: "success",
        executed_at: ts_str,
        output: "Manually triggered",
      })
      // Update run count
      schedule.run_count = schedule.run_count + 1
      schedule.last_run_at = Some(now.to_int())
      save_schedule_state()

      let msg = schedule_state.val.messages.get(id).unwrap_or("")
      let body = Json::object({
        "id": id.to_json(),
        "triggered": true.to_json(),
        "message": ("Schedule '" + id + "' triggered manually").to_json(),
        "prompt": msg.to_json(),
      })
      HttpResponse::ok(body.stringify())
    }
    None => HttpResponse::not_found("Schedule not found: " + id)
  }
}

///|
/// GET /api/schedules/:id/history — Get execution history for a task.
pub fn handle_schedules_history(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }

  ensure_schedules_loaded()

  // Filter executions for this schedule
  let filtered : Array[Json] = []
  for e in schedule_state.val.executions {
    if e.schedule_name == id {
      filtered.push(execution_to_json(e))
    }
  }

  HttpResponse::ok(filtered.to_json().stringify())
}
