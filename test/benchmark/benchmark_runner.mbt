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
  { scenarios, results: [], current_scenario: None }
}

///|
/// 运行单个场景的单次迭代
fn run_single_iteration(
  scenario : BenchmarkScenario,
  iteration : Int,
) -> BenchmarkIterationResult {
  let timer = BenchmarkTimer::new()
  let success = true
  let error = ""

  // 这里应该实际执行场景，但为了简化，我们模拟执行
  // 实际实现中，这里应该调用场景的执行逻辑
  // 例如：执行 LLM 调用、工具执行等

  // 模拟执行时间（实际应该根据场景类型执行）
  let _ = scenario.iterations + iteration

  let elapsed_ms = timer.elapsed_ms()

  { scenario_name: scenario.name, iteration, elapsed_ms, success, error }
}

///|
/// 运行单个场景的所有迭代
pub fn BenchmarkRunner::run_scenario(
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
pub fn BenchmarkRunner::run_all(
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
