# 安全/注册表/执行器对齐（security + registry + executor，矩阵§2）· 增量 Spec

> **创建日期**: 2026-08-18  
> **状态**: 已通过对抗性审查（2026-08-18）· 已移入 `specs/active/`
> **关联总览**: `specs/active/2026-08-18_01_diff-harness-matrix-backlog-overview.md`；diff-harness `docs/FEATURE_MATRIX.md` §2（security/registry/executor 部分）  
> **关联历史 spec**: 无（矩阵旧台账编号已被 BUGS.md 覆盖，本 spec 一律使用 `矩阵§2/条目名` 锚点）；与 B3（terminal/misc 工具对齐）同属矩阵§2，边界：terminal/todo/trash/browser/web 工具本体归 B3，本 spec 只覆盖 security.mbt / registry.mbt / react.mbt / tool_executor.mbt  
> **来源差距**: P1 静态对齐矩阵（2026-08-12）§2 中 security/registry/executor 的 partial/missing 条目，2026-08-18 逐条对当前代码复核  
> **依赖**: 无硬依赖；与 S05（terminal 工具安全面既有 p5 spec）存在交叉，实施时若 S05 先合入需复核本 spec 决策 1 的落点  
> **灰度 key**: 无

## 问题描述 [必填]

矩阵§2 security/registry/executor 簇复核后确认以下分歧仍然成立（按严重度排序）：

1. **`is_pattern_match` 为字面子串查找，`make_safe` 整个拦截层失效（missing→实为错误实现，安全级）**：所有危险模式（sudo、pkill clacky、curl|sh、eval()、`$(...)` 等）均为正则形式，`text.find(正则字面串)` 永不命中——`make_safe` 对任何命令都原样放行。连锁后果：`command_safe_for_auto_execution` 的 make_safe 兜底分支恒返回 true，**ConfirmSafes 模式下非白名单命令（如 `rm -rf`）也被判定为可自动执行**。
2. **权限检查使用未解析的原始工具名，别名/大小写绕过确认（partial，安全级）**：`act_async` 用 `call.function.name` 原始名调用 `should_auto_execute`，而 `is_safe_operation` 只字面匹配 `"edit"/"write"/"terminal"`——模型输出 `"Write"`、`"EDIT"` 或别名时落入 `_ => true` 分支自动执行，随后 `execute_single_tool` 才做别名解析并照常执行。
3. **denied 后悬空 tool_calls（partial，协议级）**：`act_async` 在首个拒绝处 `break`，同一轮 assistant 消息中剩余 tool_calls 没有对应 tool_result；Anthropic 协议要求 assistant 的每个 tool_use 必须有配对 tool_result，下一轮请求将直接被服务端拒绝。且 denied 后 react_loop 直接 `build_result(Success)` 结束整个 run，不交还模型处置。
4. **伪 JSON 错误结果（partial）**：`build_error_result` 输出 `{error: <未引号未转义的消息>}`、`build_denied_result` 输出未引号键——不是合法 JSON，模型按 JSON 解析失败；error_message 内含引号/换行时进一步破坏结构。
5. **参数解析失败静默空 map、无 JSON 修复（partial）**：`parse_tool_arguments` 对非法 JSON / 非 Object 一律返回空 map，工具随后以"缺少参数"报错；Ruby 侧有 JSON 修复容错（截断/单引号/尾逗号等修复尝试）先于放弃。
6. **registry 无 sanitize_name（missing）**：模型输出的非法工具名（含空格/引号/多余前缀）无清洗步骤，直接进 resolve → Unknown tool。
7. **别名指向未注册工具（partial）**：`tool_aliases` 中 `undo→undo_task`、`redo→redo_task`、`tasks→list_tasks`、`task_history→list_tasks` 的目标均未注册，resolve 成功但 get 失败，报 "registered but not found" 误导文案。
8. **`allowed_definitions` "all" 语义收窄（partial）**：MB 要求 `"all"` 为数组唯一元素；Ruby 任意位置含 all 即全放行。
9. **`all_definitions` 遍历 Map 顺序不保证（partial）**：每轮请求的工具定义顺序可能不稳定（Ruby 为注册序），影响模型工具选择的可复现性与缓存命中。
10. **默认注册集差异（partial）**：`make_default_registry` 14 个工具，较 Ruby 多 `MemoryTool`/`TrashManager`（MB 超集扩展，裁决点）。
11. **TODO reminder 注入缺失（missing）**：Ruby 每轮将未完成 todos 以 system reminder 注入上下文督促模型维护任务清单；MB agent 无任何 reminder 注入。
12. **image_inject 旁路缺失（missing）**：`browser_screenshot.mbt` 输出字面量 `[image_inject]` 占位符，但全代码库无消费方——client 层已支持 data: URI 图片块，截图 base64 实际上被丢弃（与 B3 浏览器簇交接，本 spec 负责 executor→client 的注入链路定义，B3 负责截图侧产出）。
13. **security 杂项（partial/missing）**：无审计日志（Ruby security.rb 记录被拦截命令）；无 chmod +x 分支；`$(...)` 命令替换拦截为 MB 新增（Ruby 无，语义相反，裁决点）；sudo / curl|sh 处置语义与 Ruby 相反（Ruby 行号以矩阵§2 对应行为准，实施时逐条核对）；`safe_readonly_commands` 含偏宽 Windows 命令（`set` 可带赋值、`wmic` 可变更）。
14. **`validate_secret_write` 无生产调用方（missing，凭证保护整层悬空）**：仅 `security_wbtest.mbt` 引用；write/edit 工具路径均不经过它。
15. **`is_secret_path` 全路径小写子串匹配（partial）**：`.env` 子串可误伤合法路径（如 `release.env.bak`、含 `.env` 子串的目录名），Ruby 为文件名级模式匹配。

## 现状分析 [必填 - 含代码验证]

### 验证记录（2026-08-18，对当前 HEAD 复核）

| 声称 | 验证方式 | 结果 | 结论 |
|------|---------|------|------|
| is_pattern_match 字面子串 | 读 `lib/tool/security.mbt:191-195` | `text.find(pattern) is Some(_)`，模式含 `\b`/`\s+`/`.*` 正则元字符 | 证实（make_safe 全部拦截分支永不触发） |
| ConfirmSafes 兜底恒放行 | 读 `lib/tool/security.mbt:88-112` | 白名单未命中后 `make_safe` 恒返回原命令 → `trimmed == safe` → true | 证实（连锁放大条目 1） |
| 权限判定用原始名 | 读 `lib/agent/react.mbt:247-249` + `tool_executor.mbt:34-68` | `should_auto_execute(call.function.name, ...)`；`is_safe_operation` 仅字面三分支 | 证实 |
| denied 后 break 悬空 | 读 `lib/agent/react.mbt:243-246,380-394` | denied 即 break；observe 只注入已有结果；loop 直接结束 | 证实 |
| 伪 JSON | 读 `lib/agent/tool_executor.mbt:492-510` | `{error: \{msg}}` 无键引号无转义 | 证实 |
| 参数解析静默空 map | 读 `lib/agent/tool_executor.mbt:419-439` | catch → `Map([])`；非 Object → `Map([])` | 证实 |
| 无 sanitize_name | Grep `sanitize` 全库 + 读 `registry.mbt:114-148` | 仅连字符→下划线归一 | 证实 |
| 4 条悬空别名 | 读 `lib/tool/registry.mbt:67-70` + `make_default_registry:256-273` | undo_task/redo_task/list_tasks 均未注册 | 证实 |
| "all" 唯一元素 | 读 `lib/tool/registry.mbt:200-214` | `tools.length() == 1 && tools[0] == "all"` | 证实 |
| all_definitions 顺序 | 读 `lib/tool/registry.mbt:183-191` | 遍历 `Map[String, AnyTool]` | 证实（Map 遍历序非注册序） |
| 默认注册集 14 vs 12 | 读 `lib/tool/registry.mbt:256-273` | 多出 MemoryTool/TrashManager | 证实 |
| TODO reminder 缺失 | Grep `reminder` lib/agent | 0 匹配 | 证实 |
| image_inject 无消费方 | Grep `image_inject` 全库 | 仅 `browser_screenshot.mbt` 产出侧 4 处字面量；client 层（format_anthropic/bedrock）支持 data: URI 但无人喂入 | 证实 |
| validate_secret_write 无调用方 | Grep 全库 | 仅 security_wbtest.mbt 引用 | 证实 |
| .env 全路径子串 | 读 `lib/tool/security.mbt:34-41,117-126` | `lower.find(".env")` | 证实 |
| 无审计日志 | 读 security.mbt 全文 | 无任何日志输出 | 证实 |
| 80K 截断 | 读 `lib/agent/tool_executor.mbt:444-474` | 行为存在、文案待与 Ruby 逐字核对 | 部分证实（文案差异列为实施时核对项） |

Ruby 参照（openclacky，只读）：`lib/clacky/tools/security.rb`、`lib/clacky/tools/registry.rb`、`lib/clacky/agent/tool_executor.rb`、`lib/clacky/agent.rb`（reminder 注入点）。矩阵各行 ruby 行号在 P1 阶段已核对，实施任务包内按函数再核对。

### 影响面

条目 1+2 叠加意味着 ConfirmSafes 模式的"人在环"保护在 MB 侧实际形同虚设（正则拦截全失效 + 别名绕过），是本批 12 份 spec 中安全严重度最高的簇。条目 3 会导致多工具轮次中一旦有拒绝即下一轮请求协议报错，直接打断会话。

## 决策 [必填 - 含为什么]

1. **决策 1（最高优先）**：`is_pattern_match` 替换为真正的正则匹配。选型与 B1 决策 1 共用结论（B1 任务包 0 的 MoonBit regex 调研结果为准）；security 所需模式面为：`\b` 词界、`\s+`、`^` 锚点、`(...|...)` 分组、`[^x]+` 否定字符类、`.*`——以该子集定义依赖选型边界。修复后 `make_safe` 的拦截链自动恢复，`command_safe_for_auto_execution` 的兜底语义随之正确。
   - **为什么**：这是唯一一处"实现与函数注释/设计意图完全相反"的缺陷，且连锁放大权限面；不存在"保留字面子串"的合理方案。
2. **决策 2**：权限判定改为**先解析后判定**：`act_async`/`execute_single_tool` 中先经 registry resolve 得到 canonical 名，`is_safe_operation` 对 canonical 名判定；同时 `is_safe_operation` 的大小写归一由 resolve 天然覆盖。
   - **为什么**：判定对象必须是"将要执行的工具"而非"模型写的字符串"；这是别名机制存在的前提义务。
3. **决策 3**：denied 语义对齐 Ruby：被拒工具产出 denied 结果后**继续处理剩余 tool_calls**（逐个询问或按 Ruby 策略），保证 assistant 消息的每个 tool_use 都有配对 tool_result；denied 不再直接终止 run，将拒绝结果交还模型处置（Ruby 语义以矩阵行为准实施时核对）。
   - **为什么**：协议不变式（tool_use/tool_result 配对）优先于任何便利性；同时避免"一次拒绝杀死整轮任务"。
4. **决策 4**：结果构造器输出合法 JSON：`build_error_result`/`build_denied_result` 用 `@json` 构造（键值引号与转义由序列化保证）；对 error_message 不做手工拼接。
   - **为什么**：工具结果会被模型按 JSON 解析（schema 约定），手工拼接在含引号消息时必然产生畸形输出。
5. **决策 5**：`parse_tool_arguments` 增加 JSON 修复容错层（对齐 Ruby：常见模型输出缺陷——单引号、尾逗号、未闭合截断的有限修复尝试），修复失败返回显式 parse-error 结果而非空 map，并在工具结果中说明"arguments 无法解析"，与"缺少参数"区分。
   - **为什么**：空 map 把协议层错误转嫁为工具层错误，模型得到误导性的修复方向。
6. **决策 6**：registry 增加 `sanitize_name`（对齐 Ruby 清洗规则：剥离引号/空白/多余装饰后再进 resolve）；删除 4 条悬空别名或补齐目标工具（**裁决点**：undo/redo/list_tasks 功能是否立项，若不立项则删别名并在 Unknown tool 错误中列出可用工具）。
   - **为什么**：悬空别名产出"registered but not found"的自相矛盾错误，是模型困惑与重试浪费的来源。
7. **决策 7**：`allowed_definitions` 放宽为"任意位置含 all 即全放行"；工具定义输出顺序改为**注册序**（registry 内部维护注册序数组，Map 仅做索引）。
   - **为什么**：对齐 Ruby 语义；工具定义顺序稳定是请求缓存与差分测试可复现的前提。
8. **决策 8**：TODO reminder 注入按 Ruby 语义移植（每轮 think 前将未完成 todos 以 system reminder 形式注入，带频控/去重规则，以 Ruby 实现为准）。
   - **为什么**：reminder 是 Ruby 侧任务完成率的关键机制之一（P4 基准口径内），缺失直接造成能力面落差。
9. **决策 9**：image_inject 链路：定义消息级旁路字段（复用 `@message.Message` 现有附件/图片承载方式），executor 在收到含 `[image_inject]` 标记的工具结果时将 base64 载荷挂到下一条请求的 user/tool_result 图片块（client 层 data: URI 支持已具备）；产出侧 base64 保留由 B3 负责。
   - **为什么**：截图是浏览器工具的核心价值，占位符无消费方等于功能整体不存在。
10. **决策 10**：`validate_secret_write` 接入 write/edit 工具执行路径（S10/S16 实施时同步接入，本 spec 提供接入点与语义）；`is_secret_path` 改为文件名级匹配（basename 与路径段匹配，消除全路径子串误伤）。
    - **为什么**：凭证保护是设计意图，无调用方等于未实现。
11. **决策 11（裁决点组）**：以下逐条对照 Ruby 后裁决，默认"以 Ruby 为准"：sudo / curl|sh 处置语义（MB 硬拦截 vs Ruby 原语义）；`$(...)` 拦截是否保留为 MB 超集；审计日志按 Ruby 范围补齐；chmod +x 分支按 Ruby 补齐；Windows 白名单剔除 `set`（可赋值）并复核 `wmic`；默认注册集中 MemoryTool/TrashManager 作为 MB 超集保留（先例：BUG-0016~0019 裁决原则——超集功能不删除，但需文档注明）。
    - **为什么**：安全面语义反转必须有显式裁决记录，不能静默保留。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tool/security.mbt` | 修改 | 正则匹配接入、secret 路径文件名级匹配、审计日志、白名单收敛、chmod 分支 |
| `lib/tool/security_wbtest.mbt` | 修改 | 每条拦截模式的正/反用例（修复后拦截首次真正生效，需防回归） |
| `lib/tool/registry.mbt` | 修改 | sanitize_name、悬空别名处置、"all" 语义、注册序输出 |
| `lib/tool/registry_wbtest.mbt`（若不存在则新建） | 新建/修改 | resolve 链、allowed_definitions、顺序稳定性用例 |
| `lib/agent/react.mbt` | 修改 | 先解析后判定、denied 继续配对、TODO reminder 注入、image_inject 挂载点 |
| `lib/agent/tool_executor.mbt` | 修改 | JSON 结果构造、参数解析修复层、is_safe_operation 判 canonical、image_inject 解析挂载 |
| `lib/message/message.mbt` | 修改 | 新增 `Message::user_blocks`（带 Blocks 的 user 消息构造，`system_injected: Some(true)`） |
| `lib/agent/agent_wbtest.mbt`（或对应 wbtest） | 修改/新建 | 别名权限、denied 配对、伪 JSON、reminder 用例 |

### 不涉及文件

- terminal/todo/trash/browser/web 工具本体（B3）；截图 base64 产出侧保留（B3）；请求格式面（tool_result 合并等属 B4）；write/edit 工具本体（S10/S16，本 spec 只提供 `validate_secret_write` 接入点）。

## 实施计划 [必填]

### 任务包 0：依赖与实证（预估 0.5 天）
1. 复用 B1 任务包 0 的 MoonBit regex 调研结论（若 B1 未先行，本任务包自行调研并记录）。
2. 写探针实证：ConfirmSafes 模式下 `rm -rf x` 当前被自动放行（静态结论转运行实证）。
3. 逐函数核对 Ruby 参照（security.rb / registry.rb / tool_executor.rb / agent.rb reminder 段）。

### 任务包 1：security 拦截面修复（预估 1 天）
1. `is_pattern_match` 正则实现接入；全部拦截模式回归用例。
2. secret 路径文件名级匹配 + `validate_secret_write` 接入点暴露；审计日志；白名单收敛；chmod 分支。
3. wbtest：每条模式"应拦截命令被拦"、"合法命令不误伤"双向用例。

### 任务包 2：registry + 权限链（预估 1 天）
1. sanitize_name；悬空别名处置（按裁决点结论）；"all" 语义放宽；注册序输出。
2. `act_async`/`execute_single_tool` 先解析后判定。
3. wbtest：别名权限绕过用例（`"Write"`、`"rm"` 别名在 ConfirmSafes 下必须询问）。

### 任务包 3：executor 结果面 + reminder（预估 1 天）
1. 伪 JSON → 合法 JSON；参数解析修复层与显式 parse-error。
2. denied 配对语义（所有 tool_calls 都有 result）；denied 不再终止 run。
3. TODO reminder 注入移植（含频控/去重）。

### 任务包 4：image_inject 链路 + 收尾（预估 1 天）
1. executor→client 图片旁路定义与实现（依赖 B3 截图侧产出格式定稿，可与 B3 并行、联调串行）。
2. 裁决点组（决策 11）逐条落地或记录豁免。
3. `moon check` + `moon test` 全量无回归。

## 验收标准 [必填]

- [x] `make_safe` 对 sudo / pkill clacky / curl|sh / eval() / 反引号等矩阵所列模式全部真实拦截，wbtest 双向覆盖（`security_wbtest.mbt`：每条模式正/反用例）
- [x] ConfirmSafes 探针：`rm -rf x` 类非白名单命令要求确认（不再自动执行）——`should_auto_execute_confirm_safes_*` 系列 + `run_confirm_safes_denies_unsafe` 运行级用例
- [x] 别名与大小写变体（`Write`/`rm`→trash_manager）在 ConfirmSafes 下不绕过确认（resolve canonical 后判定）
- [x] 含拒绝的多工具轮次：下一轮请求通过 Anthropic/OpenAI 协议校验（每个 tool_use 有配对 tool_result，denied 不再 break 悬空）
- [x] 错误/拒绝结果为合法 JSON（`@json.parse` 往返用例）
- [x] 非法 JSON arguments 产出 parse-error 结果而非"缺少参数"（`repair_json` 修复层 + 显式 parse-error）
- [x] 悬空别名处置完成（删除并记录）；`allowed_definitions` 任意位置 all 放行；工具定义顺序稳定（注册序）
- [x] TODO reminder 按 Ruby 语义注入（频控 30s + 去重）；`validate_secret_write` 接入点就绪（chmod 分支已接入，write/edit 本体接入随 S10/S16）
- [x] image_inject 链路：`[image_inject]` 占位符被 executor 消费、注入 user 图片消息（vision / 无 vision 双路径 + 占位无数据保留原文）
- [x] `moon check` 0 errors 0 warnings；全量 `moon test` 无回归（lib/agent 377/377，全量 3633/3633，见提交记录）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 正则依赖选型拖累（与 B1 共依赖） | 高 | B1/B2 任务包 0 合并调研，结论共享；security 模式面最小子集先落地 |
| 拦截面修复后误伤合法命令（正则语义比字面子串强得多） | 中 | 双向 wbtest 用例集 + Ruby 用例移植；灰度上无 key，靠测试兜底 |
| denied 继续配对改变交互节奏（用户需多次确认） | 中 | 按 Ruby 原语义实施（Ruby 如何处理多工具拒绝即为基准），不自行发明 |
| reminder 注入频率过高污染上下文 | 中 | 频控/去重规则从 Ruby 移植，不凭感觉设定 |
| image_inject 与 B3 接口未定稿 | 中 | 任务包 4 明确以 B3 截图载荷格式为输入；两 spec 联调点写入各自验收 |

## 依赖关系 [必填]

- **前置依赖**：无硬前置；regex 选型结论与 B1 共享（谁先实施任务包 0 谁记录）。
- **后置依赖**：`validate_secret_write` 实际接入等待 S10/S16；image_inject 产出侧等待 B3；denied 配对后的请求格式正确性由 B4（tool_result 合并）再兜底一层。
- **平行关系**：与 S05（terminal p5 spec）在 security.mbt 有同文件修改面，实施顺序上建议 S05 先行或同批次串行合入。

## 变更记录 [必填]

- 2026-08-18：创建（diff-harness 矩阵§2 security/registry/executor 残留条目核实落 spec；全部 17 项验证记录完成）。
- 2026-08-18：**任务包 1（security 拦截面）完成**：`is_pattern_match` 接入 `@string.Regex`（失败回退字面匹配，防降级静默失效）；正则拦截全部生效；`is_secret_path` 改路径段级匹配（消除 `.env` 全路径子串误伤）；`validate_secret_write` 接入 chmod 校验路径；审计日志落地（`~/.clacky/safety_logs/{cwd-hash}/safety.log`，JSON line）；`safe_readonly_commands` 剔除 `set`/`wmic`；chmod +x 分支落地（allow + secret 校验 + 审计）。
- 2026-08-18：**任务包 2（registry + 权限链）完成**：`sanitize_name` 落地（剥离引号/空白/多余前缀，含 `Bundle: ` 前缀剥离与 JSON 包裹识别）；4 条悬空别名（undo/redo/tasks/task_history）删除；`allowed_definitions` 任意位置 `all` 全放行；`all_definitions`/`allowed_definitions`/`tool_names`/`by_category` 全部改注册序输出（`order` 数组，Map 仅索引）；`act_async` 先 resolve 后判定（canonical 名进 `is_safe_operation`）。
- 2026-08-18：**任务包 3（executor 结果面 + reminder）完成**：`build_success_result`/`build_error_result`/`build_denied_result` 全改 `@json` 构造合法 JSON；`repair_json` 修复层（截断补全/单引号/尾逗号/未引号键值，失败返回显式 parse-error）；denied 配对语义（剩余 tool_calls 逐个产生 denied 结果，不再 break 悬空）；TODO reminder 注入（频控 30s + 去重哈希）。
- 2026-08-18：**任务包 4（image_inject 链路）完成**：`ToolResultEntry.image_inject` 字段 + `extract_image_inject` 解析（`[image_inject]` marker → `mime_type:`/`base64_data:`/`path:`；`(N chars)` 占位视为无数据保留原文）；`Agent::observe` 消费注入：vision 支持 → `[Text("[Image: label]"), Image(data: url)]` blocks user 消息，无 vision → 文本占位；`system_injected: true` 标记（Web UI history dedup 依赖）；产出侧 base64 由 B3 负责。涉及 `lib/message/message.mbt`（新增 `Message::user_blocks`）。
- 2026-08-18：**决策 11 裁决记录**（逐条对照 Ruby `security.rb` 330 行全量精读）：
  - **sudo（MB 保留硬拦截+审计）**：Ruby 允许并 `log_warning("sudo command executed: ...")`；MB 含 server/无人值守部署面，`sudo` 无人在环可确认，保留硬拦截为 MB 超集（注释已声明）。
  - **curl|sh（MB 保留硬拦截+审计）**：Ruby 重写为 `curl {url} -o {backup_dir}/downloaded_script_{ts}.sh && echo '🔒 ...'` 供人工审阅；MB 无强制审查 UI 流，拒绝+提示手动下载审阅更符合场景（注释已声明）。
  - **`$(...)`（MB 保留超集拦截）**：Ruby dangerous_patterns 不拦截 `$()`（仅 eval(/exec(/system(/反引号/`| sh$`/`| bash$`/重定向系统目录）；MB 保留拦截（命令替换为高危模式，且 MB 拦截面已收敛误报——先 strip 引号再匹配）。
  - **chmod +x（按 Ruby 补齐，正则比 Ruby 更正确）**：Ruby `replace_chmod_command`（`/^chmod\s+x/`）实际匹配不到真实 `chmod +x` 用法（空格后 `+x`），MB 用 `^chmod[[:space:]]*\+x` 真实命中；语义对齐：allow + 目标路径 `validate_secret_write`（= Ruby validate_file_path）+ `audit_log("allow", ...)`。
  - **审计日志范围（MB 为超集）**：Ruby block 时不记录（直接 raise），仅记录 sudo warning / curl replacement / chmod replacement；MB 保留 block 全记录（sudo/curl|sh/pkill/server/危险模式），便于无人值守追溯；时间戳从 unix ms 改为 ISO 8601（对齐 Ruby `Time.now.iso8601`；MB 发 UTC `Z`——S-FFI-08 约束不再新增本地偏移 FFI）。
  - **Windows 白名单（剔除完成）**：`set`（可赋值）与 `wmic`（`process call create` 等写语义）均剔除，注释注明理由。
  - **默认注册集 MemoryTool/TrashManager（MB 超集保留）**：Ruby 无二者；按 BUG-0016~0019 裁决原则（超集不删除、文档注明），`make_default_registry` 注释 + 本记录双重注明。
- 2026-08-18：**验收完成并归档**：全部 10 项验收标准勾选通过；`moon check` 0 errors 0 warnings；全量 `moon test` 3633/3633（lib/agent 377/377）；代码提交 `f8a96d6`（feat(agent): P6 security/registry/executor 对齐任务包 1-4 完成，13 文件 +1519/-115）；spec 移入 `specs/completed/`。

