# 用户旅程 E2E 运行器（Layer 9 · `cmd journey`）· 增量 Spec

> **创建日期**: 2026-09-23  
> **状态**: 实施完成（13/13 旅程全绿、全量测试 3,981/3,981、定时演练成功；待对抗性评审后归档）  
> **关联总览**: `docs/testing.md`（8 层测试体系，本 spec 新增第 9 层）  
> **关联历史 spec**: `specs/completed/`（web-replication 系列、eval 统一为 519c8e5 提交）  
> **来源差距**: 用户日常使用场景（多轮聊天/持久化/重启恢复/WS 流式/CLI 一次性任务）无自动化 E2E 覆盖，靠手工验证  
> **依赖**: 无（统一 eval 引擎、MockLlmServer 均已存在）  
> **灰度 key**: 无

## 问题描述 [必填]

现有测试体系 8 层全部为**进程内**验证：层 4 TUI/Web eval 场景是单步、mock canned 响应（TUI 47 个场景全部 `mock_response`，Web 26 个场景仅 REST 错误路径，无 WS 无成功聊天）；无任何测试覆盖跨进程行为（会话持久化、`--continue` 恢复、进程重启）。用户日常手工验证的产品链路（建会话→多轮聊天→token 流式→模型切换→退出恢复）没有任何自动化替代。

需要：一套**可代替用户执行的自动化 E2E 工作流**——驱动真实编译产物走完整用户旅程，失败时自动记录（清晰场景描述+结构化证据），维护入库失败台账，为修复提供输入。

**用户已定决策**（2026-09-23 会话确认）：
- LLM 上游：Mock 日常 + 真模型定期（两档分开）
- 触发：手动一条命令 + 定时无人值守
- 证据归宿：台账入库 + 证据包临时（`_build/`）
- v1 范围：Web 聊天链路 / TUI 交互旅程 / 持久化与重启恢复 / CLI --message 一次性任务（全部四类）

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| moonbitlang/async 自带 WS 客户端 | `ls .mooncakes/moonbitlang/async/src/websocket/` + `pkg.generated.mbti` | `Conn::connect/send_text/recv/ping/send_close` 存在 | 无需自研 RFC6455 客户端 |
| `@process.spawn` 支持 extra_env 覆盖 | `grep -n "extra_env" .mooncakes/moonbitlang/async/src/process/process.mbt` | process.mbt:37 `extra_env? : Map[String, String]`；env_test.mbt:74 覆盖语义 | 子进程环境隔离可行 |
| cmd 入口已是 async | `head cmd/main.mbt` | `async fn main`（main.mbt:6） | 运行器可同进程托管 mock server + WS 客户端 + 子进程 |
| MockLlmServer 可复用 | `Read test/e2e/mock_llm_server.mbt` | 随机端口绑定、剧本回放、请求录制、shutdown 唤醒机制 | mock 上游零新代码 |
| HOME 经环境变量解析 | `Read lib/utils/path.mbt` | home_dir() 读 USERPROFILE→HOME（path.mbt:10-22） | 沙箱 home 可注入 |
| config.toml 模型支持 base_url | `grep "get(\"models\")" lib/config/loader.mbt` | loader.mbt:185-215，缺 base_url 仅告警不丢弃 | 种子 config 可指向 mock 端口 |
| Web 聊天是纯 WS | `grep -rn "chat" lib/web/server.mbt` | server.mbt:247 "POST :id/chat and SSE chat/stream removed (web-parity-05)" | Web 旅程必须走 WS |
| WS 帧协议形状 | `grep -n "\"subscribe\"\|\"message\"" lib/web/handlers_ws.mbt` | `{"type":"subscribe"/"message"/"interrupt"/"confirmation"/"feedback","session_id":...}` | 客户端帧契约明确 |
| 事件线名 | `grep -n "from_wire\|type_name" lib/protocol/event.mbt` | Event::from_wire(event.mbt:973)/type_name(:302)；真实名：subscribed/token_delta/tool_call/assistant_message/error/task_finished | 帧分类用生产解析器 |
| 健康端点与 WS 路由 | `grep "health\|/ws" lib/web/server.mbt` | `/health`（:233）、`/ws`（:943）、`POST /api/sessions`→201 | 就绪探测契约明确 |
| cmd 可复用包内函数 | `grep "fn detect_binary" cmd/selftest.mbt` | selftest.mbt:561；`write_unified_report` cmd/eval.mbt:75 | 新 cmd/journey.mbt 直接调用 |
| test/tui 是同步包 | `Read test/tui/moon.pkg` | 无 async 依赖 | TUI 真实 ReAct 驱动须放在 async 的 journey driver |
| TUI 截图不持久化 | `grep -n "screenshots" test/tui/tui_eval_adapter.mbt` | :320 声明、:553 push，从未读出 | 证据持久化缺口，本 spec 顺带补上 |
| 无失败记录机制 | `grep -rn "failures.json\|known_issue" test/ cmd/` | 0 命中（仅 test/diff/known_failure.mbt 的 BUG 闸门） | 台账为全新组件 |
| `-m --json` 输出契约 | `grep -n "run_result_to_json" cmd/main.mbt` | main.mbt:1191（status/session_id/iterations/total_cost_usd/error） | CLI 旅程断言契约 |

### 详细分析

**为什么现有体系不够**：层 4 适配器（TuiEvalSimulator、TestClient）都在测试进程内 dispatch，不可能覆盖进程边界（重启、--continue、config 从磁盘加载、真实网络栈）；层 3 e2e 用 MockLlmServer 驱动真实 ReAct 但只测 Agent 核心循环，不碰任何界面；层 8 真模型评测是统计口径不做回归门禁。用户旅程需要的是"真实二进制 + mock 上游 + 真实接口驱动"的组合，这在现有 8 层中无对应位置 → 新增层 9。

**挂起教训（设计硬约束）**：CI run 35832930861（2026-09-23）`moon test` 步骤自 07:40 挂起，被 30 分钟 job 超时杀掉（cancelled）。任何长跑测试设施必须有步/旅程/批三级看门狗。

## 决策 [必填 - 含为什么]

1. **独立 `journey` 子命令，不做 `eval --journey` 后端**：eval 的旗标身份是"进程内 harness + --trials/--tasks"；旅程运行器的本质属性（子进程、端口、看门狗、台账维护、区分"产品红"与"运行器坏"的退出码 0/1/2/3）不匹配，且调度器需要一条稳定自描述命令。共享机制（UnifiedReport/渲染器/断言词表/报告写盘）全部照旧复用。
2. **Mock 上游为日常档**：确定性、零成本、失败可精确归因到产品代码；真模型质量已由层 8 覆盖（用户决策"Mock 日常+真模型定期"）。
3. **台账入库（`docs/journey-failures.md`）+ 证据包临时（`_build/journey/<stamp>/`）**：仿 known-gaps 台账纪律（marked 段自动生成 + curated 段人工批注）；一次性产物纪律（testing.md）要求证据不入库。闭环机制：同场景重跑转绿 → 台账自动移入「已修复」段。
4. **环境隔离用子进程 env 覆盖而非进程内模拟**：USERPROFILE/HOME 指向沙箱 + 种子 config.toml（base_url 指向 mock 端口）——这是唯一能覆盖"config 从磁盘加载/会话跨进程持久化"的方式，且与用户过去手工实践一致。
5. **TUI 旅程进程内驱动**：Windows 无 pty（记忆 pty-windows）；TuiEvalSimulator 虚拟屏 + 真实 Agent（指向 mock）+ 生产 AgentHookHandler 管线，兼顾真实渲染与无头。
6. **每旅程独立 MockLlmServer + 严格串行**：匹配串行 ReAct 语义与确定性。
7. **MoonBit 约束检查**：不涉及动态加载 trait（无 AOT 冲突）；不声称"crescent 不支持 X"（WS 客户端来自 moonbitlang/async 而非 crescent，已验证存在）；不涉及新 FFI/C 库。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `test/journey/moon.pkg` | 新建 | 依赖 core/x/async + lib/{agent,client,config,protocol,utils} + test/{eval,e2e,tui} |
| `test/journey/scenario.mbt` | 新建 | JourneyScenario/JourneyPhase/JourneyStep/StepAction + 解析器 |
| `test/journey/context.mbt` | 新建 | JourneyContext + 占位符展开 + 沙箱播种 |
| `test/journey/child_process.mbt` | 新建 | ChildHandle spawn/kill/流式 stdout/env 隔离 |
| `test/journey/ws_journal.mbt` | 新建 | WS journal 客户端封装 |
| `test/journey/web_driver.mbt` / `cli_driver.mbt` / `tui_driver.mbt` | 新建 | 三类步骤执行器 |
| `test/journey/assert_journey.mbt` | 新建 | 旅程断言求值（分发 AssertionKind） |
| `test/journey/evidence.mbt` | 新建 | 证据包写入器 |
| `test/journey/ledger.mbt` | 新建 | 失败台账维护 |
| `test/journey/runner.mbt` | 新建 | run_journey_batch + 看门狗 |
| `test/journey/scenarios/*.json` | 新建 | 13 个 v1 旅程 |
| `test/journey/README.md` | 新建 | 运行手册 |
| `test/journey/*_wbtest.mbt` | 新建 | co-located 白盒测试 |
| `cmd/journey.mbt` | 新建 | handle_journey + 旗标 + 退出码 |
| `cmd/main.mbt` | 修改 | 注册 journey 子命令（~15 行） |
| `cmd/moon.pkg` | 修改 | 加 test/journey 依赖 |
| `test/eval/assertions.mbt` | 修改 | 新增 8 个旅程断言种类（纯增量） |
| `test/eval/eval_engine.mbt` | 修改 | UnifiedTestKind::Journey + 归一辅助 |
| `test/tui/tui_eval_adapter.mbt` | 修改 | 抽出 new_with_agent（~15 行） |
| `docs/testing.md` | 修改 | 层 9 行 + 专节 |
| `README.md` | 修改 | 命令块 + 测试树行 |
| `docs/journey-failures.md` | 新建 | 台账（运行时自动维护） |
| `test/capability/tasks/cap-005-parallel-read.json` / `cap-006-error-recovery.json` | 新建 | 真模型定期档任务 |

### 不涉及文件

- `lib/**`（零产品代码改动——E2E 只驱动不修改产品）
- `.github/workflows/**`（用户决策不进 CI）
- `test/e2e/mock_llm_server.mbt`（原样复用）
- `vendor/**`、`.mooncakes/**`

## 实施计划 [必填]

### 任务包 1：共享设施扩展（预估 0.5 天）
- 断言词表 8 新种类 + UnifiedTestKind::Journey
- TuiEvalSimulator::new_with_agent 抽取

### 任务包 2：test/journey 运行器核心（预估 1.5 天）
- 场景 schema/解析器/沙箱上下文
- 子进程 + WS journal（含互操作排雷 wbtest）
- 三类驱动器 + 断言求值 + 证据 + runner 骨架

### 任务包 3：13 个旅程场景 + 台账（预估 1 天）
- CLI/持久化（5）→ Web（5）→ TUI（3）按序落地
- ledger.mbt + 状态迁移测试 + 全量批

### 任务包 4：cmd 接线 + 文档 + 真模型档（预估 0.5 天）
- cmd/journey.mbt + main 分派
- docs/testing.md 层 9 + README + journey README + 2 个 capability 任务
- schtasks 演练

## 验收标准 [必填]

- [ ] `cmd.exe journey --repo .` 13/13 PASS，exit 0，报告落 `_build/journey/report_<date>.txt`
- [ ] 注入失败（改坏一个期望）→ exit 1 + 证据包含 journey.json/ws_frames.jsonl/mock_requests.jsonl + 台账 open 行
- [ ] 还原后重跑 → 旅程绿 + 台账行移入「已修复」（闭环）
- [ ] 全程无挂起：单步/单旅程/整批看门狗生效（模拟超时可验证）
- [ ] 绿运行不产证据包目录（保留策略生效）
- [ ] `moon check -d` 0 error 0 warning
- [ ] `moon test --release test/journey test/eval test/tui` 通过
- [ ] `moon info` diff 纯增量（新 pub fn 均有意）
- [ ] `scripts/known_gaps.sh check && scripts/repo_stats.sh check` 仍绿
- [ ] 子进程绝不触碰真实 `~/.mbopenclacky`（沙箱隔离验证）
- [ ] `eval --live --trials 1` 冒烟 2 个新 capability 任务
- [ ] schtasks 定时演练一次成功（日志+稳定退出码）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| WS 客户端↔服务端互操作细节（关闭握手/ping 策略） | 中 | 任务包 2 先做进程内 crescent /ws 互操作排雷测试，再碰产品 server |
| Windows env 块重复键覆盖 | 中 | wbtest 用真实子进程冒烟 USERPROFILE 覆盖 |
| task group 退出时活子进程残留 | 高 | Process::cancel + 硬杀 + group 退出前显式 kill_all；参考 spawn_in_group_test.mbt |
| 会话 .jsonl flush 时机不确定（crash 路径） | 中 | crash 旅程只断言优雅路径 .jsonl；不确定性显式化为断言 |
| TUI 驱动器 agent 生命周期（env 进程全局） | 中 | 旅程串行 + 每次 agent 构造前重播种 env |
| 端口冲突 | 低 | 探测 + port+1 重试（最多 3 次） |
| 台账并发写 | 低 | temp+rename 原子写；文档化"一次一个运行器" |
| moon test 挂起教训复现 | 高 | 三级看门狗是硬性验收项 |

## 依赖关系 [必填]

- **前置依赖**：无（统一 eval 引擎 519c8e5、MockLlmServer、moonbitlang/async WS 客户端均已存在）
- **后置依赖**：CI 挂起修复为独立任务（不属于本 spec）；失败台账可供后续修复 spec 引用

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-09-23 | 初始版本 | 用户会话确认四项决策（上游/触发/证据/范围） |
| 2026-09-23 | 实施完成：13 条旅程全绿（Web 5/TUI 3/持久化 3/CLI 2）；失败→台账→转绿自动闭环经有机验证两轮；全量 scoped 测试 3,981/3,981（+8）；schtasks 注册并演练成功（scheduled.log 记录 13/13）；真模型冒烟 2 个新 capability 任务全过（cap-001 单次失败入 curated 观察段） | — |
