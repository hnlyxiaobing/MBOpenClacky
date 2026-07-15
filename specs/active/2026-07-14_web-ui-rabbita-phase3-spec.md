# Web UI Rabbita 迁移 Phase 3+4 · 增量 Spec

> **创建日期**: 2026-07-14
> **最后更新**: 2026-07-15
> **状态**: 开发中 — Task Pack 0-3 完成（21/22 面板已迁移），Task Pack 4（Chat 集群）+ Task Pack 5（Phase 4 清理）待开始
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G4（P1 重要功能差距）
> **关联历史 spec**: `specs/deprecated/2026-07-13_04_frontend-feature-architecture.md`（store/view 拆分，已被 rabbita 迁移取代）、`specs/completed/2026-07-14_web-ui-rabbita-migration.md`（Phase 0-2.8 已完成）
> **来源差距**: G4 - Web 前端 Feature-based 架构迁移（rabbita TEA 方案）
> **依赖**: Phase 0-2.8 已完成（9 个面板 + 桥接层 + 整合清理）
> **灰度 key**: 无
>
> ## 进度总览
>
> | 任务包 | 状态 | Commit | 说明 |
> |--------|------|--------|------|
> | Task Pack 0: i18n 基础设施 | ✅ 完成 | (内嵌于各 cell 迁移 commit) | i18n_t / i18n_get_locale / i18n_on_locale_changed + locale_change_cmd 模式 |
> | Task Pack 1: 低复杂度面板 | ✅ 完成 | `8599f0d` | Meeting/Marketplace/Workspace 3 面板 |
> | Task Pack 2a: Schedules | ✅ 完成 | `32a0870` | |
> | Task Pack 2b: Billing | ✅ 完成 | `83431e9` | |
> | Task Pack 2c: Media | ✅ 完成 | `1125a9e` | |
> | Task Pack 2d: Onboard | ✅ 完成 | `3d27966` | |
> | Task Pack 2e: Creator | ✅ 完成 | `af85779` | |
> | Task Pack 2f: Git | ✅ 完成 | `bebc014` | |
> | Task Pack 2g: Channels | ✅ 完成 | `63bd0fc` | |
> | Task Pack 2h: MCP | ✅ 完成 | `99286ee` | |
> | Task Pack 3a: Settings | ✅ 完成 | `3bff8b4` | |
> | Task Pack 3b: Skills | ✅ 完成 | `ff57eec` | 含跨 Cell CustomEvent 通信 |
> | Task Pack 4: Chat 集群 | ⬜ 待开始 | — | chat.js + sessions.js + websocket.js + ws-dispatcher.js（~1,255 行） |
> | Task Pack 5: Phase 4 清理 | ⬜ 待开始 | — | 移除 app.js / i18n.js / notifications.js + 架构固化 |

---

## 问题描述 [必填]

Phase 0-2.8 已完成 9 个面板的 rabbita 迁移（Brand/Backups/Version/Profile/Share/Trash/ModelTest/Tasks/Browser），Phase 3 Task Pack 0-3 进一步完成 12 个面板的迁移（Meeting/Marketplace/Workspace/Schedules/Billing/Media/Onboard/Creator/Git/Channels/MCP/Settings/Skills），**已迁移 21/22 个面板**。但以下问题尚未解决：

1. **i18n 部分完成**：Phase 3 新迁移的 12 个 Cell 已接入 i18n_t 桥接 + locale_change_cmd 监听，但已迁移的 9 个 Phase 0-2.8 Cell 仍有硬编码英文（Task Pack 0 仅在新增 Cell 中验证了 i18n 桥接，未回填旧 Cell）。
2. **Chat 集群仍为 legacy JS**（~1,255 行，4 文件紧耦合）：chat.js（588 行）、sessions.js（243 行）、websocket.js（278 行）、ws-dispatcher.js（146 行）。这是前端最复杂的交互系统，涉及 SSE 流式、Dispatcher 状态机、Markdown 渲染。
3. **app.js 仍是协调中枢**（~200 行残留）：提供 API 包装器、通知/模态框、视图切换、WS 事件路由、键盘快捷键。在 Chat 集群迁移完成前无法移除。
4. **index.html 仍有 9 个活跃 script 引用**：app.js / i18n.js / i18n/en.js / i18n/zh.js / notifications.js / websocket.js / ws-dispatcher.js / chat.js / sessions.js（+ 2 个 lib/ 库）。

本 Spec 规划 Phase 3 剩余工作（Task Pack 4: Chat 集群迁移）和 Phase 4（Task Pack 5: 全量清理与架构固化）。

---

## 现状分析 [必填 - 含代码验证]

### 验证记录（2026-07-15 最新）

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "22 个 rabbita Cell 已存在" | `ls web/mb/main/*_cell.mbt` | 22 文件 | ✅ 确认（Phase 0-2.8: 9 + Phase 3: 13） |
| "仅剩 7 个 legacy JS" | `ls web/js/*.js` | app.js / chat.js / i18n.js / notifications.js / sessions.js / websocket.js / ws-dispatcher.js | ✅ 确认（15 个面板 JS 已删除） |
| "bridge.mbt 有 28 个 extern 函数" | `grep -c 'extern "js"' web/mb/main/bridge.mbt` | 28 匹配 | ✅ 确认（Phase 0-2.8: 22 + Phase 3 新增 6: i18n_t/i18n_get_locale/i18n_on_locale_changed/app_show_view/skill_editor_open/on_skill_open_editor） |
| "i18n_t 桥接已存在" | `grep 'i18n_t' web/mb/main/bridge.mbt` | 有 `i18n_t` 函数 | ✅ 已实现 |
| "index.html 13 个 script 被注释" | `grep -c '<!-- <script' web/index.html` | 13 | ✅ 确认（已迁移面板的 script 已注释） |
| "index.html 9 个活跃 script 引用" | `grep '<script src="js/' web/index.html` | app.js/i18n.js/i18n/en.js/i18n/zh.js/notifications.js/websocket.js/ws-dispatcher.js/chat.js/sessions.js + 2 个 lib/ | ✅ 确认 |
| "chat.js 588 行" | `wc -l web/js/chat.js` | 588 | ✅ 确认 |
| "sessions.js 243 行" | `wc -l web/js/sessions.js` | 243 | ✅ 确认 |
| "websocket.js 278 行" | `wc -l web/js/websocket.js` | 278 | ✅ 确认 |
| "ws-dispatcher.js 146 行" | `wc -l web/js/ws-dispatcher.js` | 146 | ✅ 确认 |
| "chat.js 依赖 WS + Dispatcher + Sessions" | `grep -n 'WS\.\|Dispatcher\.\|Sessions\.' web/js/chat.js` | WS.connectSSE, Dispatcher.dispatch/outer/current/reset, Sessions.updateCostDisplay | ✅ 确认紧耦合 |
| "app.js navModules 多数已注释" | `grep 'navModules\|btn-' web/js/app.js` | 9 个注释 + 7 个活跃 | ✅ 确认 |
| "rabbita 有 @websocket.listen" | 读 `websocket/pkg.generated.mbti` | `listen(url, message?=emit(String)) -> Sub` | ✅ 确认可用 |
| "rabbita @http 有 expect_text" | 读 `http/pkg.generated.mbti` | `RequestWithBody::expect_text(emit(Result[String, Error])) -> Cmd` | ✅ 确认（但非流式） |
| "rabbita cell_with_emit 支持 subscriptions" | 读 `pkg.generated.mbti` | `cell_with_emit(model, update, view, subscriptions?)` | ✅ 确认 |
| "chat.js 用 fetch+ReadableStream 做 SSE 流式" | `grep 'getReader\|ReadableStream\|connectSSE' web/js/chat.js` | `WS.connectSSE()` 内 `response.body.getReader()` + `decoder.decode({stream:true})` | ✅ 确认非标准 SSE |
| "chat.js 用 marked.js 渲染 Markdown" | `grep 'marked\|hljs\|katex' web/js/chat.js` | `marked.parse()` + `hljs.highlight()` + `katex.renderToString()` | ✅ 确认 |
| "#04 spec 已归档为 deprecated" | `ls specs/deprecated/` | `2026-07-13_04_frontend-feature-architecture.md` 存在 | ✅ 确认已归档 |

### 详细分析

#### 已迁移面板现状（Phase 0-3.3 成果，21/22 面板）

22 个 rabbita Cell 已在 `web/mb/main/` 落地（Phase 0-2.8: 9 个 + Phase 3: 13 个），全部通过 `cell_with_emit` + bridge.mbt FFI 实现 API 调用。`main.mbt` 中每个 Cell 独立 mount 到对应的 `#xxx-content` 容器。

**Phase 3 新增的架构模式**：
- **i18n 桥接**：`i18n_t(key)` / `i18n_t1(key, param, value)` 获取翻译，`locale_change_cmd(emit, LocaleChanged)` 监听语言切换
- **共享 API helper**：`safe_get` / `safe_post` / `safe_put` / `safe_del`（定义于 brand_cell.mbt，包级共享）
- **JSON helper**：`json_str()` / `json_int()` / `json_bool()` / `json_bool_val()` / `json_array()`
- **跨 Cell 通信**：Cell A 通过 FFI dispatch `CustomEvent` -> Cell B 通过 `@cmd.custom_cmd` + FFI callback 监听 -> `scheduler.add(emit(msg))` 推回 Cell 的 update 循环
  - 已验证模式：Creator cell `ClickEdit(name)` -> `app_show_view("skills-enhanced")` + `skill_editor_open(name)` -> Skills cell `OpenEditor(name)`
- **懒加载**：`app_show_view` FFI 用于跨 Cell 视图切换（Onboard/Creator cell 已使用）
- **`skill_open_cmd`**：`i18n_helpers.mbt` 中的自定义 Cmd，监听 `skill:open-editor` 事件

**尚未完成**：
- Phase 0-2.8 的 9 个 Cell 仍有硬编码英文（i18n 桥接仅在 Phase 3 新 Cell 中使用）
- Chat 集群（4 文件）完全未迁移

#### Chat 集群紧耦合分析

Chat 集群由 4 个文件组成（共 1,255 行），构成前端最复杂的交互系统：

| 文件 | 行数 | 职责 | 依赖关系 |
|------|------|------|---------|
| `chat.js` | 588 | 消息渲染、流式接收、Markdown 渲染、工具调用面板 | → WS.connectSSE, Dispatcher, App, I18n, marked/hljs/katex |
| `websocket.js` | 278 | WS 连接/重连、SSE 流式读取、事件分发 | → App.emit |
| `ws-dispatcher.js` | 146 | RenderTarget 栈（push/pop）、phase 分组卡片 | → Chat.finalizeStream/createStreamingMessage/appendStreamChunk |
| `sessions.js` | 243 | 会话列表 CRUD、切换会话、费用显示 | → Chat.loadHistory, WS.connect, App |

**数据流**：
```
用户输入 → Chat.sendMessage() → WS.connectSSE(POST /api/sessions/:id/chat/stream)
  → fetch ReadableStream → WS.processSSEBuffer(onChunk)
  → Dispatcher.dispatch(event) → Chat.appendStreamChunk/createStreamingMessage/renderToolCallInStream
```

**SSE 流式机制**：非标准 EventSource，而是 `fetch(POST) + response.body.getReader()` 手动读取流，逐 chunk 解析 SSE 格式（`event:` / `data:` 行），通过 `Dispatcher.dispatch` 分发。rabbita 的 `@http.post().expect_text()` 等待完整响应，**无法支持流式渲染**。

**Dispatcher 状态机**：维护一个 `_stack` 数组（RenderTarget 栈），通过 `push`/`pop` 创建嵌套的 phase 卡片（Subagent/Thinking），流式文本渲染到 `current()` 栈顶容器。这是一个有状态的命令式 UI 管理器，需转换为声明式 Model 结构。

#### 剩余面板复杂度分级

| 分级 | 面板 | 文件 | 行数 | 状态 | 核心挑战 |
|------|------|------|------|------|---------|
| 🔴 P0-Remaining | i18n 旧 Cell 回填 | 9 个 Phase 0-2.8 Cell | - | ⬜ Task Pack 5 | brand/backups/version/profile/share/trash/model_test/tasks/browser 硬编码英文 |
| 🔴 P1-High | Chat 集群 | chat+sessions+websocket+ws-dispatcher | 1,255 | ⬜ Task Pack 4 | SSE 流式、Dispatcher 状态机、Markdown FFI |

**已完成迁移的面板（21/22）**：
Meeting ✅ / Marketplace ✅ / Workspace ✅ / Schedules ✅ / Billing ✅ / Media ✅ / Onboard ✅ / Creator ✅ / Git ✅ / Channels ✅ / MCP ✅ / Settings ✅ / Skills ✅（Phase 3 新迁移 13 个）
+ Brand ✅ / Backups ✅ / Version ✅ / Profile ✅ / Share ✅ / Trash ✅ / ModelTest ✅ / Tasks ✅ / Browser ✅（Phase 0-2.8 已迁移 9 个，待 i18n 回填）

#### app.js 残留职责

app.js（~200 行，已从原始 349 行精简）当前承担以下不可移除的职责：
1. `API` 对象（get/post/put/del）- bridge.mbt 通过 FFI 调用
2. `App.init()` - 初始化 i18n + 通知 + WS 监听 + Chat/Sessions 模块
3. `App.showView(name)` - 面板切换（`.view` class toggle），bridge.mbt 通过 `app_show_view` 代理
4. `App.bindEvents()` - 侧边栏、模态框、键盘快捷键、navModules 导航（多数已注释）
5. `App.showNotification/showModal/hideModal` - UI 辅助（bridge.mbt 代理）
6. `App.setupWSListeners()` - WS 事件路由（generation_complete/error/status_update）
7. `App.loadConfig()` / `App.updateModelDisplay()` - 配置加载与显示

**navModules 现状**：9 个注释（已迁移面板）+ 7 个活跃（browser/trash/settings/profile/share/model-test/version/tasks + chat 隐含）

---

## 决策 [必填 - 含为什么]

### 决策 1：i18n 采用 FFI 桥接方案，不做原生 MoonBit 翻译表

**选择**：在 bridge.mbt 新增 `i18n_t(key, params_json) -> String` FFI，包装现有 `I18n.t(key, params)`。所有 Cell view 函数通过 `i18n_t("chat.placeholder")` 获取翻译文本。

**为什么**：
- 现有 `i18n/en.js`（436 行）和 `i18n/zh.js`（436 行）已包含全部翻译键值，重复到 MoonBit 中是维护负担
- `I18n.t()` 支持 `{{param}}` 模板替换，FFI 桥接保持语义一致
- 语言切换时 `I18n.setLocale()` 会 dispatch `i18n:locale-changed` 事件，rabbita Cell 可监听此事件触发重渲染
- Phase 4 移除 `i18n.js` 后，可将翻译表迁移为 MoonBit `Map[String, String]`，但当前阶段保持桥接以降低风险

### 决策 2：Chat 集群整体迁移，不拆分为独立 Phase

**选择**：chat.js + sessions.js + websocket.js + ws-dispatcher.js 作为单一任务包迁移，产出 1-2 个 Cell（ChatCell + SessionsCell）。

**为什么**：
- 四文件紧耦合：sessions.switchSession → Chat.loadHistory → WS.connect；Chat.sendMessage → WS.connectSSE → Dispatcher.dispatch
- 拆分迁移会引入临时桥接代码（Cell 调 legacy JS 的 Chat 方法），增加复杂度且无法独立验证
- rabbita 的 `@websocket.listen` Sub 可替代 websocket.js 的连接/重连逻辑，Sessions 切换时通过 Msg 重新订阅

### 决策 3：SSE 流式通过自定义 FFI Sub 实现，不使用 @http.expect_text

**选择**：在 bridge.mbt 新增 `js_connect_sse(session_id, message, emit_chunk, emit_done, emit_error)` FFI，内部用 `fetch + ReadableStream.getReader()` 逐 chunk 读取，通过 callback 将 chunk 推回 MoonBit 端。

**为什么**：
- rabbita `@http.post().expect_text()` 等待完整响应，不支持流式渲染
- 流式 UX 是核心体验（用户看到 token 逐个生成），不能降级为等待完整响应后一次性渲染
- 自定义 Sub 可复用现有 `WS.connectSSE` 的全部 SSE 解析逻辑（`processSSEBuffer`），只是把回调从 `Dispatcher.dispatch` 改为 `emit(Msg)`

### 决策 4：Markdown 渲染通过 FFI 桥接 marked.js + hljs + KaTeX

**选择**：在 bridge.mbt 新增 `js_render_markdown(text) -> String` FFI，包装 `chat.js` 中现有的 `renderMarkdown()` 逻辑（marked.parse + hljs.highlight + katex.renderToString + 代码块 copy 按钮 HTML），返回预渲染 HTML 字符串。rabbita Cell 通过 `@html.raw_html(html_string)` 渲染。

**为什么**：
- marked.js（~30KB min）+ hljs（~50KB min）+ KaTeX 是成熟的 JS 库，MoonBit 端重写不现实
- `raw_html` 是 rabbita 提供的安全 HTML 注入入口，性能足够（Cell diff 只在 Markdown 内容变化时重渲染）
- 代码 copy 按钮的 `onclick` 处理通过全局函数挂载（保持 `Chat.copyCode` 或迁移为 `window.mbCopyCode`）

### 决策 5：Dispatcher 状态机转换为嵌套 Model

**选择**：将 ws-dispatcher.js 的 RenderTarget 栈转换为 ChatModel 中的 `cards : Array[ChatCard]` 字段。每张卡片是一个 `enum ChatCard { Subagent(name, messages), Think(messages), Stream(messages) }`，view 函数递归渲染嵌套结构。

**为什么**：
- 这是 TEA 架构的核心优势：将命令式的 DOM 栈操作（push/pop/createCard）转化为声明式的 Model 结构
- 状态变更通过 Msg 驱动（`SubagentStart(name)` → `model.cards.push(Subagent(...))`），自动 diff/patch
- 卡片的展开/折叠通过 `collapsed : Bool` 字段表达，无需手动 `classList.toggle`

### 决策 6：继续使用 bridge api_get/post/del/put，不切换到 @http

**选择**：Phase 3 面板继续通过 bridge.mbt 的 `api_get/api_post/api_put/api_del` 调用 API，不迁移到 rabbita `@http.get/post().expect_json()`。

**为什么**：
- bridge 方案在 Phase 0-2.8 已验证可行，9 个 Cell 全部使用此模式
- `@http.expect_json` 要求为每个 API 响应类型定义 `@json.FromJson` 实例（MoonBit struct + trait impl），工作量大且容易遗漏字段
- bridge 返回 `Json` 值，Cell 手动提取字段，虽然类型安全性较低，但开发速度更快且与现有 Cell 一致
- Phase 4 可考虑将高频 API 逐步迁移到 `@http` + 类型化 struct，作为独立优化任务

### 决策 7：面板懒加载通过 app_show_view 桥接实现

**选择**：在 bridge.mbt 新增 `app_show_view` FFI（包装 `App.showView`），并在 `app.js` 的 `showView` 中 dispatch 一个自定义事件。rabbita 通过 `@sub.custom_sub` 或 `window.addEventListener` 桥接监听此事件，当对应 view 被激活时 emit `ViewShown` Msg，Cell 在 `ViewShown` 时才发起数据加载。

**为什么**：
- 当前所有 Cell 在 `Init`（页面加载时）即拉取数据，对 MCP（393 行）、Channels 等重面板造成不必要的初始负载
- 但简单面板（Meeting、Marketplace）的 `Init` 拉取开销可忽略，不需要懒加载
- 懒加载机制作为可选模式，复杂面板迁移时按需启用

### 决策 8：#04 spec 归档为 superseded

**选择**：已将 `specs/active/2026-07-13_04_frontend-feature-architecture.md` 移动到 `specs/deprecated/`，标注状态为「被 rabbita 迁移取代」。✅ 已完成。

**为什么**：
- #04 的 store/view 拆分已证明不足以解决响应式/类型安全问题（rabbita 迁移文档 §十 已论证）
- #04 中的部分任务（API 抽取到 core/api.js、导航逻辑抽取到 core/navigation.js）已被 bridge.mbt 和 app.js showView 取代
- 保留在 active/ 会造成双线推进的混淆

---

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `web/mb/main/bridge.mbt` | ✅ 已修改（Phase 3 部分） | Phase 3 已新增 i18n_t/i18n_get_locale/i18n_on_locale_changed/app_show_view/skill_editor_open/on_skill_open_editor；Task Pack 4 需新增 js_connect_sse/js_render_markdown 等 |
| `web/mb/main/main.mbt` | 修改 | 新增各面板 Cell 的 mount 调用 |
| `web/mb/main/moon.pkg` | 修改 | 新增 `rabbita/websocket` 依赖（Chat WS 订阅） |
| `web/mb/main/chat_cell.mbt` | 新建 | Chat Cell（Model/Msg/view，含 Dispatcher 状态机转换） |
| `web/mb/main/sessions_cell.mbt` | 新建 | Sessions Cell（会话列表 + 切换 + 费用） |
| `web/mb/main/settings_cell.mbt` | ✅ 已创建 | Settings Cell |
| `web/mb/main/skills_cell.mbt` | ✅ 已创建 | Skills Cell（含代码编辑器） |
| `web/mb/main/mcp_cell.mbt` | ✅ 已创建 | MCP Cell |
| `web/mb/main/channels_cell.mbt` | ✅ 已创建 | Channels Cell |
| `web/mb/main/schedules_cell.mbt` | ✅ 已创建 | Schedules Cell |
| `web/mb/main/billing_cell.mbt` | ✅ 已创建 | Billing Cell |
| `web/mb/main/git_cell.mbt` | ✅ 已创建 | Git Panel Cell |
| `web/mb/main/workspace_cell.mbt` | ✅ 已创建 | Workspace Cell |
| `web/mb/main/creator_cell.mbt` | ✅ 已创建 | Creator Cell |
| `web/mb/main/onboard_cell.mbt` | ✅ 已创建 | Onboard Cell |
| `web/mb/main/media_cell.mbt` | ✅ 已创建 | Media Cell |
| `web/mb/main/marketplace_cell.mbt` | ✅ 已创建 | Marketplace Cell |
| `web/mb/main/meeting_cell.mbt` | ✅ 已创建 | Meeting Cell（占位面板） |
| `web/mb/main/*_cell.mbt`（Phase 0-2.8 的 9 个） | ⬜ 待 Task Pack 5 | 回填 i18n_t 调用，替换硬编码英文字符串 |
| `web/index.html` | ✅ 部分完成 | 13 个 script 已注释；Task Pack 4 后注释 chat/sessions/websocket/ws-dispatcher；Task Pack 5 后全部移除 |
| `web/js/app.js` | 修改→最终删除 | 逐步移除 navModules/init 守卫，最终删除 |
| `web/js/chat.js` | 删除 | 被 chat_cell.mbt 取代 |
| `web/js/sessions.js` | 删除 | 被 sessions_cell.mbt 取代 |
| `web/js/websocket.js` | 删除 | 被 @websocket.listen + bridge 取代 |
| `web/js/ws-dispatcher.js` | 删除 | 被 ChatModel.cards 取代 |
| `web/js/settings.js` | ✅ 已删除 | 被 settings_cell.mbt 取代 |
| `web/js/skills.js` | ✅ 已删除 | 被 skills_cell.mbt 取代 |
| `web/js/skills_enhanced.js` | ✅ 已删除 | 被 skills_cell.mbt 取代 |
| `web/js/mcp.js` | ✅ 已删除 | 被 mcp_cell.mbt 取代 |
| `web/js/channels.js` | ✅ 已删除 | 被 channels_cell.mbt 取代 |
| `web/js/schedules.js` | ✅ 已删除 | 被 schedules_cell.mbt 取代 |
| `web/js/billing.js` | ✅ 已删除 | 被 billing_cell.mbt 取代 |
| `web/js/git_panel.js` | ✅ 已删除 | 被 git_cell.mbt 取代 |
| `web/js/workspace.js` | ✅ 已删除 | 被 workspace_cell.mbt 取代 |
| `web/js/creator.js` | ✅ 已删除 | 被 creator_cell.mbt 取代 |
| `web/js/onboard.js` | ✅ 已删除 | 被 onboard_cell.mbt 取代 |
| `web/js/media.js` | ✅ 已删除 | 被 media_cell.mbt 取代 |
| `web/js/marketplace.js` | ✅ 已删除 | 被 marketplace_cell.mbt 取代 |
| `web/js/meeting.js` | ✅ 已删除 | 被 meeting_cell.mbt 取代 |
| `web/js/i18n.js` | 保留→Phase 4 删除 | i18n 框架，Phase 3 期间继续提供翻译服务 |
| `web/js/i18n/en.js` | 保留→Phase 4 删除 | 英文翻译表 |
| `web/js/i18n/zh.js` | 保留→Phase 4 删除 | 中文翻译表 |
| `web/js/notifications.js` | 保留→Phase 4 删除 | 通知管理器，bridge.mbt 代理调用 |
| `web/js/lib/marked.min.js` | 保留 | Markdown 渲染库，Chat Cell 通过 FFI 调用 |
| `web/js/lib/highlight.min.js` | 保留 | 语法高亮库，Chat Cell 通过 FFI 调用 |
| `specs/active/2026-07-13_04_frontend-feature-architecture.md` | 移动→`specs/completed/` | 归档为 superseded |

### 不涉及文件

- **后端 API 契约**：不修改任何 `lib/server/handlers_*.mbt` 或路由定义，所有 Cell 复用现有 API 端点
- **CSS 样式**：不修改 `web/styles.css` 或 inline style，Cell 复用现有 CSS class
- **rabbita 框架本身**：不修改 `.mooncakes/` 下的 rabbita 源码
- **TUI 代码**：不涉及 `cmd/` 或 `lib/tui/` 的任何改动

---

## 实施计划 [必填]

### 任务包 0：i18n 基础设施建设 ✅ 已完成

**前置条件**：无（所有后续任务包依赖此包）

**步骤**：
1. 在 `bridge.mbt` 新增 `i18n_t(key : String, params_json : String) -> String` FFI，包装 `I18n.t(key, JSON.parse(params_json || '{}'))`
2. 在 `bridge.mbt` 新增 `i18n_get_locale() -> String` FFI，包装 `I18n.getLocale()`
3. 在 `bridge.mbt` 新增 `i18n_on_locale_changed(callback)` FFI，注册 `window.addEventListener('i18n:locale-changed', ...)` 回调，通过 rabbita `@sub.custom_sub` 或 `@cmd.effect` emit `LocaleChanged` Msg
4. 回填已有 9 个 Cell 的硬编码字符串：将 `"Backups"` 等替换为 `i18n_t("backups.title", "{}")`，提取翻译 key 对照 `i18n/en.js` 和 `i18n/zh.js`
5. `warren build` + `moon check` 验证

**验证标准**：
- [ ] bridge.mbt 包含 `i18n_t` + `i18n_get_locale` 函数
- [ ] 9 个已存在 Cell 的可见字符串全部通过 `i18n_t()` 获取
- [ ] 浏览器切换语言后，rabbita Cell 面板文本同步切换
- [ ] `moon check` 0 errors / `warren build` 通过

### 任务包 1：低复杂度面板迁移 ✅ 已完成（`8599f0d`）

**前置条件**：任务包 0 完成

**面板**：Meeting（68 行，占位）、Marketplace（184 行）、Workspace（206 行）

**步骤**（每面板 1 commit）：
1. 创建 `meeting_cell.mbt`：Model 仅含 `active_tab`；view 渲染占位内容（复用 `meeting.js` 的 HTML 结构）；挂载到 `#meeting-content`
2. 创建 `marketplace_cell.mbt`：Model 含 extensions 列表 + loading 状态；`GET /api/extensions` 拉取；挂载到 `#marketplace-content`
3. 创建 `workspace_cell.mbt`：Model 含文件树 + 当前路径；`GET /api/workspace` 拉取；挂载到 `#workspace-content`
4. 每面板迁移后：修改 `index.html`（注释/移除 `<script>`）、修改 `app.js`（移除 init 守卫 + navModules 条目）、`git rm` 旧 JS 文件
5. 所有字符串通过 `i18n_t()` 获取

**验证标准**：
- [ ] 3 个面板功能不回归（手动浏览器验证）
- [ ] 旧 JS 文件删除，`grep` 无残留引用
- [ ] i18n 字符串正常显示

### 任务包 2：标准复杂度面板迁移 ✅ 已完成（8 个面板，`32a0870`-`99286ee`）

**前置条件**：任务包 1 完成

**面板**（按风险从低到高）：Schedules（239 行）、Billing（275 行）、Media（286 行）、Onboard（285 行）、Creator（321 行）、Git（365 行）、Channels（352 行）、MCP（393 行）

**步骤**（每面板 1 commit，按 Phase 1 模板复制）：
1. 读取旧 JS 文件，提取 API 端点、Model 字段、交互逻辑
2. 创建 `xxx_cell.mbt`：定义 `priv struct XxxModel` + `enum XxxMsg` + `build_xxx_cell` 函数
3. view 函数复用旧 JS 的 HTML 结构（CSS class 不变），所有字符串通过 `i18n_t()` 获取
4. 在 `main.mbt` 新增 mount 调用到 `#xxx-content`
5. 修改 `index.html`（移除 `<script>`）、修改 `app.js`（移除 init 守卫 + navModules 条目）、`git rm` 旧 JS
6. 对重面板（MCP/Channels/Git）启用懒加载（任务包 0 的 `app_show_view` 机制）

**验证标准**：
- [ ] 每个面板迁移后功能不回归
- [ ] 旧 JS 文件删除，无残留引用
- [ ] `warren build` 产物大小合理（预计 < 400KB）

### 任务包 3：Settings + Skills 迁移 ✅ 已完成（`3bff8b4` + `ff57eec`）

**前置条件**：任务包 2 完成

**步骤**：
1. **Settings Cell**（`settings_cell.mbt`）：
   - Model：`config` + `models` + `loading` + `saving` + `error`
   - API：`GET /api/config` + `GET /api/config/models` + `PUT /api/config`
   - view：配置表单（模型选择、温度等参数）+ 模型列表
   - 挂载到 `#settings-content`
2. **Skills Cell**（`skills_cell.mbt`）：
   - 合并 `skills.js`（136 行）+ `skills_enhanced.js`（321 行）为单一 Cell
   - Model：`skills_list` + `store_skills` + `creator_skills` + `current_skill` + `content` + `modified`
   - API：`GET /api/skills` + `GET /api/skills/:name/content` + `PUT /api/skills/:name/content`
   - **代码编辑器**：通过 FFI 桥接 `<textarea>` + 基础高亮（或保留简化版纯 textarea）
   - 挂载到 `#skills-enhanced-content`（当前 `skills.js` 渲染到 `#skills-content`，需整合两个容器）
3. 每面板迁移后清理旧 JS + index.html + app.js

**验证标准**：
- [ ] Settings 面板配置保存正常
- [ ] Skills 面板代码查看/编辑/保存正常
- [ ] 旧 JS 文件删除，无残留引用

#### 实际实现记录

**Task Pack 0 实际实现**：
- bridge.mbt 新增：`i18n_t(key, params_json)` / `i18n_get_locale()` / `i18n_on_locale_changed(callback)`
- i18n_helpers.mbt 新增：`t(key)` / `t1(key, param, value)` 辅助函数 + `locale_change_cmd(emit, to_msg)` 模式
- 所有 Phase 3 新 Cell 在 Init 时注册 `locale_change_cmd(emit, LocaleChanged)` 监听语言切换
- ⚠️ 注意：Phase 0-2.8 的 9 个旧 Cell 仍有硬编码英文，需在 Task Pack 5 中回填

**Task Pack 1-3 实际实现**：
- 13 个面板全部迁移，每个 1 commit
- 每面板模式：读取旧 JS -> 创建 `xxx_cell.mbt` -> mount 到 `#xxx-content` -> 注释 index.html script -> 注释 app.js init -> git rm 旧 JS
- 新增共享 helper：`safe_get/safe_post/safe_put/safe_del`（brand_cell.mbt 包级共享）、`json_str/json_int/json_bool/json_bool_val`、`input_style/textarea_style`
- 跨 Cell 通信模式：Creator cell -> `CustomEvent('skill:open-editor')` -> Skills cell 监听 -> `OpenEditor(name)` Msg

**Task Pack 3b 关键创新（跨 Cell 通信）**：
- bridge.mbt: `skill_editor_open(name)` 改为 dispatch `CustomEvent`（不再直接调用 JS 方法）
- bridge.mbt: 新增 `on_skill_open_editor(callback)` 监听 `skill:open-editor` 事件
- i18n_helpers.mbt: 新增 `skill_open_cmd(emit, to_msg)` 自定义 Cmd
- creator_cell.mbt: `ClickEdit(name)` 先 `app_show_view("skills-enhanced")` 再 `skill_editor_open(name)`
- skills_cell.mbt: Init 时注册 `skill_open_cmd(emit, name => OpenEditor(name))`

### 任务包 4：Chat 集群迁移（预估 3-4 天）

**前置条件**：任务包 0-3 完成（i18n + 所有非 Chat 面板已迁移）

**这是整个 Phase 3 的核心与最高风险任务。**

**步骤**：

#### 4a. 桥接层扩展（0.5 天）
1. `bridge.mbt` 新增 `js_render_markdown(text : String) -> String`：包装 `Chat.renderMarkdown()` 逻辑（marked + hljs + katex + copy 按钮 HTML）
2. `bridge.mbt` 新增 `js_connect_sse(session_id : String, message : String) -> @js.Promise`：包装 `WS.connectSSE()`，返回一个可 `.then()` 的 Promise。chunk/done/error 通过自定义事件或 SharedArrayBuffer 推回 MoonBit
3. `bridge.mbt` 新增 `js_disconnect_ws()`：包装 `WS.disconnect()`
4. `bridge.mbt` 新增 `js_cancel_generation(session_id : String)`：包装 `fetch(POST /api/sessions/:id/cancel)`
5. `bridge.mbt` 新增 `js_scroll_to_bottom(container_id : String)`：滚动聊天容器到底部
6. `bridge.mbt` 新增 `js_copy_code(btn_text : String)`：代码 copy 功能
7. `web/mb/main/moon.pkg` 新增 `rabbita/websocket` 依赖

#### 4b. ChatCell Model + Msg 设计（1 天）
1. 定义 `ChatModel`：
   ```
   messages : Array[ChatMessage]       // 历史消息
   cards : Array[ChatCard]              // Dispatcher 栈转换后的嵌套卡片
   stream_buffer : String               // 当前流式缓冲
   is_streaming : Bool
   stream_card_index : Option[Int]     // 当前流式渲染目标卡片索引
   input_text : String
   ```
2. 定义 `enum ChatCard`：
   ```
   Subagent(name : String, messages : Array[ChatMessage], collapsed : Bool)
   Think(messages : Array[ChatMessage], collapsed : Bool)
   Stream(messages : Array[ChatMessage])  // 主流式区域
   ```
3. 定义 `enum ChatMsg`：
   ```
   Init
   LoadHistory(session_id)
   HistoryLoaded(Result)
   Send
   StreamChunk(String)           // SSE chunk
   StreamDone
   StreamError(String)
   CancelGeneration
   SubagentStart(String)
   SubagentEnd
   ThinkStart
   ThinkEnd
   ToolExecuting(Json)
   ToolExecuted(Json)
   ToggleCardCollapse(Int)
   CopyCode(String)
   UpdateInput(String)
   LocaleChanged
   ```
4. `update` 函数：处理流式 chunk 追加、卡片 push/pop、消息列表更新
5. `view` 函数：递归渲染 `cards` 数组（每张卡片含 header + body），流式文本通过 `js_render_markdown` 转 HTML 后 `raw_html` 渲染

#### 4c. SessionsCell 设计（0.5 天）
1. 定义 `SessionsModel`：`sessions : Array[Json]` + `search_filter : String` + `current_session_id : String`
2. 定义 `SessionsMsg`：`Init / LoadSessions / SessionsLoaded / CreateSession / DeleteSession / SwitchSession / SearchInput / NewSessionDialog / CreateFromDialog`
3. `SwitchSession(id)` 时：emit `ChatMsg.LoadHistory(id)` + 调用 `js_connect_ws(id)` 建立 WS 连接
4. SessionsCell 与 ChatCell 需要跨 Cell 通信：通过 `app_show_view` 或自定义全局事件桥接，Sessions 切换时通知 Chat 加载历史

#### 4d. 整合与清理（1-1.5 天）
1. 在 `main.mbt` 挂载 ChatCell 到 `#chat-messages`（或新建子容器）、SessionsCell 到 `#session-list`
2. 用 `@websocket.listen` Sub 替代 `websocket.js` 的 WS 连接/重连：SessionsCell 在 `SwitchSession` 时动态切换 Sub URL
3. SSE 流式通过 `js_connect_sse` FFI + `@sub.custom_sub` 实现声明式订阅
4. `App.setupWSListeners()` 逻辑迁移到 ChatCell 的 `subscriptions` 函数
5. 修改 `index.html`：移除 `<script src="js/chat.js">`、`sessions.js`、`websocket.js`、`ws-dispatcher.js`
6. 修改 `app.js`：移除 `Chat.init()`、`Sessions.init()`、`setupWSListeners()`、`WS.on()` 调用
7. `git rm` 4 个旧 JS 文件
8. 浏览器端到端验证：创建会话 → 发送消息 → 流式渲染 → 工具调用 → 取消 → 切换会话 → 删除会话

**验证标准**：
- [ ] Chat 消息流式渲染正常（token 逐个出现，非等待完整响应）
- [ ] Markdown 代码块语法高亮 + copy 按钮正常
- [ ] KaTeX 数学公式正常渲染
- [ ] Subagent/Thinking 卡片可折叠展开
- [ ] 工具调用面板（tool_executing/tool_executed）正常显示
- [ ] 会话切换正常加载历史 + 建立 WS 连接
- [ ] 取消生成功能正常
- [ ] WS 断线重连正常
- [ ] 会话列表搜索/创建/删除正常
- [ ] 4 个旧 JS 文件删除，无残留引用
- [ ] `moon check` 0 errors / `warren build` 通过
- [ ] `moon build --target native --release cmd` 0 errors

### 任务包 5：Phase 4 全量清理与架构固化（预估 1 天）

**前置条件**：任务包 0-4 全部完成（所有面板已迁移）

**步骤**：
1. **移除 app.js**：将 `App.showView` 迁移为 rabbita 全局 Sub（`@sub.on_url_changed` 或自定义事件）；将 `App.showNotification/showModal/hideModal` 迁移为 rabbita 原生实现（dialog 包或自定义 Cell）；将 `API` 对象的逻辑吸收进 bridge 或替换为 `@http`；移除键盘快捷键到 rabbita `@sub.on_key_down`
2. **移除 i18n.js + i18n/en.js + i18n/zh.js**：将翻译表转换为 MoonBit `Map[String, String]` 或 `@json.parse` 嵌入的静态 JSON；`i18n_t` 改为读取 MoonBit 本地翻译表
3. **移除 notifications.js**：用 rabbita `@rabbita/dialog` 包或自定义 Toast Cell 替代
4. **简化 index.html**：移除所有 `<script src="js/...">` 引用（保留 `lib/marked.min.js` + `lib/highlight.min.js`），仅保留 `<div id="app">` + `<script type="module" src="mb/index.js">`
5. **移除 bridge.mbt 中的遗留 FFI**：`app_notify/app_show_modal/app_hide_modal` 替换为 rabbita 原生；`api_get/post/del/put` 替换为 `@http` 或保留（视评估结果）
6. **移除 #mb-root debug cell**：main.mbt 中的 counter + TestNotify/TestModal 按钮移除
7. **归档 #04 spec**：`git mv specs/active/2026-07-13_04_frontend-feature-architecture.md specs/completed/`
8. **归档 rabbita 迁移 spec**：`git mv specs/active/2026-07-14_web-ui-rabbita-migration.md specs/completed/`
9. **全量验证**：所有面板功能不回归 + `moon check` + `warren build` + `moon build` + 服务冒烟测试

**验证标准**：
- [ ] `web/js/` 目录仅保留 `lib/marked.min.js` + `lib/highlight.min.js`
- [ ] `web/index.html` 不含任何 `js/*.js` 脚本引用（除 lib/）
- [ ] bridge.mbt 仅保留必要的 JS 库桥接（marked/hljs 渲染、SSE 流式、localStorage 等浏览器原生 API）
- [ ] 通知/模态框由 rabbita 原生实现，不依赖 `App.showNotification/showModal`
- [ ] `#04` 和 rabbita 迁移 spec 归档到 `specs/completed/`
- [ ] `moon check` 0 errors / `warren build` 通过 / `moon build --target native --release cmd` 0 errors

---

## 验收标准 [必填]

### 整体验收

- [x] 15 个 legacy JS 面板全部迁移为 rabbita Cell（13 个 Phase 3 + 2 个待 Chat 集群）
- [x] 13 个旧 JS 文件已删除（settings/skills/skills_enhanced/mcp/channels/schedules/billing/git_panel/workspace/creator/onboard/media/marketplace/meeting）
- [ ] Chat 集群 4 个旧 JS 文件删除（chat/sessions/websocket/ws-dispatcher）- 待 Task Pack 4
- [x] `#04` spec 已归档到 `specs/deprecated/`
- [ ] Phase 0-2.8 的 9 个 Cell i18n 回填 - 待 Task Pack 5
- [x] Phase 3 新 Cell 的可见字符串通过 `i18n_t()` 获取，支持中英文切换
- [ ] Chat 流式渲染、Markdown、工具调用、Subagent/Thinking 卡片功能不回归 - 待 Task Pack 4
- [ ] 会话 CRUD、WS 连接/重连、SSE 流式功能不回归 - 待 Task Pack 4
- [ ] `web/js/` 仅保留 `lib/marked.min.js`、`lib/highlight.min.js`（Phase 4 完成后）- 待 Task Pack 5
- [ ] `web/index.html` 仅含 `lib/*.js` + `<script type="module" src="mb/index.js">`（Phase 4 完成后）- 待 Task Pack 5
- [x] `moon check` 0 errors（`web/mb/`）- 439 pre-existing warnings, 0 errors
- [x] `moon build --target js web/mb/main` 通过
- [ ] `moon build --target native --release cmd` 0 errors - 待最终验证
- [ ] 服务冒烟测试 - 待 Task Pack 4 完成后验证

### 每面板迁移验收（通用清单）

- [ ] Cell 挂载到正确的 `#xxx-content` 容器
- [ ] API 调用通过 bridge `api_get/post/del/put` 正常工作
- [ ] 所有可见文本通过 `i18n_t()` 获取
- [ ] 通知/模态框通过 bridge 正常工作
- [ ] 旧 JS 文件删除，`grep` 无残留引用
- [ ] `app.js` navModules + init 守卫移除
- [ ] `index.html` `<script>` 引用移除
- [ ] `warren build` 通过

---

## 风险评估 [必填]

| 风险 | 等级 | 影响范围 | 缓解方案 |
|------|------|---------|---------|
| **SSE 流式 FFI 桥接可靠性** | 🔴 高 | Chat 集群 | `js_connect_sse` 需处理 Promise→Cmd 转换、chunk 回调线程安全。先用 POC 验证单个 chunk 能通过 FFI 推回 MoonBit 端并触发重渲染，再全面实现。若 FFI 回调不可行，降级为保留 `websocket.js` 作为 SSE 传输层，仅迁移 UI 层到 Cell |
| **Chat 集群迁移工作量超预期** | 🔴 高 | 任务包 4 | 1,255 行紧耦合代码 + 状态机转换。预留 3-4 天，若超时则拆分：先迁移 Sessions（独立于 Chat 的会话列表/CRUD），再迁移 Chat（核心流式 + Dispatcher）。Sessions 迁移时保留对 legacy Chat 的调用（临时 bridge），Chat 迁移时再切断 |
| **跨 Cell 通信** | 🟡 中 | Chat + Sessions | rabbita Cell 间无内建消息传递。方案：通过 `window.dispatchEvent(CustomEvent)` + `@sub.custom_sub` 监听，或引入一个共享 Model（将 Chat + Sessions 合并为单一 Cell）。推荐后者，避免跨 Cell 通信复杂度 |
| **Markdown FFI 性能** | 🟡 中 | Chat | `js_render_markdown` 每次 chunk 到达时调用 marked.parse + hljs，高频调用可能卡顿。缓解：debounce 150ms（同 legacy chat.js 的 `_renderTimeout`），或仅在 streamDone 时做最终渲染（牺牲流式 UX） |
| **i18n_t 回填遗漏** | 🟡 中 | 任务包 0 | 9 个 Cell 共有数百个硬编码字符串，逐一替换易遗漏。缓解：迁移时逐 Cell 用 `grep` 搜索引号字符串，构建 key→text 映射表对照 `i18n/en.js` |
| **marked.js 依赖残留** | 🟢 低 | Phase 4 | `lib/marked.min.js` + `lib/highlight.min.js` 是纯函数库，Phase 4 保留为 `<script>` 引入不影响架构目标。未来可考虑 MoonBit 绑定或 WASM 版替代 |
| **warren build 产物膨胀** | 🟢 低 | 全部 | 15 个 Cell + bridge 预计 < 500KB minified（当前 9 个 Cell = 231KB）。rabbita runtime 固定 ~15KB gz，线性增长可控 |
| **浏览器兼容性** | 🟢 低 | Chat | `fetch + ReadableStream` 需现代浏览器（Chrome 43+ / Firefox 65+）。项目目标用户为开发者，浏览器版本不是问题 |
| **app.js 移除时机** | 🟡 中 | Phase 4 | app.js 的 `API` 对象被 bridge.mbt 依赖。移除 app.js 前必须将 `API.get/post/put/del` 的逻辑迁移到 bridge.mbt 内联实现（直接用 `fetch`），或切换到 `@http` 包 |

---

## 依赖关系 [必填]

- **前置依赖**：Phase 0-2.8 已完成（`specs/completed/2026-07-14_web-ui-rabbita-migration.md`）。9 个 Cell + bridge.mbt + main.mbt 挂载 + index.html 注入已就绪
- **后置依赖**：
  - `specs/active/2026-07-13_05_i18n-complete-translation.md`（i18n 完整翻译）：本 Spec 任务包 0 解决前端 i18n 接入，后端 i18n 翻译补全仍需 #05 spec 推进
  - `specs/active/2026-07-13_06_frontend-components.md`（前端组件）：本 Spec 完成后，前端组件可在 rabbita Cell 架构下统一实现
  - 未来 Web 路由（如 `@sub.on_url_changed` 做 SPA 路由）依赖本 Spec Phase 4 完成（app.js showView 移除后才能实现真正的 rabbita 路由）

---

## 对抗性审查记录

本 Spec 在撰写过程中进行了以下对抗性自查：

### Q1: SSE 流式 FFI 是否可行？MoonBit extern "js" 能否处理异步回调？

**验证**：bridge.mbt 已有 `api_get_promise` / `api_post_promise` 等 FFI 返回 `@js.Promise`，通过 `.wait()` 在 MoonBit async 函数中消费。但 SSE 流式需要多次回调（每个 chunk），不是单次 Promise。`@js.Promise` 只能 resolve 一次。

**结论**：SSE 流式不能直接用 `@js.Promise`。需要用 `@sub.custom_sub` + `window.addEventListener` 方案：JS 端在 `js_connect_sse` 内部用 `window.dispatchEvent(CustomEvent('mb-sse-chunk', {detail: chunk}))` 推送 chunk，MoonBit 端用 `@sub.custom_sub` 监听 `mb-sse-chunk` 事件。这是一个未验证的架构模式，任务包 4a 需先做 POC。**风险等级提升为 🔴 高。**

### Q2: Chat + Sessions 合并为单一 Cell 是否合理？

**质疑**：决策 5 建议合并，但 Sessions（侧边栏会话列表）和 Chat（主区域消息）在 DOM 上分属不同容器（`#session-list` vs `#chat-messages`），一个 Cell 只能 mount 到一个容器。

**修正**：rabbita `new(cell).mount(id)` 只能挂载到一个 DOM 容器。若 Sessions 和 Chat 需要渲染到不同容器，必须用两个独立 Cell。跨 Cell 通信方案：`window.dispatchEvent(CustomEvent)` + `@sub.custom_sub` 监听，或让 SessionsCell 持有 `current_session_id` 并通过全局变量/shared state 传递给 ChatCell。**决策 5 修正为：使用两个独立 Cell，通过 `window.dispatchEvent` 桥接跨 Cell 通信。**

### Q3: 任务包 4 的 3-4 天预估是否现实？

**质疑**：Chat 集群 1,255 行 + SSE FFI + Dispatcher 状态机转换 + Markdown FFI + WS 订阅，是整个迁移中最复杂的部分。Phase 2 的 Browser Cell（480 行旧 JS）就花了大量时间修复 48 个编译错误。

**评估**：3-4 天是乐观估计。更现实的预估是 5-7 天，包含 POC 验证 + 调试 + 浏览器手测。建议在任务包 4 前设置一个 checkpoint：先做 SSE FFI POC（0.5 天），验证 chunk 能推回 MoonBit 并触发重渲染。若 POC 失败，降级方案为保留 `websocket.js` 作为传输层，仅迁移 UI 层（Dispatcher + Chat 渲染）到 Cell。

### Q4: bridge.mbt 持续增长是否可持续？

**验证**：Phase 3 后实际有 28 个 extern 函数（Phase 0-2.8: 22 + Phase 3 新增 6: i18n_t/i18n_get_locale/i18n_on_locale_changed/app_show_view/skill_editor_open/on_skill_open_editor）。Task Pack 4 预计新增 ~10 个（SSE、Markdown、scroll、copy_code 等），达到 ~38 个。Phase 4 移除 app.js 后可减少 ~10 个（notify/modal/hide/api_*），净增 ~8 个。

**结论**：可接受。bridge.mbt 本质是「legacy interop 层」，会随 legacy JS 的减少而收缩。Phase 4 后预计 ~30 个函数，主要是浏览器原生 API 封装（localStorage、scroll、download、日期格式化）+ JS 库桥接（marked/hljs）。不需要重构。

### Q5: 现有 9 个 Cell 的 i18n 回填是否会引入回归？

**状态更新**：Task Pack 0 仅在 Phase 3 新 Cell 中实现了 i18n 桥接，Phase 0-2.8 的 9 个旧 Cell 仍有硬编码英文。回填推迟到 Task Pack 5。

**质疑**：逐一替换硬编码字符串为 `i18n_t(key)` 调用，如果 key 不存在于翻译表中，`I18n.t()` 返回 key 本身（而非英文文本），可能导致面板显示翻译 key 而非文本。

**缓解**：回填时对照 `i18n/en.js` 确认每个 key 存在。对于 Cell 新增的文本（不在原 JS 中的），需要在 `i18n/en.js` 和 `i18n/zh.js` 中补充对应 key。Task Pack 5 包含翻译 key 补全步骤。

### Q6: 跨 Cell 通信模式是否已在实践中验证？

**验证**：Task Pack 3b（Skills cell）已实现并验证了跨 Cell 通信模式：Creator cell -> `CustomEvent('skill:open-editor')` -> Skills cell 监听 -> `OpenEditor(name)` Msg。具体实现：
- bridge.mbt: `skill_editor_open(name)` dispatch CustomEvent
- bridge.mbt: `on_skill_open_editor(callback)` 监听事件
- i18n_helpers.mbt: `skill_open_cmd(emit, to_msg)` 自定义 Cmd
- 结论：**模式已验证可行**，Task Pack 4 的 Chat <-> Sessions 跨 Cell 通信可复用此模式。

### Q7: `safe_get/safe_post/safe_put/safe_del` 是否可靠？

**验证**：Phase 3 的 13 个 Cell 全部使用 `safe_get/safe_post/safe_put/safe_del`（定义于 brand_cell.mbt，包级共享）替代原始的 `api_get_promise/api_post_promise`。这些 helper 内部用 `@cmd.perform` + `noraise` async 块包装 Promise 调用，返回 `Result[Json, Unit]`。

**结论**：模式稳定，13 个 Cell 无一因此出问题。Task Pack 4 的 Chat Cell 可继续使用。

---

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-14 | 初始版本：Phase 3+4 增量规划（i18n 基础设施 + 15 面板迁移 + Chat 集群 + 全量清理） | 整合 #04（store/view）与 rabbita 迁移文档中未完成的 Phase 3/4 工作 |
| 2026-07-15 | Task Pack 0-3 完成：i18n 基础设施 + 13 面板迁移（Meeting/Marketplace/Workspace/Schedules/Billing/Media/Onboard/Creator/Git/Channels/MCP/Settings/Skills） | 21/22 面板已迁移，仅剩 Chat 集群 |
| 2026-07-15 | 更新 spec 状态：标记 Task Pack 0-3 为已完成，更新验证记录和进度总览 | 同步 spec 文档与实际开发进度 |
