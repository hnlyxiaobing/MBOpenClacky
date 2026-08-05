# TUI 架构与对齐状态

> 更新日期：2026-08-05
> 本文档合并了原 `tui-redesign-goal.md`、`tui-redesign-mizchi-foundation-2026-07-28.md`、`tui-comparison-test-report.md` 中仍有效的内容。

## 当前架构

| 维度 | 实现 |
|------|------|
| 渲染模式 | Inline Scrolling + **commit-scrollback**（内容随终端原生滚动向上推，非全屏 alternate-screen；输出溢出时旧行打印真实换行推入终端 scrollback，用户用终端原生滚动回看） |
| 渲染引擎 | `mizchi/tui` VNode 渲染（`lib/tui/vnode_renderer.mbt`，经 `app.render_frame(node)` 输出） |
| 终端底层 | `moonbit-community/tty`（raw mode、按键事件、终端能力探测） |
| 状态管理 | `mizchi/signals` 响应式 Signal |
| 布局 | `lib/tui/brand_layout.mbt`：单一布局，输出区 flex + 底部固定区（状态栏置底=输入区上方、分隔线形态无框输入区、附件行、建议、tips 行）；对齐 openclacky ui2 v1.5.4 |
| 编码处理 | Windows 控制台 codepage 由 `lib/tui/console_cp_native.c` stub 处理 |

### 关键决策：布局向原版完全对齐（2026-08-04 修订，2026-08-05 实施完成）

- 2026-07-01 `tui-inline-migration` spec 主动迁向 inline 架构；2026-07-28 `tui-parity-08` 维持选项 A（inline）。
- **2026-08-04 决策反转**：经对 v1.5.4 原版代码复核，默认 ui2 同为 inline + 终端原生 scrollback（`ui2/layout_manager.rb:238-267`），此前"原版是全屏分屏"的前提不成立；状态栏置顶、圆角输入框、视口回滚并非 inline 架构的必然特征。用户明确要求布局与原版完全对齐，tui-parity-08 中"保留可见差异"的结论作废（详见 `specs/completed/2026-08-04_tui-full-align-00-overview.md` 第〇节）。
- 由此产生的已知外观差异（状态栏位置、输入框形态、滚动行为、todo 显隐、tips 行）**不再视为设计差异**，按 `specs/completed/2026-08-04_tui-full-align-01-layout-align.md` 对齐：状态栏移至输入区上方、输入区去边框、滚动改为 commit-scrollback（终端原生滚动）、todo 自动显隐、补 tips 行。
- **2026-08-05 实施完成**（SPEC-01/02/03 全量验收通过，归档至 `specs/completed/`）：布局、命令语义、扩展取舍三批对齐已落地；见 `specs/completed/2026-08-04_tui-full-align-0{1,2,3}-*.md`。

## 演进历史

1. **2026-07-01**：自研全屏渲染迁移至 inline scrolling。
2. **2026-07-28**：渲染层重构为 mizchi/tui VNode 基础（Phase 1-4 完成），旧自研 renderer（`node.mbt`、`state.mbt` 等）保留兼容部分，新增 `vnode_renderer.mbt` 为主渲染路径。
3. **两轮 parity 修复**（specs 均已归档至 `specs/completed/`）：
   - 2026-07-21 tui-parity-01~05：命令可用性、欢迎页/状态栏、配置/模型弹窗、消息展示、高级交互；
   - 2026-07-28 tui-parity-01~08：状态栏截断修复与内容对齐、斜杠命令单次 Enter 执行、欢迎 banner / 输入区 / 帮助与命令集对齐、窄屏自适应、渲染架构决策。
4. **2026-08-04/05 全面对齐批次**（`specs/completed/2026-08-04_tui-full-align-00~03`）：
   - 布局对齐：状态栏置底（输入区上方）、无框输入区、commit-scrollback 滚动模型、todo 自动显隐、tips 行；废弃 `scroll_offset` 视口回滚、退役鼠标捕获。
   - 命令语义对齐：`/clear` 新会话语境、`/undo` 交互菜单 + redo、`/model` 两级抽屉 + 持久化、`/config` 连接测试 + 摘要、`?` = `/help`、技能动态斜杠命令。
   - 扩展取舍：删除 `/new` `/todo` `/meeting` `/skills`、`/config key value`、文件浏览 + shell 模式、ClaudeCodeLike/Compact 模板；保留 `/theme`、Ctrl+Y、GFM 表格、输出折叠、上下文建议、Ctrl+L、`--tui-eval`。

原对比测试报告中的 5 项 bug（状态栏截断、窄屏不响应、斜杠命令需两次 Enter、配置菜单窄屏裁剪、颜色不一致）均已在 2026-07-28 批次修复。

## 测试与评估

```bash
moon build --target native --release cmd          # 构建（须显式指定 cmd，规避 moon#1488）
./_build/native/debug/build/cmd/cmd.exe            # 推荐直接运行 exe 进入 TUI
cmd.exe --tui-eval test/scenarios/tui/             # TUI eval 场景回归（当前 46/46）
```

注意：`moon test --target wasm-gc` 会因 `tty`/`crescent` 的 FFI 失败，用 `moon check` 验证类型即可。
