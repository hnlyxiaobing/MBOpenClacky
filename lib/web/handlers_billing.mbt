///| Billing usage tracking REST API handlers.
/// Provides local usage statistics and plan selection (no license validation).

// ── Helpers ──────────────────────────────────────────────────────

///|
/// Resolve the billing state directory for persisting activation info.
fn billing_state_dir() -> String {
  match @utils.config_dir() {
    Some(d) => d
    None =>
      match @utils.home_dir() {
        Some(home) =>
          @path.Path(home).join(@path.Path(".mbopenclacky/billing")).to_string()
        None => ".mbopenclacky/billing"
      }
  }
}

///|
/// Path to the billing state JSON file.
fn billing_state_file() -> String {
  @path.Path::join(billing_state_dir(), @path.Path("state.json")).to_string()
}

///|

///|
/// Load persisted billing state.
/// Returns (active, plan, expires_at).
fn load_billing_state() -> (Bool, String, String?) {
  let file_path = billing_state_file()
  let content = @fs.read_file_to_string(file_path) catch { _ => "" }
  if content.is_empty() {
    return (false, "community", None)
  }
  let json_val : Json = @json.parse(content) catch {
    _ => return (false, "community", None)
  }
  match json_val {
    Object(obj) => {
      let active = match obj.get("active") {
        Some(v) =>
          match v.stringify() {
            "true" => true
            _ => false
          }
        None => false
      }
      let plan = match obj.get("plan") {
        Some(String(s)) => s
        _ => "community"
      }
      let expires_at : String? = match obj.get("expires_at") {
        Some(String(s)) => Some(s)
        _ => None
      }
      (active, plan, expires_at)
    }
    _ => (false, "community", None)
  }
}

///|

///|
/// Save billing state (plan selection) to disk.
fn save_billing_state(
  active : Bool,
  plan : String,
  expires_at : String?,
) -> Unit {
  let file_path = billing_state_file()
  let expires_json : Json = match expires_at {
    Some(s) => s.to_json()
    None => Json::null()
  }
  let state : Map[String, Json] = {
    let m : Map[String, Json] = {}
    m.set("active", active.to_json())
    m.set("plan", plan.to_json())
    m.set("expires_at", expires_json)
    m.set("updated_at", @async.now().to_string().to_json())
    m
  }
  // Ensure directory exists
  let dir = billing_state_dir()
  if !@fs.path_exists(dir) {
    @fs.create_dir(dir) catch {
      _ => ()
    }
  }
  @fs.write_string_to_file(file_path, Json::object(state).stringify()) catch {
    _ => ()
  }
}

///|
/// Build feature list based on plan name.
fn features_for_plan(plan : String) -> Json {
  match plan {
    "pro" =>
      [
        "basic_agent".to_json(),
        "tools".to_json(),
        "mcp".to_json(),
        "skills".to_json(),
        "multi_model".to_json(),
      ].to_json()
    "yearly" | "monthly" =>
      [
        "basic_agent".to_json(),
        "tools".to_json(),
        "mcp".to_json(),
        "skills".to_json(),
      ].to_json()
    _ => ["basic_agent".to_json(), "tools".to_json()].to_json()
  }
}

// ── Billing Handlers ──────────────────────────────────────────────

///|
/// GET /api/billing/status — Get current license/billing status.
pub fn handle_billing_status(request : HttpRequest) -> HttpResponse {
  ignore(request)
  // Query billing store for current month summary
  let store = @billing.BillingStore::default()
  let summary = store.summary(@billing.Month)
  // Load persisted activation state
  let (active, plan, expires_at) = load_billing_state()
  let expires_json : Json = match expires_at {
    Some(s) => s.to_json()
    None => Json::null()
  }
  let body : Map[String, Json] = {
    let m : Map[String, Json] = {}
    m.set("active", active.to_json())
    m.set("plan", plan.to_json())
    m.set("expires_at", expires_json)
    m.set("features", features_for_plan(plan))
    m.set("current_month_cost", summary.total_cost.to_json())
    m.set("current_month_requests", summary.record_count.to_json())
    m
  }
  HttpResponse::ok(Json::object(body).stringify())
}

///|

///|
/// POST /api/billing/activate — Switch billing plan locally.
/// Expected body: {"plan": "monthly|yearly|pro"}
/// No license key validation; purely local plan selection.
pub fn handle_billing_activate(request : HttpRequest) -> HttpResponse {
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  let body_json : Json = @json.parse(request.body) catch {
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  // Extract plan from request
  let plan = match body_json {
    Object(obj) =>
      match obj.get("plan") {
        Some(String(s)) => s
        _ => "monthly"
      }
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  // Validate plan selection
  let valid_plan = match plan {
    "monthly" | "yearly" | "pro" => plan
    _ =>
      return HttpResponse::bad_request(
        "Invalid plan. Choose: monthly, yearly, or pro",
      )
  }
  // Compute expiry based on plan type
  let now_ms = @async.now()
  let expires_at : String = match valid_plan {
    "monthly" => {
      let expires_ms = now_ms + 2_592_000_000L // ~30 days
      billing_ms_to_datetime(expires_ms)
    }
    "yearly" | "pro" => {
      let expires_ms = now_ms + 31_536_000_000L // ~365 days
      billing_ms_to_datetime(expires_ms)
    }
    _ => ""
  }
  // Persist plan selection locally
  save_billing_state(true, valid_plan, Some(expires_at))
  // Return success response
  let resp : Map[String, Json] = {
    let m : Map[String, Json] = {}
    m.set("active", true.to_json())
    m.set("plan", valid_plan.to_json())
    m.set("expires_at", expires_at.to_json())
    m.set("message", "Plan activated successfully".to_json())
    m
  }
  HttpResponse::ok(Json::object(resp).stringify())
}

///|
/// GET /api/billing/usage — Get usage statistics for billing.
/// Returns total tokens, by_model breakdown (object), and by_day breakdown (object).
pub fn handle_billing_usage(request : HttpRequest) -> HttpResponse {
  ignore(request)
  // Aggregate token usage via BillingStore
  let store = @billing.BillingStore::default()
  let summary = store.summary(@billing.Month)
  // Build by_model as object: { "model_name": { tokens, cost, ... } }
  let by_model_map : Map[String, Json] = {}
  summary.by_model.each(fn(model, ms) {
    let tokens = ms.prompt_tokens + ms.completion_tokens
    let entry : Map[String, Json] = {
      let m : Map[String, Json] = {}
      m.set("tokens", tokens.to_json())
      m.set("cost", ms.cost.to_json())
      m.set("prompt_tokens", ms.prompt_tokens.to_json())
      m.set("completion_tokens", ms.completion_tokens.to_json())
      m.set("requests", ms.requests.to_json())
      m
    }
    by_model_map.set(model, Json::object(entry))
  })
  // Build by_day from daily breakdown: { "YYYY-MM-DD": { tokens, cost, requests } }
  let daily = store.daily_breakdown(days=30)
  let by_day_map : Map[String, Json] = {}
  daily.each(fn(ds) {
    if ds.total_tokens > 0 || ds.request_count > 0 {
      let entry : Map[String, Json] = {
        let m : Map[String, Json] = {}
        m.set("tokens", ds.total_tokens.to_json())
        m.set("cost", ds.total_cost.to_json())
        m.set("requests", ds.request_count.to_json())
        m
      }
      by_day_map.set(ds.date, Json::object(entry))
    }
  })
  let total_tokens = summary.total_prompt_tokens +
    summary.total_completion_tokens
  let body : Map[String, Json] = {
    let m : Map[String, Json] = {}
    m.set("period", "current_month".to_json())
    m.set("total_tokens", total_tokens.to_json())
    m.set("total_requests", summary.record_count.to_json())
    m.set("total_cost_usd", summary.total_cost.to_json())
    m.set("by_model", Json::object(by_model_map))
    m.set("by_day", Json::object(by_day_map))
    m
  }
  HttpResponse::ok(Json::object(body).stringify())
}

// ── Internal Helpers ──────────────────────────────────────────────

///|
/// Convert milliseconds to a datetime string "YYYY-MM-DDTHH:MM:SS" (simplified).
fn billing_ms_to_datetime(ms : Int64) -> String {
  // Simplified: compute approximate date from epoch milliseconds
  let total_seconds = ms / 1000L
  let days = (total_seconds / 86400L).to_int()
  // Approximate year/month/day from days since epoch (1970-01-01)
  let mut year = 1970
  let mut remaining = days
  while remaining >= (if billing_is_leap(year) { 366 } else { 365 }) {
    let days_in_year = if billing_is_leap(year) { 366 } else { 365 }
    remaining = remaining - days_in_year
    year = year + 1
  }
  let month_days = if billing_is_leap(year) {
    [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  } else {
    [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  }
  let mut month = 1
  for md in month_days {
    if remaining < md {
      break
    }
    remaining = remaining - md
    month = month + 1
  }
  let day = remaining + 1
  // Time portion
  let day_seconds = (total_seconds % 86400L).to_int()
  let hours = day_seconds / 3600
  let minutes = day_seconds % 3600 / 60
  let seconds = day_seconds % 60
  // Format as ISO string
  billing_pad(year, 4) +
  "-" +
  billing_pad(month, 2) +
  "-" +
  billing_pad(day, 2) +
  "T" +
  billing_pad(hours, 2) +
  ":" +
  billing_pad(minutes, 2) +
  ":" +
  billing_pad(seconds, 2)
}

///|
fn billing_is_leap(year : Int) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
/// GET /api/billing/export — Export usage data as CSV.
pub fn handle_billing_export(request : HttpRequest) -> HttpResponse {
  ignore(request)
  let store = @billing.BillingStore::default()
  let records = store.query(limit=1000)
  // Build CSV header + rows
  let mut csv = "id,session_id,timestamp,model,prompt_tokens,completion_tokens,cache_read_tokens,cache_write_tokens,cost_usd,cost_source\n"
  for r in records {
    csv = csv +
      r.id +
      "," +
      r.session_id +
      "," +
      r.timestamp.to_string() +
      "," +
      r.model +
      "," +
      r.prompt_tokens.to_string() +
      "," +
      r.completion_tokens.to_string() +
      "," +
      r.cache_read_tokens.to_string() +
      "," +
      r.cache_write_tokens.to_string() +
      "," +
      r.cost_usd.to_string() +
      "," +
      r.cost_source +
      "\n"
  }
  {
    status: 200,
    body: csv,
    content_type: "text/csv",
    headers: [
      ("Content-Disposition", "attachment; filename=billing_export.csv"),
    ],
  }
}

///|
fn billing_pad(n : Int, width : Int) -> String {
  let s = n.to_string()
  if s.length() >= width {
    s
  } else {
    let mut result = ""
    let mut i = 0
    while i < width - s.length() {
      result = result + "0"
      i = i + 1
    }
    result + s
  }
}
