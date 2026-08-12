///|
/// 白盒测试 - BenchmarkTimer 和 BenchmarkStats
test "BenchmarkTimer elapsed_ms" {
  let timer = BenchmarkTimer::new()
  // 模拟一些操作
  let _ = 1 + 1
  let elapsed = timer.elapsed_ms()
  @debug.debug_inspect(elapsed >= 0L, content="true")
}

///|
test "BenchmarkStats from_samples" {
  let samples = [100L, 200L, 300L, 400L, 500L]
  let stats = BenchmarkStats::from_samples(samples)

  @debug.debug_inspect(stats.min_ms, content="100")
  @debug.debug_inspect(stats.max_ms, content="500")
  @debug.debug_inspect(stats.iterations, content="5")
  @debug.debug_inspect(stats.p50_ms, content="300")
  @debug.debug_inspect(stats.p95_ms, content="500")
  @debug.debug_inspect(stats.p99_ms, content="500")
}

///|
test "BenchmarkStats empty samples" {
  let samples : Array[Int64] = []
  let stats = BenchmarkStats::from_samples(samples)

  @debug.debug_inspect(stats.iterations, content="0")
  @debug.debug_inspect(stats.min_ms, content="0")
}

///|
test "BenchmarkStats to_markdown" {
  let samples = [100L, 200L, 300L]
  let stats = BenchmarkStats::from_samples(samples)
  let markdown = stats.to_markdown("test_scenario")

  @debug.debug_inspect(
    markdown.contains("Benchmark: test_scenario"),
    content="true",
  )
  @debug.debug_inspect(markdown.contains("Iterations: 3"), content="true")
  @debug.debug_inspect(markdown.contains("Min: 100ms"), content="true")
  @debug.debug_inspect(markdown.contains("Max: 300ms"), content="true")
}
