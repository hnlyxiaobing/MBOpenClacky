# Web UI 可用性恢复与原项目对齐 · 增量 Spec

> **创建日期**: 2026-07-20  
> **最后更新**: 2026-07-21
> **状态**: 已归档 — 所有 P0/P1/P2 目标验收通过，spec 移入 `specs/completed/`  
> **关联总览**: `docs/web_ui_comparison_report.md`（2026-07-20 对比测试报告）  
> **关联历史 spec**: `specs/completed/2026-07-09_web-frontend-panels-completion.md`、`specs/completed/2026-07-09_web-api-contract-alignment.md`  
> **来源差距**: 对比测试暴露的 6 项缺陷 + 8 类功能差距  
> **依赖**: 无  
> **灰度 key**: 无

---

## 问题描述 [必填]

MBOpenClacky Web UI 当前处于**完全不可用状态**。对比测试（Playwright + curl，2026-07-20）表明：

1. 首页因前端 JS 语法错误整页空白（SPA 根本不启动）；
2. 即使绕过启动阻断，SSE 流式数据为 MoonBit 调试格式而非 JSON，聊天回复永远无法上屏；
3. LLM 调用全链路失败（CLI 与 Web 均复现），用户无法获得任何 AI 回复；
4. 错误信息仅显示内部类型路径名，无法辅助定位问题；
5. Windows 下服务器日志刷大量目录扫描错误（error code 267）；
6. 打补丁后 UI 存在 Cost 模态框遮挡、时间占位符异常等次要问题。

与原项目（OpenClacky Ruby v1.4.0）相比，布局/顶栏、主题、国际化、新会话流程、输入区能力、会话管理、设置体系、API 契约均存在明显功能差距。

本 spec 将上述问题视为一个**完整的 Web UI 可用性恢复系统工程**，按优先级分层推进：先恢复核心链路可用（P0），再补齐关键功能差距（P1），最后回归验证与打磨（P2）。

---

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| bridge.mbt:306 存在正则双重转义 | `Read web/mb/main/bridge.mbt:306` + hex dump 源码与编译产物对比 | 确认 `extern "js" fn js_render_markdown` 中含 `<\\/code>` 等模式。**经 hex dump 验证**：MoonBit 编译器将 `extern "js"` 函数体作为**原始源文本**原样发射到 JS 输出，**不处理 MoonBit 字符串转义序列**。源码中的 `\\s`（字节 `5c 5c 73`）在编译产物 `web/mb/index.js` 中仍为 `\\s`（字节 `5c 5c 73`），而非 `\s`（字节 `5c 73`）。因此 JS 正则字面量中的 `\\/` 被解析为"转义反斜杠(`\\`)+ 正则结束符(`/`)"，后续文本变成非法 flags | 确认存在，唯一启动阻断点。根因是编译器对 `extern "js"` 体做 raw text 发射，而非 MoonBit 字符串转义处理后发射 |
| SSE 使用 @debug.to_string 序列化 | `grep "debug.to_string" lib/web/sse/sse.mbt` | 第 22 行 `let data_str = @debug.to_string(data)` | 确认存在 |
| LLM client 有真实 HTTP 路径 | `Read lib/agent/llm_caller.mbt:46-113` | `call_llm` 通过 `@client.http_post` → C FFI（WinHTTP/libcurl）发送请求 | HTTP 路径已接通，失败原因需进一步诊断 |
| 错误类型 to_string 只输出类型名 | `Read lib/errors/errors.mbt:1-56` | suberror 仅 `derive(ToJson, Debug)`，无自定义 `to_string`；`handlers.mbt:268` 使用 `err.to_string()` | 确认：默认 to_string 输出包路径+构造器名 |
| Windows 目录扫描路径问题 | `grep "read_dir" lib/` | 25+ 处调用 `@fs.read_dir`，均 catch 静默；session_store 使用 `@utils.sessions_dir()` 拼接路径 | 疑似路径拼接在 Windows 下产生无效目录名，需运行时诊断 |
| 其它 extern "js" 函数是否有同类转义问题 | `Read web/mb/main/bridge.mbt:295-327` + hex dump 编译产物 | `js_format_expiry`(L298)、`js_parse_date`(L288)、`js_connect_sse`(L317) 等均含同类问题：`/\\d+$/` 在 JS 中匹配字面 `\d` 而非数字字符类；`\\u2014` 显示为字面 `\u2014` 而非 em dash；`js_connect_sse` 中 `split('\\n')` 在 JS 中按字面 `\n`(2字符)分割而非换行符，**导致 SSE 行解析完全失效**——这是缺陷 #2 之外的另一个 P0 级阻断点 | 待排查 → 已确认全量受影响，需统一修复 |

### 详细分析

**缺陷 #1 根因链**：MoonBit `extern "js"` 函数体是字符串字面量，但**编译器将其作为原始源文本（raw text）原样发射到 JS 输出，不处理 MoonBit 字符串转义序列**（经 hex dump 对比源码与 `web/mb/index.js` 编译产物确认：源码字节 `5c 5c 73` = `\\s`，编译产物字节仍为 `5c 5c 73` = `\\s`，未变为 `5c 73` = `\s`）。因此源码中的 `\\s`、`\\w`、`\\/`、`\\n`、`\\u2014` 等双反斜杠序列在 JS 输出中保持不变。在 JS 正则字面量 `/pattern/flags` 中，`\\` 被解析为"转义反斜杠"（匹配字面 `\`），随后的 `/` 被解析为正则结束符，后续文本 `code>...` 变成非法 flags -> `SyntaxError: Invalid regular expression flags` -> 整个 ES module 解析失败 -> SPA 不启动。

**同类影响（非语法错误但行为错误）**：`js_parse_date`/`js_format_expiry` 中的 `/^\\d+$/` 在 JS 中匹配字面 `\d` 而非数字字符类；`\\u2014` 显示为字面 `\u2014` 而非 em dash 字符；`js_connect_sse` 中 `split('\\n')` 按字面 2 字符串 `\n` 分割而非换行符，**导致 SSE 行解析完全失效**（即使修好 SSE 数据格式，前端仍无法解析事件流）。

**缺陷 #2 根因链**：`format_sse_event` 使用 `@debug.to_string(data)` 将 Json 值序列化为 MoonBit 调试表示（如 `Object({ "status": String("running") })`），前端 `JSON.parse` 必然失败。

**缺陷 #3 根因假设**：curl 直连 LLM 端点正常，说明 api_key/base_url 可用。可能原因：
- (a) C FFI HTTP 层在 Windows (WinHTTP) 下对 HTTPS/HTTP2/大 body 的处理有 bug；
- (b) 请求头格式（`format_headers` 使用 `\r\n` 拼接）与 WinHTTP 预期不匹配；
- (c) 请求体中 `stream: true` 但当前 `call_llm` 走非流式路径，而端点要求特定参数；
- (d) 响应解析（`parse_openai_response`）对 ark/volces 端点的响应格式不兼容。
需在修复 #1/#2 后通过日志增强进一步定位。

**缺陷 #4 根因**：MoonBit suberror 的默认 `to_string()` 输出 `包路径.构造器名.构造器名`，不提取内嵌的 String message。`handlers.mbt:268` 的 `err.to_string()` 和 CLI 输出均受此影响。

**功能差距总结**（均因 #1 阻断无法深入验证，完成度待 P0 修复后回归）：
- 布局：无 header/顶栏，20+ 入口堆在侧边栏底部
- 主题：仅深色，无亮色/跟随系统/主题色
- 国际化：硬编码英文，i18n 下拉未生效
- 新会话：无 agent 类型/目录/模型选择
- 输入区：无附件/斜杠命令/运行状态栏/Stop 按钮
- 会话管理：无类型过滤/日期过滤/Actions 菜单/分页
- 设置：功能面窄于原项目
- API 契约：路径差异（`/api/models` vs `/api/config/models`）

---

## 决策 [必填 - 含为什么]

1. **分层推进而非一次性全量修复**：P0 阻塞修复（3 项）→ P1 功能补齐 → P2 回归打磨。理由：P0 不修复则后续所有功能验证无法进行；分层可逐步验收、降低回归风险。

2. **bridge.mbt 正则修复策略：重写为不含正则字面量的 JS 代码**：将 `js_render_markdown` 中的正则改用 `new RegExp(...)` 构造器（字符串参数），避免正则字面量 `/` 与路径转义冲突。同时全量排查所有 `extern "js"` 函数体。理由：最小改动、根治转义问题，不引入新依赖。

3. **SSE 序列化改用 `data.stringify()`**：MoonBit `Json` 类型自带 `.stringify()` 方法输出合法 JSON。理由：一行修改，无副作用。

4. **LLM 调用失败诊断优先于修复**：先增强 `call_llm` 错误路径的日志输出（记录 URL、status、response body 前 500 字符），再根据日志定位具体原因。理由：根因尚未确定，盲修可能引入新问题。

5. **错误可读性：为 suberror 添加 `display_message` 辅助函数**：在 `lib/errors` 中新增 `pub fn error_message(err : Error) -> String`，match 各 suberror 提取内嵌 message。Web handler 和 CLI 统一调用此函数。理由：不修改 suberror derive，影响面最小。

6. **Windows 目录扫描：防御性路径校验 + 日志降级**：在 `ensure_sessions_dir` 等关键路径添加 `path_exists` 前置检查；将 `read_dir` 失败的静默 catch 改为 warn 级别日志（仅首次）。理由：error 267 是"目录名无效"，大概率是路径拼接问题（如尾部多余分隔符或 UNC 路径），防御性检查可消除刷屏。

7. **功能差距暂不纳入本 spec 实施范围**：布局/主题/i18n/输入区/会话管理/设置体系等属于 P1/P2，待 P0 修复后另开 spec 逐项推进。理由：避免单个 spec 范围过大、不可验收；功能差距需要 UI 可用后才能精确评估。

8. **API 契约差异保持现有路径，不盲目对齐原项目**：当前 `/api/models`、`/api/settings` 等路径已被前端消费，改动需前后端同步。理由：原项目路径非标准，当前项目已有独立契约，强行对齐收益低风险高。

---

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `web/mb/main/bridge.mbt` | 修改 | 修复 `js_render_markdown` 正则转义；全量排查其它 extern "js" 函数 |
| `lib/web/sse/sse.mbt` | 修改 | L22: `@debug.to_string(data)` → `data.stringify()` |
| `lib/agent/llm_caller.mbt` | 修改 | 增强错误路径日志（URL/status/body 摘要） |
| `lib/errors/errors.mbt` | 修改 | 新增 `error_message(err) -> String` 辅助函数 |
| `lib/web/handlers.mbt` | 修改 | L268: `err.to_string()` → `@errors.error_message(err)` |
| `cmd/main.mbt` | 修改 | CLI 错误输出改用 `error_message` |
| `lib/agent/session_store.mbt` | 修改 | `ensure_sessions_dir` 添加路径有效性校验 |
| `lib/web/handlers_backup.mbt` | 修改 | `read_dir` 失败日志降级为 warn（首次） |

### 不涉及文件

- `web/css/`、`web/js/lib/`（第三方库不动）
- `web/mb/main/*_cell.mbt`（P1 功能补齐另开 spec）
- `lib/client/format_openai.mbt`、`lib/client/format_anthropic.mbt`（待诊断结果确认后再决定是否修改）
- `lib/client/http_native.c`（C FFI 层暂不动，先通过日志确认是否为该层问题）
- 原项目 API 路径对齐（决策 8：不盲目对齐）

---

## 实施计划 [必填]

### 任务包 1：P0-1 首页 SPA 启动阻断修复（预估 0.5 天）

1. 重写 `bridge.mbt:306` 的 `js_render_markdown` 函数体：
   - 将所有正则字面量 `/pattern/flags` 改为 `new RegExp('pattern', 'flags')` 形式
   - 或将所有 `\\x`（双反斜杠+字符）改为 `\x`（单反斜杠+字符），因为编译器对 `extern "js"` 体做 raw text 发射，源码中的 `\\s` 在 JS 输出中仍为 `\\s`（错误），改为 `\s` 后 JS 输出为 `\s`（正确）。注意：`\\/` 应改为 `\/`（JS 正则中 `\/` 是合法的转义斜杠），`\\n` 应改为 `\n`（JS 中 `\n` 是换行符），`\\u2014` 应改为 `\u2014`（JS 中 `\u2014` 是 em dash 字符）
   - 关键：验证 MoonBit 字符串转义规则，确保发射后的 JS 是合法的
2. 全量排查 `bridge.mbt` 中所有 `extern "js"` 函数体（`js_format_expiry`、`js_connect_sse`、`js_cancel_generation`、`js_scroll_chat_to_bottom` 等），修复同类问题
3. 重新构建 `web/mb` → `web/mb/index.js`（`moon build --target js`，在 `web/mb/` 目录下执行；`web/index.html` 引用的是 `mb/index.js` 即 `web/mb/index.js`，非 `web/dist/index.js`）
4. 验证：浏览器打开 `http://localhost:7071/`，页面正常渲染，Console 无 pageerror

### 任务包 2：P0-2 SSE 流式数据格式修复（预估 0.5 天）

1. `lib/web/sse/sse.mbt:22`：将 `@debug.to_string(data)` 替换为 `data.stringify()`
2. 检查 `build_sse_body` 中是否有其它 `@debug.to_string` 调用（已确认仅 `format_sse_event` L22 一处）
3. **修复 `js_connect_sse`（bridge.mbt:317）中 `split('\\n')` 的同类转义问题**：由于编译器 raw text 发射，`\\n` 在 JS 中变为字面 `\n`（2字符）而非换行符，导致 SSE 行解析完全失效。改为 `split('\n')` 后 JS 输出为 `split('\n')`（按换行符分割，正确）
4. 添加白盒测试：验证 `format_sse_event("status", Json::object({"status": "running".to_json()}))` 输出包含合法 JSON `"status":"running"`
5. 验证：curl 直连 SSE 端点，data 行为合法 JSON；前端 `JSON.parse` 成功且 SSE 事件流可正确分割

### 任务包 3：P0-3 LLM 调用链路诊断与修复（预估 1-2 天）

1. 在 `llm_caller.mbt` 的 `call_llm` 错误路径增加诊断日志：
   - `Err(err)` 分支：输出 URL + 错误详情
   - `map_http_error` 分支：输出 status + body 前 500 字符
   - JSON 解析失败分支：输出 body 前 500 字符
2. 构建后通过 `cmd.exe --message "Hello"` 复现，根据日志定位根因
3. 根据诊断结果修复（可能涉及 `http_native.c` WinHTTP 路径、请求头格式、或响应解析）
4. 验证：CLI 和 Web 均能收到 LLM 回复

### 任务包 4：P1-1 错误信息可读化（预估 0.5 天）

1. `lib/errors/errors.mbt` 新增：
   ```
   pub fn error_message(err : Error) -> String {
     match err {
       AgentError(msg) => msg
       BadRequestError(code, msg) => "[HTTP \{code}] \{msg}"
       RetryableError(msg) => msg
       ToolCallError(name, msg) => "[Tool: \{name}] \{msg}"
       ...
     }
   }
   ```
2. `lib/web/handlers.mbt:268`：`err.to_string()` → `@errors.error_message(err)`
3. CLI 入口（`cmd/main.mbt`）：错误输出改用 `error_message`
4. SSE error 事件：确保 `ErrorOccurred(msg)` 中的 msg 来自 `error_message` 而非 `to_string`
5. 验证：触发错误时，Web UI 和 CLI 显示人类可读的错误描述

### 任务包 5：P1-2 Windows 目录扫描错误修复（预估 0.5 天）

1. 在 `ensure_sessions_dir` 中添加路径规范化（去除尾部分隔符、验证路径格式）
2. 排查 `@utils.sessions_dir()` 在 Windows 下的返回值（是否含尾部 `\` 或非法字符）
3. 将高频 `read_dir` 失败的 catch 分支添加首次 warn 日志（避免 30+ 次刷屏）
4. 验证：Windows 下启动服务器，stdout 不再刷 `error code 267`

### 任务包 6：P2 打补丁后 UI 次要异常（预估 0.5 天）

1. Cost Information 模态框：检查触发条件，添加"仅在完成后显示"逻辑或用户手动触发
2. 会话列表时间字段：空日期时显示合理占位符（如 "—" 或 "Just now"）
3. 添加 favicon（复用品牌 logo）
4. JS 崩溃时添加 `<noscript>` 或全局 error boundary 提示
5. 验证：UI 无异常弹窗遮挡，时间显示正常

### 任务包 7：P1-3 功能差距回归验证（预估 1 天，P0 全部完成后执行）

1. 使用 `.test_web_compare/` 脚本重新运行 test1~3，确认 P0 修复生效
2. 逐项检查报告第二节功能差距，记录当前完成度
3. 为后续 P1 功能补齐 spec 提供精确的差距清单（布局/主题/i18n/输入区/会话管理/设置）
4. 输出回归验证报告至 `docs/` 或 spec 变更记录

---

## 验收标准 [必填]

### P0 阻塞修复（必须全部通过）

- [x] 浏览器打开 `http://localhost:7071/` 正常渲染首页，Console 无 pageerror
- [x] `curl -N POST /api/sessions/{id}/chat/stream` 返回的 data 行为合法 JSON（可被 `JSON.parse` 解析）
- [x] `js_connect_sse` 中 `split('\\n')` 修复后，前端能正确分割 SSE 事件流（按换行符而非字面 `\n`）
- [x] 通过 Web UI 发送消息后，聊天区能渲染 AI 回复（需 LLM 端点可用）
- [x] `cmd.exe --message "Hello"` 能正常返回 AI 回复
- [x] `moon check` 0 errors（lib/web/sse、lib/errors、lib/agent、web/mb/main）

### P1 功能补齐

- [x] 触发 LLM 错误时，Web UI 显示人类可读错误信息（非包路径+类型名）
- [x] Windows 下服务器启动后 stdout 无 `error code 267` 刷屏
- [x] `moon test lib/web` 通过
- [x] `moon test lib/errors` 通过（若新增测试）

### P2 回归验证

- [x] `.test_web_compare/test1_load.js` 所有探针通过（无需补丁注入）
- [x] `.test_web_compare/test3_chat.js` 消息发送后 30s 内收到流式回复
- [x] 无 Cost 模态框异常弹出
- [x] 会话列表时间字段显示正常

---

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| bridge.mbt 正则修复引入新的 JS 语法错误 | 高 | 修复后立即用 `node --check web/dist/index.js` 验证语法；Playwright test1 回归 |
| LLM 调用失败根因在 C FFI 层（WinHTTP） | 高 | 先通过日志定位；若确认是 FFI 问题，可临时切换到 libcurl 或添加 fallback |
| SSE 格式修复影响 hook 事件捕获链路 | 中 | `capture_hook_event` 已使用 `Json::object` 构造，仅 `format_sse_event` 序列化方式变更，不影响上游 |
| 全量排查 extern "js" 可能遗漏 | 中 | 编写 grep 脚本扫描所有 `extern "js"` 函数体中的正则字面量 |
| Windows 路径问题根因不在 sessions_dir | 低 | 添加 warn 日志后可从日志中精确定位失败路径 |
| P0 修复后功能差距比预期更大 | 低 | 任务包 7 回归验证后另开 P1 spec，不影响本 spec 验收 |

---

## 依赖关系 [必填]

- **前置依赖**：无（本 spec 为当前最高优先级）
- **后置依赖**：
  - 布局/主题/i18n/输入区/会话管理/设置体系功能补齐 spec（待 P0 完成后根据回归结果创建）
  - `specs/completed/2026-07-09_web-frontend-panels-completion.md` 中未验证的面板功能

---

## 回归测试方案

### 自动化回归

1. **构建验证**：`moon check` + `moon build --target native --release cmd` + `moon build --target js`（web/mb）
2. **单元测试**：`moon test lib/web` + `moon test lib/errors` + `moon test lib/agent`
3. **E2E 脚本**：
   - `node .test_web_compare/test1_load.js`（首屏加载探针）
   - `node .test_web_compare/test2_structure.js`（UI 结构探针）
   - `node .test_web_compare/test3_chat.js`（聊天流式回复）
4. **CLI 冒烟**：`cmd.exe --message "Reply with just: OK"` 返回 "OK"

### 手动回归

1. 浏览器打开首页 → 正常渲染
2. 新建会话 → 发送消息 → 收到流式回复 → Markdown 正确渲染
3. 触发错误（如断网/无效 key）→ 显示可读错误信息
4. Windows 下启动服务器 → 无目录错误刷屏
5. 检查会话列表、设置页、各面板入口可正常打开

---

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-20 | 初始版本：基于 web_ui_comparison_report.md 创建 | 对比测试暴露 Web UI 完全不可用，需系统性修复 |
| 2026-07-20 | 审核修正：1. 缺陷 #1 根因机制纠正（经 hex dump 验证，编译器对 `extern "js"` 体做 raw text 发射，非转义处理后发射）；2. 构建输出路径 `web/dist/index.js` -> `web/mb/index.js`；3. 修复策略解释纠正（`\\x` -> `\x` 而非 `\\/` -> `/`）；4. 新增 `js_connect_sse` 中 `split('\\n')` 同类 bug（P0 级 SSE 行解析阻断）；5. `js_format_expiry`/`js_parse_date` 转义问题确认（`\\d` 匹配字面 `\d`，`\\u2014` 显示字面 `\u2014`） | 对抗性审核 + hex dump 源码/产物对比验证 |
| 2026-07-20 | 实施完成并验收通过：P0-1 bridge.mbt 4 个 extern "js" 函数转义修复；P0-2 SSE 改 `data.stringify()` + 白盒测试；P0-3 根因定位为 WinHTTP `WinHttpSendRequest` 的 `dwTotalLength=0`（ERROR_INVALID_PARAMETER 0x57），修复后 CLI/Web 均通；P1-1 新增 `error_message` 并在 handlers/CLI/react 统一使用；P1-2 根因为 `handlers_files.is_directory` 用 read_dir 探测文件（C 层逐文件打印 267），改用 `@fs.is_dir` 并给 handlers_backup 加守卫与首次 warn；P1-3 Cost 模态框根因为 `StreamDone` 复用 `CostLoaded` 自动弹窗，拆出 `CostRefreshed`；另修复新会话 `GET /api/sessions/:id`/`/messages` 404（active_agents 内存兜底）、添加 favicon/noscript/error boundary。E2E test1/2/3 全绿（无补丁注入），验收标准全部通过。验收报告：`specs/completed/web_ui_usability_restoration_acceptance.md` | 按 Spec 分层实施 + P2 回归验证 |
| 2026-07-21 | 独立对抗性复核 + 归档：按 Harness v2 "gap 是假设" 原则，将验收报告作为假设逐项用 grep/hex dump/真实浏览器验证。<br>**源码层确认**：`bridge.mbt` 4 个 extern "js" 函数均为单反斜杠（hex 验证 5c 73/5c 77/5c 2f）；`sse.mbt:22` 使用 `data.stringify()`；`http_native.c:228` `WinHttpSendRequest` 传 `(DWORD)body_len` 修复 dwTotalLength=0。<br>**构建/测试层确认**：`moon check` 0 errors；`moon test lib/web/sse lib/errors lib/web` 249/249 通过；`moon test lib/agent lib/client` 318/318 通过；`moon build --target native --release cmd` 0 errors。<br>**真实 Chrome 端到端确认**：title="MBOpenClacky - AI Agent"、#app 4 子节点 203k 字符 DOM、会话列表 `3 msgs · $0 · just now`、Markdown 渲染为 `<p>OK</p>`、发送 "Say only the word WORKING" 2.5s 内收到 "WORKING" 实时流式回复、input 自动清空、状态 IDLE、无 Cost 弹窗。<br>**环境性注记**（非代码缺陷）：WSL 环境死代理 `HTTP_PROXY=127.0.0.1:9567` 导致 CLI 直连 ark API 失败（`env -u HTTP_PROXY -u HTTPS_PROXY` 后通过）；Playwright headless chromium 在 WSL 下无法连接 localhost:7071（curl 可达），WSL headless chromium 网络限制，使用真实 Chrome 替代 E2E 验证。Spec 移入 `specs/completed/`，验收报告保留于 `docs/web_ui_usability_restoration_acceptance.md` | 对抗性复核 + 归档（决策 7/8 范围内的功能差距按设计留给后续 P1 spec） |
