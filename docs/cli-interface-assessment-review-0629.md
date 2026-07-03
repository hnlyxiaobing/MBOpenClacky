# MBOpenClacky CLI 用户界面实现状况评审报告

> **文档版本**: 1.1  
> **评审日期**: 2026-06-29（2026-07-03 同步最新代码）  
> **评审范围**: `cmd/main.mbt` 入口 + `lib/tui/` 模块 + CLI 流程编排  
> **基线文档**: `docs/gap-analysis-between-projects-2026-06-30.md`、`docs/project-status-and-deployment-guide.md`  
> **评审目的**: 对前次 CLI 评估报告进行事实校正与细化，形成权威问题清单与修复时间表
---

## 目录

1. [评审范围与基线确认](#1-评审范围与基线确认)
2. [前次报告的问题修正清单](#2-前次报告的问题修正清单)
3. [CLI 核心实现现状（校正后）](#3-cli-核心实现现状校正后)
4. [已确认的缺失与不完整功能清单](#4-已确认的缺失与不完整功能清单)
5. [分项解决方案与精确工时](#5-分项解决方案与精确工时)
6. [优先级排序与实施路线](#6-优先级排序与实施路线)
7. [附录：代码锚点索引](#7-附录代码锚点索引)

---

## 1. 评审范围与基线确认

### 1.1 评审对象

| 对象 | 路径 | 实际行数/文件数 |
|------|------|---------------|
| CLI 主入口 | `cmd/main.mbt` | 530 行 |
| CLI 辅助模块 | `cmd/` | 8 个文件（main + 5 个辅助 .mbt + moon.pkg + pkg.generated.mbti） |
| TUI 模块 | `lib/tui/` | 29 个 `.mbt` + 4 个 `*_wbtest.mbt`，共 6,784 行（含测试） |
| 会话管理支撑 | `lib/agent/session_manager.mbt` | 339 行（已实现 fork_session） |
| 服务发现支撑 | `lib/server/discover.mbt` | 98 行（find_all_local 为 stub） |
| 计费支撑 | `lib/billing/billing_store.mbt` 等 | 4 个文件，691 行（完整实现） |
| 源项目 CLI 入口 | `openclacky/lib/clacky/cli.rb` | 1,521 行（参考对照） |

### 1.2 CLI 选项总数确认（关键修正）

`cmd/main.mbt` 中实际通过 `@clap.Parser::new` 注册的命名参数为 **16 个**，外加 **2 个子命令**，合计 18 个入口：

| 编号 | 参数 | 类型 | 说明 |
|------|------|------|------|
| 1 | `--message/-m` | named, AtMost(1) | 非交互式消息 |
| 2 | `--mode` | named, Fixed(1) | 权限模式（auto_approve/confirm_safes/confirm_all） |
| 3 | `--model` | named, AtMost(1) | 覆盖模型名 |
| 4 | `--agent` | named, Fixed(1) | Agent profile，默认 `coding` |
| 5 | `--path` | named, AtMost(1) | 工作目录路径 |
| 6 | `--verbose/-v` | flag | 详细输出 |
| 7 | `--version/-V` | flag | 打印版本 |
| 8 | `--continue` | flag | 恢复最近会话 |
| 9 | `--list` | flag | 列出会话 |
| 10 | `--attach` | named, AtMost(1) | 按 ID 附加会话 |
| 11 | `--ndjson` | flag | NDJSON 日志 |
| 12 | `--patches-dir` | named, Fixed(1) | 自定义补丁目录 |
| 13 | `--hooks-dir` | named, Fixed(1) | 自定义钩子目录 |
| 14 | `--extensions-dir` | named, Fixed(1) | 自定义 API 扩展目录 |
| 15 | `--scaffold-channel` | named, Fixed(1) | 生成 Channel 模板 |
| 16 | `--list-templates` | flag | 列出 Channel 模板 |
| Sub1 | `billing` | subcmd | 计费汇总 |
| Sub2 | `server` | subcmd | 启动 Web UI |

> ⚠️ **修正说明**：前次报告将 CLI 选项数描述为"10 个"，实际为 16 个。10 这个数字仅对应"主要功能类"参数（message/mode/model/agent/path/v/version/continue/list/attach），其余 6 个为基础设施类参数。

---

## 2. 前次报告的问题修正清单

通过对 `cmd/main.mbt`、`cmd/channel_scaffold.mbt`、`lib/tui/agent_hooks.mbt`、`lib/tui/slash_commands.mbt`、`lib/tui/state.mbt`、`lib/agent/session_manager.mbt`、`lib/agent/hook.mbt`、`lib/server/discover.mbt`、`lib/billing/billing_store.mbt` 等关键文件的逐一审计，前次报告存在以下需要修正的描述：

### 2.1 错误/失实修正

| 编号 | 前次报告描述 | 核实后真实情况 | 修正影响 |
|------|-------------|---------------|---------|
| **E-1** | "HookEvent 翻译 6/25 待补齐" | HookEvent 实际只有 **10 个变体**（`StatusChanged`/`BeforeIteration`/`AfterIteration`/`BeforeLlmCall`/`AfterLlmCall`/`MessageAdded`/`ToolExecuting`/`ToolExecuted`/`ErrorOccurred`/`RunCompleted`），且 `lib/tui/agent_hooks.mbt::dispatch_hook_event` 已 **100% match** 所有 10 个变体 | 直接删除该项问题，或重新评估为"已完整" |
| **E-2** | "缺少 `/config` 命令" | `lib/tui/slash_commands.mbt::SlashCommandParser` 已注册 7 个命令（config/model/clear/new/skills/help/exit），`/config` 的解析逻辑完整；但 `execute()` 函数仅返回描述性字符串，未实际调用 `@config`/Agent 接口 | 修正为"P2 已实现但未生效"，预估工时从 2 天降至 0.5 天 |
| **E-3** | "缺少 `/clear` 命令" | 同上，`/clear` 的解析器已实现，但 `execute()` 仅返回 "Message history cleared" 字符串，未实际清空消息历史或重建 Client | 修正为"P2 已实现但未生效"，预估工时 0.5 天 |
| **E-4** | "缺少 Sibling Server 自动发现" | `lib/server/discover.mbt` 已实现 `find_local()`/`find_all_local()`/`write_pid_file()`/`is_process_alive()` 等函数，但 `find_all_local` 因 FFI 未完成（依赖"扫描目录 + 进程检测"系统调用）返回空数组，`is_process_alive` 永远返回 `true` | 修正为"P1 框架已建但 stub 化"，预估工时从 1 天修正为 1.5 天（含 FFI 实现） |
| **E-5** | "Billing 子命令未实现" | `lib/billing/billing_store.mbt` 已完整实现（Summary/ModelSummary/DaySummary 等数据结构 + append/query/summary/daily_breakdown/cleanup 5 个核心方法），问题仅在 `cmd/main.mbt::handle_billing()` 是占位实现 | 修正为"P1 上层未连接底层"，预估工时从 2 天降至 0.5 天 |
| **E-6** | "缺少 Rich UI 第二套实现" | 准确，但源项目 `rich_ui/` 模块以"高级 TUI 美化"为主，与"基本 TUI 交互"功能正交；对终端 CLI 核心体验的影响有限 | 维持评估，但建议从 P2 调整为可选 |
| **E-7** | "缺少 `--theme` 选项" | 源项目实际仅支持 `hacker`/`minimal` 两种内置主题，不影响 CLI 核心可用性 | 维持 P2，工时 0.5 天不变 |

### 2.2 描述不够精确的修正

| 编号 | 前次描述 | 修正后描述 |
|------|---------|-----------|
| **R-1** | "缺少 `/fork` 会话分叉" | `lib/agent/session_manager.mbt::fork_session`（第 136-179 行）已实现完整分叉逻辑（含新 ID 生成、统计清零、`forked_from` 标记、消息完整复制）；CLI 仅缺少 `--fork` 参数接入（预计 0.5-1 天） |
| **R-2** | "缺少工作目录切换与恢复" | `cmd/main.mbt::run_agent` 第 274-290 行通过 CD/PWD 环境变量读取工作目录，但**未调用 `Dir.chdir`**，Agent 在原始 cwd 中运行；需在 `run_agent` 入口处补充 `chdir` 并在出口处 `chdir` 恢复 |
| **R-3** | "缺少 Client Factory 模式" | 当前 `cmd/main.mbt` 在第 267-272 行直接构造 `@client.Client`，未采用源项目的 lambda 工厂模式；这意味着 `--model` 切换后所有工具调用仍使用旧 Client（修复优先级中等） |
| **R-4** | "缺少图片粘贴支持" | 源项目通过平台 FFI 实现，TUI 中可通过 lib/utils + lib/parser 实现图片二进制读取和 base64 内联，工作量与单纯"附加 --file"接近；建议合并到 P1-02 |

### 2.3 缺失但应补充的细节

| 编号 | 应补充内容 | 用途 |
|------|-----------|------|
| **A-1** | 当前 CLI 的 6 个子模块与 main.mbt 的依赖关系图 | 帮助理解 main.mbt 中如何串联 load_config → session → patch → hook → extension → agent.run |
| **A-2** | TUI 渲染组件清单与缺失对照 | 当前 TuiState 字段反映已实现能力，缺失字段反映待补齐项 |
| **A-3** | 钩子事件全景映射表 | 明确 Agent HookEvent 10 个变体与 TUI 状态字段的精确对应 |
| **A-4** | 工时复算依据 | 基于每项改动涉及的文件数、改动性质、是否涉及 FFI、是否需要新模块测试等维度 |

---

## 3. CLI 核心实现现状（校正后）

### 3.1 已完整实现的功能

| 功能 | 实现位置 | 代码量 | 状态 |
|------|---------|--------|------|
| CLI 参数解析 | `cmd/main.mbt` L7-70 | 64 行 | ✅ 完整 |
| 配置加载与校验 | `cmd/main.mbt::run_agent` L213-229 + `lib/config/` | 跨多文件 | ✅ 完整 |
| 模型选择与切换 | `cmd/main.mbt::apply_model_override` L414-430 | 17 行 | ✅ 完整 |
| 权限模式设置 | `cmd/main.mbt` L239-244 | 5 行 | ✅ 完整 |
| 工作目录解析 | `cmd/main.mbt` L274-290 | 17 行 | ✅ 完整读取，未切换 |
| 会话解析（continue/attach） | `cmd/main.mbt::resolve_session` L378-411 | 34 行 | ✅ 完整 |
| 补丁加载与应用 | `cmd/main.mbt` L298-311 + `cmd/patch_loader.mbt` | 跨文件 | ✅ 完整 |
| 钩子加载与执行 | `cmd/main.mbt` L313-329 + `cmd/hook_loader.mbt` | 跨文件 | ✅ 完整 |
| API 扩展加载 | `cmd/main.mbt` L331-340 + `cmd/api_extension_loader.mbt` | 跨文件 | ✅ 完整 |
| Agent 创建 | `cmd/main.mbt` L342-346 | 5 行 | ✅ 完整 |
| 会话恢复 | `cmd/main.mbt` L348-359 | 12 行 | ✅ 完整 |
| 非交互模式运行 | `cmd/main.mbt::run_non_interactive` L432-499 | 68 行 | ✅ 完整（含 Interrupted/Error 三态） |
| TUI 交互模式入口 | `cmd/main.mbt` L362-368 + `lib/tui/tui.mbt` | 跨文件 | ✅ 入口完整，渲染依赖平台 |
| NDJSON 日志 | `cmd/main.mbt` L141-144 + `cmd/ndjson_logger.mbt` | 跨文件 | ✅ 完整 |
| Channel 脚手架 | `cmd/channel_scaffold.mbt` 整文件 | 82 行 | ✅ 完整支持 6 平台 |
| Session 列表 | `cmd/main.mbt::handle_list_sessions` L501-514 | 14 行 | ✅ 完整 |
| Web 服务器子命令 | `cmd/main.mbt::handle_server` L174-201 | 28 行 | ✅ 完整 |

### 3.2 部分实现 / Stub 化的功能

| 功能 | 实现位置 | 真实状态 | 影响 |
|------|---------|---------|------|
| Billing 子命令 | `cmd/main.mbt::handle_billing` L148-151 | 仅输出占位文字，**底层 BillingStore 完整** | 用户运行 `mbopenclacky billing` 仅看到提示 |
| Sibling Server 发现 | `lib/server/discover.mbt::find_all_local` L37-49 | 函数返回空数组（含 TODO 注释） | 技能回环调用不可达 |
| PID 文件写入/删除 | `lib/server/discover.mbt::write_pid_file/remove_pid_file` L52-68 | 返回 `Ok(())` 但无实际写文件 | 服务器模式无法跨进程标识 |
| 进程存活检测 | `lib/server/discover.mbt::is_process_alive` L93-97 | 永远返回 `true` | 即便有 PID 文件也无效 |
| TUI 斜杠命令执行 | `lib/tui/slash_commands.mbt::execute` L162-186 | 返回描述字符串而非执行实际操作 | `/clear`、`/config` 等仅打印提示 |

### 3.3 当前 CLI 选项覆盖度（vs 源项目）

| 类别 | 源项目选项 | MBOpenClacky 选项 | 缺失选项 |
|------|-----------|-------------------|---------|
| 运行控制 | `--mode`、`--verbose`、`--message`、`--continue`、`--attach`、`--fork`、`--list`、`--path`、`--agent`、`--model` | 同上 10 项 | `--fork` |
| 主题/UI | `--theme`、`--ui` | ❌ 全部缺失 | `--theme`、`--ui` |
| 文件附加 | `--file`、`--image` | ❌ 全部缺失 | `--file`、`--image` |
| 脚本化输出 | `--json`（NDJSON 交互模式） | `--ndjson`（仅日志级别） | `--json` |
| 子命令 | `clacky server`、`clacky channel`、`clacky billing`、`clacky config` 等 | `server`、`billing` | `channel`、`config`、`update`、`version` 等 |
| 工具链 | `--patches-dir`、`--hooks-dir`、`--extensions-dir`、`--scaffold-channel`、`--list-templates` | 同上 5 项 | 无 |

> 📊 **覆盖率统计**：核心功能选项覆盖率 **92%**（11/12），脚本化与主题 UI 覆盖率 **0%**（0/3），文件附加覆盖率 **0%**（0/2）。

---

## 4. 已确认的缺失与不完整功能清单

> 下列清单已根据 §2 的修正项整理，去除错误项、合并近似项、补充细节。

### 4.1 P1 — 影响功能完整性（7 项，合计 ~6.5 人天）

| 编号 | 问题 | 影响范围 | 涉及文件 | 基础评估 |
|------|------|---------|---------|---------|
| **P1-01** | 缺少 `--fork` 会话分叉选项（底层 `fork_session` 已实现） | CLI 多会话分支场景 | `cmd/main.mbt` L36-65（注册）+ L292-410（调用） | `fork_session` 已在 `lib/agent/session_manager.mbt:136` 实现，CLI 仅需接入，**0.5-1 天** |
| **P1-02** | 缺少 `--file/-f` 与 `--image/-i` 文件附件支持 | 非交互模式附图/文档 | `cmd/main.mbt`（新增 args）+ `cmd/main.mbt::run_non_interactive`（修改签名）+ `lib/agent/`（文件注入） | 需新增 file 路径解析、文件类型判定、MIME 标记、Agent 消息构造，**1.5 天** |
| **P1-03** | 缺少 NDJSON 交互模式（`--json`） | 脚本/CI 集成场景 | `cmd/main.mbt`（新增 args）+ `cmd/ndjson_logger.mbt`（扩展为流式输出）+ `cmd/main.mbt::run_agent`（流式分支） | 现有 `NdjsonLogger` 仅记录日志，需扩展为 stdout 流式事件（message_added/iteration/tool_exec/done），**2 天** |
| **P1-04** | Sibling Server 发现为 stub（`find_all_local` 返回空） | 技能回调（channel/browser/scheduler）在 CLI 模式下工作 | `lib/server/discover.mbt` L37-49、L52-68、L93-97 | 需 FFI 实现 `opendir/readdir`、`open/write/close`、`kill(pid, 0)` 或 Windows 等价，**1.5 天** |
| **P1-05** | 工作目录未切换（`run_agent` 读取了 `path` 但未 `Dir.chdir`） | 多项目并行、shell 自动化集成 | `cmd/main.mbt::run_agent` L274-290 + L487-498 | 需在 `run_agent` 入口保存 `original_dir`、`chdir(working_dir)`，在 `ensure` 块中 `chdir(original_dir)`，**0.5 天** |
| **P1-06** | Billing 子命令未连接底层 BillingStore | 用户运行 `billing` 仅看到占位提示 | `cmd/main.mbt::handle_billing` L148-151 | BillingStore 已完整实现，仅需 `BillingStore::default() + .summary() + println`，**0.5 天** |
| **P1-07** | TUI 斜杠命令未实际生效（`/clear`/`/config`/`/model`/`/new`/`/skills` 仅返回描述字符串） | TUI 内运行时控制能力 | `lib/tui/slash_commands.mbt::execute` L162-186 + 调用点 | 需将 execute 改为真实执行：清空 `agent.history`、调用 `agent.switch_model_by_id`、新建会话、启用/禁用技能，**1 天** |

### 4.2 P2 — 影响用户体验（8 项，合计 ~9.5 人天）

| 编号 | 问题 | 影响范围 | 涉及文件 | 基础评估 |
|------|------|---------|---------|---------|
| **P2-01** | 缺少 `--theme` 选项（hacker/minimal 双主题） | TUI 视觉偏好 | `cmd/main.mbt`（新增 args）+ `lib/tui/theme.mbt`（扩展主题枚举）+ 源项目 `cli.rb` 已实现参考 | **0.5 天** |
| **P2-02** | 缺少 `--ui` UI 引擎选择（默认 `moonbit-community/tty`，可选 rich） | 高级终端用户偏好 | `cmd/main.mbt`（新增 args）+ `lib/tui/tui.mbt`（调度分支） | 依赖 P2-05 Rich UI 实现，**0.5 天**（不含 Rich UI 工作） |
| **P2-03** | `lib/tui/state.mbt` 中无 `session_bar`/`todo_area` 字段 | TUI 信息丰富度 | `lib/tui/state.mbt`（扩字段）+ `lib/tui/components/session_bar.mbt`（新建）+ `lib/tui/components/todo_area.mbt`（新建）+ `lib/tui/tui.mbt::build_main_layout`（集成） | **2 天**（两个新组件） |
| **P2-04** | TUI 缺少 Client Factory 模式 + BrowserManager 清理 | 长时间运行稳定性、退出残留 | `cmd/main.mbt::run_agent`（重构 Client 构造）+ `cmd/main.mbt::run_non_interactive`（增加 `ensure` 块调用 `@server.BrowserManager::instance.stop()`） | **0.5 天** |
| **P2-05** | Rich UI 第二套实现完全缺失（`rich_ui/` 14 个文件） | 高级终端用户 | 新建 `lib/tui/rich/` 子目录（参考源项目） | **5-8 天**（可选，影响等级中等） |
| **P2-06** | Markdown 渲染待增强（表格、任务列表、GFM） | TUI 内 Markdown 美观度 | `lib/tui/markdown.mbt`（扩展语法支持） | 当前仅基础标题/代码块渲染，**1 天** |
| **P2-07** | TUI 主题系统仅暗色（无 light/dark 切换和系统偏好检测） | 用户偏好 | `lib/tui/theme.mbt`（扩展检测逻辑）+ `lib/tui/state.mbt`（新增 theme_mode 字段） | **1.5 天** |
| **P2-08** | Ctrl+C 在 TUI 模式仅退出（应优先尝试中断 Agent） | 用户体验 | `lib/tui/tui.mbt::handle_global_event` L160-162（已有 Ctrl+C 处理）+ `lib/tui/state.mbt` 扩展中断信号状态 | 当前仅简单退出 flag，**0.5 天** |

### 4.3 不在 CLI 范围内的相关缺失（仅供背景了解）

| 编号 | 问题 | 影响范围 | 备注 |
|------|------|---------|------|
| **X-1** | Web 前端功能差距（5.3 倍代码量） | Web UI 用户 | 不在 CLI 评审范围内，仅记录 |
| **X-2** | 部署基础设施（Docker/安装脚本） | 终端用户安装 | 不在 CLI 评审范围内 |
| **X-3** | IM 适配器深度 | IM 用户 | 不在 CLI 评审范围内 |

---

## 5. 分项解决方案与精确工时

### 5.1 P1-01：实现 `--fork` 会话分叉（0.5-1 天）

**问题定位**：源项目支持 `clacky agent --fork <number-or-id>`，MBOpenClacky 底层 `fork_session` 已就绪，仅 CLI 入口未接入。

**实施步骤**：

1. **注册参数**（`cmd/main.mbt` L36-65 args dict 中）
   ```moonbit
   "fork": @clap.Arg::named(
     nargs=@clap.Nargs::AtMost(1),
     help="Fork a session by number or session ID prefix",
   ),
   ```

2. **修改 `resolve_session`**（L378-411）增加 `fork_id` 参数：
   - 调用 `@agent.fork_session(fork_id)` 获取新 SessionData
   - 复用现有 restore 流程（L348-359）

3. **提取会话编号**：源项目支持 `-a 2` 这种数字编号，MBOpenClacky 需在 `resolve_session` 中实现"按数字 N 列出第 N 个会话"的索引逻辑（参考 `lib/agent/session_store.mbt::list_sessions` 已返回 Array[SessionData]）

**验证**：
- `moon check --target native` 0 errors
- `moon test` 现有套件通过
- 手动验证：`mbopenclacky --fork <existing_session_id>` 启动后 `--list` 可见新 ID 且 `forked_from` 字段已填

### 5.2 P1-02：实现 `--file/-f` 与 `--image/-i`（1.5 天）

**实施步骤**：

1. **注册两个参数**：
   ```moonbit
   "file": @clap.Arg::named(
     short='f', nargs=@clap.Nargs::AtLeast(1),  // Array
     help="File path(s) to attach (use with -m)",
   ),
   "image": @clap.Arg::named(
     short='i', nargs=@clap.Nargs::AtLeast(1),
     help="Image file path(s) to attach (alias for --file)",
   ),
   ```

2. **修改 `get_named_arg` 工具函数**：当前仅返回首元素（L204-209），需新增 `get_named_args(value, name) -> Array[String]` 返回全部值。

3. **扩展 `run_non_interactive` 签名**：增加 `file_paths : Array[String]` 参数，在构造 Agent 消息前：
   - 读取每个文件 → 判定 MIME
   - 图片：base64 内联为 ImageBlock（参考 `lib/message/` 中 ImageBlock 类型）
   - 文档：调用 `lib/parser/` 对应解析器，提取文本
   - 拼接为多 Block 消息送入 `agent.run`

4. **新增文件类型判定模块** `cmd/file_attach.mbt`（建议），独立可测试

**验证**：
- 用一张 PNG 图片 `mbopenclacky -m "描述这张图" -i test.png`，确认消息携带图片块
- 用 PDF `mbopenclacky -m "总结该 PDF" -f doc.pdf`，确认文本提取成功

### 5.3 P1-03：实现 NDJSON 交互模式 `--json`（2 天）

**当前状态**：`cmd/ndjson_logger.mbt`（1.5KB）仅作为后端日志输出器；源项目 `--json` 是 stdout 上的实时 NDJSON 事件流。

**实施步骤**：

1. **重构 `NdjsonLogger`** 扩展接口：
   ```moonbit
   pub struct NdjsonLogger {
     enabled : Bool
     stream : Bool  // 新增：true 表示流到 stdout
   }
   
   pub fn emit_event(self : NdjsonLogger, event : @agent.HookEvent) -> Unit  // 新增
   pub fn emit_message(self : NdjsonLogger, msg : Message) -> Unit
   pub fn emit_iteration(self : NdjsonLogger, n : Int) -> Unit
   pub fn emit_tool_call(self : NdjsonLogger, name : String, args : String) -> Unit
   pub fn emit_done(self : NdjsonLogger, result : RunResult) -> Unit
   ```

2. **注册 `--json` 参数**：与 `--ndjson` 区分（前者交互模式，后者日志模式）

3. **修改 `run_agent`**（L362-368）：当 `--json` 启用时，跳过 TUI 分支，进入新的 `run_json_streaming(agent, logger)` 路径，订阅 Agent HookEvent 持续输出 NDJSON 行

4. **保持 stdin/stdout 纯净**：确保 stderr 继续承载人类可读错误，stdout 严格 NDJSON

**验证**：
- `mbopenclacky --json -m "hi"` 输出至少包含 `{"event":"iteration","n":1}`、`{"event":"tool_call",...}`、`{"event":"done","status":"success"}` 等行
- `mbopenclacky --json -m "hi" | jq '.event'` 正常工作

### 5.4 P1-04：补完 Sibling Server 发现（1.5 天）

**实施步骤**：

1. **实现 `find_all_local`**（`lib/server/discover.mbt:37`）：
   - 调用 `opendir(pid_file_dir)` 扫描所有 `mbopenclacky-master-*.pid` 文件
   - 对每个文件：`open` 读取 PID、`kill(pid, 0)` 检测存活
   - 解析端口号（已有 `extract_port_from_filename`）
   - 返回排序的 `Array[ServerInstance]`

2. **实现 `write_pid_file`/`remove_pid_file`**：
   - 替换 `TODO: FFI` 为真实的 `open/write/close` 与 `unlink`

3. **实现 `is_process_alive`**：
   - POSIX：`kill(pid, 0)` 返回 0 表示存活
   - Windows：`OpenProcess + GetExitCodeProcess` 或 `WaitForSingleObject(handle, 0)`

4. **在 `handle_server`**（`cmd/main.mbt:174-201`）启动成功后调用 `write_pid_file(4000, getpid())`；在 `Server stopped.` 之前调用 `remove_pid_file(4000)`

5. **在 `run_agent` 入口处** 调用 `discover_sibling_server!()`（仿源项目 `cli.rb:188-204`），若发现本地服务器则设置 `MBOPENCLACKY_SERVER_HOST`/`MBOPENCLACKY_SERVER_PORT` 环境变量

**验证**：
- 启动 `mbopenclacky server`，等待 2 秒后另开终端 `mbopenclacky -m "hi"`，确认日志中输出"Discovered local server PID=... at ...:4000"
- 杀掉服务器进程后再运行 CLI，确认日志中无该提示

### 5.5 P1-05：工作目录切换与恢复（0.5 天）

**实施步骤**：

1. **修改 `run_agent` 入口**（L274）增加切换逻辑：
   ```moonbit
   let original_dir : String = @sys.get_env_var("CD").unwrap_or(".")
   // ... 现有 working_dir 解析逻辑 ...
   if working_dir != original_dir {
     @sys.chdir(working_dir)  // MoonBit 异步版本
   }
   ```

2. **在 `run_non_interactive` 末尾（L487-498 `ensure` 等价位置）** 调用 `@sys.chdir(original_dir)` 恢复

3. **TUI 路径**：在 `tui.mbt::run_tui_interactive` 的 ensure 块中也应恢复（参考源项目 `cli.rb:169-172`）

**MoonBit 平台差异**：
- 优先调用 `@fs.chdir` 或封装为 `@utils.change_dir`
- Windows/POSIX 行为应一致

**验证**：
- 在 `/tmp` 目录运行 `mbopenclacky --path /usr/local -m "pwd"`，确认 Agent 在 /usr/local 运行且退出后 shell 仍处于 /tmp

### 5.6 P1-06：连接 Billing 子命令到 BillingStore（0.5 天）

**实施步骤**：

1. **替换 `handle_billing` 实现**（`cmd/main.mbt:148-151`）：
   ```moonbit
   fn handle_billing() -> Unit {
     let store = @billing.BillingStore::default() catch {
       err => {
         println("Error: Failed to initialize billing store: \{err}")
         @sys.exit(1)
         return
       }
     }
     let summary = store.summary(@billing.TimePeriod::AllTime) catch {
       err => {
         println("Error: Failed to query billing: \{err}")
         @sys.exit(1)
         return
       }
     }
     println("Billing Summary:")
     println("  Total Cost: $\{summary.total_cost_usd}")
     println("  Total Tokens: \{summary.total_input_tokens + summary.total_output_tokens}")
     println("  Total Requests: \{summary.total_requests}")
     // ... 遍历 ModelSummary、DaySummary 等
   }
   ```

2. **增加 TimePeriod 选择**：可通过 `--period today|week|month|all` 参数细化（可选）

3. **导出 `@billing` 模块**：确认 `cmd/moon.pkg` 已导入 `lib/billing`，或新增导入

**验证**：
- `moon check --target native` 0 errors
- `mbopenclacky billing` 输出格式化的计费汇总

### 5.7 P1-07：激活 TUI 斜杠命令实际执行（1 天）

**实施步骤**：

1. **修改 `slash_commands.mbt::execute`** 接收 `agent : @agent.Agent` 参数（原签名仅接 `cmd: SlashCommand`）：
   ```moonbit
   pub fn execute(cmd : SlashCommand, agent : @agent.Agent) -> Result[String, String] {
     match cmd {
       Clear => {
         agent.clear_history()  // 需在 lib/agent/agent.mbt 新增
         Ok("Message history cleared")
       }
       Model(name~) => {
         match agent.switch_model_by_name(name) {
           true => Ok("Model switched to: \{name}")
           false => Err("Model not found: \{name}")
         }
       }
       Config(key~, value~) => {
         agent.config.set_dynamic_value(key, value)  // 需新增
         Ok("Configuration set: \{key} = \{value}")
       }
       New(title~) => {
         // 保存当前 session，启动新会话
         // ... 与 /fork 类似逻辑，但 name = title 不带 "(copy)"
         Ok("New session created: \{title}")
       }
       Skills(action~) => {
         match action {
           "list" => Ok(format_skills_list(agent))
           "enable" | "disable" => agent.toggle_skill(action)  // 需新增
           _ => Err(...)
         }
       }
       // Help/Exit 不变
     }
   }
   ```

2. **新增 Agent 接口**：
   - `@agent.Agent::clear_history()`
   - `@agent.Agent::switch_model_by_name(name : String) -> Bool`（已有 `switch_model_by_id`，新增 name 版）
   - `@agent.Agent::config.set_dynamic_value(key, value)`

3. **修改 TUI 输入回调**（`lib/tui/tui.mbt::submit_input`）解析 SlashCommand 后调用真实 execute

**验证**：
- 在 TUI 中输入 `/clear` 后消息历史清空
- 输入 `/model gpt-4o` 后底部状态栏更新模型名
- 输入 `/new 实验` 后开始新会话且原会话已保存

### 5.8 P2-01：实现 `--theme` 选项（0.5 天）

**实施步骤**：

1. **注册参数**：`"theme": @clap.Arg::named(nargs=@clap.Nargs::Fixed(1), choices=HashSet::from_array(["hacker", "minimal"]), defaults=["hacker"])`

2. **扩展 `lib/tui/theme.mbt`**：将 `Theme` enum 改为 `Hacker`/`Minimal` 两个变体，当前实现已可复用

3. **在 `run_agent` 创建 TUI 前** 将 theme 传入 `run_tui_interactive(agent, theme~)`

**验证**：两种主题下 TUI 渲染符号与配色明显不同

### 5.9 P2-02：实现 `--ui` 选项（0.5 天，不含 Rich UI）

**实施步骤**：

1. **注册参数**：`"ui": @clap.Arg::named(nargs=@clap.Nargs::Fixed(1), defaults=["tui"], choices=...)`

2. **TUI 入口分支**：`if ui == "tui" { run_tui_interactive(...) } else if ui == "rich" { run_rich_tui_interactive(...) }`

**注意**：本项需 P2-05 Rich UI 实现后才能完整生效；可先注册参数 + 占位分支

### 5.10 P2-03：新增 Session Bar 与 Todo Area 组件（2 天）

**实施步骤**：

1. **扩展 `lib/tui/state.mbt::TuiState`**（L32-96）增加：
   ```moonbit
   mut working_dir : String
   mut current_permission_mode : String
   mut todo_items : Array[TodoItem]  // 新结构体 {id, content, status: Pending|InProgress|Done}
   mut todo_area_visible : Bool
   ```

2. **创建 `lib/tui/components/session_bar.mbt`**：
   - `pub fn session_bar_render(state : Ref[TuiState]) -> @view.View`
   - 显示格式：`{session_id_short} | {working_dir} | {model} | ${cost} | {mode}`

3. **创建 `lib/tui/components/todo_area.mbt`**：
   - `pub fn todo_area_render(state : Ref[TuiState]) -> @view.View`
   - 根据 `todo_area_visible` 决定是否渲染

4. **修改 `lib/tui/tui.mbt::build_main_layout`**（L56-139）集成两者：
   - 在状态栏（status_bar）下方插入 session_bar
   - 在主内容区上方插入 todo_area（受可见性控制）

5. **Todo 数据来源**：监听 `@agent.TodoChanged` HookEvent（需确认 HookEvent 是否需要扩展；当前 10 个变体未含，可加入或通过 `@agent.Agent::get_todo_items()` 主动拉取）

### 5.11 P2-04：Client Factory 重构与 BrowserManager 清理（0.5 天）

**实施步骤**：

1. **重构 Client 构造**（`cmd/main.mbt:252-272`）：
   ```moonbit
   let client_factory : () -> @client.Client = fn() {
     let mc = config.current_model().unwrap()
     let api_type = if mc.anthropic_format { ... } else { ... }
     @client.Client::new(mc.api_key, mc.base_url, mc.model, api_type)
   }
   // 之后每次需要 Client 时调用 client_factory()，避免持有过期引用
   ```

2. **BrowserManager 清理**：在 `run_non_interactive` 末尾（`@sys.exit` 之前）调用 `@server.BrowserManager::stop()` rescue；TUI 模式同样在 ensure 块处理

### 5.12 P2-05：Rich UI 实现（5-8 天，可选）

源项目 `rich_ui/` 14 个文件基于 `ruby_rich` 库，主要差异在于颜色渲染、ASCII art 与动画效果。如需在 MBOpenClacky 中实现，建议：

- 新建 `lib/tui/rich/` 子目录
- 利用现有 `lib/tui/theme.mbt` 的颜色与符号注册表
- 复用 `progress_stack.mbt` 的动画能力
- 优先级低，仅在用户明确反馈后实施

### 5.13 P2-06：Markdown 增强渲染（1 天）

**实施步骤**：

1. **扩展 `lib/tui/markdown.mbt`**：增加 GFM 表格（`| col1 | col2 |`）、任务列表（`- [ ]` / `- [x]`）、删除线（`~~text~~`）、链接 `[text](url)` 渲染
2. **新增对应测试** `lib/tui/tui_markdown_wbtest.mbt`
3. **集成到 `message_view.mbt`**（L1-35）的渲染管线

### 5.14 P2-07：主题系统 light/dark（1.5 天）

**实施步骤**：

1. **扩展 `lib/tui/theme.mbt::Theme`**：`{mode : LightOrDark, style : HackerOrMinimal}`
2. **新增 `detect_system_preference()` 函数**：Windows 调用 `GetSystemMetrics(SPI_GETHIGHCONTRAST)` 或读取注册表；POSIX 读取 `~/.config/gtk-3.0/settings.ini` 的 `gtk-application-prefer-dark-theme`
3. **在 `run_tui_interactive` 入口处** 初始化 theme，根据检测结果设置

### 5.15 P2-08：TUI 模式 Ctrl+C 优雅中断（0.5 天）

**实施步骤**：

1. **修改 `lib/tui/tui.mbt::handle_global_event`** L160-162：
   - 当前为 `should_quit.val = true` 直接退出
   - 改为：`if state.val.mode == Running { agent.interrupt() } else { should_quit.val = true }`
2. **新增 `@agent.Agent::interrupt()` 方法**：发送中断信号或抛出 AgentInterrupted 异常
3. **处理异常捕获**：在 `submit_input` 的 try-catch 中（tui.mbt:205-213）扩展对 Interrupted 的处理

---

## 6. 优先级排序与实施路线

### 6.1 总工时汇总

| 类别 | 项数 | 工时 |
|------|------|------|
| P1 全部 | 7 项 | **6.5 人天** |
| P2 全部（不含 Rich UI） | 7 项 | **6.5 人天** |
| P2 含 Rich UI | 8 项 | **11.5-14.5 人天** |
| **总计（不含 Rich UI）** | 14 项 | **~13 人天** |
| **总计（含 Rich UI）** | 15 项 | **~18-21 人天** |

### 6.2 建议实施顺序

```
第 1 周（P1 高 ROI 快速见效，~3.5 天）：
  P1-06 Billing 连接（0.5d）→ P1-05 工作目录切换（0.5d）→
  P1-01 --fork 接入（0.5-1d）→ P1-04 Sibling Server 发现（1.5d）

第 2 周（P1 核心交互，~3 天）：
  P1-02 --file/--image 附件（1.5d）→ P1-07 TUI 斜杠命令生效（1d）→
  P1-03 NDJSON 交互模式（2d，可与下项并行一部分）

第 3 周（P2 体验优化，~6.5 天）：
  P2-01 --theme（0.5d）→ P2-04 Client Factory + 清理（0.5d）→
  P2-08 Ctrl+C 优雅中断（0.5d）→ P2-06 Markdown 增强（1d）→
  P2-03 Session Bar / Todo Area（2d）→ P2-07 主题系统（1.5d）→
  P2-02 --ui 选项（0.5d，不含 Rich UI）

第 4-5 周（可选）：
  P2-05 Rich UI 实现（5-8d，视用户反馈决定）
```

### 6.3 关键路径与依赖关系

```
P1-06 Billing ──→ 无依赖 ──→ 0.5d 完成
P1-05 工作目录 ──→ 无依赖 ──→ 0.5d 完成
P1-01 --fork ──→ 依赖 fork_session 已存在 ──→ 0.5-1d 完成
P1-04 Sibling Server ──→ 依赖 FFI (opendir/kill) ──→ 1.5d 完成
P1-02 --file ──→ 依赖 lib/parser + lib/message 已存在 ──→ 1.5d 完成
P1-07 斜杠命令 ──→ 依赖 lib/agent 新增 clear/switch 接口 ──→ 1d 完成
P1-03 NDJSON ──→ 依赖 hook 事件已就绪 ──→ 2d 完成

P2 全部 ──→ 依赖 P1 完成 ──→ 6.5d 完成
P2-05 Rich UI ──→ 独立分支，可与 P2 其他项并行 ──→ 5-8d
```

### 6.4 里程碑

| 里程碑 | 完成标准 | 累计工时 |
|--------|---------|---------|
| **M1：CLI 基础对齐** | P1-01/05/06 完成；`--fork`/工作目录/Billing 子命令可用 | ~2 天 |
| **M2：CLI 高级功能** | P1-02/03/04/07 完成；文件附件、NDJSON 流、Sibling 发现、斜杠命令生效 | ~7 天 |
| **M3：TUI 体验优化** | P2 全部完成；主题/UI/Markdown/Session Bar/Ctrl+C 等 | ~13 天 |
| **M4：Rich UI 可选** | 5-8 天追加 | ~18-21 天 |

---

## 7. 附录：代码锚点索引

> 便于定位每项修复的具体代码位置。

| 编号 | 涉及模块 | 关键行号 |
|------|---------|---------|
| **P1-01** | `cmd/main.mbt` | L36-65（args 注册）、L378-411（resolve_session） |
| P1-01 依赖 | `lib/agent/session_manager.mbt` | L136-179（fork_session） |
| **P1-02** | `cmd/main.mbt` | L36-65、L204-209、L432-499 |
| P1-02 依赖 | `lib/message/` | ImageBlock 类型 |
| P1-02 依赖 | `lib/parser/` | PDF/DOCX/PPTX/XLSX 解析器 |
| **P1-03** | `cmd/main.mbt` | L362-368（运行分支） |
| P1-03 核心 | `cmd/ndjson_logger.mbt` | 整文件（重构） |
| **P1-04** | `lib/server/discover.mbt` | L37-49、L52-68、L93-97 |
| P1-04 触发 | `cmd/main.mbt::handle_server` | L174-201 |
| **P1-05** | `cmd/main.mbt::run_agent` | L274-290、L487-498 |
| P1-05 触发 | `lib/tui/tui.mbt::run_tui_interactive` | L19-52 |
| **P1-06** | `cmd/main.mbt::handle_billing` | L148-151 |
| P1-06 依赖 | `lib/billing/billing_store.mbt` | 整文件（已完整） |
| **P1-07** | `lib/tui/slash_commands.mbt::execute` | L162-186 |
| P1-07 触发 | `lib/tui/tui.mbt::submit_input` | L189-221 |
| P1-07 依赖 | `lib/agent/agent.mbt` | 需新增 `clear_history`、`switch_model_by_name` |
| **P2-01** | `cmd/main.mbt` | L36-65 |
| P2-01 依赖 | `lib/tui/theme.mbt` | 扩展 Theme enum |
| **P2-02** | `cmd/main.mbt` | L362-368 |
| **P2-03** | `lib/tui/state.mbt` | L32-96（扩字段） |
| P2-03 新建 | `lib/tui/components/session_bar.mbt` | 全新 |
| P2-03 新建 | `lib/tui/components/todo_area.mbt` | 全新 |
| P2-03 集成 | `lib/tui/tui.mbt::build_main_layout` | L56-139 |
| **P2-04** | `cmd/main.mbt::run_agent` | L252-272 |
| P2-04 触发 | `cmd/main.mbt::run_non_interactive` | L487-498 |
| P2-04 依赖 | `lib/server/browser_manager.mbt` | stop() 方法 |
| **P2-05** | `lib/tui/rich/`（新建） | 14 文件 |
| **P2-06** | `lib/tui/markdown.mbt` | 整文件（扩语法） |
| P2-06 集成 | `lib/tui/message_view.mbt` | 渲染管线 |
| **P2-07** | `lib/tui/theme.mbt` | Theme enum 扩展 |
| P2-07 触发 | `lib/tui/tui.mbt::run_tui_interactive` | L19-52 |
| **P2-08** | `lib/tui/tui.mbt::handle_global_event` | L160-162 |
| P2-08 依赖 | `lib/agent/agent.mbt` | 新增 `interrupt()` 方法 |

---

## 总结

**前次报告的核心修正**：

1. **CLI 选项总数从 10 修正为 16** + 2 子命令
2. **HookEvent 翻译 6/25 修正为 10/10（已完成）**
3. **`/config`/`/clear` 斜杠命令从"完全缺失"修正为"已实现但未生效"**
4. **Billing 子命令从"底层未实现"修正为"底层完整，仅上层未连接"**
5. **Sibling Server 发现从"完全缺失"修正为"框架已建，FFI 未完成"**

**修正后的整体评估**：

- CLI 核心可用性 **无 P0 阻碍**
- P1 级 7 项共 **~6.5 人天**
- P2 级 7 项共 **~6.5 人天**（不含 Rich UI）
- **总计 ~13 人天（约 2.5 周）** 可实现 CLI 层面与源项目的功能对齐
- 加上 Rich UI 可选增强 **5-8 天**，总计 **~18-21 人天**

---

**文档版本**: 1.0  
**最后更新**: 2026-06-29  
**作者**: 基于代码库深度审计  
**状态**: 权威评审文档，供后续迭代决策参考