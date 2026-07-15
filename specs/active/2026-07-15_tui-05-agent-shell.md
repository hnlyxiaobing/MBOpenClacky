# TUI-05: Agent Shell（多面板模式切换）· 增量 Spec

> **创建日期**: 2026-07-15
> **状态**: 开发中
> **关联总览**: `specs/active/2026-07-15_tui-overhaul-master-plan.md`
> **来源差距**: G12 - TUI Rich Agent Shell（高级交互模式）
> **依赖**: TUI-01（异步事件循环 + 模式切换需 agent 运行时响应）、TUI-02（Node 渲染 + Msg 驱动）
> **替代**: `specs/deprecated/2026-07-13_12_tui-agent-shell.md`（G12）

## 问题描述 [必填]

原项目 `rich_ui/shell/rich_agent_shell` 提供多面板布局（聊天区 + 文件浏览 + 状态栏）、上下文感知命令建议。当前 TUI 使用单面板 Inline Scrolling，缺少：
1. **模式切换**：默认聊天模式，Tab 切换到文件浏览/配置模式
2. **文件浏览面板**：显示工作目录文件树，支持导航和预览
3. **上下文感知命令建议**：根据当前会话状态动态调整

G12 spec 提出在现有阻塞架构上增加"模式切换"，但阻塞的事件循环无法在 agent 运行时响应 Tab 键。TUI-01 的异步事件循环解决了此问题。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| `input_area.mbt` 无 Tab 键处理 | `grep -i "tab\|Tab\|autocomplete" lib/tui/input_area.mbt lib/tui/tui_controller.mbt` | 0 命中（Tab 键无冲突） | 确认可用于模式切换 |
| 无 `shell_mode` 字段 | `grep "shell_mode\|ShellMode" lib/tui/state.mbt` | 0 命中 | 确认需新增 |
| 无文件浏览面板 | `grep -r "file_browser\|FileBrowser\|file_tree" lib/tui/*.mbt` | 0 命中 | 确认缺失 |
| `@fs` 包已在项目使用 | `grep -r "@fs\b" lib/ cmd/ --include="*.mbt" | head -5` | 多处使用 | 确认可用 |
| `slash_commands.mbt` 有命令建议 | `grep "pub.*fn\|struct\|enum" lib/tui/slash_commands.mbt` | `SlashCommandParser` + `execute` | 确认已有基础 |
| `command_suggestions.mbt` 存在 | `grep "pub.*fn\|struct" lib/tui/command_suggestions.mbt` | 命令建议组件 | 确认可扩展 |
| `TuiMode` 枚举仅 Idle/Running | `grep "enum TuiMode" lib/tui/state.mbt` | `Idle` + `Running` | 确认需扩展或新增 ShellMode |

### 详细分析

**模式切换设计**：

G12 spec 提出"不重写 Inline Scrolling 架构，增加模式切换能力"。在 TUI-01 异步事件循环基础上，模式切换通过 `TuiMsg::SwitchMode(ShellMode)` 实现：

```
Tab 键 -> TuiMsg::SwitchMode(FileBrowser) -> update() -> state.shell_mode = FileBrowser
  -> full_redraw() 切换到文件浏览面板全屏
Tab 键 -> TuiMsg::SwitchMode(Chat) -> update() -> state.shell_mode = Chat
  -> full_redraw() 切换回聊天面板
```

**文件系统访问**：TUI 目前不直接访问文件系统（文件操作通过 agent 工具层）。文件浏览面板需新增直接文件系统读取能力（`@fs` 包，已在项目其他模块使用）。

## 决策 [必填 - 含为什么]

### 决策 1：Tab 键模式切换（非传统多面板并排）

**为什么**：传统多面板并排渲染（聊天区 + 侧边栏 + 状态栏同时显示）在窄终端下可读性差，且与现有 Inline Scrolling 架构不兼容。采用"模式切换全屏替换"：Tab 切换时 full_redraw 到新面板，保持简单。这与 G12 spec 的决策一致，但 G12 在阻塞架构下无法实现（Tab 在 agent 运行时不响应）。TUI-01 解决后此方案可行。

### 决策 2：`ShellMode` 枚举独立于 `TuiMode`

**为什么**：`TuiMode`（Idle/Running）描述 agent 执行状态，`ShellMode`（Chat/FileBrowser/Config）描述 UI 面板状态。两者正交：agent 运行时仍可切换到文件浏览面板查看文件。

```moonbit
pub enum ShellMode {
  Chat          // 默认聊天模式
  FileBrowser   // 文件浏览模式
  Config        // 配置模式（依赖 TUI-03 Config Menu Dialog）
}
```

### 决策 3：文件浏览面板使用 `@fs` 直接读取（非 agent 工具层）

**为什么**：文件浏览是 UI 交互（实时导航），不应通过 agent 的工具调用流程（异步、需确认）。直接使用 `@fs.read_dir()` / `@fs.read_file()` 在 `spawn_bg` 中异步执行，结果 push 到 Queue。

### 决策 4：上下文感知命令建议基于会话状态

**为什么**：`slash_commands.mbt` 的建议列表当前为静态。根据 `state.tool_history`（最近执行的工具）、`state.working_dir`（当前目录）、`state.agent_status`（agent 状态）动态调整建议优先级。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/shell_mode.mbt` | **新建** | `ShellMode` 枚举 + 模式切换逻辑 |
| `lib/tui/file_browser.mbt` | **新建** | 文件浏览面板：文件树渲染 + 导航 + 预览 |
| `lib/tui/file_browser_wbtest.mbt` | **新建** | 单元测试 |
| `lib/tui/state.mbt` | **修改** | 新增 `shell_mode : ShellMode`（mut，默认 Chat） |
| `lib/tui/msg.mbt` | **修改** | 新增 `SwitchMode(ShellMode)` Msg + update 逻辑 |
| `lib/tui/tui_controller.mbt` | **修改** | Tab 键生成 `SwitchMode`；根据 `shell_mode` 选择渲染路径；文件浏览面板的导航键处理 |
| `lib/tui/slash_commands.mbt` | **修改** | 上下文感知建议：根据 `tool_history`、`working_dir`、`agent_status` 调整建议列表 |
| `lib/tui/command_suggestions.mbt` | **修改** | 建议列表动态化 |
| `lib/tui/moon.pkg` | **修改** | 新增 `@fs` 依赖（如未已有） |

### 不涉及文件

- `lib/agent/`（文件浏览是 UI 层操作，不走 agent 工具层）
- `lib/web/`、`cmd`（TUI 独有功能）

## 实施计划 [必填]

### 任务包 1：ShellMode + 模式切换（预估 1 天）

1. 新建 `shell_mode.mbt`：
   - `ShellMode` 枚举（Chat / FileBrowser / Config）
   - `fn switch_mode(state, mode) -> TuiCmd`：更新 `shell_mode`，返回 `Redraw`
2. 修改 `state.mbt`：新增 `mut shell_mode : ShellMode`（默认 Chat）
3. 修改 `msg.mbt`：`SwitchMode(ShellMode)` 的 update 逻辑
4. 修改 `tui_controller.mbt`：
   - Tab 键：`SwitchMode(FileBrowser)` / `SwitchMode(Chat)` 循环切换
   - 渲染路径：`match state.shell_mode { Chat => render_chat(); FileBrowser => render_file_browser(); Config => render_config() }`
   - Ctrl+Tab 或 Shift+Tab：反向切换

### 任务包 2：文件浏览面板（预估 1.5 天）

1. 新建 `file_browser.mbt`：
   - `FileBrowser` struct：`current_path`、`entries : Array[DirEntry]`、`selected_idx`、`scroll_offset`
   - `DirEntry { name, is_dir, size }`
   - `fn render_file_browser(browser) -> Node`：
     - Border("Files") + Column(文件列表，目录高亮，选中项反色)
     - 底部显示选中文件预览（前 3 行文本）
   - 导航键：
     - 上下箭头：移动 `selected_idx`（含滚动）
     - Enter：目录则进入，文件则预览
     - Backspace/Left：返回上级目录
     - Esc：返回聊天模式
2. 文件系统读取（`spawn_bg`）：
   - `async fn load_dir(path) -> Array[DirEntry]`：`@fs.read_dir(path)` + 过滤 + 排序
   - `async fn preview_file(path) -> String`：`@fs.read_file_to_string(path)`，截断前 500 字符
   - 结果 push `FileListLoaded(entries)` / `FilePreviewLoaded(content)` 到 Queue
3. 修改 `tui_controller.mbt`：文件浏览模式下的按键处理

### 任务包 3：上下文感知命令建议（预估 1 天）

1. 修改 `slash_commands.mbt`：
   - 新增 `fn context_aware_suggestions(state) -> Array[String]`
   - 规则：
     - `agent_status == "error"` -> 优先 `/retry`、`/clear`
     - `tool_history` 最后执行了 `write_file` -> 优先 `/diff`、`/undo`
     - `working_dir` 是 git 仓库 -> 优先 `/git-status`
     - 默认 -> `/help`、`/todo`、`/clear`
2. 修改 `command_suggestions.mbt`：调用 `context_aware_suggestions` 替代静态列表
3. 修改 `tui_controller.mbt`：输入 `/` 时渲染动态建议列表

### 任务包 4：配置模式（预估 0.5 天）

1. 配置模式复用 TUI-03 的 Config Menu Dialog
2. 显示可配置项：模型选择、权限模式、verbose 开关
3. 选择后更新 agent config（`agent.config`）

### 任务包 5：测试与回归（预估 0.5 天）

1. 新建 `file_browser_wbtest.mbt`
2. TUI eval 场景：模式切换、文件浏览、命令建议
3. `moon check` + `moon test`

## 验收标准 [必填]

- [ ] Tab 键在 Chat / FileBrowser 模式间切换
- [ ] 文件浏览面板显示工作目录文件树（目录 + 文件）
- [ ] 上下箭头导航文件列表，Enter 进入目录/预览文件
- [ ] Backspace 返回上级目录，Esc 返回聊天模式
- [ ] 模式切换在 agent 运行时仍可响应（TUI-01 异步事件循环保障）
- [ ] 输入 `/` 时显示上下文感知的命令建议
- [ ] 命令建议根据 agent 状态、tool_history、working_dir 动态调整
- [ ] 大目录（> 100 条目）支持滚动，不卡顿
- [ ] `moon check` 0 errors（`lib/tui`）
- [ ] `moon test lib/tui` 通过
- [ ] TUI eval 场景通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| `@fs.read_dir` 阻塞事件循环 | 中 | 在 `spawn_bg` 中异步执行，结果 push 到 Queue；设置超时 5s |
| 大目录性能 | 低 | 限制单次渲染 50 条目，支持滚动；按文件名排序 |
| Tab 键模式切换与未来 autocomplete 冲突 | 中 | 当前无 Tab 处理（已验证）；未来 autocomplete 用 Ctrl+Space，模式切换用 Tab |
| 文件预览大文件内存 | 低 | 截断前 500 字符；仅文本文件预览，二进制文件跳过 |
| 配置模式修改 agent.config 的影响范围 | 中 | 仅修改可安全热更新的配置项（model、permission_mode）；不支持运行时修改不可逆配置 |

## 依赖关系 [必填]

- **前置依赖**：TUI-01（异步事件循环）、TUI-02（Node 渲染 + Msg 驱动）
- **可选依赖**：TUI-03（Config Menu Dialog 用于配置模式）
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-15 | 初始版本 | 替代 G12，基于 TUI-01 异步事件循环 + TUI-02 Node 渲染重新设计模式切换 |
