///|
/// BenchmarkStats - 基准测试统计结果
pub struct BenchmarkStats {
  min_ms : Int64
  max_ms : Int64
  avg_ms : Double
  p50_ms : Int64
  p95_ms : Int64
  p99_ms : Int64
  iterations : Int
  total_ms : Int64
}

///|
/// 创建新的 BenchmarkStats
pub fn BenchmarkStats::new(
  min_ms : Int64,
  max_ms : Int64,
  avg_ms : Double,
  p50_ms : Int64,
  p95_ms : Int64,
  p99_ms : Int64,
  iterations : Int,
  total_ms : Int64
) -> BenchmarkStats {
  { min_ms, max_ms, avg_ms, p50_ms, p95_ms, p99_ms, iterations, total_ms }
}

///|
/// 计算统计信息
pub fn BenchmarkStats::from_samples(samples : Array[Int64]) -> BenchmarkStats {
  if samples.length() == 0 {
    return { min_ms: 0L, max_ms: 0L, avg_ms: 0.0, p50_ms: 0L, p95_ms: 0L, p99_ms: 0L, iterations: 0, total_ms: 0L }
  }
  
  // 排序样本用于分位数计算
  let sorted = samples.copy()
  sorted.sort()
  
  let min_ms = sorted[0]
  let max_ms = sorted[sorted.length() - 1]
  
  // 计算平均值
  let mut total = 0L
  for i = 0; i < sorted.length(); i = i + 1 {
    total = total + sorted[i]
  }
  let avg_ms = total.to_double() / sorted.length().to_double()
  
  // 计算分位数
  let p50_index = (sorted.length() * 50) / 100
  let p95_index = (sorted.length() * 95) / 100
  let p99_index = (sorted.length() * 99) / 100
  
  let p50_ms = sorted[p50_index]
  let p95_ms = sorted[p95_index]
  let p99_ms = sorted[p99_index]
  
  { min_ms, max_ms, avg_ms, p50_ms, p95_ms, p99_ms, iterations: sorted.length(), total_ms: total }
}

///|
/// 生成 Markdown 报告
pub fn BenchmarkStats::to_markdown(self : BenchmarkStats, scenario_name : String) -> String {
  "## Benchmark: " + scenario_name + "\n" +
  "- Iterations: " + self.iterations.to_string() + "\n" +
  "- Total time: " + self.total_ms.to_string() + "ms\n" +
  "- Min: " + self.min_ms.to_string() + "ms\n" +
  "- Max: " + self.max_ms.to_string() + "ms\n" +
  "- Avg: " + self.avg_ms.to_string() + "ms\n" +
  "- P50: " + self.p50_ms.to_string() + "ms\n" +
  "- P95: " + self.p95_ms.to_string() + "ms\n" +
  "- P99: " + self.p99_ms.to_string() + "ms\n"
}

///|
/// 实现 Eq trait
impl Eq for BenchmarkStats with equal(self : BenchmarkStats, other : BenchmarkStats) -> Bool {
  self.min_ms == other.min_ms &&
  self.max_ms == other.max_ms &&
  self.avg_ms == other.avg_ms &&
  self.p50_ms == other.p50_ms &&
  self.p95_ms == other.p95_ms &&
  self.p99_ms == other.p99_ms &&
  self.iterations == other.iterations &&
  self.total_ms == other.total_ms
}

///|
/// 实现 Debug trait
impl Debug for BenchmarkStats with to_repr(self : BenchmarkStats) -> Repr {
  Repr::string("BenchmarkStats(" +
    "min_ms=" + self.min_ms.to_string() +
    ", max_ms=" + self.max_ms.to_string() +
    ", avg_ms=" + self.avg_ms.to_string() +
    ", p50_ms=" + self.p50_ms.to_string() +
    ", p95_ms=" + self.p95_ms.to_string() +
    ", p99_ms=" + self.p99_ms.to_string() +
    ", iterations=" + self.iterations.to_string() +
    ", total_ms=" + self.total_ms.to_string() +
    ")")
}