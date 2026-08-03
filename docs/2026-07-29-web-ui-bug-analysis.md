# Web UI 手动测试 Bug 分析报告

**日期**: 2026-07-29
**测试环境**: WSL2 / Windows, MoonBit native release build, Chrome
**服务端口**: 7071

---

## Bug 1: Session 切换后历史消息丢失

**现象**: 从 Settings 返回点击侧边栏 session 后，聊天区域显示空状态提示，历史消息不加载。

**根因**: `handle_session_messages`（`lib/web/handlers_session_ext.mbt:376`）优先从磁盘加载 session：

```
let messages = match @agent.load_session(id) {
    Some(data) => Some(data.messages)   // ← 磁盘快照（创建时保存，messages 为空）
    None => ...                          // ← 内存 agent（有实际消息）永远不会被走到
}
```

- `handle_create_session`（`lib/web/handlers.mbt:270`）在创建时调用 `save_session` 保存了一个 **空历史** 的快照。
- 用户通过 WS 发送消息后，`run_ws_agent` 只在 **成功** 路径调用 `save_session`（`handlers_ws.mbt:1064`）。API key 错误等失败场景下 session 不会重新持久化。
- 因此磁盘上始终是空快照，`load_session` 返回 `Some(空)`，内存 fallback 永远不会触发。

**修复方向**:
1. 在 `handle_session_messages` 中优先检查内存 agent（`active_agents`），若存在则使用内存数据；或
2. 在 `run_ws_agent` 的错误路径也调用 `save_session`；或
3. 比较磁盘和内存的消息数量，取较新者。

**涉及文件**:
- `lib/web/handlers_session_ext.mbt:376-415`
- `lib/web/handlers_ws.mbt:1058-1066`（错误路径缺少 save_session）
- `lib/web/handlers.mbt:270`（创建时保存空快照）

---

## Bug 2: 模型下拉列表不更新

**现象**: 在 Settings 中增删模型后，返回新建 session 的高级面板，模型下拉列表仍是旧数据。

**根因**: `web/features/new-session/view.js` 中 `_populateModels()` 有一个一次性守卫：

```js
if (_modelsLoaded) return;   // ~line 193
```

首次加载后 `_modelsLoaded = true`，之后无论配置如何变化都不会重新拉取。

**修复方向**: 在高级面板每次打开时重置 `_modelsLoaded = false`，或监听配置变更事件（如 `settings:saved`）后重置。

**涉及文件**:
- `web/features/new-session/view.js:~193`（`_populateModels` 守卫）

---

## Bug 3: 工作目录斜杠/反斜杠混杂

**现象**: 在 Windows 原生环境下，新建 session 的默认工作目录显示为 `C:\Users\hnlyh/clacky_workspace`（混合分隔符）。

**根因**: `handle_create_session`（`lib/web/handlers.mbt:228`）构造默认路径时未经规范化：

```moonbit
match @utils.home_dir() {
    Some(h) => h + "/clacky_workspace"   // ← h 可能含反斜杠，拼接后混杂
    None => "."
}
```

而 `handlers_dirs.mbt` 中的 `/api/dirs` 接口使用了 `dirs_fwd_slashes()` 规范化，所以前端从 `/api/dirs` 拿到的 `home` 是正确的。但 `handle_create_session` 独立构造路径时绕过了规范化。

**注**: WSL 环境下 `home_dir()` 返回 `/root`（纯正斜杠），无法复现。仅在原生 Windows 下触发。

**修复方向**: 在 `handle_create_session` 中对 `default_dir` 调用 `dirs_fwd_slashes()` 规范化。

**涉及文件**:
- `lib/web/handlers.mbt:225-232`
- `lib/web/handlers_dirs.mbt:17`（`dirs_fwd_slashes` 参考实现）

---

## Bug 4: Session 名称不自动生成（回归）

**现象**: 用户报告新建 session 时名称不自动递增（如始终为 "Session 1"）。

**代码分析**: `_autoName`（`web/features/new-session/store.js:117`）逻辑正确——扫描 `existingSessions` 中匹配 `Session N` 的名称取最大值 +1。

调用链：`NewSessionView._submit()` → `createSession({ existingSessions: Sessions.all })`。`Sessions.all` 返回内部 `_sessions` 数组（`sessions.js:2311`）。

**可能原因**:
- 若 session 列表尚未从 API 加载完成（`_sessions` 为空），`_autoName` 始终返回 "Session 1"。
- 本次自动化测试中未复现（侧边栏正确显示 "Session 1"、"Session 2"）。

**修复方向**: 在 `createSession` 中若 `existingSessions` 为空，先 `await` 一次 session 列表刷新；或在 `_autoName` 中增加 fallback 逻辑。

**涉及文件**:
- `web/features/new-session/store.js:117-123`
- `web/features/new-session/view.js:449-450`

---

## Bug 5: Agent 头像图标加载失败

**现象**: 新建 session 高级视图中，三个 agent 卡片的头像全部显示为破碎图片。

**根因**: 后端 `handlers_agents.mbt:145` 生成 avatar URL 为 `/agent_avatar/<id>`，但 `server.mbt` 中 **没有** 对应的路由处理器。

请求链路：
1. 浏览器请求 `GET /agent_avatar/coding`
2. 静态文件中间件在 `web/` 目录下找不到 → 404 → `next()`
3. SPA fallback（`server.mbt:806`）返回 `web/index.html`，`Content-Type: text/html`
4. 浏览器收到 HTML 而非图片 → `naturalWidth: 0`

实际头像文件存在于 `assets/agents/<id>/avatar.png`。

**修复方向**: 在 `server.mbt` 中注册 `/agent_avatar/:id` 路由，读取 `assets/agents/<id>/avatar.png` 并以 `Content-Type: image/png` 返回。

**涉及文件**:
- `lib/web/server.mbt`（缺少路由）
- `lib/web/handlers_agents.mbt:142-148`（URL 生成）
- `assets/agents/*/avatar.png`（实际文件）

---

## Bug 6: 选择的模型未被使用

**现象**: 在新建 session 高级面板中选择 `kimi-k2.7-code`，创建后信息栏显示的是 `qwen3.7-plus`（全局默认模型）。

**根因**: `handle_create_session`（`lib/web/handlers.mbt:243`）始终使用全局默认模型：

```moonbit
let model_config = match server_ref.val.config.current_model() {
    Some(mc) => mc    // ← 永远是全局默认
    None => ...
}
```

前端正确发送了 `model_id` 字段（`store.js:141`: `if (adv.modelId) payload.model_id = adv.modelId`），但后端 **完全忽略** 了请求体中的 `model_id`。

同样，`get_or_create_agent`（`server.mbt:98`）也使用 `config.current_model()`，不考虑 session 级别的模型选择。

**修复方向**:
1. 在 `handle_create_session` 中解析 `model_id`，从 `config.models` 中查找对应配置。
2. 将 session 的模型选择持久化（存入 session 元数据），使 `get_or_create_agent` 能恢复。

**涉及文件**:
- `lib/web/handlers.mbt:243-260`（忽略 model_id）
- `lib/web/server.mbt:98`（get_or_create_agent 使用全局默认）
- `web/features/new-session/store.js:141`（前端正确发送）

---

## Bug 7: 历史消息重复展示

**现象**: 用户报告在会话中向上滚动时看到重复消息。

**代码分析**: 前端去重机制基于 `_renderedCreatedAt`（`sessions.js`），按 `history_user_message` 事件的 `created_at` 时间戳去重。`_restoreMessages` 切换 session 时清空去重集合。

**与 Bug 1 的关联**: 本次测试中由于 Bug 1（历史加载返回空），无法充分验证去重逻辑。但存在以下潜在问题：

1. **分页重叠**: `loadMoreHistory` 使用 `before` 游标分页。若后端返回的 `before` 边界不精确（如时间戳精度不够），相邻页可能包含重叠事件。
2. **WS 实时消息 + 历史加载竞争**: 若用户在 WS 实时接收消息的同时触发历史加载（如快速切换 session），同一消息可能通过两条路径各渲染一次。
3. **`created_at` 缺失**: 若后端事件缺少 `created_at` 字段，去重集合无法工作。

**修复方向**: 需要在工作正常的模型配置下多轮对话后复现。建议增加基于事件 ID 的去重（而非仅靠时间戳）。

**涉及文件**:
- `web/sessions.js`（`_renderedCreatedAt` 去重逻辑、`_fetchHistory`、`loadMoreHistory`）
- `lib/agent/protocol.mbt`（`build_messages_history` 分页逻辑）

---

## 严重程度排序

| 优先级 | Bug | 影响 |
|--------|-----|------|
| P0 | Bug 1 | 历史消息完全丢失，核心功能不可用 |
| P0 | Bug 6 | 用户选择的模型被忽略，核心功能错误 |
| P1 | Bug 5 | Agent 头像全部破碎，UI 体验差 |
| P1 | Bug 2 | 模型列表不更新，配置变更不生效 |
| P2 | Bug 3 | 路径显示不规范（仅 Windows 原生） |
| P2 | Bug 7 | 消息重复（需进一步复现） |
| P3 | Bug 4 | 自动命名可能失败（未复现） |
