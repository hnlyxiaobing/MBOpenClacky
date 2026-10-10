# MBOpenClacky 开发计划（2026-09-23）

> 来源：从 [known-gaps.md](known-gaps.md)（86 条 `open` 命中）与 [project-status.md](project-status.md) 中筛选出 **20 个**需要修复/优化的问题。
> 优先级公式（沿用 [improvement-execution-plan.md](improvement-execution-plan.md)）：`优先级 = 承诺落差 × 可信度影响 ÷ 实现成本`。
> 既有契约约束见 [improvement-execution-plan.md](improvement-execution-plan.md) §1.2（7 条会绊住后来者的陷阱）。
> **v2（2026-09-23）**：经对抗性审查修订，所有条目已逐条代码核实。**E2E 测试用例设计见 §7**（含 3 处测试基建前置扩展）。

---

## 0. 一句话判断

17 个工作包闭环后，**代码面**的"宣传 > 现实"落差已清零；但**发布面与申报口径**仍有两处待办（mooncakes 0.2.0 未发布、SQLite 申报口径待官方确认）。本期稀缺项：
①**静默假成功型缺陷**（状态码回落、JSON 不转义、stdout 污染）——直接违反诚实纪律，必须修；
②**发布落差**（mooncakes 版本落后）——对外可信度性价比最高的一项；
③**渠道接收侧**长轮询/WebSocket（唯一剩余的真实功能落差）；
④**Web handlers 的 not-implemented/stub**（备份 ZIP、快照 diff、trash 接线）；
⑤**评测对标与任务集扩充**（项目立项核心论点，目前只有 MB 侧单侧数据）。

---

## 1. 问题清单（20 条，按优先级排序）

### P0 — 静默假成功 / 数据失真 + 发布落差

| # | 问题 | 位置 | 状态 |
|---|------|------|------|
| 1 | **Web 状态码回落 200**：`response_to_core` 只映射 201/204/400/404，其他一律 `_ => ok()` | `lib/web/handlers_bridge.mbt:27-36` | ✅ 已修复 |
| 2 | **错误响应体不转义 JSON**：`HttpResponse::bad_request`/`not_found` 直接插值，message 含引号/花括号时产非法 JSON | `lib/web/router.mbt:113,125` | ✅ 已修复 |
| 3 | **stdout `[stream-summary]` 污染**：注释写 "visible in stderr"，实际走 `println`（stdout） | `lib/agent/llm_caller.mbt:685` | `[ ]` 待修 |
| 4 | **`updated_at` 回退 `created_at`**：两处投影未携带真实值 | `lib/web/handlers_ws.mbt:283`、`lib/web/handlers.mbt:21` | ✅ 已修复 |
| 5 | **mooncakes.io 0.2.0 未发布**：registry 落后本地 | mooncakes registry | `[ ]` 待发布 |
| 6 | **文档校准批次**：三处文档矛盾 | `docs/project-status.md`、`README.md` | ✅ 已修复 |

### P1 — 承诺落差 / 接收侧 / CLI 入口 / Web handlers

| # | 问题 | 位置 | 状态 |
|---|------|------|------|
| 7 | **Telegram `getUpdates` 长轮询未接线** | `lib/channel/telegram.mbt:250` | `[ ]` 待修 |
| 8 | **企微 WebSocket 接收侧未接线** | `lib/channel/wecom.mbt` | `[ ]` 待修 |
| 9 | **钉钉 Stream Mode 接收侧未接线** | `lib/channel/dingtalk.mbt` | `[ ]` 待修 |
| 10 | **`cmd/cli_mcp.mbt` stdio MCP server 暴露为 stub** | `cmd/cli_mcp.mbt` | `[ ]` 待修 |
| 11 | **备份快照 ZIP 打包** | `lib/web/handlers_backup.mbt:649,670` | ✅ 已修复 |
| 12 | **任务快照 diff / restore_preview 为 stub** | `lib/web/handlers_extra.mbt:13,1192,1218` | `[ ]` 待修（滑点高危） |
| 13 | **trash Web 路由仍用 stub 模型**（注释过期，trash_manager 已存在） | `lib/web/handlers_trash.mbt:365` | `[ ]` 待修 |

### P2 — 测试基建 / 能力延伸 / 评测对标 / 卫生项

| # | 问题 | 位置 | 状态 |
|---|------|------|------|
| 14 | **test/e2e 退避断言负载敏感（flaky）** | `test/e2e/scenarios_wbtest.mbt:54-63` | ✅ 已修复 |
| 15 | **上游 Ruby 侧真模型对标未执行** | `docs/eval/` + WSL Ruby 环境 | `[ ]` 待执行 |
| 16 | **评测任务集偏小**：当前 6 条，目标 20~30 条 | `test/capability/tasks/` | `[ ]` 待扩充 |
| 17 | **性能基准未升级为门禁**：需先补 `specs/draft/` 规格 | `test/benchmark/` | `[ ]` 待决策 |
| 18 | **`lib/hook/shell_loader.mbt` 为死代码**：生产代码零调用 | `lib/hook/shell_loader.mbt` | ✅ 已清理 |
| 19 | **browser 工具截图尺寸约束与配置检测 TODO** | `lib/tool/browser.mbt:234,237,241` | `[ ]` 待修 |
| 20 | **browser_manager 运维 TODO** | `lib/server/browser_manager.mbt:36,80,125,150` | `[ ]` 待修 |

---

## 2. 范围外（已披露或经核实降级，本期不动）

- **worker 模式重启**：`ServerMaster` 在 `cmd/` 与 `lib/web` 中零调用，worker 模式未接入运行时。
- **SQLite 申报口径**：代码无 SQLite，README 已转 JSON 架构决策；与官方确认口径即可。
- **WASM 回退 stub**（~20 行）：native 路径真实实现，wasm 仅 `moon check`（非阻塞）。
- **品牌服务端 HTTP**（~15 行）：仅当商业化成为目标时接线。
- **遥测占位**（3 行）：fire-and-forget、匿名，影响面小。
- **execution-plan 遗留承诺**：技能执行台账、Web JSONL 面板回放 UI、技能进化面板 UI——均转入下一期。
- **vision OCR 回退**、**TUI 卫生**、**utils 卫生**、**微优先**、**待决策**（`MBOPENCLACKY_*` 环境变量语义）。

---

## 3. 实施约定

### 3.1 流程分级

**完整 Harness 流程**（`specs/draft/` → 对抗评审 → `specs/active/` → 实现 → `specs/completed/`），按主题归并为约 **9 个 spec**：

| Spec | 覆盖问题 |
|------|----------|
| A：HTTP 响应保真 | #1 + #2 |
| B：agent stdout 诊断路由 | #3 |
| C：会话 updated_at 真实化 | #4 |
| D1/D2/D3：渠道接收侧 | #7 / #8 / #9 |
| E：MCP server 侧 stdio 暴露 | #10 |
| F：备份 ZIP 接线 | #11 |
| G：trash 接线 | #13 |
| H：评测对标与任务集 | #15 + #16 |

**轻流程**（一个提交 + 台账 `fixed`，无需 spec）：#6 文档校准、#14 e2e 确定性化、#18 死代码清理、#19/#20 browser 卫生。

**发布动作**（用户执行）：#5 mooncakes 发布。

### 3.2 验证基线命令

```bash
moon check -d                                                  # 0 error / 0 warning（CI 硬闸门）
moon build --target native --release cmd
BIN=./_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe
"$BIN" selftest --repo .                                       # 层 5 CLI 契约
"$BIN" eval --offline --repo .                                 # 层 6 确定性评测
moon test --release $(find lib cmd test -name moon.pkg | sed 's|/moon.pkg$||')
scripts/known_gaps.sh check && scripts/repo_stats.sh check      # 台账与数字闸门
```

### 3.3 诚实纪律

- 接不通的路径必须返回可诊断的 `Err(...)`，**不得静默假成功**。
- P0 代码项须有复现用例证明此前失真、此后正确。

---

## 4. 风险与触发条件

| 风险 | 触发信号 | 立即动作 |
|------|----------|----------|
| #10 stdin 能力探明失败 | spike 无法读到自身 stdin | #10 转范围外并如实登记 |
| #12 快照 diff infra 依赖过深 | 需新建大规模快照基础设施 | 转下一期并在台账登记 |
| 渠道接收侧引入回归 | `moon test` 或 `selftest` 变红 | 回到最近绿提交，先补复现用例再修 |
| #15 Ruby 对标环境不可用 | WSL 侧跑不通 | 降级为单侧数据，如实标注 |
| 范围被侵蚀 | PR 出现新渠道/Provider | 拒收，转台账或下一期 |

---

## 5. E2E 测试用例设计

### 5.1 设计原则

- **先选层**（[testing.md](testing.md)）：包内逻辑→层 1；与 Ruby 基线可比→层 2；完整 ReAct→层 3；界面/API→层 4；命令形状→层 5；工具任务→层 6；跨进程端到端→层 9。
- **复现纪律**：先固化复现用例，修复前该用例应为红。
- 禁止时间类断言；mock 剧本是顺序回放。

| 用例 ID | 层 | 对应问题 | CI |
|---|---|---|---|
| 1a | 1 | #1 状态码回落 | ✅ |
| 1b | 9 | #1 + #11 备份下载 | 手动/定时 |
| 2a | 1 | #2 JSON 转义 | ✅ |
| 2b | 9 | #2 用户输入进错误消息 | 手动/定时 |
| 3a | 9 | #3 stdout 污染 | 手动/定时 |
| 4a | 1 | #4 updated_at | ✅ |
| 4b | 9 | #4 排序反映活跃度 | 手动/定时 |
| 7a/8a/9a | 1+3 | #7/#8/#9 接收侧 | ✅ |
| 10a | 3 | #10 MCP stdio server | ✅ |
| 10b | 5 | #10 契约探针更新 | ✅ |
| 13a | 9 | #13 trash 真实数据面 | 手动/定时 |
| 12a | 9 | #12 快照 diff | 手动/定时 |
| 14a | 3 | #14 e2e flaky | ✅ |
| 18a | 1/5 | #18 死代码清理 | ✅ |
| 20a | 1 | #20 browser.yml/uptime | ✅ |

### 5.2 前置扩展（已落地）

| ID | 缺口 | 状态 |
|---|---|---|
| P-A | JSON 路径支持数组下标 | ✅ 已落地 |
| P-B | 断言词表补 `stdout_not_contains`/`stderr_not_contains`/`json_path_ne` | ✅ 已落地 |
| P-C | journey 驱动"向子进程 stdin 写帧" | — 未启用（设计已绕开） |
| P-D | IM mock + home 种子 | — 未启用（设计已绕开） |

### 5.3 落地进度（2026-09-23）

**已落地**：P-A/P-B 基建；1a/2a（`lib/web/response_fidelity_wbtest.mbt`）；14a（只保留下界判失败）；4a（`lib/web/handlers_wbtest.mbt`）；18a（`cmd/hook_loader_wbtest.mbt` 4 例）；1b（backup download 返回 201 + `id`）；层 9 的 2b/3a/4b 三个场景。

**仍未落地**：7a/8a/9a（依赖接收侧实现）、10a/10b（#10）、12a（#12）、13a（#13）、20a（#20）——各自等待对应实现。

---

> 维护约定：本文是**本期开发计划**，随进展更新 §1 的状态列；结论与优先级以 [improvement-execution-plan.md](improvement-execution-plan.md) 为准，逐行缺口以 [known-gaps.md](known-gaps.md) 为准。
