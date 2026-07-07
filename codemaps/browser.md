# browser — 浏览器自动化 · MCP 代理 · 表单增强 · 截图管道 · 快照压缩

> 路径: `lib/tool/browser*.mbt` · 7 文件 · 浏览器工具层（属于 tool 包）
> 完成度: ~90%（核心功能完整，max_width/max_height 缩放 TODO）

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `Browser::execute(action, args)` | `browser.mbt` | Tool trait 执行入口，按 action 分发到各子功能 |
| `Browser::dispatch_act(kind, args)` | `browser_action.mbt` | act kind 二级分发（click/fill/scroll/screenshot 等） |
| `Browser::mcp_call(tool_name, args)` | `browser.mbt` | 底层 MCP JSON-RPC 调用封装 |
| `compress_snapshot(text)` | `browser_snapshot.mbt` | 快照压缩入口（阈值门控 + 两段式压缩） |
| `format_screenshot_result(raw, args)` | `browser_screenshot.mbt` | 截图结果格式化（base64 提取/文件保存/格式转换） |

## 关键类型

### 核心 Struct
- **`Browser`** — 浏览器工具主结构：`daemon_connected`（MCP 守护进程连接状态）、`page_cache`（当前页面缓存）
- **`PageCache`** — 页面缓存：`current`（当前 page ID）、`invalidated`（缓存失效标志）
- **`BrowserMcpState`** — 模块级 MCP 状态：持有 `McpRegistry` 引用（全局变量）

### 辅助函数
- **`build_mcp_*_args`** — 各 MCP 工具的参数构建器系列（`browser_mcp_args.mbt`）
- **`escape_js_string(s)`** — JS 字符串转义辅助（`browser_action.mbt`）

## 核心调用链

```
Browser::execute(action, args)
  ├─ "open"      → mcp_call("open_page", args)
  ├─ "navigate"  → mcp_call("navigate_page", args)
  ├─ "snapshot"  → mcp_call("take_snapshot", args) → compress_snapshot()
  ├─ "act"       → dispatch_act(kind, args)
  │   ├─ click/dblclick → with_page("click", args)
  │   ├─ type/fill      → dispatch_fill_enhanced(args)
  │   │   ├─ evaluate_script("element.focus()")  # 静默降级
  │   │   ├─ with_page("fill", args)
  │   │   └─ evaluate_script("element.blur()")   # 静默降级
  │   ├─ scroll         → dispatch_scroll(args)
  │   │   ├─ with_page("scroll_page", args)      # 优先原生 MCP
  │   │   └─ with_page("evaluate_script", args)  # 失败回退 JS scrollBy
  │   ├─ press   → with_page("press_key", args)
  │   ├─ hover   → with_page("hover", args)
  │   ├─ drag    → with_page("drag", args)
  │   ├─ select  → with_page("select_option", args)
  │   ├─ wait    → with_page("wait_for", args)
  │   ├─ evaluate → mcp_call("evaluate_script", args)
  │   └─ click_at → with_page("click_at", args)
  ├─ "screenshot" → mcp_call("take_screenshot", args) → format_screenshot_result()
  ├─ "tabs"      → mcp_call("list_pages", args)
  ├─ "focus"     → mcp_call("switch_page", args)
  ├─ "close"     → mcp_call("close_page", args)
  └─ "status"    → 本地状态查询
```

## 文件职责分组

| 文件 | 职责 |
|------|------|
| `browser.mbt` (542行) | 核心：Browser struct、Tool trait 实现、execute 分发、MCP 调用、参数 schema（含 format/quality/save_path/max_width/max_height）、配置检查 |
| `browser_action.mbt` (184行) | act kind 二级分发、scroll 原生 MCP（带回退）、fill focus/blur 增强（静默降级）、escape_js_string 转义辅助 |
| `browser_mcp_args.mbt` (~300行) | MCP 工具参数构建器系列：build_mcp_click_args、build_mcp_fill_args、build_mcp_scroll_args（新增）、build_mcp_screenshot_args（新增，透传 format/quality）等 |
| `browser_page.mbt` (149行) | 页面缓存管理、with_page 自动重试、页面就绪轮询、错误恢复 |
| `browser_screenshot.mbt` (~200行) | 截图管道：base64 提取、PNG/JPEG 格式保存、savePath 自定义路径、150KB 大小检查 |
| `browser_snapshot.mbt` (~260行) | 快照处理：150KB 阈值门控（跳过小快照）、两段式压缩（去噪+合并 StaticText）、三阶段压缩日志、查询窗口分页、输出截断 |
| `browser_wbtest.mbt` (新建) | 18+ 个白盒测试：scroll 原生调用/回退、fill 增强/降级、截图格式切换/保存路径、快照阈值门控/压缩日志、escape_js_string 转义 |

## 已实现功能清单

### 核心 Actions（9 种）
- open / navigate / snapshot / act / screenshot / tabs / focus / close / status

### Act Kinds（12 种）
- click / dblclick / type / fill / press / hover / drag / select / scroll / wait / evaluate / click_at

### 表单交互增强（2026-07-07 新增）
- **scroll** 改用原生 MCP `scroll_page` 工具，失败时自动回退到 `evaluate_script` JS scrollBy
- **fill** 操作前置 `focus()` + 后置 `blur()` 事件增强，兼容 React/Vue 等框架
- focus/blur 失败时静默降级，不影响核心 fill 功能
- `escape_js_string` 辅助函数，完整转义 `\"` `\\` `\n` `\r` `\t` 等字符

### 截图管道完善（2026-07-07 新增）
- `build_mcp_screenshot_args` 透传 format（jpeg/png）和 quality 参数到 MCP
- `format_screenshot_result` 支持 format 参数，jpeg 时设置正确 mime_type
- savePath 自定义保存路径支持
- 参数 schema 新增 format / quality / save_path / max_width / max_height（后两者 TODO）

### 快照压缩阈值门控（2026-07-07 新增）
- 150KB 阈值判断：小于阈值的快照跳过压缩，直接返回
- 大于阈值自动执行两段式压缩（去噪 → 合并 StaticText）
- 三阶段压缩日志：原始大小 → 去噪后 → 合并后（含压缩比）
- `compress_snapshot` 公开签名不变，向后兼容

## 外部依赖

- `lib/mcp` — 所有浏览器操作通过 MCP 协议（JSON-RPC 2.0）委托给 browser-use 服务器
- `moonbitlang/x/fs` — 截图文件保存
- 无直接 CDP 调用

## 风险点

1. **MCP 服务器 scroll_page 可用性** — 若 browser-use MCP 未提供 scroll_page 工具，scroll 会自动回退到 evaluate_script，功能不受影响但性能略降
2. **fill focus/blur 前端兼容性** — 部分前端框架（如使用 Shadow DOM 的组件）可能无法通过 `data-ref` 属性定位元素，此时静默降级为普通 fill
3. **max_width/max_height TODO** — 截图缩放功能需要 libpng FFI 支持，当前仅预留参数 schema
4. **Browser MCP 全局状态** — `set_browser_mcp_registry()` 使用全局变量，测试时需注意隔离
5. **守护进程层 TODO** — `lib/server/` 中的 browser.yml 配置读写、uptime 计算尚未实现

## 测试覆盖

| 测试文件 | 测试数 | 覆盖范围 |
|---------|--------|---------|
| `tool_wbtest.mbt`（浏览器部分） | 5 | name/category、status action、not_configured error、open missing url、format_call |
| `browser_wbtest.mbt` | 18+ | scroll 原生/回退、fill 增强/降级、截图格式/路径、快照阈值/日志、escape_js_string |
| **合计** | **23+** | 全部三个任务包功能覆盖 |
