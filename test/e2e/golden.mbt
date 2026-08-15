///| 冻结的 golden 断言点 —— 从 diff-harness `runs/<scenario>/ruby/` 的 Ruby 侧

///| 基线产物提取（请求数、tool 调用序列、文件终态字面量、完成/退出语义）。

///|
/// 语义级断言而非逐字节比对：请求体格式差异（session context、latency 字段、
/// display_text 等）已登记为 BUG-0033~0035，不属于本测试的断言面。

///|
/// 基线可信度：11 个已执行剧本的 ruby 基线已核实完整可信；
/// 011（malformed_sse_chunk）从未执行，无基线，对应测试按纪律留空。

///|
/// 一个剧本的黄金断言点。
pub(all) struct Golden {
  /// 剧本名。
  scenario : String
  /// ruby 侧请求总数（runs/<scenario>/ruby/requests/ 下的 req_*.json 数）。
  request_count : Int
  /// ruby 侧完整 tool 调用名序列（按最后一个请求的累积历史提取）。
  /// 空数组表示该剧本不断言工具序列（010：ruby 的截断重试不留下 assistant
  /// 消息，两侧序列形状不同且无独立 BUG 编号，按任务书只断言其余维度）。
  tool_sequence : Array[String]
  /// ruby 侧工作目录文件终态 {相对路径: 内容字面量}（fs_after.json 与 fixture 核对）。
  final_files : Array[(String, String)]
  /// ruby 侧最终回复文本（剧本最后一步的 content 原文）。
  final_text : String
  /// ruby 侧退出语义：exit=0 ↔ true（对应 outcome.status == "success"）。
  expect_success : Bool
  /// 基线证据路径（diff-harness 仓库内）。
  evidence : String
}

///|
/// 按剧本名取冻结的 golden。
pub fn golden(name : String) -> Golden {
  match name {
    "001_read_edit_file" =>
      {
        scenario: name,
        request_count: 3,
        tool_sequence: ["file_reader", "edit"],
        final_files: [
          ("config.yaml", "server:\n  host: 0.0.0.0\n  port: 9090\n"),
        ],
        final_text: "已将 config.yaml 中的端口从 8080 改为 9090。",
        expect_success: true,
        evidence: "runs/001_read_edit_file/ruby/（3 请求，exit=0，fs_after config.yaml 37B）",
      }
    "002_stream_cut_retry" =>
      {
        scenario: name,
        request_count: 4,
        tool_sequence: ["read_file"],
        final_files: [("README.md", "# demo\n")],
        final_text: "文件已读取，任务完成。",
        expect_success: true,
        evidence: "runs/002_stream_cut_retry/ruby/（4 请求，exit=0，间隔 5.0s/5.0s 见 reports/p3/002_stream_cut_retry_diff.md）",
      }
    "003_multi_turn_tool_sequence" =>
      {
        scenario: name,
        request_count: 4,
        tool_sequence: ["file_reader", "edit", "file_reader"],
        final_files: [("app.conf", "[app]\ndebug=true\nverbose=true\n")],
        final_text: "已确认 debug 已设为 true。",
        expect_success: true,
        evidence: "runs/003_multi_turn_tool_sequence/ruby/（4 请求，exit=0，fs_after app.conf 30B）",
      }
    "004_parallel_tool_calls" =>
      {
        scenario: name,
        request_count: 2,
        tool_sequence: ["file_reader", "file_reader"],
        final_files: [("a.txt", "alpha\n"), ("b.txt", "beta\n")],
        final_text: "a.txt 与 b.txt 内容一致。",
        expect_success: true,
        evidence: "runs/004_parallel_tool_calls/ruby/（2 请求，exit=0，a.txt/b.txt 无变化）",
      }
    "005_compression_trigger" =>
      {
        scenario: name,
        request_count: 3,
        tool_sequence: ["file_reader"],
        // big.txt 内容 315000B，不断言全量字面量；测试里断言长度与前缀
        final_files: [],
        final_text: "big.txt 共 15000 行。",
        expect_success: true,
        evidence: "runs/005_compression_trigger/ruby/（3 请求，exit=0，req_0002 带压缩指令，big.txt 315000B 无变化）",
      }
    "008_http_429_retry_after" =>
      {
        scenario: name,
        request_count: 3,
        tool_sequence: ["read_file"],
        final_files: [("note.txt", "hello\n")],
        final_text: "文件内容是 hello，共 5 个字符。",
        expect_success: true,
        evidence: "runs/008_http_429_retry_after/ruby/（3 请求，exit=0，重试 1 次间隔 5.0s 见 reports/p3/008_diff.md）",
      }
    "009_http_500_retry" =>
      {
        scenario: name,
        request_count: 4,
        tool_sequence: ["read_file"],
        final_files: [("note.txt", "hello\n")],
        final_text: "文件内容是 hello，共 5 个字符。",
        expect_success: true,
        evidence: "runs/009_http_500_retry/ruby/（4 请求，exit=0，间隔 5.0s/5.0s 见 reports/p3/009_diff.md）",
      }
    "010_tool_call_args_truncated" =>
      {
        scenario: name,
        request_count: 3,
        tool_sequence: [],
        final_files: [("out.txt", "hello world")],
        final_text: "文件已写入。",
        expect_success: true,
        evidence: "runs/010_tool_call_args_truncated/ruby/（3 请求，exit=0，out.txt 11B；req_0002 为 ruby 截断重试注入 system hint）",
      }
    "012_finish_stop_with_tool_calls" =>
      {
        scenario: name,
        request_count: 2,
        tool_sequence: ["read_file"],
        final_files: [("note.txt", "hello\n")],
        final_text: "文件内容是 hello。",
        expect_success: true,
        evidence: "runs/012_finish_stop_with_tool_calls/ruby/（2 请求，exit=0）",
      }
    "013_consecutive_failures_circuit_breaker" =>
      {
        scenario: name,
        request_count: 11,
        tool_sequence: [],
        final_files: [("note.txt", "hello\n")],
        final_text: "",
        expect_success: false,
        evidence: "runs/013_consecutive_failures_circuit_breaker/ruby/（11 请求，exit=1 干净失败，见 BUG-0039）",
      }
    "014_tool_execution_failure_recovery" =>
      {
        scenario: name,
        request_count: 3,
        tool_sequence: ["read_file", "read_file"],
        final_files: [("note.txt", "hello\n")],
        final_text: "第二个文件读取成功，内容是 hello。",
        expect_success: true,
        evidence: "runs/014_tool_execution_failure_recovery/ruby/（3 请求，exit=0；req_0002 的 tool 错误为标准 JSON）",
      }
    _ => {
      println("FATAL: 无 golden 数据的剧本: \{name}")
      panic()
    }
  }
}
