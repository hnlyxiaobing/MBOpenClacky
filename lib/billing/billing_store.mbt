///| JSONL-based billing record storage and query engine.

///| Reference: openclacky/lib/clacky/billing/billing_store.rb

// ── Supporting Types ────────────────────────────────────────────

///|
/// Time period for billing summaries.
pub(all) enum TimePeriod {
  Day
  Week
  Month
  Year
  All
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend TimePeriod with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TimePeriod with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend TimePeriod with Eq::{not_equal, equal}

///|
pub extend TimePeriod with ToJson::{to_json}

///|
/// Aggregated billing summary for a time period.
pub(all) struct Summary {
  period : TimePeriod
  total_cost : Double
  total_prompt_tokens : Int
  total_completion_tokens : Int
  total_cache_read_tokens : Int
  total_cache_write_tokens : Int
  by_model : Map[String, ModelSummary]
  record_count : Int
} derive(Eq, Debug)

///|
pub extend Summary with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Summary with Eq::{not_equal, equal}

///|
/// Per-model billing summary.
pub(all) struct ModelSummary {
  cost : Double
  prompt_tokens : Int
  completion_tokens : Int
  requests : Int
} derive(Eq, Debug)

///|
pub extend ModelSummary with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ModelSummary with Eq::{not_equal, equal}

///|
/// Per-day billing summary.
pub(all) struct DaySummary {
  date : String // "YYYY-MM-DD"
  total_cost : Double
  total_tokens : Int
  request_count : Int
} derive(Eq, Debug)

///|
pub extend DaySummary with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DaySummary with Eq::{not_equal, equal}

// ── BillingStore ────────────────────────────────────────────────

///|
/// JSONL-based billing record storage.
/// Files stored at: {billing_dir}/YYYY-MM.jsonl
pub(all) struct BillingStore {
  billing_dir : String
} derive(Eq, Debug)

///|
pub extend BillingStore with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BillingStore with Eq::{not_equal, equal}

///|
/// Create a new BillingStore with given directory.
pub fn BillingStore::new(billing_dir : String) -> BillingStore {
  { billing_dir, }
}

///|
/// Create a BillingStore with default directory (~/.mbopenclacky/billing/).
/// The CLACKY_BILLING_DIR env var overrides the default location
/// (Ruby BillingStore#initialize precedence, spec 21 decision 7).
pub fn BillingStore::default() -> BillingStore {
  match @env.get_env_var("CLACKY_BILLING_DIR") {
    Some(dir) if !dir.is_empty() => return { billing_dir: dir }
    _ => ()
  }
  let dir = match @env.get_env_var("USERPROFILE") {
    Some(home) if !home.is_empty() =>
      @path.Path::join(home, @path.Path(".mbopenclacky/billing")).to_string()
    _ =>
      match @env.get_env_var("HOME") {
        Some(home) if !home.is_empty() =>
          @path.Path::join(home, @path.Path(".mbopenclacky/billing")).to_string()
        _ => ".mbopenclacky/billing"
      }
  }
  { billing_dir: dir }
}

///|
/// Append a billing record to the month JSONL file (`YYYY-MM.jsonl`,
/// local timezone) matching the record's timestamp.
/// Returns the record id on success.
pub fn BillingStore::append(
  self : BillingStore,
  record : BillingRecord,
) -> Result[String, String] {
  // Ensure billing directory exists
  ensure_billing_dir(self.billing_dir)
  // Ruby: records land in the current month file (Time.now.strftime('%Y-%m'));
  // MB keys off the record timestamp so explicit-timestamp appends stay
  // consistent with the file they belong to.
  let file_path = @path.Path::join(
    self.billing_dir,
    @path.Path(month_file_name(record.timestamp)),
  ).to_string()
  // Serialize record to JSON line
  let json_line = record.to_json().stringify()
  // Append to file
  append_line(file_path, json_line) catch {
    _ => return Err("Failed to append billing record")
  }
  Ok(record.id)
}

///|
/// Query billing records with optional filters.
/// Returns matching records sorted by timestamp descending.
pub fn BillingStore::query(
  self : BillingStore,
  from_ms? : Int64 = 0L,
  to_ms? : Int64 = 0L,
  model? : String = "",
  session_id? : String = "",
  limit? : Int = 0,
) -> Array[BillingRecord] {
  let all_records = load_all_records(self.billing_dir)
  let filtered = filter_records(
    all_records,
    from_ms~,
    to_ms~,
    model~,
    session_id~,
  )
  // Sort by timestamp descending
  let sorted = filtered
  sorted.sort_by(fn(a, b) { b.timestamp.compare(a.timestamp) })
  // Apply limit
  if limit > 0 && sorted.length() > limit {
    sorted[:limit].to_owned()
  } else {
    sorted
  }
}

///|
/// Compute aggregated summary for a time period.
pub fn BillingStore::summary(
  self : BillingStore,
  period : TimePeriod,
  model? : String = "",
) -> Summary {
  let period_start_ms = get_period_start_ms(period)
  let records = self.query(from_ms=period_start_ms, model~)
  aggregate_summary(records, period)
}

///|
/// Get daily cost breakdown for the last N days (Ruby default: 30).
/// Groups records by local calendar date; zero-fills empty days and
/// returns oldest first.
pub fn BillingStore::daily_breakdown(
  self : BillingStore,
  days? : Int = 30,
) -> Array[DaySummary] {
  let ms_per_day = 86_400_000L
  let now_ms = current_time_ms()
  let records = self.query()
  // Group by local calendar date
  let day_map : Map[String, (Double, Int, Int)] = Map([])
  for record in records {
    let date = ms_to_local_date_string(record.timestamp)
    let (cost, tokens, count) = match day_map.get(date) {
      Some(v) => v
      None => (0.0, 0, 0)
    }
    day_map.set(
      date,
      (cost + record.cost_usd, tokens + record.total_tokens(), count + 1),
    )
  }
  // Walk the calendar range oldest first, zero-filling empty days
  let result : Array[DaySummary] = []
  for i = days - 1; i >= 0; i = i - 1 {
    let day_ms = now_ms - i.to_int64() * ms_per_day
    let date = ms_to_local_date_string(day_ms)
    let (cost, tokens, count) = match day_map.get(date) {
      Some(v) => v
      None => (0.0, 0, 0)
    }
    result.push({
      date,
      total_cost: cost,
      total_tokens: tokens,
      request_count: count,
    })
  }
  result
}

// ── Session summary & clear (Ruby parity, spec 21 decision 7) ───

///|
/// Per-session billing aggregate returned by `session_summary`.
pub(all) struct SessionSummary {
  session_id : String // "_deleted_" for the merged unnamed row
  session_name : String?
  is_deleted : Bool
  total_cost : Double
  total_tokens : Int
  prompt_tokens : Int
  completion_tokens : Int
  requests : Int
} derive(Eq, Debug)

///|
pub extend SessionSummary with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SessionSummary with Eq::{not_equal, equal}

///|
/// Scope selector for `BillingStore::clear`.
pub(all) enum ClearScope {
  ClearToday
  ClearAll
} derive(Eq, Debug)

///|
pub extend ClearScope with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ClearScope with Eq::{not_equal, equal}

///|
/// Aggregate billing records per session for a period, mirroring Ruby
/// BillingStore#session_summary: sessions present in `session_names`
/// become named rows; sessions without a known name are merged into a
/// single `_deleted_` row. Result is sorted by total cost descending
/// and capped at `limit` (default 50).
pub fn BillingStore::session_summary(
  self : BillingStore,
  period : TimePeriod,
  model? : String = "",
  limit? : Int = 50,
  session_names? : Map[String, String] = Map([]),
) -> Array[SessionSummary] {
  let period_start_ms = get_period_start_ms(period)
  let records = self.query(from_ms=period_start_ms, model~)
  // Accumulator: (cost, tokens, prompt, completion, requests)
  let named : Map[String, (Double, Int, Int, Int, Int)] = Map([])
  let mut deleted : (Double, Int, Int, Int, Int) = (0.0, 0, 0, 0, 0)
  for r in records {
    let entry = (
      r.cost_usd,
      r.total_tokens(),
      r.prompt_tokens,
      r.completion_tokens,
      1,
    )
    match session_names.get(r.session_id) {
      Some(_) => {
        let acc = match named.get(r.session_id) {
          Some(v) => v
          None => (0.0, 0, 0, 0, 0)
        }
        named.set(r.session_id, merge_session_acc(acc, entry))
      }
      None => deleted = merge_session_acc(deleted, entry)
    }
  }
  let result : Array[SessionSummary] = []
  if deleted.4 > 0 {
    let (cost, tokens, prompt, completion, requests) = deleted
    result.push({
      session_id: "_deleted_",
      session_name: None,
      is_deleted: true,
      total_cost: cost,
      total_tokens: tokens,
      prompt_tokens: prompt,
      completion_tokens: completion,
      requests,
    })
  }
  named.each(fn(session_id, acc) {
    let (cost, tokens, prompt, completion, requests) = acc
    result.push({
      session_id,
      session_name: session_names.get(session_id),
      is_deleted: false,
      total_cost: cost,
      total_tokens: tokens,
      prompt_tokens: prompt,
      completion_tokens: completion,
      requests,
    })
  })
  result.sort_by(fn(a, b) { b.total_cost.compare(a.total_cost) })
  if limit > 0 && result.length() > limit {
    result[:limit].to_owned()
  } else {
    result
  }
}

///|
/// Merge two (cost, tokens, prompt, completion, requests) accumulators.
fn merge_session_acc(
  a : (Double, Int, Int, Int, Int),
  b : (Double, Int, Int, Int, Int),
) -> (Double, Int, Int, Int, Int) {
  (a.0 + b.0, a.1 + b.1, a.2 + b.2, a.3 + b.3, a.4 + b.4)
}

///|
/// Clear billing records, mirroring Ruby BillingStore#clear:
/// - ClearToday rewrites the current month file dropping records from
///   today's local midnight onward, returning records removed;
/// - ClearAll deletes every month file, returning files removed.
pub fn BillingStore::clear(self : BillingStore, scope : ClearScope) -> Int {
  match scope {
    ClearToday => {
      let today_start = get_period_start_ms(Day)
      let now_ms = current_time_ms()
      let file_path = @path.Path::join(
        self.billing_dir,
        @path.Path(month_file_name(now_ms)),
      ).to_string()
      let content = @fs.read_file_to_string(file_path) catch { _ => return 0 }
      let kept : Array[BillingRecord] = []
      let mut removed = 0
      for line in content.split("\n") {
        let trimmed = line.to_owned().trim().to_owned()
        if trimmed.is_empty() {
          continue
        }
        let json_val : Json = @json.parse(trimmed) catch { _ => continue }
        let record : BillingRecord = @json.from_json(json_val) catch {
          _ => continue
        }
        if record.timestamp >= today_start {
          removed = removed + 1
        } else {
          kept.push(record)
        }
      }
      if removed > 0 {
        rewrite_records(file_path, kept)
      }
      removed
    }
    ClearAll => {
      let mut removed = 0
      if !@fs.path_exists(self.billing_dir) {
        return 0
      }
      let entries = @fs.read_dir(self.billing_dir) catch { _ => return 0 }
      for entry in entries {
        let name = entry.to_string()
        if name.has_suffix(".jsonl") {
          let file_path = @path.Path::join(self.billing_dir, @path.Path(name)).to_string()
          @fs.remove_file(file_path) catch {
            _ => continue
          }
          removed = removed + 1
        }
      }
      removed
    }
  }
}

///|
/// Delete month files whose whole month predates `before_ms` (Ruby
/// BillingStore#cleanup: file_month < before - 31 days). Returns the
/// number of files removed.
pub fn BillingStore::cleanup(self : BillingStore, before_ms : Int64) -> Int {
  let mut removed = 0
  if !@fs.path_exists(self.billing_dir) {
    return 0
  }
  let entries = @fs.read_dir(self.billing_dir) catch { _ => return 0 }
  for entry in entries {
    let name = entry.to_string()
    if !name.has_suffix(".jsonl") {
      continue
    }
    match month_file_start_ms(name) {
      Some(month_start) =>
        // Drop months that end before the cutoff month starts.
        if month_start < before_ms - 31L * 86_400_000L {
          let file_path = @path.Path::join(self.billing_dir, @path.Path(name)).to_string()
          @fs.remove_file(file_path) catch {
            _ => continue
          }
          removed = removed + 1
        }
      None => () // Non-month files (e.g. legacy current.jsonl) are kept
    }
  }
  removed
}

// ── Internal Helpers ────────────────────────────────────────────

///|
/// Filter records by criteria. Exported for testing.
pub fn filter_records(
  records : Array[BillingRecord],
  from_ms? : Int64 = 0L,
  to_ms? : Int64 = 0L,
  model? : String = "",
  session_id? : String = "",
) -> Array[BillingRecord] {
  let result : Array[BillingRecord] = []
  for record in records {
    if from_ms > 0L && record.timestamp < from_ms {
      continue
    }
    if to_ms > 0L && record.timestamp > to_ms {
      continue
    }
    if !model.is_empty() && record.model != model {
      continue
    }
    if !session_id.is_empty() && record.session_id != session_id {
      continue
    }
    result.push(record)
  }
  result
}

///|
/// Aggregate records into a Summary. Exported for testing.
pub fn aggregate_summary(
  records : Array[BillingRecord],
  period : TimePeriod,
) -> Summary {
  let mut total_cost = 0.0
  let mut total_prompt = 0
  let mut total_completion = 0
  let mut total_cache_read = 0
  let mut total_cache_write = 0
  let by_model : Map[String, ModelSummary] = Map([])
  for record in records {
    total_cost = total_cost + record.cost_usd
    total_prompt = total_prompt + record.prompt_tokens
    total_completion = total_completion + record.completion_tokens
    total_cache_read = total_cache_read + record.cache_read_tokens
    total_cache_write = total_cache_write + record.cache_write_tokens
    // Aggregate per model
    let ms = match by_model.get(record.model) {
      Some(existing) =>
        {
          cost: existing.cost + record.cost_usd,
          prompt_tokens: existing.prompt_tokens + record.prompt_tokens,
          completion_tokens: existing.completion_tokens +
          record.completion_tokens,
          requests: existing.requests + 1,
        }
      None =>
        {
          cost: record.cost_usd,
          prompt_tokens: record.prompt_tokens,
          completion_tokens: record.completion_tokens,
          requests: 1,
        }
    }
    by_model.set(record.model, ms)
  }
  {
    period,
    total_cost,
    total_prompt_tokens: total_prompt,
    total_completion_tokens: total_completion,
    total_cache_read_tokens: total_cache_read,
    total_cache_write_tokens: total_cache_write,
    by_model,
    record_count: records.length(),
  }
}

///|
/// Ensure billing directory exists.
fn ensure_billing_dir(dir : String) -> Unit {
  if @fs.path_exists(dir) {
    return
  }
  // Create parent directories recursively
  let parent = @path.Path::dirname(@path.Path(dir)).to_string()
  if !parent.is_empty() && parent != dir && !@fs.path_exists(parent) {
    ensure_billing_dir(parent)
  }
  @fs.create_dir(dir) catch {
    _ => ()
  }
}

///|
/// Load all billing records from the directory.
fn load_all_records(dir : String) -> Array[BillingRecord] {
  let records : Array[BillingRecord] = []
  if !@fs.path_exists(dir) {
    return records
  }
  // Read all .jsonl files in the directory
  let entries = @fs.read_dir(dir) catch { _ => return records }
  for entry in entries {
    let name = entry.to_string()
    if name.has_suffix(".jsonl") {
      let file_path = @path.Path::join(dir, @path.Path(name)).to_string()
      let content = @fs.read_file_to_string(file_path) catch { _ => continue }
      // Parse each line
      for line in content.split("\n") {
        let trimmed = line.to_owned().trim().to_owned()
        if trimmed.is_empty() {
          continue
        }
        let json_val : Json = @json.parse(trimmed) catch { _ => continue }
        let record : BillingRecord = @json.from_json(json_val) catch {
          _ => continue
        }
        records.push(record)
      }
    }
  }
  records
}

///|
/// Append a single line to a file (creates file if not exists).
fn append_line(file_path : String, line : String) -> Unit raise @fs.IOError {
  let existing = @fs.read_file_to_string(file_path) catch { _ => "" }
  let new_content = if existing.is_empty() {
    line + "\n"
  } else {
    existing + line + "\n"
  }
  @fs.write_string_to_file(file_path, new_content)
}

///|
/// Rewrite file with given records.
fn rewrite_records(file_path : String, records : Array[BillingRecord]) -> Unit {
  let mut content = ""
  for record in records {
    content = content + record.to_json().stringify() + "\n"
  }
  @fs.write_string_to_file(file_path, content) catch {
    _ => ()
  }
}
