# TUI 架构与对齐状态

> 更新日期：2026-07-29
> 本文档合并了原 `tui-redesign-goal.md`、`tui-redesign-mizchi-foundation-2026-07-28.md`、`tui-comparison-test-report.md` 中仍有效的内容。

## 当前架构

| 维度 | 实现 |
|------|------|
| 渲染模式 | Inline Scrolling（内容随终端原生滚动向上推，非全屏 alternate-screen） |
| 渲染引擎 | `mizchi/tui` VNode 渲染（`lib/tui/vnode_renderer.mbt`，经 `app.render_frame(node)` 输出） |
| 终端底层 | `moonbit-community/tty`（raw mode、按键事件、终端能力探测） |
| 状态管理 | `mizchi/signals` 响应式 Signal |
| 布局 | `lib/tui/brand_layout.mbt`：状态栏置顶，圆角框输入区置底 |
| 编码处理 | Windows 控制台 codepage 由 `lib/tui/console_cp_native.c` stub 处理 |

### 关键决策：保留 Inline Scrolling

与基准 OpenClacky（全屏分屏、状态栏底部、无框输入区）的根本架构差异是**有意为之**：

- 2026-07-01 `tui-inline-migration` spec 主动迁向 inline 架构；
- 2026-07-28 `tui-parity-08-render-architecture-decision` 复审后维持选项 A（inline），不做二次大改。

由此产生的已知外观差异（状态栏位置、输入框形态、滚动行为）视为设计差异而非缺陷。

## 演进历史

1. **2026-07-01**：自研全屏渲染迁移至 inline scrolling。
2. **2026-07-28**：渲染层重构为 mizchi/tui VNode 基础（Phase 1-4 完成），旧自研 renderer（`node.mbt`、`state.mbt` 等）保留兼容部分，新增 `vnode_renderer.mbt` 为主渲染路径。
3. **两轮 parity 修复**（specs 均已归档至 `specs/completed/`）：
   - 2026-07-21 tui-parity-01~05：命令可用性、欢迎页/状态栏、配置/模型弹窗、消息展示、高级交互；
   - 2026-07-28 tui-parity-01~08：状态栏截断修复与内容对齐、斜杠命令单次 Enter 执行、欢迎 banner / 输入区 / 帮助与命令集对齐、窄屏自适应、渲染架构决策。

原对比测试报告中的 5 项 bug（状态栏截断、窄屏不响应、斜杠命令需两次 Enter、配置菜单窄屏裁剪、颜色不一致）均已在 2026-07-28 批次修复。

## 测试与评估

```bash
moon build --target native --release cmd          # 构建（须显式指定 cmd，规避 moon#1488）
./_build/native/debug/build/cmd/cmd.exe            # 推荐直接运行 exe 进入 TUI
cmd.exe --tui-eval test/scenarios/tui/             # TUI eval 场景回归
```

注意：`moon test --target wasm-gc` 会因 `tty`/`crescent` 的 FFI 失败，用 `moon check` 验证类型即可。
