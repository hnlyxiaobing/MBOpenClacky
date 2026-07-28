# TUI 响应式状态迁移 · 增量 Spec

> **创建日期**: 2026-07-28  
> **状态**: 已完成  
> **关联总览**: `docs/tui-redesign-goal.md`（Phase 2 状态与主题系统升级）  
> **关联历史 spec**: 无  
> **来源差距**: 验收审计 — "state.mbt 未改为 @signals.Signal 驱动"  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

TUI 重构任务书 Phase 2 要求将 `state.mbt` 改为 `mizchi/signals` 的 `Signal[T]` 驱动。实际交付中 `state.mbt`（380 行）原样未动，`mizchi/signals` 未加入 `moon.mod` 直接依赖。

当前状态管理采用手动失效模式：修改字段 → `self.dirty = true` → `self.redraw()`。`tui_controller.mbt` 中有 **59 处** `self.dirty = true` 和 **14 处** `self.redraw()` 调用。遗漏任何一处都会导致渲染滞后（stale frame），且无法通过编译器检查发现。

**影响**：功能上无 bug（3196 测试全过），但维护成本高、易引入回归。属于代码质量债务，非功能缺陷。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "state.mbt 未使用 signals" | `grep "Signal\|signal" lib/tui/state.mbt` | 0 命中 | 确认：纯 `mut` 字段结构体 |
| "mizchi/signals 未在 moon.mod" | `grep "signals" moon.mod` | 0 命中 | 确认：非直接依赖 |
| "mizchi/signals 已作为传递依赖存在" | `grep "signals" .mooncakes/mizchi/tui/moon.mod` | 命中 `mizchi/signals@0.6.4` | 确认：已在 .mooncakes 中 |
| "手动 dirty 模式" | `grep -c "self.dirty = true" lib/tui/tui_controller.mbt` | 59 处 | 确认：大量手动失效点 |
| "手动 redraw 调用" | `grep -c "self.redraw()" lib/tui/tui_controller.mbt` | 14 处 | 确认 |
| "signals API 可用" | 读取 `.mooncakes/mizchi/signals/src/signal.mbt` | 提供 `Signal[T]`、`signal()`、`render_effect()`、`memo()` | 确认：API 就绪 |

### 详细分析

**当前模式**（`tui_controller.mbt` 典型片段）：

```moonbit
// 每次状态变更都要手动标记 + 重绘
self.state.val.streaming_buffer = self.state.val.streaming_buffer + chunk
self.dirty = true
// ... 59 处类似代码
if self.dirty {
  self.redraw()
  self.dirty = false
}
```

**问题**：
1. 59 个 `dirty = true` 散布在 1328 行 controller 中，新增功能时极易遗漏
2. `redraw()` 调用与 `dirty` 标记分离（14 处 vs 59 处），逻辑不对称
3. 无法区分"哪些字段变了"，每次 dirty 都触发完整 VNode 树重建（虽然 diff 引擎只写变化 cell，但树构建本身有开销）

**mizchi/signals 已有能力**（v0.6.4，已在 .mooncakes）：
- `Signal[T]`：响应式值容器，`.get()` / `.set()`
- `render_effect(fn)`：同步副作用，依赖变化时自动重执行
- `memo(fn)`：惰性计算缓存
- `sig_map` / `sig_filter`：信号组合子

## 决策 [必填 - 含为什么]

1. **渐进迁移，不全量替换**：将 TuiState 的高频变更字段（streaming_buffer、tool_output、thinking_buffer、agent_status、tick_count）改为 `Signal[T]`，低频字段（session_id、model_name、working_dir 等初始化后不变的）保持 `mut`。原因：全量替换 59 处调用风险过高，渐进迁移可在每步验证后继续。

2. **用 `render_effect` 替代手动 dirty+redraw**：在 controller 初始化时注册一个 `render_effect`，监听高频 Signal 变化，自动触发 `redraw()`。原因：消除遗漏 dirty 标记的风险，且 effect 只在依赖真正变化时触发。

3. **保留 tick 循环作为兜底**：200ms tick 循环保留，但改为"仅当 effect 未触发时才 redraw"。原因：某些非 Signal 字段（如 dialog 状态）仍需 tick 兜底，避免一次性改动过多。

4. **mizchi/signals 加为直接依赖**：虽然已是传递依赖，但直接使用必须声明。原因：MoonBit 包管理要求显式声明直接使用的依赖。

<!-- MoonBit 约束检查：
- AOT 约束：Signal[T] 是编译期泛型，不涉及动态 trait。✓
- crescent 路由：不涉及。✓
- FFI：不涉及 C 库。✓
- 注意：Signal 的 render_effect 是同步执行的，与 controller 的 async 事件循环兼容。✓
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `moon.mod` | 修改 | 添加 `"mizchi/signals@0.6.4"` 直接依赖 |
| `lib/tui/moon.pkg` | 修改 | import 中添加 `"mizchi/signals"` |
| `lib/tui/state.mbt` | 修改 | 5 个高频字段改为 `Signal[T]`，其余保持 `mut` |
| `lib/tui/tui_controller.mbt` | 修改 | 高频路径的 `dirty=true` 改为 `.set()`；初始化时注册 `render_effect` |

### 不涉及文件

- `lib/tui/output_buffer.mbt`：数据层不变
- `lib/tui/vnode_renderer.mbt`：渲染管线不变
- `lib/tui/tui_controller_vnode.mbt`：VNode 构建读取 Signal 的 `.get()` 即可，结构不变
- `lib/agent/*`：agent 接口不变
- 所有 `*_wbtest.mbt`：断言逻辑不变，仅 setup 中 TuiState 构造可能需适配

## 实施计划 [必填]

### 任务包 1：依赖声明 + Signal 字段迁移（预估 0.5 天）

- `moon.mod` 添加 `"mizchi/signals@0.6.4"`
- `lib/tui/moon.pkg` import 添加 `"mizchi/signals"`
- `state.mbt` 中以下字段改为 `Signal[T]`：
  - `streaming_buffer : Signal[String]`（原 `mut streaming_buffer : String`）
  - `streaming_active : Signal[Bool]`
  - `tool_output : Signal[String]`
  - `thinking_buffer : Signal[String]`
  - `agent_status : Signal[String]`
- `TuiState::from_agent` 中对应初始化改为 `signal("")`、`signal(false)` 等
- 所有读取处改为 `.get()`，写入处改为 `.set()`

### 任务包 2：render_effect 替代手动 dirty（预估 0.5 天）

- 在 `TuiController` 初始化（`run_tui_interactive` 或 `TuiController::new`）中注册：
  ```moonbit
  let _ = render_effect(fn() {
    // 读取高频 Signal，建立依赖
    let _ = self.state.val.streaming_buffer.get()
    let _ = self.state.val.tool_output.get()
    let _ = self.state.val.thinking_buffer.get()
    let _ = self.state.val.agent_status.get()
    self.redraw()
  })
  ```
- 删除这 4 个字段相关的 `self.dirty = true` 调用（约 20-25 处）
- 保留其余字段的 `dirty = true`（dialog、shell_mode 等低频路径）
- tick 循环改为：`if self.dirty { self.redraw(); self.dirty = false }`（不变，作为兜底）

### 任务包 3：测试适配 + 回归验证（预估 0.25 天）

- 检查所有 `*_wbtest.mbt` 中直接构造 `TuiState` 的地方，适配 Signal 初始化
- 运行 `moon test lib/tui` 确认全过
- 运行 `--tui-eval` 确认 41 场景全过
- 手动测试：流式输出、工具调用、thinking 显示是否正常

## 验收标准 [必填]

- [ ] `mizchi/signals@0.6.4` 在 `moon.mod` 中声明为直接依赖
- [ ] TuiState 的 5 个高频字段为 `Signal[T]` 类型
- [ ] 高频路径不再有手动 `self.dirty = true`（由 render_effect 自动触发）
- [ ] 流式输出、工具调用、thinking 显示行为不变
- [ ] 现有 41 个 tui-eval 场景全部通过
- [ ] `moon check` 0 errors（lib/tui）
- [ ] `moon test lib/tui` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| render_effect 与 async 事件循环交互异常 | 高 | mizchi/signals 的 render_effect 是同步执行的（非 JS 微任务），与 MoonBit native async 兼容。先在 wbtest 中验证 |
| Signal .get() 在 VNode 构建热路径上的性能开销 | 中 | Signal.get() 是 O(1) 读取（无订阅追踪时在非 effect 上下文中），性能影响可忽略。若实测有回归，回退到 mut 字段 |
| wbtest 中 TuiState 构造需大量适配 | 中 | 提供 `TuiState::from_agent` 作为唯一构造入口，wbtest 通过它创建状态，减少适配点 |
| 渐进迁移导致"半 Signal 半 mut"混合状态 | 低 | 明确划分：高频 5 字段用 Signal，其余保持 mut。不追求全量迁移 |

## 依赖关系 [必填]

- **前置依赖**：无（mizchi/signals 已在 .mooncakes 中作为 mizchi/tui 的传递依赖）
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-28 | 初始版本 | 验收审计发现 state.mbt 未迁移到 signals，经代码验证确认为代码质量债务（非功能缺陷） |
| 2026-07-28 | 对抗性审核 | 经代码验证，所有声明正确，文件存在，无过度工程，模板完整 |
