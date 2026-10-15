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
/// Percentage increase from `baseline` to `current`, or None when the baseline
/// carries no signal. Dividing by a zero baseline yields Infinity, which would
/// report a regression out of thin air, so such metrics are skipped.
fn pct_increase(current : Double, baseline : Double) -> Double? {
  guard baseline > 0.0 else { return None }
  Some((current - baseline) / baseline * 100.0)
}

///|
fn pct_increase_ms(current : Int64, baseline : Int64) -> Double? {
  pct_increase(current.to_double(), baseline.to_double())
}

///|
/// Append a regression detail when `increase` exceeds the threshold.
fn push_regression_detail(
  details : Array[String],
  metric : String,
  increase : Double?,
  threshold_pct : Double,
  current_ms : String,
  baseline_label : String,
  baseline_ms : String,
) -> Unit {
  match increase {
    None => ()
    Some(v) =>
      if v > threshold_pct {
        details.push(
          metric +
          " increased by " +
          v.to_string() +
          "% (current: " +
          current_ms +
          "ms, " +
          baseline_label +
          ": " +
          baseline_ms +
          "ms)",
        )
      }
  }
}

///|
/// 检测回归
pub fn RegressionReport::detect_regression(
  self : RegressionReport,
) -> RegressionReport {
  let regression_details : Array[String] = []
  let cur = self.current_stats

  // 与最后一次结果比较
  match self.last_stats {
    Some(last) => {
      push_regression_detail(
        regression_details,
        "P95",
        pct_increase_ms(cur.p95_ms, last.p95_ms),
        self.threshold_pct,
        cur.p95_ms.to_string(),
        "last",
        last.p95_ms.to_string(),
      )
      push_regression_detail(
        regression_details,
        "Average",
        pct_increase(cur.avg_ms, last.avg_ms),
        self.threshold_pct,
        cur.avg_ms.to_string(),
        "last",
        last.avg_ms.to_string(),
      )
      push_regression_detail(
        regression_details,
        "Max",
        pct_increase_ms(cur.max_ms, last.max_ms),
        self.threshold_pct,
        cur.max_ms.to_string(),
        "last",
        last.max_ms.to_string(),
      )
    }
    None => ()
  }

  // 与中位数比较
  match self.median_stats {
    Some(median) => {
      push_regression_detail(
        regression_details,
        "P95",
        pct_increase_ms(cur.p95_ms, median.p95_ms),
        self.threshold_pct,
        cur.p95_ms.to_string(),
        "median",
        median.p95_ms.to_string(),
      )
      push_regression_detail(
        regression_details,
        "Average",
        pct_increase(cur.avg_ms, median.avg_ms),
        self.threshold_pct,
        cur.avg_ms.to_string(),
        "median",
        median.avg_ms.to_string(),
      )
    }
    None => ()
  }

  {
    ..self,
    has_regression: regression_details.length() > 0,
    regression_details,
  }
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
/// Median of a non-empty sample (upper-middle element after sorting).
fn median_ms(samples : Array[Int64]) -> Int64 {
  let sorted = samples.copy()
  sorted.sort()
  sorted[sorted.length() / 2]
}

///|
fn median_avg(samples : Array[Double]) -> Double {
  let sorted = samples.copy()
  sorted.sort_by(fn(a, b) { if a < b { -1 } else if a > b { 1 } else { 0 } })
  sorted[sorted.length() / 2]
}

///|
/// 比较当前结果与历史结果
pub fn compare_with_history(
  scenario_name : String,
  current_stats : BenchmarkStats,
  history : Array[BenchmarkResult],
  threshold_pct : Double,
) -> RegressionReport {
  let mut last_stats : BenchmarkStats? = None
  let mut median_stats : BenchmarkStats? = None

  if history.length() > 0 {
    // 按时间戳排序，获取最新的结果
    let sorted_history = history.copy()
    sorted_history.sort_by(fn(a, b) { a.timestamp.compare(b.timestamp) })
    last_stats = Some(sorted_history[sorted_history.length() - 1].stats)

    // 每个指标各自取真实中位数：基线必须全部来自实测样本，
    // 任何伪造的 0 都会让比值变成无穷大而误报回归。
    let mins : Array[Int64] = []
    let maxs : Array[Int64] = []
    let avgs : Array[Double] = []
    let p50s : Array[Int64] = []
    let p95s : Array[Int64] = []
    let p99s : Array[Int64] = []
    let iters : Array[Int64] = []
    let totals : Array[Int64] = []
    for result in history {
      let s = result.stats
      mins.push(s.min_ms)
      maxs.push(s.max_ms)
      avgs.push(s.avg_ms)
      p50s.push(s.p50_ms)
      p95s.push(s.p95_ms)
      p99s.push(s.p99_ms)
      iters.push(s.iterations.to_int64())
      totals.push(s.total_ms)
    }
    median_stats = Some({
      min_ms: median_ms(mins),
      max_ms: median_ms(maxs),
      avg_ms: median_avg(avgs),
      p50_ms: median_ms(p50s),
      p95_ms: median_ms(p95s),
      p99_ms: median_ms(p99s),
      iterations: median_ms(iters).to_int(),
      total_ms: median_ms(totals),
    })
  }

  let report = RegressionReport::new(
    scenario_name, current_stats, last_stats, median_stats, threshold_pct,
  )
  report.detect_regression()
}

///|
/// BaselineReport - 基于显式基线的回归报告
pub struct BaselineReport {
  scenario_name : String
  current_stats : BenchmarkStats
  baseline_stats : BenchmarkStats
  threshold_pct : Double
  has_regression : Bool
  regression_ratio : Double
  top_slowest : Array[Int64]
}

///|
pub fn BaselineReport::to_markdown(self : BaselineReport) -> String {
  let lines : Array[String] = []
  lines.push("## Baseline Report: " + self.scenario_name)
  lines.push("")
  lines.push("- Threshold: " + self.threshold_pct.to_string() + "%")
  lines.push("- Baseline P95: " + self.baseline_stats.p95_ms.to_string() + "ms")
  lines.push("- Current P95: " + self.current_stats.p95_ms.to_string() + "ms")
  lines.push("- Ratio: " + self.regression_ratio.to_string())
  lines.push(
    "- Regression detected: " + (if self.has_regression { "YES" } else { "NO" }),
  )
  if self.top_slowest.length() > 0 {
    lines.push("")
    lines.push("### Top slowest iterations")
    for i = 0; i < self.top_slowest.length(); i = i + 1 {
      lines.push(
        "- #" +
        (i + 1).to_string() +
        ": " +
        self.top_slowest[i].to_string() +
        "ms",
      )
    }
  }
  lines.join("\n")
}

///|
/// 比较当前结果与显式基线（仅比较 P95）。
/// `samples` 用于打印诊断性的 top-3 最慢迭代。
pub fn compare_with_baseline(
  scenario_name : String,
  current_stats : BenchmarkStats,
  baseline_stats : BenchmarkStats,
  threshold_pct : Double,
  samples~ : Array[Int64] = [],
) -> BaselineReport {
  let ratio = if baseline_stats.p95_ms == 0L {
    1.0
  } else {
    current_stats.p95_ms.to_double() / baseline_stats.p95_ms.to_double()
  }
  let has_regression = ratio > 1.0 + threshold_pct / 100.0
  let sorted = samples.copy()
  sorted.sort_by(fn(a, b) { b.compare(a) })
  let top_slowest : Array[Int64] = []
  let n = if sorted.length() > 3 { 3 } else { sorted.length() }
  for i = 0; i < n; i = i + 1 {
    top_slowest.push(sorted[i])
  }
  {
    scenario_name,
    current_stats,
    baseline_stats,
    threshold_pct,
    has_regression,
    regression_ratio: ratio,
    top_slowest,
  }
}
