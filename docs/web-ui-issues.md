# Web UI 问题记录（当前项目已有功能的实现缺陷）

> 判定规则见 `web-ui-test-plan.md` §3：只记"功能存在但跑不通/行为错误"的 bug；"尚未实现"记入 `web-ui-gaps.md`。
> 严重度：P0 阻断核心流程 / P1 功能受损有绕行 / P2 体验问题 / P3 轻微
> 状态：Open / Fixed（注明 commit）/ Won't fix
> 详细复现步骤与原始证据：`logs/web-compare/2026-07-24/findings-{api,ui,ws}.md`、`api-diff.json`、`ws-events.json`、`shots/`

## 状态总览

### 按严重度统计

| 严重度 | 总数 | ✅ 已解决 | ❌ 待解决 | ⚠️ 部分解决 |
|--------|------|----------|----------|------------|
| P0 | 2 | 2 | 0 | 0 |
| P1 | 11 | 6 | 4 | 1 |
| P2 | 18 | 1 | 17 | 0 |
| P3 | 8 | 0 | 8 | 0 |
| **合计** | **39** | **9** | **29** | **1** |

### 已解决问题清单（9 项）

| ID | 标题 | 严重度 | 实施 Spec |
|----|------|--------|-----------|
| ✅ I-001 | WS 发消息触发的 LLM 流式调用导致 server 崩溃（WSL1） | P0 | `fix-01-wsl1-server-crash` |
| ✅ I-002 | 新建会话发首条消息后被弹回新建页 | P0 | `fix-02-session-creation-broadcast` |
| ✅ I-003 | GET /api/mcp 尾斜杠路由 404 | P1 | `fix-04-api-response-wrappers` |
| ✅ I-004 | GET /api/sessions/:id 缺 session 包装层 | P1 | `fix-04-api-response-wrappers` |
| ✅ I-005 | GET /api/channels 响应未包装 | P1 | `fix-04-api-response-wrappers` |
| ✅ I-006 | GET /api/cron-tasks 响应未包装 | P1 | `fix-04-api-response-wrappers` |
| ✅ I-011 | 会话时间戳序列化为 epoch 毫秒字符串 | P1 | `fix-03-session-serialization` |
| ✅ I-012 | HTTP 会话接口不返回 model 字段 | P1 | `fix-03-session-serialization` |
| ✅ I-026 | PATCH /api/sessions/:id 对未发消息的新会话 404 | P2 | `fix-02-session-creation-broadcast` |

### 部分解决问题清单（1 项）

| ID | 标题 | 严重度 | 已修复部分 | 残留部分 | 实施 Spec |
|----|------|--------|-----------|---------|-----------|
| ✅ I-030 | 会话摘要字段名与前端期望不符 | P2 | `latest_latency` 已改为对象 `{ttft_ms, duration_ms}`；error_code/top_up_url/raw_message/model_id/card_model/channel_info 六字段已补齐 | — | `fix-03-session-serialization` + `fix-09-session-summary-fields` |

### 待解决问题清单（29 项）

| ID | 标题 | 严重度 | 备注 |
|----|------|--------|------|
| ❌ I-007 | GET /api/media/types 语义被重定义 | P1 | 需人工确认 |
| ❌ I-008 | GET /api/dirs 目录浏览结构不兼容 | P1 | |
| ❌ I-009 | GET /api/billing/summary 结构完全不同 | P1 | |
| ❌ I-010 | GET /api/trash 与 /api/trash/sessions 结构不兼容 | P1 | |
| ✅ I-013 | WS subscribe 不存在的 session 返回 subscribed 成功 | P1 | fix-07 |
| ❌ I-014 | /api/billing/daily 键名不一致 | P2 | |
| ❌ I-015 | /api/billing/records、sessions 缺字段 | P2 | |
| ❌ I-016 | /api/creator/skills 结构不兼容 | P2 | |
| ❌ I-017 | /api/config/media 缺 per-模态详情 | P2 | |
| ❌ I-018 | /api/config/ocr 结构不兼容 | P2 | |
| ❌ I-019 | /api/config 缺当前模型指针与媒体能力 | P2 | |
| ❌ I-020 | /api/config/settings 缺 4 个开关 | P2 | |
| ❌ I-021 | /api/skills 条目缺 9 个展示字段 | P2 | |
| ❌ I-022 | /api/brand 缺 13 个品牌键 | P2 | |
| ❌ I-023 | /api/onboard/status 缺 needs_onboard/branded | P2 | 需人工确认 |
| ❌ I-024 | /api/version 缺更新检查字段 | P2 | 需确认是否有意重设计 |
| ❌ I-025 | /api/sessions/:id/skills 返回空数组 | P2 | 需确认 |
| ✅ I-027 | interrupt 后缺 session_update(idle)/progress(done) | P2 | fix-07 |
| ✅ I-028 | 运行结束状态值为 "completed" 而非 "idle" | P2 | fix-07 |
| ✅ I-029 | task_finished 投递不到任何正常客户端 | P2 | fix-07 |
| ❌ I-032 | 部分 404 错误体缺 ok:false | P3 | |
| ❌ I-033 | /api/store/* 缺 ok 字段 | P3 | |
| ❌ I-034 | /api/agents 条目缺 avatar | P3 | |
| ❌ I-035 | /api/backup/status 缺 config/dest_dir/is_wsl | P3 | |
| ❌ I-036 | /api/browser/status 缺 chrome_version | P3 | |
| ❌ I-037 | i18n key sessions.untitled 缺失显示原始 key | P3 | |
| ❌ I-038 | 删除会话出现一次 DELETE net::ERR_ABORTED | P3 | 需人工确认 |
| ❌ I-039 | 首页 networkidle 15s 未达成 | P3 | |
| ✅ I-040 | token_usage 发两次（第二帧 delta=0） | P3 | fix-07 |

---

## P0（2 条）

### ✅ I-001 WS 发消息触发的 LLM 流式调用间歇性导致整个 server 进程崩溃（WSL1）
- area：ws / `lib/client/http_async.mbt:214`
- 期望（orig）：正常事件流，server 存活。
- 实际：WSL1 上 3 次运行 2 次崩溃（Windows release 2 次未崩）。`IoHandle::from_fd` guard panic（io.mbt:102）← `pipe()` ← `http_post_stream_async` ← `run_ws_agent`（handlers_ws.mbt:846）；`catch` 拦不住 PanicError，进程整体退出，HTTP 全挂。
- 证据：`logs/web-compare/2026-07-24/server-7071-wsl-debug.log`（完整堆栈）、findings-ws.md WS-001
- 状态：✅ Fixed（2026-07-24，未提交）。修复：WSL1 运行时检测（`@utils.is_wsl1()`，uname FFI）-> 绕开 pipe 路径，复用 Windows slot 方案（C 线程 + sleep 轮询，不注册 event-loop fd）；`http_thread.c` slot 实现扩展 Unix 分支（pthread+libcurl），流式保留。WSL1 实测连续 5 条 WS 消息不崩溃（`logs/wsl1-accept-7075.json`）；spec：`specs/completed/2026-07-24_web-ui-fix-01-wsl1-server-crash.md`

### ✅ I-002 新建会话发首条消息后被弹回新建页，assistant 回复永不渲染
- area：聊天 / 新会话流程
- 期望（orig）：进入会话视图，回复完整渲染。
- 实际：创建会话后后端广播的 `session_list` **不包含刚创建的会话**（与 GET /api/sessions 数据源不一致）-> 前端 `Sessions.setAll()` 后发现 activeId 不在列表 -> 路由跳回 `#new` -> 后续 `assistant_message` 被守卫静默丢弃。无任何 console 报错（静默失败）；侧边栏条目名显示原始 i18n key。
- 证据：shots/current-06-chat-reply.png、findings-ui.md UI-001（WS 抓帧证明后端回复正常，是列表广播丢会话）
- 状态：✅ Fixed（2026-07-24，未提交）。修复：创建即持久化（对齐原项目 build_session 的 initial snapshot），`handle_create_session` 立即 `save_session`；另加 `Agent::rename` 内存同步防重命名被首条消息覆盖。Playwright 实测不弹回、回复渲染。spec：`specs/completed/2026-07-24_web-ui-fix-02-session-creation-broadcast.md`

## P1（11 条）

### ✅ I-003 GET /api/mcp 尾斜杠路由 404，MCP 面板整体不可用
- 期望（orig）：`/api/mcp` 200。实际：仅 `/api/mcp/` 200，`/api/mcp` 404（`lib/web/server.mbt:348-356` 只注册 `mcp.get("/")`）；前端面板显示 JSON 解析错误。
- 证据：api-diff.json、shots/current-02-nav-mcp.png；合并自 API-001 / UI-002
- 状态：✅ Fixed（2026-07-24，未提交）。修复：`server.mbt` 增加 `mcp.get("", ...)`；servers 项补 has_env/has_headers/url-null，顶层键与 orig 完全一致。Playwright 复测 MCP 面板正常加载。spec：`specs/completed/2026-07-24_web-ui-fix-04-api-response-wrappers.md`

### ✅ I-004 GET /api/sessions/:id 缺 `session` 包装层
- 期望（orig）：`{session: {...}}`。实际：平铺结构且内嵌完整 messages，同源前端读 `resp.session.*` 全 undefined。（API-002）
- 状态：✅ Fixed（2026-07-24，未提交）。两个返回分支（磁盘 + 内存 fallback）均包装 `{session: ...}`。注：fork 前端 ApiNorm 本就兼容两形状（UI 未破），此修复主要消除契约差异、为前端 v1.5.0 同步（G-001）铺路。spec：同 I-003。

### ✅ I-005 GET /api/channels 响应未包装
- 期望（orig）：`{channels: [...]}`。实际：裸数组，前端读 `data.channels` 得 undefined。（API-003）
- 状态：✅ Fixed（2026-07-24，未提交）。修复超出包装：审核加深发现项缺 `has_config`/`running`（前端按平台卡片渲染必然全显示未配置）、orig 返回所有平台而 current 只返回已配置、且 **GET 明文泄露 api_key/secret**（orig 仅 has_token 安全字段）--已全部对齐（全平台 + 四键 + has_api_key/has_secret 脱敏）。Playwright 复测 6 张平台卡片正常渲染。spec：同 I-003。

### ✅ I-006 GET /api/cron-tasks 响应未包装
- 期望（orig）：`{cron_tasks: [...]}`。实际：裸数组。（API-004）
- 状态：✅ Fixed（2026-07-24，未提交）。包装 + 项形状对齐 orig（补 `cron`/`content`/`scheduled` 三键，前端卡片依赖）。orig 额外合并手动任务文件的能力记为差距 G-005。spec：同 I-003。

### ❌ I-007 GET /api/media/types 语义被重定义
- 期望（orig）：各模态配置对象（configured/model/base_url/source，含 stt、video_understanding）。实际：文件扩展名列表。疑似遗漏而非有意，**需人工确认**。（API-005）
- 状态：Open

### ❌ I-008 GET /api/dirs 目录浏览结构不兼容
- 期望（orig）：`{root, path, parent, home, default, entries:[{name,path,type}]}`。实际：`{path, count, files:[{name,is_dir}]}`；工作目录选择器无法导航。（API-006）
- 状态：Open

### ❌ I-009 GET /api/billing/summary 结构完全不同
- 期望（orig）：period/from/to/by_day/by_model/各项 token 细分等 12 字段。实际：仅 6 字段，计费页图表无法渲染。（API-007）
- 状态：Open

### ❌ I-010 GET /api/trash 与 /api/trash/sessions 结构不兼容
- 期望（orig）：`{ok, files/sessions, total_size, ...}`。实际：均为 `{items: [], total: 0}`，回收站两个 tab 无法渲染。（API-010）
- 状态：Open

### ✅ I-011 会话时间戳序列化为 epoch 毫秒字符串，侧边栏显示 "NaN/NaN NaN:NaN"
- 期望（orig）：ISO 8601。实际：`created_at:"13429275854279"`，`new Date(...)` Invalid；`web/sessions.js:1663` 按 ISO 解析。（UI-003；POST /api/sessions 响应同样问题且缺 updated_at）
- 状态：✅ Fixed（2026-07-24，未提交）。根因比预想更深：Windows C FFI（`lib/agent/time_stub.c`）未减 1601->1970 偏移，epoch 本身错 369 年。修复：C 层照抄 billing 正确写法 + 新增 ISO 8601 FFI；`current_timestamp_iso()` 替换全部 11 个调用点；`load_session` 兼容转换两种脏 epoch 格式。Playwright 实测侧边栏显示 "Yesterday 18:24"。spec：`specs/completed/2026-07-24_web-ui-fix-03-session-serialization.md`

### ✅ I-012 HTTP 会话接口不返回 model 字段，信息栏模型切换器整体隐藏
- 期望（orig）：`sib-model` 可点出模型下拉。实际：`GET /api/sessions` 列表项 `model:null`、`GET /api/sessions/:id` 无 `model/model_id/card_model`（WS session_update 里有 model）；`web/sessions.js:3284` 按 `s.model` 决定显隐 -> 页面加载后切换器必隐藏。与 I-036 同一 SessionSummary 序列化根源。（UI-005）
- 状态：✅ Fixed（2026-07-24，未提交）。根因：`SessionData.model_name` 的 Option ToJson 写成数组而 from_json 只认 String，重载后恒 None。修复：from_json 双格式兼容 + ToJson 输出纯 String（model_name/reasoning_effort/sub_model 三个受损字段全修）+ 历史缺字段文件兜底当前模型。Playwright 实测切换器可见、下拉可点开。spec：同 I-011。

### ✅ I-013 WS subscribe 不存在的 session 返回 subscribed 成功
- 期望（orig）：回 `error "Session not found"`。实际：回 `subscribed` + session_list，无存在性检查（`lib/web/handlers_ws.mbt:188-207`）；前端会 enable 发送按钮，用户在"幽灵会话"上操作无提示。（WS-002）
- 状态：✅ Fixed（2026-07-24，fix-07）。`handle_ws_subscribe` 增加存在性检查，不存在时回 `error "Session not found"` 且不切换订阅。

## P2（18 条）

| ID | 标题 | 要点（期望 orig -> 实际 current） | 来源 | 状态 |
|---|---|---|---|---|
| ✅ I-026 | PATCH /api/sessions/:id 对未发消息的新会话 404 | 新会话首条消息持久化前只在内存，GET 能读 PATCH 读不到（handlers_session_ext.mbt:514，存储双轨，与 I-002 同源） | UI-006 | ✅ Fixed（2026-07-24，未提交）。创建即持久化后 PATCH/rename 均 200。spec：`fix-02-session-creation-broadcast` |
| ❌ I-014 | /api/billing/daily 键名不一致 | `{days:[...]}` -> `{daily:[...]}` | API-008 | Open |
| ❌ I-015 | /api/billing/records、sessions 缺字段 | 含 count/cache_read_tokens/cache_write_tokens/cost_source -> 均缺 | API-009 | Open |
| ❌ I-016 | /api/creator/skills 结构不兼容 | `{ok,licensed,cloud_skills,local_skills,...}` -> `{skills,total}` | API-011 | Open |
| ❌ I-017 | /api/config/media 缺 per-模态详情 | default_provider 五子键 + media.* 六字段 -> 缺（39 处 diff） | API-012 | Open |
| ❌ I-018 | /api/config/ocr 结构不兼容 | `{default_provider, ocr:{...}}` -> 平铺四字段 | API-013 | Open |
| ❌ I-019 | /api/config 缺当前模型指针与媒体能力 | current_id/current_index/media_capabilities -> 缺 | API-014 | Open |
| ❌ I-020 | /api/config/settings 缺 4 个开关 | enable_compression/enable_prompt_caching/memory_update_enabled/proxy_url -> 缺 | API-015 | Open |
| ❌ I-021 | /api/skills 条目缺 9 个展示字段 | name_zh/description_zh/always_show/warnings 等 -> 全缺，中文列表缺名称描述 | API-016 | Open |
| ❌ I-022 | /api/brand 缺 13 个品牌键 | product_name/logo_url/activated/... -> 仅 `{device_id}` | API-017 | Open |
| ❌ I-023 | /api/onboard/status 缺 needs_onboard/branded | 引导门禁字段缺失，**需人工确认**行为影响 | API-018 | Open |
| ❌ I-024 | /api/version 缺更新检查字段 | current/latest/needs_update/cli_command -> 缺，**需确认**是否有意重设计 | API-019 | Open |
| ❌ I-025 | /api/sessions/:id/skills 返回空数组 | orig 同位置 53 个技能 -> current `[]`，**需确认**是数据差异还是加载未实现 | API-022 | Open |
| ✅ I-027 | interrupt 后缺 session_update(idle)/progress(done) | 仅发 `interrupted` 一帧（handlers_ws.mbt:323）-> 前端状态栏卡在 running | WS-003 | ✅ Fixed（fix-07） |
| ✅ I-028 | 运行结束状态值为 "completed" 而非 "idle" | 前端 `patch.status==="idle"` 才触发 Tasks/Skills 刷新与 clearProgress（ws-dispatcher.js:268）-> 全部不执行 | WS-004 | ✅ Fixed（fix-07） |
| ✅ I-029 | task_finished 投递不到任何正常客户端 | 走了 `broadcast_global` 只发 global_subs（hub.mbt:140），按会话订阅的前端永远收不到 -> 完成提示音失效 | WS-005 | ✅ Fixed（fix-07） |
| ✅ I-030 | 会话摘要字段名与前端期望不符 | `latest_latency_ms` vs 前端读 `latest_latency`（sessions.js:3301），且缺 error_code/top_up_url/raw_message/model_id/card_model/channel_info -> 延迟信号永不显示；与 I-012 同源 | WS-007 | ✅ Fixed（fix-09）：`latest_latency` 已改为对象 `{ttft_ms, duration_ms}`；error_code/top_up_url/raw_message/model_id/card_model/channel_info 六字段已补齐 |

## P3（8 条）

| ID | 标题 | 要点 | 来源 | 状态 |
|---|---|---|---|---|
| ❌ I-032 | 部分 404 错误体缺 `ok:false` | /api/mcp/:name/tools、/api/skills/:name/content | API-020 | Open |
| ❌ I-033 | /api/store/* 缺 `ok` 字段 | 前端若以 resp.ok 判成败会误判 | API-021 | Open |
| ❌ I-034 | /api/agents 条目缺 avatar | - | API-023 | Open |
| ❌ I-035 | /api/backup/status 缺 config/dest_dir/is_wsl | - | API-024 | Open |
| ❌ I-036 | /api/browser/status 缺 chrome_version | - | API-025 | Open |
| ❌ I-037 | i18n key `sessions.untitled` 缺失显示原始 key | 上游也缺该 key，但 current 因 I-002/I-011 实际触发；`I18n.t` 返回 key 使 `\|\| "Untitled"` 兜底失效 | UI-004 | Open（I-002/I-011 修复后触发条件已大幅减少） |
| ❌ I-038 | 删除会话出现一次 DELETE net::ERR_ABORTED | 疑似前端双发 DELETE，最终生效；需人工确认 | UI-007 | Open |
| ❌ I-039 | 首页 networkidle 15s 未达成（orig 2.8s vs current 16.8s） | 存在长挂请求，不影响交互，需定位具体请求 | UI-008 | Open |
| ✅ I-040 | token_usage 发两次（第二帧 delta=0） | 前端 appendTokenUsage 每帧建 DOM -> 界面两行 token 用量 | WS-006 | ✅ Fixed（fix-07） |

## 已核实为 version-skew 或有意差异（不计入）

- ~~主题切换入口位置、头部 `#reload-header`、新会话 Advanced options、Extensions Brand 过滤 tab、accent 色板：orig v1.5.0 新增，current 前端基线 v1.4.0（见 G-001）。~~ **已随 fix-06 v1.5.0 同步解决（2026-07-24）**。
- ~~`sib-id` 文案（"Session file (xxxxxxxx)" vs 裸 id）：v1.5.0 文案改进。~~ **已随 fix-06 v1.5.0 同步解决（2026-07-24）**。
- meetings / SSE chat：web-parity-05 有意删除。ext_ui（git/time-machine）：current 独有。品牌文案、端口：刻意区分。
- 无害 WS 差异：`connected` 初始帧、pong 多 timestamp、phase_start/phase_end（前端原生支持）、非法帧行为一致。

## 待验证线索（静态走查，未在运行实例复现）

1. **会话数无上限**：`active_agents` Map 无上限（测试中出现过 `enforce_session_cap` 痕迹，待确认是否已有限制）。
2. **WebSocket 断连客户端清理**：`broadcast/hub.mbt` 内存增长风险--长跑重连测试验证。
3. **模板注入面**：`template_processor.mbt` 品牌名含 HTML/JS 时是否 XSS。
4. **路径遍历面**：`/api/backup/*`、技能名拼接、`/api/files/*` 校验完备性。
5. **Windows 下 Git C FFI**：`git_exec.c` `popen()` vs `_popen`--Git 面板操作流验证。
6. **Billing 重启丢失**：BillingStore 内存实现，重启后 Billing 面板数据是否保留（对照 orig）。
