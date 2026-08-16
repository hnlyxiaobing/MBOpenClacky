/// # diff-harness 回归测试：known-failure 机制
///
/// 本包（test/diff）承载从 diff-harness（D:/MoonBit/diff-harness）迁移的
/// 单元级差分用例。期望值已从 Ruby 版 openclacky 的实测运行记录冻结为字面量，
/// 测试不依赖 Ruby 存在。
///
/// ## known-failure 约定
///
/// 对应未修复 BUG 的用例不能直接进入回归套件（会永远红）。
/// 处理方式：用 `known_failure("BUG-NNNN")` 闸门隔离——编号在册则跳过断言；
/// 修复对应 BUG 后，把编号从 `known_failure_bug_ids` 中移除，断言即生效，
/// 测试转绿完成闭环。
///
/// 纪律（来自 diff-harness AGENTS.md）：
/// - known-failure 用例必须与 BUG 编号一一对应，禁止无编号隔离。
/// - 每个 known-failure 测试的注释必须引用 BUG 编号与 diff-harness 证据路径。
/// - 修复 commit 必须引用 BUG 编号，并同步移除本文件中的对应编号。
///
/// BUG 台账：diff-harness/reports/BUGS.md（BUG-0001~0043，四位编号）。
/// 注意：本仓库 lib/web、lib/tui 另有 BUG-001~027 等三位编号体系，互不相关。

///|
/// 当前在册的 known-failure BUG 编号（未修复，对应断言被跳过）。
/// 修复后从此数组移除编号即完成闭环；本数组清零是 P5 修复阶段的验收条件之一。
let known_failure_bug_ids : Array[String] = [
  // B 类冻结条目（P2.5 冻结，证据基于旧基线，修复前需重新验证）
  "BUG-0002", // write "." 路径应报 "Is a directory"
   "BUG-0003", // write 空路径错误消息不一致
   "BUG-0005", // expand_path 不解析 ~user（与 BUG-0008 同根因）
   "BUG-0006", // OpenAiStreamAggregator 缺 frames_seen/bytes_seen/approximate_output_tokens/parse_failures/saw_done
  // BUG-0007 已转 needs-investigation（台账与实测证据矛盾，见 BUGS.md 2026-08-14 修订），
  // 当前无断言挂该编号，不在册
   "BUG-0008", // expand_path 不解析 ~user（同 BUG-0005）
   "BUG-0009", // token 估算不区分 CJK 字符
   "BUG-0010", // tool_calls 估算多加 50 tokens
   "BUG-0011", // 溢出恢复拆散 tool pair
  // config_cli 模块（P2）
   "BUG-0012", // max_tokens 不从配置文件加载
   "BUG-0013", // anthropic_format 默认值不一致
   "BUG-0014", // current_model_id 未自动设置
   "BUG-0015", // CLACKY_* 环境变量覆盖行为不一致
   "BUG-0020", // switch_model_by_id 失败时 current_model 行为不一致
   "BUG-0022", // 保存后加载 max_tokens 不一致（同根因 BUG-0012）
  // error_retry 模块（P2）
   "BUG-0023", // 退避算法不一致（ruby 固定 5s vs MB 指数退避）
   "BUG-0024", // 402 错误分类不一致
  // BUG-0025/0026 已于基线实现（react 层空响应/thinking 静默重试，台账记录过时），
  // retry-013/014 为绿断言，不在册
   "BUG-0028", // context overflow 恢复后未调压缩
   "BUG-0029", // context overflow 激进模式无 pop 上限
   "BUG-0031", // 平台 HTTP failover 域名数不一致
  // link 层（P3，test/e2e 剧本用）
   "BUG-0032", // stream_cut 断流不重试，截断响应当最终答案
   "BUG-0037", // HTTP 5xx/429 退避策略不一致（指数退避 vs 固定 5s）
   "BUG-0038", // 连续失败时 system prompt 中途切换
   "BUG-0039", // 熔断行为不一致（15 请求 exit=-1 vs 11 请求 exit=1）
   "BUG-0040", // 工具错误 tool_result 非标准 JSON
   "BUG-0041", // MBOPENCLACKY_COMPRESSION_THRESHOLD 不被 env overlay 读取
   "BUG-0042", // needs_compression 语义/recent 守卫未对齐
  // BUG-0043 已修复（基线 commit 8f4381e，compressor.mbt:141-148 已有 10% 检查，
  // lib/agent 339/339 绿），移出注册表
  // P5 新登记（详见 diff-harness reports/BUGS.md BUG-0044 起）
   "BUG-0044", // edit 缺 Ruby 分层匹配回退（edit-008/009/010）
   "BUG-0045", // edit 缺 new_string 静默删除（edit-018）
   "BUG-0046", // edit 非法 UTF-8 panic（edit-019，闸门内不得执行真实调用）
   "BUG-0047", // write 不支持嵌套目录创建（write-003/006）
   "BUG-0048", // 图片 token 估算差异（token-008）
   "BUG-0049", // 摘要 token 钳制公式差异（token-027）
   "BUG-0050", // 关键信息提取规则差异（token-028）
   "BUG-0052", // CLACKY_ANTHROPIC_FORMAT 未读取（config-019）
]

///|
/// 判断某个 BUG 是否处于 known-failure 状态（未修复、断言应跳过）。
/// 用法：`if known_failure("BUG-0007") { return }`
pub fn known_failure(bug_id : String) -> Bool {
  known_failure_bug_ids.contains(bug_id)
}
