# MBOpenClacky TUI 全面评估与改造方案

> **日期**：2026-07-01
> **作者**：可莱克（AI 技术合伙人）
> **范围**：`lib/tui/` 全部 27 个文件 + onebit-tui 依赖 + vendor/yoga + C FFI 渲染器
> **基线**：`docs/TUI_DEBUG_PLAN.md`（2026-07-01 Yoga 引擎替换）、`docs/gap-analysis-between-projects-2026-06-30.md`、`docs/cli-interface-assessment-review-0629.md`
> **状态**：⚠️ 已过时 — 本文档基于旧的 onebit-tui 架构。TUI 已迁移至 `moonbit-community/tty` Inline Scrolling 架构，详见 [`docs/tui-inline-migration-plan.md`](./tui-inline-migration-plan.md)（Phase 0-5 已完成）

---

## 目录

1. [执行摘要](#1-执行摘要)
2. [现状分析](#2-现状分析)
3. [根因分析：5 个已确认的 Bug](#3-根因分析5-个已确认的-bug)
4. [MoonBit 生态评估](#4-moonbit-生态评估)
5. [历史经验总结](#5-历史经验总结)
6. [解决方案设计：三选一](#6-解决方案设计三选一)
7. [推荐方案与实施路径](#7-推荐方案与实施路径)
8. [风险评估](#8-风险评估)
9. [附录：关键代码锚点索引](#9-附录关键代码锚点索引)

---

## 1. 执行摘要

MBOpenClacky 的 TUI 建立在 `Frank-III/onebit-tui@0.1.3` 之上，采用**全屏保留模式（retained-mode）**架构，通过 Facebook Yoga Flexbox 引擎布局，由纯 C ANSI 渲染器（`opentui_stubs.c`）输出到终端。这与原项目 openclacky 的**内联滚动式（inline scrolling）TUI** 形成本质差异。

上一轮修复（`TUI_DEBUG_PLAN.md`，2026-07-01）成功替换了 Yoga 空桩为真实引擎并添加了根布局约束。但本次深入代码审计发现 **5 个未解决的渲染 Bug**，其中最严重的是：**在非 Windows 平台上（含 WSL/Linux），所有 View 边框被静默丢弃**——`bufferDrawBoxMB` 函数通过 `dlsym` 查找 Zig 库符号，而该库仅在 `aarch64-macos` 上存在。

本报告提出三套方案并推荐**混合方案（Option C）**：先以 2-3 天修复 C stubs 中的关键 Bug，验证渲染质量后再决定是否迁移到 `moonbit-community/tty` 的内联 TUI 架构。

---

## 2. 现状分析

### 2.1 架构概览

```
┌──────────────────────────────────────────────────────┐
│                  MBOpenClacky TUI                     │
│                                                       │
│  ┌─────────┐    ┌──────────────┐    ┌──────────────┐ │
│  │ lib/tui │───▶│ onebit-tui   │───▶│ Yoga Layout  │ │
│  │ 27 files│    │ (MoonBit API)│    │ (C++ lib)    │ │
│  │ 4941 LOC│    └──────┬───────┘    └──────────────┘ │
│  └─────────┘           │                              │
│                        ▼                              │
│              ┌───────────────────┐                    │
│              │ opentui_stubs.c   │ ◀── 纯 C ANSI 渲染器│
│              │ (798 lines)       │     双缓冲/脏行优化 │
│              │ Cell[8+w*RGBA]   │     UTF-8/CJK 宽度 │
│              └────────┬──────────┘                    │
│                       │                               │
│              ┌────────▼──────────┐                    │
│              │ opentui_wrap.c    │ ◀── 跨平台输入处理 │
│              │ (710 lines)       │     POSIX/Windows  │
│              │ dlsym(sym) 桥接   │     termios/_kbhit │
│              └───────────────────┘                    │
└──────────────────────────────────────────────────────┘
```

### 2.2 与原项目 openclacky 的架构对比

| 维度 | openclacky (Ruby) | MBOpenClacky (MoonBit) |
|------|-------------------|------------------------|
| **TUI 模式** | Inline 滚动式（利用终端 scrollback） | Full-screen retained-mode（接管 alternate screen） |
| **渲染方式** | 直接 ANSI escape codes，手动计算坐标 | 双缓冲 Cell 网格 → dirty-row 优化 → ANSI 输出 |
| **布局引擎** | 无（手动 `row`/`col` 坐标计算） | Yoga 2.0.2 Flexbox（vendored ~408KB） |
| **输入处理** | `io/console` raw mode + char-by-char | onebit-tui FFI: POSIX termios / Windows _kbhit |
| **文本编辑** | `LineEditor` mixin（char 级操作） | `@widget.TextInput`（View-based, caret_col） |
| **代码规模** | ui2 8047 行 + rich_ui 2252 行 = 10,695 行 | 27 文件 4941 行 + C stubs 1508 行 |
| **功能覆盖** | 完整（审批对话框、实时思考、表单等） | ~75%（基础功能完整，缺 Rich UI 高级组件） |

### 2.3 关键文件清单

| 文件 | 行数 | 职责 | 健康度 |
|------|------|------|--------|
| `tui.mbt` | 343 | 入口、主布局、输入提交、状态同步 | ✅ 良好 |
| `input_bar.mbt` | 594 | 输入栏 + 多行编辑器 + 命令建议 | ⚠️ 双渲染函数冗余 |
| `state.mbt` | 163 | TuiState 结构体（~30 字段） | ✅ 良好 |
| `status_bar.mbt` | 54 | 13 段 Row 布局 | ❌ 溢出/重叠 |
| `message_view.mbt` | 90 | ScrollBox + 动态行数 | ⚠️ 仅字符串格式 |
| `banner.mbt` | 220 | 3 种横幅风格（Boxed/Minimal/Block） | ⚠️ 边框乱码 |
| `agent_hooks.mbt` | ~100 | 10 种 HookEvent 分发 | ✅ 良好 |
| `slash_commands.mbt` | ~150 | 7 个斜杠命令 | ⚠️ execute 仅返回描述字符串 |
| `tui_layout_wbtest.mbt` | 94 | 布局回归测试 | ✅ 良好 |

### 2.4 onebit-tui 依赖健康度

| 指标 | 值 | 评估 |
|------|-----|------|
| mooncakes 下载量 | **19** | 极低（全生态最低之一） |
| 版本数 | 4 | 迭代缓慢 |
| build_status | `legacy` | MoonBit 编译器已不兼容最新标准 |
| 最近更新 | 2025-10-17 | 8 个月未更新 |
| 作者维护 | Frank-III | 活跃度未知 |

**结论**：onebit-tui 是一个低质量、低维护的依赖包，但它的 C 渲染器（`opentui_stubs.c`）实际上是一个功能完备的纯 C ANSI 终端渲染器，值得修复而非废弃。

---

## 3. 根因分析：5 个已确认的 Bug

### Bug #1（P0 致命）：View 边框在 Linux/WSL 上完全消失

**现象**：所有带 `border` 的 View（输入框、按钮、容器）在 WSL/Linux 终端中无边框显示。

**根因链**：
```
bufferDrawBoxMB() (opentui_wrap.c:237)
  └─ #else 分支（非 Windows）
      └─ sym("bufferDrawBox")  ← dlsym(RTLD_DEFAULT, "bufferDrawBox")
          └─ 符号不存在（Zig libopentui.a 仅 aarch64-macos）
              └─ 返回 NULL
                  └─ if(f) 失败 → 边框不绘制
```

**代码位置**：
- `opentui_wrap.c:265-269`：非 Windows 分支仅有 `if(f) f(...)` 无 fallback
- `opentui_wrap.c:76-92`：`sym()` 使用 `dlsym(RTLD_DEFAULT, name)`
- Windows 分支（`opentui_wrap.c:241-263`）已有完整 fallback 使用 `stubSetCellWithAlpha`

**影响范围**：所有 `View` 的 `border` 属性在非 macOS ARM 平台上无效。这是当前 TUI "乱码" 视觉效果的主要原因——没有边框约束，内容溢出到错误位置。

**修复方案**：将 Windows 分支的 `stubSetCellWithAlpha` 直接绘制逻辑提取为公共函数，在 `#else` 分支中作为 fallback 调用。

**预计工时**：0.5 天

---

### Bug #2（P1 高）：光标覆盖文本首字符

**现象**：输入框中 `|` 光标与占位符 "Type a message..." 的首字母 "T" 重叠，显示为 `|ype a message`。

**根因**：
```
render_with_layout() (layout_engine.mbt:301-308)
  └─ app.draw_text(text, inner_x, inner_y, fg)     ← 先画文本
  └─ app.draw_text("|", caret_x, caret_y, fg)       ← 再画光标，覆盖文本
```

`caret_x = inner_x + cidx`，当 `cidx = 0` 时光标位置 = 文本起始位置，`draw_text` 直接覆盖该 cell。

**代码位置**：`layout_engine.mbt:298-308`

**修复方案**：将光标逻辑改为在文本字符串中插入光标字符（如在 `cidx` 位置插入 `▏` 或反转该字符颜色），而非在缓冲区上二次绘制。

**预计工时**：0.5 天

---

### Bug #3（P1 高）：状态栏 13 段文本溢出/重叠

**现象**：状态栏显示 `ϥ idl |s_17828 |/mnt/d/MoonBit/MBOpenCl | confirm_saf |kimi-k2.7-co |0 task | $0`，文本被截断和重叠。

**根因**：
```
status_bar.mbt → Row of 13 × View::text(segment)
  └─ 每段无显式 width/flex 约束
      └─ Yoga 将可用宽度平均分配 → 每段仅 ~6 字符宽
          └─ 长文本（如工作目录路径）被截断
              └─ 截断后的文本 + 分隔符挤在一起 → 视觉重叠
```

**代码位置**：`status_bar.mbt` 全文（54 行）

**修复方案**：
1. 将固定文本段（分隔符 `|`、标签）设为固定宽度
2. 将可变文本段（路径、模型名）设为 `flex(1.0)` + `overflow(Truncate)`
3. 减少段数：合并相关字段（如 `model | iter` → `model:iter`）

**预计工时**：0.5 天

---

### Bug #4（P2 中）：bufferDrawText 不处理换行符

**现象**：包含 `\n` 的多行文本（如 banner）被渲染为单行，换行后的内容接在前一行末尾。

**根因**：
```c
// opentui_stubs.c:372
int w = char_width(cp);
if (w == 0) { pos += adv; continue; }  // \n (0x0A) 的 char_width 返回 0
// → 跳过 \n 但不重置 cx=0, cy++
```

`\n`（U+000A）在 `char_width()` 中返回 0（控制字符），`bufferDrawText` 跳过它但不换行。

**代码位置**：`opentui_stubs.c:371-373`

**修复方案**：在 `w == 0` 的分支中，检测 `cp == '\n'`（0x0A）时执行 `cx = x; cy++;` 换行。

**预计工时**：0.5 天

---

### Bug #5（P2 中）：tmux capture 可能不代表真实渲染

**现象**：tmux `capture-pane` 输出显示 `T%P%P%P%` 等乱码，但这可能是 tmux 对 alternate screen + 多字节 UTF-8 的捕获限制，而非真实终端渲染问题。

**验证需求**：在真实终端（非 tmux）中运行 TUI 并截图对比。strace 输出已确认正确的 ANSI 序列被写入 stdout：
```
write(1, "\33[H\33[1;1H\33[K\33[0m\33[38;2;255;255;2"..., 4096) = 4096
```

**验证方法**：
1. 在 WSL 终端中直接运行 `./_build/native/debug/build/cmd/cmd.exe`（非 tmux）
2. 使用 Windows 截图工具捕获终端画面
3. 或使用 `script` 命令录制终端会话后检查

**预计工时**：0.5 天

---

## 4. MoonBit 生态评估

### 4.1 TUI 相关包下载量排名

| 排名 | 包名 | 下载量 | 版本 | 创建日期 | 适用性评估 |
|------|------|--------|------|----------|-----------|
| 1 | **moonbit-community/tty@0.2.5** | **2,032** | 7 | 2026-06-10 | ✅ 最成熟，低层终端原语（raw mode/size/VT/input），无布局引擎 |
| 2 | FrozenLemonTee/LunarTUI@0.1.0 | 137 | 3 | 2026-06-03 | ⚠️ C++ FFI 后端，早期 |
| 3 | CAIMEOX/box@0.1.3 | 25 | 3 | 2026-05-06 | ⚠️ 2D 文本布局组合子 |
| 4 | moonbit-community/rabbita_tui@0.1.0 | 16 | 1 | 2026-05-14 | ⚠️ Elm 架构，仅 4 次提交 |
| 5 | brickfrog/pippa@0.1.0 | 15 | 1 | 2026-06-04 | ⚠️ Bubbletea 风格，极早期 |
| 6 | **Frank-III/onebit-tui@0.1.3** | **19** | 4 | 2025-10-17 | ⚠️ 当前依赖，legacy build status |
| 7 | Yu-zh/termbit@0.1.1 | 11 | 2 | 2025-04-09 | ❌ 终端操作库，不活跃 |
| 8 | xingwangzhe/style_print@0.1.7 | 10 | 3 | 2025-10-08 | ❌ 仅 ANSI 着色 |
| 9 | allwefantasy/readline.mbt@0.1.0 | 9 | 1 | 2025-09-04 | ❌ readline 兼容层 |
| 10 | grandEarshot/tui@0.1.0 | 6 | 1 | 2026-04-14 | ❌ 极早期 |

### 4.2 标准库终端能力

| 库 | 版本 | 终端 I/O 能力 |
|----|------|-------------|
| `moonbitlang/core` | 内置 | ❌ 无（仅有 `println`/`print`） |
| `moonbitlang/x` | 0.4.43 | ❌ 无（codec/crypto/fs/json/path/sys/time/uuid，无终端） |
| `moonbitlang/async` | 0.19.1 | ❌ 无（io/fs/http/aqueue/cond_var，无终端） |

**结论**：MoonBit 标准库**完全不含终端 I/O 能力**，必须使用第三方包。`moonbit-community/tty` 是唯一成熟的选择。

### 4.3 `moonbit-community/tty` 能力评估

通过查看 mooncakes.io 包页面，`tty@0.2.5` 提供：
- 终端状态管理（raw mode、canonical mode）
- 终端尺寸获取（`terminal_size()`）
- VT100 输出（光标定位、清屏、颜色）
- 输入事件解码（键盘、鼠标）
- 依赖 `moonbitlang/async@0.19.1`（与项目一致）

**缺少**：布局引擎、widget 系统、双缓冲、CJK 宽度计算——这些需要自行实现。

---

## 5. 历史经验总结

### 5.1 已完成的 TUI 修复（TUI_DEBUG_PLAN.md, 2026-07-01）

| 修复项 | 状态 | 效果 |
|--------|------|------|
| Yoga 空桩 → 真实 Yoga 2.0.2 | ✅ 已完成 | 布局计算不再返回全零 |
| 根布局 width/height 约束 | ✅ 已完成 | 子节点 flex(1.0) 可获得弹性空间 |
| 状态栏重构（顶部→底部） | ✅ 已完成 | 视觉层次更接近原项目 |
| TuiState 扩展（working_dir 等） | ✅ 已完成 | 状态信息更丰富 |
| 布局回归测试（94 行） | ✅ 已完成 | 防止布局回归 |
| **View 边框渲染** | ❌ **未修复** | dlsym fallback 缺失（Bug #1） |
| **光标/文本重叠** | ❌ **未修复** | 二次 draw_text 覆盖（Bug #2） |
| **状态栏溢出** | ❌ **未修复** | 无 width/flex 约束（Bug #3） |

### 5.2 Gap Analysis 中的 TUI 评估（2026-06-30）

- TUI 覆盖度：**~75%**
- 缺失：Rich UI 高级组件（审批对话框、实时思考视图、表单对话框）
- 代码规模：MBOpenClacky 4941 行 vs openclacky 10695 行

### 5.3 CLI 评估报告中的 TUI 发现（2026-06-29）

- HookEvent：10 个变体，100% 已 match
- 斜杠命令：7 个已注册（config/model/clear/new/skills/help/exit），但 `execute()` 仅返回描述字符串，未实际执行
- `--theme` 选项：源项目仅支持 hacker/minimal 两种内置主题

### 5.4 关键教训

1. **C FFI 层是脆弱点**：onebit-tui 的 C stubs 包含大量平台条件编译，Windows 分支有完整实现但非 Windows 分支依赖 `dlsym` 动态查找，导致跨平台不一致。
2. **Yoga 修复验证不充分**：TUI_DEBUG_PLAN 的"验证通过"仅基于 strace 确认 ANSI 序列被写出，未实际验证渲染质量（tmux capture 可能有误导）。
3. **架构选型影响深远**：从 inline TUI 切换到 full-screen retained-mode TUI 是一个重大架构决策，引入了布局引擎、双缓冲、C FFI 等复杂度，但这些复杂度的收益（自动布局、widget 复用）尚未兑现。

---

## 6. 解决方案设计：三选一

### Option A：深度修复 onebit-tui C stubs

**思路**：保留现有架构，逐一修复第 3 节中的 5 个 Bug。

**修复清单**：
1. [P0] `bufferDrawBoxMB` 非 Windows 分支添加 `stubSetCellWithAlpha` fallback
2. [P1] `render_with_layout` 光标渲染逻辑改为内嵌而非覆盖
3. [P1] `status_bar.mbt` 段落添加 width/flex 约束
4. [P2] `bufferDrawText` 添加 `\n` 换行处理
5. [P2] 真实终端截图验证

| 维度 | 评估 |
|------|------|
| 工时 | 2-3 天 |
| 风险 | 低（修改范围明确，有 Windows 分支作为参考实现） |
| 收益 | 立即解决所有渲染问题，保留现有架构和代码 |
| 不足 | 仍依赖 onebit-tui（19 下载、legacy）；C stubs 可能有更多隐藏 Bug |
| 适合场景 | 快速止血，验证 onebit-tui 的真实渲染能力 |

---

### Option B：迁移到 `moonbit-community/tty` 内联 TUI

**思路**：参照原项目 openclacky 的 inline TUI 架构，基于 `tty@0.2.5` 重新构建 TUI 层。

**架构设计**：
```
┌─────────────────────────────────────────────┐
│           新 TUI 架构（Inline）              │
│                                             │
│  ┌─────────────┐  ┌──────────────────────┐ │
│  │ moonbit-    │  │ lib/tui/ (重写)      │ │
│  │ community/  │──│                      │ │
│  │ tty@0.2.5   │  │ - inline_renderer    │ │
│  │             │  │ - line_editor        │ │
│  │ - raw mode  │  │ - screen_buffer      │ │
│  │ - term size │  │ - status_bar         │ │
│  │ - VT output│  │ - message_scroller   │ │
│  │ - input     │  │ - markdown_renderer  │ │
│  └─────────────┘  └──────────────────────┘ │
│                                             │
│  无 Yoga / 无双缓冲 / 无 C stubs            │
│  直接 ANSI escape codes + 终端 scrollback   │
└─────────────────────────────────────────────┘
```

**需要重写的组件**：

| 组件 | 当前行数 | 预计行数 | 工作量 |
|------|---------|---------|--------|
| screen_buffer（ANSI 渲染层） | 0（C stubs 替代） | ~200 | 2 天 |
| line_editor（输入编辑器） | 594 | ~300 | 2 天 |
| message_scroller（消息滚动） | 90 | ~150 | 1 天 |
| status_bar（状态栏） | 54 | ~80 | 0.5 天 |
| markdown_renderer（Markdown） | ~200 | ~250 | 2 天 |
| slash_commands（斜杠命令） | ~150 | ~150 | 0.5 天 |
| theme（主题系统） | ~100 | ~100 | 0.5 天 |
| agent_hooks（事件钩子） | ~100 | ~100 | 0.5 天 |
| 主控制器（orchestrator） | 343 | ~300 | 1 天 |

| 维度 | 评估 |
|------|------|
| 工时 | 2-3 周 |
| 风险 | 中（需要重建输入编辑器和 Markdown 渲染器，但参照原项目 Ruby 实现） |
| 收益 | 摆脱 onebit-tui 依赖；架构更简单可靠；与原项目 UX 一致；tty 包活跃维护（2032 下载） |
| 不足 | 大规模重写，需要重建所有 TUI 组件；丢失 Yoga 布局能力（但 inline TUI 不需要） |
| 适合场景 | 彻底解决 TUI 质量问题，长期维护 |

---

### Option C：混合方案（推荐）

**思路**：分两阶段——先修复（Option A），再评估是否迁移（Option B）。

**Phase 1：快速修复（2-3 天）**
1. 修复 Bug #1（边框 dlsym fallback）— **0.5 天**
2. 修复 Bug #2（光标覆盖）— **0.5 天**
3. 修复 Bug #3（状态栏溢出）— **0.5 天**
4. 修复 Bug #4（换行处理）— **0.5 天**
5. 真实终端验证 — **0.5 天**

**Phase 1 验收标准**：
- [ ] 在 WSL 终端（非 tmux）中运行 TUI，边框正确显示
- [ ] 输入框光标不覆盖文本
- [ ] 状态栏文本不溢出/重叠
- [ ] 多行 banner 正确换行
- [ ] `moon check` 0 errors
- [ ] `moon test` 全量通过

**Phase 2：架构决策（Phase 1 完成后）**

根据 Phase 1 的验证结果：
- **如果渲染质量可接受** → 继续使用 onebit-tui，逐步补充 Rich UI 组件
- **如果仍有严重问题** → 启动 Option B 迁移到 tty 内联 TUI

| 维度 | 评估 |
|------|------|
| 工时 | Phase 1: 2-3 天；Phase 2（可选）: 2-3 周 |
| 风险 | 最低（先验证再决策，避免不必要的重写） |
| 收益 | 立即止血 + 保留迁移选项 |
| 适合场景 | 所有情况（推荐默认选择） |

---

## 7. 推荐方案与实施路径

### 推荐：Option C（混合方案）

**理由**：
1. Bug #1 的修复极其简单（将 Windows 分支已有代码复制到 `#else` 分支），预期立竿见影
2. 在确认 onebit-tui 的真实渲染能力之前，大规模重写是不必要的风险
3. 即使最终选择迁移到 tty，Phase 1 的修复也能让 TUI 在过渡期内可用

### Phase 1 详细实施计划

#### Step 1：修复边框 dlsym fallback（Bug #1）

**文件**：`.mooncakes/Frank-III/onebit-tui/src/ffi/opentui_wrap.c`

**修改**：将 `bufferDrawBoxMB` 的 `#else` 分支从：
```c
#else
    fn_bufferDrawBox f = (fn_bufferDrawBox)sym("bufferDrawBox");
    if (f) f(buffer, x, y, width, height, borderChars, packedOptions, fborder, fbg, title, titleLen);
#endif
```

改为：
```c
#else
    fn_bufferDrawBox f = (fn_bufferDrawBox)sym("bufferDrawBox");
    if (f) {
        f(buffer, x, y, width, height, borderChars, packedOptions, fborder, fbg, title, titleLen);
    } else {
        // Fallback: use pure-C implementation (same as Windows)
        bufferDrawBoxFallback(buffer, x, y, width, height, borderChars, fborder, fbg, title, titleLen);
    }
#endif
```

其中 `bufferDrawBoxFallback` 是从 Windows 分支提取的公共函数，使用 `stubSetCellWithAlpha` 直接绘制。

**验证**：`moon check` + tmux 运行确认边框出现。

---

#### Step 2：修复光标覆盖（Bug #2）

**文件**：`.mooncakes/Frank-III/onebit-tui/src/layout/layout_engine.mbt`

**修改**：在 `render_with_layout` 中，将光标渲染从"覆盖式"改为"内嵌式"。

当前逻辑：
```moonbit
app.draw_text(text, inner_x, inner_y + center_offset, fg)  // 画文本
// ...
app.draw_text("|", caret_x, caret_y, fg)  // 画光标（覆盖文本）
```

改为：
```moonbit
// 如果有光标位置，在文本中插入光标标记
let display_text = match view.caret_col {
  Some(cidx) => insert_caret(text, cidx)  // 在 cidx 位置插入 ▏
  None => text
}
app.draw_text(display_text, inner_x, inner_y + center_offset, fg)
```

或者更简单的方案：仅当 `text` 为空（显示 placeholder）时画光标，否则用反色渲染光标位置的字符。

---

#### Step 3：修复状态栏溢出（Bug #3）

**文件**：`lib/tui/status_bar.mbt`

**修改**：
1. 将分隔符 `|` 和固定标签设为 `.width(N)` 固定宽度
2. 将可变内容（路径、模型名）设为 `.flex(1.0)` + `.overflow(Overflow::Hidden)`
3. 合并部分字段减少段数（13 → 8）

```moonbit
// 示例重构
let segments = [
  status_icon.width(3),           // ●/■/▶  固定
  state_text.width(8),            // running/idle  固定
  separator.width(1),             // |
  model_name.flex(1.0),           // kimi-k2.7-coding  弹性
  separator.width(1),             // |
  iter_count.width(6),            // #42   固定
  separator.width(1),             // |
  working_dir.flex(1.0),          // /mnt/d/...  弹性+截断
  separator.width(1),             // |
  permission.width(12),           // confirm_safes  固定
  separator.width(1),             // |
  task_count.width(8),            // 0 task  固定
  separator.width(1),             // |
  cost.width(8),                  // $0.00  固定
]
```

---

#### Step 4：修复换行处理（Bug #4）

**文件**：`.mooncakes/Frank-III/onebit-tui/src/ffi/opentui_stubs.c`

**修改**：在 `bufferDrawText` 的 `w == 0` 分支中添加换行处理：

```c
int w = char_width(cp);
if (w == 0) {
    if (cp == '\n') {       // ← 新增：换行符处理
        cx = x;             // 重置到起始列
        cy++;                // 换行
        if (cy >= b->height) break;
    }
    pos += adv;
    continue;  // 跳过控制字符
}
```

---

#### Step 5：真实终端验证

**方法**：
1. 在 WSL 终端中直接运行（非 tmux）：
   ```bash
   MBOPENCLACKY_API_KEY=dummy-key ./_build/native/debug/build/cmd/cmd.exe
   ```
2. Windows 截图工具捕获画面
3. 与原项目 openclacky 截图对比
4. 记录渲染质量评估

---

### Phase 2 决策矩阵

| Phase 1 结果 | 推荐 Phase 2 行动 |
|-------------|------------------|
| 渲染完美/基本正常 | 保持 onebit-tui，逐步补充 Rich UI 组件 |
| 有小问题但可用 | 修复剩余问题，保持 onebit-tui |
| 仍有严重渲染问题 | 启动 Option B 迁移到 tty 内联 TUI |
| C stubs 有更多隐藏 Bug | 启动 Option B 迁移到 tty 内联 TUI |

---

## 8. 风险评估

### 技术风险

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| C stubs 修复后发现更多隐藏 Bug | 中 | 中 | Phase 2 决策矩阵已覆盖此场景 |
| tty 包缺少某些能力（如 CJK 宽度） | 低 | 中 | Phase 2 前先评估 tty API 完整性 |
| Yoga 库跨平台编译问题 | 低 | 高 | 已有 setup_yoga.sh 脚本，WSL 验证通过 |
| MoonBit 编译器版本升级破坏 onebit-tui | 中 | 高 | 将 onebit-tui 源码 fork 到项目内（已通过 .mooncakes 间接实现） |

### 工期风险

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| Phase 1 修复引入回归 | 低 | 低 | 已有 94 行布局回归测试 + `moon test` 全量验证 |
| Phase 2 迁移工期超预期 | 中 | 中 | 分组件迁移，优先输入栏和消息视图 |

---

## 9. 附录：关键代码锚点索引

### Bug #1：边框不绘制

| 文件 | 行号 | 代码 |
|------|------|------|
| `opentui_wrap.c` | 76-92 | `sym()` → `dlsym(RTLD_DEFAULT, name)` |
| `opentui_wrap.c` | 237-269 | `bufferDrawBoxMB()` — `#else` 分支无 fallback |
| `opentui_wrap.c` | 241-263 | Windows 分支完整实现（参考） |
| `opentui_stubs.c` | 399-440 | `stubSetCellWithAlpha()` — 可复用的 cell 写入函数 |
| `layout_engine.mbt` | 356-396 | `render_border()` → `buf.draw_box()` 调用链 |

### Bug #2：光标覆盖

| 文件 | 行号 | 代码 |
|------|------|------|
| `layout_engine.mbt` | 298-308 | `app.draw_text(text, ...)` + `app.draw_text("\|", ...)` |
| `widget/input.mbt` | 100-115 | `TextInput::render()` → `view.caret_col(self.cursor)` |
| `core/app.mbt` | 38-48 | `App::draw_text()` → `buffer.draw_text()` |

### Bug #3：状态栏溢出

| 文件 | 行号 | 代码 |
|------|------|------|
| `status_bar.mbt` | 全文 | 13 段 `View::text` Row 布局，无 width/flex |

### Bug #4：换行不处理

| 文件 | 行号 | 代码 |
|------|------|------|
| `opentui_stubs.c` | 371-373 | `if (w == 0) { pos += adv; continue; }` — 不处理 `\n` |
| `opentui_stubs.c` | 162-180 | `char_width()` — 控制字符返回 0 |
| `opentui_stubs.c` | 347-395 | `bufferDrawText()` 完整函数 |

### 原始项目参考

| 文件 | 行数 | 参考价值 |
|------|------|---------|
| `openclacky/lib/clacky/ui2/screen_buffer.rb` | ~200 | inline ANSI 渲染参考 |
| `openclacky/lib/clacky/ui2/line_editor.rb` | 363 | char 级输入编辑器参考 |
| `openclacky/lib/clacky/ui2/ui_controller.rb` | 1943 | 主控制器编排参考 |
| `openclacky/lib/clacky/rich_ui/` | 2252 | Rich UI 高级组件参考 |

---

## 总结

MBOpenClacky TUI 的核心问题不是架构选型错误，而是 onebit-tui 的 C FFI 层存在跨平台实现缺陷。最致命的 Bug #1（边框在非 Windows 上消失）有一个极简修复——将 Windows 分支已有的直接绘制代码复制到 `#else` 分支作为 fallback。

推荐立即执行 Phase 1（2-3 天），在验证渲染质量后再决定是否需要 Phase 2 的架构迁移。这个顺序确保：
1. **立即止血**——修复后 TUI 在所有平台上都能正确显示边框
2. **数据驱动决策**——基于真实渲染效果而非推测来选择长期方案
3. **最小化风险**——避免在未验证 onebit-tui 真实能力前就启动大规模重写
