///|
/// BenchmarkIterationResult - 单次基准测试迭代结果
pub struct BenchmarkIterationResult {
  scenario_name : String
  iteration : Int
  elapsed_ms : Int64
  success : Bool
  error : String
}

///|
/// BenchmarkRunner - 基准测试运行器
pub struct BenchmarkRunner {
  scenarios : Array[BenchmarkScenario]
  results : Array[BenchmarkIterationResult]
  current_scenario : BenchmarkScenario?
}

///|
/// 创建新的 BenchmarkRunner
pub fn BenchmarkRunner::new(
  scenarios : Array[BenchmarkScenario],
) -> BenchmarkRunner {
  { scenarios, results: [], current_scenario: None, }
}

///|
/// 实际执行工具并返回 (elapsed_ms, success, error)
async fn execute_tool_timed(
  tool : @tool.AnyTool,
  args : Map[String, Json],
) -> (Int64, Bool, String) {
  let timer = BenchmarkTimer::new()
  let result = @tool.Tool::execute(tool, args) catch {
    err =>
      @tool.ToolResult::{
        content: "tool raised: " + @debug.to_string(err),
        is_error: true,
      }
  }
  let elapsed_ms = timer.elapsed_ms()
  (
    elapsed_ms,
    !result.is_error,
    if result.is_error {
      result.content
    } else {
      ""
    },
  )
}

///|
/// 运行单个场景的单次迭代
async fn run_single_iteration(
  scenario : BenchmarkScenario,
  iteration : Int,
) -> BenchmarkIterationResult {
  let registry = @tool.make_default_registry()
  let _ = iteration

  if scenario.tool == "" {
    return {
      scenario_name: scenario.name,
      iteration,
      elapsed_ms: 0L,
      success: false,
      error: "scenario has no tool configured",
    }
  }

  match registry.get_resolved(scenario.tool) {
    Some(tool) => {
      let (elapsed_ms, success, error) = execute_tool_timed(
        tool,
        scenario.parameters,
      )
      { scenario_name: scenario.name, iteration, elapsed_ms, success, error, }
    }
    None =>
      {
        scenario_name: scenario.name,
        iteration,
        elapsed_ms: 0L,
        success: false,
        error: "tool not found: \{scenario.tool}",
      }
  }
}

///|
/// 运行单个场景的所有迭代
pub async fn BenchmarkRunner::run_scenario(
  scenario : BenchmarkScenario,
) -> BenchmarkStats {
  let samples : Array[Int64] = []

  // 预热阶段
  for i = 0; i < scenario.warmup; i = i + 1 {
    let _ = run_single_iteration(scenario, i)
  }

  // 正式迭代阶段
  for i = 0; i < scenario.iterations; i = i + 1 {
    let result = run_single_iteration(scenario, i)
    if result.success {
      samples.push(result.elapsed_ms)
    }
  }

  BenchmarkStats::from_samples(samples)
}

///|
/// 运行所有场景
pub async fn BenchmarkRunner::run_all(
  self : BenchmarkRunner,
) -> Array[(String, BenchmarkStats)] {
  let results : Array[(String, BenchmarkStats)] = []

  for scenario in self.scenarios {
    let stats = BenchmarkRunner::run_scenario(scenario)
    results.push((scenario.name, stats))
  }

  results
}

///|
/// 生成汇总报告
pub fn BenchmarkRunner::generate_report(
  results : Array[(String, BenchmarkStats)],
) -> String {
  let lines : Array[String] = []
  lines.push(
    "═══════════════════════════════════════════",
  )
  lines.push("  Benchmark Report")
  lines.push(
    "═══════════════════════════════════════════",
  )
  lines.push("")

  for i = 0; i < results.length(); i = i + 1 {
    let (name, stats) = results[i]
    lines.push(stats.to_markdown(name))
    lines.push("")
  }

  lines.push(
    "═══════════════════════════════════════════",
  )
  lines.join("\n")
}
