///|
/// RegressionReport - 回归检测报告
pub struct RegressionReport {
  scenario_name : String
  current_stats : BenchmarkStats
  last_stats : BenchmarkStats?
  median_stats : BenchmarkStats?
  has_regression : Bool
  regression_details : Array[String]
  threshold_pct : Double
}

///|
/// 创建新的 RegressionReport
pub fn RegressionReport::new(
  scenario_name : String,
  current_stats : BenchmarkStats,
  last_stats : BenchmarkStats?,
  median_stats : BenchmarkStats?,
  threshold_pct : Double,
) -> RegressionReport {
  let has_regression = false
  let regression_details : Array[String] = []

  {
    scenario_name,
    current_stats,
    last_stats,
    median_stats,
    has_regression,
    regression_details,
    threshold_pct,
  }
}

///|
/// 检测回归
pub fn RegressionReport::detect_regression(
  self : RegressionReport,
) -> RegressionReport {
  let mut has_regression = false
  let regression_details : Array[String] = []

  // 与最后一次结果比较
  match self.last_stats {
    Some(last) => {
      // 检查 p95 回归
      let p95_increase = (self.current_stats.p95_ms - last.p95_ms).to_double() /
        last.p95_ms.to_double() *
        100.0
      if p95_increase > self.threshold_pct {
        has_regression = true
        regression_details.push(
          "P95 increased by " +
          p95_increase.to_string() +
          "% (current: " +
          self.current_stats.p95_ms.to_string() +
          "ms, last: " +
          last.p95_ms.to_string() +
          "ms)",
        )
      }

      // 检查平均值回归
      let avg_increase = (self.current_stats.avg_ms - last.avg_ms) /
        last.avg_ms *
        100.0
      if avg_increase > self.threshold_pct {
        has_regression = true
        regression_details.push(
          "Average increased by " +
          avg_increase.to_string() +
          "% (current: " +
          self.current_stats.avg_ms.to_string() +
          "ms, last: " +
          last.avg_ms.to_string() +
          "ms)",
        )
      }

      // 检查最大值回归
      let max_increase = (self.current_stats.max_ms - last.max_ms).to_double() /
        last.max_ms.to_double() *
        100.0
      if max_increase > self.threshold_pct {
        has_regression = true
        regression_details.push(
          "Max increased by " +
          max_increase.to_string() +
          "% (current: " +
          self.current_stats.max_ms.to_string() +
          "ms, last: " +
          last.max_ms.to_string() +
          "ms)",
        )
      }
    }
    None => ()
  }

  // 与中位数比较
  match self.median_stats {
    Some(median) => {
      // 检查 p95 回归
      let p95_increase = (self.current_stats.p95_ms - median.p95_ms).to_double() /
        median.p95_ms.to_double() *
        100.0
      if p95_increase > self.threshold_pct {
        has_regression = true
        regression_details.push(
          "P95 increased by " +
          p95_increase.to_string() +
          "% vs median (current: " +
          self.current_stats.p95_ms.to_string() +
          "ms, median: " +
          median.p95_ms.to_string() +
          "ms)",
        )
      }

      // 检查平均值回归
      let avg_increase = (self.current_stats.avg_ms - median.avg_ms) /
        median.avg_ms *
        100.0
      if avg_increase > self.threshold_pct {
        has_regression = true
        regression_details.push(
          "Average increased by " +
          avg_increase.to_string() +
          "% vs median (current: " +
          self.current_stats.avg_ms.to_string() +
          "ms, median: " +
          median.avg_ms.to_string() +
          "ms)",
        )
      }
    }
    None => ()
  }

  { ..self, has_regression, regression_details }
}

///|
/// 生成 Markdown 报告
pub fn RegressionReport::to_markdown(self : RegressionReport) -> String {
  let lines : Array[String] = []
  lines.push("## Regression Report: " + self.scenario_name)
  lines.push("")
  lines.push("### Current Results")
  lines.push(self.current_stats.to_markdown("Current"))
  lines.push("")

  match self.last_stats {
    Some(last) => {
      lines.push("### Last Results")
      lines.push(last.to_markdown("Last"))
      lines.push("")
    }
    None => {
      lines.push("### Last Results")
      lines.push("No previous results found")
      lines.push("")
    }
  }

  match self.median_stats {
    Some(median) => {
      lines.push("### Median Results")
      lines.push(median.to_markdown("Median"))
      lines.push("")
    }
    None => {
      lines.push("### Median Results")
      lines.push("No historical results found")
      lines.push("")
    }
  }

  lines.push("### Regression Analysis")
  lines.push("- Threshold: " + self.threshold_pct.to_string() + "%")
  lines.push(
    "- Regression detected: " + (if self.has_regression { "YES" } else { "NO" }),
  )

  if self.has_regression {
    lines.push("")
    lines.push("#### Regression Details")
    for detail in self.regression_details {
      lines.push("- " + detail)
    }
  }

  lines.join("\n")
}

///|
/// 比较当前结果与历史结果
pub fn compare_with_history(
  current_stats : BenchmarkStats,
  history : Array[BenchmarkResult],
  threshold_pct : Double,
) -> RegressionReport {
  let scenario_name = "unknown"
  let mut last_stats : BenchmarkStats? = None
  let mut median_stats : BenchmarkStats? = None

  if history.length() > 0 {
    // 按时间戳排序，获取最新的结果
    let sorted_history = history.copy()
    sorted_history.sort_by(fn(a, b) { a.timestamp.compare(b.timestamp) })
    last_stats = Some(sorted_history[sorted_history.length() - 1].stats)

    // 计算中位数
    let samples : Array[Int64] = []
    for result in history {
      samples.push(result.stats.p95_ms)
    }
    if samples.length() > 0 {
      let sorted_samples = samples.copy()
      sorted_samples.sort()
      let median_index = sorted_samples.length() / 2
      let median_p95 = sorted_samples[median_index]

      // 使用中位数 p95 创建一个代表性的统计信息
      median_stats = Some({
        min_ms: 0L,
        max_ms: 0L,
        avg_ms: 0.0,
        p50_ms: 0L,
        p95_ms: median_p95,
        p99_ms: 0L,
        iterations: 0,
        total_ms: 0L,
      })
    }
  }

  let report = RegressionReport::new(
    scenario_name, current_stats, last_stats, median_stats, threshold_pct,
  )
  report.detect_regression()
}
