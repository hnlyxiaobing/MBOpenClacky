# Web UI 一比一复刻方案：移植原项目前端 + API 兼容层

- 调查日期：2026-07-21
- 当前项目：MBOpenClacky（MoonBit 重写版），`http://localhost:7071/`
- 原项目：OpenClacky（Ruby 版），`http://127.0.0.1:7070/`，源码在本机 `D:/MoonBit/openclacky`（git 检出 `042772e`）
- 前置文档：`docs/web_ui_comparison_report.md`（2026-07-20 的功能差距清单；其中缺陷 #1 JS 正则双重转义、缺陷 #2 SSE 序列化已在提交 `8af6968` 修复）

## 总体结论

**一比一复刻的正确路径不是在现有 MoonBit SPA（web/mb）上继续补功能，而是整体移植原项目的前端静态资产，再让 MoonBit 后端满足它的后端契约。**

依据：

1. **原项目前端是纯静态、零构建的资产集**：`D:/MoonBit/openclacky/lib/clacky/web/` 共 87 个文件、约 3MB，全部是手写 vanilla JS/CSS/HTML + vendored 第三方库（marked/hljs/katex/codemirror/qrcode），无打包器、无 transpile。拷过来就能跑。
2. **许可证无障碍**：原项目 MIT License，本仓库 LICENSE 已声明衍生自 openclacky 并保留上游版权，直接复制资产合规。
3. **成本对比悬殊**：web/mb 是用 rabbita/warren 框架重写的 MoonBit→JS SPA，要在 MoonBit 里重写原前端约 3 万行 JS 的交互细节（20+ 功能面板、i18n、主题、扩展插槽），工作量大且永远追不上"一比一"；移植资产则是确定性的一次性工作。
4. **架构上正好规避已知短板**：原前端聊天流式走 **纯 WebSocket**（无 SSE），而本项目的 SSE 恰是"伪流式"（crescent 不支持 chunked，`lib/web/handlers.mbt:311` TODO），真正的实时通道是 WS（`lib/web/broadcast/hub.mbt`）。换用原前端后，crescent 的 SSE 短板直接不再是问题。

---

## 一、原项目前端的后端契约（调查结果）

来源：对 `D:/MoonBit/openclacky` 的只读调查。服务端单文件 `lib/clacky/server/http_server.rb`（约 7000 行，WEBrick + 手动 WS 升级），路由总表在 `http_server.rb:499-758`。

### 1.1 静态服务

- 静态根 = `lib/clacky/web/`，挂 `/`，全部响应 `Cache-Control: no-store`（`http_server.rb:348-382`）。
- `GET /` 与 `/index.html` 做**服务端模板替换**，仅两个占位符：
  - `{{BRAND_NAME}}`（`web/index.html:6,38,1279`）→ 品牌名，缺省 "OpenClacky"
  - `{{EXT_SCRIPTS}}`（`web/index.html:1540`）→ 扩展 `<script>` 标签；`?pure=true` 或为空时前端自动容错
- **无 SPA fallback**（前端用 hash 路由 `#session/:id`，不需要）。
- 特殊前缀：`/ext_ui/<ext_id>/<rel>`（扩展面板 JS/CSS）、`/agent_ui/<name>/`、`/agent_avatar/<id>`。

### 1.2 WebSocket 协议（聊天实时链路的全部）

- URL：`ws://<host>/ws`（鉴权时带 `?access_key=`），文本帧 JSON。握手在 `http_server.rb:6122`，消息分发在 `:6195`。
- 客户端→服务端 8 种消息（`http_server.rb:6199-6257`）：
  - `{type:"subscribe", session_id}` → 回 `subscribed` + `session_update` 全量快照 + replay 进行中事件
  - `{type:"message", session_id, content, files?, lang?}` — files 为 `[{data_url?,name,mime_type,path?}]`
  - `{type:"edit_message", session_id, content, created_at}` — 截断重发
  - `{type:"confirmation", session_id, id, result}` — 回应确认请求
  - `{type:"interrupt", session_id}` / `{type:"run_task", session_id}`
  - `{type:"list_sessions"}` → 回 `session_list`
  - `{type:"ping"}` → 回 `pong`
- 服务端→客户端事件（处理器在 `web/ws-dispatcher.js:140-441`，产生端 `web_ui_controller.rb:436` 的 `emit`）：
  `session_list / subscribed / session_update(全量或增量) / session_renamed / session_deleted / session_restored / task_finished / history_user_message / assistant_message / tool_call / tool_args / tool_result / tool_error / tool_stdout / token_usage / progress / complete / request_feedback / request_confirmation / interrupted / info / warning / success / error(可带 code:"insufficient_credit") / phase_start / phase_end / output / log / diff / file_preview / shell_preview / todo_update / upgrade_log / upgrade_complete / server_stop`
- **无 token 级流式**：assistant 消息按整条/按块以 `assistant_message` 推送——这降低了本项目 WS 广播的实现对齐难度。
- 历史消息走 REST：`GET /api/sessions/:id/messages?limit&before` 返回与 WS 事件**同构**的事件数组。

### 1.3 REST API 规模

共约 **120 个端点**，按优先级分簇（完整字段级清单见调查记录，路由定义 `http_server.rb:510-758`）：

| 簇 | 代表端点 | 前端用途 |
|---|---|---|
| 会话核心 | `GET/POST /api/sessions`、`GET/PATCH/DELETE /api/sessions/:id`、`POST :id/fork`、`GET :id/messages`、`PATCH :id/model`、`GET :id/export`(zip) | 侧栏列表、新建、重命名/置顶、导出 |
| 会话周边 | `GET :id/skills`、`GET :id/files`、`GET :id/git/{status,diff,log,branches}`、`POST :id/git/commit`、`GET/POST :id/time_machine*` | 文件树、git 面板、时光机面板 |
| 配置 | `GET /api/config`、`POST/PATCH/DELETE /api/config/models*`、`POST /api/config/test`、`GET/PATCH /api/config/settings`、`/api/config/media*`、`/api/config/ocr*`、`GET /api/providers` | 设置五分区 |
| 文件 | `POST /api/upload`(multipart)、`POST /api/file-action`、`GET /api/local-image`、`GET /api/dirs`、`POST /api/dirs/mkdir` | 附件上传、目录浏览 |
| 技能/Agent | `GET /api/skills`、`PATCH :name/toggle`、`GET/PUT :name/content`、`GET /api/agents` | 技能页、新建会话选 agent |
| Profile/记忆 | `GET/PUT /api/profile`、`GET/POST/PUT/DELETE /api/memories*` | Profile 页、Memory 三区 |
| 次级面板 | `/api/cron-tasks*`、`/api/channels*`、`/api/mcp*`、`/api/trash*`、`/api/billing/*`、`/api/backup/*`、`/api/brand/*`、`/api/store/*`、`/api/version`、`POST /api/restart` | 各侧边面板 |
| 媒体/其他 | `/api/media/*`、`/api/exchange-rate`、`/api/telemetry`、`/api/onboard/*`、`/api/browser/*` | 聊天内嵌媒体、汇率、Onboard 引导 |

### 1.4 鉴权

- key 来源 `CLACKY_ACCESS_KEY`；**绑定 localhost 或来自 loopback 的请求完全免鉴权**（`http_server.rb:2941`）。
- 提取顺序：Bearer 头 > `?access_key=` > cookie `clacky_access_key`；前端 `auth.js` 探测 `GET /api/sessions?limit=1`，401 弹密码框；防爆破 10 次/300s → 429。
- 本项目已有同构实现（`lib/web/middleware/auth.mbt`），只需**默认放开 loopback 免鉴权**即可让原前端 `Auth.check()` 直接通过。

### 1.5 i18n 与扩展

- i18n 完全前端内嵌（`web/i18n.js`，en/zh 常量，2123 行），不依赖后端数据；前端通过 `X-Lang` 头和 WS `lang` 字段告知后端语言。
- 扩展机制：ext.yml 声明 panels/api；面板 JS 经 `{{EXT_SCRIPTS}}` 注入、从 `/ext_ui/*` 服务；扩展后端挂在 **`/api/ext/<ext_id>/*`**（`lib/clacky/extension/dispatcher.rb:14`）。git/time_machine 两个默认面板无自有 API，直接用宿主 `/api/sessions/:id/git|time_machine*`。**第一阶段注入空 `{{EXT_SCRIPTS}}` 即可，前端对扩展缺失是容错设计的。**

---

## 二、本项目现状与差距

来源：对本仓库的调查。路由唯一事实来源：`lib/web/server.mbt` 的 `WebServer::build_app()`（`server.mbt:130-616`，注意 `lib/web/router.mbt` 已废弃）。

- 已有 100+ REST 端点，但**路径与响应形状多为自行设计**，与原契约系统性不一致。典型错位：
  - 模型管理：本项目 `GET/POST /api/models` vs 原契约 `/api/config/models*`
  - 定时任务：本项目 `/api/schedules` vs 原契约 `/api/cron-tasks`
  - git：本项目 `/api/git/*`（全局）vs 原契约 `/api/sessions/:id/git/*`（会话作用域）
  - 聊天流：本项目 `POST /api/sessions/:id/chat/stream`（SSE 伪流式）vs 原契约 WS `/ws` 消息
  - WS：本项目 `/ws/sessions/:id`（消息类型自定义）vs 原契约单端点 `/ws` + `subscribe` 切换会话
- 静态服务：`lib/web/static_server.mbt` 已有模板替换机制（`process_template`）和 SPA fallback，可直接复用改造；原前端不需要 SPA fallback 但保留无害。
- 鉴权：已有 Bearer/`?access_key=`/cookie 三种携带 + 限流，缺 loopback 默认免鉴权（现有 `MBOPENCLACKY_DEV_ALLOW_LOOPBACK=1` 开关，需改为默认开）。
- 前端 web/mb：MoonBit→JS SPA，无 header、20+ 按钮堆侧栏、无 i18n/主题/附件/斜杠命令，布局与原项目差距是结构性的（详见 7-20 对比报告第二节），逐点补齐不现实。

---

## 三、复刻方案

### 方案 A（推荐）：资产移植 + API 兼容层

把原项目 `lib/clacky/web/` 整体拷贝为本项目的新静态根，后端分阶段实现原契约。**前端一行不改**（`{{BRAND_NAME}}` 替换为 "MBOpenClacky" 即可换牌），所有对齐工作集中在后端，且本项目已有的大量 handler 可复用——只是改路径、改响应形状、补缺失端点。

阶段划分（每阶段结束都可用 Playwright 对比两边截图验收）：

- **P0 资产与静态服务**（最小可见成果：打开 7071 看到与原项目一致的首页骨架）
  1. 拷贝 `D:/MoonBit/openclacky/lib/clacky/web/` → `web/`（原 `web/mb`、`web/css`、`web/js` 归档到 `web/legacy_mb/` 或删除；保留原前端自带 vendor 库，勿与现有 `web/js/lib` 混用）。
  2. 改造 `static_server.mbt`：`/`、`/index.html` 替换 `{{BRAND_NAME}}`（先硬编码 "MBOpenClacky"，后续接 brand 配置）与 `{{EXT_SCRIPTS}}`（先注入空串）；加 `no-store` 头；补 favicon/logo 等静态 MIME。
  3. 鉴权默认放开 loopback（对齐原项目行为，`lib/web/middleware/auth.mbt`）。
  4. 实现契约探针端点：`GET /api/sessions`（原响应形状 `{sessions, has_more, cron_count, latest_cron_updated_at}`）——`auth.js` 和首屏加载的第一依赖。
- **P1 聊天主链路**（最小可见成果：能建会话、发消息、看到回复与工具调用）
  1. 新 WS 端点 `/ws`：实现 8 种客户端消息 + 事件集（复用 `lib/web/broadcast/hub.mbt` 扇出；事件名/字段对齐 `ws-dispatcher.js` 的期望）。assistant 按条推送即可，无需 token 级。
  2. 会话 REST 核心簇 + `GET :id/messages`（返回与 WS 同构事件数组）、`POST /api/upload`、`GET /api/dirs`、`POST /api/dirs/mkdir`（新建会话的目录浏览）。
  3. `GET /api/config` + `/api/config/models*` 增删改 + `/api/config/test`（新建会话选模型、设置页 Models 分区）。
- **P2 设置与Profile**（设置五分区可用）：`/api/config/settings`、`/api/profile`、`/api/memories*`、`/api/skills*`、`/api/agents`、`/api/providers`、`/api/exchange-rate`。
- **P3 次级面板**：git、time_machine、trash、billing、backup、cron-tasks、channels、mcp、version/restart、share、onboard、browser、media。按"端点翻译"方式逐簇对齐——多数在本项目已有对应 handler，工作是改路径与响应形状。
- **P4 扩展机制（可选/可裁剪）**：`/api/ext/*` 分发 + `{{EXT_SCRIPTS}}` 注入 + `/ext_ui/*` 服务。若暂不做，保持空注入与 404，前端容错。git/time_machine 面板因走宿主 API，P3 完成后可在 `{{EXT_SCRIPTS}}` 中恢复其 script 标签。

API 对齐策略：以**原契约为准**新增路由；本项目现有自设路径（`/api/models`、`/api/schedules` 等）在 web/mb 退役后无消费者，可随 P3 逐簇删除或保留至测试迁移完毕。`lib/web/server.mbt` 的 `build_app()` 是唯一事实来源，避免再出现重复注册。

### 方案 B（不推荐）：继续自研 web/mb 对齐

在 rabbita/warren 框架里重写原前端全部交互。缺点：工作量是方案 A 的数倍；MoonBit→JS 对 DOM 细节（codemirror 集成、拖拽上传、主题切换）表达力弱；永远存在像素/交互级差异，达不到"一比一"。仅在"必须保持前端技术栈为 MoonBit"这一硬性约束下才考虑。

### 方案 C（过渡可选）：双前端并存

保留 web/mb 于 `?legacy` 路径或独立端口作为降级方案，主路径用移植前端。适合 P0-P1 期间回归对照，正式复刻完成后删除。

### 品牌注意点

原资产含 OpenClacky 品牌图（`logo_nav_dark.png`、favicon、icon.svg）。原项目自身有品牌系统（`/api/brand/*` + brand 配置），复刻后应通过 `{{BRAND_NAME}}` 替换 + 替换 logo/favicon 资产完成换牌，而不是硬改前端代码。

---

## 四、风险与注意点

1. **WS 事件字段对齐是最大工作量点**：`ws-dispatcher.js:140-441` 是权威清单，建议逐事件核对实现；历史消息与实时事件必须同构，否则切换会话后渲染不一致。
2. **会话数据格式**：README 声称与原项目会话格式兼容，需在 P1 验证 `SessionSummary` 字段（`session_registry.rb:517-543`：id/name/working_dir/status/total_tasks/total_cost/model/source/agent_profile/pinned 等）能由原前端直接消费。
3. **Windows 路径**：`/api/dirs`、`/api/sessions/:id/files` 的越界检查与盘符路径要按 Windows 语义处理（原项目为 Ruby 跨平台实现，参考 `http_server.rb:4354-4467`）。
4. **超时与长任务**：原服务对媒体/备份类端点放宽到 600s（`http_server.rb:448-487`），crescent 侧需确认可配置。
5. **不要混用两套 vendor 库**：原前端自带 `web/vendor/*`（marked/hljs/katex/codemirror/qrcode），拷贝后删除本项目 `web/js/lib` 避免版本冲突。
6. **回归手段**：沿用 `.test_web_compare/` 的 Playwright 探针脚本（test1~3），把"原项目 7070 vs 本项目 7071"的 DOM 结构探针做成逐阶段验收门槛；每阶段对关键页面截图 diff。

## 五、验收标准（一比一的判定）

1. 同一视口（1440x900）下，首页、会话页、新建会话对话框、设置五分区、各面板的截图与原项目视觉一致（允许品牌名/logo 差异）。
2. 原前端**零修改**运行在本项目后端上（除 `{{BRAND_NAME}}`/`{{EXT_SCRIPTS}}` 服务端替换）。
3. 核心交互闭环全通：建会话（选 agent/目录/模型）→ 发消息 → WS 实时回复/工具调用展示 → 中断 → 重命名/置顶/删除/导出 → 附件上传 → 斜杠命令 → 主题/语言切换。
4. `.test_web_compare/` 探针报告中原为 `false` 的结构探针（hasHeader 等）全部转 true。


---

# 附：三方案对抗性审查（2026-07-21 第二轮）

## 审查方法与量化事实

评估轴与权重（从第一性原理推导：产品的第一价值是"用户现在就能用"，其次是"五年后还活着且能演进"）：

- **用户可用性 35%**：功能是否真的能用、多快能用、是否有 silent broken 的按钮
- **用户易用性 25%**：交互质量、一致性、i18n/主题等细节完成度
- **可维护性 25%**：谁有能力维护、回归成本、同步成本、技术栈一致性
- **可扩展性 15%**：加新能力的自由度、API 自主权、扩展机制

新补充的量化事实：

| 事实 | 数值 | 含义 |
|---|---|---|
| web/mb 已投入 | 15,289 行 MoonBit | 仍未达到布局骨架级 parity |
| 原项目前端规模 | ~38,000 行 JS/CSS/HTML | B 方案的追赶总量 |
| 上游活跃度（近 3 月） | 768 提交，其中 300 触及 web/（约 3 个 UI 提交/天） | 目标是高速移动的 |
| 上游发布节奏 | 有正式 tag（v1.4.0、v1.3.x…） | 钉版本同步可行 |

## 对方案 A（资产移植 + API 兼容层）的对抗性审查

先摆出它最强的反对意见，逐条检验：

1. **"fork 漂移失控"**——上游每天 3 个 UI 提交，拷贝来的前端会迅速过时。
   检验：成立但可控。上游有正式 release tag，钉版本（如 v1.4.0）而非追 master，同步降级为季度级的"拷贝 → 重放 delta → Playwright 回归"。漂移风险本质取决于**是否保持前端零修改**——每多一处本地改动，同步成本指数上升。所以 A 必须附加"受管 fork 纪律"（见结论），裸奔的 A 确实会在一年内烂掉。
2. **"API 自主权丧失"**——后端 120 个端点的设计被 Ruby 项目绑架，本项目无法按 MoonBit 的特长演进。
   检验：部分成立，但换个角度是优点。原契约是被真实用户打磨过的 API 设计（会话作用域的 git、SessionSummary 字段集等比本项目自设路径更合理）；且对齐它意味着与 Ruby 版生态、第三方集成、会话格式互通。真正的代价是：未来加 MoonBit 独有能力时需要同时改 fork 前端——这会破坏零修改纪律。缓解：独有能力走 `/api/ext/*` 扩展挂载点 + `{{EXT_SCRIPTS}}` 注入，这正是原架构预留的扩展缝，不算破坏 fork。
3. **"团队能力错配"**——MoonBit 项目的维护者面对 38k 行别人的 vanilla JS，修 bug、做定制的能力存疑。
   检验：成立但被两点抵消：vanilla JS 无框架无构建，是前端代码里可维护性的天花板（任何工程师+AI 辅助都能改）；且"零修改纪律"本身就把维护面压缩到服务端模板替换这一处。
4. **"一比一本来就不可能"**——meeting/ext-studio 等面板依赖 Ruby 运行时加载 handler，MoonBit AOT 约束做不到同构，这些 UI 会永久半残。
   检验：成立，这是 A 的真实上限。应对不是假装能做，而是**主动裁剪**：`{{EXT_SCRIPTS}}` 不注入这些面板，前端对扩展缺失是容错设计，UI 上不出现死按钮——这反而比现状（20+ 个点了没反应的按钮）更符合可用性原则。
5. **"品牌法律风险"**——logo/favicon 是 OpenClacky 品牌资产，MIT 管不到商标。
   检验：成立。结论：品牌资产（logo/favicon/product name）不属于"零修改"范围，必须在移植时替换，这是唯一被允许的、永久维护的前端 delta。

## 对方案 B（继续自研 web/mb）的对抗性审查

先摆出它最强的支持意见：

1. **"单一语言栈，长期最健康"**——一种语言、一套测试、编译期类型安全、API 自主、无同步负担。
   检验：这些优点全部真实。如果项目是"MoonBit 技术展示"，B 是最优。但 README 自我定位是"扩展至商业可用级别"的产品——产品就要接受可用性权重的审判。
2. 审判点一（致命）：**可用性时间线**。已写 15.3k 行连布局骨架都未对齐，剩余差距（i18n 2123 行翻译、主题系统、附件拖拽、CodeMirror 集成、20+ 面板的交互细节）保守估计 ≥ 已投入量，而上游以每天 3 个 UI 提交的速度继续拉开差距。**parity 在 B 路径上渐进不可达**。
3. 审判点二：**生态风险**。rabbita/warren 是 0.12.4 的社区框架；MoonBit→JS 写 DOM 密集型 UI 要靠 `extern "js"` 手拼字符串——bridge.mbt 双重转义导致整页空白的 bug 就是这种工作方式的内生缺陷，在纯 JS 里这类 bug 不会发生。用不成熟的工具链复刻成熟 UI，是在最不利的地形作战。
4. 审判点三：**易用性永远打折**。即使功能补齐，焦点管理、动画、拖拽手感等细节在跨语言 FFI 层上会持续渗漏，用户感知到的就是"差点意思"。

结论：B 的可维护性优势是真实的，但它服务的是一个它自己也交付不了的功能集——**不能交付可用产品的架构，可维护性再好也没有维护对象**。

## 对方案 C（双前端并存）的对抗性审查

- 长期双前端 = 双倍回归面 + 用户困惑（哪个是"真的"UI？）+ 每个后端改动要验证两个消费者。作为终态不合格。
- 但作为 **A 的过渡战术**有价值：P0–P1 期间 web/mb 保留在 `?legacy` 路径作降级对照。C 不是方案，是 A 的一个带截止日期的阶段。

## 评分汇总

| 轴（权重） | A 裸奔 | A 受管 fork | B 自研 | C 并存终态 |
|---|---|---|---|---|
| 可用性 35% | 9 | 9 | 2 | 7 |
| 易用性 25% | 9 | 9 | 4 | 8 |
| 可维护性 25% | 4 | 7 | 8 | 3 |
| 可扩展性 15% | 6 | 7 | 8 | 5 |
| **加权** | **7.4** | **8.4** | **4.4** | **5.7** |

（A 裸奔与受管 fork 的差距全部来自同步纪律——这本身就是审查的产出。）

## 最终推荐：方案 A，但必须是"受管 fork"形态

在原有 P0–P4 计划上追加五条纪律，它们是对抗性审查的直接产出：

1. **钉版本**：从上游 release tag（当前 v1.4.0）拷贝，不追 master；同步节奏按季度或按上游 minor 版本。
2. **零修改纪律**：前端代码唯一允许的永久 delta 是品牌资产（logo/favicon/产品名）；任何其它本地修改必须记录在一根 `web/PATCHES.md` 清单里并在每次同步时重放，清单长度是 fork 健康度指标，应趋向于 0。
3. **裁剪而非半残**：MoonBit AOT 做不到的扩展面板（meeting、ext-studio 等依赖运行时 Ruby handler 的）通过不注入 `{{EXT_SCRIPTS}}` 整体裁掉，UI 上不留死按钮。
4. **独有能力走扩展缝**：未来 MoonBit 侧独有能力一律走 `/api/ext/*` + `{{EXT_SCRIPTS}}` 注入，不直接改 fork 前端。
5. **web/mb 设退役线**：C 形态仅存在于 P0–P1，`?legacy` 保留至 P2 验收通过后删除归档；此后它的唯一遗产是已修复的服务端 bug 与测试资产。

**权重前提的诚实声明**：本结论依赖"这是要交付给用户的产品"这一定位（README 自称商业可用级别）。若项目真实目标是 MoonBit 语言/生态的技术验证，可用性权重应降至 15% 以下，此时 B 反超——但那条路不应以"一比一复刻原项目 UI"为目标，两个目标在 B 路径上互斥。
