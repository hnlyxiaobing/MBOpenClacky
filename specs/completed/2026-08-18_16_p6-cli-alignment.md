# CLI 命令行面对齐（矩阵§8）· 增量 Spec

> **创建日期**: 2026-08-18  
> **状态**: 已实施并归档（2026-08-20）· 曾通过对抗性审查（2026-08-18）
> **关联总览**: `specs/active/2026-08-18_01_diff-harness-matrix-backlog-overview.md`；diff-harness `docs/FEATURE_MATRIX.md` §8  
> **关联历史 spec**: 边界——`--fork` 的执行语义归 B7（fork_subagent 移植），本 spec 只负责 CLI 入口接线；server 路由/认证面对齐归 B9；配置加载差异归 B10；会话命名/恢复差异归 B5；矩阵旧台账编号已被覆盖，一律使用 `矩阵§8/条目名` 锚点  
> **来源差距**: P1 静态对齐矩阵（2026-08-12）§8 partial/missing 条目，2026-08-18 逐条对当前代码复核  
> **依赖**: B7（`--fork` 入口消费方）；B5（会话自动命名语义）  
> **灰度 key**: 无

## 问题描述 [必填]

### 子命令面缺失

1. **mcp 子命令组整体缺失（missing，已核实）**：Ruby 有 `clacky mcp`（MCP server 暴露）；MB `cmd/main.mbt:74-181` subcmds 仅 billing/server/onboard/benchmark/ext。
2. **patch_new/patch_verify/patch_list 缺失（missing，已核实）**：MB 只有 `--patches-dir` 加载面（main.mbt:46-49,646-659），无创作/校验子命令。
3. **hook_new/hook_verify 缺失（missing，已核实）**：MB 只有 `--hooks-dir` 加载面（main.mbt:50-53,661-677），无创作/校验子命令。
4. **channel_new 语义差异（partial，已核实）**：Ruby `clacky channel new/verify`；MB 是顶层 `--scaffold-channel` flag，固定 6 平台白名单（`cmd/channel_scaffold.mbt:3-7`：feishu/wecom/telegram/discord/dingtalk/weixin），无 verify。
5. **agent 子命令缺失（partial）**：Ruby `clacky agent` 显式子命令；MB 走默认路径（main.mbt:282-286）。裁决点：是否补别名入口。
6. **billing 选项缩水（partial，已核实）**：`handle_billing()` 无任何参数（main.mbt:290-327），仅 all-time 汇总；Ruby 有周期/格式化选项。
7. **ext 缺 verify/pack/publish（partial，已核实）**：MB ext 仅 list/install/uninstall/enable/disable/info/search/create 八个（main.mbt:109-179、cli_ext.mbt）。

### 顶层选项面缺失

8. **`--fork` 无入口（missing，已核实）**：Grep 全 cmd 目录无 fork 相关参数；依赖 B7 落地后接线。
9. **`--json` 结构化输出缺失（missing，已核实）**：`--ndjson` 仅是 NDJSON 日志开关（main.mbt:45,283-285），非结果输出格式；Ruby `--json` 产出机器可读运行结果。
10. **`-f/--file` 与 `-i/--image` 附件入口缺失（missing，已核实）**：args 表（main.mbt:10-73）无文件/图片附件参数。图片消费链与 B2 决策 image_inject 联动。
11. **`-c`/`-l`/`-a` 短选项缺失（partial，已核实）**：continue/list/attach 均无 short（main.mbt:39-44）；Ruby 有。
12. **`--theme`/`--ui`/`--brand_test`/`--no_*` 系列缺失（partial，已核实）**：args 表无这些参数。
13. **`--path` 无存在性校验（partial，已核实）**：`@utils.change_dir(p)` 无条件执行（main.mbt:629-638），无效路径静默进入错误目录语义未定义。

### 运行行为差异

14. **中断退出码 130 vs Ruby 1（partial，已核实）**：`Interrupted => 130`（main.mbt:851-856）；Ruby 恒 1。裁决点：130 是 POSIX SIGINT 惯例（MB 超集）还是对齐 Ruby。
15. **多打 `✓ Done (N iterations, $cost)` 汇总行（partial，已核实）**：`print_run_result`（main.mbt:876-888）；Ruby 非交互模式无此汇总（输出仅模型正文）。
16. **裸 `-m`（无值）落 TUI（partial，已核实）**：nargs AtMost(1) + `get_named_arg` 返回 None 时进入 `run_tui_interactive`（main.mbt:716-722）；Ruby 报错或空消息处理。
17. **会话自动命名 unclear**：Ruby 会话有自动标题；MB 命名语义未核对，任务包 0 复核（与 B5 会话面对齐合并）。
18. **server `--host/--port` CLI 参数缺失（missing，已核实）**：仅环境变量 MBOPENCLACKY_WEB_HOST/PORT（main.mbt:472-530）；默认端口 7071 与 Ruby 7070 不同（注释自认，main.mbt:521-522）。裁决点：7071 保留与否。
19. **公网绑定门退出码 0 vs Ruby 1（partial，已核实）**：安全门拒绝时 `return`（main.mbt:517），进程退出码 0；Ruby exit 1。
20. **master/worker 双进程架构 unclear**：Ruby server 有双进程语义；MB 单进程，任务包 0 评估必要性。

## 现状分析 [必填 - 含代码验证]

### 验证记录（2026-08-18，对当前 HEAD 复核）

| 声称 | 验证方式 | 结果 | 结论 |
|------|---------|------|------|
| mcp/patch/hook 子命令缺失 | 读 `cmd/main.mbt:74-181` subcmds 表 + Grep `patch_new\|hook_new\|"mcp"` cmd 目录 | subcmds 仅 billing/server/onboard/benchmark/ext；0 匹配 | 证实 |
| channel_new 6 固定平台无 verify | 读 `cmd/channel_scaffold.mbt:3-7` | 白名单数组恰 6 平台，`--scaffold-channel` 顶层 flag 形式 | 证实 |
| billing 无参数 | 读 `cmd/main.mbt:75,290-327` | `SubCommand::new` 无 args；handle_billing 恒 all-time | 证实 |
| ext 缺 verify/pack/publish | 读 `cmd/main.mbt:109-179` | 8 个子命令，无 verify/pack/publish | 证实 |
| `--fork` 无入口 | Grep `fork` cmd 目录 | 0 匹配 | 证实 |
| `--json` 缺失（--ndjson 仅日志） | 读 `cmd/main.mbt:45,283-285` | ndjson 只构造 NdjsonLogger | 证实 |
| `-f`/`-i` 附件缺失 | 读 `cmd/main.mbt:10-73` args 全表 | 无 file/image 参数 | 证实 |
| `-c`/`-l`/`-a` 短选项缺失 | 读 `cmd/main.mbt:39-44` | continue/list/attach 均无 short | 证实 |
| `--path` 无校验 | 读 `cmd/main.mbt:629-638` | change_dir 直接执行，无存在性检查 | 证实 |
| 中断退出码 130 | 读 `cmd/main.mbt:851-856` | `Interrupted => 130` | 证实 |
| `✓ Done` 汇总行 | 读 `cmd/main.mbt:876-888` | Success 分支打印汇总 | 证实 |
| 裸 `-m` 落 TUI | 读 `cmd/main.mbt:11-15,716-722` | AtMost(1) 无值时 msg_opt=None 进 TUI | 证实 |
| server 仅环境变量、默认 7071 | 读 `cmd/main.mbt:472-530` | 无 --host/--port CLI；注释自认区别于 Ruby 7070 | 证实 |
| 公网门退出码 0 | 读 `cmd/main.mbt:481-518` | 拒绝后 `return` 无 exit | 证实 |
| theme/ui/brand_test/no_* 缺失 | 读 `cmd/main.mbt:10-73` args 全表 | 无 | 证实 |
| 会话自动命名 / master-worker 双进程 | 矩阵行号引用 | 未逐行核对 | unclear（任务包 0） |

Ruby 参照（openclacky，只读）：`exe/clacky` 命令面、`cli.rb` 各子命令定义。

### 影响面

子命令面缺失（mcp/patch/hook）是能力缺口：用户无法经 CLI 管理补丁/钩子生命周期，MCP 集成整体不可用。行为差异中**公网门退出码 0** 最危险（脚本/CI 无法感知安全拒绝）；中断退出码 130 与 Ruby 1 的不一致会破坏依赖退出码的差分测试闸门（test/diff 已知受影响面）。

## 决策 [必填 - 含为什么]

1. **决策 1（mcp 子命令组）**：按 Ruby 移植 `mcp` 子命令组（stdio MCP server 暴露）。
   - **为什么**：MCP 是与外部工具链集成的标准面，整体缺失属能力缺口。
2. **决策 2（patch/hook 创作子命令）**：移植 patch_new/patch_verify/patch_list 与 hook_new/hook_verify；复用既有 PatchLoader/load_shell_hooks 的解析器做 verify。
   - **为什么**：只有加载面没有创作/校验面，用户资产生命周期不完整。
3. **决策 3（channel 面）**：`--scaffold-channel` 保留为顶层 flag（MB 既有形式），补 `verify` 能力与平台白名单外报错文案对齐；是否另立 `channel` 子命令组为裁决点（倾向保留 flag 形式并记录）。
4. **决策 4（选项补齐组）**：补 `-c`/`-l`/`-a` 短选项、`-f/--file`、`-i/--image`、`--json`（运行结果 NDJSON/JSON 输出，与 `--ndjson` 日志开关明确区分）、`--fork`（B7 落地后接线）；`--theme`/`--ui`/`--brand_test`/`--no_*` 随对应功能面（TUI/品牌）状态裁决，未实现者记录豁免而非空开关。
   - **为什么**：`-f`/`-i` 是附件管线入口（联动 B2 image_inject）；`--json` 是机器消费与差分测试的基础。
5. **决策 5（`--path` 校验）**：路径不存在/非目录时报错 exit 1，不静默 change_dir。
6. **决策 6（退出码与输出对齐）**：中断退出码对齐 Ruby 1（裁决记录：放弃 130 POSIX 惯例，以行为一致优先；若差分测试已按 130 断言则同步修订）；公网绑定门拒绝改 exit 1；非交互模式去掉 `✓ Done` 汇总行（或移入 `--verbose`，裁决倾向完全移除以对齐 Ruby stdout 语义）。
   - **为什么**：退出码与 stdout 是脚本消费契约，汇总行污染机器解析。
7. **决策 7（裸 `-m` 行为）**：`-m` 无值时报错 exit 1（对齐 Ruby），不再静默落 TUI。
8. **决策 8（server 参数面）**：补 `--host`/`--port` CLI 参数（优先级高于环境变量）；默认端口 7071 保留为 MB 超集裁决（注释已自认区分意图，改 7070 会与并行运行的 Ruby 原版冲突）并记录。
9. **决策 9（裁决点组）**：agent 子命令别名入口（倾向不补，默认路径即 agent）；master/worker 双进程按任务包 0 结论处置（倾向不实现并记录）；会话自动命名随 B5 复核结论接线。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `cmd/main.mbt` | 修改 | args 表补选项、subcmds 补 mcp/patch/hook、退出码、`✓ Done`、`--path` 校验、裸 `-m`、server 参数 |
| `cmd/cli_mcp.mbt`（新建） | 新建 | mcp 子命令组 |
| `cmd/cli_patch.mbt` / `cmd/cli_hook.mbt`（新建） | 新建 | patch/hook 创作与 verify 子命令 |
| `cmd/channel_scaffold.mbt` | 修改 | verify 能力、白名单外报错 |
| `cmd/cli_ext.mbt` | 修改 | ext verify/pack/publish（随 extension 模块能力，超出部分记录豁免） |
| 对应 wbtest | 修改/新建 | 参数解析与退出码回归 |

### 不涉及文件

- server 路由/认证（B9）；配置加载（B10）；fork 执行语义本体（B7）；image_inject 消费链本体（B2）。

## 实施计划 [必填]

### 任务包 0：复核与裁决（预估 0.5 天）
1. 会话自动命名、master/worker 双进程两项 unclear 复核。
2. 裁决点落地记录（agent 别名、7071 保留、theme/ui 豁免）。

### 任务包 1：选项与退出码对齐（预估 1 天）
1. 短选项、`-f`/`-i`、`--json`、`--path` 校验、裸 `-m` 报错。
2. 退出码对齐（中断 1、公网门 exit 1）、`✓ Done` 移除。
3. wbtest：参数解析、退出码矩阵。

### 任务包 2：子命令组移植（预估 2 天）
1. mcp 子命令组；patch_new/verify/list；hook_new/verify。
2. channel verify；ext verify/pack/publish 按能力边界落实。
3. wbtest：各子命令冒烟 + verify 路径。

### 任务包 3：收尾（预估 0.5 天）
1. `--fork` 接线（前置 B7）；server `--host/--port`。
2. `moon check` + 全量 `moon test` 无回归；同步修订 test/diff 中按旧退出码断言的用例。

## 验收标准 [必填]

- [x] `patch new|verify|list`/`hook new|verify` 子命令可用且与 Ruby 参数面一致（`mcp` 子命令入口已保留，stdio serve 能力拆二期，见豁免）
- [x] `-c`/`-l`/`-a`/`-f`/`-i`/`--json` 入口存在且语义对齐（`--fork` 待 B7，记豁免）
- [x] `--path` 指向不存在目录时 exit 1 并报错
- [x] 中断退出码为 1；公网绑定门拒绝时 exit 1
- [x] 非交互模式 stdout 无 `✓ Done` 汇总行
- [x] 裸 `-m`（无值）报错 exit 1 而非进入 TUI
- [x] server 支持 `--host`/`--port`，优先级高于环境变量
- [x] `moon check` 0 errors；`moon test cmd` 无回归（全量 `moon test` 中 web 包存在与本次改动无关的既有 Windows 路径 panic）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 退出码变更破坏既有差分测试断言 | 中 | 任务包 3 同步修订 test/diff 用例，变更说明记录新旧值 |
| mcp 子命令依赖 stdio JSON-RPC 基础设施 | 高 | 任务包 0 先盘点 MB 侧 stdio/JSON 能力，必要时拆二期 |
| `--json` 与 `--ndjson` 语义混淆 | 低 | help 文案显式区分（结果输出 vs 日志格式） |
| 移除 `✓ Done` 影响现有用户习惯 | 低 | MB 处于 0.1.0，以对齐 Ruby 契约优先 |

## 依赖关系 [必填]

- **前置依赖**：无硬前置；`--fork` 接线软依赖 B7。
- **后置依赖**：B9 server 面在本 spec 的 `--host/--port` 之上继续。
- **交叉**：`-i` 附件消费链与 B2 image_inject、B4 图片占位决策联动；会话命名随 B5。

## 变更记录 [必填]

- 2026-08-18：创建（diff-harness 矩阵§8 残留条目核实落 spec；15 项直接证实 + 2 项 unclear 留任务包 0 复核）。
- 2026-08-20：实施完成并归档。

### 实施结果（2026-08-20）

**已落地（决策 1–8）：**

| 决策 | 落地情况 |
|------|---------|
| 决策 2（patch/hook 创作子命令） | `patch new/verify/list`、`hook new/verify` 子命令已实现，复用 `PatchLoader`/`load_shell_hooks` 解析器做 verify（`cmd/cli_patch.mbt`、`cmd/cli_hook.mbt`） |
| 决策 3（channel verify） | `verify_channel` + 顶层 `--verify-channel <platform>` flag；`--scaffold-channel` 保留 flag 形式（裁决记录：不另立 channel 子命令组） |
| 决策 4（选项补齐组） | `-c`/`-l`/`-a` 短选项、`-f/--file`、`-i/--image`、`--json`（运行结果 JSON，与 `--ndjson` 日志明确区分）已补；`--fork` 因 B7 未落地记豁免；`--theme`/`--ui`/`--brand_test`/`--no_*` 记豁免（不加空开关） |
| 决策 5（`--path` 校验） | 不存在/非目录时报错 exit 1 |
| 决策 6（退出码与输出） | 中断退出码 130→1；公网绑定门拒绝 exit 1；非交互模式移除 `✓ Done` 汇总行 |
| 决策 7（裸 `-m`） | 无值报错 exit 1，不再静默落 TUI（`is_bare_message_flag` 从原始 argv 检测） |
| 决策 8（server 参数） | `server --host/--port` CLI 参数（优先级高于环境变量）；默认端口 7071 保留（裁决记录：MB 超集） |
| 决策 7（ext verify/pack/publish） | `ext verify`/`ext pack`/`ext publish` 已接线到既有 `@extension.validate_extension`/`package_extension`/`publish_extension` |

**豁免项（记录，未实现）：**

| 项 | 原因 |
|----|------|
| 决策 1（mcp 子命令组 stdio 暴露） | `lib/mcp/stdio_transport.mbt` 仍是占位符（"TODO: FFI implementation needed"），stdio JSON-RPC serve 能力未实现。CLI 入口 `mcp` 子命令已保留并给出明确提示，拆二期 |
| `--fork` 接线 | 依赖 B7（fork_subagent 移植），B7 无对应 spec，未落地 |
| agent 子命令别名（决策 9） | 裁决不补，默认路径即 agent |
| master/worker 双进程（决策 9） | 裁决不实现并记录 |
| 会话自动命名（决策 9） | 随 B5 复核结论接线，本 spec 未改动 |

**验证：**

- `moon check`：0 errors
- `moon test cmd`：26 passed, 0 failed（新增 `is_bare_message_flag`/`parse_port`/`verify_channel` 回归测试）
- 全量 `moon test`：web 包 `handlers_session_ext_wbtest.mbt:188` 存在既有的 Windows 路径分隔符 panic（`save_session FAILED`），与本次 CLI 改动无关（改动范围仅 `cmd/`）
- test/diff 无针对退出码 130 或 `✓ Done` 的既有断言，无需同步修订
