# 验收文档（docs/acceptance.md）

> 本期范围：`docs/MBOpenClacky-改造开发计划.md` 的 P0 + P1（承诺验收范围）。
> 基线：`main@5b74655`（2026-09-20）。全部证据可在本机复现；未完成项见
> [known-gaps.md](known-gaps.md)。

## 0. 一键复现（从全新 clone）

```bash
moon version                      # 工具链（本期验证于 0.1.20260920）
moon update                       # 拉取依赖（moon install 无参已弃用）
moon check                        # 期望：0 errors / 0 warnings
moon build --target native --release cmd
BIN=_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd
./$BIN selftest                   # 期望：exit 0，14/14 探针通过
./$BIN --version                  # 期望：MBOpenClacky v0.1.3（与 moon.mod 一致）
./$BIN --list                     # 期望：会话列表 + 未列出文件数（不隐藏）
./$BIN inspect <某个.jsonl>        # 期望：离线时间线
scripts/known_gaps.sh check        # 期望：台账与代码一致
moon test --release               # 全量测试（见 §3 的平台说明）
```

## 1. 对照官方验收 6 条

| 官方标准 | 本仓库证据 | 状态 |
|---|---|---|
| MoonBit 为主 | 本期新增实现全部是 `.mbt`（`lib/protocol/`、`lib/agent/session_log.mbt`、`cmd/selftest.mbt`、`cmd/inspect.mbt` 等）；辅助脚本为 bash，文档为 markdown，未引入其他语言的实现代码 | ✅ |
| 仓库公开、连续提交 | 本地提交历史连续（本机 `git log --oneline`）；GitHub Issue/PR 流程与推送不在本次执行范围内，未在此文档中断言 | ⚠️ 部分 |
| 能够运行 | `moon build --target native --release cmd` 绿；`cmd selftest` 14/14（详见 §2）；`cmd inspect` 可离线回放真实/构造日志（§2.3）；`cmd eval --offline` **本期未实现**（P2 stretch），见 known-gaps | ⚠️ 部分（如实标注） |
| 工作有效 | 基线不存在的新结构：31 个 `.mbti` 接口文件入库并被 CI 闸门约束、`lib/protocol/`（Event/Command + 往返测试）、append-only JSONL 会话日志 + `cmd inspect`、`cmd selftest` 契约探针、`scripts/known_gaps.sh` 真话台账 | ✅ |
| 开源合规 | `LICENSE`（MIT）+ `NOTICE`（上游 clacky-ai/openclacky、12 个直接依赖及许可、参考设计 OpenSeek 不复制代码）+ README 来源说明 | ✅ |
| AI 可解释 | `docs/ai-usage.md`（AI 使用声明 + 三类机器闸门）+ 闸门均为可运行命令 | ✅ |

## 2. 交付物与独立验证方式

### 2.1 P0-1 公共 API 闸门（`.mbti` + CI diff）

```bash
moon info
git diff --exit-code -- '**/pkg.generated.mbti'   # 期望：无输出、exit 0
```

- 全仓 **31 个** `pkg.generated.mbti` 已入库（`lib/` + `cmd/`）；`.gitattributes` 固定
  LF，避免 Windows `core.autocrlf` 造成假差异。
- **非空洞性已验证**：临时给 `lib/errors` 增加一个公共函数后，`moon info` 改动
  `lib/errors/pkg.generated.mbti`，上述命令报出该文件；删除后恢复干净。

### 2.2 P0-2 真话台账（`docs/known-gaps.md`）

```bash
scripts/known_gaps.sh check
# 期望：known-gaps ledger consistent: 159 live hits, 159 curated rows.
```

- 扫描段由脚本重生成并与文件逐字节比对（过期即失败）；每条命中必须有 curated 状态行
  （`open` / `fixed` / `retracted`）。
- 抑制规则（域术语、历史 `stubfix-NN` 引用、运行时状态描述、真实 C 辅助文件名）在
  `scripts/known_gaps.sh` 中可见，理由在台账 §抑制规则中列出。
- README 的「MCP Stdio/HTTP」不实声明已撤回；`--version` 与 `moon.mod` 的版本漂移已修
  复并由契约探针卡住；`moon install` 弃用命令已从 README/安装脚本/文档移除。

### 2.3 P0-3 CLI 契约探针（`cmd selftest`）

```bash
./$BIN selftest
```

实测输出（2026-09-21，Windows native）：

```
assertion engine self-check: 23/23 cases
target: native     PASS help / version / list_sessions / list_sessions_json /
                        unknown_flag(exit 1) / invalid_mode(exit 1) /
                        mcp_unavailable(exit 1)
target: moon-run   PASS 同上 7/7
native vs moon run differences: none
summary: 14/14 probes passed          (exit 0)
```

- 断言维度：退出码（zero / non-zero / 精确值）、stdout 形状（empty / text / json /
  json-lines）、stdout 必含子串、stderr 策略、禁用串（`Failure(`/`Panic(`/`Raised at`…）。
- 断言引擎自检 23 条合成样本，覆盖 live CLI 无法确定性产出的形状。
- 探针以 argv 数组执行（不过 shell），并对比「release 原生二进制」与 `moon run cmd`
  （对比前先预热一次，避免把构建成本误报为超时）。
- 顺带修掉两个真实契约缺陷：`mcp` 子命令原本打印「不可用」却 **exit 0**（现为 1）；
  `--version` 原打印 `v0.1.0` 而 `moon.mod` 为 `0.1.3`（现由探针交叉校验 manifest）。

### 2.4 P1-1 类型化引擎协议（`lib/protocol/`）

```bash
moon test lib/protocol --release          # 期望：8/8（每个 Event/Command 变体往返）
moon test lib/web --release               # 期望：469/469（Web 层无行为回归）
moon test lib/web/protocol --release      # 期望：41/41
```

- 叶子包只依赖 `moonbitlang/core/json`；31 个 `Event` 变体 + 10 个 `Command` 变体；
  `to_json` 是事件形状的唯一作者，`parse` 为其逆，`to_wire`/`to_framed_json` 负责封帧。
- Web 端：`lib/web` 已无手写事件 JSON 字面量（通用 `build_event`/`build_global_event`
  逃生口删除，13 处内联构造迁移为类型化 frame builder）。
- CLI 端：`--ndjson` 输出类型化事件流；`cmd inspect` 渲染协议事件时间线。
- 新增变体会在三处编译失败（Web `ws_frame`、CLI `log_event`、`inspect` 渲染）。
- 设计取舍与未接入 TUI 的理由见
  [ADR-0001](../specs/decisions/2026-09-21_01_typed-engine-protocol-leaf-boundary.md)。

### 2.5 P1-2 可回放会话日志（append-only JSONL + `cmd inspect`）

```bash
moon test lib/agent --release --filter "session log*"   # 期望：5/5
./$BIN inspect <session.jsonl>                          # 期望：时间线
./$BIN inspect <session.json>                           # 期望：legacy 只读导入渲染
```

DoD 三项均有测试固定：

| DoD | 测试 | 结果 |
|---|---|---|
| 给定 `.jsonl` 可离线回放 | `create, append and read roundtrip` + `cmd inspect` 实测 | ✅ |
| 截断最后一个字节仍能恢复 | `truncated tail recovers complete records`（丢尾行、完整记录保留、续写不撞号） | ✅ |
| 压缩前后原始事件字节完全一致 | `compaction appends and preserves original bytes`（新文件以原字节为前缀） | ✅ |

另覆盖：`session.lock` 排他锁与陈旧锁恢复、旧 JSON 会话只读投影（不就地改写）。

## 3. 平台与未完成项（如实说明）

| 事项 | 状态 | 说明 |
|---|---|---|
| `moon test`（debug） | 不可用 | moonc ≥ 20260827 工具链在 debug 模式链接 mbtpdf 相关测试二进制时 ICE；CI 与本地统一用 `--release`（见 `.github/workflows/ci.yml` 注记） |
| Windows 本机全量 release 测试 | 挂起 | `lib/mcp/mcp.whitebox_test.exe` 近零 CPU、无子进程产出（与 moonbitmark 升级无关：无依赖边）；Linux CI 该包全绿。单包测试可绕过 |
| `cmd eval`（P2 评测分层） | 未实现 | P2 为 stretch；范围冻结原则下不进 P0/P1 验收，登记于 known-gaps |
| TUI 未绑定 wire 词表 | 已知取舍 | TUI 直接消费引擎 `HookEvent`（其富状态机需要 wire 有意丢弃的信息）；TUI 的 HookEvent 匹配仍穷尽，新增引擎事件仍会编译失败。理由见 ADR-0001 §7 |
| 旧会话文件 schema | 部分不兼容 | 参考机器 32 个会话文件中 31 个因旧 `tool_calls` schema 或非 JSON 内容无法解析；`--list` 现已如实报告数量，`inspect` 报告具体原因；schema 迁移仍待办 |
| GitHub Issue/PR 流程 | 未执行 | 本地提交连续；推送与 Issue/PR 属于远端流程，不在本次执行范围 |

## 4. 本期提交序列（本地）

```
chore(deps): bump moonbitmark 0.4.3 -> 0.4.5 (latest release)      # 阶段一
docs(known-gaps): machine-verified truth ledger + honest doc fixes # P0-2
ci: gate public API (.mbti diff) and make warning budget strict    # P0-1（初次，后证明空洞）
feat(cli): contract probes via 'cmd selftest'                      # P0-3
fix(ci): make the public API gate real - track pkg.generated.mbti  # P0-1 修复
feat(protocol): typed engine protocol leaf package                 # P1-1 (1/2)
feat(protocol): migrate the Web and CLI ends to the typed protocol # P1-1 (2/2)
feat(session): append-only JSONL session log + offline replay      # P1-2
```

`git tag v0.2.0-hackathon` 标记本期验收点。
