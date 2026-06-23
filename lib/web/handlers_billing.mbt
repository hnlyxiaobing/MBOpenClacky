///| Billing and License management REST API handlers.

// ── Billing Handlers ──────────────────────────────────────────────

///|
/// GET /api/billing/status — Get current license/billing status.
pub fn handle_billing_status(request : HttpRequest) -> HttpResponse {
  ignore(request)
  // Query billing store for current month summary
  let store = @billing.BillingStore::default()
  let summary = store.summary(@billing.Month)
  let body = Json::object({
    "license_type": "community".to_json(),
    "activated": false.to_json(),
    "expires_at": Json::null(),
    "features": ["basic_agent".to_json(), "tools".to_json()].to_json(),
    "current_month_cost": summary.total_cost.to_json(),
    "current_month_requests": summary.record_count.to_json(),
  })
  HttpResponse::ok(body.stringify())
}

///|
/// POST /api/billing/activate — Activate a license key.
pub fn handle_billing_activate(request : HttpRequest) -> HttpResponse {
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  // TODO: Validate and activate the license key
  // Expected body: {"license_key":"..."}
  let body =
    #|{"activated":true,"license_type":"pro","message":"License activated successfully"}
  HttpResponse::ok(body)
}

///|
/// GET /api/billing/usage — Get usage statistics for billing.
pub fn handle_billing_usage(request : HttpRequest) -> HttpResponse {
  ignore(request)
  // Aggregate token usage via BillingStore
  let store = @billing.BillingStore::default()
  let summary = store.summary(@billing.Month)
  // Build by_model breakdown as JSON array
  let breakdown : Array[Json] = []
  summary.by_model.each(fn(model, ms) {
    breakdown.push(
      Json::object({
        "model": model.to_json(),
        "cost_usd": ms.cost.to_json(),
        "prompt_tokens": ms.prompt_tokens.to_json(),
        "completion_tokens": ms.completion_tokens.to_json(),
        "requests": ms.requests.to_json(),
      }),
    )
  })
  let body = Json::object({
    "period": "current_month".to_json(),
    "total_tokens": (summary.total_prompt_tokens +
    summary.total_completion_tokens).to_json(),
    "total_requests": summary.record_count.to_json(),
    "total_cost_usd": summary.total_cost.to_json(),
    "breakdown": breakdown.to_json(),
  })
  HttpResponse::ok(body.stringify())
}
