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
/// Per-model billing summary.
pub(all) struct ModelSummary {
  cost : Double
  prompt_tokens : Int
  completion_tokens : Int
  requests : Int
} derive(Eq, Debug)

///|
/// Per-day billing summary.
pub(all) struct DaySummary {
  date : String // "YYYY-MM-DD"
  total_cost : Double
  total_tokens : Int
  request_count : Int
} derive(Eq, Debug)

// ── BillingStore ────────────────────────────────────────────────

///|
/// JSONL-based billing record storage.
/// Files stored at: {billing_dir}/YYYY-MM.jsonl
pub(all) struct BillingStore {
  billing_dir : String
} derive(Eq, Debug)

///|
/// Create a new BillingStore with given directory.
pub fn BillingStore::new(billing_dir : String) -> BillingStore {
  { billing_dir, }
}

///|
/// Create a BillingStore with default directory (~/.mbopenclacky/billing/).
pub fn BillingStore::default() -> BillingStore {
  let dir = match @sys.get_env_var("USERPROFILE") {
    Some(home) if !home.is_empty() =>
      @path.Path::join(home, @path.Path(".mbopenclacky/billing")).to_string()
    _ =>
      match @sys.get_env_var("HOME") {
        Some(home) if !home.is_empty() =>
          @path.Path::join(home, @path.Path(".mbopenclacky/billing")).to_string()
        _ => ".mbopenclacky/billing"
      }
  }
  { billing_dir: dir }
}

///|
/// Append a billing record to the current month's JSONL file.
/// Returns the record id on success.
pub fn BillingStore::append(
  self : BillingStore,
  record : BillingRecord,
) -> Result[String, String] {
  // Ensure billing directory exists
  ensure_billing_dir(self.billing_dir)
  // Determine month file name (simplified: use "current.jsonl" since we lack date formatting)
  let file_path = @path.Path::join(
    self.billing_dir,
    @path.Path("current.jsonl"),
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
/// Get daily cost breakdown for the last N days.
pub fn BillingStore::daily_breakdown(
  self : BillingStore,
  days? : Int = 7,
) -> Array[DaySummary] {
  let ms_per_day = 86_400_000L
  let now_ms = current_time_ms()
  let from_ms = now_ms - days.to_int64() * ms_per_day
  let records = self.query(from_ms~)
  // Group by day bucket
  let day_map : Map[Int, (Double, Int, Int)] = {}
  for record in records {
    let day_offset = ((now_ms - record.timestamp) / ms_per_day).to_int()
    let key = days - 1 - day_offset
    if key >= 0 && key < days {
      let (cost, tokens, count) = match day_map.get(key) {
        Some(v) => v
        None => (0.0, 0, 0)
      }
      day_map.set(
        key,
        (cost + record.cost_usd, tokens + record.total_tokens(), count + 1),
      )
    }
  }
  // Build result array
  let result : Array[DaySummary] = []
  for i = 0; i < days; i = i + 1 {
    let (cost, tokens, count) = match day_map.get(i) {
      Some(v) => v
      None => (0.0, 0, 0)
    }
    let day_ms = now_ms - (days - 1 - i).to_int64() * ms_per_day
    let date = ms_to_date_string(day_ms)
    result.push({
      date,
      total_cost: cost,
      total_tokens: tokens,
      request_count: count,
    })
  }
  result
}

///|
/// Delete billing records before a given timestamp.
/// Returns count of files removed (simplified: returns records removed).
pub fn BillingStore::cleanup(self : BillingStore, before_ms : Int64) -> Int {
  let all_records = load_all_records(self.billing_dir)
  let kept : Array[BillingRecord] = []
  let mut removed = 0
  for record in all_records {
    if record.timestamp < before_ms {
      removed = removed + 1
    } else {
      kept.push(record)
    }
  }
  // Rewrite file with kept records
  let file_path = @path.Path::join(
    self.billing_dir,
    @path.Path("current.jsonl"),
  ).to_string()
  rewrite_records(file_path, kept)
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
  let by_model : Map[String, ModelSummary] = {}
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
/// Calculate period start in milliseconds.
fn get_period_start_ms(period : TimePeriod) -> Int64 {
  let now_ms = current_time_ms()
  match period {
    Day => now_ms - 86_400_000L
    Week => now_ms - 604_800_000L
    Month => now_ms - 2_592_000_000L // ~30 days
    Year => now_ms - 31_536_000_000L // ~365 days
    All => 0L
  }
}

///|
/// Convert milliseconds to date string "YYYY-MM-DD" (simplified).
fn ms_to_date_string(_ms : Int64) -> String {
  // Simplified: without full date formatting support, return placeholder
  "0000-00-00"
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
