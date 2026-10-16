# TUI 架构与对齐状态

> 更新日期：2026-10-14

## 当前架构

| 维度 | 实现 |
|---|---|
| 渲染模式 | Inline Scrolling + `commit-scrollback`，内容进入终端原生 scrollback，不占 alternate-screen |
| 渲染引擎 | `lib/tui/tui_controller_render.mbt` 自研行级重绘：行数组公共前缀 diff，仅改变化行 |
| 终端底层 | `moonbit-community/tty`（raw mode、按键事件、终端能力） |
| 状态管理 | `mizchi/signals` Signal |
| 布局 | 输出区 + 底部固定区：状态栏、无框输入区、附件、建议、tips |
| Windows 编码 | `console_cp_native.c` 处理控制台 codepage；不是产品功能 stub |

## 与 openclacky 的对齐

上游 ui2 v1.5.4 也是 inline 架构。已对齐：

- 状态栏置底、输入区无框、todo 自动显隐、tips 行；
- commit-scrollback 滚动模型；
- `/exit`、`/quit`、`/help`、`/config`、`/model`、`/clear`、`/undo` 和动态 Skill 命令；
- `/theme` 为本项目扩展；`/config key value` 直改已移除。

仍有的有意差异：

- `?` 不触发 `/help`；
- `/undo` 打开任务历史做 undo/redo，不做上游所有分支；
- TUI 直接消费引擎 `HookEvent`，不绑定 Web/CLI 使用的 wire 词表（见 ADR-0001）。

命令集以 `lib/tui/slash_commands.mbt` 的 `SlashCommandParser::new()` 为准。

## 演进结论

1. 早期全屏 VNode 渲染与 commit-scrollback 的物理滚动冲突，已改行级重绘。
2. 2026-08 的布局和命令对齐批次已完成，历史 spec 在 `specs/completed/`。
3. 旧 `scroll_offset` 视口回滚和鼠标捕获不再使用。

## 测试与评估

```bash
moon build --target native --release cmd
BIN=./_build/native/release/build/cmd/cmd.exe
"$BIN"                                  # 进入 TUI
"$BIN" eval --tui test/scenarios/tui/ --format markdown
```

`--tui-eval` 是旧顶层旗标，只作兼容；新命令统一走 `eval`。TUI 场景与 Journey 的 TUI 旅程互补：前者验单步渲染，后者验真实用户链路。

`moon test --target wasm-gc` 因 tty/crescent FFI 不可用，wasm-gc 用 `moon check` 验证。
