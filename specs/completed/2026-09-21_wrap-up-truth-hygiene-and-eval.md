# 2026-09 收尾：真话卫生、会话日志接线补全与 `cmd eval`

> 状态：**completed**（2026-09-21）
> 上游计划：`docs/wrap-up-plan.md`（v1，draft）｜基线：`main@4eb6aad`
> 执行方式：按计划阶段顺序 T0–T13 串行落地；本文是该期的权威记录，随实现一起提交

## 1. 背景与目标

`docs/wrap-up-plan.md` 对本仓库"是否达到附件宣称标准"做了对抗性审查，确认三条不变量：
冻结功能面、每条对外承诺可被第三方证伪、文档是机器的投影。本期把这三条在现有代码上**落地**，
而不是新增功能面。

范围外（明确不做，与计划 §8 一致）：IM 渠道 / Provider / 前端重写 / MCP resources·prompts、
计费·白标·遥测服务端、wasm 全量、TUI 绑定 wire 词表、旧会话 schema 迁移器、Web 会话 JSONL 事件流。

## 2. 交付物（按任务）

| 任务 | 交付物 | 判据 |
|---|---|---|
| T1 | `scripts/repo_stats.sh`（print/generate/check）+ README/CLAUDE.md/project-status 的机器生成块 | `bash scripts/repo_stats.sh check` 绿；CI `Repo stats gate` |
| T2 | README 会话兼容性表述与台账一致；`docs/MBOpenClacky-改造开发计划.md` 悬空引用修复 | `grep` 无"完全兼容 openclacky 会话格式"（计划文档内的缺陷引述除外） |
| T3 | 版本对齐 0.2.0（`moon.mod` / `cmd/main.mbt` / `lib/tui/tui_controller.mbt` / `lib/web/handlers_version.mbt`） | `--version` = `MBOpenClacky v0.2.0`；`repo_stats.sh` 四处一致性行非 DRIFT |
| T4 | `docs/known-gaps.md` 重生成 + 3 条 `--live` 诚实缺口登记 | `known_gaps.sh check` → 162/162 |
| T5 | TUI 路径 `flush_session_log`（与 `--message` 路径对称） | `cmd` 测试：`attach_session_log + flush_session_log write the run's log` |
| T6 | `HookEvent::CompressionPerformed(Int)` + 压缩边界切段 + `summary` 记录 | `cmd/session_log_producer_wbtest.mbt`（2 例）+ `lib/agent` 发射（2 例） |
| T7 | `test/eval/tool_harness.mbt`（工具白名单 + 沙箱 + 断言原语 + 评分 JSON） | `moon test test/eval --release` 9/9 |
| T8 | `cmd eval --offline` + `test/eval/tasks/*.json` + 报告 + CI 步骤 | `eval --offline --repo .` exit 0、stdout 单 JSON、CI `Deterministic capability eval` |
| T9/T10 | `cmd eval --live` 的 D1 回退实现（诚实 exit 1）+ 契约探针 | `cmd selftest` 18/18；台账登记 `open` |
| T11 | `docs/acceptance.md` 重写 + README 快速开始/闸门表更新 + CHANGELOG | §6 一键序列全绿 |
| T12 | 全量闸门 + 逐任务提交 + `v0.2.0` tag | 见 §5 |
| T13 | spec 归档；`specs/active`、`specs/draft` 为空 | 本节所示 |

## 3. 第一性原理修正（与计划的偏差，逐条有据）

1. **T6 的 emit 点**：计划写"`compress_with_safety` 成功分支 emit"，但生产 ReAct 循环走的是
   `lib/agent/react.mbt:403` 的 `compress_with_level_fallback`，`compress_with_safety` 全仓无生产调用者。
   若只按计划接线，真实压缩路径永远不会发事件 → **两处都 emit**（react 为生产路径，compress_with_safety 为
   Agent 级包装），并由 `lib/agent` 测试固定。
2. **T6 的 summary 落盘时机**：hook 回调是同步的，而追加是 async，且事件在运行结束才统一 flush。
   因此不在回调里落盘，而是**按压缩边界切段缓冲**，flush 时逐段追加并为其追加 `summary`。
   语义按计划风险表预案取粗粒度投影（覆盖本段全部事件），字节保全不变量不受影响。
3. **生产者从进程全局改为值类型**：原实现把缓冲放在模块级数组里，同一测试进程内并发跑的用例互相污染
   （实测 4 条记录变成 9 条）。改为 `SessionLogProducer` 值类型，CLI 保留一个全局实例，
   测试各自持有实例 → 测试确定性恢复。
4. **测试用例数的口径**：`moon test` 的计数与静态 `test` 声明数不等（`lib/agent` 403 vs 494、
   `lib/web` 510 vs 469），无法静态推导；而 Windows 上 `lib/mcp` 的 stdio 测试死锁，
   全量跑不完。因此口径定为**排除 `lib/mcp` 的 `moon test --release` 汇总**，
   在 `repo_stats.sh` 头注释、CI 步骤与台账中同步写明，CI 用 `--test-count-from` 校验同一个数。
5. **T1 的实现形态**：计划写"输出与三份文档数字逐字节一致（diff 校验）"。
   实现取更彻底的形式——三份文档内嵌**同一段**由脚本生成的标记块，`check` 重新渲染并 diff，
   既保证三处一致，也保证与机器统计一致（等价于单一事实来源，且不依赖脆弱的逐行 grep）。
6. **T3 追加了一个漂移点**：计划只提 `moon.mod` 与 `cmd/main.mbt`，
   实际 `lib/tui` 的 `app_version` 是 `0.1.0`、`lib/web` 的 `VERSION` 也是 `0.1.0`（比 `moon.mod` 还旧），
   一并对齐并把"四处一致"做成 `repo_stats.sh` 的机器判据。

## 4. 决策记录（D1–D4）

| 决策 | 结论 | 依据 |
|---|---|---|
| D1 `eval --live` 预算 | **走回退方案**：不执行真模型，`--live` 诚实 exit 1 + 说明；台账登记 `open` | 无 API key 预算，且不制造无法复现的数字 |
| D2 版本号 | **bump 到 0.2.0**，新建 `v0.2.0` tag，`v0.2.0-hackathon` 保留为历史标记 | 消除 `--version` 与 tag 的错位 |
| D3 Web 会话 JSONL | **不接**，README 精确化 + 台账新行（范围外） | 接入需广播层新增持久化旁路，超出收尾边界 |
| D4 旧会话迁移器 | **不做**，README 改说法，台账注明可见性已修、schema 迁移待办 | 无上游会话样本可做 fixture 兼容测试 |

## 5. 验收证据

一键序列见 `docs/acceptance.md` §0。本期新增/变更的机器判据：

- `bash scripts/repo_stats.sh check`（含 `--test-count-from <log>`）
- `<binary> eval --offline --repo .`（exit 0 + 评分向量全绿）
- `<binary> selftest --repo .` → 18/18（新增 `eval_offline`、`eval_live_unavailable`）
- `bash scripts/known_gaps.sh check` → 162/162
- `moon check` 0 错误 0 警告；`bash scripts/warn_count.sh 0 strict` 绿
- `moon test --release`（口径见 §3.4）全绿

**CI 绿：曾失败，已定位并修复，并已复验为绿（2026-09-21）。** 通过公开 API（无需鉴权）取得步骤级证据：`CI` 与
`Docker` 工作流自 `c4b3fa4b`（2026-08-28，最后一次 success）起每次都失败，失败步骤是 `Run tests`。

根因（第一性原理定位，非猜测）：`moon.work` 声明工作区 `members = [".", "vendor/mbtpdf"]`，
因此**裸 `moon test --release` 不只跑本模块，还会编译并运行 vendored 依赖 mbtpdf 自带的内部测试**；
那个测试驱动在当前工具链上 ICE：

```
Error: Sys_error("/root/.moon/lib/core/_build/native/release/bundle/prelude/prelude.mi: No such file or directory")
  ... bobzhang/mbtpdf/font/pdffont -test-mode ...
```

定位手段：CI 步骤级结论显示 type check / 警告预算 / 公共 API / 真话台账 / 构建 / 契约探针全部 success，
只有 `Run tests` 红；同一次运行中本收尾新增的 `Deterministic capability eval` 与 `Repo stats gate`
（后者执行的正是"限定包列表"的测试）**双双 success**，直接指向"范围包含 vendor"这一差异。
WSL 复现印证：`moon check` 绿，裸 `moon test --release` ICE，限定 `lib cmd test` 跑完 **3818/3818**。

修复：CI 的测试步骤只跑本模块自身的包（`lib cmd test`；`lib/mcp` 单列一步供 Linux 跑）。

**复验证据**：commit `020ec26` 的 `CI` 工作流（run `35565534593`）全部步骤 success，含 `Run tests (module packages)`、`Run lib/mcp tests`、`Deterministic capability eval`、`Repo stats gate` —— 这是自 `c4b3fa4b`（2026-08-28）以来第一次绿，也证明收尾新增的两条闸门在真实 CI 上可执行且通过。
依赖的**库**代码仍参与构建并由 `lib/parser` 的测试覆盖，只是不再把其自带单测当成本仓库的回归面
（`vendor/` 本就在公共 API 闸门与台账扫描范围之外）。`Docker` 工作流失败于 `Build Docker image`，同样是既有问题且**已定位修复**：`Dockerfile` 的产物路径不含模块命名空间，且**两处**都错（构建阶段的 `test -f` 断言、运行阶段的 `COPY --from=builder`）。真正的报错来自 COPY，经 job 页面读得：`failed to compute cache key ... "…/build/cmd/cmd.exe": not found`。修复方式是在构建阶段把产物规范化为 `/build/out/mbopenclacky`，运行阶段只引用该稳定路径。（首版修复只改了断言，报文随即暴露出 COPY 这一处——两处同源，一次改净。）本机无 Docker，本地无法复现镜像构建；**复验为绿**：commit `7770730` 的 Docker 工作流（run `35566838562`）所有步骤 success，含 `Build Docker image` 与 `Verify image`。

本地等价序列（Windows 口径，排除挂起的 lib/mcp）已逐条跑绿：见 §5 其余条目。

## 6. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-21 | 首版：T0–T13 全部落地；§3 记录 6 处与计划的第一性原理偏差 |