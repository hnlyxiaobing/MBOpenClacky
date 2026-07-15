# Web UI Phase 4 清理 · 移除 app.js / i18n.js / notifications.js / 简化 index.html

> **创建日期**: 2026-07-15
> **最后更新**: 2026-07-15
> **状态**: 草案 — 待对抗评审
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G4（P1 重要功能差距）
> **关联历史 spec**: `specs/completed/2026-07-14_web-ui-rabbita-phase3-spec.md`（Phase 3 全部完成，本 spec 承接其延期项）
> **来源差距**: G4 - Web 前端 Feature-based 架构迁移（rabbita TEA 方案）Phase 4 收尾
> **依赖**: Phase 3 Task Pack 0-4 已完成（commit `08b9c8e`，22/22 面板已迁移）
> **灰度 key**: 无
>
> ## 进度总览
>
> | 任务包 | 状态 | Commit | 说明 |
> |--------|------|--------|------|
> | Task Pack A: Notification 系统迁移 (P1-3) | ⬜ 待开始 | — | 用 rabbita 原生 notification overlay 替代 `notifications.js` |
> | Task Pack B: Modal 系统迁移 | ⬜ 待开始 | — | 替换 `app_show_modal` FFI（仅 chat_cell 使用） |
> | Task Pack C: Stats 面板迁移 | ⬜ 待开始 | — | 将 `App.loadStats` 迁为 `stats_cell.mbt` |
> | Task Pack D: API 包装器迁移 | ⬜ 待开始 | — | 将 `app.js` 的 `API.*` 迁到 MoonBit 原生 `@http` 或 fetch FFI |
> | Task Pack E: Shell / 视图路由 / 键盘快捷键迁移 | ⬜ 待开始 | — | 将 `App.showView` / sidebar / modal close / 键盘绑定迁到 rabbita shell cell |
> | Task Pack F: i18n 字典迁移 (P1-2) | ⬜ 待开始 | — | 将 `i18n.js` + `i18n/en.js` + `i18n/zh.js` 迁到 MoonBit `Map[String, Map[String, String]]` |
> | Task Pack G: index.html 简化 (P1-4) | ⬜ 待开始 | — | 移除静态 `#view-*` 容器和 `data-i18n*` 属性，shell 完全由 rabbita 渲染 |
> | Task Pack Z: 归档旧 JS 文件 (P1-1) | ⬜ 待开始 | — | 删除 `web/js/app.js`，清理所有残留引用 |

---

## 问题描述 [必填]

Phase 3 已完成 22/22 面板的 rabbita 迁移，但 Web UI 仍依赖 3 个 legacy JS 文件和大量静态 HTML 结构：

1. **`web/js/app.js` 仍是协调中枢**（362 行）：提供 `API` 包装器、全局通知代理、模态框、视图切换、配置加载、统计面板、侧边栏/键盘事件绑定。所有 rabbita Cell 通过 `bridge.mbt` FFI 间接调用它。
2. **`web/js/notifications.js` 仍是全局通知容器**（98 行）：23 个 Cell 通过 `app_notify` FFI → `App.showNotification` → `NotificationManager.notify` 显示 toast。
3. **`web/js/i18n.js` + `i18n/en.js` + `i18n/zh.js` 仍是翻译引擎**（85 + 1598 行）：24 个 Cell 通过 `i18n_t` / `i18n_get_locale` / `i18n_on_locale_changed` FFI 调用它；`index.html` 还有 80 个 `data-i18n*` 静态属性依赖 `I18n.translateDOM()`。
4. **`web/index.html` 仍是静态容器大盘**（~428 行）：包含 25 个 `#view-*` / `#*-content` 容器、21 个侧边栏按钮、模态框和通知容器。这些结构本可以由 rabbita shell Cell 动态生成。

这 4 个遗留项互相耦合：
- 删除 `app.js` 前必须先移除 `API.*`、`showNotification`、`showModal`、`showView`、`loadStats`、`loadConfig`、`bindEvents` 的调用方；
- 简化 `index.html` 前必须先把静态翻译属性、静态 view 容器、侧边栏的渲染迁到 rabbita；
- `i18n.js` 删除前必须先把 ~735 个翻译键迁到 MoonBit。

本 Spec 规划 Phase 4 清理，目标是把前端彻底变成「一个极简 HTML 壳 + 一个 rabbita JS bundle」，最终只保留 `marked.min.js`、`highlight.min.js`、KaTeX、qrcode 等纯工具库。

---

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "仅剩 3 个 legacy JS" | `ls web/js/*.js` | `app.js` / `i18n.js` / `notifications.js` | ✅ 确认 |
| "app.js 362 行" | `wc -l web/js/app.js` | 362 | ✅ 确认 |
| "notifications.js 98 行" | `wc -l web/js/notifications.js` | 98 | ✅ 确认 |
| "i18n 字典约 1598 行" | `wc -l web/js/i18n/en.js web/js/i18n/zh.js` | 799 + 799 | ✅ 确认 |
| "index.html 仍有 10 个活跃 script" | `grep -c '<script' web/index.html` | 10 | ✅ 确认 |
| "bridge.mbt 40 个 extern" | `grep -c 'extern "js"' web/mb/main/bridge.mbt` | 40 | ✅ 确认 |
| "app_notify 调用方最多" | `grep -c 'app_notify' web/mb/main/*_cell.mbt` | 147 | ✅ 23 个 Cell 使用 |
| "app_show_modal 仅 chat_cell 使用" | `grep -rn 'app_show_modal' web/mb/main/` | 2 | ✅ 确认 |
| "app_show_view 仅 creator/onboard 使用" | `grep -rn 'app_show_view' web/mb/main/` | 3 | ✅ 确认 |
| "api_* 被 22 个 Cell 使用" | `grep -rn 'safe_get\|safe_post\|safe_put\|safe_del' web/mb/main/` | 100+ | ✅ 确认 |
| "index.html 有 25 个 #view-* 容器" | `grep -c 'id="view-' web/index.html` | 25 | ✅ 确认 |
| "index.html 有 80 个 data-i18n* 属性" | `grep -cE 'data-i18n' web/index.html` | 80 | ✅ 确认 |

### app.js 残留职责拆解

| 职责 | 行号 | 当前调用方 | 迁移目标 |
|------|------|-----------|---------|
| `API.get/post/put/del` | 8–67 | 22 个 Cell 通过 `safe_*` 间接使用 | MoonBit 原生 `@http` 或新的 fetch FFI helper |
| `App.init()` | 74–95 | 页面启动时执行 | 拆分到各 Cell / shell |
| `App.bindEvents()` | 96–144 | 全局事件绑定 | rabbita shell Cell |
| `App.loadConfig()` / `updateModelDisplay()` | 145–173 | 初始化 + 配置变更 | chat_cell / 新的 config_cell |
| `App.showView()` | 188–193 | `creator_cell.mbt`, `onboard_cell.mbt` | shell Cell 视图路由 |
| `App.loadStats()` | 195–230 | `#btn-stats` 点击 | 新的 `stats_cell.mbt` |
| `App.showNotification()` | 238–258 | 23 个 Cell 通过 `app_notify` | rabbita notification overlay |
| `App.showModal()` / `hideModal()` | 260–278 | `chat_cell.mbt` | rabbita modal overlay |
| `mbCopyCode()` | 350–362 | Markdown 输出中的 copy 按钮 | 保留为全局函数或迁到 bridge FFI |

### notifications.js API 与行为

| 函数 | 行为 | 替代方案 |
|------|------|---------|
| `NotificationManager.init()` | 创建 `#notifications-container` | shell Cell view 中直接渲染容器 |
| `NotificationManager.notify(msg, type)` | Toast + icon + 自动关闭（success/info 3s；error/warning 常驻） | rabbita notification model + timer Cmd |
| `NotificationManager.dismiss(id)` | 淡出移除 | Msg 移除指定 toast |
| `NotificationManager.clearAll()` | 清空所有 toast | Msg 清空 |
| `NotificationManager._escapeHtml(text)` | DOM 转义 | MoonBit `String::replace` 或 rabbita text node |

### i18n.js + locale 文件结构

`web/js/i18n.js`：
- `I18n.init()`：从 `localStorage` 或 `navigator.language` 检测语言，注册 `I18nEn`/`I18nZh`，调用 `translateDOM()`。
- `I18n.t(key, params)`：字典查找 + `{{param}}` 替换；回退到英文再回退到 key。
- `I18n.setLocale(locale)`：切换语言、持久化到 `localStorage`、派发 `i18n:locale-changed`。
- `I18n.getLocale()`：返回当前 locale。
- `I18n.translateDOM()`：翻译所有 `[data-i18n]` / `[data-i18n-placeholder]` / `[data-i18n-title]` 静态元素。

`web/js/i18n/en.js` / `zh.js`：各 ~735 键，覆盖所有 22 个面板、sidebar、chat、sessions、stats、notifications、errors。

### index.html 静态结构

当前 `web/index.html` 包含：
- 10 个 `<script>`（5 个 legacy + 5 个工具/lib）
- 25 个 `#view-*` / `#*-content` 容器
- 21 个 sidebar nav 按钮
- `#modal-overlay` + `#modal-title/body/footer`
- `#notifications-container`
- `#session-list`
- 80 个 `data-i18n*` 属性

### rabbita Cell 与遗留 JS 的耦合点

```
23 Cells ──app_notify──► bridge.mbt ──► App.showNotification ──► NotificationManager
22 Cells ──safe_*──────► brand_cell helpers ──► api_get/post/put/del ──► API.* (app.js)
 chat    ──app_show_modal────► App.showModal ──► #modal-overlay
creator/onboard ──app_show_view──► App.showView ──► .view active toggle
all Cells ──i18n_t/i18n_get_locale/i18n_on_locale_changed──► I18n.* (i18n.js)
```

---

## 决策 [必填 - 含为什么]

### 决策 1：先迁移 notification / modal / stats，再动 API 和 shell

**选择**：按 Task Pack A → B → C → D → E → F → G 顺序推进。

**为什么**：
- `app_notify` 有 147 个调用点，但替换只是改变 FFI 目标（从 `App.showNotification` 改为 rabbita 内部函数），不影响 Cell 业务逻辑；可以独立先做。
- `app_show_modal` 仅 2 个调用点，影响面最小，适合第二步。
- `App.loadStats` 是唯一没有对应 rabbita Cell 的功能，必须先创建 `stats_cell.mbt`。
- `API.*` 被 22 个 Cell 共享，迁移风险高，放在 notification/modal/stats 之后。
- `showView`/sidebar/keyboard 是全局交互，必须等所有子面板都准备好才能替换。
- `i18n.js` 迁移字典工作量大但独立，可在任何时间做；放在 shell 之前是因为简化 `index.html` 需要移除静态 `data-i18n*` 属性。

### 决策 2：Notification 用独立 `notification_cell.mbt` 实现，不归入 shell

**选择**：新建 `web/mb/main/notification_cell.mbt`，mount 到 `<body>` 末尾的 `#notifications-container`；提供 `notify(msg, type)` FFI 给 bridge 使用。

**为什么**：
- 通知是全局服务，但用独立 Cell 更符合 rabbita「一个 mount 点一个 Cell」的现有约定。
- 其他 Cell 通过 `app_notify` FFI 调用，内部改为往 `#notifications-container` 对应的 Cell 发 `CustomEvent`，或直接把消息推入一个全局 Model。
- 独立 Cell 便于测试和后续扩展（通知历史、持久化）。

### 决策 3：Modal 用 `chat_cell.mbt` 内部 overlay 实现，不建全局 modal Cell

**选择**：`chat_cell.mbt` 当前 2 个 `app_show_modal` 调用分别是 tools 面板和 cost 详情，直接在 ChatModel 中加入 `modal : Option[Modal]` 字段，view 中渲染一个局部 overlay。

**为什么**：
- 当前只有 chat 面板使用模态框，其他 21 个面板没有模态框需求。
- 全局 modal Cell 会增加跨 Cell 通信复杂度，而 chat 内部模态完全可以在本 Cell 内闭环。
- 如果未来其他面板需要模态框，再提取为共享组件。

### 决策 4：Stats 面板新建 `stats_cell.mbt`，而不是合并到 chat

**选择**：将 `#view-stats` / `#stats-content` 的渲染从 `App.loadStats` 迁移到新的 `stats_cell.mbt`。

**为什么**：
- Stats 是独立功能（调用 `/api/stats`），有自己的 Model 和 view，符合一个面板一个 Cell 的架构。
- 合并到 chat 会让 chat_cell 变得不相关。
- 新建 Cell 后，`#btn-stats` 的点击由 shell Cell 处理视图切换，stats_cell 在 `ViewShown` 时加载数据。

### 决策 5：API 包装器先迁到 MoonBit 的 `@rabbita/http`，不做强类型响应

**选择**：用 `@rabbita/http.get/post/put/delete().expect_json()` 替代 `api_get/post/put/del` FFI，返回 `Json` 值保持与现有 `safe_*` helper 兼容。

**为什么**：
- 消除对 `app.js` 的依赖，同时保持现有 Cell 代码改动最小（只需改 `safe_*` 内部实现）。
- `expect_json` 返回 `Json`，Cell 继续手动提取字段，与当前模式一致。
- 不做强类型响应 struct：虽然更安全，但会大幅增加改动范围（需要为每个 API 定义 struct + FromJson）。
- 如果 `@rabbita/http` 在某些场景下（如上传文件、自定义 header）能力不够，保留少数直接 `fetch` FFI 作为逃生舱。

### 决策 6：Shell Cell 负责 sidebar、view router、keyboard shortcuts、notification container mount

**选择**：新建 `shell_cell.mbt`，它是唯一 mount 到 `#app` 的 Cell；它渲染 sidebar + 25 个 view 容器 + notification container + 处理键盘快捷键（Escape、Ctrl+N）。其他业务 Cell 改为 mount到由 shell 动态生成的容器。

**为什么**：
- 当前 `index.html` 的静态 view 容器只是占位 div，完全可以用 rabbita view 生成。
- 把视图路由集中到 shell 后，`app_show_view` FFI 可以移除，creator/onboard 通过 `CustomEvent` 或直接 Msg 请求切换视图。
- shell Cell 统一处理快捷键和全局事件，避免每个 Cell 各自监听。

### 决策 7：i18n 字典用 MoonBit `Map[String, Map[String, String]]`，按面板拆分文件

**选择**：把 `en.js` / `zh.js` 的 ~735 个键拆成多个 MoonBit 文件（如 `i18n_sidebar.mbt`、`i18n_chat.mbt`、`i18n_settings.mbt` 等），每个文件暴露 `en : Map[String, String]` 和 `zh : Map[String, String]`；`I18n.t()` 在 MoonBit 中实现查找 + `{{param}}` 替换。

**为什么**：
- 单文件 1600 行字典编译/维护都不方便，按面板拆分与 Cell 组织一致。
- MoonBit `Map` 查找是 O(log n)，性能足够。
- 保留 `{{param}}` 替换语义，Cell 调用 `t1(key, param, value)` 无需改动签名。
- `i18n_set_locale` 由 `profile_cell.mbt` 调用，改为更新 shell Cell 的 global locale model 并触发所有 Cell 重渲染。

### 决策 8：index.html 最终只保留工具库 script 和 mb/index.js

**选择**：完成 P1-1/1-2/1-3 后，`index.html` 只保留：
```html
<script src="js/lib/marked.min.js"></script>
<script src="js/lib/highlight.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/katex@.../katex.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/qrcode@.../qrcode.min.js"></script>
<script type="module" src="mb/index.js"></script>
```
以及一个空的 `<body>` 或 `<div id="app"></div>`。

**为什么**：
- 这是 Phase 4 的终点状态：整个 UI 由 rabbita bundle 驱动。
- 工具库（marked/hljs/katex/qrcode）没有 MoonBit 等价实现，继续保留。
- 空 body 需要 shell Cell 在 `Init` 时创建 `#app`。

---

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `web/mb/main/notification_cell.mbt` | 新增 | 全局 toast overlay |
| `web/mb/main/shell_cell.mbt` | 新增 | sidebar + view router + keyboard shortcuts + notification mount |
| `web/mb/main/stats_cell.mbt` | 新增 | 统计面板（替代 `App.loadStats`） |
| `web/mb/main/chat_cell.mbt` | 修改 | 内部实现 modal overlay，移除 `app_show_modal` 调用 |
| `web/mb/main/creator_cell.mbt` | 修改 | `app_show_view` 改为向 shell 发切换视图事件 |
| `web/mb/main/onboard_cell.mbt` | 修改 | `app_show_view` 改为向 shell 发切换视图事件 |
| `web/mb/main/brand_cell.mbt` | 修改 | `safe_*` helper 改用 `@rabbita/http` |
| `web/mb/main/*_cell.mbt` | 修改 | 所有 `app_notify` 调用目标不变（bridge 内部改实现） |
| `web/mb/main/moon.pkg` | 修改 | 新增 `"moonbit-community/rabbita/http"` 依赖（Task Pack D 使用） |
| `web/mb/main/bridge.mbt` | 修改 | 移除 `app_notify`/`app_show_modal`/`app_show_view`/`api_*` FFI；新增/保留必要 helper |
| `web/mb/main/main.mbt` | 修改 | mount shell Cell 到 body/#app；其他 Cell mount 改为由 shell 管理 |
| `web/mb/main/i18n_*.mbt` | 新增 | 按面板拆分的翻译字典（en/zh） |
| `web/mb/main/i18n_helpers.mbt` | 修改 | `t`/`t1` 改为使用 MoonBit 字典，移除 `i18n_t` FFI |
| `web/js/app.js` | 删除 | 所有职责迁出后删除 |
| `web/js/notifications.js` | 删除 | 被 notification_cell 取代 |
| `web/js/i18n.js` | 删除 | 被 MoonBit i18n 实现取代 |
| `web/js/i18n/en.js` | 删除 | 被 MoonBit 字典取代 |
| `web/js/i18n/zh.js` | 删除 | 被 MoonBit 字典取代 |
| `web/index.html` | 修改 | 移除静态 view 容器、sidebar、data-i18n 属性、legacy script 引用 |

### 不涉及文件

- 后端 API 契约：不修改 `lib/web/handlers_*.mbt` 或路由；统计面板仍使用 `/api/stats`。
- CSS 样式：`web/styles.css` 不变，Cell 继续使用现有 class。
- rabbita 框架本身：不修改 `.mooncakes/`。
- TUI：`cmd/` 与 `lib/tui/` 不变。

---

## 实施计划 [必填]

### Task Pack A: Notification 系统迁移 (P1-3)

**前置条件**：无（可独立开始）

**步骤**：
1. 创建 `notification_cell.mbt`：
   - Model：`toasts : Array[Toast]`，其中 `Toast` 含 `id`、`message`、`type`、`dismiss_at : Option[Int64]`。
   - Msg：`Notify(message, type)` / `Dismiss(id)` / `Tick` / `ClearAll`。
   - view：渲染 `#notifications-container` 内的 toast 列表（position fixed top-right）。
2. 在 `bridge.mbt` 中把 `app_notify` 的内部实现从 `App.showNotification` 改为向 `#notifications-container` 对应的 Cell 派发事件，或直接调用新的 JS helper `mbNotify(message, type)`。
3. 在 `main.mbt` 中 mount `notification_cell` 到 `<body>` 末尾（需要一个稳定的 mount 点；如果 index.html 还没简化，先保留 `#notifications-container`）。
4. 验证所有 23 个 Cell 的 `app_notify` 调用仍然能显示 toast。
5. `git rm web/js/notifications.js`；从 `index.html` 移除 `<script src="js/notifications.js">`。

**验证标准**：
- [ ] `moon check` 0 errors
- [ ] `warren build` 成功
- [ ] 浏览器中手动触发一个通知（如保存设置）能正常显示
- [ ] `web/js/notifications.js` 已删除且无残留引用

### Task Pack B: Modal 系统迁移

**前置条件**：Task Pack A 完成（降低 app.js 依赖，但 modal 本身不依赖 A）

**步骤**：
1. 在 `chat_cell.mbt` 的 `ChatModel` 中加入 `modal : Option[ChatModal]`。
2. 定义 `enum ChatModal { Tools, Cost(message : Json) }`。
3. Msg 增加 `ShowModal(ChatModal)` / `HideModal`。
4. view 函数在 chat 面板内部渲染 modal overlay（使用现有 `#modal-overlay` CSS class 或新的局部 overlay class）。
5. 替换 2 个 `app_show_modal` 调用为 `ShowModal(...)`。
6. 从 `bridge.mbt` 移除 `app_show_modal` FFI。

**验证标准**：
- [ ] chat 面板的 tools 和 cost modal 正常弹出/关闭
- [ ] `app_show_modal` FFI 已移除
- [ ] `moon check` / `warren build` 通过

### Task Pack C: Stats 面板迁移

**前置条件**：Task Pack A/B 完成

**步骤**：
1. 创建 `stats_cell.mbt`：
   - Model：`stats : Json` / `loading : Bool` / `error : Option[String]`。
   - Msg：`LoadStats` / `StatsLoaded(Result[Json, String])` / `ViewShown`。
   - view：复用 `App.loadStats` 现有的 HTML 结构渲染统计卡片。
2. 在 `main.mbt` 中 mount `stats_cell` 到 `#stats-content`。
3. 从 `app.js` 移除 `App.loadStats` 及 `#btn-stats` 事件绑定。
4. `#btn-stats` 的点击由后续 shell Cell 处理（在本包中可临时保留 `app_show_view("stats")` 调用，直到 Task Pack E）。

**验证标准**：
- [ ] 点击 sidebar 统计按钮，统计面板正确加载 `/api/stats` 数据
- [ ] `App.loadStats` 代码已从 `app.js` 移除

### Task Pack D: API 包装器迁移

**前置条件**：Task Pack A/B/C 完成

**步骤**：
1. 评估 `@rabbita/http` 能力：确认 `get/post/put/delete` + `expect_json` + header/body 设置是否覆盖当前所有 API 调用。
2. 在 `brand_cell.mbt`（或新建 `api_helpers.mbt`）中重写 `safe_get/post/put/del`：
   - 使用 `@http.get(url).header("Accept", "application/json").expect_json(...)` 等。
   - 保持返回类型为 `Result[Json, String]`，让现有 Cell 调用方零改动。
3. 特殊场景处理：
   - `api_get_text`（`share_cell.mbt` 下载 skill 内容）：使用 `@http.get(url).expect_text()`。
   - 文件上传等 `@http` 不支持的场景：保留少数 `fetch` FFI 或改用 `@http` 的 raw body 能力。
4. 从 `bridge.mbt` 移除 `api_get`/`api_post`/`api_put`/`api_del`/`api_get_text` FFI。
5. 从 `app.js` 移除 `API` 对象。

**验证标准**：
- [ ] 所有现有 API 调用（GET/POST/PUT/DELETE）功能不回归
- [ ] `share_cell.mbt` 的 `api_get_text` 功能不回归
- [ ] `api_*` FFI 已从 `bridge.mbt` 移除
- [ ] `app.js` 中 `API` 对象已移除

### Task Pack E: Shell / 视图路由 / 键盘快捷键迁移

**前置条件**：Task Pack A/B/C/D 完成

**步骤**：
1. 创建 `shell_cell.mbt`：
   - Model：`active_view : String` / `sidebar_collapsed : Bool` / `locale : String`。
   - Msg：`SwitchView(name)` / `ToggleSidebar` / `NewSession` / `SetLocale(locale)` / `KeyEscape` / `KeyCtrlN`。
   - subscriptions：监听 `popstate` / `hashchange`（可选）、键盘事件。
   - view：渲染 sidebar + 25 个 view 容器 + notification container mount 占位。
2. 修改 `main.mbt`：
   - 只 mount `shell_cell` 到 `#app`（或 body）。
   - 其他业务 Cell 的 mount 逻辑改由 shell view 生成容器后动态挂载。
   - 这里有一个技术点：rabbita `App::mount` 是静态 mount。可选方案：
     a) shell Cell 渲染 25 个容器，业务 Cell 仍用 `App::mount` 静态挂到这些容器（要求容器在 DOM 中存在）。
     b) 业务 Cell 改为由 shell Cell 通过 `iframe` 或动态 script 加载（不推荐）。
     c) 业务 Cell 不作为独立 App，而是作为 shell Cell 的 child component（需要 rabbita 支持或手动嵌入 view）。
   - **推荐方案 a**：shell view 生成 25 个容器 div，业务 Cell 继续 `App::mount` 到对应 ID。这样改动最小，只需把容器从 `index.html` 移到 shell view。
3. 替换 `app_show_view` FFI：
   - `creator_cell.mbt` / `onboard_cell.mbt` 请求切换视图时，dispatch `CustomEvent('app:show-view', {detail: name})`。
   - shell Cell 监听该事件并 emit `SwitchView(name)`。
4. 从 `app.js` 移除 `App.showView`、`App.bindEvents`、sidebar 事件、键盘事件。
5. `#btn-stats` 点击由 shell 处理为 `SwitchView("stats")`。
6. `#btn-new-session` / `#btn-settings` 等由 shell 处理。

**验证标准**：
- [ ] 所有 sidebar 按钮能正确切换视图
- [ ] Escape 关闭 modal/overlay（chat 内部 modal 不受影响）
- [ ] Ctrl+N 新建 session
- [ ] creator/onboard 的跨 Cell 视图切换正常
- [ ] `app_show_view` FFI 已移除

### Task Pack F: i18n 字典迁移 (P1-2)

**前置条件**：无硬性依赖，但建议在 Task Pack E 之前或并行完成，因为 Task Pack G 需要移除 `data-i18n*` 静态属性。

**步骤**：
1. 在 `web/mb/main/` 下创建 `i18n_sidebar.mbt`、`i18n_chat.mbt`、`i18n_sessions.mbt`、`i18n_settings.mbt`、`i18n_skills.mbt`、`i18n_mcp.mbt`、`i18n_channels.mbt`、`i18n_schedules.mbt`、`i18n_billing.mbt`、`i18n_git.mbt`、`i18n_workspace.mbt`、`i18n_creator.mbt`、`i18n_onboard.mbt`、`i18n_media.mbt`、`i18n_marketplace.mbt`、`i18n_meeting.mbt`、`i18n_brand.mbt`、`i18n_backups.mbt`、`i18n_version.mbt`、`i18n_profile.mbt`、`i18n_share.mbt`、`i18n_trash.mbt`、`i18n_model_test.mbt`、`i18n_tasks.mbt`、`i18n_browser.mbt`、`i18n_stats.mbt`、`i18n_notifications.mbt`、`i18n_errors.mbt`。
2. 每个文件定义：
   ```moonbit
   let en : Map[String, String] = Map::of([("key", "value"), ...])
   let zh : Map[String, String] = Map::of([("key", "value"), ...])
   ```
3. 在 `i18n_helpers.mbt` 中合并所有字典：
   ```moonbit
   let dict_en = merge_all([i18n_sidebar::en, i18n_chat::en, ...])
   let dict_zh = merge_all([i18n_sidebar::zh, i18n_chat::zh, ...])
   ```
4. 实现 `t(key, params_json)`：
   - 根据当前 locale 选择字典。
   - 查找 key，未找到则回退到英文，再未找到则返回 key。
   - 解析 `params_json` 为 `Map[String, String]`，替换 `{{param}}`。
5. 移除 `bridge.mbt` 中的 `i18n_t` / `i18n_get_locale` / `i18n_on_locale_changed` / `i18n_set_locale` FFI。
6. `i18n_get_locale()` 改为读取 shell Cell 的 locale model（或继续用 `localStorage` 读取一次）。
7. 语言切换：
   - `profile_cell.mbt` 调用 `set_locale(locale)` 时，改为 dispatch `CustomEvent('i18n:set-locale', {detail: locale})`。
   - shell Cell 监听并 emit `SetLocale(locale)`，更新 model 并持久化到 `localStorage`。
   - 所有 Cell 在 `subscriptions` 中监听 locale 变化（或 shell 触发全局重渲染）。
8. `git rm web/js/i18n.js web/js/i18n/en.js web/js/i18n/zh.js`；从 `index.html` 移除对应 script。

**验证标准**：
- [ ] 所有 Cell 的可见文本正常显示（中英文）
- [ ] 切换语言后所有 Cell 同步刷新
- [ ] `web/js/i18n*.js` 已删除
- [ ] `i18n_t` 等 FFI 已从 `bridge.mbt` 移除

### Task Pack G: index.html 简化 (P1-4)

**前置条件**：Task Pack A/B/C/D/E/F 全部完成

**步骤**：
1. 重写 `web/index.html`：
   ```html
   <!DOCTYPE html>
   <html lang="en">
   <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
     <title>MBOpenClacky</title>
     <link rel="stylesheet" href="styles.css">
   </head>
   <body>
     <script src="js/lib/marked.min.js"></script>
     <script src="js/lib/highlight.min.js"></script>
     <script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
     <script src="https://cdn.jsdelivr.net/npm/qrcode@1.5.4/build/qrcode.min.js"></script>
     <script type="module" src="mb/index.js"></script>
   </body>
   </html>
   ```
2. shell Cell 在 `Init` 时创建 `#app` 并把自己 mount 进去（或直接把 view 渲染到 body）。
3. 移除 `index.html` 中所有 `data-i18n*` 属性（已无用）。
4. 验证所有业务 Cell 的 mount 点由 shell view 生成。

**验证标准**：
- [ ] 简化后的 `index.html` 不超过 30 行
- [ ] 浏览器加载后 UI 完整，所有面板可切换
- [ ] 无 `data-i18n*` 残留
- [ ] 无 legacy JS script 残留

### Task Pack Z: 最终清理与归档 (P1-1 收尾)

**前置条件**：Task Pack A-G 完成

**步骤**：
1. `git rm web/js/app.js`。
2. 检查 `web/js/` 目录，只保留 `lib/`。
3. 检查 `bridge.mbt`，确认所有指向 app.js / notifications.js / i18n.js 的 FFI 已移除。
4. 运行完整验证：`moon check` + `moon build --target native --release cmd` + `warren build` + 浏览器端到端测试。
5. 更新本 spec 状态为「已完成」，移动到 `specs/completed/`。

**验证标准**：
- [ ] `web/js/app.js` 已删除
- [ ] `web/js/` 下只剩 `lib/`
- [ ] `moon check` 0 errors
- [ ] 浏览器端到端测试通过

---

## 验证策略 [必填]

### 单元/白盒测试

- 每个 Task Pack 完成后运行 `moon check` 和 `moon test`（针对修改的 package）。
- 对 `i18n_helpers.mbt` 的 `t` / `t1` / `set_locale` 添加 white-box test（`i18n_helpers_wbtest.mbt`）。
- 对 `notification_cell.mbt` 的 model update 添加 white-box test。

### 构建验证

- `moon build --target native --release cmd` 必须成功（后端无回归）。
- `moon build --target js web/mb/main` + `warren build` 必须成功。
- 最终 bundle 大小应小于当前 445KB（移除 app.js / i18n.js / notifications.js 后预期减少 ~30-50KB）。

### 浏览器端到端验证

每个 Task Pack 至少执行以下冒烟测试：
1. 打开 `http://127.0.0.1:7071/`。
2. 切换 5 个主要面板（Chat、Settings、Skills、MCP、Channels），确认渲染无异常。
3. Chat 集群：创建 session → 发送消息 → 收到 assistant 占位消息。
4. Notification：触发一次保存/删除操作，确认 toast 显示。
5. Modal：在 chat 中打开 tools/cost modal。
6. i18n：切换语言，确认 sidebar 和面板文本刷新。
7. Keyboard：Ctrl+N 新建 session，Escape 关闭全局 overlay。

---

## 风险与缓解 [必填]

| 风险 | 可能性 | 影响 | 缓解 |
|------|--------|------|------|
| `@rabbita/http` 无法完全替代现有 API 包装器（如自定义 header、文件上传） | 中 | 高 | Task Pack D 先做能力评估；不支持的接口保留少量 fetch FFI 作为逃生舱 |
| shell Cell 生成 25 个容器后，业务 Cell 的 `App::mount` 时机/顺序出错 | 中 | 高 | 方案 a（shell 先渲染容器，业务 Cell 仍静态 mount）已被验证可行；确保 shell view 在业务 Cell mount 前完成首次渲染 |
| i18n 字典 735 键迁移工作量大，容易遗漏 | 高 | 中 | 按面板拆分文件，每迁移一个面板就验证对应 Cell 的文本；保留 key 回退机制 |
| 移除 `app.js` 后全局事件（如 Escape/Ctrl+N）行为改变 | 中 | 中 | 在 shell Cell subscriptions 中显式监听；逐个验证快捷键 |
| notification / modal 样式在 rabbita view 中表现不一致 | 低 | 中 | 复用现有 CSS class；浏览器截图对比 |
| 一个 Task Pack 改动范围过大，commit 难以 review | 中 | 中 | 每个 Task Pack 独立 commit；D/E/F 再细分为多个小 commit |

---

## 开放问题 [选填]

1. **Stats 面板是否值得独立 Cell？** 当前 `App.loadStats` 只有 35 行渲染逻辑。可选方案是合并到 `shell_cell.mbt` 或 `chat_cell.mbt`。本 Spec 选择独立 Cell 以保持「一个面板一个 Cell」的架构一致性，但实现时如果发现过于单薄，可重新评估。
2. **Shell Cell 是否应同时承担 notification overlay？** 本 Spec 选择 notification 独立 Cell，但也可以把 toast 直接渲染在 shell view 里。独立 Cell 更利于测试，但多了一个 mount 点；如果 rabbita 对 body 多个 mount 点支持不佳，可合并。
3. **i18n locale 状态放在哪里？** 本 Spec 建议放在 shell Cell model，但所有业务 Cell 都需要读取 locale。当前模式是各 Cell 在 Init 时通过 FFI 读取一次。迁移后可以让业务 Cell 在 Init 时从 `localStorage` 读取，或在 shell locale 变化时 dispatch 事件让各 Cell 更新。

---

## 变更记录

| 日期 | 变更 | 作者 |
|------|------|------|
| 2026-07-15 | 创建草案，规划 P1-1~P1-4 清理的 7 个 Task Pack | Clacky |
| 2026-07-15 | 审核修正：所有量化声明（行数、调用次数、容器数量）经 `grep`/`wc`/`ls` 验证无误；补充 `web/mb/main/moon.pkg` 需新增 `@rabbita/http` 依赖；确认 `@rabbita/http` 已存在于 rabbita 包中并支持 `expect_json`/`expect_text` | 对抗性审核 + 第一性原理校验 |
