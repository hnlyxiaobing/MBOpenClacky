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
    let m : Map[String, Json] = Map([])
    m.set("active", active.to_json())
    m.set("plan", plan.to_json())
    m.set("expires_at", expires_json)
    m.set("updated_at", @env.now().to_string().to_json())
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
    let m : Map[String, Json] = Map([])
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
  let now_ms = @env.now().reinterpret_as_int64()
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
    let m : Map[String, Json] = Map([])
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
  let by_model_map : Map[String, Json] = Map([])
  summary.by_model.each(fn(model, ms) {
    let tokens = ms.prompt_tokens + ms.completion_tokens
    let entry : Map[String, Json] = {
      let m : Map[String, Json] = Map([])
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
  let by_day_map : Map[String, Json] = Map([])
  daily.each(fn(ds) {
    if ds.total_tokens > 0 || ds.request_count > 0 {
      let entry : Map[String, Json] = {
        let m : Map[String, Json] = Map([])
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
    let m : Map[String, Json] = Map([])
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
    body_bytes: None,
    content_type: "text/csv",
    headers: [
      ("Content-Disposition", "attachment; filename=billing_export.csv"),
    ],
  }
}

///|
/// GET /api/billing/summary — Billing summary for a time period.
/// Aligned with orig openclacky api_billing_summary: period/from/to,
/// token splits, by_model and by_day breakdowns, record_count.
/// Query params: period (day|week|month|year|all, default: month).
pub fn handle_billing_summary(request : HttpRequest) -> HttpResponse {
  let (period, period_name) = billing_parse_period(request)
  let store = @billing.BillingStore::default()
  let summary = store.summary(period)
  let now_ms = @env.now().reinterpret_as_int64()
  let from_ms = billing_period_start_ms(period, now_ms)
  // by_model: { model: { cost, prompt_tokens, completion_tokens, requests } }
  let by_model_map : Map[String, Json] = Map([])
  summary.by_model.each(fn(model, ms) {
    by_model_map.set(
      model,
      Json::object({
        "cost": ms.cost.to_json(),
        "prompt_tokens": ms.prompt_tokens.to_json(),
        "completion_tokens": ms.completion_tokens.to_json(),
        "requests": ms.requests.to_json(),
      }),
    )
  })
  // by_day: { "YYYY-MM-DD": cost } — only days with activity (orig semantics)
  let day_costs : Map[String, Double] = Map([])
  for r in store.query(from_ms~) {
    let date = billing_date_of_ms(r.timestamp)
    let cost = match day_costs.get(date) {
      Some(c) => c
      None => 0.0
    }
    day_costs.set(date, cost + r.cost_usd)
  }
  let by_day_map : Map[String, Json] = Map([])
  day_costs.each(fn(date, cost) { by_day_map.set(date, cost.to_json()) })
  // "all" period has no lower bound in orig (from: null)
  let from_json : Json = match period {
    @billing.All => Json::null()
    _ => billing_ms_to_datetime(from_ms).to_json()
  }
  let body : Map[String, Json] = {
    let m : Map[String, Json] = Map([])
    m.set("period", period_name.to_json())
    m.set("from", from_json)
    m.set("to", billing_ms_to_datetime(now_ms).to_json())
    m.set("total_cost", summary.total_cost.to_json())
    m.set(
      "total_tokens",
      (summary.total_prompt_tokens + summary.total_completion_tokens).to_json(),
    )
    m.set("prompt_tokens", summary.total_prompt_tokens.to_json())
    m.set("completion_tokens", summary.total_completion_tokens.to_json())
    m.set("cache_read_tokens", summary.total_cache_read_tokens.to_json())
    m.set("cache_write_tokens", summary.total_cache_write_tokens.to_json())
    m.set("by_model", Json::object(by_model_map))
    m.set("by_day", Json::object(by_day_map))
    m.set("record_count", summary.record_count.to_json())
    m
  }
  HttpResponse::ok(Json::object(body).stringify())
}

///|
/// GET /api/billing/daily — Daily cost breakdown.
/// Aligned with orig openclacky api_billing_daily: top-level key is `days`,
/// each entry carries full token splits; the full day range is emitted
/// (zero-fill for days without records), oldest first.
/// Query params: days (default: 30, max: 90).
pub fn handle_billing_daily(request : HttpRequest) -> HttpResponse {
  let store = @billing.BillingStore::default()
  let days = billing_parse_int_param(request, "days", 30, 90)
  let now_ms = @env.now().reinterpret_as_int64()
  let ms_per_day = 86_400_000L
  let from_ms = now_ms - days.to_int64() * ms_per_day
  // Accumulate per calendar date: (cost, tokens, prompt, completion,
  // cache_read, cache_write, requests)
  let day_map : Map[String, (Double, Int, Int, Int, Int, Int, Int)] = Map([])
  for r in store.query(from_ms~) {
    let date = billing_date_of_ms(r.timestamp)
    let (cost, tokens, prompt, completion, cache_read, cache_write, requests) = match
      day_map.get(date) {
      Some(v) => v
      None => (0.0, 0, 0, 0, 0, 0, 0)
    }
    day_map.set(
      date,
      (
        cost + r.cost_usd,
        tokens + r.prompt_tokens + r.completion_tokens,
        prompt + r.prompt_tokens,
        completion + r.completion_tokens,
        cache_read + r.cache_read_tokens,
        cache_write + r.cache_write_tokens,
        requests + 1,
      ),
    )
  }
  let items : Array[Json] = []
  for i = 0; i < days; i = i + 1 {
    let day_ms = now_ms - (days - 1 - i).to_int64() * ms_per_day
    let date = billing_date_of_ms(day_ms)
    let (cost, tokens, prompt, completion, cache_read, cache_write, requests) = match
      day_map.get(date) {
      Some(v) => v
      None => (0.0, 0, 0, 0, 0, 0, 0)
    }
    items.push(
      Json::object({
        "date": date.to_json(),
        "cost": cost.to_json(),
        "tokens": tokens.to_json(),
        "prompt_tokens": prompt.to_json(),
        "completion_tokens": completion.to_json(),
        "cache_read_tokens": cache_read.to_json(),
        "cache_write_tokens": cache_write.to_json(),
        "requests": requests.to_json(),
      }),
    )
  }
  HttpResponse::ok(Json::object({ "days": Json::array(items) }).stringify())
}

///|
/// GET /api/billing/records — Raw usage records.
/// Aligned with orig openclacky api_billing_records: full record fields
/// (incl. cache splits and cost_source), ISO timestamp, top-level count.
/// Query params: limit (default: 100, max: 500).
pub fn handle_billing_records(request : HttpRequest) -> HttpResponse {
  let store = @billing.BillingStore::default()
  let limit = billing_parse_int_param(request, "limit", 100, 500)
  let records = store.query(limit~)
  let items : Array[Json] = []
  for r in records {
    items.push(
      Json::object({
        "id": r.id.to_json(),
        "session_id": r.session_id.to_json(),
        "timestamp": billing_ms_to_datetime(r.timestamp).to_json(),
        "model": r.model.to_json(),
        "prompt_tokens": r.prompt_tokens.to_json(),
        "completion_tokens": r.completion_tokens.to_json(),
        "cache_read_tokens": r.cache_read_tokens.to_json(),
        "cache_write_tokens": r.cache_write_tokens.to_json(),
        "cost_usd": r.cost_usd.to_json(),
        "cost_source": r.cost_source.to_json(),
      }),
    )
  }
  HttpResponse::ok(
    Json::object({
      "records": Json::array(items),
      "count": items.length().to_json(),
    }).stringify(),
  )
}

///|
/// GET /api/billing/sessions — Per-session cost aggregation.
/// Aligned with orig openclacky api_billing_sessions: full token splits,
/// first/last request timestamps, distinct model list, top-level count,
/// sorted by total cost descending.
/// Query params: period (day|week|month|year|all, default: month),
/// limit (default: 50, max: 200).
pub fn handle_billing_sessions(request : HttpRequest) -> HttpResponse {
  let (period, _) = billing_parse_period(request)
  let limit = billing_parse_int_param(request, "limit", 50, 200)
  let store = @billing.BillingStore::default()
  let now_ms = @env.now().reinterpret_as_int64()
  let from_ms = billing_period_start_ms(period, now_ms)
  // Aggregate by session_id
  let session_map : Map[String, BillingSessionAgg] = Map([])
  for r in store.query(from_ms~) {
    match session_map.get(r.session_id) {
      Some(agg) => {
        agg.total_cost = agg.total_cost + r.cost_usd
        agg.prompt_tokens = agg.prompt_tokens + r.prompt_tokens
        agg.completion_tokens = agg.completion_tokens + r.completion_tokens
        agg.cache_read_tokens = agg.cache_read_tokens + r.cache_read_tokens
        agg.cache_write_tokens = agg.cache_write_tokens + r.cache_write_tokens
        agg.requests = agg.requests + 1
        if r.timestamp < agg.first_ms {
          agg.first_ms = r.timestamp
        }
        if r.timestamp > agg.last_ms {
          agg.last_ms = r.timestamp
        }
        if !agg.models.contains(r.model) {
          agg.models.push(r.model)
        }
      }
      None =>
        session_map[r.session_id] = {
          total_cost: r.cost_usd,
          prompt_tokens: r.prompt_tokens,
          completion_tokens: r.completion_tokens,
          cache_read_tokens: r.cache_read_tokens,
          cache_write_tokens: r.cache_write_tokens,
          requests: 1,
          first_ms: r.timestamp,
          last_ms: r.timestamp,
          models: [r.model],
        }
    }
  }
  // Sort by total cost descending (orig semantics), then apply limit
  let pairs : Array[(String, BillingSessionAgg)] = []
  session_map.each(fn(sid, agg) { pairs.push((sid, agg)) })
  pairs.sort_by(fn(a, b) { b.1.total_cost.compare(a.1.total_cost) })
  let items : Array[Json] = []
  for i = 0; i < pairs.length() && i < limit; i = i + 1 {
    let (sid, agg) = pairs[i]
    items.push(
      Json::object({
        "session_id": sid.to_json(),
        // NOTE: no session-name data source yet (orig reads SessionManager);
        // emit empty string per spec risk convention.
        "session_name": "".to_json(),
        "total_cost": agg.total_cost.to_json(),
        "total_tokens": (agg.prompt_tokens + agg.completion_tokens).to_json(),
        "prompt_tokens": agg.prompt_tokens.to_json(),
        "completion_tokens": agg.completion_tokens.to_json(),
        "cache_read_tokens": agg.cache_read_tokens.to_json(),
        "cache_write_tokens": agg.cache_write_tokens.to_json(),
        "requests": agg.requests.to_json(),
        "first_request": billing_ms_to_datetime(agg.first_ms).to_json(),
        "last_request": billing_ms_to_datetime(agg.last_ms).to_json(),
        "models": agg.models.map(fn(m) { m.to_json() }).to_json(),
      }),
    )
  }
  HttpResponse::ok(
    Json::object({
      "sessions": Json::array(items),
      "count": items.length().to_json(),
    }).stringify(),
  )
}

///|
/// DELETE /api/billing/clear — Clear all billing records.
pub fn handle_billing_clear(request : HttpRequest) -> HttpResponse {
  ignore(request)
  let store = @billing.BillingStore::default()
  // Clear ALL records: cleanup removes everything before the cutoff, so use
  // a far-future cutoff. Named constant instead of a bare magic number;
  // BillingStore exposes no dedicated clear-all API.
  let clear_all_before_ms = 99999999999999L
  let _ = store.cleanup(clear_all_before_ms)
  // NOTE: only usage records are cleared. The persisted plan state
  // (license/tier) is deliberately left untouched — clearing usage history
  // must not silently downgrade the user's plan.
  HttpResponse::ok(
    Json::object({
      "ok": true.to_json(),
      "message": "Billing records cleared".to_json(),
    }).stringify(),
  )
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

// ── Contract Alignment Helpers (web-ui-fix-10) ──────────────────────

///|
/// Mutable per-session aggregation accumulator for handle_billing_sessions.
priv struct BillingSessionAgg {
  mut total_cost : Double
  mut prompt_tokens : Int
  mut completion_tokens : Int
  mut cache_read_tokens : Int
  mut cache_write_tokens : Int
  mut requests : Int
  mut first_ms : Int64
  mut last_ms : Int64
  models : Array[String]
}

///|
/// Extract a query parameter value from the request path (after "?").
/// NOTE: the crescent bridge strips the query string before constructing
/// HttpRequest, so this only sees params when the path still carries them
/// (unit tests); live requests fall back to the orig defaults.
fn billing_query_param(request : HttpRequest, key : String) -> String? {
  let target = "\{key}="
  match request.path.find(target) {
    Some(idx) => {
      let start = idx + target.length()
      let chars = request.path.to_array()
      let buf = StringBuilder::new()
      let mut i = start
      while i < chars.length() {
        let c = chars[i]
        if c == '&' {
          break
        }
        buf.write_char(c)
        i = i + 1
      }
      let val = buf.to_string()
      if val.is_empty() {
        None
      } else {
        Some(val)
      }
    }
    None => None
  }
}

///|
/// Parse the `period` query param into a TimePeriod plus its orig string
/// form (day|week|month|year|all, default: month).
fn billing_parse_period(request : HttpRequest) -> (@billing.TimePeriod, String) {
  match billing_query_param(request, "period") {
    Some("day") => (@billing.Day, "day")
    Some("week") => (@billing.Week, "week")
    Some("year") => (@billing.Year, "year")
    Some("all") => (@billing.All, "all")
    _ => (@billing.Month, "month")
  }
}

///|
/// Parse an integer query param with default and upper cap (orig clamps).
fn billing_parse_int_param(
  request : HttpRequest,
  key : String,
  default : Int,
  cap : Int,
) -> Int {
  let raw = match billing_query_param(request, key) {
    Some(s) => @string.parse_int(s) catch { _ => default }
    None => default
  }
  if raw < 1 {
    default
  } else if raw > cap {
    cap
  } else {
    raw
  }
}

///|
/// Period start in milliseconds, mirroring BillingStore's period windows.
fn billing_period_start_ms(
  period : @billing.TimePeriod,
  now_ms : Int64,
) -> Int64 {
  match period {
    @billing.Day => now_ms - 86_400_000L
    @billing.Week => now_ms - 604_800_000L
    @billing.Month => now_ms - 2_592_000_000L // ~30 days
    @billing.Year => now_ms - 31_536_000_000L // ~365 days
    @billing.All => 0L
  }
}

///|
/// Calendar date "YYYY-MM-DD" for an epoch-millisecond timestamp.
fn billing_date_of_ms(ms : Int64) -> String {
  billing_ms_to_datetime(ms)[:10].to_owned()
}
