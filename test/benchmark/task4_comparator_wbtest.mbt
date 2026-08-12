///|
/// task4_comparator_wbtest.mbt - 任务包4白盒测试

///|
/// 测试 RegressionReport 创建
test "RegressionReport creation" {
  let stats = BenchmarkStats::new(
    100L, 200L, 150.0, 140L, 180L, 190L, 10, 1500L,
  )
  let report = RegressionReport::new("test_scenario", stats, None, None, 10.0)

  @test.assert_eq(report.scenario_name, "test_scenario")
  @test.assert_eq(report.current_stats, stats)
  @test.assert_eq(report.has_regression, false)
  @test.assert_eq(report.threshold_pct, 10.0)
}

///|
/// 测试无回归检测
test "no regression detected" {
  let current_stats = BenchmarkStats::new(
    100L, 200L, 150.0, 140L, 180L, 190L, 10, 1500L,
  )
  let last_stats = Some(
    BenchmarkStats::new(110L, 210L, 160.0, 150L, 190L, 200L, 10, 1600L),
  )

  let report = RegressionReport::new(
    "test_scenario",
    current_stats,
    last_stats,
    None,
    10.0,
  )
  let detected = report.detect_regression()

  @test.assert_eq(detected.has_regression, false)
  @test.assert_eq(detected.regression_details.length(), 0)
}

///|
/// 测试回归检测（P95 增加）
test "regression detected - p95 increase" {
  let current_stats = BenchmarkStats::new(
    100L, 200L, 150.0, 140L, 200L, 190L, 10, 1500L,
  )
  let last_stats = Some(
    BenchmarkStats::new(100L, 200L, 150.0, 140L, 150L, 190L, 10, 1500L),
  )

  let report = RegressionReport::new(
    "test_scenario",
    current_stats,
    last_stats,
    None,
    10.0,
  )
  let detected = report.detect_regression()

  @test.assert_eq(detected.has_regression, true)
  @test.assert_eq(detected.regression_details.length() > 0, true)
}

///|
/// 测试回归检测（平均值增加）
test "regression detected - avg increase" {
  let current_stats = BenchmarkStats::new(
    100L, 200L, 200.0, 140L, 180L, 190L, 10, 1500L,
  )
  let last_stats = Some(
    BenchmarkStats::new(100L, 200L, 150.0, 140L, 180L, 190L, 10, 1500L),
  )

  let report = RegressionReport::new(
    "test_scenario",
    current_stats,
    last_stats,
    None,
    10.0,
  )
  let detected = report.detect_regression()

  @test.assert_eq(detected.has_regression, true)
  @test.assert_eq(detected.regression_details.length() > 0, true)
}

///|
/// 测试回归检测（最大值增加）
test "regression detected - max increase" {
  let current_stats = BenchmarkStats::new(
    100L, 300L, 150.0, 140L, 180L, 190L, 10, 1500L,
  )
  let last_stats = Some(
    BenchmarkStats::new(100L, 200L, 150.0, 140L, 180L, 190L, 10, 1500L),
  )

  let report = RegressionReport::new(
    "test_scenario",
    current_stats,
    last_stats,
    None,
    10.0,
  )
  let detected = report.detect_regression()

  @test.assert_eq(detected.has_regression, true)
  @test.assert_eq(detected.regression_details.length() > 0, true)
}

///|
/// 测试与中位数比较
test "regression vs median" {
  let current_stats = BenchmarkStats::new(
    100L, 200L, 150.0, 140L, 200L, 190L, 10, 1500L,
  )
  let median_stats = Some(
    BenchmarkStats::new(100L, 200L, 150.0, 140L, 150L, 190L, 10, 1500L),
  )

  let report = RegressionReport::new(
    "test_scenario",
    current_stats,
    None,
    median_stats,
    10.0,
  )
  let detected = report.detect_regression()

  @test.assert_eq(detected.has_regression, true)
  @test.assert_eq(detected.regression_details.length() > 0, true)
}

///|
/// 测试 Markdown 报告生成
test "Markdown report generation" {
  let stats = BenchmarkStats::new(
    100L, 200L, 150.0, 140L, 180L, 190L, 10, 1500L,
  )
  let report = RegressionReport::new("test_scenario", stats, None, None, 10.0)

  let markdown = report.to_markdown()
  @test.assert_eq(
    markdown.contains("## Regression Report: test_scenario"),
    true,
  )
  @test.assert_eq(markdown.contains("### Current Results"), true)
  @test.assert_eq(markdown.contains("### Regression Analysis"), true)
}

///|
/// 测试 compare_with_history
test "compare_with_history" {
  let current_stats = BenchmarkStats::new(
    100L, 200L, 150.0, 140L, 180L, 190L, 10, 1500L,
  )

  // 创建历史结果
  let history : Array[BenchmarkResult] = []
  history.push(BenchmarkResult::new("scenario1", current_stats))

  let report = compare_with_history(current_stats, history, 10.0)
  @test.assert_eq(report.scenario_name, "unknown")
  @test.assert_eq(report.current_stats, current_stats)
}
