# MBOpenClacky 优化提升执行计划（可落地开发文档）

> 生成日期：2026-09-21
> 来源：把 [improvement-roadmap.md](improvement-roadmap.md) 的优先级结论，拆成可直接开工的**工作包（WP）**。路线图回答"做什么、为什么"，本文回答"怎么落地、改哪些文件、如何验收"。
> 参考对象：上游 [clacky-ai/openclacky](https://github.com/clacky-ai/openclacky)（Ruby）。
> 事实基线：所有"缺口"以机器校验的 [known-gaps.md](known-gaps.md) 为准；本文不重复逐行清单，只给闭环动作。

---

## 0. 如何使用本文

1. 挑一个工作包（WP-x.y）。
2. 按 Harness 方法论在 `specs/draft/` 建增量 spec（用 `specs/_templates/incremental-spec-template.md`），过对抗性评审后进 `specs/active/`。
3. 实现时在 `moon check` 紧循环里小步推进；执行型工作（接线、改 stub、写测试）用**便宜模型**，仅架构/FFI 内存布局/对抗评审用贵模型（见 `AGENTS.md` 效率协议第 1 条）。
4. 每闭环一个 WP：重跑 `scripts/known_gaps.sh generate` → 对应命中行消失 → 把 curated 台账行状态改 `fixed`；归档 spec 到 `specs/completed/`；在 `docs/CHANGELOG.md` 记一笔；更新本文对应 WP 的状态列。
5. 提交遵循 `feat:`/`fix:`/`docs:` 小写类型前缀，一个 WP 一个逻辑提交。

**状态标记**：`[ ]` 未开始 · `[~]` 进行中 · `[x]` 完成 · `[?]` 待决策门放行 · `[—]` 作废（决策门结果使其失效）。

---

## 1. 全局约定（每个 WP 都适用）

- **验证基线命令**（改动前后各跑一次，见 `docs/testing.md` 一键全跑）：
  ```bash
  moon check                                                       # 0 error / 0 warning（CI 硬闸门）
  moon build --target native --release cmd
  BIN=./_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe
  "$BIN" selftest --repo .                                         # 层 5 CLI 契约
  "$BIN" eval --offline --repo .                                   # 层 6 确定性评测
  moon test --release $(find lib cmd test -name moon.pkg | sed 's|/moon.pkg$||' | grep -v '^lib/mcp$')
  scripts/known_gaps.sh check && scripts/repo_stats.sh check       # 台账与数字闸门
  ```
- **数字口径**：README/CLAUDE/project-status 的规模数字由 `scripts/repo_stats.sh` 生成，**禁止手改** `<!-- BEGIN: repo-stats -->` 块；改了代码规模就跑 `generate`。
- **测试就近**：新测试放 `*_wbtest.mbt`（层 1）或 `test/diff`/`test/e2e`（层 2/3）；不新增顶层目录；一次性产物只落 `_build/`。
- **诚实纪律**：接不通的路径必须返回可诊断的 `Err(...)`，不得静默假成功（stubfix 批次已清零假成功型 stub，勿回退）。

---

## 2. 决策门（开工前必须先拍板）

路线图的核心判断是"不要停在『宣传 > 现实』的中间态"。以下两个门决定 Phase 1 走**接线**还是**降级声明**：

| 门 | 问题 | 选项 A（接线） | 选项 B（降级声明） |
|---|---|---|---|
| **D-A 渠道** | 4 个未接通渠道（飞书/企微/钉钉/微信）本期做吗？ | 执行 WP-1.1~1.4 | 执行 WP-0.2，把 README"6 平台 IM 渠道"改为"6 平台适配器（Telegram/Discord 已接通，其余接线中）" |
| **D-B 媒体生成** | 图/视频/语音生成本期做吗？ | 执行 WP-1.5 | 执行 WP-0.2，把"媒体生成"从亮点移到路线图，明确"视频理解 ≠ 生成" |

> 建议：**D-A 选 A 且先做飞书**（国内主力、富文本解析已完整、HTTP 基础设施齐备）；**D-B 选 A**（`openai_compat.mbt` 已构建好请求体与解析器，只差一次 POST，成本极低）。若资源不足，至少执行选项 B 让文档与现实一致——**不允许两个门都悬空**。

> **放行记录（2026-09-21）**：**D-A = A**（接线，飞书先行；D-B 同步放行 A）。依据：计划建议 + 第一性原理——接线的依赖（`@async/http`、`http_post_json`、`@client.http_post`）已就绪，宣传落差是当前最大可信度损耗；资源不足时可退选项 B，但在本轮内先执行 A 的低成本项（WP-1.5）。

---

## 3. 工作包总览

| WP | 标题 | 优先级 | 门 | 预估 | 依赖 | 状态（核对于 2026-09-22） |
|---|---|---|---|---|---|---|
| WP-0.1 | 品牌资产法律核实与文档统一 | P0 | — | 0.5 天 | — | `[x]` 完成（2026-09-21） |
| WP-0.2 | 宣传口径对齐（降级声明分支） | P0 | D-A/D-B 选 B 时 | 0.5 天 | 决策门 | `[—]` 作废（两门均选 A） |
| WP-1.1 | 飞书 send/receive 接线 | P1 | D-A=A | 1–2 天 | — | `[x]` 完成（2026-09-22） |
| WP-1.2 | 钉钉 send 接线 | P1 | D-A=A | 1 天 | WP-1.1（复用模式） | `[x]` 完成（2026-09-22） |
| WP-1.3 | 企业微信 send 接线 | P1 | D-A=A | 1 天 | WP-1.1 | `[x]` 完成（2026-09-22） |
| WP-1.4 | 微信 send + AES-128-ECB | P1 | D-A=A | 2–3 天 | WP-1.4a 加密原语 | `[x]` 完成（2026-09-22） |
| WP-1.5 | 媒体生成接线（图/语音/视频） | P1 | D-B=A | 1–2 天 | — | `[x]` 完成（2026-09-21） |
| WP-1.6 | 全平台 update/delete_message | P2 | — | 1–2 天 | WP-1.1~1.4 | `[x]` 完成（2026-09-22） |
| WP-1.7 | 渠道配置单一真相源贯通 | P1 | — | 1–2 天 | WP-1.1~1.4 | `[x]` 完成（2026-09-22） |
| WP-2.1 | GEP SkillReflector 做实 | P1 | — | 2–3 天 | — | `[x]` 完成（2026-09-22） |
| WP-2.2 | `cmd eval --live` 真模型评测接线 | P1 | — | 2–3 天 | — | `[x]` 完成（2026-09-22） |
| WP-3.1 | 旧会话 schema 只读迁移投影 | P2 | — | 1–2 天 | — | `[x]` 完成（2026-09-22） |
| WP-3.2 | Web 会话 JSONL 事件流（复议 D3） | P2 | — | 2–3 天 | — | `[ ]` 未开始 |
| WP-3.3 | MCP HTTP 传输 | P2 | — | 1–2 天 | — | `[x]` 完成（2026-09-22） |
| WP-3.4 | 性能基准真实执行驱动 | P2 | — | 2 天 | 先出 spec | `[ ]` 未开始 |
| WP-3.5 | Windows `lib/mcp` 测试挂死排查 | P3 | — | 1–2 天 | — | `[ ]` 未开始 |
| WP-3.6 | TUI 绑定 wire 词表（ADR-0001 后续） | P3 | — | 2–3 天 | — | `[ ]` 未开始 |

> **一句话结论**：17 个 WP 中 **12 个完成、1 个作废、4 个未开始**。已完成的是 P0 与全部 P1/P2 渠道与能力主线（品牌 / 渠道 send / 媒体 / 渠道配置 / GEP 反思 / 真模型评测 / 全平台编辑撤回 / 旧会话只读投影 / MCP HTTP 传输）；
> 未开始的是 4 个 P2/P3 卫生项（WP-3.2、WP-3.4~3.6）。因此 §7 的整体完成定义**尚未达成**。
> 逐项证据与剩余范围见下节 §3.1。

### 3.1 完成情况核对（逐项代码验证，2026-09-22）

**已完成（12 项）**：

| WP | 核对证据 |
|---|---|
| WP-0.1 | `web/PATCHES.md` 的 P0-001 标题即 `resolved in WP-0.1`，并记录六文件替换与 rsync 排除；`web/UPSTREAM_SYNC.md` 不再自相矛盾（仅剩"uses its own brand assets"一处表述）。 |
| WP-1.1~1.4 | `scripts/known_gaps.sh generate` 后飞书/钉钉/企微/微信相关命中全部消失，curated 行转 `fixed`（飞书 14 + 钉钉 6 + 企微 3 + 微信 10 行）。 |
| WP-1.5 | `lib/media/*` 无 "requires HTTP FFI" 命中；台账 media 行全部 `fixed`。 |
| WP-1.6 | `scripts/known_gaps.sh generate` 后 `discord_api.mbt` 5 行 + `telegram.mbt:291` 全部消失，curated 行转 `fixed`（95 → 89）；`Adapter` trait 新增 `delete_message`/`supports_message_deletion` 并由 `AnyAdapter` 分发 6 平台；飞书/Telegram/Discord 的编辑与撤回经本地 mock 真 HTTP 往返；`supports_message_*` 声明与实现一致（不支持撤回的企微/微信/钉钉如实报错）。 |
| WP-1.7 | 渠道端点全部读写 `ChannelManager`（无 `channels_store` 双真相源）；台账「渠道配置不生效」相关行 `fixed`。 |
| WP-3.1 | 参考机 `~/.mbopenclacky/sessions/` 由 **1/32 可列出 → 32/32**（`cmd --list` 无「未列出」提示）；新增 `lib/agent/session_legacy_repr.mbt` 处理 Debug-repr 转储，`lib/message` 容忍旧 Option 包装（`[x]`/`[[...]]`/`type_`）与 `SessionData` 缺字段容忍；`cmd inspect` 对两种旧格式均渲染时间线；文件字节不变（只读投影）。 |
| WP-3.3 | `grep -c "not implemented" lib/mcp/http_transport.mbt` → 0；台账 3 行消失（89 → 86）并转 `fixed`；13 条新测试全部走真实 socket（JSON/SSE 往返、会话回带、503 与拒连报错、SSE 关流报错、另一 id 拒收、batch/url 单测），另有 `McpClient` 经 HTTP 完成握手 + `tools/list` 的端到端一条。 |
| WP-2.1 | `lib/skill/reflector.mbt` 无 `placeholder` 命中；两端点为真实实现；台账 6 行 `fixed`（104 → 98）。 |
| WP-2.2 | `grep -rn "not implemented" cmd/eval.mbt cmd/main.mbt cmd/selftest.mbt` → 0 命中；台账 3 行 `fixed`（98 → 95）；真模型实测 12/12 trial（`docs/eval/2026-09-22.md`）。 |
| WP-0.2 | 决策门 D-A/D-B 均选 A（放行记录见 §2），"降级声明"分支**不适用**，故标 `[—]`。 |

**未完成（4 项）**——以下均为本次逐项核验后的**精确剩余范围**，不是推测：

1. **WP-3.2 Web 会话 JSONL 事件流**（P2）：`SessionLogProducer` 只存在于 `cmd/inspect.mbt`（CLI 路径）；`lib/web` 无任何会话事件日志接线。
4. **WP-3.4 性能基准真实执行驱动**（P2）：`test/benchmark/benchmark_runner.mbt:37-44` 明写"为了简化，我们模拟执行"，`elapsed_ms` 紧随 `BenchmarkTimer::new()` 读取。**实测**（2026-09-22）`cmd benchmark --iterations 3 --warmup 1` 输出 Total/Min/Max/Avg/P50/P95/P99 **全部为 0ms**，且回归报告的场景名显示 `unknown`；`test/benchmark/README.md:52` 已如实说明该限制。
5. **WP-3.5 Windows `lib/mcp` 测试挂死**（P3）：**本次复验仍挂死**（2026-09-22，`timeout 40 moon test --release lib/mcp`）：`mcp.whitebox_test.exe` 无输出、被计时器杀死（exit 143）。故本机全量测试仍需排除该包（Linux CI 全绿）。
6. **WP-3.6 TUI 绑定 wire 词表**（P3）：`lib/tui/agent_hooks.mbt` 仍直接消费引擎 `HookEvent`；ADR-0001 的后续项未启动。

---

## 4. 里程碑

- **M1 可信度速赢（1 天）** `[x]` 已完成（2026-09-21）：WP-0.1 落地（品牌资产替换 + 两份文档统一）；决策门 D-A/D-B 均放行 A，故 WP-0.2 作废。✅ 法律风险消除、文档与现实一致。
- **M2 网络接线（1–2 周）** `[x]` 完成（2026-09-22）：WP-1.1→1.2/1.3/1.5 并行 →1.4 全部接线（`moonbitlang/x/crypto` 提供 AES-ECB，无需 FFI），WP-1.6 补齐全平台编辑/撤回，并顺带闭环 WP-1.7 暴露的四处"配置不生效"断点。
- **M3 能力深度（1 周）** `[x]` 已完成（2026-09-22）：WP-2.1（GEP 反思做实 + 进化日志 + 两端点）、WP-2.2（`cmd eval --live` 真模型评测，首次真模型运行见 `docs/eval/`）。**遗留**：上游 Ruby 侧对标、任务集扩充（均已在路线图 §2.3 记为待办）。
- **M4 卫生与契约（backlog）** `[ ]` 部分完成：WP-3.1、WP-3.3 已完成，WP-3.2、WP-3.4~3.6 未做（核对证据见 §3.1）。均已在台账登记，不构成可信度风险。

---

## 5. 工作包详情

### WP-0.1 品牌资产法律核实与文档统一 `[x]`（P0，先做）

> **完成（2026-09-21）**：与上游 v1.5.0 原件哈希/内容比对，判定 `favicon.svg`、`icon*.svg`、`apple-touch-icon-180.png`、`logo_nav_dark.png`、`favicon.ico` 全部为上游原件 → 设计并替换为 MBOpenClacky 自有品牌（对话气泡 + 终端提示符，`#14B8A6`→`#3B82F6`）；`PATCHES.md` P0-001 归档 Resolved；`UPSTREAM_SYNC.md` 矛盾消除、rsync 排除补 `favicon.ico`；`index.html`/`brand/view.js` 默认品牌字符串同步。DoD 复验：矛盾 grep 通过，六文件与上游哈希全不同。

- **目标**：消除 `web/UPSTREAM_SYNC.md` 自相矛盾（第 16 行"upstream originals still in place"vs 第 84–88 行"own brand assets"），确认 `web/{favicon.svg,icon.svg,apple-touch-icon-180.png,logo_nav_dark.png}` 来源合法。
- **触点**：`web/UPSTREAM_SYNC.md`、`web/PATCHES.md`（P0-001）、四个品牌文件。
- **步骤**：
  1. 与上游 v1.5.0 原件逐文件比对（`diff`/图像比对）；判定是自制还是上游原件。
  2. 若自制：`PATCHES.md` 的 P0-001 标 **Resolved**（保留记录），删掉 `UPSTREAM_SYNC.md` 第 16 行矛盾表述，与第 84–88 行统一。
  3. 若为上游原件：设计并替换为 MBOpenClacky 品牌资产，再执行步骤 2。
- **DoD**：两份文档对品牌资产的表述一致且与磁盘文件相符；仓库不含上游 OpenClacky 品牌资产。
- **验证**：`grep -n "upstream originals still in place\|own brand assets" web/*.md` 无矛盾；人工图像核对。
- **备注**：法律敏感，判定不确定时**保守替换**，不要猜。

### WP-0.2 宣传口径对齐 `[—]`（P0，仅当 D-A/D-B 选 B）

> **作废（2026-09-22 核对）**：决策门 D-A/D-B 均选 A（放行记录见 §2），"降级声明"分支不再适用，本 WP 不执行。
> 其目的（让宣传与代码一致）已由接线本身达成：渠道、媒体、GEP、真模型评测四条宣传线全部做实；`README.md`/`CLAUDE.md`/`docs/project-status.md` 与台账逐项一致（`scripts/known_gaps.sh check` 绿）。
> 下方"目标/触点/步骤"保留为历史预案。

- **目标**：让 README/CLAUDE/project-status 的能力宣传与 `known-gaps.md` 一致。
- **触点**：`README.md`（功能亮点段）、`CLAUDE.md`、`docs/project-status.md` §5.3/§7。
- **步骤**：渠道改为"6 平台适配器（Telegram/Discord 已接通，其余接线中）"；媒体明确"视频理解已实现，图/视频/语音生成待接线"；GEP 收敛为"技能自动创建 + 进化框架（反思环节待接线）"。
- **DoD**：无"已宣传但未接线"的表述；`scripts/repo_stats.sh check` 绿（未动数字块）。
- **验证**：跑全局基线命令；人工比对 README 亮点与 known-gaps。

### WP-1.1 飞书 send/receive 接线 `[x]`（P1，D-A=A）

> **完成（2026-09-22）**：`FeishuApiClient` 六方法（send/update/upload_image/upload_file/
> download/fetch_history）全部经 `@client` 异步传输真接线：upload 走手工 multipart
> 二进制上传（签名 Bytes 化），download 走 `http_get_bytes` + base64，其余走 JSON
> GET/POST/PATCH（`HttpMethod` 新增 `Patch`）；所有响应追加 `code != 0` 业务检查。
> **顺带修正契约缺陷**：`build_send_request`/`build_update_request` 的 `content` 由嵌套
> 对象改为飞书要求的字符串化 JSON（原形状对真实 API 必失败）。`FeishuAdapter::
> update_message` 接通；`start()` TODO 如实化（webhook 接收已由 stubfix-01 承担）。
> DoD 验证：`moon check` 0 错 0 警；`moon test lib/channel lib/client lib/web`
> 1021/1021（含 mock TCP server 六方法真 HTTP 往返 + 业务错误注入）；`selftest`
> 18/18；`eval --offline` 3/3；台账飞书 14 行转 `fixed`；spec 归档
> `specs/completed/2026-09-22_wp-1.1-feishu-wiring.md`。

- **目标**：飞书适配器从"诚实 stub"变为真发送/接收，以 **Telegram 为参考实现**（`lib/channel/telegram.mbt::send_text` 已用 `http_post_json`）。
- **触点**：`lib/channel/feishu_api.mbt`（`send_message`/`update_message`/`upload_image`/`upload_file`/`download_resource`/`fetch_chat_history` 的 `not yet wired` 分支）、`lib/channel/feishu.mbt`（`send_text`/`update_message`）。
- **已具备的基础设施**（无需新造）：`http_helper.mbt` 的 `http_post_json`/`http_get_json`（async，走 `@client.http_post`）、`HttpHeaders`、`TokenCache`（tenant_access_token 缓存）、`FEISHU_API_BASE`、`extract_feishu_message_id`；`feishu_message_parser.mbt` 富文本解析已完整。
- **步骤**：
  1. `send_message`：构建飞书 `im/v1/messages` 请求体 → `http_post_json` → `extract_feishu_message_id`，映射错误码（`http_status_error` 已覆盖 `msg` 字段）。
  2. `update_message`（PATCH）、`upload_image`/`upload_file`（multipart，需确认 `@client` 是否支持 multipart；不支持则先只接 JSON 类接口，multipart 记入台账）、`download_resource`/`fetch_chat_history`（GET）。
  3. tenant_access_token 获取 + `TokenCache` 缓存刷新。
- **DoD**：`feishu_api.mbt`/`feishu.mbt` 不再有 `not yet wired`/`not implemented` 命中（multipart 若受限则单独留台账行）；请求构建与响应解析有 `*_wbtest.mbt` 覆盖；HTTP 路径经本地 mock（参考 `test/e2e/mock_llm_server.mbt` 起 raw TCP）跑通一次。
- **验证**：`moon test --release lib/channel`；`scripts/known_gaps.sh generate` 后飞书行消失 → 台账改 `fixed`。

### WP-1.2 钉钉 send 接线 `[x]`（P1，依赖 WP-1.1 模式）

> **完成（2026-09-22）**：`DingTalkApiClient::open_stream_connection`（POST
> `/v1.0/gateway/connections/open`）与 `download_file_url`（POST
> `/v1.0/robot/messageFiles/download`）从 `not yet wired` 变为真实 HTTP POST +
> 响应解析——缺 `endpoint`/`downloadUrl` 即返回诊断错误，不静默假成功；新增
> `with_base_url` 供离线 mock 验证。`DingTalkAdapter::start`/`stop` 的误导性 TODO
> 改为如实描述（robot 回调经 `/api/webhooks/dingtalk` → `ChannelManager` 到达
> `parse_and_cache_event`；Stream Mode WS 循环是独立工作项），`stop` 顺带清空已
> 缓存的 sessionWebhook。DoD 验证：`moon check -d` 全仓 0 错 0 警；
> `moon test --release lib/channel` 441/441（含 gateway/download 两方法 mock TCP
> 往返 + 401 错误注入 + token 只取一次断言）；台账钉钉 6 行转 `fixed`。

- **触点**：`lib/channel/dingtalk_api.mbt`（`open_stream_connection`/`download_file_url`）、`lib/channel/dingtalk.mbt`。
- **已具备**：`DINGTALK_API_BASE`/`DINGTALK_OAPI_BASE`、`extract_dingtalk_message_id`、`http_post_json`。
- **DoD/验证**：同 WP-1.1（钉钉行从台账消失）。

### WP-1.3 企业微信 send 接线 `[x]`（P1）

> **完成（2026-09-22）**：新增 `lib/channel/wecom_api.mbt`（`WeComApiClient`：
> `gettoken` 取 access_token 并缓存、`message/send` 发送、`errcode != 0` 一律映射
> 为诊断错误）。`WeComAdapter` 从持 `TokenCache` 改为持 `api_client`，`send_text`
> 真实发送（`chat_id` 映射 API 的 `touser`，群聊投递由平台 errcode 如实回报）；
> `start` 注释如实化（接收走 `/api/webhooks/wecom` 路由，WebSocket 收发为独立工作
> 项）；删除零调用方的旧 `build_wecom_message`（与 `build_wecom_send_body` 重复且
> 忽略自己的参数）。DoD 验证：`moon test --release lib/channel` 441/441（含
> token+send 往返、第二次发送复用缓存 token 的计数断言、errcode 40013/81013 注入、
> `api_base` 不可达时的真实传输错误）；台账企微 3 行转 `fixed`。

- **触点**：`lib/channel/wecom.mbt`、`lib/channel/wecom_ws.mbt`（WebSocket 帧构建保留给接收侧）。
- **已具备**：`WECOM_API_BASE`、`http_post_json`；`extract_api_error` 已处理 `errmsg`。
- **步骤**：access_token 获取 + 缓存；`message/send` 接线；WebSocket 收发用 `@async.websocket`（参考 `lib/channel/ws_client.mbt`、Discord 网关 stubfix-07）。
- **DoD/验证**：同 WP-1.1。

### WP-1.4 微信 send + AES-128-ECB `[x]`（P1，依赖加密原语）

> **前置 WP-1.4a 已解，无需 FFI**：`moonbitlang/x/crypto` 提供
> `aes_ecb_encrypt`/`aes_ecb_decrypt`（无填充、要求块对齐）。`lib/channel` 直接
> 导入该包并自实现 PKCS#7 补/去填充，**取消了计划中评估 OpenSSL/BCrypt FFI 的
> 贵模型环节**。
>
> **完成（2026-09-22）**：`weixin_aes_encrypt`/`weixin_aes_decrypt` 从 placeholder
> 变为真实 AES-128-ECB（`weixin_aes_key_from_hex` 校验 32 hex 字符，无填充块路径
> `weixin_aes_ecb_encrypt/decrypt` 单独暴露以便对齐官方向量）；
> `WeixinAdapter::send_text` 走真实 `sendmessage`（文本先 `sanitize_for_weixin`、
> 附上下文 token、`ret != 0` 一律报错并对 `-2` 标注限流），缺 `uin` 时如实报
> `no api_client`；`start` 的 TODO 长轮询注释如实化（接收走
> `/api/webhooks/weixin` 路由）。DoD 验证：FIPS-197 §C.1 官方向量
> （`69c4e0d8…c55a`）+ 加解密往返 + 畸形填充/非块对齐/短密钥错误用例；
> `moon test --release lib/channel` 441/441；台账微信 10 行转 `fixed`。

- **前置 WP-1.4a**：**已解**——`moonbitlang/x/crypto` 提供 AES-ECB，无需 FFI。
- **触点**：`lib/channel/weixin_api.mbt`、`lib/channel/weixin.mbt`。
- **DoD**：AES-128-ECB 加解密有向量测试（对齐微信平台已知测试向量）；send 接通；台账微信行消失。
- **验证**：`moon test --release lib/channel`；加解密往返 `decrypt(encrypt(x)) == x` + 官方向量。

### WP-1.5 媒体生成接线 `[x]`（P1，D-B=A，成本极低）

> **完成记录（2026-09-21）**：四个媒体端点全部接线。`lib/client` 新增二进制传输
> （`http_get_bytes`/`http_post_bytes`，承载语音音频、multipart 上传与生成 URL 下载）；
> `lib/media/openai_compat.mbt` 承载图/视频/语音（JSON + b64/URL 载荷，上游对齐超时
> 240s/600s/120s/30s）并新增 transcription（multipart 二进制上传）；`dashscope.mbt`
> 改为同步 multimodal-generation 上游协议（chat 形状 input + size/n/prompt_extend/
> watermark 参数，图片 URL 下载落盘，因链接会过期）；`gemini.mbt` 直连改为与上游一致
> 的诚实网关重定向错误；生成产物统一落 `{output_dir}/assets/generated/`。
> `lib/web/handlers_media.mbt` 四端点改 async：非法输入/未配置模型返回诊断 400，
> 其余走 MediaGenerator 真实调用；`handlers_bridge.mbt` video/status 如实报告同步
> 执行模型。DoD 验证：`moon check` 0 错 0 警；`moon test --release lib/media lib/web
> lib/client` 689/689 通过；`selftest` 18/18；`eval --offline` 3/3；台账 media 行全部
> 转 `fixed`（`known_gaps.sh check` 一致）。

- **目标**：把 `lib/media` 三个后端从 501 stub 变为真调用。**请求体与响应解析已写好，只差 HTTP POST。**
- **触点**：
  - `lib/media/openai_compat.mbt`：`openai_generate_image`/`openai_generate_speech` —— 已构建 `build_openai_image_request`/`build_openai_speech_request`、已有 `parse_openai_image_response`；补 `@client.http_post({base_url}/v1/images/generations, body, [Authorization: Bearer …], timeout)` 并解析。
  - `lib/media/gemini.mbt`（图/视频）、`lib/media/dashscope.mbt`（图）：同模式。
  - `lib/web/handlers_media.mbt`：把 4 个 501 端点改为调用上述函数（`image`/`video`/`audio/speech`/`audio/transcription`）；`handlers_bridge.mbt` 视频生成同步。
- **DoD**：`lib/media/*.mbt` 无 `requires HTTP FFI - not yet implemented` 命中；请求构建/响应解析有 wbtest；REST 端点在配置了 key 时返回真实结果、未配置时返回可诊断错误（非 501 空壳）。
- **验证**：`moon test --release lib/media lib/web`；`selftest`；台账 media 行消失。
- **注意**：区分**生成**（本 WP）与**视频理解**（FFmpeg 抽帧 + Vision，已实现，勿动）。

### WP-1.6 全平台 update/delete_message `[x]`（P2）

> **完成（2026-09-22）**：按 D-A/D-B 的 A 路线**接线**而非降级标志，消除两处"声明与实现不一致"并补齐接口缺口。
> ①**接口扩展**：`Adapter` trait 新增 `delete_message` + `supports_message_deletion`，`AnyAdapter` 补 extend 列表与 6 平台分发。
> ②**Telegram**：`update_message` 接 `editMessageText`（纯文本、不带 `parse_mode`，与发送侧 R3 决策一致，同时删掉旧 builder 里写死的 `Markdown`）、新增 `delete_message` 接 `deleteMessage`；`supports_message_*` 均与实现一致。
> ③**Discord**：`edit_message`（PATCH）/`delete_message`（DELETE，204 仅看状态）/`get_current_user`（GET /users/@me）/`upload_file`（手工 multipart）四方法接线；`download_attachment` 的 `Ok("")` **静默假成功**改为真实 GET；`start()` 里无法 await 的同步探测删除（`bot_user_id` 全仓无读取方），改由 web 的 Discord 连通性探针调用真实 `get_current_user`（该探针此前正是为绕开 stub 而手工拼 URL）。
> ④**飞书**：新增 `delete_message`（DELETE `/im/v1/messages/{message_id}` + code 检查），`update_message` 沿用 WP-1.1 已接通的 PATCH。
> ⑤**不支持撤回的平台**：企微/微信/钉钉补 `supports_message_deletion=false` 并如实报 "does not support message deletion"，不虚报平台能力。
> ⑥**传输层**：`lib/client` 加 `http_delete` 包装（`HttpMethod` 对外不可构造，既有权衡）；`lib/channel` 加 `http_delete_ok`（Discord 204 无 body）/`http_delete_json`（飞书 200 + code）/`http_get_text`。
> **DoD 验证**：台账 6 行（`discord_api.mbt:85/101/114/136/150` + `telegram.mbt:291`）消失并转 `fixed`（95 → 89 命中）；编辑/撤回在飞书/Telegram/Discord 经本地 mock 真 HTTP 往返并有失败面断言；存量 stub 闸门（4 个 discord + 1 个 telegram）改写为"未接线端口必真报错"而非删除；`moon check -d` 0 错 0 警；`moon test --release` 全量口径 **3953/3953**（channel 473 / web 498 / client 127 单包复验全绿）；`known_gaps`/`repo_stats` 闸门绿。spec 归档 `specs/completed/2026-09-22_wp-1.6-message-edit-delete-wiring.md`。

- **历史剩余范围（开工前核对，非推测）**：
  1. **Telegram**：`lib/channel/telegram.mbt` 的 `update_message` 为 stub，而 `supports_message_updates` 已返回 `true` → 声明与实现不一致。
  2. **Discord**：`lib/channel/discord_api.mbt` 四方法为 stub + 一处 `TODO`；`DiscordAdapter::update_message` 必然报错，而 `supports_message_updates` 返回 `true` → 同一处不一致。
  3. **delete_message 不在接口里**：`Adapter` trait 只有 `send_text`/`update_message`/`supports_message_updates`/`validate_config` → 撤回能力须先扩 trait（含 `AnyAdapter` 分发与各平台实现）。
  4. **非缺口**：企微/微信/钉钉 `supports_message_updates=false` 并如实报"不支持编辑"，属平台能力事实。
  5. 飞书 `update_message` **已由 WP-1.1 接通**（走 PATCH），本 WP 无需重做。

- **触点**：`lib/channel/{telegram,discord,discord_api,adapter,feishu,feishu_api,wecom,weixin,dingtalk}.mbt`、`lib/client/platform_http.mbt`、`lib/channel/http_helper.mbt`、`lib/web/handlers_channels.mbt`。
- **DoD**：编辑/撤回在各已接通平台可用并有 wbtest；`supports_message_updates`/`supports_message_deletion` 与实现一致；台账对应 `not implemented yet` 行消失。

### WP-1.7 渠道配置单一真相源贯通 `[x]`（P1，WP-1.2~1.4 收尾时暴露的产品面缺口）

> **完成（2026-09-22）**：修掉四处"配置了不生效"的断点。①**默认路径字面 `~` 从未展开**——`server.mbt` 以 `"~/.mbopenclacky/channels.json"` 构造 manager，`x/fs` 不展开 tilde，`load_config` 恒按空配置返回、**零适配器注册**；新增 `expand_config_path`（`@utils.home_dir()` + `Path::join`）在读写前解析，home 不可解析即报错。②删除 Web 侧 `channels_store`/`ChannelEntry` 双真相源，全部渠道端点改为读写 `ChannelManager`，`has_config`/`enabled`/`running`/`has_token`/`token_updated_at` 全部来自真实状态，密钥键统一掩码为 `has_<key>`。③`channel-manager` 技能从 `channels.yml`（YAML、平台为键的扁平结构，运行时从不读取）重写为 `channels.json` 的真实 schema 与完整 settings 键名。④面板 Diagnostics 从 `/channel-manager doctor` 改调真实 REST 探针（此前该端点无任何调用方），探针取 manager 的真实配置。**顺带修掉一个运行期阻塞**：`WeixinAdapter::new` 硬要求 iLink 路径从不使用的 `app_id`/`app_secret`，使已配置的微信渠道无法构造、永不启动。DoD 验证：`moon check -d` 312 tasks 0 错 0 警；`moon test --release lib/channel lib/web lib/web/handler` 987/987；`selftest` 18/18；`eval --offline` 3/3；`fmt`/`known_gaps`/`repo_stats` 三闸门绿；隔离 HOME 起真实服务 + 浏览器实测面板状态与三类探针结果。spec 归档 `specs/completed/2026-09-22_channel-config-single-source-of-truth.md`。

- **目标**：让"配好的渠道"在运行时真正生效，并让 Web 面板 / 技能 / 运行时共用一份配置。
- **触点**：`lib/channel/manager.mbt`（读写与应用原语）、`lib/channel/registry.mbt`、`lib/web/handlers_channels.mbt`、`lib/web/handlers_bridge.mbt`、`lib/web/server.mbt`、`assets/skills/channel-manager/SKILL.md`、`web/features/channels/*`。
- **DoD**：面板状态与运行时一致且凭据不泄露；配置变更落盘并在重载后保持；技能写入的路径与 schema 可被 `load_config` 解析；探针使用真实凭据。
- **备注**：探针 happy path 仍需真实平台凭据，沿既有口径以 mock/缺失分支覆盖并如实标注。

### WP-2.1 GEP SkillReflector 做实 `[x]`（P1）

> **完成（2026-09-22）**：反思环节从占位变为真实 LLM 驱动流程。①`lib/skill` 删除占位
> `apply_improvements`，新增 `ReflectionProposal` + `build_reflection_prompt`（嵌入技能名/
> 定义/执行证据，要求严格 JSON 输出）+ `parse_reflection_response`（**容错解析**：剥离代码
> 围栏、容忍前后缀散文、按字符扫描做花括号配平且正确处理字符串内引号/转义、空 suggestions
> 元素丢弃）；证据超长按头尾截断（12000 字符上限）。②新增 `evolution_log.mbt`：手写
> `to_json`/`from_json`（**容错解码**，缺字段回落默认值，坏条目跳过），追加式日志写
> `~/.mbopenclacky/skills/evolution_log.json`（最新在前、上限 500、损坏文件读作空但**不覆盖**）；
> 因 `x/fs` 无 rename/append，写入为读-改-写且**如实标注非原子**。③新增 `proposal_apply.mbt`：
> 回写前**必先备份**为 `SKILL.md.bak.<ms>`，无既有文件时创建覆盖层并回报 `None`。
> ④两个 Web 端点从硬编码假成功改为真实实现：`POST /api/skills/:name/evolve`（`transcript`
> 必填，缺失返回可诊断 400；`apply` 显式 opt-in；`force` 可绕过分数门；无可用模型返回 400）
> 与 `GET /api/skills/evolution/history`（真实日志 + `?skill=`/`?limit=`）；`EvolutionEngine`
> 形状不变（`handle_post_execution` 不再调占位）。⑤失败一律如实上报并**落 `action:"error"`
> 日志**，无静默假成功。
>
> DoD 验证：`moon check -d` 312 tasks 0 错 0 警；`moon test --release lib/skill lib/agent`
> 640/640、`lib/web` 498/498；`selftest` 18/18；`eval --offline` 3/3；`fmt`/`known_gaps`/
> `repo_stats` 三闸门绿；台账 6 行转 `fixed`（104 → 98 命中）。
> **隔离 HOME 起真实服务 + 本地 mock LLM 端到端实测**（本环境无真实 key，故用 mock 验证
> 传输与解析链路）：提议路径返回真实 suggestions 与改写内容；`apply` 路径真实回写且
> 备份内容 == 原内容；`GET history` 读回真实条目并支持过滤/限量。
> 该实测**发现并修掉 3 个单测未覆盖的真实缺陷**（见下方"实施期发现"）。
>
> 完成记录归档：`specs/completed/2026-09-22_wp-2.1-gep-skill-reflector.md`。
>
> **实施期发现的既有基础设施缺陷（本 WP 已规避，未扩大改动）**：
> 1. `response_to_core`（`handlers_bridge.mbt`）只映射 201/204/400/404，**其他状态码一律回落为
>    200** → handler 返回 5xx 会以 200 到达客户端（静默假成功）。本 WP 因此用 400 而非 502。
>    其他 handler 均未使用 5xx，故当前无实际影响；若将来需要 5xx，须先修该映射。
> 2. `HttpResponse::bad_request`/`not_found` 直接插值消息、**不做 JSON 转义** → 消息含引号或
>    花括号时产出**非法 JSON** 响应体。本 WP 新增 `json_error`（经 `to_json()` 转义）规避并加
>    回归测试；既有调用点消息均无特殊字符，暂不受影响。
> 3. 查询串**不在** `HttpRequest.params`（该字段只承载路由参数），bridge 必须从 `event.req.url`
>    用 `find_query_param` 取出后注入（同 backup-download bridge 惯例）。本 WP 已按此接线并实测。

- **目标**：`lib/skill/reflector.mbt` 从占位（"real implementation would invoke LLM or code modification"）变为真实的执行后反思。
- **触点**：`lib/skill/reflector.mbt`、`lib/skill/evolution.mbt`（EvolutionEngine 调用点）、`lib/web/handlers_skills.mbt`（进化触发/日志查询 stub 端点）。
- **步骤**：
  1. 定义反思输入（最近任务的 transcript / 工具调用序列 / 成败）与输出（技能改进建议或 SKILL.md diff）。
  2. 用现有 `Agent`/`Client` 走一次 LLM 调用产出结构化建议；落进化日志。
  3. 接线 Web 端点（触发进化、查历史）。
- **DoD**：`reflector.mbt` 无 `placeholder` 命中；反思产出可持久化并可被 Web 查询；有 wbtest（用 mock LLM，参考 `test/e2e`）。
- **验证**：`moon test --release lib/skill lib/web`；台账 GEP 行消失。
- **备注**：反思提示词设计属复杂推理，用贵模型；接线与测试用便宜模型。
- **范围外（已在台账登记）**：面板无进化 UI（面板没有技能执行证据可提交，加按钮只会制造新假成功）；
  把 `PostExecution` 接入 agent 运行期需先建"技能执行台账"机制。

### WP-2.2 `cmd eval --live` 真模型评测接线 `[x]`（P1，战略项）

> **完成（2026-09-22）**：真模型能力评测从"规程已定、无任务集无运行器"变为**一条命令跑通**。
> ①`test/eval/tool_harness.mbt` 的任务 schema 追加 `prompt`/`acceptance`/`trials`（offline 任务不受影响），
> 评分/报告函数加可选 `cost_usd`；②新增 `test/eval/live_harness.mbt`：runner 以
> `async (String, String) -> LiveRunOutcome` 注入 → 批次驱动（逐 trial 独立沙箱 + seed + checks + 真实成本累加 +
> transcript 落盘）可**无网络确定性测试**，真 runner 工厂 `make_agent_live_runner` 走真 Agent + 事件捕获；
> ③新增 `test/capability/tasks/` 4 条任务（派生自 001/003/004/014 已验证剧本）；④`cmd/eval_live.mbt` 接线
> `--live`：模型解析（`MBOPENCLACKY_*` 显式覆盖 → `config.toml`/`CLACKY_*` → `DEEPSEEK_*` 兜底）、无模型时
> 可诊断 exit 1、报告落 `docs/eval/<date>.md`、transcript/JSON 落 `_build/capability/results/<stamp>/`；
> ⑤契约探针改为与 key 无关的确定性路径（避免探针继承环境后真发付费请求）。
>
> **安全要点**：`auto_approve` 下一切已注册工具自动执行（`should_auto_execute` 恒真），故真模型**工具面被重建的
> 受限 registry 收窄为** `file_reader`/`write`/`edit`/`grep`/`glob`（无 shell、无网络），与确定性层同构；
> 仅设 `allowed_tools` 不够——它只过滤发给模型的 definitions，执行解析走 registry（`get_resolved`）。
>
> DoD 验证：`moon check -d` 312 tasks 0 错 0 警；`moon test --release test/eval cmd` 63/63（含 mock LLM 端到端：
> 真 runner + 真工具 + 真沙箱）；`selftest` 20/20；`eval --offline` 3/3；`fmt`/`known_gaps`（95 命中）/`repo_stats` 三闸门绿。
> **真模型实测**（deepseek-flash @ api.deepseek.com，4 任务 × 3 次）：12/12 trial 通过、33/33 断言、
> 可重复性 1.0、0 基础设施失败、97,130 token、成本列 0（该模型无定价条目，如实标注 + 给 token 代理）；
> 报告 `docs/eval/2026-09-22.md`。**如实说明**：任务集小且偏基础，全通过只证明链路与模型可用，不构成模型能力结论。
>
> 完成记录归档：`specs/completed/2026-09-22_wp-2.2-live-model-eval.md`。
>
> **实施期发现（本 WP 未扩大改动，已登记）**：
> 1. `MBOPENCLACKY_*` 在存在 `config.toml` 时**会被忽略**（`apply_env_overlay` 仅在 `models` 为空时才用 env），
>    与 README 的"设 MBOPENCLACKY_API_KEY 即可"暗示不符。基准必须可指名模型，故 live 路径把 `MBOPENCLACKY_*`
>    提升为**显式覆盖**并如实标注来源；全局语义未改（属独立决策）。
> 2. 流式调用每次收尾的 `[stream-summary]`（`lib/agent/llm_caller.mbt:685`）注释与所依据 spec 都写 stderr、实际走
>    stdout，污染一切机器可读 stdout（`-m --json`、`eval --live`）。本 WP 改为**如实声明契约**（JSON 是 stdout
>    最后一行 + 另存 score.json），修复需专门的诊断路由决策（core 无 stderr 原语），已入台账。
> 3. 工具按**进程 CWD** 解析相对路径（e2e runner 亦如此），故真 runner 逐 trial chdir；这会与并发测试相互影响，
>    故测试用绝对路径 + `chdir=false`，CLI 侧路径全部绝对化。

- **目标**：接通真模型能力评测，拿到与上游对标的硬证据。**规程与 schema 已定**（`test/capability/README.md`），只差任务集与运行器。
- **触点**：新建 `test/capability/tasks/*.json`（schema = `test/eval/tasks/` + `prompt`/`acceptance`/`trials`）；`cmd/eval.mbt`（`--live` 分支，开工时为诚实 exit 1）；复用 `test/eval/tool_harness.mbt` 的 `seed`/`{sandbox}`/`checks` 原语。
- **步骤**：
  1. 从已验证的 e2e 剧本派生种子任务：001 read_edit、003 multi_turn、004 parallel、014 tool_failure_recovery。
  2. `cmd eval --live` 读 `MBOPENCLACKY_API_KEY/BASE_URL/MODEL`，每任务跑 `trials`（≥5）次真实 ReAct 循环，跑 `checks` + 记录 transcript/退出码/token。
  3. 输出评分向量（completion/verification/repeatability/cost）到 `_build/capability/results/`，报告写 `docs/eval/<date>.md`。
  4. 更新 `cmd/selftest.mbt` 与 `cmd/main.mbt` 的 `--live` 帮助文本（去掉"not implemented"）。
- **DoD**：一条命令用真实 key 产出可重跑报告；无 key 时仍诚实报错（不静默）；`--live` 不再命中 `not implemented`；**不进 CI**（成本/随机性）。
- **验证**：手动 `cmd eval --live`（廉价模型）跑通一次，如实记录波动与成本；台账 eval 三行（`cmd/eval.mbt:75`、`cmd/main.mbt:198`、`cmd/selftest.mbt:520`）改状态。
- **纪律**：禁止把真实 key 写入任务/结果文件；任务集只增不减。

### WP-3.1 旧会话 schema 只读迁移投影 `[x]`（P2，2026-09-22 完成）

- **触点**：`lib/agent/session*.mbt`（只读导入路径）、`cmd inspect`。
- **步骤**：旧 `tool_calls` schema → 新事件投影（只读，不就地改写）；加兼容测试（用参考机 `~/.mbopenclacky/sessions/*.json` 的脱敏样本）。
- **DoD**：`--list` 能列出此前静默跳过的旧会话；`cmd inspect` 对旧格式给出时间线而非仅报因；README"读取兼容性未经验证"可升级为"已验证只读兼容"。
- **完成记录（2026-09-22）**：
  - 实现期发现**两类真实成因**（原执行计划只写了"旧 `tool_calls` schema 不匹配"这一条笼统描述）：
    1. **早期构建把 `Json` 的 Debug-repr 写进 `.json`**（`Object({session_id: String(...)})`），根本不是 JSON → 7 个文件；
    2. **旧 Option 序列化器把 `Some(x)` 写成 `[x]`**，`tool_calls` 因而是 `[[...]]` → 解码在 `ToolCall: expected object` 处失败 → 24 个文件；同批文件里 `tool_call_id`/`name`/`reasoning_content` 被写成 `[scalar]`（原先是**静默丢字段**，会让恢复后的 tool_result 失去配对）。
  - 新增 `lib/agent/session_legacy_repr.mbt`：repr → `Json` 的递归下降投影（含 `String(...)` 原文体的括号终结规则；解析不到底返回 `None`，绝不猜半截内容）。裸 JSON 失败时才回退到该投影。
  - `lib/message`：新增 `opt_message_string`/`opt_message_bool`/`opt_message_tool_calls` 容忍旧 Option 包装；`ToolCall` 接受旧派生键 `type_`。`SessionData`：缺 `stats`/`working_dir`/`name` 与数字型 `created_at` 不再让整个会话消失。
  - **实测**：参考机 `~/.mbopenclacky/sessions/` 从 **1/32 可列出 → 32/32**（无"未列出"提示）；`cmd inspect` 对 Debug-repr 报 `format: legacy debug-repr`、对旧 JSON 报 `legacy json`，两者都渲染出时间线。
  - **只读保证**：不改写任何既有文件（投影只在内存中构造 `SessionData`）。
  - **如实说明**：参考机上**没有上游 Ruby openclacky 的原始会话样本**，因此"对上游文件的端到端比对"仍属未验证；README 改为精确表述（已验证：旧版转储 + 字段变体；未验证：上游原始样本）。
  - spec 归档：`specs/completed/2026-09-22_wp-3.1-legacy-session-readonly-projection.md`。

### WP-3.2 Web 会话 JSONL 事件流（复议 D3）`[ ]`（P2）

- **背景**：决策 D3 曾划为范围外。若追求三端可观测一致，需在 `lib/web/broadcast/hub.mbt` 加持久化旁路，复用 CLI/TUI 的 `SessionLogProducer`（值类型，可脱进程测试）。
- **DoD**：Web 会话也产 append-only JSONL；压缩只追加 `Summary`；不改原始事件字节。

### WP-3.3 MCP HTTP 传输 `[x]`（P2，2026-09-22 完成）

- **触点**：`lib/mcp/http_transport.mbt`（三处 `Err("... not implemented")`）。
- **步骤**：用 `@async/http` 实现 Streamable HTTP / SSE 传输（Stdio 已完整，可复用 JSON-RPC 层）。
- **DoD**：HTTP 传输可连一个真实/ mock MCP server；README MCP 表述升级。
- **完成记录（2026-09-22）**：
  - 三处 `not implemented` 全部消失，换成真实实现：`start` 校验 url（http/https、有 host）并置为可用——Streamable HTTP 没有需要建立的常驻连接，可达性由第一个请求如实报错，**不假装已连接**；`send_request` 用 `@async/http` 每请求一条连接 POST，并把 `Mcp-Session-Id` 捕获后回带；应答按 `Content-Type` 分流：`application/json` 直接取与 id 匹配的帧（含 batch 数组），`text/event-stream` 逐帧扫描 `data:` 行、**读到自己的 id 即停**（服务端保持流打开也不会卡住），非本请求的 JSON-RPC 帧（通知/服务端发起请求）转交已注册的 message handler。
  - `send_message`（通知）按 Streamable HTTP 语义接受 202/空体；HTTP ≥400 与服务端 error 对象都如实报错，不静默成功。
  - 测试（13 条，**全部走真实 socket**：同进程内 `@http.Server` 绑定 127.0.0.1 临时端口，无外网）：JSON 往返、SSE 往返（通知 + 陈旧 id 帧 + 本 id 帧，断言只返回本 id 且前两帧被转发）、路径/`Accept`/会话回带、空通知体、**服务端 503 与拒连都报错**、SSE 未收到回复即关流报错、另一 id 的 JSON 回复被拒、batch 提取与 url 切分的单测；另有**端到端**一条：`McpClient` 经 HTTP 完成 `initialize` 握手 + `notifications/initialized` + `tools/list`（会话 id 在第三个请求上回带）。
  - 存量"断言 stub 报错"的闸门测试改写为"不可用 url 必真报错"，保住 stubfix-02 的禁止假成功契约。
  - 台账 3 行（`http_transport.mbt:58/81/95`）消失，curated 行转 `fixed`（89 → 86）。
  - **如实说明**：Windows 本机仍无法跑该包全量（`mcp.whitebox_test.exe` 在 stdio 的 python3 集成测试处挂死，WP-3.5 范围），故本 WP 用 `--filter` 分片验证：新 HTTP 测试 13/13、其余非挂死用例（`build_jsonrpc` 3、`dispatch_line` 4、`session_id` 1、`McpClient` 6、`registry` 13、`virtual_skill` 1）全绿。
  - spec 归档：`specs/completed/2026-09-22_wp-3.3-mcp-http-transport.md`。

### WP-3.4 性能基准真实执行驱动 `[ ]`（P2，先出 spec）

> **现状核对（2026-09-22）**：`test/benchmark/benchmark_runner.mbt:37-44` 的 `run_single_iteration` 明写"为了简化，我们模拟执行"，
> 且 `elapsed_ms` 紧随 `BenchmarkTimer::new()` 读取——**实测** `cmd benchmark --iterations 3 --warmup 1`
> 输出 Total/Min/Max/Avg/P50/P95/P99 **全部 0ms**，回归报告的场景名显示 `unknown`。
> `test/benchmark/README.md:52` 已如实说明"输出反映的是计时管线本身，不是被测能力的延迟"。
> 因此本 WP 的剩余工作是：先补 `specs/draft/` 规格，再把 `tool`/`parameters` 接到真实执行路径。

- **触点**：`test/benchmark/`（`BenchmarkRunner::run_scenario` 当前为模拟执行，`tool`/`parameters` 不真执行）。
- **前置**：先在 `specs/draft/` 出规格（真实性能闸门的口径、噪声处理）。
- **DoD**：`cmd benchmark` 真执行工具路径并计时（数值不再恒为 0ms，回归报告场景名不再是 `unknown`）；结果落 `_build/benchmark/results/`；仍不进 CI。

### WP-3.5 Windows `lib/mcp` 测试挂死排查 `[ ]`（P3）

- **现象**：`moon test --release` 在 Windows 本机挂死于 `lib/mcp/mcp.whitebox_test.exe`（stdio 集成测试 spawn python3 前停住，疑似 async 管道/事件循环死锁）；Linux CI 全绿。
- **步骤**：最小复现 → 定位 async spawn/pipe 在 Windows 的死锁点 → 修复或给该测试加 Windows 跳过 + 台账登记。
- **DoD**：Windows 本机可跑全量测试（或该包有明确的平台跳过与根因记录）。

### WP-3.6 TUI 绑定 wire 词表 `[ ]`（P3，ADR-0001 后续）

- **背景**：TUI 直接消费引擎 `HookEvent`（富状态机需要 wire 丢弃的原始信息）；Web/CLI 已走 `lib/protocol`。见 `specs/decisions/2026-09-21_01_typed-engine-protocol-leaf-boundary.md`。
- **DoD**：若决定统一，TUI 改绑 wire 词表并保留必要适配层；否则维持现状（HookEvent 穷尽匹配已保证新增事件即编译失败）。

---

## 6. 风险与触发条件

| 风险 | 触发信号 | 立即动作 |
|---|---|---|
| 渠道 multipart/长轮询受 `@client` 能力限制 | 飞书 `upload_image` 无法发 multipart | 先接 JSON 类接口，multipart 单独留台账；不阻塞 WP-1.1 主体 |
| 微信 AES-128-ECB 无现成原语 | `moonbitlang/x/crypto` 无 ECB | 走 FFI（贵模型），或该渠道降级声明，不拖累其余渠道 |
| 真模型评测超预算/不稳定 | 单任务成本或时延不可控 | 降到 3 次重复、换更小任务，报告注明限制（规程已允许） |
| 接线引入回归 | `moon test` 或 `selftest` 变红 | 回到最近绿提交，先补复现用例再修（效率协议第 4 条：先读完整错误） |
| 范围被"顺手加功能"侵蚀 | PR 出现新渠道/Provider/前端重写 | 拒收，转 `known-gaps.md` 或下一期 |

---

## 7. 完成定义（整体）

本计划视为达成，当：
1. WP-0.1 完成（无法律矛盾）；
2. 决策门 D-A/D-B 均已放行并执行对应分支（接线或降级，**无悬空**）；
3. 已接线的 WP 在 `known-gaps.md` 对应行状态为 `fixed`，且全局基线命令全绿；
4. `docs/improvement-roadmap.md` 对应条目状态同步更新，`docs/CHANGELOG.md` 有记录。

**当前状态（2026-09-22 核对）：整体尚未达成。**
- 条件 1 ✅ 满足（WP-0.1 已完成，`web/PATCHES.md` P0-001 `resolved`）。
- 条件 2 ✅ 满足（D-A/D-B 均选 A 并执行接线，无悬空）。
- 条件 3 ⚠️ **部分满足**：已完成的 12 个 WP 对应台账行均为 `fixed`、全局基线命令全绿；但 **WP-3.2、WP-3.4~3.6 未开始**，其台账行仍为 `open`（这是有意的如实登记，不是遗漏）。
- 条件 4 ⚠️ **部分满足**：已完成 WP 的路线图条目与 `CHANGELOG` 均已同步；未开始项的路线图状态已按本次核对标注为未完成。
- 结论：**P0 与 P1 主线全部闭环；余下 7 个 P2/P3 工作包（1 个渠道补齐 + 6 个卫生项）按资源择机**，不影响对外承诺的可信度（均为已披露的诚实 stub/骨架）。

> 维护约定：本文是**执行视图**，随 WP 进展更新状态标记；结论与优先级以 [improvement-roadmap.md](improvement-roadmap.md) 为准，逐行缺口以 [known-gaps.md](known-gaps.md) 为准。三者不一致时，以机器校验的台账为最终事实。
