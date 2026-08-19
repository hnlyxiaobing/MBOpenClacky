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
  // BUG-0009/0010 已修复（spec 2026-08-18_05_p5-token-estimation-alignment.md：
  // token 估算分桶公式 + tool_calls 去 +50），移出注册表
   "BUG-0011", // 溢出恢复拆散 tool pair（+50 根因已随 BUG-0010 修复，本体属 FU-09）
  // config_cli 模块（P2）
  // BUG-0012/0022 已裁决（spec 2026-08-18_12_p5-config-loading-alignment.md：
  // 决策 1 选项 B——Ruby CONFIG_SETTINGS_KEYS 与 to_yaml 双双遗漏 max_tokens，
  // 判为原版缺陷；MB 保留加载/保存，config-002/011 冻结 MB 行为），移出注册表
  // BUG-0013 已关闭（spec 2026-08-18_12：nil/false 语义等价，config-012 断言
  // 修正为 false），移出注册表
  // BUG-0014 已修复（spec 2026-08-18_12：from_toml 自动锚定 current_model_id），
  // 移出注册表
  // BUG-0015 已修复（spec 2026-08-18_07_p5-env-overlay-config-channel.md：
  // merge_config 改按 type 去重追加 env 模型），移出注册表
  // BUG-0020 已修复（spec 2026-08-18_12：switch_model_by_id 失败消息改
  // "model not found"），移出注册表
  // error_retry 模块（P2）
  // BUG-0023 已修复（spec 2026-08-18_08_p5-retry-backoff-circuit-breaker.md：
  // retry_delay_ms 固定 5000ms 对齐 Ruby sleep retry_delay），移出注册表
   "BUG-0024", // 402 错误分类不一致
  // BUG-0025/0026 已于基线实现（react 层空响应/thinking 静默重试，台账记录过时），
  // retry-013/014 为绿断言，不在册
   "BUG-0028", // context overflow 恢复后未调压缩
   "BUG-0029", // context overflow 激进模式无 pop 上限
   "BUG-0031", // 平台 HTTP failover 域名数不一致
  // link 层（P3，test/e2e 剧本用）
  // BUG-0032 已修复（spec 2026-08-18_02_p5-stream-truncation-retry-pipeline.md：
  // 流式缺 finish_reason / 空参数 tool_call 判截断并走重试管道），移出注册表
  // BUG-0037 已修复（spec 2026-08-18_08：retry_delay_ms 固定 5s，009 剧本
  // 退避间隔断言转绿），移出注册表
   "BUG-0038", // 连续失败时 system prompt 中途切换
  // BUG-0039 已修复（spec 2026-08-18_08：013 的"15 请求"系 diff-harness 记录
  // 污染——req_0009+ 为 014 场景进程误写入；真实根因是指数退避拖垮 300s 超时。
  // 退避固定 5s 后 11 请求干净 exit=1，e2e 013 转绿），移出注册表
   "BUG-0040", // 工具错误 tool_result 非标准 JSON
  // BUG-0041 已修复（spec 2026-08-18_07_p5-env-overlay-config-channel.md：
  // apply_env_overlay 读取 MBOPENCLACKY_COMPRESSION_THRESHOLD），移出注册表
  // BUG-0042 已修复（spec 2026-08-18_09_p5-compression-trigger-semantics.md：
  // needs_compression 取 max(previous_total_tokens, estimate) + recent 守卫对
  // >2000 字符 tool_result 放行；005 e2e 转绿），移出注册表
  // BUG-0043 已修复（基线 commit 8f4381e，compressor.mbt:141-148 已有 10% 检查，
  // lib/agent 339/339 绿），移出注册表
  // P5 新登记（详见 diff-harness reports/BUGS.md BUG-0044 起）
   "BUG-0044", // edit 缺 Ruby 分层匹配回退（edit-008/009/010）
   "BUG-0045", // edit 缺 new_string 静默删除（edit-018）
   "BUG-0046", // edit 非法 UTF-8 panic（edit-019，闸门内不得执行真实调用）
   "BUG-0047", // write 不支持嵌套目录创建（write-003/006）
  // BUG-0048/0049/0050 已修复（spec 2026-08-18_05_p5-token-estimation-alignment.md：
  // 图片块计 0 + 钳制公式对齐 + 关键信息提取对齐 driver 简化语义），移出注册表
  // BUG-0052 已修复（spec 2026-08-18_07_p5-env-overlay-config-channel.md：
  // try_load_with_prefix 读取 <prefix>_ANTHROPIC_FORMAT），移出注册表
]

///|
/// 判断某个 BUG 是否处于 known-failure 状态（未修复、断言应跳过）。
/// 用法：`if known_failure("BUG-0007") { return }`
pub fn known_failure(bug_id : String) -> Bool {
  known_failure_bug_ids.contains(bug_id)
}
