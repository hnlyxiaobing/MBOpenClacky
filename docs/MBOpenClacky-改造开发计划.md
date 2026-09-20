# MBOpenClacky「契约化」改造开发计划（9/11 – 9/24，13 天）

> 配套文件：`MBOpenClacky-一页项目说明.md`、`MBOpenClacky-参赛策略推演.md`
> 基线：`main@c4b3fa4`（2026-08-28），MIT，native 目标
> 验收日 / 报名截止：**2026-09-24**

---

## 0. 前置确认（动手前 30 分钟做完）

| 项 | 确认内容 | 若为否则 |
|---|---|---|
| 仓库权限 | 是 `hnlyxiaobing/MBOpenClacky` 的 owner，还是 fork 后开发？ | fork 后在本期 PR 中说明"上游来源 + 本期新增"，满足"实质新增工作" |
| 报名 | 飞书表单已提交（参赛信息 + 仓库 + 本页说明）；已加入赛事交流群 | 立即完成，否则影响奖励 |
| 工具链 | MoonBit 版本、`moon check`、`moon test --release` 本地全绿 | 先修环境，再开新工作 |
| 模型 Key | 至少 1 个真实 Provider key（DeepSeek / Kimi / GLM 之一）可用于 `cmd eval` | 先跑 mock；真模型评测作为 stretch 并如实标注 |
| 入口确认 | CLI 现为 `moon run cmd -- ...`；release 产物路径以实际为准 | 用 `moon build --target native --release cmd` 后核对产物名 |

**范围冻结原则**：本计划 P0+P1 为**承诺验收范围**；P2 为**加分 stretch**；任何超出以下内容的改动一律进 `docs/known-gaps.md`，不在本期实现。

---

## 1. 交付物定义（Definition of Done）

### P0-1 公共 API 闸门（`.mbti` + CI diff）
- 对 `lib/` 与 `cmd/` 各包生成 `pkg.generated.mbti` 并提交入库。
- CI 新增步骤：重新生成 → `git diff --exit-code` → 有未提交差异即失败。
- **DoD**：改动任一公共符号而不提交 `.mbti`，CI 必红。

### P0-2 真话台账（`docs/known-gaps.md`）
- 脚本扫描全部 `TODO` / `FIXME` / `not implemented` / `placeholder` / `Err("` ，生成带 `file:line` 的清单。
- 每条含 `status: open | fixed | retracted` 与所属交付物；CI 校验引用的文件/行存在。
- 修正 `README.md` 中"MCP 协议：Stdio/HTTP 传输"的不实声明；修正 `project-status.md` 与本页冲突的数字（以 CI 输出为唯一来源）。
- **DoD**：`known-gaps.md` 与代码一致；README 不再声称 HTTP MCP 可用。

### P0-3 CLI 契约探针（`cmd selftest`）
- 以 argv 数组（不过 shell）执行 CLI，断言：退出码（zero/nonzero/精确值）、stdout 格式（json/json_lines/text/empty）、stderr 策略（干净/必须含某串）、禁止串（`Failure(` / `Panic(`）。
- 覆盖：`--help`、`--version`、`run --dry-run`、`sessions list`、一个必然失败路径。
- 同一组断言分别跑 `moon run cmd` 与 release 原生二进制，输出差异报告。
- **DoD**：一条命令在 CI 中确定性通过；`moon run` 与原生二进制的差异被记录而非隐藏。

### P1-1 类型化引擎协议（`lib/protocol/`）
- 新建叶子包 `lib/protocol/`（仅依赖 `moonbitlang/core/json` 等基础库，**不依赖引擎**）。
- 定义 `Event` 枚举与 `Command` 枚举；`to_json` 为唯一作者、`parse` 为逆；提供往返 property 测试。
- 把 `lib/web/protocol/events.mbt`（`MappedWsEvent` + 手写 `Json::object`）与 `types.mbt` 的事件字面量迁移进来；Web（`lib/web/handlers_ws.mbt`）、TUI、CLI 三端改用穷尽匹配。
- **DoD**：`lib/protocol` 之外不再有手写事件 JSON 字面量；**故意新增一个 `Event` 变体时，三端编译失败**；往返测试全绿。

### P1-2 可回放会话日志（append-only JSONL）
- 新会话格式：首行 header（`version`/`session_id`/`created_at`），其后每行一个事件 `{seq, unix_ms, type, ...}`，`seq` 连续。
- `append` 不可变；上下文压缩**只追加** `Summary(from_seq, to_seq)`，投影时跳过被覆盖事件，**绝不改写原始事件**；尾部半行容错读取；`session.lock` + 陈旧快照检测。
- 旧 JSON 会话提供**只读导入**，不就地改写。
- 新增 `cmd inspect <session.jsonl>`：离线渲染时间线（文本即可）。
- **DoD**：给定 `.jsonl` 可离线回放；截断最后一个字节仍能恢复；压缩前后原始事件字节完全一致。

### P2 能力评测（stretch）
- 在已有 `test/eval/eval_engine.mbt` 基础上分层：`eval/tool_harness`（确定性，进普通 `moon test`）+ `eval/prompt_task`（真模型，opt-in，N 任务 × M 重复、`--min-successes`、`--prompt-label`）。
- **评分向量**：任务完成 / 验证纪律（是否补测试并真跑）/ 改动质量 / 修复效率（turn 数）/ 成本与缓存。
- 首轮：**5 个任务 × 3 次重复**，任务取自本仓库自身 backlog（Bug 或小 feature）；产出 JSON + 可读报告 `docs/eval/2026-09.md`。
- **DoD**：一条命令产出报告；确定性 harness 在普通 `moon test` 中通过；真模型结果如实标注波动与成本。

### P3 验收包（`docs/acceptance.md` + 可执行文档）
- README 的每条安装/运行/演示命令都变成可执行测试（cram 或等价 `moon test` 包装）。
- 录制 ≤3 分钟演示；`docs/acceptance.md` 逐条对应官方验收 6 条并给出复现命令。
- 打 tag `v0.2.0-hackathon`。

---

## 2. 逐日排期（13 天）

> 约定：`D1 = 9/12`。每天至少 1 次 commit；每个交付物一个 Issue + PR。

| 天 | 日期 | 主要工作 | 当日产出（可验证） |
|---|---|---|---|
| D0 | 9/11 | 报名、入群、开 5 个 Issue、跑通本地 `check/test`、确认范围冻结 | 报名截图 + Issue #1–#5 |
| D1 | 9/12 | 全仓 stub/TODO 扫描；生成 `docs/known-gaps.md` 初版；定位 README 不实声明 | commit：known-gaps v1 + README 修正 |
| D2 | 9/13 | 生成并提交 `.mbti`；CI 加 `git diff --exit-code` 闸门；warning 预算 ratchet 到当前基线 | PR：`ci: gate public API` |
| D3 | 9/14 | 实现 `cmd selftest` 契约探针；覆盖 5 组用例；记录 `moon run` vs 原生差异 | PR：`feat(cli): contract probes`，CI 绿 |
| D4 | 9/15 | 协议 spike：盘点全部 WS 事件与前端消费者；写 ADR-0001（叶子包边界） | ADR + 事件清单 Issue |
| D5 | 9/16 | 建 `lib/protocol/`；定义 `Event`/`Command` + `to_json`/`parse` + 往返测试 | PR：protocol skeleton，测试全绿 |
| D6 | 9/17 | 迁移 Web 端（`handlers_ws.mbt` 去字面量）；TUI/CLI 接入；提交 `.mbti` | PR：三端穷尽匹配；新增变体演示编译失败 |
| D7 | 9/18 | 设计 JSONL 会话 schema；实现 append/投影/容错读；写迁移导入 | PR：session log core |
| D8 | 9/19 | 压缩改为 append-only `Summary`；`session.lock` + 陈旧快照检测 | PR：compaction + lock，测试含截断恢复 |
| D9 | 9/20 | 实现 `cmd inspect`；旧 JSON 只读导入；端到端回放测试 | PR：inspect；演示脚本 |
| D10 | 9/21 | 评测分层骨架；确定性 `tool_harness` 进 `moon test` | PR：eval harness（确定性） |
| D11 | 9/22 | `cmd eval` 真模型 5×3；评分向量；产出报告 | `docs/eval/2026-09.md` + 原始 JSON |
| D12 | 9/23 | README 命令可执行化（cram/等价）；修 Known Gaps 中已闭合项 | PR：executable docs |
| D13 | 9/24 | `docs/acceptance.md`、≤3 分钟演示、打 tag、提交验收 | tag `v0.2.0-hackathon` + 验收提交 |

**缓冲策略**：每天预留 1–2 小时处理"真实数字与文档不符"的意外；若 D6 未完成协议迁移，则砍 P2 保 P0+P1，并在 Known Gaps 写明。

---

## 3. 质量闸门矩阵（CI / 本地）

| 命令 | 覆盖 | 进 CI？ |
|---|---|---|
| `moon check` | 全仓类型检查 | 是，必须 |
| `moon info` + `git diff --exit-code` | 公共 API 冻结 | 是，新增 |
| `moon test --release` | 白盒 + 差分 + 确定性 eval harness | 是，必须 |
| `moon test`（debug） | 受编译器 ICE 影响，**如实标注不可用** | 否，记入 Known Gaps |
| `moon check --target wasm-gc` | wasm 仅检查 | 非阻塞，如实标注 |
| `cmd selftest` | CLI 契约 + 原生/`moon run` 一致性 | 是，新增 |
| `cmd eval --offline` | 确定性评测 | 是，新增 |
| `cmd eval --live`（真 key） | 真模型 5×3 | 否，opt-in 本地跑 |
| `known-gaps` 校验脚本 | 台账与代码一致 | 是，新增 |
| warning ratchet | warning 数不得增加 | 是，新增 |

---

## 4. 风险登记与触发条件

| 风险 | 触发信号 | 立即动作 |
|---|---|---|
| 13 天不够 | D6 结束协议未接入 ≥2 端 | 砍 P2，保 P0+P1；Known Gaps 记录 |
| 协议迁移面超预期 | 事件字面量散落 >10 文件 | 先抽协议 + 保留适配层，不做大爆炸式替换 |
| 会话迁移破坏数据 | 导入后投影与旧数据不一致 | 新格式独立落盘，旧数据只读，打快照后再切 |
| 真模型评测不稳定/超预算 | 单任务成本或时延不可控 | 降到 3×2、换成小任务，报告注明限制 |
| 编译器/工具链阻塞 | `moon test` debug ICE 复发 | 维持 `--release`，写入 Known Gaps，不在此纠缠 |
| 范围被"顺手加功能"侵蚀 | PR 出现新渠道/Provider | PR 直接拒收，转 Issue 标注下一期 |

---

## 5. 合规清单（验收前逐项打勾）

- [ ] 仓库 public，LICENSE 为 MIT 且未被移除。
- [ ] `NOTICE` 披露：上游 `clacky-ai/openclacky`（MIT）、依赖来源、参考的设计（OpenSeek，未复制代码）。
- [ ] README 首屏说明本期新增工作与上游关系。
- [ ] 全部改动有连续 commit 与关联 Issue/PR。
- [ ] AI 使用声明写入 README / `docs/ai-usage.md`：目标与质量由人负责、AI 产出须过三类闸门。
- [ ] `docs/known-gaps.md` 如实列出未完成项（含 debug 测试、wasm、MCP HTTP、真模型波动）。
- [ ] 演示可在 3 分钟内、从全新 clone 复现。

---

## 6. 验收自检（对照官方 6 条）

| 官方标准 | 自检命令 / 证据 |
|---|---|
| MoonBit 为主 | 本期新增全部为 `.mbt`；`git diff --stat main..HEAD` 无其他语言新增实现 |
| 仓库公开、连续提交 | `git log --since=2026-09-11 --oneline` 覆盖每一天；Issue/PR 列表 |
| 能够运行 | `moon build --target native --release cmd` → `cmd selftest` / `cmd inspect` / `cmd eval --offline` 全绿 |
| 工作有效 | `.mbti`、`lib/protocol/`、JSONL 会话、`cmd eval` 均为基线不存在的新结构 |
| 开源合规 | LICENSE + NOTICE + README 来源说明 |
| AI 可解释 | 三类机器闸门 + `docs/ai-usage.md` |

---

## 7. 本期之后（不放进本期验收，写入路线图）

按 OpenSeek 纪律排序，作为下一期候选：类型化 fail-closed 审批（Rejected/Cancelled/Unavailable 三分）→ 子代理进程级隔离 + 预算 + 类型化报告 → 沙箱与写范围工具化 → `goal/plan/steer/job` 运行时原语 → 前端契约测试与产品端点探针。
