# Web UI 一比一复刻方案

- 最后更新：2026-07-22
- 当前项目：MBOpenClacky（MoonBit），`http://localhost:7071/`
- 原项目：OpenClacky（Ruby），源码 `D:/MoonBit/openclacky`（v1.4.0）
- 路由唯一事实来源：`lib/web/server.mbt` → `WebServer::build_app()`

## 决策结论

**方案：整体移植原项目前端静态资产 + 后端 API 兼容层（受管 fork 形态）。**

理由：原前端是 87 文件 ~3MB 的纯静态 vanilla JS/CSS/HTML（MIT 许可），拷过来即可运行；自研 MoonBit→JS SPA 在 15k 行后仍未达骨架级 parity，追赶不可行。

**受管 fork 五条纪律**：
1. 钉版本（v1.4.0），不追 master，按季度同步
2. 前端零修改（唯一 delta = 品牌资产），本地改动记录在 `web/PATCHES.md`
3. AOT 做不到的扩展面板（meeting/ext-studio）不注入，不留死按钮
4. 独有能力走 `/api/ext/*` + `{{EXT_SCRIPTS}}` 扩展缝
5. 旧前端 web/mb 已删除归档

---

## 一、原项目后端契约

来源：`D:/MoonBit/openclacky/lib/clacky/server/http_server.rb`（~7000 行），路由表 `:499-758`。

### 1.1 静态服务

- 静态根 `lib/clacky/web/`，全部 `Cache-Control: no-store`
- 模板占位符：`{{BRAND_NAME}}`（4 处）、`{{EXT_SCRIPTS}}`（1 处，空值容错）
- 无 SPA fallback（hash 路由）；扩展资产走 `/ext_ui/<ext_id>/<rel>`

### 1.2 WebSocket 协议

- 单端点 `ws://<host>/ws`，文本帧 JSON
- **上行 8 种**：subscribe / message / edit_message / confirmation / interrupt / run_task / list_sessions / ping
- **下行 30+ 种**（权威清单 = `ws-dispatcher.js:140-441`）：
  session_list / subscribed / session_update / session_renamed / session_deleted / session_restored / task_finished / history_user_message / assistant_message / tool_call / tool_args / tool_result / tool_error / tool_stdout / token_usage / progress / complete / request_feedback / request_confirmation / interrupted / info / warning / success / error / phase_start / phase_end / output / log / diff / file_preview / shell_preview / todo_update / upgrade_log / upgrade_complete / server_stop
- 无 token 级流式（assistant 按整条推送）
- 历史消息 REST：`GET /api/sessions/:id/messages?limit&before`，与 WS 事件同构

### 1.3 REST API（~120 端点）

| 簇 | 代表端点 |
|---|---|
| 会话核心 | `GET/POST /api/sessions`、`GET/PATCH/DELETE :id`、`POST :id/fork`、`GET :id/messages`、`PATCH :id/model`、`PATCH :id/submodel`、`PATCH :id/reasoning_effort`、`POST :id/benchmark`、`GET :id/export` |
| 会话周边 | `GET :id/skills`、`GET :id/files`、`GET :id/git/{status,diff,log,branches}`、`POST :id/git/commit`、`GET/POST :id/time_machine*` |
| 配置 | `GET /api/config`、`POST/PATCH/DELETE /api/config/models*`、`POST /api/config/test`、`GET/PATCH /api/config/settings`、`GET /api/config/media`、`/api/config/ocr*`、`GET /api/providers` |
| 文件 | `POST /api/upload`、`POST /api/file-action`、`GET /api/local-image`、`GET /api/dirs`、`POST /api/dirs/mkdir` |
| 技能/Agent | `GET /api/skills`、`PATCH :name/toggle`、`GET/PUT :name/content`、`GET /api/agents`、`GET /api/agents/:id/skills` |
| Profile/记忆 | `GET/PUT /api/profile`、`GET/POST/PUT/DELETE /api/memories*` |
| MCP | `GET /api/mcp`、`POST /api/mcp`、`POST :name/probe`、`PATCH :name/enabled`、`PUT :name`、`DELETE :name`、`GET :name/tools`、`POST :name/call` |
| 频道 | `GET /api/channels`、`POST /:platform`、`DELETE /:platform`、`PATCH /:platform/enabled`、`POST /:platform/test`、`POST /:platform/send` |
| 次级面板 | `/api/cron-tasks*`、`/api/trash*`、`/api/billing/*`、`/api/backup/*`、`/api/brand/*`、`/api/store/extensions*`、`/api/version`、`POST /api/restart` |
| 媒体/其他 | `/api/media/*`、`/api/exchange-rate`、`/api/telemetry`、`/api/onboard/*`、`/api/browser/*` |

### 1.4 鉴权

- loopback 免鉴权；Bearer > `?access_key=` > cookie；前端 auth.js 探测 401 弹密码框
- 本项目已实现（`lib/web/middleware/auth.mbt`），loopback 默认放开

### 1.5 i18n 与扩展

- i18n 前端内嵌（`i18n.js` 2033 行 en/zh），不依赖后端
- 扩展：ext.yml 声明 → `{{EXT_SCRIPTS}}` 注入面板 script → `/ext_ui/*` 服务资产 → `/api/ext/<id>/*` 后端
- git/time_machine 面板走宿主 API，无自有后端

---

## 二、当前前端实际状态（2026-07-22 核实）

### 2.1 资产规模

| 维度 | 原项目 | 当前项目 |
|---|---|---|
| 文件数 | 87 | 4（index.html / app.js / app.css / favicon.svg） |
| 代码量 | ~38,000 行 | 448 行 |
| 功能模块 | 15 feature + 5 组件 + vendor 库 | 无 |
| WS 客户端 | ws.js + ws-dispatcher.js（30+ 事件） | 无 |
| i18n | 2,033 行 | 9 条字符串 |

### 2.2 UI 元素可用状态

| 元素 | 状态 |
|---|---|
| 🌓 主题切换 | ✅ 唯一完整功能 |
| ☰ 汉堡菜单 | 仅 toggle CSS class，侧栏无内容 |
| 搜索框 / 分享按钮 | 死按钮（无 handler） |
| Send 按钮 | 死按钮（chat/WS 零实现） |
| + New Session | 死按钮（无 click handler） |
| 会话列表 | 渲染名称，点击无响应 |

### 2.3 完全缺失的 UI 区域

侧栏配置分区（任务/技能/频道/MCP/扩展市场）、我的数据（记忆/文件/用量）、设置+版本号、右侧面板（Git/时光机/文件）、底部状态栏、附件/斜杠命令、聊天渲染管线（Markdown/hljs/KaTeX/工具卡片/确认框）、新建会话对话框、设置 5 分区、Onboard 引导、会话右键菜单、模型切换器。

**前端完成度 ≈ 3-5%。**

---

## 三、后端差距清单

后端经 web-parity-01~05 对齐，100+ 端点已就位。以下为剩余缺口。

### 3.1 缺失端点（调用即 404）

| 端点 | 用途 |
|---|---|
| `PATCH /api/sessions/:id/model` | 切换模型 |
| `PATCH /api/sessions/:id/submodel` | 切换子模型 |
| `PATCH /api/sessions/:id/reasoning_effort` | 推理力度 |
| `POST /api/sessions/:id/benchmark` | 模型跑分 |
| `GET/POST /api/mcp`、`POST :name/probe`、`PATCH :name/enabled`、`PUT/DELETE :name`、`GET :name/tools`、`POST :name/call` | MCP 管理（8 个） |
| `GET /api/brand` | 品牌信息 |
| `POST /api/brand/skills/:name/install` | 安装品牌技能 |
| `GET /api/store/extensions`、`installed`、`extension?id=`、`POST install/enable/disable`、`DELETE extension` | 扩展市场（7 个） |
| `POST /api/sessions/:id/time_machine/switch` | 时光机回滚 |
| `PATCH /api/channels/:platform/enabled`、`POST/DELETE /:platform`、`POST /:platform/send`、`GET group_history/:chat_id`、`GET /:platform/users` | 频道 platform 键路由（6 个） |
| `POST /api/my-skills/:name/publish` | 发布技能 |
| `GET /api/config/media`（全量） | Media 设置初始化 |

### 3.2 路径/方法不匹配

| 前端期望 | 当前实际 | 差异 |
|---|---|---|
| `POST /api/backup/restore` | `POST /restore/:id` | body 携 id vs 路径参数 |
| `GET /api/backup/download` | `GET /download/:id` | 同上 |
| `PATCH /api/backup/config` | 仅 GET | 缺写方法 |
| `PATCH/DELETE /api/cron-tasks/:name` | `PUT/DELETE /:id` | 方法+键语义不同 |
| `POST /api/cron-tasks/:name/run` | `POST /:id/trigger` | 路径不同 |
| `POST /api/trash/restore` | `POST /restore-batch` | 路径不同 |
| `POST /api/trash/sessions/restore` | `POST /sessions/:id/restore` | body vs 路径 |
| `POST /api/onboard/device/poll` | GET | 方法不同 → 405 |

### 3.3 SessionSummary 缺失字段

`pinned`（置顶排序）、`agent_profile`（Agent 标签）、`sub_model`、`sub_model_options`、`reasoning_effort`（模型切换器）

### 3.4 WS 事件覆盖度

- **上行 8 种**：✅ 全部实现
- **下行已实现**：connected / subscribed / session_list / session_update / progress / phase_start / phase_end / tool_call / tool_result / tool_error / complete / error / interrupted / pong
- **需字段核实**：assistant_message
- **未实现（19 个）**：session_renamed / session_deleted / session_restored / task_finished / token_usage / request_feedback / request_confirmation / history_user_message / tool_args / tool_stdout / diff / file_preview / shell_preview / todo_update / output / log / upgrade_log / upgrade_complete / server_stop

### 3.5 静态服务层

| 问题 | 影响 |
|---|---|
| `try_read_file` 用 `read_file_to_string` | 二进制资产（woff2/png/mp3）损坏 |
| `is_static_asset` 缺 `.woff2`/`.mp3` | 落入 SPA fallback |
| `get_mime_type` 缺 audio/mpeg、font/woff2 | 浏览器拒绝加载 |
| 无 `/ext_ui/*` 路径 | 扩展面板无法加载 |
| `{{EXT_SCRIPTS}}` 硬编码空串 | 右侧面板不注入 |

---

## 四、困难分析（按风险排序）

| # | 困难 | 核心风险 | 估时 |
|---|---|---|---|
| 1 | WS 事件字段级对齐 | 30+ case 对字段名精确敏感，历史/实时必须同构 | 2-3 天 |
| 2 | 二进制静态资产 | crescent 全链路 String，需验证是否支持 Byte[] 响应 | 0.5-1 天 |
| 3 | 扩展面板注入 | git/time_machine 面板 JS 来源与注入机制待查明 | 1-2 天 |
| 4 | Channels platform 键 | 原契约用 platform 做键，当前用 id，需路由别名 | 0.5 天 |
| 5 | 扩展市场 7 端点 | 需对接 lib/extension 或返回合法空响应降级 | 1 天 |
| 6 | SessionSummary 扩字段 | 涉及 lib/agent 数据模型变更 | 1 天 |
| 7 | 前端资产移植 | 确定性高，品牌替换 + 56 个 script 加载顺序 | 1 天 |

---

## 五、执行路线图

### P0 资产移植（1 天）

1. 拷贝 `D:/MoonBit/openclacky/lib/clacky/web/` 87 文件 → `web/`
2. 修复 StaticServer：补 `.woff2`/`.mp3` 识别 + 字节读取 + 二进制响应
3. `{{BRAND_NAME}}` → "MBOpenClacky"；`{{EXT_SCRIPTS}}` 暂空串
4. **验收**：7071 首页骨架与原项目视觉一致，console 无 404

### P1 聊天主链路（3-4 天）

1. WS 事件字段对齐（逐事件对照 ws-dispatcher.js）
2. 补齐优先下行事件：assistant_message / token_usage / session_renamed / request_confirmation / task_finished
3. SessionSummary 补 pinned / agent_profile
4. 补 `PATCH :id/model`、`PATCH :id/reasoning_effort`
5. **验收**：建会话 → 发消息 → 实时回复 → 工具卡片 → 中断 → 切换会话历史

### P2 面板与设置（3-4 天）

1. MCP 管理 8 端点
2. Channels platform 键路由
3. 扩展市场 7 端点（可先空数据降级）
4. cron-tasks / trash / backup 路径对齐
5. `GET /api/brand` + brand skills install + `GET /api/config/media`
6. **验收**：侧栏全面板可交互，设置 5 分区可保存

### P3 右侧面板 + 扩展注入（2-3 天）

1. 查明 git/time_machine 面板 JS 来源
2. `/ext_ui/*` 服务 + `{{EXT_SCRIPTS}}` 动态注入
3. 补 `POST :id/time_machine/switch`
4. **验收**：右侧 Git/时光机面板可操作

### P4 收尾（2 天）

1. submodel / benchmark 完整模型切换器
2. Onboard 引导流（修正 poll 方法）
3. 通知音 / 分享 / 导出端到端
4. **验收**：Playwright 截图 diff，同视口逐页对比

**总估时：11-14 天。**

---

## 六、前置验证项（阻塞性）

| # | 验证项 | 方法 | 失败后果 |
|---|---|---|---|
| 1 | crescent 二进制响应体 | wbtest：Byte[] 含 0x00 → curl 验证 | 字体/图标全灭，需 fork crescent |
| 2 | git/time_machine 面板 JS 位置 | 检查原项目 ext.yml / assets/extensions/ | 需自写面板 JS |
| 3 | `{{EXT_SCRIPTS}}` 空值容错 | 浏览器加载原前端观察 console | 需注入 stub |

---

## 七、验收标准

1. 同视口（1440×900）截图与原项目视觉一致（允许品牌差异）
2. 原前端零修改运行在本项目后端（仅 `{{BRAND_NAME}}`/`{{EXT_SCRIPTS}}` 替换）
3. 核心闭环：建会话 → 发消息 → 实时回复 → 工具调用 → 中断 → 重命名/置顶/删除/导出 → 附件 → 斜杠命令 → 主题/语言切换
4. 各面板/设置页功能可用，无死按钮
