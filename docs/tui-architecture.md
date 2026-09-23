# TUI 架构与对齐状态

> 更新日期：2026-09-21

## 当前架构

| 维度 | 实现 |
|------|------|
| 渲染模式 | Inline Scrolling + **commit-scrollback**（内容随终端原生滚动向上推，非全屏 alternate-screen） |
| 渲染引擎 | 自研行级重绘（`lib/tui/tui_controller_render.mbt`）：输出区组装为行数组后与 `painted_body` 做公共前缀 diff，仅重写变化行（`ESC[row;1H` + `ESC[2K` 清行直写 tty）；`mizchi/tui` 仅保留 `core` 宽度测量 |
| 终端底层 | `moonbit-community/tty`（raw mode、按键事件、终端能力探测） |
| 状态管理 | `mizchi/signals` 响应式 Signal |
| 布局 | 输出区 + 底部固定区（状态栏置底=输入区上方、无框输入区、附件行、建议、tips 行）；对齐 openclacky ui2 v1.5.4 |
| 编码处理 | Windows 控制台 codepage 由 `lib/tui/console_cp_native.c` stub 处理 |

## 与原版 openclacky 的对齐状态

两者都是 **inline 架构**（内容推入终端 scrollback，不占 alternate-screen 全屏）。原版 v1.5.4 的 ui2 默认即为 inline（`ui2/layout_manager.rb:238-267`）。

### 布局对齐（已完成 2026-08-05）

状态栏置底（输入区上方）、无框输入区、commit-scrollback 滚动模型、todo 自动显隐、tips 行；废弃 `scroll_offset` 视口回滚、退役鼠标捕获。

### 命令语义对比

> 命令集以 `lib/tui/slash_commands.mbt` 的 `SlashCommandParser::new()` 为准（下表已按实际代码核对）。

| 命令 | 原版 (ui2) | MB | 一致性 | 说明 |
|------|:--:|:--:|:--:|------|
| `/exit` `/quit` | ✅ | ✅ | ✅ 一致 | — |
| `/help` | ✅ | ✅ | ✅ 一致 | MB 附快捷键表并列出技能命令 |
| `/config` | ✅ | ✅ | ✅ 一致 | 均为菜单式；MB 的 `/config key value` 直改已按 SPEC-03 移除（带参报用法错误） |
| `/model` | ✅ | ✅ | ✅ 一致 | 带参切换 + 持久化；原版为两级抽屉 |
| `/clear` | ✅ | ✅ | ✅ 一致 | 均为新建会话（新 session_id） |
| `/undo` | ✅ | ✅ | ⚠️ 基本一致 | 均打开任务历史做 undo/redo；原版另有分支 |
| `/theme` | ❌ | ✅ | — | MB 运行时切主题；原版仅启动参数 |
| 技能动态 `/xxx` | ✅ | ✅ | ✅ 一致 | 用户可调用技能注册为斜杠命令（对齐 Ruby `skills_by_command`） |
| `?` 触发帮助 | ✅ | ❌ | — | 原版输入 `?` 触发 `/help`；MB 未实现 |

### 命令扩展取舍（2026-08-05 决策）

删除 `/new` `/todo` `/meeting` `/skills`、`/config key value`、文件浏览 + shell 模式、ClaudeCodeLike/Compact 模板；保留 `/theme`、Ctrl+Y、GFM 表格、输出折叠、上下文建议、Ctrl+L、`--tui-eval`。

## 演进历史

1. **2026-07-01**：自研全屏渲染迁移至 inline scrolling。
2. **2026-07-28**：渲染层重构为 mizchi/tui VNode 基础，两轮 parity 修复完成（tui-parity-01~08）。
3. **2026-08-04/05 全面对齐批次**：布局、命令语义、扩展取舍三批对齐落地，归档至 `specs/completed/`。
4. **2026-08-05 渲染层再重构**：废弃 VNode 渲染（坐标 diff 与 commit-scrollback 物理滚动本质冲突，BUG-004），改为自研行级重绘 + `screen_lines.mbt` 行模型原语。

## 测试与评估

```bash
moon build --target native --release cmd          # 构建（须显式指定 cmd，规避 moon#1488）
./_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe   # 推荐直接运行 exe 进入 TUI
cmd.exe eval --tui test/scenarios/tui/            # TUI eval 场景回归（统一入口，--format text|json|markdown）
cmd.exe --tui-eval test/scenarios/tui/            # 旧顶层旗标，仍可用（报告落 logs/）
```

注意：`moon test --target wasm-gc` 会因 `tty`/`crescent` 的 FFI 失败，用 `moon check` 验证类型即可。
