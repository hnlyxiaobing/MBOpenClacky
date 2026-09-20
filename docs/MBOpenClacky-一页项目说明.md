# 一页项目说明 ｜ MBOpenClacky「契约化」改造

> 用途：黑客松报名时的"一页项目说明"（资格审核据此确认**选题、工作范围、参赛信息**）。
> 建议正文控制在一页内；文末另附**可直接粘贴到飞书报名表单的纯文本版**。

---

## 基本信息

| 字段 | 内容 |
|---|---|
| 项目名称 | **MBOpenClacky：给移植型 AI Agent 装上可证伪的工程契约** |
| 参赛仓库 | https://github.com/hnlyxiaobing/MBOpenClacky （MIT，本期在 `main` 上增量改造） |
| 比赛方向 | 主：**语言与开发工具**（CLI / 开发体验）；次：**Web 与网络基础设施**（事件协议） |
| 参赛者 GitHub ID | `[填写]` |
| 推荐人 GitHub ID | `[填写，无则留空]` |
| 联系方式 | `[填写邮箱/微信]` |

---

## 一句话主张

**冻结功能面，把 MBOpenClacky 的对外承诺——事件协议、会话记录、Agent 能力——从"文档里的说法"变成"任何第三方跑一条命令就能证伪的合约"。**

## 问题：为什么是现在

MBOpenClacky 是一个用 MoonBit **完整重写**的 AI Agent 平台：514 个 `.mbt`、218 条 REST 路由、6 个 IM 渠道、3,843 个白盒测试，功能广度已经足够。它真正稀缺的不是功能，而是**可证伪性**：

1. **公共 API 零机器闸门**——全仓库 **0 个 `.mbti`**，接口变更只靠人工纪律；
2. **前端事件各写各的**——`lib/web/protocol/` 只是 558 行手写 JSON 映射，TUI / CLI 另起炉灶，漂移只能靠人看；
3. **会话不可回放**——`session_store.mbt` 整份 JSON 读写，压缩会改写历史，无法离线复现；
4. **测试答不了真问题**——3,843 个用例全是白盒 + mock LLM，回答不了"接上真模型它到底能不能干活"；
5. **文档与事实脱节**——README 宣称"**MCP 协议：Stdio/HTTP 传输**"，实测 `lib/mcp/http_transport.mbt` 三处 `Err("not implemented")`。

这是工程可信度问题，不是功能问题——恰好与本届黑客松"**这不是提示词比赛**、看工程边界/测试质量/可维护性"的取向正面对齐。

## 本期目标（3 条，均可独立复现）

1. **类型化引擎协议**：把 `lib/web/protocol/` 的手写事件收敛为叶子模块 `lib/protocol/`，定义 `Event` / `Command` 枚举与互为逆的 `to_json` / `parse`，Web/TUI/CLI 共用并**穷尽匹配**；提交 `pkg.generated.mbti`，CI diff 即公共 API 变更记录。
2. **可回放会话日志**：会话落盘改为 **append-only JSONL**（header + 每行一事件 + 连续 `sequence`），压缩只追加 `Summary(from,to)`、绝不改写原始事件；新增 `cmd inspect <session.jsonl>` 离线回放，坏尾行可恢复。
3. **能力评测 + 契约探针**：`cmd eval` 用真模型跑 **5 个任务 × 3 次重复**，输出评分向量（完成率 / 验证纪律 / 改动质量 / 成本）；`cmd selftest` 对 CLI 断言退出码、stdout 合法 JSON、stderr 干净，并对比 `moon run` 与 release 原生二进制。

## 交付物与验收（独立验证方式）

| 交付物 | 第三方如何验证 |
|---|---|
| `lib/protocol/` + `.mbti` | `moon info` 产物入库、CI diff 拦截；**新增一个事件变体，未适配的前端编译失败**；`to_json`∘`parse` 往返测试 |
| append-only 会话 + `cmd inspect` | 给定一个 `.jsonl` 可离线回放；压缩后原始事件字节不变；截断尾行仍能恢复 |
| `cmd eval` 评测报告 | 一条命令产出报告（5×3 + 评分向量 + 成本），可重跑 |
| `docs/known-gaps.md` | 由 `TODO` / `not implemented` 扫描生成并被 CI 校验，每条 `status: open/fixed/retracted`；README 不实声明已修正或撤回 |

## 明确不做（本期边界）

不新增 IM 渠道 / Provider / 前端重写；不实现 MCP `resources`/`prompts`；不动计费、白标、遥测的服务端；不追求 wasm 全量通过（**以 native 为唯一验收目标**）。

## 13 天计划（9/11 – 9/24，公开提交）

- **D1–D3 真话基线**：`.mbti` 入库 + CI diff 闸门；生成 `known-gaps.md`；修正/撤回 MCP HTTP 声明；`cmd selftest` 契约探针。
- **D4–D9 协议 + 会话**：`lib/protocol/` 落地并三端接入；append-only JSONL 会话 + `cmd inspect`；迁移只读导入。
- **D10–D12 评测**：`cmd eval`（5×3 + 评分向量）、确定性 tool_harness、发布评测报告。
- **D13 验收包**：README 命令全部可执行化、演示与 `docs/acceptance.md`、打 tag。

**提交纪律**：每天至少 1 次 commit；每个交付物一个 Issue + PR；关键取舍写入 `docs/decisions/`；保留失败与修复轨迹。

## 开源合规与 AI 使用声明

- **许可**：本项目 MIT；上游 `clacky-ai/openclacky`（MIT）及移植来源、参考过的设计（如 MoonBit 官方 OpenSeek 的协议 / append-only / 评测思路，**不复制代码**）统一在 `NOTICE` 与文档中披露。
- **AI 使用**：开发使用 AI 编程工具，但**目标、范围、验收标准与最终质量由参赛者定义并负责**；AI 产出必须通过"协议往返测试 + 契约探针 + 真模型评测"三类机器闸门方可合入。

---

# 附：可直接粘贴到报名表单的纯文本版

项目名称：MBOpenClacky：给移植型 AI Agent 装上可证伪的工程契约

参赛仓库：https://github.com/hnlyxiaobing/MBOpenClacky（MIT）

比赛方向：语言与开发工具（主）、Web 与网络基础设施（次）

一句话主张：冻结功能面，把 MBOpenClacky 的对外承诺——事件协议、会话记录、Agent 能力——从"文档里的说法"变成任何第三方跑一条命令就能证伪的合约。

问题背景：MBOpenClacky 是用 MoonBit 完整重写的 AI Agent 平台，已有 514 个 .mbt、218 条 REST 路由、6 个 IM 渠道、3843 个白盒测试，功能广度足够；真正稀缺的是可证伪性——全仓库 0 个 .mbti（公共 API 无机器闸门）；lib/web/protocol 只是 558 行手写 JSON、TUI/CLI 各写各的；会话整份 JSON 读写、无法回放；3843 个测试全是白盒与 mock，回答不了真模型下能否干活；README 宣称 MCP HTTP 已支持，实测三处 Err("not implemented")。

本期目标（三条，均可独立复现）：
1) 类型化引擎协议：把手写事件收敛为叶子模块 lib/protocol，定义 Event/Command 枚举与互为逆的 to_json/parse，Web/TUI/CLI 穷尽匹配，提交 .mbti 并由 CI diff 拦截；
2) 可回放会话日志：改为 append-only JSONL（header + 每行一事件 + 连续 sequence），压缩只追加 Summary、不改写原始事件，新增 cmd inspect 离线回放；
3) 能力评测 + 契约探针：cmd eval 用真模型跑 5 任务 × 3 次重复并输出评分向量，cmd selftest 断言退出码/stdout 合法 JSON/stderr 干净并对比 moon run 与 release 原生二进制。

验收方式：新增事件变体时未适配前端编译失败 + 协议往返测试；给定 .jsonl 可离线回放且压缩后原始字节不变；一条命令产出可重跑的评测报告；docs/known-gaps.md 由扫描生成并被 CI 校验，README 不实声明已修正或撤回。

本期不做：不新增渠道/Provider、不重写前端、不实现 MCP resources/prompts、不动计费白标遥测服务端、不追求 wasm 全量通过（以 native 为唯一验收目标）。

计划：9/11-9/24。D1-D3 真话基线与闸门；D4-D9 类型化协议 + append-only 会话；D10-D12 评测 harness 与报告；D13 可执行文档、演示与验收包。每天至少一次 commit，每个交付物一个 Issue + PR。

开源合规：MIT；上游 clacky-ai/openclacky（MIT）与参考来源在 NOTICE 披露（含 MoonBit 官方 OpenSeek 的工程思路，不复制代码）。

AI 使用声明：使用 AI 编程工具，但目标、范围、验收标准与质量由参赛者定义并负责；AI 产出须通过协议往返测试、契约探针、真模型评测三类机器闸门方可合入。
