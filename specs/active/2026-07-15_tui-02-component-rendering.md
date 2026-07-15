# TUI-02: 组件化渲染系统 · 增量 Spec

> **创建日期**: 2026-07-15
> **状态**: 开发中
> **关联总览**: `specs/active/2026-07-15_tui-overhaul-master-plan.md`
> **来源差距**: 架构级 - 无组件系统，渲染逻辑硬编码 ANSI 拼接
> **依赖**: TUI-01（需要异步事件循环提供 Msg 驱动基础）
> **后置**: TUI-03（Rich Dialogs）依赖本 spec 的 Node 渲染系统

## 问题描述 [必填]

当前 TUI 所有渲染函数手动拼接 ANSI 字符串：

```moonbit
// dialog.mbt - 手动拼接
let warning = "\u{1b}[33m⚠\u{1b}[0m"
let tool = "\u{1b}[1m\{pending.tool_name}\u{1b}[0m"
```

- 无法组合复用（border、padding 需每个组件重新实现）
- 样式与逻辑耦合（改颜色需改业务代码）
- Rich Dialog（TUI-03）需要大量重复的 ANSI 手工拼接
- Agent Shell（TUI-05）的多面板布局无法用硬编码实现

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 渲染函数手动拼接 ANSI | `grep "\\\\u{1b}" lib/tui/dialog.mbt` | 多处 `\u{1b}[33m`、`\u{1b}[1m`、`\u{1b}[0m` 硬编码 | 确认 |
| input_area 硬编码 border | `grep "┌\|└\|│\|─" lib/tui/tui_controller.mbt` | L181/L190/L197: 手动写 `┌─ Input ───` + 循环写 `─` | 确认硬编码 |
| layout_manager 硬编码布局 | `grep "input_h\|status_h\|msg_top" lib/tui/layout_manager.mbt` | 固定 `status_h=1`、`input_h=4`，`compute_layout` 硬计算 | 确认固定布局 |
| 无 Node/View/Widget 抽象 | `grep -r "enum.*Node\|struct.*Node\|trait.*Widget\|trait.*View" lib/tui/*.mbt` | 0 命中 | 确认无组件系统 |
| ScreenBuffer 支持基础操作 | `grep "pub.*fn.*ScreenBuffer" lib/tui/screen_buffer.mbt` | `move_cursor`、`write_string`、`clear_to_eol`、`set_foreground` 等 | 确认可作为渲染后端 |
| theme.mbt 已有颜色定义 | `grep "pub.*fn\|pub.*let\|enum\|struct" lib/tui/theme.mbt` | `Theme` struct + `default_()` | 确认可复用 |

### 详细分析

当前渲染层次：
- `ScreenBuffer`（VT100 原语）<- `LayoutManager`（固定布局）<- `TuiController`（手动调用 ScreenBuffer 方法）
- 每个区域（status/input/output/todo）独立渲染，无法组合
- 对话框（`dialog.mbt`）渲染为单行 inline 文本，无法扩展为多行框

调研报告评估了 rabbita_tui（Node/View 但组件少）和 mizchi/tui（Virtual DOM 但 168 文件重依赖）。两者均过重或不足。需要一个**轻量级** Node 系统，满足：
1. 可组合（Column/Row/Border/Padding 嵌套）
2. 样式分离（Style 结构体，不硬编码 ANSI）
3. 足够简单（< 200 行实现），不引入外部依赖

## 决策 [必填 - 含为什么]

### 决策 1：轻量级 Node 枚举（非 Virtual DOM）

**为什么**：Virtual DOM（mizchi/tui 的 diff 渲染）需要 prev_buffer 对比、patch 生成等复杂逻辑（168 文件）。当前 TUI 已有 OutputBuffer 的 version tracking 做增量，不需要 diff 渲染。一个简单的 `Node` 枚举 + `render_node()` 递归函数即可满足组合需求。

**设计**：
```moonbit
pub enum Node {
  Text(String, Style)           // 带样式的文本
  Column(Array[Node])           // 垂直排列
  Row(Array[Node])              // 水平排列
  Border(String, Array[Node])   // 带标题的边框
  Padding(Int, Int, Node)       // 上下/左右内边距
  Styled(Style, Node)           // 样式包裹
}

pub struct Style {
  fg : Color?
  bg : Color?
  bold : Bool
  dim : Bool
}

pub fn render_node(
  screen : ScreenBuffer,
  node : Node,
  row : Int,    // 起始行
  col : Int,    // 起始列
  width : Int,  // 可用宽度
) -> Int       // 返回消耗的行数
```

### 决策 2：Msg 枚举驱动用户交互

**为什么**：借鉴 Elm 架构的 Msg 模式（不引入 rabbita_tui 包）。当前 `handle_key()` 用 match 分发按键，随着 Rich Dialogs 和 Agent Shell 增加交互，分支会爆炸。引入 Msg 枚举将"按键事件"转为"语义消息"，`update(state, msg)` 统一处理状态变更。

**设计**：
```moonbit
pub enum TuiMsg {
  // 输入
  KeyChar(Char)
  KeyEnter
  KeyBackspace
  KeyArrow(Direction)
  KeyCtrl(Char)         // Ctrl+C, Ctrl+L 等
  // Agent
  SubmitInput(String)
  CancelAgent
  // Dialog
  DialogApprove
  DialogDeny
  DialogToggleDetails
  DialogSelectItem(Int)
  DialogToggleItem(Int)
  DialogConfirm
  // Shell
  SwitchMode(ShellMode)
  // 系统
  Redraw
  Resize(Int, Int)
}
```

### 决策 3：保留 ScreenBuffer + LayoutManager 作为渲染后端

**为什么**：ScreenBuffer 已封装 VT100 原语（move_cursor/write_string/clear），LayoutManager 已有区域管理。Node 系统在其上层组合，不替换底层。`render_node()` 最终调用 ScreenBuffer 方法输出。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/node.mbt` | **新建** | `Node` 枚举 + `Style` 结构体 + `render_node()` 递归渲染 |
| `lib/tui/node_wbtest.mbt` | **新建** | Node 渲染单元测试（使用 VirtualScreen 验证输出） |
| `lib/tui/msg.mbt` | **新建** | `TuiMsg` 枚举 + `update(state, msg) -> Cmd` 分发函数 |
| `lib/tui/tui_controller.mbt` | **修改** | `handle_key()` 改为生成 `TuiMsg`，调用 `update()`；渲染路径使用 Node |
| `lib/tui/theme.mbt` | **修改** | 新增 `Style` 转换为 ANSI 转义码的辅助函数 |

### 不涉及文件

- `lib/tui/screen_buffer.mbt`（底层不变）
- `lib/tui/output_buffer.mbt`（输出管理不变）
- `lib/tui/layout_manager.mbt`（布局管理不变，Node 在其上层）
- `lib/agent/`（不影响 agent 模块）

## 实施计划 [必填]

### 任务包 1：Node 渲染系统（预估 1.5 天）

1. 新建 `lib/tui/node.mbt`：
   - `Style` 结构体：`fg`、`bg`、`bold`、`dim`，带 `default_()` 工厂
   - `Node` 枚举：Text、Column、Row、Border、Padding、Styled
   - `render_node(screen, node, row, col, width) -> Int`：
     - Text：应用 Style 后 write_string
     - Column：逐行渲染子节点，累加行数
     - Row：在同一行渲染子节点，累加列数（注意宽度截断）
     - Border：渲染 ┌─ title ─┐ / │ content │ / └──┘ 框架
     - Padding：偏移 row/col 后递归
     - Styled：应用 Style 后递归
2. 新建 `lib/tui/node_wbtest.mbt`：使用 `VirtualScreen`（已在 eval adapter 中）验证渲染输出

### 任务包 2：Msg 驱动交互（预估 1 天）

1. 新建 `lib/tui/msg.mbt`：
   - `TuiMsg` 枚举
   - `fn update(state : TuiState, msg : TuiMsg) -> TuiCmd`：纯函数，根据 Msg 更新 state
   - `TuiCmd` 枚举：`None`、`Redraw`、`SubmitToAgent(String)`、`CancelAgent`
2. 修改 `tui_controller.mbt`：
   - `handle_key()` 改为：解析按键 -> 生成 `TuiMsg` -> 调用 `update()` -> 根据 `TuiCmd` 执行副作用
   - 渲染路径：对话框/todo 等区域改为使用 Node 构建 + `render_node()`
3. 修改 `theme.mbt`：新增 `style_to_ansi(style : Style) -> String` 辅助函数

### 任务包 3：迁移现有渲染（预估 0.5 天）

1. `dialog.mbt`：`render_confirmation_lines` 改为构建 `Node` 树
2. `input_area.mbt`：border 渲染改为 `Node::Border`
3. `todo_area.mbt`：渲染改为 `Node::Column` + `Node::Text`

## 验收标准 [必填]

- [ ] `Node` 枚举支持 Text/Column/Row/Border/Padding/Styled 六种节点
- [ ] `render_node()` 可正确渲染嵌套 Node 树到 ScreenBuffer
- [ ] `TuiMsg` 枚举覆盖所有现有按键交互
- [ ] `update()` 函数为纯函数（不直接产生副作用，返回 TuiCmd）
- [ ] 对话框渲染使用 Node 构建（非手工 ANSI 拼接）
- [ ] 现有 wbtest 通过（`modal_lifecycle_wbtest`、`todo_area_wbtest` 等）
- [ ] `moon check` 0 errors（`lib/tui`）
- [ ] TUI eval 场景通过（`cmd.exe --tui-eval test/scenarios/tui/`）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| Node 渲染性能（递归 + 多次 ScreenBuffer 调用） | 低 | Node 树通常 < 20 节点，递归深度 < 5；ScreenBuffer 已有缓冲 |
| Row 节点的宽度计算复杂（CJK 宽度） | 中 | 复用现有 `cjk_width.mbt` 的 `display_width()` 函数 |
| Msg 枚举与 TUI-01 的 TuiEvent 关系混淆 | 中 | TuiEvent 是异步事件（Queue 传递），TuiMsg 是同步语义消息（update 处理）；TuiEvent::Terminal(input) 转换为 TuiMsg 后调用 update() |
| 迁移现有渲染引入回归 | 中 | 分批迁移，每迁移一个区域跑一次 eval 场景 |

## 依赖关系 [必填]

- **前置依赖**：TUI-01（需要异步事件循环；Msg 由 TuiEvent::Terminal 转换而来）
- **后置依赖**：TUI-03（Rich Dialogs 使用 Node + Msg 构建）、TUI-05（Agent Shell 使用 Node 构建面板）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-15 | 初始版本 | Master Plan 组件化渲染 spec |
