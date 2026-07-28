# TUI 一致性 Spec 总览（MBOpenClacky ↔ OpenClacky）

> **创建日期**: 2026-07-28
> **状态**: 讨论中（全部位于 `specs/draft/`，待对抗性审核）
> **来源**: `docs/tui-comparison-test-report.md`（5 个 BUG + 20+ 个 DIFF + 1 个根本架构差异）
> **方法论**: `specs/decisions/harness-methodology-v2-upgrade.md`（Gap-to-Spec 强制代码验证）

## 一、Spec 清单

| # | 文件 | 优先级 | 核心问题 | 主要文件 |
|---|------|--------|---------|---------|
| 01 | `…-01-statusbar-render-fix.md` ✅已完成 | **P1** | 状态栏文字被系统性截断（BUG-001）；澄清 BUG-005 → 已归档 `specs/completed/` | `brand_layout.mbt`、`tui_controller_vnode.mbt`、`vnode_renderer.mbt` |
| 02 | `…-02-statusbar-content-align.md` ✅已完成 | P2 | 状态栏分隔符/字段/花费格式对齐（DIFF-02~06）；已归档 `specs/completed/` | `status_bar.mbt`、`tui_wbtest.mbt`、`thinking_view_wbtest.mbt` |
| 03 | `…-03-slash-command-single-enter.md` ✅已完成 | P2 | 斜杠命令需双击 Enter（BUG-003）；已归档 `specs/completed/` | `tui_controller.mbt`、`tui_input_nav_wbtest.mbt` |
| 04 | `…-04-welcome-banner-align.md` ✅已完成 | P3 | 横幅/标语/提示/Agent 面板对齐（DIFF-07~14） | `banner.mbt` |
| 05 | `…-05-input-area-align.md` ✅已完成 | P3 | 输入区提示符/占位符（DIFF-15~17） | `input_area.mbt`、`brand_layout.mbt` |
| 06 | `…-06-help-and-command-set.md` ✅已完成 | P3 | `/help` 呈现 + 命令集（DIFF-18~20） | `slash_commands.mbt`、`dialog.mbt` |
| 07 | `…-07-narrow-width-adaptation.md` ✅已完成 | P2 | 窄终端宽度自适应（BUG-002 + BUG-004）；已归档 `specs/completed/` | `status_bar.mbt`、`dialog_config_menu.mbt` |
| 08 | `…-08-render-architecture-decision.md` ✅已决策 | 探索 | 全屏分屏 vs Inline Scrolling 架构决策（选项 A：保留 inline scrolling） | （决策文档，约束 05/影响 01/02/07） |

## 二、依赖链与建议实施顺序

```
SPEC-08（架构决策，并行推进，不阻塞修复）
   │ 约束
   ▼
SPEC-01（P1 渲染修复）──► SPEC-02（内容格式对齐）──► SPEC-07（窄屏自适应）
                                                          ▲
SPEC-03（P2 单击 Enter，独立）                              │ 复用宽度钳制
SPEC-04（P3 欢迎区，独立）                                  │
SPEC-05（P3 输入区，任务包2 依赖 08）                  SPEC-06（P3 /help，任务包2 协同 07）
```

建议顺序：**01 → 03 → 02 → 07 → 04 → 05 → 06**，SPEC-08 作为并行决策轨道。

## 三、Gap 验证中被证伪/修正的声称（Harness v2 纪律）

| 原声称（来自对比报告） | 验证结论 | 处理 |
|----------------------|---------|------|
| BUG-005：`colored_text()` 是死代码、存在两条颜色路径 | **证伪**：`tui_controller_vnode.mbt:36/152` 调用它；终端 256 色是 mizchi/tui 把 `rgb()` 降频输出 | 不修复，仅在 SPEC-01 记录结论 |
| DIFF-17：MB 缺粘贴功能 | **证伪**：MB 已实现与 OC 同款 `[#N Paste Text]` 占位符机制（`line_editor.mbt:542`、`state.mbt:280-377`） | 真实缺口仅 `/help` 未列粘贴项，归 SPEC-06 |
| DIFF-19：MB 命令集与 OC 不一致（暗示缺失） | **修正**：MB 12 命令是 OC 7 命令的**超集**，多出 `/new /todo /skills /meeting /theme` 且有实现支撑 | SPEC-06 决策保留扩展，不删除 |
| DIFF-04：状态栏会话 ID 格式问题 | **修正**：状态栏仅 `session_id[0:8]` 截取，`s_` 前缀源于会话 ID 生成模块（TUI 之外） | SPEC-02 标注跨模块边界 |
| DIFF-06：颜色深度差异是 bug | **修正**：属 mizchi/tui 输出编码，功能正常 | SPEC-02 列为范围外信息项 |

## 四、当前状态

所有 spec 已完成或已决策：
- **SPEC-01/02/03/07**：已归档 `specs/completed/`
- **SPEC-04/05/06**：已实施，待归档到 `specs/completed/`
- **SPEC-08**：已决策（选项 A：保留 inline scrolling）

## 五、下一步

1. 将 SPEC-04/05/06/08 从 `specs/active/` 移入 `specs/completed/`
2. 可选：运行 TUI eval 场景验证（`moon build --target native --release cmd` → `cmd.exe --tui-eval test/scenarios/tui/`）
3. 可选：整理变更日志、提交代码
