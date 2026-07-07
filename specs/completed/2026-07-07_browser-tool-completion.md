# 浏览器工具完善（70% → 100%） · 增量 Spec

> **创建日期**: 2026-07-07  
> **状态**: 已完成  
> **关联历史 spec**: 无（首次浏览器工具 spec）  
> **灰度 key**: 无

## 问题描述

浏览器工具当前完成度约 70%，核心交互（open、navigate、snapshot、act、screenshot、tabs、focus、close、status）已可通过 MCP（browser-use）服务器运行，但以下三方面仍存在缺口：

1. **表单交互缺乏客户端增强**：drag、scroll、wait 已作为 act kind 委托给 MCP 服务器，但客户端缺乏本地增强逻辑——scroll 仅通过 `evaluate_script` 执行 JS 而非原生 MCP 工具；fill 没有 focus/blur 事件增强，部分前端框架无法正确感知输入。
2. **截图管道功能单一**：`format_screenshot_result()` 仅支持 PNG 格式，缺少 format（jpeg/png）、quality、自定义 savePath、maxWidth/maxHeight 参数，无法满足不同输出场景。
3. **快照压缩缺乏智能阈值**：`compress_snapshot()` 已实现两段式压缩（去噪 + 合并 StaticText），但总是无条件执行，缺少基于输出大小的阈值判断（150KB），也缺少压缩日志记录。

## 现状分析

### 核心架构（MCP-based）

- 通信方式：**MCP stdio JSON-RPC 2.0**，连接到 "browser-use" MCP 服务器守护进程
- 无直接 CDP 调用，所有浏览器操作通过 `Browser::mcp_call()` / `Browser::with_page()` 委托给 MCP
- `Browser` struct 管理 MCP 连接状态和页面缓存（`PageCache`）
- Action 通过字符串 match 分发，act kind 通过 `dispatch_act()` 路由到对应 MCP 工具

### 现有文件结构

| 文件 | 行数 | 职责 |
|------|------|------|
| `browser.mbt` | 542 | 核心：Browser struct、Tool trait、execute 分发、MCP 调用、配置检查、参数 schema |
| `browser_action.mbt` | 184 | act kind 分发（dispatch_act）、scroll 原生 MCP+回退、fill focus/blur 增强、escape_js_string |
| `browser_mcp_args.mbt` | ~300 | 各 MCP 工具的参数构建（build_mcp_*_args），新增 scroll/screenshot 参数构建 |
| `browser_page.mbt` | 149 | 页面缓存、错误恢复、with_page 自动重试、页面就绪轮询 |
| `browser_screenshot.mbt` | ~200 | 截图管道：base64 提取、PNG/JPEG 保存、format/quality/savePath 支持 |
| `browser_snapshot.mbt` | ~260 | 快照处理：两段式压缩、150KB 阈值门控、三阶段压缩日志、查询窗口分页、截断 |
| `browser_wbtest.mbt` | 新建 | 18+ 个白盒测试覆盖三个任务包 |

### 已实现的 act kind

click, dblclick, type, fill, press, hover, drag, select, scroll, wait, evaluate, click_at

### 各 act kind 当前 MCP 映射

| act kind | MCP 工具 | 备注 |
|----------|----------|------|
| click | click | 直接委托 |
| dblclick | click（+dblClick flag） | 增强参数 |
| type/fill | fill | type 是 fill 的别名 |
| press | press_key | 直接委托 |
| hover | hover | 直接委托 |
| drag | drag | 直接委托，需要 ref + target_ref |
| select | select_option | 直接委托 |
| **scroll** | **scroll_page**（回退 evaluate_script） | 优先原生 MCP 工具，失败时回退 JS scrollBy |
| wait | wait_for | 直接委托 |
| evaluate | evaluate_script | 直接委托 |
| click_at | click_at | 坐标点击 |

### 测试覆盖

- `tool_wbtest.mbt` 包含 5 个浏览器测试：name/category、status action、not_configured error、open missing url、format_call
- `browser_wbtest.mbt`（新建）包含 18+ 个独立浏览器测试：scroll 原生调用/回退、fill 增强/降级、截图格式/保存路径、快照阈值门控/压缩日志、escape_js_string 等

## 决策

1. **scroll 改用原生 MCP 工具而非 evaluate_script**：当前 scroll 通过 `evaluate_script` 执行 `window.scrollBy()` JS 代码，但 browser-use MCP 服务器可能提供原生 scroll 工具（如 `scroll_page`）。改为优先尝试原生工具调用，失败时回退到 evaluate_script。这比纯 JS 注入更可靠，且能触发原生滚动事件。
2. **fill 增强通过前置 evaluate_script 注入 focus/blur**：在调用 MCP `fill` 前，先通过 `evaluate_script` 对目标元素执行 `element.focus()`，fill 完成后再执行 `element.blur()`。这样 React/Vue 等依赖 focus/blur 生命周期事件的框架能正确响应，且不改动 MCP 服务器端。
3. **截图参数扩展通过参数 map 传递，不改 MCP 接口**：`take_screenshot` MCP 工具已支持部分参数（如 format），只需在 `build_mcp_screenshot_args` 中透传 format/quality。savePath 和 maxWidth/maxHeight 在客户端处理。
4. **快照压缩增加阈值门控和日志**：`compress_snapshot()` 当前总是无条件执行。改为先检查原始大小是否超过 `max_snapshot_chars * 19`（约 150KB），未超过则原样返回；超过则执行压缩并记录三阶段大小。这避免了对小快照的不必要处理。
5. **三个任务包串行执行**：虽然代码已拆分到多个 `browser_*.mbt` 文件，但三个任务包之间有共享逻辑（如 Browser struct、MCP 调用），串行执行降低集成风险。逐个任务包验收后再进入下一个。
6. **不修改 MCP 服务器协议**：所有增强在客户端（MoonBit 代码）内完成，不要求 browser-use MCP 服务器做变更。

## 文件组织策略

所有浏览器相关代码统一放在 `lib/tool/` 包下，按职责拆分为 `browser_*.mbt` 文件（同一包内）。

**原则**：不创建 `lib/tool/` 以外的包。新增代码优先放入现有文件；如果某个文件行数过大，按 `browser_<职责>.mbt` 命名新文件（如 `browser_form.mbt` 放表单增强逻辑）。

## 改动范围

- **涉及包**：`lib/tool`（且仅此一个包）
- **涉及文件**：
  - `lib/tool/browser_action.mbt`（任务包 1：scroll 改用原生工具、fill 增强逻辑）
  - `lib/tool/browser_mcp_args.mbt`（任务包 1：scroll 参数构建；任务包 2：截图参数透传）
  - `lib/tool/browser_screenshot.mbt`（任务包 2：format/quality/savePath/maxWidth/maxHeight）
  - `lib/tool/browser_snapshot.mbt`（任务包 3：阈值门控、压缩日志）
  - `lib/tool/browser.mbt`（任务包 1/2：参数 schema 更新、execute 分发调整）
  - `lib/tool/tool_wbtest.mbt`（三个任务包各自的测试用例，或新建 `browser_wbtest.mbt`）
- **不涉及**：
  - browser-use MCP 服务器（不要求服务端变更）
  - `web/js/browser.js`（前端面板不在本次范围）
  - 不引入新的外部依赖
  - 不实现服务端图片处理或二进制压缩
  - 不创建 `lib/tool/` 以外的新包

## 任务包定义

### 任务包 1：表单交互增强

**目标**：scroll 改用原生 MCP 工具，fill 增加 focus/blur 事件增强。

**实现要点**：
- **scroll 改造**：
  - 在 `browser_action.mbt` 的 `dispatch_act` 中，将 `"scroll"` 的映射从 `"evaluate_script"` 改为 `"scroll_page"`（或 MCP 服务器实际提供的滚动工具名）
  - 保留 evaluate_script 作为回退：先尝试原生 scroll_page，失败则回退到 JS scrollBy
  - 在 `browser_mcp_args.mbt` 中新增 `build_mcp_scroll_args`，传递 direction + amount 参数
- **fill 增强**：
  - 在 `browser_action.mbt` 的 `dispatch_act` 中，type/fill 分支增加前置 evaluate_script 调用：`document.querySelector('[data-ref="<ref>"]')?.focus()`
  - fill 完成后追加 blur 调用
  - 如果 evaluate_script 失败（MCP 不支持或元素无法定位），静默降级为直接 fill
- **参数 schema**：
  - scroll 已有 `direction`（up/down/left/right）和 `amount`（默认 300）参数，无需变更
  - fill 无新增参数

**验收标准**：
- [x] `dispatch_act("scroll", ...)` 调用原生 MCP scroll_page 工具（而非 evaluate_script）
- [x] 原生 scroll_page 失败时自动回退到 evaluate_script scrollBy
- [x] `dispatch_act("fill", ...)` 在 fill 前执行 focus()、fill 后执行 blur()
- [x] focus/blur evaluate_script 失败时静默降级，不影响 fill 正常执行
- [x] `browser_wbtest.mbt` 新增至少 4 个测试用例（scroll 原生调用、scroll 回退、fill 增强、fill 降级）
- [x] `moon check` 0 errors
- [x] `moon test lib/tool` 全部通过

### 任务包 2：截图管道完善

**目标**：扩展截图支持 format、quality、savePath、maxWidth/maxHeight 参数，返回结构化结果。

**实现要点**：
- **MCP 参数透传**：
  - 在 `build_mcp_screenshot_args` 中新增 format（"jpeg"/"png"，默认 "png"）和 quality（0-100，仅 jpeg 生效）参数传递
  - 不新增 MCP 工具调用，仅扩展现有 `take_screenshot` 的参数
- **客户端处理**：
  - `format_screenshot_result()` 增加 format 参数，jpeg 时设置正确的 mime_type
  - 新增 savePath 可选参数：指定时保存到用户自定义路径，未指定时沿用现有临时目录逻辑
  - maxWidth/maxHeight：通过 MCP `Emulation.setDeviceMetricsOverride` 或 `take_screenshot` 的 clip 参数控制（如 MCP 支持），否则标记为 TODO
- **参数 schema 更新**：
  - 在 `browser.mbt` 的 `parameters()` 中新增 `format`、`quality`、`save_path`、`max_width`、`max_height` 参数描述
- **返回结构**：
  - 现有返回格式已包含 mime_type、base64_data、path、size 信息，无需变更结构
  - 新增 format 和 quality 的回显信息

**验收标准**：
- [x] `build_mcp_screenshot_args` 正确透传 format 和 quality 到 MCP 参数
- [x] `format_screenshot_result` 支持 format 参数，jpeg 输出时 mime_type 为 "image/jpeg"
- [x] savePath 指定时文件正确保存到用户指定路径，未指定时保存到临时目录
- [x] 返回结果包含 format、path、size 信息
- [x] 参数 schema 中包含 format、quality、save_path、max_width、max_height 描述
- [x] 新增至少 3 个测试用例（格式切换、自定义保存路径、参数 schema 验证）
- [x] `moon check` 0 errors
- [x] `moon test lib/tool` 全部通过

### 任务包 3：快照压缩阈值门控与日志

**目标**：为 `compress_snapshot` 增加阈值自动判断和压缩日志记录。

**实现要点**：
- **阈值门控**：
  - 在 `compress_snapshot()` 入口处检查原始文本大小
  - 阈值定义：`snapshot_compress_threshold = 150 * 1024`（150KB，约 153600 字符）
  - 未超过阈值：跳过压缩，原样返回（仅执行 truncate_browser_output）
  - 超过阈值：执行现有两段式压缩
- **压缩日志**：
  - 记录三阶段大小：`原始大小 → 第一阶段（去噪）后大小 → 第二阶段（合并）后大小`
  - 日志格式：`"[snapshot-compress] original=XXXkb → stage1=XXXkb → stage2=XXXkb (ratio=XX%)"`
  - 日志输出到压缩结果头部（作为注释行），或通过 `@io.println` 输出到 stderr
- **snapshot 执行流程调整**：
  - 在 `browser.mbt` 的 `execute` 方法中，snapshot 分支已有 `compress_snapshot(output)` 调用
  - 阈值判断在 `compress_snapshot` 内部完成，调用方无需修改
- **不改动现有压缩算法**：第一阶段（去噪）和第二阶段（合并 StaticText）逻辑不变

**验收标准**：
- [x] 小于 150KB 的快照不触发两段式压缩，直接返回（仅 truncate）
- [x] 大于 150KB 的快照自动执行两段式压缩
- [x] 压缩结果包含日志信息（三阶段大小 + 压缩比）
- [x] 现有压缩算法逻辑不变（去噪 + 合并 StaticText）
- [x] `compress_snapshot` 的公开签名不变（向后兼容）
- [x] 新增至少 3 个测试用例（阈值以下跳过、阈值以上压缩、日志格式验证）
- [x] `moon check` 0 errors
- [x] `moon test lib/tool` 全部通过

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| MCP 服务器不支持原生 scroll_page 工具 | 中 | dispatch_act 中先尝试原生工具，捕获错误后回退到 evaluate_script；编写测试覆盖两种路径 |
| fill 增强中 evaluate_script 定位元素失败 | 低 | focus/blur 调用失败时静默降级（catch 后 ignore），不影响核心 fill 功能 |
| MCP take_screenshot 不支持 format/quality 参数 | 低 | 参数透传不影响核心功能；MCP 服务器忽略未知参数时仅输出 png 默认格式 |
| 快照阈值 150KB 对某些场景过于宽松或严格 | 低 | 阈值作为常量定义，后续可根据实际使用反馈调整 |
| 串行执行三个任务包延长整体交付周期 | 低 | 任务包 2（截图）和任务包 3（快照）涉及文件基本不重叠，可视情况并行 |

# 验收报告

### 改了什么
- `lib/tool/browser_action.mbt`：scroll 改用原生 MCP scroll_page 工具（带回退到 evaluate_script）；fill 增加 focus/blur 事件增强（静默降级）；新增 escape_js_string 辅助函数
- `lib/tool/browser_mcp_args.mbt`：新增 build_mcp_scroll_args、build_mcp_screenshot_args 透传 format/quality
- `lib/tool/browser_screenshot.mbt`：format_screenshot_result 支持 format(jpeg/png) 和 savePath 参数
- `lib/tool/browser_snapshot.mbt`：compress_snapshot 增加 150KB 阈值门控和三阶段压缩日志
- `lib/tool/browser.mbt`：参数 schema 新增 format/quality/save_path/max_width/max_height
- `lib/tool/browser_wbtest.mbt`（新建）：18+ 个白盒测试覆盖全部三个任务包

### 跑了什么验证
- moon check → 0 errors
- moon test lib/tool → 85 tests 全部通过
- moon info → API 变更合理
- Code Review → 1 SHOULD FIX + 1 CONSIDER，均已修复

### 验收标准对照

**任务包 1（表单交互增强）**：
- [x] dispatch_act("scroll") 调用原生 MCP scroll_page
- [x] 原生 scroll_page 失败时自动回退到 evaluate_script
- [x] dispatch_act("fill") 在 fill 前执行 focus()、fill 后执行 blur()
- [x] focus/blur 失败时静默降级
- [x] 新增 4+ 测试用例

**任务包 2（截图管道完善）**：
- [x] build_mcp_screenshot_args 透传 format 和 quality
- [x] format_screenshot_result 支持 format 参数
- [x] savePath 指定时文件正确保存到用户指定路径
- [x] 返回结果包含 format、path、size 信息
- [x] 参数 schema 包含 5 个新参数
- [x] 新增 3+ 测试用例

**任务包 3（快照压缩阈值门控）**：
- [x] 小于 150KB 的快照不触发压缩
- [x] 大于 150KB 的快照自动执行两段式压缩
- [x] 压缩结果包含日志信息
- [x] 现有压缩算法不变
- [x] compress_snapshot 公开签名不变
- [x] 新增 3+ 测试用例

### 没覆盖的
- max_width/max_height 截图缩放（标记为 TODO，需 libpng FFI）
- lib/server/ 守护进程层 TODO（browser.yml 配置读写、uptime 计算）不在本次范围
- Release 构建需在有 MSVC 环境的终端中验证

### 后续排查建议
- 如果 scroll_page MCP 工具不存在，scroll 操作会自动回退到 evaluate_script，检查 MCP 服务器日志确认实际可用工具
- 如果 fill focus/blur 在某些前端框架下仍有问题，检查 evaluate_script 是否能正确定位 data-ref 属性

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-07 | 初始版本 | 锚定浏览器工具 70% → 100% 的三个任务包 |
| 2026-07-07 | 全面重写：修正架构为 MCP-based，基于实际代码现状分析 | 背景研究偏离事实（CDP → MCP、BrowserAction 枚举 → 字符串分发），需基于代码实际状态 |
| 2026-07-07 | 确认文件组织策略：所有代码在 lib/tool/ 包下按 browser_*.mbt 拆分 | 遵循项目惯例 |
| 2026-07-07 | 状态更新为"已完成"，添加验收报告 | 三个任务包全部实现并验收通过 |
| 2026-07-07 | 复核归档：moon check 0 errors、moon test lib/tool 85/85、cmd 二进制构建正常，spec 移入 completed/ | 收尾归档 |
