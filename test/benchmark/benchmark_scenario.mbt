///|
/// BenchmarkScenario - 基准测试场景定义
pub struct BenchmarkScenario {
  /// 场景名称
  name : String
  /// 场景描述
  description : String
  /// 迭代次数
  iterations : Int
  /// 预热次数
  warmup : Int
  /// 并发数（暂不实现，保留字段）
  concurrency : Int
  /// 要执行的工具名称（如 "file_reader", "grep"）
  tool : String
  /// 传递给工具的参数
  parameters : Map[String, Json]
  /// 原始 JSON 内容（用于传递给 eval 框架）
  raw_json : String
}

///|
/// 从 JSON 字符串解析 BenchmarkScenario
pub fn BenchmarkScenario::from_json(json_str : String) -> BenchmarkScenario? {
  let json = @json.parse(json_str) catch { _ => return None }

  match json {
    Object(map) => {
      let name = match map.get("name") {
        Some(String(s)) => s
        _ => "unknown"
      }
      let description = match map.get("description") {
        Some(String(s)) => s
        _ => ""
      }
      let iterations = match map.get("iterations") {
        Some(Number(n, ..)) => n.to_int()
        _ => 10
      }
      let warmup = match map.get("warmup") {
        Some(Number(n, ..)) => n.to_int()
        _ => 3
      }
      let concurrency = match map.get("concurrency") {
        Some(Number(n, ..)) => n.to_int()
        _ => 1
      }
      let tool = match map.get("tool") {
        Some(String(s)) => s
        _ => ""
      }
      let parameters : Map[String, Json] = Map([])
      match map.get("parameters") {
        Some(Object(pm)) =>
          for key, value in pm {
            parameters[key] = value
          }
        _ => ()
      }

      Some({
        name,
        description,
        iterations,
        warmup,
        concurrency,
        tool,
        parameters,
        raw_json: json_str,
      })
    }
    _ => None
  }
}

///|
/// 返回只替换迭代/预热次数的场景副本，用于让 CLI 覆盖值生效。
pub fn BenchmarkScenario::with_counts(
  self : BenchmarkScenario,
  iterations : Int,
  warmup : Int,
) -> BenchmarkScenario {
  {
    name: self.name,
    description: self.description,
    iterations,
    warmup,
    concurrency: self.concurrency,
    tool: self.tool,
    parameters: self.parameters,
    raw_json: self.raw_json,
  }
}

///|
/// 加载目录中的所有 benchmark 场景
pub fn load_benchmark_scenarios(dir_path : String) -> Array[BenchmarkScenario] {
  let scenarios : Array[BenchmarkScenario] = []
  let json_texts = @eval.load_scenario_files(dir_path)

  for json_text in json_texts {
    match BenchmarkScenario::from_json(json_text) {
      Some(scenario) => scenarios.push(scenario)
      None => continue
    }
  }

  scenarios
}
