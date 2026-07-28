# TUI 滚动体验增强 · 增量 Spec

> **创建日期**: 2026-07-28  
> **状态**: 已完成  
> **关联总览**: `docs/tui-redesign-goal.md`（Phase 3 视口虚拟化）  
> **关联历史 spec**: 无  
> **来源差距**: 验收审计 — "视口虚拟化未实现"（经代码验证后修正为"滚动 UX 不完整"）  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

TUI 重构验收审计声称"视口虚拟化未实现"。经代码验证，**数据层已具备视口虚拟化能力**（`output_buffer.mbt` 的 `cached_flat_lines` + `tail_lines_with_scroll()` 实现 O(viewport) 读取），但 **UI 层滚动体验不完整**：

1. **无键盘滚动导航**：Page Up/Down、Ctrl+↑/↓ 均无绑定。Home/End 仅控制输入光标，不控制输出滚动。
2. **无滚动位置指示器**：用户滚动后无法感知当前位置（"第 X/Y 行"或进度条）。
3. **鼠标滚动步长固定 3 行**：无 Shift+Scroll 加速、无 Page 级滚动。

**影响**：长对话（1000+ 行）中用户只能用鼠标滚轮逐 3 行翻阅，无法快速跳转，体验远逊于 Claude Code / Gemini CLI。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "视口虚拟化未实现" | `grep "viewport\|virtual\|cached_flat" lib/tui/output_buffer.mbt` | 命中 `cached_flat_lines`(L105)、`tail_lines_with_scroll`(L545)、注释"viewport virtualization"(L103) | **部分否定**：数据层已有，UI 层缺失 |
| "无键盘滚动" | `grep "PageUp\|PageDown\|page_up\|page_down" lib/tui/tui_controller.mbt` | 0 命中 | 确认缺失 |
| "Home/End 不控制滚动" | 读取 `tui_controller.mbt` L918-925 | Home→`input.cursor_home()`、End→`input.cursor_end()` | 确认：仅控制输入光标 |
| "无 Ctrl/Shift+方向键滚动" | `grep "Ctrl.*Up\|Shift.*Up\|Alt.*Up" lib/tui/tui_controller.mbt` | 0 命中 | 确认缺失 |
| "无滚动指示器" | `grep "scroll_indicator\|scroll_bar\|scrollbar\|scroll_pos" lib/tui/*.mbt` | 0 命中 | 确认缺失 |
| "鼠标滚动步长固定" | 读取 `tui_controller_mouse.mbt` L25-38 | `scroll_offset + 3` / `scroll_offset - 3`，无加速逻辑 | 确认 |
| "数据层 O(viewport)" | 读取 `output_buffer.mbt` L539-567 | `tail_lines_with_scroll` 用 cached_flat_lines，注释"O(viewport) instead of O(total_lines)" | 确认已有 |

### 详细分析

**数据层（已就绪）**：

`output_buffer.mbt` 已实现：
- `cached_flat_lines : Array[String]`（L105）：懒重建的扁平行缓存
- `cache_version`（L107）：版本号控制缓存失效
- `tail_lines_with_scroll(n, scroll_offset)`（L545）：O(viewport) 窗口读取
- `max_entries = 2000`（L96）：软上限防内存膨胀
- `collapse_threshold = 15`（L110）：长 System 条目自动折叠

**UI 层（缺失）**：

`tui_controller.mbt` 的按键分发（`handle_key` 方法）中：
- 方向键 ↑/↓ 仅用于建议列表导航、历史浏览、光标移动（L910-917）
- Home/End 仅用于输入光标（L918-925）
- 无 Page Up/Down 处理
- 无 Ctrl/Shift+方向键处理

`tui_controller_mouse.mbt` 的鼠标处理：
- Scroll Up/Down 固定 ±3 行（L25-38）
- 无 Shift+Scroll 加速
- 点击空白区域重置滚动到底部（L65-66）

`tui_controller_vnode.mbt` 的 VNode 构建：
- L38 传递 `self.scroll_offset` 给 `tail_lines_with_scroll`
- 无滚动指示器 VNode

## 决策 [必填 - 含为什么]

1. **不新建视口组件，在现有 controller 上增强**：数据层 `tail_lines_with_scroll` 已提供 O(viewport) 读取，无需引入新的 Viewport 抽象。在 `handle_key` 中增加滚动按键绑定即可。这避免了不必要的架构变更，保持改动最小化。

2. **滚动指示器放在 status_bar 而非独立组件**：status_bar.mbt 已存在且每帧渲染，追加一个 `↑ X/Y` 段成本最低（~10 行），无需新建 VNode 组件。当 `scroll_offset == 0` 时隐藏，避免视觉噪音。

3. **鼠标滚动增加 Shift 加速**：Shift+Scroll 步长改为半屏（`term_height / 2`），普通 Scroll 保持 3 行。这是终端 TUI 的常见约定（vim、less）。

4. **Page Up/Down 步长为 `term_height - 2`**：保留 2 行重叠，与 less/vim 行为一致，避免用户丢失上下文。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及动态加载 trait，纯编译期代码。✓
- crescent 路由：不涉及。✓
- FFI：不涉及 C 库。✓
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/tui_controller.mbt` | 修改 | `handle_key` 增加 PageUp/PageDown/Ctrl+↑/Ctrl+↓ 滚动绑定 |
| `lib/tui/tui_controller_mouse.mbt` | 修改 | Shift+Scroll 半屏加速 |
| `lib/tui/status_bar.mbt` | 修改 | 追加滚动位置指示段 `↑ X/Y` |
| `lib/tui/tui_controller_vnode.mbt` | 修改 | 传递 scroll_offset + total_lines 给 status_bar |

### 不涉及文件

- `lib/tui/output_buffer.mbt`：数据层已就绪，不改
- `lib/tui/vnode_renderer.mbt`：渲染管线不变
- `lib/agent/*`：agent 接口不变
- `lib/web/*`：Web 端不受影响

## 实施计划 [必填]

### 任务包 1：键盘滚动导航（预估 0.5 天）

- 在 `tui_controller.mbt` 的 `handle_key` 中增加：
  - `PageUp` → `scroll_offset += (term_height - 2)`，clamp 到 `[0, max_offset]`
  - `PageDown` → `scroll_offset -= (term_height - 2)`，clamp 到 `[0, max_offset]`
  - `Ctrl+Up` → `scroll_offset += 1`（单行精确滚动）
  - `Ctrl+Down` → `scroll_offset -= 1`
- 需要确认 `@tty/input` 是否提供 PageUp/PageDown/Ctrl+Arrow 按键事件（`grep "PageUp\|PageDown" .mooncakes/moonbit-community/tty/`）
- 若 tty 不提供，需在 `handle_key` 中匹配原始转义序列 `\x1b[5~`（PageUp）、`\x1b[6~`（PageDown）

### 任务包 2：鼠标滚动加速（预估 0.25 天）

- 在 `tui_controller_mouse.mbt` 的 `Scroll` 分支中：
  - 检测 `ev.modifiers` 是否包含 Shift
  - Shift+ScrollUp → `scroll_offset += term_height / 2`
  - Shift+ScrollDown → `scroll_offset -= term_height / 2`
  - 普通 Scroll 保持 ±3

### 任务包 3：滚动位置指示器（预估 0.25 天）

- 在 `status_bar.mbt` 中增加 `scroll_segment(scroll_offset, total_lines, viewport_height)` 函数
- 当 `scroll_offset > 0` 时显示 `↑ {offset}/{total}`
- 当 `scroll_offset == 0` 时返回空字符串（不占位）
- 在 `tui_controller_vnode.mbt` 构建 status_bar 时传入 scroll 参数

## 验收标准 [必填]

- [ ] Page Up/Down 可翻页滚动输出区域
- [ ] Ctrl+↑/↓ 可单行精确滚动
- [ ] Shift+鼠标滚轮半屏加速滚动
- [ ] 滚动时 status_bar 显示 `↑ X/Y` 位置指示
- [ ] 滚回底部（scroll_offset=0）时指示器消失
- [ ] 滚动不影响输入区域操作（Home/End 仍控制光标）
- [ ] 现有 41 个 tui-eval 场景全部通过
- [ ] `moon check` 0 errors（lib/tui）
- [ ] `moon test lib/tui` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| `@tty/input` 不提供 PageUp/PageDown 事件 | 中 | 回退到原始转义序列匹配（`\x1b[5~`/`\x1b[6~`），在 handle_key 的 fallback 分支处理 |
| Ctrl+Arrow 与终端快捷键冲突 | 低 | 部分终端拦截 Ctrl+↑/↓；文档注明备选键位，不阻塞主流程 |
| 滚动指示器在窄终端下挤占空间 | 低 | 当 `term_width < 40` 时隐藏指示器 |

## 依赖关系 [必填]

- **前置依赖**：无（数据层 `tail_lines_with_scroll` 已就绪）
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-28 | 初始版本 | 验收审计发现"视口虚拟化未实现"，经代码验证修正为"滚动 UX 不完整" |
| 2026-07-28 | 对抗性审核 | 经代码验证，所有声明正确，文件存在，无过度工程，模板完整 |
