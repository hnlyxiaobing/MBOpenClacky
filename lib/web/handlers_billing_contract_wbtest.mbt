///| White-box contract tests for the billing REST API handlers, covering

///| spec `2026-07-24_web-ui-fix-10-billing-api-contract` (I-009/I-014/I-015):

///| summary 12-field shape, daily `days` key with token splits, records and

///| sessions incremental fields aligned with the orig openclacky contract.

///|
/// Point USERPROFILE at an isolated dir so BillingStore::default() is hermetic.
/// Pre-creates the billing dir: BillingStore::ensure_billing_dir cannot create
/// multi-level missing paths (Path::dirname quirk), so tests set it up first.
fn bc_use_dir(dir : String) -> Unit {
  @sys.set_env_var("USERPROFILE", dir)
  // Drop leftovers from previous failed runs before re-creating the tree.
  @fs.remove_file(dir + "/.mbopenclacky/billing/current.jsonl") catch {
    _ => ()
  }
  @fs.create_dir(dir) catch {
    _ => ()
  }
  @fs.create_dir(dir + "/.mbopenclacky") catch {
    _ => ()
  }
  @fs.create_dir(dir + "/.mbopenclacky/billing") catch {
    _ => ()
  }
}

///|
/// Seed one billing record into the default store.
fn bc_seed(
  session_id : String,
  model : String,
  prompt_tokens : Int,
  completion_tokens : Int,
  cache_read_tokens : Int,
  cache_write_tokens : Int,
  cost_usd : Double,
  cost_source : String,
) -> Unit {
  let store = @billing.BillingStore::default()
  let record = @billing.BillingRecord::new(
    session_id~,
    model~,
    prompt_tokens~,
    completion_tokens~,
    cache_read_tokens~,
    cache_write_tokens~,
    cost_usd~,
    cost_source~,
  )
  ignore(store.append(record))
}

///|
fn bc_body_json(resp : HttpResponse) -> Json {
  @json.parse(resp.body) catch {
    _ => Json::object(Map([]))
  }
}

///|
fn bc_remove_dir(dir : String) -> Unit {
  @fs.remove_file(dir + "/.mbopenclacky/billing/current.jsonl") catch {
    _ => ()
  }
  @fs.remove_dir(dir + "/.mbopenclacky/billing") catch {
    _ => ()
  }
  @fs.remove_dir(dir + "/.mbopenclacky") catch {
    _ => ()
  }
  @fs.remove_dir(dir) catch {
    _ => ()
  }
}

///|
test "billing summary matches orig 12-field contract" {
  let dir = "_build/billing-contract-summary"
  bc_use_dir(dir)
  bc_seed("s1", "model-a", 100, 50, 10, 5, 0.01, "price")
  bc_seed("s2", "model-b", 200, 80, 20, 8, 0.02, "api")
  let resp = handle_billing_summary(
    HttpRequest::new(GET, "/api/billing/summary"),
  )
  @debug.assert_eq(resp.status, 200)
  let j = bc_body_json(resp)
  guard! j is Json::Object(obj)
  // Exactly the orig 12 keys (I-009)
  let expected = [
    "period", "from", "to", "total_cost", "total_tokens", "prompt_tokens", "completion_tokens",
    "cache_read_tokens", "cache_write_tokens", "by_model", "by_day", "record_count",
  ]
  for key in expected {
    assert_true(obj.contains(key))
  }
  @debug.assert_eq(obj.length(), 12)
  @debug.assert_eq(obj.get("period"), Some("month".to_json()))
  @debug.assert_eq(obj.get("record_count"), Some((2).to_json()))
  @debug.assert_eq(obj.get("prompt_tokens"), Some((300).to_json()))
  @debug.assert_eq(obj.get("completion_tokens"), Some((130).to_json()))
  @debug.assert_eq(obj.get("total_tokens"), Some((430).to_json()))
  @debug.assert_eq(obj.get("cache_read_tokens"), Some((30).to_json()))
  @debug.assert_eq(obj.get("cache_write_tokens"), Some((13).to_json()))
  // from/to are ISO datetime strings
  guard! obj.get("from") is Some(String(_))
  guard! obj.get("to") is Some(String(_))
  // by_model entries: { cost, prompt_tokens, completion_tokens, requests }
  guard! obj.get("by_model") is Some(Object(by_model))
  guard! by_model.get("model-a") is Some(Object(ma))
  @debug.assert_eq(ma.get("requests"), Some((1).to_json()))
  @debug.assert_eq(ma.get("prompt_tokens"), Some((100).to_json()))
  @debug.assert_eq(ma.get("completion_tokens"), Some((50).to_json()))
  assert_true(ma.contains("cost"))
  // by_day values are plain cost numbers keyed by date
  guard! obj.get("by_day") is Some(Object(by_day))
  @debug.assert_eq(by_day.length(), 1)
  bc_remove_dir(dir)
}

///|
test "billing summary honors period query param" {
  let dir = "_build/billing-contract-summary-period"
  bc_use_dir(dir)
  let resp = handle_billing_summary(
    HttpRequest::new(GET, "/api/billing/summary?period=week"),
  )
  let j = bc_body_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("period"), Some("week".to_json()))
  // "all" period emits from: null (orig semantics)
  let resp_all = handle_billing_summary(
    HttpRequest::new(GET, "/api/billing/summary?period=all"),
  )
  let j_all = bc_body_json(resp_all)
  guard! j_all is Json::Object(obj_all)
  @debug.assert_eq(obj_all.get("period"), Some("all".to_json()))
  @debug.assert_eq(obj_all.get("from"), Some(Json::null()))
  bc_remove_dir(dir)
}

///|
test "billing daily uses days key with full token splits" {
  let dir = "_build/billing-contract-daily"
  bc_use_dir(dir)
  bc_seed("s1", "model-a", 100, 50, 10, 5, 0.01, "price")
  let resp = handle_billing_daily(HttpRequest::new(GET, "/api/billing/daily"))
  @debug.assert_eq(resp.status, 200)
  let j = bc_body_json(resp)
  guard! j is Json::Object(obj)
  // I-014: top-level key is days, not daily
  assert_true(obj.contains("days"))
  assert_true(!obj.contains("daily"))
  guard! obj.get("days") is Some(Array(days))
  @debug.assert_eq(days.length(), 30)
  guard! days[0] is Json::Object(first)
  let expected = [
    "date", "cost", "tokens", "prompt_tokens", "completion_tokens", "cache_read_tokens",
    "cache_write_tokens", "requests",
  ]
  for key in expected {
    assert_true(first.contains(key))
  }
  // The seeded record lands in the most recent day bucket
  guard! days[29] is Json::Object(today)
  @debug.assert_eq(today.get("requests"), Some((1).to_json()))
  @debug.assert_eq(today.get("tokens"), Some((150).to_json()))
  @debug.assert_eq(today.get("cache_read_tokens"), Some((10).to_json()))
  // days query param is honored and capped at 90 (orig clamps)
  let resp7 = handle_billing_daily(
    HttpRequest::new(GET, "/api/billing/daily?days=7"),
  )
  guard! bc_body_json(resp7) is Json::Object(obj7)
  guard! obj7.get("days") is Some(Array(d7))
  @debug.assert_eq(d7.length(), 7)
  let resp_cap = handle_billing_daily(
    HttpRequest::new(GET, "/api/billing/daily?days=500"),
  )
  guard! bc_body_json(resp_cap) is Json::Object(obj_cap)
  guard! obj_cap.get("days") is Some(Array(d_cap))
  @debug.assert_eq(d_cap.length(), 90)
  bc_remove_dir(dir)
}

///|
test "billing records include count, cache splits and cost_source" {
  let dir = "_build/billing-contract-records"
  bc_use_dir(dir)
  bc_seed("s1", "model-a", 100, 50, 10, 5, 0.01, "price")
  bc_seed("s1", "model-b", 200, 80, 20, 8, 0.02, "estimated")
  let resp = handle_billing_records(
    HttpRequest::new(GET, "/api/billing/records"),
  )
  @debug.assert_eq(resp.status, 200)
  let j = bc_body_json(resp)
  guard! j is Json::Object(obj)
  // I-015: top-level count plus full record fields
  @debug.assert_eq(obj.get("count"), Some((2).to_json()))
  guard! obj.get("records") is Some(Array(records))
  @debug.assert_eq(records.length(), 2)
  let expected = [
    "id", "session_id", "timestamp", "model", "prompt_tokens", "completion_tokens",
    "cache_read_tokens", "cache_write_tokens", "cost_usd", "cost_source",
  ]
  // Records with near-identical timestamps may come back in either order;
  // locate the model-b entry explicitly.
  let mut rb : Map[String, Json]? = None
  for item in records {
    guard! item is Json::Object(r)
    for key in expected {
      assert_true(r.contains(key))
    }
    if r.get("model") == Some("model-b".to_json()) {
      rb = Some(r)
    }
    // timestamp is an ISO datetime string, not raw milliseconds
    guard! r.get("timestamp") is Some(String(ts))
    assert_true(ts.contains("T"))
  }
  guard! rb is Some(r0)
  @debug.assert_eq(r0.get("cache_read_tokens"), Some((20).to_json()))
  @debug.assert_eq(r0.get("cache_write_tokens"), Some((8).to_json()))
  @debug.assert_eq(r0.get("cost_source"), Some("estimated".to_json()))
  // limit query param is honored
  let resp1 = handle_billing_records(
    HttpRequest::new(GET, "/api/billing/records?limit=1"),
  )
  guard! bc_body_json(resp1) is Json::Object(obj1)
  @debug.assert_eq(obj1.get("count"), Some((1).to_json()))
  bc_remove_dir(dir)
}

///|
test "billing sessions aggregate per orig contract shape" {
  let dir = "_build/billing-contract-sessions"
  bc_use_dir(dir)
  bc_seed("s1", "model-a", 100, 50, 10, 5, 0.03, "price")
  bc_seed("s1", "model-b", 200, 80, 20, 8, 0.02, "api")
  bc_seed("s2", "model-a", 10, 5, 0, 0, 0.01, "price")
  let resp = handle_billing_sessions(
    HttpRequest::new(GET, "/api/billing/sessions"),
  )
  @debug.assert_eq(resp.status, 200)
  let j = bc_body_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("count"), Some((2).to_json()))
  guard! obj.get("sessions") is Some(Array(sessions))
  @debug.assert_eq(sessions.length(), 2)
  // Sorted by total cost descending: s1 (0.05) before s2 (0.01)
  guard! sessions[0] is Json::Object(first)
  let expected = [
    "session_id", "session_name", "total_cost", "total_tokens", "prompt_tokens",
    "completion_tokens", "cache_read_tokens", "cache_write_tokens", "requests", "first_request",
    "last_request", "models",
  ]
  for key in expected {
    assert_true(first.contains(key))
  }
  @debug.assert_eq(first.get("session_id"), Some("s1".to_json()))
  @debug.assert_eq(first.get("requests"), Some((2).to_json()))
  @debug.assert_eq(first.get("total_tokens"), Some((430).to_json()))
  @debug.assert_eq(first.get("prompt_tokens"), Some((300).to_json()))
  @debug.assert_eq(first.get("completion_tokens"), Some((130).to_json()))
  @debug.assert_eq(first.get("cache_read_tokens"), Some((30).to_json()))
  @debug.assert_eq(first.get("cache_write_tokens"), Some((13).to_json()))
  guard! first.get("models") is Some(Array(models))
  @debug.assert_eq(models.length(), 2)
  guard! first.get("first_request") is Some(String(_))
  guard! first.get("last_request") is Some(String(_))
  guard! sessions[1] is Json::Object(second)
  @debug.assert_eq(second.get("session_id"), Some("s2".to_json()))
  // limit query param is honored
  let resp1 = handle_billing_sessions(
    HttpRequest::new(GET, "/api/billing/sessions?limit=1"),
  )
  guard! bc_body_json(resp1) is Json::Object(obj1)
  @debug.assert_eq(obj1.get("count"), Some((1).to_json()))
  bc_remove_dir(dir)
}
