///|
/// BenchmarkResult - 可持久化的基准测试结果
pub struct BenchmarkResult {
  scenario_name : String
  timestamp : String
  stats : BenchmarkStats
  metadata : Map[String, String]
}

///|
/// 创建新的 BenchmarkResult
pub fn BenchmarkResult::new(
  scenario_name : String,
  stats : BenchmarkStats,
) -> BenchmarkResult {
  { scenario_name, timestamp: @agent.current_iso8601(), stats, metadata: {} }
}

///|
/// 将 BenchmarkResult 转换为 JSON 字符串
pub fn BenchmarkResult::to_json(self : BenchmarkResult) -> String {
  let stats_map : Map[String, Json] = Map([
    ("min_ms", Json::number(self.stats.min_ms.to_double())),
    ("max_ms", Json::number(self.stats.max_ms.to_double())),
    ("avg_ms", Json::number(self.stats.avg_ms)),
    ("p50_ms", Json::number(self.stats.p50_ms.to_double())),
    ("p95_ms", Json::number(self.stats.p95_ms.to_double())),
    ("p99_ms", Json::number(self.stats.p99_ms.to_double())),
    ("iterations", Json::number(self.stats.iterations.to_double())),
    ("total_ms", Json::number(self.stats.total_ms.to_double())),
  ])

  let metadata_map : Map[String, Json] = Map([])
  for key, value in self.metadata {
    metadata_map[key] = Json::string(value)
  }

  let result_map : Map[String, Json] = Map([
    ("scenario_name", Json::string(self.scenario_name)),
    ("timestamp", Json::string(self.timestamp)),
    ("stats", Json::object(stats_map)),
    ("metadata", Json::object(metadata_map)),
  ])

  Json::object(result_map).stringify()
}

///|
/// 从 JSON 字符串解析 BenchmarkResult
pub fn BenchmarkResult::from_json(json_str : String) -> BenchmarkResult? {
  let json = @json.parse(json_str) catch { _ => return None }

  match json {
    Object(map) => {
      let scenario_name = match map.get("scenario_name") {
        Some(String(s)) => s
        _ => "unknown"
      }
      let timestamp = match map.get("timestamp") {
        Some(String(s)) => s
        _ => ""
      }
      let stats = match map.get("stats") {
        Some(Object(stats_map)) => {
          let min_ms = match stats_map.get("min_ms") {
            Some(Number(n, ..)) => n.to_int64()
            _ => 0L
          }
          let max_ms = match stats_map.get("max_ms") {
            Some(Number(n, ..)) => n.to_int64()
            _ => 0L
          }
          let avg_ms = match stats_map.get("avg_ms") {
            Some(Number(n, ..)) => n
            _ => 0.0
          }
          let p50_ms = match stats_map.get("p50_ms") {
            Some(Number(n, ..)) => n.to_int64()
            _ => 0L
          }
          let p95_ms = match stats_map.get("p95_ms") {
            Some(Number(n, ..)) => n.to_int64()
            _ => 0L
          }
          let p99_ms = match stats_map.get("p99_ms") {
            Some(Number(n, ..)) => n.to_int64()
            _ => 0L
          }
          let iterations = match stats_map.get("iterations") {
            Some(Number(n, ..)) => n.to_int()
            _ => 0
          }
          let total_ms = match stats_map.get("total_ms") {
            Some(Number(n, ..)) => n.to_int64()
            _ => 0L
          }

          {
            min_ms,
            max_ms,
            avg_ms,
            p50_ms,
            p95_ms,
            p99_ms,
            iterations,
            total_ms,
          }
        }
        _ => BenchmarkStats::from_samples([])
      }
      let metadata = match map.get("metadata") {
        Some(Object(m)) => {
          let result : Map[String, String] = Map([])
          for key, value in m {
            match value {
              String(s) => result[key] = s
              _ => continue
            }
          }
          result
        }
        _ => {}
      }

      Some({ scenario_name, timestamp, stats, metadata })
    }
    _ => None
  }
}

///|
/// 保存 BenchmarkResult 到文件
pub fn save_result(
  result : BenchmarkResult,
  base_dir : String,
) -> Result[String, String] {
  let scenario_dir = @path.Path::join(
    base_dir,
    @path.Path(result.scenario_name),
  ).to_string()
  @utils.ensure_dir(scenario_dir)

  let filename = result.timestamp + ".json"
  let filepath = @path.Path::join(scenario_dir, @path.Path(filename)).to_string()

  let json_str = result.to_json()
  @fs.write_string_to_file(filepath, json_str) catch {
    e => return Err("Failed to write result file: \{@debug.to_string(e)}")
  }

  Ok(filepath)
}

///|
/// 加载指定场景的历史结果
pub fn load_history(
  scenario_name : String,
  base_dir : String,
) -> Array[BenchmarkResult] {
  let results : Array[BenchmarkResult] = []
  let scenario_dir = @path.Path::join(base_dir, @path.Path(scenario_name)).to_string()

  if !@fs.path_exists(scenario_dir) {
    return results
  }

  let entries = @fs.read_dir(scenario_dir) catch { _ => return results }
  for entry in entries {
    let filepath = @path.Path::join(scenario_dir, @path.Path(entry)).to_string()
    if filepath.has_suffix(".json") {
      let content = @fs.read_file_to_string(filepath) catch { _ => continue }
      match BenchmarkResult::from_json(content) {
        Some(result) => results.push(result)
        None => continue
      }
    }
  }

  results
}

///|
/// 加载所有场景的历史结果
pub fn load_all_history(
  base_dir : String,
) -> Map[String, Array[BenchmarkResult]] {
  let history : Map[String, Array[BenchmarkResult]] = Map([])

  if !@fs.path_exists(base_dir) {
    return history
  }

  let entries = @fs.read_dir(base_dir) catch { _ => return history }
  for entry in entries {
    let scenario_dir = @path.Path::join(base_dir, @path.Path(entry)).to_string()
    if @fs.path_exists(scenario_dir) {
      let results = load_history(entry, base_dir)
      if results.length() > 0 {
        history[entry] = results
      }
    }
  }

  history
}
