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
  // BUG-0002 已修复（spec 2026-08-18_25：write is_dir 预检，"." 报
  // "Is a directory"，write_fuzz_1245 转绿），移出注册表
  // BUG-0003 已修复（spec 2026-08-18_25：空检查改 trim，纯空白路径报
  // "Path cannot be empty"，write_004 冻结期望按决策 2 修正后转绿），移出注册表
  // BUG-0005/BUG-0008 已修复（本 spec：~user 解析实现，对齐 Ruby 报错语义），移出注册表
  // BUG-0006 已修复（spec 2026-08-18_23：OpenAiStreamAggregator 补 frames_seen/
  // bytes_seen/parse_failures/saw_done/approximate_output_tokens，stream-005/007/
  // 011/012/013/019 统计断言转绿，移除闸门）
  // BUG-0007 已转 needs-investigation（台账与实测证据矛盾，见 BUGS.md 2026-08-14 修订），
  // 当前无断言挂该编号，不在册
  // BUG-0009/0010 已修复（spec 2026-08-18_05_p5-token-estimation-alignment.md：
  // token 估算分桶公式 + tool_calls 去 +50），移出注册表
  // BUG-0011 已修复（spec 2026-08-18_14_p5-overflow-recovery-tool-pairs.md：
  // pulled_back_messages 改回填方向对齐 Ruby driver，FU-06 修复后估算口径
  // 收敛 token-029 kept_count=4），移出注册表
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
  // BUG-0028 已修复（spec 2026-08-18_14_p5-overflow-recovery-tool-pairs.md：
  // handle_context_overflow pop 后调 compress_messages_if_needed；
  // 阶段 A 闭合 retry-017，阶段 B 生产接线另案），移出注册表
  // BUG-0029 已修复（spec 2026-08-18_14：Aggressive 钳制 [4, min(len-2, 64)]
  // 对齐 Ruby llm_caller.rb:535-549），移出注册表
   "BUG-0031", // 平台 HTTP failover 域名数不一致
  // link 层（P3，test/e2e 剧本用）
  // BUG-0032 已修复（spec 2026-08-18_02_p5-stream-truncation-retry-pipeline.md：
  // 流式缺 finish_reason / 空参数 tool_call 判截断并走重试管道），移出注册表
  // BUG-0037 已修复（spec 2026-08-18_08：retry_delay_ms 固定 5s，009 剧本
  // 退避间隔断言转绿），移出注册表
  // BUG-0038 已关闭（spec 2026-08-18_19：非产品缺陷——013 的"system prompt
  // 中途切换"系 diff-harness 记录污染，req_0009+ 为 ruby 进程 014 场景误写入；
  // 013 真实请求 prompt 逐字节一致。e2e 013 补 assert_system_prompt_stable
  // 回归断言），移出注册表
  // BUG-0039 已修复（spec 2026-08-18_08：013 的"15 请求"系 diff-harness 记录
  // 污染——req_0009+ 为 014 场景进程误写入；真实根因是指数退避拖垮 300s 超时。
  // 退避固定 5s 后 11 请求干净 exit=1，e2e 013 转绿），移出注册表
  // BUG-0040 已修复（spec 2026-08-18_24_p5-tool-result-json-format.md：
  // build_error_result / build_denied_result 改为 Json::object + stringify，
  // tool_result content 为标准 JSON；e2e 014 assert_tool_results_valid_json 生效），
  // 移出注册表
  // BUG-0041 已修复（spec 2026-08-18_07_p5-env-overlay-config-channel.md：
  // apply_env_overlay 读取 MBOPENCLACKY_COMPRESSION_THRESHOLD），移出注册表
  // BUG-0042 已修复（spec 2026-08-18_09_p5-compression-trigger-semantics.md：
  // needs_compression 取 max(previous_total_tokens, estimate) + recent 守卫对
  // >2000 字符 tool_result 放行；005 e2e 转绿），移出注册表
  // BUG-0043 已修复（基线 commit 8f4381e，compressor.mbt:141-148 已有 10% 检查，
  // lib/agent 339/339 绿），移出注册表
  // BUG-0044 已修复（spec 2026-08-18_26：分层匹配 trim/unescape/smart-line，
  // edit_008/009/010 转绿），移出注册表
  // BUG-0045 已修复（spec 2026-08-18_26：new_string 缺失报错而非静默删除，
  // edit_018 转绿），移出注册表
  // BUG-0046 已修复（spec 2026-08-18_26：UTF-8 清洗 + 安全 count_occurrences，
  // edit_019 转绿），移出注册表
  // P5 新登记（详见 diff-harness reports/BUGS.md BUG-0044 起）
  // BUG-0047 已修复（spec 2026-08-18_25：父目录创建换 @utils.ensure_dir
  // 递归创建，write-003/006 转绿），移出注册表
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
