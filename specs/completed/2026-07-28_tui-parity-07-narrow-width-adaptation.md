# TUI 窄终端宽度自适应 · 增量 Spec

> **创建日期**: 2026-07-28
> **状态**: 已完成
> **关联总览**: `docs/tui-comparison-test-report.md`
> **关联历史 spec**: `specs/draft/2026-07-28_tui-parity-01-statusbar-render-fix.md`、`specs/draft/2026-07-28_tui-parity-02-statusbar-content-align.md`
> **来源差距**: BUG-002（状态栏窄屏溢出裁剪，P2）、BUG-004（配置菜单窄屏边框裁剪/不换行，P3）
> **依赖**: SPEC-01（渲染修复）、SPEC-02（字段集对齐后再做宽度预算）
> **灰度 key**: 无

## 问题描述 [必填]

在窄终端（80×24）下：

1. **状态栏（BUG-002）**：整行溢出右边界被硬裁剪，目录不缩短，行尾断开，**花费字段完全丢失**：
   ```
   ● id |s_178524 |/mnt/d/MoonBit/MBOpenClacky confirm_safes |qwen3.7-plus |0 tas |
   ```
2. **配置菜单（BUG-004）**：圆角框右上角 `╮` 被裁掉，框内 profile 文本顶到右边界不换行。

基准 OpenClacky 的状态栏在窄屏下能适配宽度。MBOpenClacky 缺乏宽度自适应逻辑。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 状态栏窄屏溢出裁剪、花费丢失 | 实测 `resize-pane -x 80 -y 24` + `capture-pane` | 行尾 `… \|0 tas \|` 后断开，无 `$0.0000` | **确认** |
| 状态栏格式化无宽度参数 | `file_reader lib/tui/status_bar.mbt`（`format_from_state`） | 函数签名 `(self, state)`，无 `width`；固定 push 全部字段；`truncate_dir(_, 30)`/`truncate_model(_, 24)` 为固定上限，与终端宽无关 | **确认**：无宽度自适应 |
| 配置菜单窄屏裁剪 | 实测 80×24 打开 `/config` | 顶边 `╭──…` 无右上 `╮`，profile 行顶格不换行 | **确认** |
| 对话框宽度来源 | `glob/grep lib/tui/dialog_config_menu.mbt`、`dialog.mbt` | 对话框存在独立渲染（`dialog_config_menu.mbt`），未见他处传入终端宽做钳制 | **确认**：需补宽度钳制/换行 |

### 详细分析

- 状态栏：`format_from_state` 不感知终端宽度，始终产出约 118 列的完整行；`truncate_dir(30)`/`truncate_model(24)` 是固定字符上限，无法在 80 列下让整行 fit。需引入"按宽度预算渐进降级"。
- 对话框：`dialog_config_menu.mbt` 渲染未以 `term_width` 钳制总宽，导致窄屏下边框/内容越界。
- 两处共享同一主题"渲染需感知终端宽度并自适应"，但分属不同文件，分两个任务包。

## 决策 [必填 - 含为什么]

1. **状态栏引入宽度预算与字段降级顺序**：因为固定字段集无法适配任意宽度。把 `term_width` 传入状态栏格式化，按优先级保留字段：状态 > 模型 > 花费 > 权限 > 任务 > 目录 > 会话；宽度不足时先压缩目录（更激进的 `truncate_dir`）、再依次省略低优先级字段，保证关键字段（状态/模型/花费）最后才被裁。
2. **目录优先压缩而非直接丢弃**：因为目录常很长且信息密度低，先缩短目录能在多数窄屏下保住其它字段。
3. **对话框宽度 = `min(term_width - 边距, 内容上限)`，内容超宽换行/截断**：因为对话框越界裁剪是观感破损的直接原因；钳制总宽并保证四角完整、长行换行。
4. **复用 `cjk_width.mbt` 的宽度计算**：因为它已委托 `@tui_core.char_display_width` 做 Unicode 感知宽度测量，降级/换行应基于显示列宽而非字节/字符数。

<!-- MoonBit 约束检查：不涉及 AOT/crescent/FFI/vendored。宽度计算复用现有 cjk_width（基于 @tui_core）。 -->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/status_bar.mbt` | 修改 | `format_from_state` 增加 `width` 参数与字段降级逻辑；`truncate_dir` 支持按剩余预算动态缩短 |
| `lib/tui/tui_controller_vnode.mbt` | 修改 | 调用状态栏格式化时传入 `self.term_width` |
| `lib/tui/dialog_config_menu.mbt` | 修改 | 对话框总宽按 `term_width` 钳制；长行换行/截断；保证边框四角完整 |
| `lib/tui/dialog.mbt` | 可能修改 | 若对话框边框渲染需通用宽度钳制 |
| 相关 wbtest | 修改/新增 | 80 列下状态栏含关键字段、对话框四角完整的断言 |

### 不涉及文件

- 状态栏字段集合（由 SPEC-02 决定，本 spec 在其基础上做宽度预算）。
- 渲染截断 bug（SPEC-01 负责）。

## 实施计划 [必填]

### 任务包 1：状态栏宽度自适应（预估 0.5 天）
- `format_from_state(self, state, width)`：估算各段显示列宽，按降级顺序裁剪至 fit。
- `tui_controller_vnode.mbt` 传入 `term_width`。
- 测试 150/120/100/80/60 列下关键字段保留情况。

### 任务包 2：对话框宽度自适应（预估 0.5 天）
- `dialog_config_menu.mbt` 总宽钳制 + 内容换行；窄屏下四角完整。
- 与 SPEC-06 任务包 2（/help 对话框）共享宽度钳制思路。

## 验收标准 [必填]

- [x] 80×24 下状态栏不溢出，状态/模型/花费关键字段可见
- [x] 极窄（60 列）下优雅降级（至少状态 + 花费），不出现断裂残行
- [x] 80×24 下配置菜单边框四角完整、长行换行
- [x] 宽屏（150 列）下显示不回归（与 SPEC-02 对齐后的完整字段一致）
- [x] `moon check` 0 errors（`lib/tui`）
- [x] `moon test lib/tui` 通过（301 tests, 0 failed）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 降级顺序取舍争议 | 低 | 按"状态>模型>花费>权限>任务>目录>会话"默认序，可评审调整 |
| 宽度测量与渲染不一致导致仍裁剪 | 中 | 统一用 `cjk_width`/`@tui_core` 显示列宽；多宽度实测 |
| 依赖 SPEC-01/02 未完成 | 中 | 排在其后实施 |

## 依赖关系 [必填]

- **前置依赖**：SPEC-01（渲染修复）、SPEC-02（字段集对齐）
- **后置依赖**：SPEC-06 任务包 2（/help 对话框）可复用本 spec 的宽度钳制

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-28 | 初始版本 | 由对比报告 BUG-002、BUG-004 转化，合并为"宽度自适应"主题 |
| 2026-07-28 | 任务包1完成：`status_bar.mbt` 新增 `display_width`、`truncate_dir_to_width`、`format_from_state_adaptive`；`tui_controller_vnode.mbt` 调用自适应版本；4个回归测试 | 状态栏宽度自适应 |
| 2026-07-28 | 任务包2完成：`dialog_config_menu.mbt` 新增 `truncate_to_display_width`，`render_config_menu` 增加 `term_width~` 默认参数，标签截断+窄屏提示精简；4个回归测试 | 配置菜单宽度自适应 |
| 2026-07-28 | 实测验证：150列全字段、80列关键字段+目录压缩、60列降级、50列菜单截断+提示精简 | 全部验收通过 |
