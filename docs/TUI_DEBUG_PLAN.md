# MBOpenClacky TUI 调试报告：Yoga 布局引擎修复

> **日期**：2026-07-01
> **状态**：⚠️ 已过时 — 本文档涉及 onebit-tui + Yoga 架构的修复。TUI 已迁移至 `moonbit-community/tty` Inline Scrolling 架构，Yoga/onebit-tui 依赖已完全移除。详见 [`docs/tui-inline-migration-plan.md`](./tui-inline-migration-plan.md)
> **相关提交**：`497c4c4` (布局对齐), `b6e2c43` (Yoga 引擎替换)

---

## 1. 问题现象

启动 MBOpenClacky TUI 后，终端画面出现严重渲染异常：
- 所有 UI 组件（状态栏、输入框、Submit/Quit 按钮、占位符文字）**堆叠在终端左上角**
- 出现文字交叠乱码（`stimated)00t yetP%P%P%P%...`）
- 与源项目 openclacky 的截图对比，差异巨大

## 2. 根因分析（第一性原理）

### 2.1 架构差异

| 维度 | openclacky (Ruby) | MBOpenClacky (MoonBit) |
|------|------------------|----------------------|
| TUI 模式 | Inline TUI（滚动式命令行） | Retained-mode Full-screen TUI（全屏保留模式） |
| 渲染方式 | 依赖终端滚动缓冲区 + 底部 ANSI 动态输入框 | 接管备用屏幕（Alternate Screen），每帧全屏重绘 |
| 布局引擎 | 无（手动计算坐标） | Yoga（Facebook Flexbox 布局引擎） |

### 2.2 根因：Yoga 空桩 + 根节点约束缺失

经过深入排查，定位到**双重根因**：

**根因 1：onebit-yoga 的 yoga_stubs.c 是空桩**

`onebit-yoga` 依赖包提供的 `yoga_stubs.c` 中，`YGNodeCalculateLayout` 函数实现为一个空桩——它不做任何实际计算，直接返回全零布局（top=0, left=0, width=0, height=0）。所有 Yoga 节点的布局计算结果都被清零，导致无论 Flexbox 规则如何，所有子节点都坍塌到坐标原点 `(0,0)`。

这个空桩的存在是因为 onebit-yoga 作为 MoonBit 包发布时，选择了在 native-stub 中包含一个简化的 C 文件而不是链接真实的 Yoga 库。MoonBit 编译器会优先使用 native-stub 中声明的符号，覆盖了系统库中的真实实现。

**根因 2：根 Column 容器无显式尺寸约束**

即使 Yoga 引擎正常工作，如果 Flexbox 列布局的根节点没有明确的宽度和高度，其默认表现为 `Auto`（包裹内容）。子节点 `flex(1.0)` 在父节点高度为 Auto 时无法获得弹性空间分配，实际高度仍为 0。

### 2.3 影响链

```
Yoga 空桩
  → YGNodeCalculateLayout 返回全零
  → 所有节点 layout_top=0, layout_left=0
  → 所有组件堆叠在 (0,0)
  → 重叠渲染导致视觉乱码
```

## 3. 解决方案

### 3.1 替换 Yoga 空桩为真实引擎

**方案**：Vendor 真实 Facebook Yoga 2.0.2 C++ 源码，编译为静态库，从 onebit-yoga 的 native-stub 中移除空桩。

**实施步骤**：

1. `scripts/setup_yoga.sh` — 自动化编译脚本
   - 从 GitHub 下载 Yoga 2.0.2 C++ 源码
   - 编写 C wrapper（`vendor/yoga/src/yoga_wrap.cpp`）
   - 编译为 `vendor/yoga/lib/libyoga_full.a`（~408KB）
2. 链接配置：
   - `cmd/moon.pkg` — 添加 `-L vendor/yoga/lib -lyoga_full -lstdc++`
   - `lib/tui/moon.pkg` — 添加 `-L ../../vendor/yoga/lib -lyoga_full -lstdc++`
3. `.mooncakes/Frank-III/onebit-yoga/src/ffi/moon.pkg.json` — 从 `native-stub` 中移除 `yoga_stubs.c`

**关键文件变更**：

| 文件 | 变更 |
|------|------|
| `scripts/setup_yoga.sh` | 新增（64 行） |
| `vendor/yoga/lib/libyoga_full.a` | 新增（408KB 二进制） |
| `vendor/yoga/src/` | 新增（Yoga C++ 源码 + C wrapper） |
| `.mooncakes/Frank-III/onebit-yoga/src/ffi/moon.pkg.json` | 从 native-stub 移除 yoga_stubs.c |
| `cmd/moon.pkg` | 添加 -lyoga_full -lstdc++ |
| `lib/tui/moon.pkg` | 添加 -lyoga_full -lstdc++ |

### 3.2 根布局约束修复

**文件**：`lib/tui/tui.mbt` — `build_main_layout` 函数

**修改前**：
```mbt
@view.View::container_views([...]).direction(Column)
```

**修改后**：
```mbt
let (term_w, term_h) = @ffi.get_terminal_size()
let terminal_width = term_w.reinterpret_as_int()
let terminal_height = term_h.reinterpret_as_int()
// ...
@view.View::container_views([...]).direction(Column)
  .width(terminal_width.to_double())
  .height(terminal_height.to_double())
```

### 3.3 状态栏重构

**文件**：`lib/tui/status_bar.mbt`（42 行重写）

- 从顶部移至底部（输入栏上方），匹配源项目的 Inline TUI 视觉习惯
- 显示内容扩展：Agent 状态 / 模型名 / 迭代次数 / 工作目录 / 权限模式 / 活跃任务数
- 颜色映射：running→Green / error→Red / completed→Blue / 其他→Gray

### 3.4 TuiState 扩展

**文件**：`lib/tui/state.mbt`

新增字段：
- `working_dir : String` — 当前工作目录
- `permission_mode : String` — 权限模式（auto_approve / confirm_safes / confirm_all）
- `active_tasks : Int` — 活跃任务数

### 3.5 Agent Hooks 增强

**文件**：`lib/tui/agent_hooks.mbt`

RunCompleted 事件处理中新增：
- `s.working_dir = a.working_dir`
- `s.active_tasks = a.todo_manager.size()`

### 3.6 消息视图重构

**文件**：`lib/tui/message_view.mbt`

`message_view_render` 重写：
- `max_visible_lines` 从终端高度动态计算（`terminal_height - 5`），替代硬编码
- 自动滚动到最新消息

### 3.7 布局回归测试

**文件**：`lib/tui/tui_layout_wbtest.mbt`（新增 94 行）

验证项：
- 容器子节点 Y 轴偏移递增不重叠（Flex 列布局正确展开）
- `flex(1.0)` 子节点获得正高度（弹性空间分配正确）
- 固定高度子节点不被压缩

### 3.8 构建依赖补充

多个包的 `moon.pkg` 添加 `-lcurl` 链接标志（test 二进制链接 `lib/client` 需要 libcurl）：

| 包 | 新增标志 |
|------|---------|
| `lib/agent/moon.pkg` | `-lcurl` |
| `lib/client/moon.pkg` | `-lcurl` |
| `lib/tool/moon.pkg` | `-lcurl` |
| `lib/vision/moon.pkg` | `-lcurl` |

## 4. 验证结果

### 4.1 编译验证

```
moon check → 0 errors
```

### 4.2 测试验证

```
moon test --target native → 1,355 / 1,355 通过（+14 新增测试）
```

### 4.3 TUI 交互验证

在 WSL tmux 终端中运行原生二进制：

```bash
MBOPENCLACKY_API_KEY=dummy-key ./_build/native/debug/build/cmd/cmd.exe
```

结果：
- ✅ 正确进入备用屏幕（`\033[?1049h`）
- ✅ 隐藏光标（`\033[?25l`）
- ✅ 绘制欢迎横幅：`OpenClacky / AI Agent TUI`
- ✅ 底部输入栏：`Type a message...`
- ✅ 按 `q` 正常退出（退出备用屏幕、恢复光标）

strace 验证 Yoga 布局写入：
```
write(1, "\33[H\33[1;1H\33[K\33[0m\33[38;2;255;255;2"..., 4096) = 4096
write(1, "27m\33[48;2;30;30;43m|ype a messag"..., 430) = 430
```

### 4.4 注意事项

- `moon run cmd` 包装器在某些终端环境下可能不启动 TUI（MoonBit 运行包装器的已知行为）。手动使用时建议直接运行编译后的二进制：`./_build/native/debug/build/cmd/cmd.exe`
- Windows 环境下 TUI 需要启用 VT Processing，已在 `opentui_wrap.c` 中处理

## 5. 相关文件清单

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `lib/tui/tui.mbt` | 修改 | 根布局添加 width/height 约束 |
| `lib/tui/status_bar.mbt` | 重写 | 底部状态栏，扩展显示字段 |
| `lib/tui/state.mbt` | 修改 | 新增 working_dir / permission_mode / active_tasks 字段 |
| `lib/tui/agent_hooks.mbt` | 修改 | RunCompleted 同步新增字段 |
| `lib/tui/message_view.mbt` | 修改 | 从终端高度动态计算可见行数 |
| `lib/tui/tui_layout_wbtest.mbt` | 新增 | 布局回归测试（94 行） |
| `scripts/setup_yoga.sh` | 新增 | Yoga 编译脚本（64 行） |
| `vendor/yoga/` | 新增 | 真实 Yoga 2.0.2 库 |
| `.mooncakes/Frank-III/onebit-yoga/src/ffi/moon.pkg.json` | 修改 | 移除空桩 yoga_stubs.c |
| `cmd/moon.pkg` | 修改 | 添加 -lyoga_full -lstdc++ |
| `lib/tui/moon.pkg` | 修改 | 添加 -lyoga_full -lstdc++ |
| `lib/agent/moon.pkg` | 修改 | 添加 -lcurl |
| `lib/client/moon.pkg` | 修改 | 添加 -lcurl |
| `lib/tool/moon.pkg` | 修改 | 添加 -lcurl |
| `lib/vision/moon.pkg` | 修改 | 添加 -lcurl |
