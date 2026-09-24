# MBOpenClacky 开发计划（2026-09-23）

> 来源：从 [known-gaps.md](known-gaps.md)（86 条 `open` 命中）与 [project-status.md](project-status.md)（§5.3 渠道接收侧、§7 建议优先级）中，按第一性原理筛选出 **20 个**需要修复/优化/追赶的问题。
> 优先级公式（沿用 [improvement-roadmap.md](improvement-roadmap.md)）：`优先级 = 承诺落差 × 可信度影响 ÷ 实现成本`。
> 既有契约约束见 [improvement-execution-plan.md](improvement-execution-plan.md) §1.2（7 条会绊住后来者的陷阱）。
> **v2（2026-09-23）**：经对抗性审查修订，所有条目已逐条代码核实。关键变更：新增 mooncakes 发布与 e2e flaky 两项；#9 cli_mcp 阻塞理由过期已重写；原 worker 重启与 shell_loader 两项经核实分别降为范围外/改为死代码清理；文档校准项脱离 P0 复现用例要求；实施流程分级。变更明细见 §8；**E2E 测试用例设计见 §7**（含 3 处测试基建前置扩展）。

---

## 0. 一句话判断

17 个工作包闭环后，**代码面**的"宣传 > 现实"落差已清零；但**发布面与申报口径**仍有两处待办（mooncakes 0.2.0 未发布、SQLite 申报口径待官方确认，见 [review-feedback-check-20260923.md](review-feedback-check-20260923.md) §四）。本期稀缺项：
①**静默假成功型缺陷**（状态码回落、JSON 不转义、stdout 污染）——直接违反诚实纪律，必须修；
②**发布落差**（mooncakes 版本落后 26 天）——对外可信度性价比最高的一项；
③**渠道接收侧**长轮询/WebSocket（§5.3 唯一剩余的真实功能落差）；
④**Web handlers 的 not-implemented/stub**（备份 ZIP、快照 diff、trash 接线）；
⑤**评测对标与任务集扩充**（项目立项核心论点，目前只有 MB 侧单侧数据）。

---

## 1. 问题清单（20 条，按优先级排序）

### P0 — 静默假成功 / 数据失真（违反诚实纪律）+ 发布落差

| # | 问题 | 位置 | 影响 | 成本 |
|---|------|------|------|------|
| 1 | **Web 状态码回落 200**：`response_to_core` 只映射 201/204/400/404，其他一律 `_ => ok()`。**现存受害者已核实**：backup 下载的诚实 501（`handlers_backup.mbt:666`）正以 200 到达客户端 | `lib/web/handlers_bridge.mbt:27-36` | 所有经 bridge 的 Web API 错误诊断失真；与 #11 耦合（修本项后 #11 的 501 恢复可见，spec 断言须联动） | 低（`@core.HttpResponse` 有通用构造器，补全 status 映射） |
| 2 | **错误响应体不转义 JSON**：`HttpResponse::bad_request`/`not_found` 直接插值 `"{\"error\":\"\{message}\"}"`，message 含引号/花括号/换行时产非法 JSON | `lib/web/router.mbt:113,125` | 机器可读契约破坏；调用面广（trash/backup 等多处）。修两处构造器即全覆盖（`json_error` 同包可见，`handlers_skills.mbt:653`） | 低 |
| 3 | **stdout `[stream-summary]` 污染**：注释与 spec 都写 "visible in stderr"，实际走 `println`（stdout） | `lib/agent/llm_caller.mbt:685` | 影响一切机器可读 stdout（`-m --json`、`eval --live`）；契约被迫声明"JSON 是 stdout 最后一行"。**两条低成本路径**：a) stderr C stub（仓库已有 8 个 C stub 的既有模式，lib/agent 即有 `time_stub.c`）；b) 环境变量门控（零 FFI）。"core 无 stderr 原语"不是硬阻塞，1 页 ADR 定路径即可 | 低-中 |
| 4 | **`updated_at` 回退 `created_at`**：**两处**——`handlers_ws.mbt:283`（有 TODO 注释）与 `handlers.mbt:21`（无注释，台账扫描未覆盖）。前端确实按 updated_at 排序（`web/sessions.js:2973` "pinned first, then most-recently-active"）与显示相对时间（`:2218`） | `lib/web/handlers_ws.mbt:283`、`lib/web/handlers.mbt:21` | 会话列表排序恒等于创建时间，活跃会话不上浮 | 低（SessionData 持真实 updated_at，消息追加时刷新，两处投影同步） |
| 5 | **mooncakes.io 0.2.0 未发布**：registry 最新 0.1.3（2026-08-28，26 天前），本地 `moon.mod` 已 0.2.0 | mooncakes registry | 评审安装最新发布包看到旧快照，可能重复此前"未修复"判定（反馈报告 §四 P1）。**发布是用户动作**，计划只列前置闸门 | 低（闸门全绿后 `moon publish`） |
| 6 | **文档校准批次**（性质：文档校准，**不要求复现用例**，并入首个 `docs:` 提交）：① project-status §4 "缺少 6 个内置扩展包" 与 §7/§6.1 矛盾（实测 `assets/extensions/` 有 6 个目录）；② §7 "4 任务 × 3 重复" 与 §8 "6 任务" 矛盾（实际 `test/capability/tasks/` 为 **6** 条）；③ `README.md:140-144` 测试命令注释滞后（仍写"统一 --release"，CI 已改 scoped debug） | `docs/project-status.md`、`README.md` | 文档健康；三处都会误导后来者 | 极低 |

### P1 — 承诺落差 / 接收侧 / CLI 入口 / Web handlers

| # | 问题 | 位置 | 影响 | 成本 |
|---|------|------|------|------|
| 7 | **Telegram `getUpdates` 长轮询未接线**：`start()` 的 TODO 如实登记，接收侧为诚实报错 stub | `lib/channel/telegram.mbt:250` | §5.3 主要剩余缺口；纯 HTTP 轮询，三个接收侧里最简单（先行验证模式） | 中（复用 WP-1.1~1.4 mock-TCP 验证模式 + ChannelManager 单一真相源） |
| 8 | **企微 WebSocket 接收侧未接线**：send 已通（WP-1.3），接收走 `/api/webhooks/wecom`，WS 收发为 stub | `lib/channel/wecom.mbt` | §5.3 主要剩余缺口 | 中（复用 `ws_client.mbt`——@async/websocket 薄封装，Discord 网关已在用） |
| 9 | **钉钉 Stream Mode 接收侧未接线**：send 与 `open_stream_connection`/`download_file_url` 已通（WP-1.2），WS 循环为独立工作项 | `lib/channel/dingtalk.mbt` | §5.3 主要剩余缺口 | 中（`ws_client.mbt` + `discord_gateway.mbt` 435 行完整生命周期：心跳/Resume/退避，直接可参考） |
| 10 | **`cmd/cli_mcp.mbt` stdio MCP server 暴露为 stub**。⚠️ **原阻塞理由已过期**：该文件注释（引用 spec 2026-08-18_16）称 stdio_transport 仍是 placeholder、需子进程 FFI——实际 `lib/mcp/stdio_transport.mbt` native 已是真实实现（@process pipes + python3 集成测试）。**真实工作**：a) 读取自身进程 stdin 的能力（TTY 读取已有，管道 stdin 待探明，先出 spike）；b) MCP **server** 侧 JSON-RPC 协议面（initialize/tools/list/tools/call 映射到现有工具注册表）。修复时顺带更新过期注释 | `cmd/cli_mcp.mbt` | 对外集成面缺失（编辑器/编排器无法以 stdio 调用本项目） | 中（spike 探 stdin → spec → 协议面实现） |
| 11 | **备份快照 ZIP 打包未实现**：`not-implemented` + `not-yet`，返回 501（该 501 当前被 #1 吞成 200） | `lib/web/handlers_backup.mbt:649,670` | 备份功能不完整。**`lib/zip/zip.mbt:92` 已有 `pub fn create_zip`**——打包能力现成，剩余是遍历快照目录 + 接线 handler + 流式响应 | 低-中（原"中"高估，硬核部分已存在） |
| 12 | **任务快照 diff / restore_preview 为 stub**：`full task-snapshot diff requires deeper infra` | `lib/web/handlers_extra.mbt:13,1192,1218` | time_machine 配套功能不完整 | 高（需快照 infra；本期滑点高危项） |
| 13 | **trash Web 路由仍用 stub 模型**：注释称"once B3 lands trash_manager this route will wire"——**trash_manager 工具早已存在**（project-status §2 ✅），注释过期 | `lib/web/handlers_trash.mbt:365` | 回收站 delete/restore 未接真实数据面。正确动作是**接线到已存在的 trash_manager 工具面**，而非新建 trash 模型（原方案"中"成本高估）；顺带修过期注释 | 低-中 |

### P2 — 测试基建 / 能力延伸 / 评测对标 / 卫生项

| # | 问题 | 位置 | 影响 | 成本 |
|---|------|------|------|------|
| 14 | **test/e2e 退避断言负载敏感（flaky，已复现一次）**：墙钟窗口 [2000, 20000]ms，高负载实测 22768ms 越界 → 测试进程崩溃（0xc0000409）；单独重跑 14/14 绿 | `test/e2e/scenarios_wbtest.mbt:54-63` | CI 假红风险（反馈报告 §四 P3 新发现） | 低（窗口上限放宽至 30s，或改可注入时钟的确定性断言——`llm_caller_wbtest` 已有单元级固定断言先例） |
| 15 | **上游 Ruby 侧真模型对标未执行**：MB 侧已有两份单侧报告（2026-09-22 deepseek-flash、2026-09-23 qwen3.8-max 定期档）+ 周检机制；"同模型同参数对标"仍只有单侧数据 | `docs/eval/` + WSL Ruby 环境 | 无法回答"MB 重写是否行为对齐"；项目立项核心论点 | 高（需 WSL Ruby + 两侧同模型同参数、每任务 ≥5 次） |
| 16 | **评测任务集偏小**：当前 **6** 条任务（cap-001~006）× 3 重复（⚠️ 原计划误写 4 条，系继承 project-status §7 过期口径），全通过不构成"模型强"的证据；目标 20~30 条 | `test/capability/tasks/` | 无区分度；无法检测模型能力回归。扩充须与 #15 的定期档机制衔接 | 中（任务设计 + 验收标准） |
| 17 | **性能基准未升级为门禁**：WP-3.4 流程偏差——以一次代码提交直接落地，未走 Harness 流程；若要升级为门禁必须先补规格 | `test/benchmark/` + `specs/draft/` | 计时噪声大且历史基线须同代；有人拿抖动卡 PR 时无规格依据拒绝 | 低（补 `specs/draft/` 规格） |
| 18 | **`lib/hook/shell_loader.mbt` 为死代码**：`ShellHookLoader` 生产代码零调用（仅自身 .mbti + `hook_wbtest.mbt:69` 引用）；真实 hook 加载是 `cmd/hook_loader.mbt:27` 的 `load_shell_hooks`（扫描 `.clacky/hooks/*.toml|json`），已接 `cmd/main.mbt:998`。**风险**：`execute_hook` 无条件返回 `Allow`（`shell_loader.mbt:55`）——若未来误接，shell hook 审批将静默放行 | `lib/hook/shell_loader.mbt` | 静默放行陷阱。处置：**删除**（含相关 wbtest 用例）→ 重跑 `known_gaps.sh generate` → 台账 3 行处置；不是"实现 YML 解析"（原方案做错了方向——那是给被替代的平行设计补实现） | 低（轻流程，无需 spec） |
| 19 | **browser 工具截图尺寸约束与配置检测 TODO**：`max_width`/`max_height` 未 enforce；`browser_config_path` 存在性与 `enabled` 检测为 TODO | `lib/tool/browser.mbt:234,237,241,427,439,448` | browser 工具完整性。若上游 MCP 不支持 clip，诚实选项是从 schema 移除误导性参数而非伪装支持 | 低（轻流程） |
| 20 | **browser_manager 运维 TODO**：`browser.yml` 读取/时间戳/uptime 计算/配置更新为 TODO。**现成原语**：`@env.now()`（`handlers_billing.mbt:83` 在用）、`@fs.read_file_to_string`（`hook_loader.mbt:49` 在用）——均为平凡修复，无需新 FFI | `lib/server/browser_manager.mbt:36,80,125,150` | `started_at` 恒为 0，uptime 无法计算 | 低（轻流程，接近顺手修） |

---

## 2. 范围外（已披露或经核实降级，本期不动）

以下为**有意范围外**、**平台事实**或**经对抗性审查降级**的项：

- **worker 模式重启**（原计划 P1，审查降级）：`ServerMaster` 仅存在于 `lib/server/master.mbt` + wbtest，在 `cmd/` 与 `lib/web` 中**零调用**——worker 模式未接入运行时，"接线 worker 信号"是伪命题（没有运行中的 master 可接）。要做需先立"运行时多进程模型"架构 spec，属下一期运行时原语候选（roadmap §5）。
- **SQLite 申报口径**（反馈报告 P1，沟通项）：代码无 SQLite，README 已转 JSON 架构决策；若官方验收硬性要求 SQLite 本体，需先立 spec（C FFI 或纯 MoonBit，大工程）。**与官方确认口径**，不在本计划内实现。
- **WASM 回退 stub**（~20 行）：`lib/mcp/stdio_transport.mbt`、`lib/server/browser_*.mbt`、`lib/tool/pty_session_wasm.mbt`、`lib/utils/epipe_safe_io.mbt` —— native 路径真实实现，wasm 仅 `moon check`（非阻塞）。
- **品牌服务端 HTTP**（~15 行）：`lib/brand/{license,skill_manager,device}.mbt` —— 仅当商业化（白标授权服务）成为目标时接线。
- **遥测占位**（3 行）：`lib/telemetry/telemetry.mbt` —— fire-and-forget、匿名，影响面小。
- **execution-plan §3.1 遗留承诺**：技能执行台账（GEP PostExecution 前置）、Web JSONL 面板回放 UI（`cmd inspect` 已可回放）、技能进化面板 UI（需先有可提交的执行证据）——均明确转入下一期。
- **vision OCR 回退**：`lib/agent/react.mbt:348` —— 无视觉模型时 Ruby 的 OCR 回退未移植。
- **TUI 卫生**：`lib/tui/theme.mbt:155`（终端背景色检测固定深色）、`lib/tui/todo_area.mbt:4`（Phase 0 占位）。
- **utils 卫生**：`lib/utils/workspace_rules.mbt:54`（子目录扫描未实现）、`lib/utils/browser_detector.mbt:140,142`（浏览器检测 FFI）。
- **微优先**：`lib/client/client.mbt:15`（注释疑似过时）、`lib/tool/registry.mbt:59`（部分别名注册但未实现）—— 可顺手修。
- **待决策**：`MBOPENCLACKY_*` 环境变量在存在 `config.toml` 时被忽略——属独立配置语义决策，非 bug。

---

## 3. 实施约定

### 3.1 流程分级（v2 修订：不再对全部 20 项套完整 Harness 流程）

**完整 Harness 流程**（`specs/draft/` → 对抗评审 → `specs/active/` → 实现 → `specs/completed/`），按主题归并为约 **9 个 spec**：

| Spec | 覆盖问题 | 备注 |
|------|----------|------|
| A：HTTP 响应保真 | #1 + #2 | 同一主题（状态码映射 + JSON 转义），断言含 backup 501 联动 |
| B：agent stdout 诊断路由 | #3 | 1 页 ADR 选路径（stderr C stub / 环境变量门控）后实现 |
| C：会话 updated_at 真实化 | #4 | 覆盖 `handlers_ws.mbt:283` 与 `handlers.mbt:21` 两处 |
| D1/D2/D3：渠道接收侧 | #7 / #8 / #9 | 每平台一个 spec（沿用 WP-1.1~1.4 习惯）；Telegram 先行 |
| E：MCP server 侧 stdio 暴露 | #10 | 先 spike 探 stdin 能力，再立 spec |
| F：备份 ZIP 接线 | #11 | 接 `create_zip`，断言含 #1 修复后 501 状态码 |
| G：trash 接线 | #13 | 接线到 trash_manager 工具面 |
| H：评测对标与任务集 | #15 + #16 | 方法学 + 任务设计，与定期档机制衔接 |

**轻流程**（一个提交 + 台账 `fixed`，无需 spec）：#6 文档校准、#11 前置的 #14 e2e 确定性化、#18 死代码清理、#19/#20 browser 卫生。

**发布动作**（用户执行）：#5 mooncakes 发布——前置闸门为 `moon check -d` / 全量测试 / `known_gaps.sh check` / `repo_stats.sh check` 全绿。

实现时在 `moon check` 紧循环里小步推进；执行型工作用**便宜模型**，仅架构/FFI 内存布局/对抗评审用贵模型（见 `AGENTS.md` 效率协议第 1 条）。每闭环一项：重跑 `scripts/known_gaps.sh generate` → 命中行消失 → curated 行改 `fixed`；`docs/CHANGELOG.md` 记一笔；提交遵循 `feat:`/`fix:`/`docs:` 小写前缀。

### 3.2 验证基线命令（改动前后各跑一次）

```bash
moon check -d                                                  # 0 error / 0 warning（CI 硬闸门）
moon build --target native --release cmd
BIN=./_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe
"$BIN" selftest --repo .                                       # 层 5 CLI 契约
"$BIN" eval --offline --repo .                                 # 层 6 确定性评测，评分须全 1
moon test --release $(find lib cmd test -name moon.pkg | sed 's|/moon.pkg$||')
scripts/known_gaps.sh check && scripts/repo_stats.sh check      # 台账与数字闸门
```

> 用例数以 `repo_stats.sh` 机器生成块为准（**勿在文档手写具体数字**——execution-plan §1.1 的 3,973+96=4,069 已漂移为 3,981+96=4,077，journey runner 落地后仍在变动）。

### 3.3 诚实纪律

- 接不通的路径必须返回可诊断的 `Err(...)`，**不得静默假成功**（stubfix 批次已清零假成功型 stub，勿回退）。
- P0 的 **#1~#4**（代码行为变更）须有复现用例证明此前确实失真、此后正确；**#6 文档校准不要求用例**（文档矛盾无测试可写）；**#5 发布**以 registry 在线状态为验收。
- 修 #1 时注意会让 #11 的 501 恢复可见——两个 spec 的断言须联动，避免"修好一个暴露另一个"被当成回归。

---

## 4. 排期建议（8 周）

| 周次 | 内容 | 问题编号 |
|------|------|----------|
| 第 1 周 | **P0 代码三项**（Spec A：#1+#2；Spec C：#4）+ **#6 文档校准**（`docs:` 提交）+ **#5 发布闸门预跑** | #1, #2, #4, #6, #5(闸门) |
| 第 2 周 | **Spec B：#3 stdout**（ADR 选路径后实现）+ **#5 mooncakes 发布执行** + **#11 备份 ZIP**（Spec F）+ **#14 e2e flaky** | #3, #5, #11, #14 |
| 第 3-4 周 | **P1 渠道接收侧**（Telegram D1 先行 → 企微 D2 → 钉钉 D3，复用 ws_client/discord_gateway） | #7, #8, #9 |
| 第 5 周 | **#10 cli_mcp**（spike 探 stdin → Spec E）+ **#13 trash 接线**（Spec G） | #10, #13 |
| 第 6 周 | **#12 快照 diff**（Spec 范围内可做则做，滑点高危）+ **#18 死代码清理** | #12, #18 |
| 第 7 周 | **#15 Ruby 对标 + #16 任务集扩充**（Spec H） | #15, #16 |
| 第 8 周 | **#17 benchmark 规格** + **#19/#20 browser 卫生**（轻流程）+ 收尾（台账/文档/CHANGELOG 同步） | #17, #19, #20 |

> 排期原则：P0 代码项先行（违反纪律的缺陷不能过夜）；mooncakes 发布闸门预跑与文档校准搭首周快车、发布执行在第 2 周代码冻结窗口；渠道接收侧是 §5.3 唯一剩余真实落差，优先于 Web handlers；评测对标需 WSL Ruby 环境，排中后段；卫生项可并行。

---

## 5. 风险与触发条件

| 风险 | 触发信号 | 立即动作 |
|------|----------|----------|
| #10 stdin 能力探明失败（spike 结论为"管道 stdin 不可读"） | spike 无法以阻塞/异步方式读到自身 stdin | #10 转范围外并如实登记（"server 侧暴露受平台 stdin 能力约束"），不硬造 |
| #12 快照 diff infra 依赖过深 | 实现需要新建大规模快照基础设施 | 转下一期并在 `known-gaps.md` 如实登记（§6 DoD 已预设其为滑点高危） |
| P1 渠道接收侧引入回归 | `moon test` 或 `selftest` 变红 | 回到最近绿提交，先补复现用例再修（效率协议第 4 条：先读完整错误） |
| #15 Ruby 对标环境不可用 | WSL 侧 `openclacky agent -m` 跑不通 | 降级为"MB 侧单侧数据 + 方法学文档"，如实标注未验证部分 |
| 范围被"顺手加功能"侵蚀 | PR 出现新渠道/Provider/前端重写 | 拒收，转 `known-gaps.md` 或下一期 |
| 数字或台账静默失真 | `repo_stats.sh check` / `known_gaps.sh check` 变红 | 按 improvement-execution-plan.md §1.1 显式重生成，不要手改数字块 |
| 修 #1 暴露 #11 的 501 | backup 下载测试从 200 变 501 | 这是预期行为（诚实报错恢复可见），Spec A/F 断言联动覆盖，勿当回归回滚 |

---

## 6. 完成定义（本期）

本计划视为达成的四个条件：

1. ✅ P0 的 6 条全部闭环：#1~#4 有复现用例证明此前失真、此后正确；#5 以 mooncakes registry 在线可见 0.2.0 为验收；#6 三处文档矛盾清零（`docs:` 提交）。
2. ✅ P1 的 7 条中至少 **5** 条闭环；滑点高危项已识别为 **#10**（stdin 能力未探明）与 **#12**（infra 依赖深）——滑点须给出具体依赖证据并在 `known-gaps.md` 如实登记，不得无声缺席。
3. ✅ P2 的 7 条中至少 **4** 条闭环（评测方法学文档 + 任务集扩到 ≥10 条 + benchmark 规格 + e2e 确定性化或死代码清理至少其一）；剩余可转下一期。
4. ✅ `docs/improvement-roadmap.md` 条目状态与 `docs/CHANGELOG.md` 均已同步；`known_gaps.sh check` 绿。

> 维护约定：本文是**本期开发计划**，随进展更新 §1 的状态列（可加 `[x]`/`[ ]` 标记）；结论与优先级以 [improvement-roadmap.md](improvement-roadmap.md) 为准，逐行缺口以 [known-gaps.md](known-gaps.md) 为准，交付细节以 [CHANGELOG.md](CHANGELOG.md) 与 `specs/completed/` 为准。四者不一致时，以机器校验的台账为最终事实。

---

## 7. E2E 测试用例设计（依托现有测试体系）

### 7.1 设计原则与分层归属

- **先选层**（[testing.md](testing.md) 新增用例规范 6）：包内逻辑→层 1；与 Ruby 基线可比语义→层 2；完整 ReAct 循环→层 3；界面/API 可观测行为→层 4 场景；对外命令形状→层 5 探针；工具脚本可判定任务→层 6；跨进程端到端→层 9 旅程。
- **E2E 优先级**：层 9（真实二进制 + 真实网络栈）> 层 4（进程内真实服务器）> 层 3（进程内 mock 链路）。
- **CI 归属纪律**：层 9 手动/定时、层 4 场景回放手动、层 7/8 不进 CI —— **每个进层 9 的关键回归，必须同时在层 1/2/3/5/6 有 CI 侧护栏**，否则改动只在定时任务里被发现。
- **复现纪律**（testing.md 规范 1）：先固化复现用例，**修复前该用例应为红**；下表"修复前预期"列即验收判据。
- 禁止时间类断言（层 9 README 编写纪律）；mock 剧本是顺序回放，每旅程用 `mock_request_count` 设护栏。

| 用例 ID | 层 | 对应问题 | 位置 | CI |
|---|---|---|---|---|
| 1a | 1 | #1 状态码回落 | `lib/web/handlers_bridge_wbtest.mbt` | ✅ |
| 1b | 9 | #1 + #11 备份下载 | `test/journey/scenarios/web_backup_download_archive.json` | 手动/定时 |
| 2a | 1 | #2 JSON 转义 | `lib/web/router_wbtest.mbt` | ✅ |
| 2b | 9 | #2 用户输入进错误消息 | `test/journey/scenarios/web_error_body_json_safety.json` | 手动/定时 |
| 3a | 9 | #3 stdout 污染 | `test/journey/scenarios/cli_stdout_json_clean.json` | 手动/定时 |
| 4a | 1 | #4 updated_at | `lib/web/handlers_wbtest.mbt` | ✅ |
| 4b | 9 | #4 排序反映活跃度 | `test/journey/scenarios/web_session_updated_at_order.json` | 手动/定时 |
| 7a/8a/9a | 1+3 | #7/#8/#9 接收侧 | `test/e2e/`（IM mock）+ `lib/channel/*_wbtest.mbt` | ✅ |
| 10a | 3 | #10 MCP stdio server | `test/e2e/mcp_server_wbtest.mbt`（spawn 真实二进制） | ✅ |
| 10b | 5 | #10 契约探针更新 | `cmd/selftest.mbt` | ✅ |
| 13a | 9 | #13 trash 真实数据面 | `test/journey/scenarios/web_trash_roundtrip.json` | 手动/定时 |
| 12a | 9 | #12 快照 diff | `test/journey/scenarios/web_time_machine_diff.json` | 手动/定时 |
| 14a | 3 | #14 e2e flaky | `test/e2e/scenarios_wbtest.mbt`（改断言） | ✅ |
| 18a | 1/5 | #18 死代码清理后的真实加载路径 | `cmd/hook_loader_wbtest.mbt` | ✅ |
| 20a | 1 | #20 browser.yml/uptime | `lib/server/browser_manager_wbtest.mbt` | ✅ |

### 7.2 前置扩展（测试基建缺口，须先补）

| ID | 缺口 | 位置 | 必要性 | 状态 |
|---|---|---|---|---|
| **P-A** | **JSON 路径不支持数组下标**（`journey_json_walk` 与 `json_path_value` 只走对象键） | `test/journey/context.mbt:155`、`test/web/web_e2e_adapter.mbt:310` | 必需：4b 的排序断言（`sessions.0.id`）与未来所有列表/排序类断言 | ✅ 已落地（2026-09-23）：两处遍历均支持数字段索引，越界/类型不匹配返回 `None`；`test/journey/context_wbtest.mbt` 3 例覆盖 |
| **P-B** | **断言词表缺 3 种**：`stdout_not_contains`、`stderr_not_contains`、`json_path_ne` | `test/eval/assertions.mbt`（枚举 + 解析 + 序列化）、`test/journey/assert_journey.mbt`（求值） | 必需：3a（stdout 不得含诊断行）、4b（updated_at 须变化） | ✅ 已落地（2026-09-23）：词表 29 → 32 种；`json_path_ne` 语义为"路径必须解析成功且值不同"；`test/eval/assertions_wbtest.mbt` 覆盖往返 |
| **P-C** | **journey 驱动无"向子进程 stdin 写帧"步骤**（`spawn_bin`/`wait_child` 只读 stdout） | `test/journey/`（步骤动作表） | 仅当 #10 走层 9 时需要；本设计改用层 3 集成 | — 未启用（设计已绕开） |
| **P-D** | **IM mock（Telegram/DingTalk/企微 平台接口仿真）+ home 种子**（现有 journey mock 只仿真 LLM 上游；`seed` 仅覆盖工作区） | `test/e2e/` 新 mock + journey 运行器 | 7b/8b/9b 层 9 版本需要；本设计主线走层 1+3 | — 未启用（设计已绕开） |

> P-A/P-B 已作为共享基建落地（含各自单测与 `docs/testing.md`、`test/journey/README.md` 的同步）；P-C/P-D 仅在未来要把 #7~#10 也搬进层 9 时才需要。

### 7.3 逐项用例设计

**1a + 1b（#1 状态码回落）**
- 1a（层 1，CI）：表驱动断言 `response_to_core` 对 200/201/204/400/404/**500/501/503**/429 的映射。现状 500/501/503 均落 `ok()` → **红**。
- 1b（层 9）：`spawn_server` → `POST /api/backup/run`（capture 备份 id）→ `GET /api/backup/download/{capture:id}` → 断言 `status_eq 200` + `header_contains Content-Disposition attachment` + `body_length_gt 100`。现状：501 被 bridge 吞成 200 且 body 是 JSON 元数据 → header 断言 **红**。修复后与 #11 联合转绿。**该用例同时是 #11 的验收**。

**2a + 2b（#2 JSON 转义）**
- 2a（层 1，CI）：`HttpResponse::not_found("a\"b{c}")` 的 body 必须可被 `@json.parse` 且 `error` 字段等于原文 → 现状 **红**。
- 2b（层 9）：`http DELETE path="/api/channels/a%22b%7Bc%7D"`（id 含 `"` 与 `{}`，命中 `handlers_channels.mbt:622` 的 `"Channel not found: \{id}"` 插值）→ 断言 `status_eq 404` + `json_path_eq path="error" value="\"Channel not found: a\\\"b{c}\""`。**关键**：`json_path_eq` 先 parse body，非法 JSON 即判红 → 现状 **红**，修复后绿。

**3a（#3 stdout 污染）**
- 层 9：`spawn_cli`（`json: true`、`mode: auto_approve`）+ `wait_child` → 断言 `exit_code 0` + `stdout_json_path_eq path="status" value="\"Success\""`（末行仍是合法 JSON）+ **`stdout_not_contains "[stream-summary]"`** + `stderr_contains "[stream-summary]"`（修复后诊断走 stderr）。现状 stdout 含诊断行 → **红**。依赖 P-B。

**4a + 4b（#4 updated_at）**
- 4a（层 1，CI）：`build_session_summary`（`handlers.mbt:9-44`，统一供列表/创建/详情）在 SessionData 携带真实 `updated_at` 时应投影该值 → 现状恒等于 `created_at`，**红**。
- 4b（层 9）：创建顺序与活跃顺序**刻意错开**以避免时间戳粒度抖动——`POST /api/sessions`（A，capture id）→ `POST /api/sessions`（B，最后创建）→ `ws_connect`/`subscribe` + chat 到 A（mock content 1 步）→ `GET /api/sessions` → 断言 `json_path_eq path="sessions.0.id" value="{capture:A.id}"`。现状按 `created_at` 排序 → `sessions[0]` 是 B → **红**；修复后 A 因最近活跃排首位 → 绿。依赖 P-A。
- 实现要点（写入 #4 spec）：排序 comparator 需**确定性 tie-break**（同时间戳时按 id），否则同秒活跃仍可能抖动。

**7a/8a/9a（#7/#8/#9 渠道接收侧）**
- 层 1+3（CI）：在 `test/e2e/` 复用 raw TCP mock 模式新增平台 mock —— ①Telegram：服务 `getUpdates`（回放一条 message update 后空轮询）与 `sendMessage`；②企微/钉钉：WS mock（crescent 起 WS 或 `@async.websocket`）服务握手/心跳/事件帧。
- 断言：① 入站消息被投递到 ChannelManager/agent handler（回调计数 ≥1）；② 出站回复到达 mock（mock 侧请求计数）；③ 长轮询/WS 断开时退避重连且不崩（可注入短退避）。
- 现状 `start()` 为诚实报错 → **红**（报错即失败）。层 9 版本（7b/8b/9b）需 P-C/P-D，列为可选增强。

**10a + 10b（#10 cli_mcp stdio server）**
- 10a（层 3，CI）：spawn **真实二进制** `cmd.exe mcp`，经 `@process` 管道写 `initialize` → 断言 result 含 protocolVersion/capabilities；写 `tools/list` → 断言含内置工具名；写 `tools/call` → 断言在沙箱内真实执行。现状子命令 println + `exit 1` → **红**。
- 注意：Windows 命名管道上的阻塞读取消语义是已登记的上游缺口（WP-3.5），该集成测试可能需沿用相同的平台跳过策略并在注释写明根因。
- 10b（层 5）：`selftest` 的 `mcp_unavailable` 探针随契约变更更新（从"不可用报告 exit 1"改为 server 模式形状），防探针与新契约漂移。

**12a（#12 快照 diff）**：`ws` 聊天触发一次文件编辑（mock `tool_calls`）→ GET 任务 diff 端点 → 断言 `status_eq 200` + `body_contains "---"`（真实 unified diff）。现状 stub → **红**。本项为滑点高危，用例先冻结为 spec 的验收定义。

**13a（#13 trash 接线）**：`POST /api/sessions`（capture id）→ `DELETE /api/sessions/{id}` → `GET /api/trash` 断言 `body_contains "{capture:id}"` **且** `file_exists "{home}/.mbopenclacky/trash/..."`（**磁盘证据用于区分 stub 与真实数据面**——stub 模型可让 REST 层"看起来"通过）→ 恢复路由 → `GET /api/sessions/{id}` 断言 `status_eq 200` + `json_path_eq path="id" value="{capture:id}"`。trash 路由组已存在（`server.mbt:669-699`）。

**14a（#14 e2e flaky）**：修改 `test/e2e/scenarios_wbtest.mbt` 的 `assert_retry_intervals`——**只保留下界判失败**（`@async.sleep` 只会因 CPU 争抢变长、不会变短，故"未退避"是可靠信号），**上界改为仅打印诊断、不再判失败**（原 `[2000, 20000]ms` 窗口在高负载下被 22,768ms 越界击穿，整条测试二进制以 `0xc0000409` 崩溃）。新增不 sleep 的确定性用例（合成时间数组：正常 5s / 膨胀 22,768ms / 多段膨胀），证明不再假红；退避是否精确 5s 仍由层 1 `llm_caller_wbtest.mbt` 承担。

**18a（#18 死代码清理）**：删除 `lib/hook/shell_loader.mbt` 与 `lib/hook/hook_wbtest.mbt:69` 相关用例后，为**幸存的真实加载路径** `cmd/hook_loader.mbt:27 load_shell_hooks` 补层 1 白盒（临时目录放 `.toml`/`.json` → 断言解析结果；非目标扩展名跳过；目录缺失返回空）。验收另加 `grep ShellHookLoader` 0 命中。

**20a（#20 browser_manager）**：层 1 白盒——`browser.yml` 解析（临时目录）、`uptime` 计算（注入 `started_at`）、配置写回。现状 `started_at = Some(0)` → **红**。层 4/9 的 API 版本（状态端点字段存在且 `uptime_ms > 0`）作为可选增强。

**#19（browser 截图约束）**：可测部分是"工具 schema 不广告未执行参数"——放层 6（`test/eval/tasks/` 任务断言 registry 暴露的 schema）或层 5 探针；若实现 libpng 尺寸裁剪，再加层 1 白盒（构造超限 PNG 断言输出 ≤ 上限）。真实截图链路需 Chrome + MCP daemon，**不纳入自动化**，如实标注为环境依赖项。

### 7.4 不适合 E2E 的项与验收替代

| 问题 | 为何无 E2E 用例 | 验收替代 |
|---|---|---|
| #5 mooncakes 发布 | 发布是外部动作，非运行时行为 | registry 在线可见 0.2.0；发布前后四道闸门（`moon check -d`/全量测试/`known_gaps.sh check`/`repo_stats.sh check`）全绿 |
| #6 文档校准 | 文档矛盾不可断言 | 三处矛盾人工复核消失 + `repo_stats.sh check` 绿；可考虑把"§7/§8 数字一致"纳入脚本校验（脚本改动，另议） |
| #15 Ruby 对标 | 属统计口径（层 8，不进 CI） | `test/capability/README.md` 增两侧对标规程（同模型同参数、每任务 ≥5 trials、判分口径对齐）+ 对比报告 `docs/eval/<date>-vs-ruby.md` |
| #16 任务集扩充 | 同上（层 8） | 新增 `test/capability/tasks/cap-007..NN`（6 → 20~30），每任务须**具备失败可能**（负样本/多步编排）；`eval --live --trials 3` 后若全满分则该批任务无区分度，需重设计 |
| #17 benchmark 门禁 | 规格决策，非行为 | `specs/draft/` 规格（p95 阈值、基线同代、噪声处理）+ 判定器与场景输入补齐 |

### 7.5 执行方式

```bash
# CI 侧护栏（1a/2a/4a/7a-9a/10a/10b/14a/18a/20a）
moon test --release $(find lib cmd test -name moon.pkg | sed 's|/moon.pkg$||')
"$BIN" selftest --repo .                       # 层 5（含 10b）

# E2E 侧（1b/2b/3a/4b/12a/13a；不进 CI，手动或定时）
"$BIN" journey --repo . --filter web_ --verbose
"$BIN" journey --repo . --filter cli_stdout_json_clean --verbose
```

> 建议实施顺序：**P-A/P-B 基建 → 1a/2a/4a（CI 护栏，修复前红）→ 1b/2b/3a/4b（层 9）**，与 §4 第 1 周（Spec A + Spec C）对齐；渠道接收侧用例（7a/8a/9a）随 Spec D1~D3 落地。
>
> **进度（2026-09-23）**：P-A/P-B 已落地（见 §7.2）；**1a/2a 已落地**于 `lib/web/response_fidelity_wbtest.mbt`（#1/#2 的修复由并发会话落地，闸门随之移除、断言已全文生效）。**第二批（本日）**：**14a 已落地**（只保留下界判失败 + 上界改诊断 + 确定性回归用例，见 §7.3）；**层 9 的 2b/3a/4b 三个场景由并发会话写出**，经逐份核对后修复其中两处可证缺陷——4b 的 `capture: "id_a"` 不是合法响应路径（创建响应为 `{"session":{...}}`，capture 键即路径且会互相覆盖，改为只捕获 `session.id`）且终局断言缺 stringify 形式（改用确定性会话名 `sessions.0.name`，避开秒级时间戳同秒相等导致的抖动）；2b 的百分号编码到不了 handler（crescent `Event::param` 不解码），已改性为原样引号并在 description 写明理由，防止被"顺手"改回而静默失效。**4a 已落地**（并发会话，经核对）：`lib/web/handlers_wbtest.mbt` 两例——真实投影透出 + 旧会话（空 `updated_at`）回落 `created_at`；`SessionData` 已新增 `updated_at`，共享助手 `session_updated_at`（`handlers.mbt:9`）供 REST 与 WS 两侧复用。**18a 已落地**：新增 `cmd/hook_loader_wbtest.mbt`（4 例：缺目录→空列表、TOML 分节/引号剥离/`enabled=false`、JSON 解析并跳过无名条目、混入 `.txt` 与畸形内容不抛错）——为 #18 删除 `lib/hook/shell_loader.mbt` 死代码前，先给幸存真实路径加护栏。**1b 已落地**（并发会话，经核对）：`POST /api/backup/run`（`handle_backups_create`）返回 **201** 且响应根级有 `id`（故 `capture: "id"` 成立）；`response_to_core` 已扩展为 `body_bytes → raw_body` 并搬运 `resp.headers`，所以 ZIP 字节与 `Content-Disposition` 能过桥。**仍未落地的用例**：7a/8a/9a（依赖 #7/#8/#9 接收侧）、10a/10b（#10）、12a（#12）、13a（#13）、20a（#20）——各自等待对应实现，不做提前红用例。
>
> **本批验证**：`moon test test/e2e --filter "*load-inflated*"` **1 passed**（输出两条 `[diag]`，证明 22,768ms / 26,000ms 不再判失败）；`moon test cmd --filter "load_shell_hooks*"` **4 passed**。发布口径全量 **3,994/3,994**（+7：本批 5 例 + 并发会话 2 例）、`lib/mcp` 96，`moon check -d` 全绿；`repo_stats`（`--test-count 3994`）与 `known_gaps` 两闸门复验绿。
>
> **台账闭环（本批顺手完成）**：并发落地的 #11 与 #4 移除了三处标记，`known_gaps.sh check` 因此转红；已按纪律 `generate` 重扫（86 → 84 命中）并把 curated 行改判——`handlers_backup.mbt:649/670` → `fixed`（#11 备份 ZIP：`build_backup_zip` + `application/zip` + 500 `json_status`，原双层嵌套隐患一并清除）、`handlers_ws.mbt:283` → `fixed`（#4）。另新增一行：`lib/agent/diagnostics.mbt:9` → `retracted`（注释里的 "stub" 指实现 stderr 路由的 C stub 本体，非占位；建议后续并入 §抑制规则 的 C 辅助文件族）。
>
> **3a 的观察**：`cli_stdout_json_clean.json` 里 `stdout_not_contains "[skills]"` 目前是 **vacuous** ——`lib/agent/skill_manager.mbt:37` 的 `[skills] … overrides an existing skill` 只在同名技能覆盖时触发，旅程沙箱不会发生（要做实需 home 种子 = P-D）；`[stream-summary]` 那几条是有效断言。

---

## 8. 修订记录

**v3（2026-09-23，补充 E2E 测试用例设计）**：新增 §7——20 项逐一给出分层归属（层 1/3/5/9 与 CI 归属）、15 个用例 ID 与具体步骤/断言/修复前预期、3 处测试基建前置扩展（P-A JSON 路径数组下标、P-B 断言词表补 `stdout_not_contains`/`stderr_not_contains`/`json_path_ne`、P-C/P-D 为可选的驱动与 IM mock）、5 项"不适合 E2E"的验收替代。设计已按代码核实：断言词表 30 种（`test/eval/assertions.mbt`）、JSON 路径仅对象键（`context.mbt:155`、`web_e2e_adapter.mbt:310`）、backup download 为 bridge 路由（`server.mbt:524`）、`build_session_summary` 为会话投影单一修复点（`handlers.mbt:9-44`）、错误消息插值用户输入的 4 处（`handlers_channels.mbt:622` 等）。

**v2（2026-09-23，对抗性审查后修订）**。审查方法：对 v1 全部 20 条逐条代码级核实（违反"gap 文档是假设非事实"的教训正是 v1 的主要错误来源）。关键变更：

| 类型 | 变更 |
|------|------|
| 新增 | **#5 mooncakes 0.2.0 发布**（反馈报告 P1，v1 遗漏的全表性价比最高项）；**#14 e2e 退避断言 flaky**（反馈报告 P3 新发现，已复现一次） |
| 重写 | **#10 cli_mcp**：原"需子进程 FFI"系继承 `cli_mcp.mbt` 过期注释（stdio native 已真实实现）；真实阻塞是自身 stdin 读取 + server 侧协议面 |
| 降级 | **worker 重启**（原 P1 → 范围外）：`ServerMaster` 在 `cmd/`/`lib/web` 零调用，worker 模式未接入运行时 |
| 变性 | **shell_loader**（原 P2 "实现 YML 解析" → #18 死代码删除）：生产代码零调用，真实加载路径在 `cmd/hook_loader.mbt`；`execute_hook` 无条件 `Allow` 是静默放行陷阱 |
| 修正 | **#16 任务数 4 → 6**（继承 project-status §7 过期口径，§8 已写 6）；**#15 现状补充**（已有两份单侧报告 + 定期档）；**#11 成本下调**（`lib/zip` 已有 `create_zip`）；**#13 方向修正**（接线到已存在的 trash_manager 工具面，非新建模型）；**#4 范围补全**（`handlers.mbt:21` 第二处）；**#1 补现存受害者**（backup 501 被吞成 200）与 #11 耦合；**#3 补两条低成本路径**；**#20 确认现成原语** |
| 结构 | §0 前提句修正（代码面清零 ≠ 发布面清零）；#6 文档校准脱离复现用例要求；§3.1 流程分级（9 个 spec + 轻流程 + 发布动作，不再对 20 项全套 Harness）；§6 DoD 滑点对象改为 #10/#12 并要求依赖证据；§2 范围外补 4 条（worker 重启、SQLite 口径、execution-plan §3.1 遗留三项） |

> v1→v2 未变的核心判断：P0 静默假成功三项（#1/#2/#3）的选取与排序、渠道接收侧 P1 位置、评测对标 P2 位置、诚实纪律与验证基线命令。
