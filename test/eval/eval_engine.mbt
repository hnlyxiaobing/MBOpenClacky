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
/// Load scenario JSON files from a directory.
/// Returns an array of raw JSON text strings (one per .json file).
/// Parsing into domain-specific types is the adapter's responsibility.
pub fn load_scenario_files(dir_path : String) -> Array[String] {
  let texts : Array[String] = []
  let entries = @fs.read_dir(dir_path) catch { _ => return texts }
  for entry in entries {
    let path = @path.Path::join(dir_path, @path.Path(entry)).to_string()
    if path.ends_with(".json") {
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
