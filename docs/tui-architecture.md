# TUI 架构与对齐状态

> 更新日期：2026-08-11

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

| 命令 | 原版 (ui2) | MB | 一致性 | 关键差异 |
|------|:--:|:--:|:--:|------|
| `/exit` `/quit` | ✅ | ✅ | ✅ 一致 | — |
| `/help` | ✅ | ✅ | ✅ 一致 | 内容随命令集不同；MB 多快捷键表 |
| `/config` | ✅ | ✅ | ⚠️ 基本一致 | MB 多 `key=value` 直改；原版多连接测试、配置摘要 |
| `/model` | ✅ | ✅ | ⚠️ 部分一致 | MB 带参切换不持久化；原版两级抽屉 + 一律持久化 |
| `/clear` | ✅ | ✅ | ❌ 不同 | 原版 = 新建会话（新 session_id）；MB = 会话内清理 |
| `/undo` | ✅ | ✅ | ❌ 明显不同 | 原版交互菜单 + undo/redo + 分支；MB 直接撤销最后任务 |
| `/new` | ❌ | ✅ | — | MB 新增，原版由 `/clear` 承担 |
| `/todo` | ❌ | ✅ | — | MB 新增，原版 todo 自动显隐 |
| `/theme` | ❌ | ✅ | — | MB 运行时切主题；原版仅启动参数 |
| 技能动态 `/xxx` | ✅ | ❌ | — | 原版 SkillLoader 动态注册；MB 缺此机制 |
| `?` 触发帮助 | ✅ | ❌ | — | 原版输入 `?` 触发 `/help` |

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
./_build/native/debug/build/cmd/cmd.exe            # 推荐直接运行 exe 进入 TUI
cmd.exe --tui-eval test/scenarios/tui/             # TUI eval 场景回归（当前 47/47）
```

注意：`moon test --target wasm-gc` 会因 `tty`/`crescent` 的 FFI 失败，用 `moon check` 验证类型即可。
