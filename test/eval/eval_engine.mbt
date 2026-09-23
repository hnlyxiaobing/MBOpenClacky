///|
/// Generic Eval Engine: module-agnostic eval framework core.
///
/// Provides result types, scenario file loading, and report formatting.
/// Each module (TUI, Agent, Web, etc.) implements its own adapter layer
/// that produces EvalScenarioResult/EvalBatchResult for unified reporting.

///|
/// Result of a single assertion check.
pub(all) struct EvalAssertionResult {
  /// The assertion that was checked (description).
  description : String
  /// Whether the assertion passed.
  passed : Bool
  /// Diagnostic message on failure.
  detail : String
} derive(Debug)

///|
pub extend EvalAssertionResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Result of running a single eval scenario.
pub(all) struct EvalScenarioResult {
  /// Scenario name.
  scenario_name : String
  /// Whether all assertions passed.
  passed : Bool
  /// Individual assertion results.
  assertion_results : Array[EvalAssertionResult]
  /// Final screen content (for debugging).
  final_screen : String
  /// Error message if scenario failed to execute.
  error : String
} derive(Debug)

///|
pub extend EvalScenarioResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Result of running a batch of eval scenarios.
pub(all) struct EvalBatchResult {
  /// Results for each scenario.
  results : Array[EvalScenarioResult]
  /// Number of passed scenarios.
  passed_count : Int
  /// Number of failed scenarios.
  failed_count : Int
  /// Total number of scenarios.
  total_count : Int
} derive(Debug)

///|
pub extend EvalBatchResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Load scenario JSON files from a directory.
/// Returns an array of raw JSON text strings (one per .json file).
/// Parsing into domain-specific types is the adapter's responsibility.
pub fn load_scenario_files(dir_path : String) -> Array[String] {
  let texts : Array[String] = []
  let entries = @fs.read_dir(dir_path) catch { _ => return texts }
  for entry in entries {
    let path = @path.Path::join(dir_path, @path.Path(entry)).to_string()
    if path.has_suffix(".json") {
      let content = @fs.read_file_to_string(path) catch { _ => continue }
      texts.push(content)
    }
  }
  texts
}

///|
/// Format eval batch results as a human-readable report string.
pub fn format_eval_report(batch : EvalBatchResult) -> String {
  let lines : Array[String] = []
  lines.push(
    "═══════════════════════════════════════════",
  )
  lines.push("  Eval Report")
  lines.push(
    "═══════════════════════════════════════════",
  )
  lines.push("")

  for result in batch.results {
    let status = if result.passed { "✓ PASS" } else { "✗ FAIL" }
    lines.push("  \{status}  \{result.scenario_name}")
    if !result.passed {
      for ar in result.assertion_results {
        if !ar.passed {
          lines.push("         ↳ \{ar.description}")
          if ar.detail.length() > 0 {
            lines.push("           \{ar.detail}")
          }
        }
      }
    }
  }

  lines.push("")
  lines.push(
    "───────────────────────────────────────────",
  )
  lines.push(
    "  Total: \{batch.total_count}  Passed: \{batch.passed_count}  Failed: \{batch.failed_count}",
  )
  lines.push(
    "═══════════════════════════════════════════",
  )
  lines.join("\n")
}

// ── Unified Report Pipeline ──────────────────────────────────────────────────
//
// A domain-agnostic report type that all eval subsystems can produce, consumed
// by three renderers (text, JSON, markdown). This replaces six independent
// report formatters with one shared pipeline.

///|
pub(all) enum UnifiedTestKind {
  Tui
  Web
  HarnessOffline
  HarnessLive
  Benchmark
  Contract
  Journey
}

///|
pub(all) struct UnifiedAssertionResult {
  description : String
  passed : Bool
  detail : String
}

///|
pub(all) struct UnifiedSuiteResult {
  name : String
  passed : Bool
  assertions : Array[UnifiedAssertionResult]
  error : String
  duration_ms : Double
  metadata : Json
}

///|
pub(all) struct UnifiedSummary {
  total : Int
  passed : Int
  failed : Int
}

///|
pub(all) struct UnifiedReport {
  suite_name : String
  kind : UnifiedTestKind
  timestamp : String
  results : Array[UnifiedSuiteResult]
  summary : UnifiedSummary
}

// ── Conversions from existing types ──────────────────────────────────────────

///|
pub fn EvalBatchResult::to_unified_report(
  self : EvalBatchResult,
  suite_name? : String = "eval",
) -> UnifiedReport {
  let results : Array[UnifiedSuiteResult] = []
  for r in self.results {
    results.push(EvalScenarioResult::to_unified(r))
  }
  {
    suite_name,
    kind: UnifiedTestKind::Tui,
    timestamp: "",
    results,
    summary: {
      total: self.total_count,
      passed: self.passed_count,
      failed: self.failed_count,
    },
  }
}

///|
fn EvalScenarioResult::to_unified(r : EvalScenarioResult) -> UnifiedSuiteResult {
  let assertions : Array[UnifiedAssertionResult] = []
  for a in r.assertion_results {
    let ua : UnifiedAssertionResult = {
      description: a.description,
      passed: a.passed,
      detail: a.detail,
    }
    assertions.push(ua)
  }
  {
    name: r.scenario_name,
    passed: r.passed,
    assertions,
    error: r.error,
    duration_ms: 0.0,
    metadata: Json::object(Map([])),
  }
}

///|
pub fn HarnessReport::to_unified_report(
  self : HarnessReport,
  mode : String,
  trials : Int,
  cost_usd? : Double = 0.0,
) -> UnifiedReport {
  let results : Array[UnifiedSuiteResult] = []
  for r in self.results {
    let assertions : Array[UnifiedAssertionResult] = []
    for a in r.assertions {
      let ua : UnifiedAssertionResult = {
        description: a.description,
        passed: a.passed,
        detail: a.detail,
      }
      assertions.push(ua)
    }
    results.push({
      name: r.task_id,
      passed: r.passed,
      assertions,
      error: "",
      duration_ms: 0.0,
      metadata: Json::object({
        "goal": r.goal.to_json(),
        "steps_run": r.steps_run.to_json(),
      }),
    })
  }
  let score = self.score(trials, cost_usd~)
  let kind = if mode == "live" {
    UnifiedTestKind::HarnessLive
  } else {
    UnifiedTestKind::HarnessOffline
  }
  {
    suite_name: "eval-" + mode,
    kind,
    timestamp: "",
    results,
    summary: {
      total: score.tasks,
      passed: score.tasks_passed,
      failed: score.tasks - score.tasks_passed,
    },
  }
}

// ── Renderers ────────────────────────────────────────────────────────────────

///|
pub fn render_unified_report_text(report : UnifiedReport) -> String {
  let lines : Array[String] = []
  lines.push(
    "═══════════════════════════════════════════",
  )
  lines.push("  \{report.suite_name} Report")
  lines.push(
    "═══════════════════════════════════════════",
  )
  lines.push("")
  for result in report.results {
    let status = if result.passed { "✓ PASS" } else { "✗ FAIL" }
    lines.push("  \{status}  \{result.name}")
    if !result.passed {
      for ar in result.assertions {
        if !ar.passed {
          lines.push("         ↳ \{ar.description}")
          if ar.detail.length() > 0 {
            lines.push("           \{ar.detail}")
          }
        }
      }
      if result.error.length() > 0 {
        lines.push("         error: \{result.error}")
      }
    }
  }
  lines.push("")
  lines.push(
    "───────────────────────────────────────────",
  )
  lines.push(
    "  Total: \{report.summary.total}  Passed: \{report.summary.passed}  Failed: \{report.summary.failed}",
  )
  lines.push(
    "═══════════════════════════════════════════",
  )
  lines.join("\n")
}

///|
pub fn render_unified_report_json(report : UnifiedReport) -> Json {
  let results_json : Array[Json] = []
  for result in report.results {
    let assertions_json : Array[Json] = []
    for ar in result.assertions {
      assertions_json.push(
        Json::object({
          "description": ar.description.to_json(),
          "passed": Json::boolean(ar.passed),
          "detail": ar.detail.to_json(),
        }),
      )
    }
    results_json.push(
      Json::object({
        "name": result.name.to_json(),
        "passed": Json::boolean(result.passed),
        "assertions": Json::array(assertions_json),
        "error": result.error.to_json(),
        "duration_ms": Json::number(result.duration_ms),
        "metadata": result.metadata,
      }),
    )
  }
  Json::object({
    "suite_name": report.suite_name.to_json(),
    "timestamp": report.timestamp.to_json(),
    "results": Json::array(results_json),
    "summary": Json::object({
      "total": report.summary.total.to_json(),
      "passed": report.summary.passed.to_json(),
      "failed": report.summary.failed.to_json(),
    }),
  })
}

///|
pub fn render_unified_report_markdown(
  report : UnifiedReport,
  title? : String = "",
) -> String {
  let heading = if title.length() > 0 {
    title
  } else {
    "\{report.suite_name} Report"
  }
  let lines : Array[String] = []
  lines.push("# \{heading}")
  lines.push("")
  lines.push("| # | Name | Result | Assertions |")
  lines.push("|---|------|--------|------------|")
  let mut idx = 0
  for result in report.results {
    idx = idx + 1
    let status = if result.passed { "PASS" } else { "FAIL" }
    let mut passed_count = 0
    for a in result.assertions {
      if a.passed {
        passed_count = passed_count + 1
      }
    }
    lines.push(
      "| \{idx} | \{result.name} | \{status} | \{passed_count}/\{result.assertions.length()} |",
    )
  }
  lines.push("")
  lines.push("## Summary")
  lines.push("")
  lines.push("- Total: \{report.summary.total}")
  lines.push("- Passed: \{report.summary.passed}")
  lines.push("- Failed: \{report.summary.failed}")
  if report.timestamp.length() > 0 {
    lines.push("- Timestamp: \{report.timestamp}")
  }
  lines.push("")
  lines.push("## Details")
  lines.push("")
  for result in report.results {
    lines.push("### \{result.name}")
    lines.push("")
    for a in result.assertions {
      let mark = if a.passed { "x" } else { " " }
      let detail_suffix = if a.detail.length() > 0 {
        " — \{a.detail}"
      } else {
        ""
      }
      lines.push("- [\{mark}] \{a.description}\{detail_suffix}")
    }
    if result.error.length() > 0 {
      lines.push("")
      lines.push("> Error: \{result.error}")
    }
    lines.push("")
  }
  lines.join("\n")
}
