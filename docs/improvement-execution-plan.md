# MBOpenClacky 优化提升计划

> 生成日期：2026-09-21 · **全部 17 个工作包闭环：2026-09-23**
> 对标上游 [clacky-ai/openclacky](https://github.com/clacky-ai/openclacky)（Ruby）。Web 前端 fork 基线 v1.5.0，TUI 布局对标 ui2 v1.5.4。
> 本文是优化提升工作的**唯一活文档**：流程约定（§0–§1）、实施期发现的既有约束（§1.2）、下一步方向（§2）。历史 WP 状态与交付细节见 `specs/completed/` 与 [CHANGELOG.md](CHANGELOG.md)，逐行缺口以机器校验的 [known-gaps.md](known-gaps.md) 为准。

---

## 0. 如何使用本文（新增 WP 时）

1. 挑一个工作包（WP-x.y）。
2. 按 Harness 方法论在 `specs/draft/` 建增量 spec（用 `specs/_templates/incremental-spec-template.md`），过对抗性评审后进 `specs/active/`。
3. 实现时在 `moon check` 紧循环里小步推进；执行型工作（接线、改 stub、写测试）用**便宜模型**，仅架构/FFI 内存布局/对抗评审用贵模型（见 `AGENTS.md` 效率协议第 1 条）。
4. 每闭环一个 WP：重跑 `scripts/known_gaps.sh generate` → 对应命中行消失 → 把 curated 台账行状态改 `fixed`；归档 spec 到 `specs/completed/`；在 `docs/CHANGELOG.md` 记一笔。
5. 提交遵循 `feat:`/`fix:`/`docs:` 小写类型前缀，一个 WP 一个逻辑提交。

**状态标记**：`[x]` 完成 · `[—]` 作废 · `[ ]` 未开始。

---

## 1. 全局约定（每个 WP 都适用）

- **验证基线命令**（改动前后各跑一次，见 `docs/testing.md` 一键全跑）：
  ```bash
  moon check -d                                                  # 0 error / 0 warning（CI 硬闸门）
  moon build --target native --release cmd
  BIN=./_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe
  "$BIN" selftest --repo .                                       # 层 5 CLI 契约：20/20
  "$BIN" eval --offline --repo .                                 # 层 6 确定性评测：3 任务 × 2 重复，评分须全 1
  moon test --release $(find lib cmd test -name moon.pkg | sed 's|/moon.pkg$||')
  scripts/known_gaps.sh check && scripts/repo_stats.sh check      # 台账与数字闸门
  ```
  自 2026-09-23 起 Windows 本机这条 `moon test` **不再需要排除 `lib/mcp`**。
- **数字口径**：README/AGENTS/project-status 的规模数字由 `scripts/repo_stats.sh` 生成，**禁止手改** `<!-- BEGIN: repo-stats -->` 块；改了代码规模就跑 `generate`。
- **测试就近**：新测试放 `*_wbtest.mbt`（层 1）或 `test/diff`/`test/e2e`（层 2/3）；不新增顶层目录；一次性产物只落 `_build/`。
- **诚实纪律**：接不通的路径必须返回可诊断的 `Err(...)`，不得静默假成功（stubfix 批次已清零假成功型 stub，勿回退）。

### 1.1 用例数与格式化口径

- `repo_stats.sh generate` **不带 `--test-count` 时会沿用文档里的旧用例数**，数字不随新增测试自动更新。新增/删除用例后必须显式传值：`generate --test-count <moon test 汇总行的 passed 数>`。
- 发布的用例数口径 = **CI `Run tests (module packages)` 那一步**（`lib cmd test` 且 `grep -v '^lib/mcp$'`），CI 另有一步单独跑 `lib/mcp`。当前实测（2026-09-23）：该口径 3,973/3,973，`lib/mcp` 单独 96/96，合起来本模块全包 4,069/4,069。
- **`moon fmt` 不要裸跑全仓**：它会重排无关文件，污染 diff。只对本次改动的文件定点格式化。
- **裸 `moon test --release` 不是验收口径**：`moon.work` 含 `vendor/mbtpdf`，裸跑会连带运行该依赖自带的测试（6 例失败，非本仓回归面）。

### 1.2 实施期发现的既有契约约束（改动这些面前先读）

来自 WP-1.x~WP-3.x 的端到端实测，均未在本期扩大改动，但会绊住后来者：

1. **Web 状态码回落**：`response_to_core`（`lib/web/handlers_bridge.mbt`）只映射 201/204/400/404，**其他状态码一律回落为 200** → handler 返回 5xx 会以 200 到达客户端。需要 5xx 时先修该映射。
2. **错误响应体转义**：`HttpResponse::bad_request`/`not_found` 直接插值消息、不做 JSON 转义 → 消息含引号或花括号时产出非法 JSON。用 `json_error`（经 `to_json()` 转义）。
3. **查询串不在 `HttpRequest.params`**（该字段只承载路由参数）→ bridge 必须从 `event.req.url` 用 `find_query_param` 取出后注入。
4. **`MBOPENCLACKY_*` 环境变量在存在 `config.toml` 时会被忽略**（`apply_env_overlay` 仅在 `models` 为空时才用 env）。
5. **stdout 不是干净的机器输出**：每次流式调用收尾打印一行 `[stream-summary]`（`lib/agent/llm_caller.mbt`）。
6. **工具按进程 CWD 解析相对路径**：需要隔离的用例要么逐次 chdir，要么用绝对路径。
7. **MoonBit AOT 约束**：运行期热加载的扩展无法实现 trait，扩展路由用 shell 命令承担（见 `AGENTS.md`）。

---

## 2. 下一步方向

全部 17 个 WP（P0/P1/P2/P3）已闭环（16 完成 / 1 作废）。稀缺项已从"把已宣传的能力做实"换轨为"把已做实的能力向外延伸"：

1. **渠道接收侧接线**：Telegram `getUpdates` 长轮询 → 企微 WebSocket → 钉钉 Stream Mode，复用 WP-1.1~1.4 的 mock-TCP 验证模式与 `ChannelManager` 单一真相源。
2. **上游 Ruby 侧真模型对标**：两侧同模型同参数、每任务 ≥5 次；需 WSL 侧 `openclacky agent -m`。
3. **评测任务集扩充**（4 → 20~30 条）与**性能基准是否升级为门禁**的规格决策（先 `specs/draft/`）。
4. **运行时原语候选**（按依赖顺序）：类型化 fail-closed 审批 → 子代理进程级隔离+预算 → 沙箱与写范围工具化 → `goal`/`plan`/`steer`/`job` 原语 → 前端契约测试与产品端点探针。

剩余缺口逐条见 [known-gaps.md](known-gaps.md)（当前 86 条 `open` 命中，多为 wasm 回退、平台能力事实与已披露的接收侧长轮询）。

### 范围冻结

本期明确不做，范围外改动一律登记台账：

- 不新增 IM 渠道 / Provider，不重写前端；
- 不实现 MCP `resources` / `prompts`（传输层 Stdio 与 HTTP 均可用，能力面只覆盖 tools）；
- 不动计费、白标、遥测的服务端集成；
- 不追求 wasm 全量通过——**native 为唯一验收目标**（wasm 仅 `moon check`，非阻塞）。

---

## 3. 历史 WP 索引（全部闭环，2026-09-23）

| WP | 标题 | 优先级 | 状态 | 落地位置 |
|---|---|---|---|---|
| WP-0.1 | 品牌资产法律核实与文档统一 | P0 | `[x]` 2026-09-21 | `web/PATCHES.md` P0-001 resolved |
| WP-0.2 | 宣传口径对齐（降级声明分支） | P0 | `[—]` 作废 | 决策门 D-A/D-B 均选 A，降级分支不适用 |
| WP-1.1 | 飞书 send/receive 接线 | P1 | `[x]` 2026-09-22 | `specs/completed/2026-09-22_wp-1.1-feishu-wiring.md` |
| WP-1.2 | 钉钉 send 接线 | P1 | `[x]` 2026-09-22 | `specs/completed/2026-09-22_wp-1.2-1.4-channel-send-wiring.md` |
| WP-1.3 | 企业微信 send 接线 | P1 | `[x]` 2026-09-22 | 同上 |
| WP-1.4 | 微信 send + AES-128-ECB | P1 | `[x]` 2026-09-22 | 同上（取消 FFI 评估，`x/crypto` ECB） |
| WP-1.5 | 媒体生成接线（图/语音/视频） | P1 | `[x]` 2026-09-21 | 四端点真调用 + `lib/client` 二进制传输 |
| WP-1.6 | 全平台 update/delete_message | P2 | `[x]` 2026-09-22 | `specs/completed/2026-09-22_wp-1.6-message-edit-delete-wiring.md` |
| WP-1.7 | 渠道配置单一真相源贯通 | P1 | `[x]` 2026-09-22 | `specs/completed/2026-09-22_channel-config-single-source-of-truth.md` |
| WP-2.1 | GEP SkillReflector 做实 | P1 | `[x]` 2026-09-22 | `specs/completed/2026-09-22_wp-2.1-gep-skill-reflector.md` |
| WP-2.2 | `cmd eval --live` 真模型评测接线 | P1 | `[x]` 2026-09-22 | `specs/completed/2026-09-22_wp-2.2-live-model-eval.md` |
| WP-3.1 | 旧会话 schema 只读迁移投影 | P2 | `[x]` 2026-09-22 | `specs/completed/2026-09-22_wp-3.1-legacy-session-readonly-projection.md` |
| WP-3.2 | Web 会话 JSONL 事件流 | P2 | `[x]` 2026-09-22 | `specs/completed/2026-09-22_wp-3.2-web-session-jsonl-event-stream.md` |
| WP-3.3 | MCP HTTP 传输 | P2 | `[x]` 2026-09-22 | `specs/completed/2026-09-22_wp-3.3-mcp-http-transport.md` |
| WP-3.4 | 性能基准真实执行驱动 | P2 | `[x]` 2026-09-23 | commit `3e4f567` |
| WP-3.5 | Windows `lib/mcp` 测试挂死 | P3 | `[x]` 2026-09-23 | 根因：Windows 命名管道阻塞 async fiber，运行时跳过 |
| WP-3.6 | TUI 绑定 wire 词表 | P3 | `[x]` 2026-09-23 | 结论：维持现状（ADR-0001 §7 取舍成立） |

> 维护约定：逐行缺口以机器校验的 [known-gaps.md](known-gaps.md) 为准，交付细节以 [CHANGELOG.md](CHANGELOG.md) 与 `specs/completed/` 为准。不一致时以台账为最终事实。
