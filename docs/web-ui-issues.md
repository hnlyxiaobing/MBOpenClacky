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
| P1 | 11 | 11 | 0 | 0 |
| P2 | 17 | 17 | 0 | 0 |
| P3 | 9 | 9 | 0 | 0 |
| **合计** | **39** | **39** | **0** | **0** |

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

### 部分解决问题清单（0 项）

I-030 已随 fix-09 全部修复，无部分解决项。

### 原待解决问题清单（29 项，已全部修复：fix-06 ~ fix-20，2026-07-25）

| ID | 标题 | 严重度 | 实施 Spec / 备注 |
|----|------|--------|------|
| ✅ I-007 | GET /api/media/types 语义被重定义 | P1 | fix-14（人工确认 gate 已批准，按 orig 五模态语义恢复） |
| ✅ I-008 | GET /api/dirs 目录浏览结构不兼容 | P1 | fix-12 |
| ✅ I-009 | GET /api/billing/summary 结构完全不同 | P1 | fix-10 |
| ✅ I-010 | GET /api/trash 与 /api/trash/sessions 结构不兼容 | P1 | fix-13 |
| ✅ I-013 | WS subscribe 不存在的 session 返回 subscribed 成功 | P1 | fix-07 |
| ✅ I-014 | /api/billing/daily 键名不一致 | P2 | fix-10（`daily`→`days`） |
| ✅ I-015 | /api/billing/records、sessions 缺字段 | P2 | fix-10 |
| ✅ I-016 | /api/creator/skills 结构不兼容 | P2 | fix-16 |
| ✅ I-017 | /api/config/media 缺 per-模态详情 | P2 | fix-11 |
| ✅ I-018 | /api/config/ocr 结构不兼容 | P2 | fix-11 |
| ✅ I-019 | /api/config 缺当前模型指针与媒体能力 | P2 | fix-11（残留 4 个 current-only 附加键，见下文） |
| ✅ I-020 | /api/config/settings 缺 4 个开关 | P2 | fix-11（原声称过时，实际差异为嵌套层级，已拍平 + AgentConfig 直读） |
| ✅ I-021 | /api/skills 条目缺 9 个展示字段 | P2 | fix-15 |
| ✅ I-022 | /api/brand 缺 13 个品牌键 | P2 | fix-18（顺带封堵 license_key 明文泄露） |
| ✅ I-023 | /api/onboard/status 缺 needs_onboard/branded | P2 | fix-18（人工确认 gate 已批准，恢复引导门禁） |
| ✅ I-024 | /api/version 缺更新检查字段 | P2 | fix-18（人工确认 gate 已批准，1h 缓存对齐 orig） |
| ✅ I-025 | /api/sessions/:id/skills 返回空数组 | P2 | fix-15（stub 接真实扫描） |
| ✅ I-027 | interrupt 后缺 session_update(idle)/progress(done) | P2 | fix-07 |
| ✅ I-028 | 运行结束状态值为 "completed" 而非 "idle" | P2 | fix-07 |
| ✅ I-029 | task_finished 投递不到任何正常客户端 | P2 | fix-07 |
| ✅ I-032 | 部分 404 错误体缺 ok:false | P3 | fix-20 |
| ✅ I-033 | /api/store/* 缺 ok 字段 | P3 | fix-20 |
| ✅ I-034 | /api/agents 条目缺 avatar | P3 | fix-20 |
| ✅ I-035 | /api/backup/status 缺 config/dest_dir/is_wsl | P3 | fix-20 |
| ✅ I-036 | /api/browser/status 缺 chrome_version | P3 | fix-20 判定 false positive |
| ✅ I-037 | i18n key sessions.untitled 缺失显示原始 key | P3 | fix-20 |
| ✅ I-038 | 删除会话出现一次 DELETE net::ERR_ABORTED | P3 | fix-20（根因同 I-039） |
| ✅ I-039 | 首页 networkidle 15s 未达成 | P3 | fix-20 |
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

### ✅ I-007 GET /api/media/types 语义被重定义
- 期望（orig）：各模态配置对象（configured/model/base_url/source，含 stt、video_understanding）。实际：文件扩展名列表。疑似遗漏而非有意，**需人工确认**。（API-005）
- 状态：✅ Fixed（2026-07-25，fix-14，人工确认 gate 已批准）。`handle_media_types_bridge` 重写为遍历五模态：`find_explicit_media_model` 显式扫描命中 → `source:"custom"`；否则 `derive_media_model` 派生 → `source:"auto"`；均无 → `{configured:false, source:"off"}`。语义照抄 Ruby `media_state`，白盒测试覆盖 off/custom/auto 三分支并断言无 api_key 泄漏。spec：`specs/completed/2026-07-24_web-ui-fix-14-media-types-semantics.md`

### ✅ I-008 GET /api/dirs 目录浏览结构不兼容
- 期望（orig）：`{root, path, parent, home, default, entries:[{name,path,type}]}`。实际：`{path, count, files:[{name,is_dir}]}`；工作目录选择器无法导航。（API-006）
- 状态：✅ Fixed（2026-07-25，fix-12）。`handle_dirs_list` 重写为 orig 六键契约：仅目录条目（绝对 path + type:"dir"）、字典序排序、IGNORED/隐藏过滤、show_hidden 放行、home 默认、`~` 展开、不存在目录回退最近存在祖先、`default` 字段。保留 `validate_path` 拒 `..`（fix-05 基线）。spec：`specs/completed/2026-07-24_web-ui-fix-12-dirs-endpoint-contract.md`

### ✅ I-009 GET /api/billing/summary 结构完全不同
- 期望（orig）：period/from/to/by_day/by_model/各项 token 细分等 12 字段。实际：仅 6 字段，计费页图表无法渲染。（API-007）
- 状态：✅ Fixed（2026-07-25，fix-10）。输出 orig 精确 12 键（period/from/to/total_cost/total_tokens/prompt/completion/cache_read/cache_write/by_model/by_day/record_count），复用 usage 端点数据源。残留：crescent bridge 会剥掉 query string，live 请求 period 参数暂走默认值（参数解析已实现并有测试），另案处理。spec：`specs/completed/2026-07-24_web-ui-fix-10-billing-api-contract.md`

### ✅ I-010 GET /api/trash 与 /api/trash/sessions 结构不兼容
- 期望（orig）：`{ok, files/sessions, total_size, ...}`。实际：均为 `{items: [], total: 0}`，回收站两个 tab 无法渲染。（API-010）
- 状态：✅ Fixed（2026-07-25，fix-13）。list 输出 `{ok, files, projects, total_count, total_size}`（files 条目九键），sessions 输出 `{ok, sessions, count, total_size}`（条目十键）；`handle_delete_session` 已接线 soft_delete（盘上会话删除时写入回收站）。残留：restore 只移清单条目、不能真正恢复会话文件（存储层范畴，另案）。spec：`specs/completed/2026-07-24_web-ui-fix-13-trash-api-contract.md`

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
| ✅ I-014 | /api/billing/daily 键名不一致 | `{days:[...]}` -> `{daily:[...]}` | API-008 | ✅ Fixed（2026-07-25，fix-10）：键名改 `days`，条目补齐 8 键，全区间零填充、最旧在前；`days` 参数默认 30 clamp 90 |
| ✅ I-015 | /api/billing/records、sessions 缺字段 | 含 count/cache_read_tokens/cache_write_tokens/cost_source -> 均缺 | API-009 | ✅ Fixed（2026-07-25，fix-10）：records 补 count+三字段、timestamp 改 ISO；sessions 补 count、条目 12 键、按 total_cost 降序 |
| ✅ I-016 | /api/creator/skills 结构不兼容 | `{ok,licensed,cloud_skills,local_skills,...}` -> `{skills,total}` | API-011 | ✅ Fixed（2026-07-25，fix-16）：五键响应，licensed 由 BrandConfig 真实派生，local_skills 真实扫描；platform_version/uploaded_at 已由 fix-17 接 upload_meta 数据源 |
| ✅ I-017 | /api/config/media 缺 per-模态详情 | default_provider 五子键 + media.* 六字段 -> 缺（39 处 diff） | API-012 | ✅ Fixed（2026-07-25，fix-11）：media.* 补为 orig 十键、default_provider 五子键；无数据源键（available/aliases/stale/requested_model/primary）按约定给空值 |
| ✅ I-018 | /api/config/ocr 结构不兼容 | `{default_provider, ocr:{...}}` -> 平铺四字段 | API-013 | ✅ Fixed（2026-07-25，fix-11）：嵌套化为 `{ocr:{十键}, default_provider:{...}}` |
| ✅ I-019 | /api/config 缺当前模型指针与媒体能力 | current_id/current_index/media_capabilities -> 缺 | API-014 | ✅ Fixed（2026-07-25，fix-11）：三键补齐 + models[].index + 排除 media/ocr 管理条目；残留：保留 4 个 current-only 附加键（PUT 回环依赖），api-diff 的 missing_in_orig 四条目保留 |
| ✅ I-020 | /api/config/settings 缺 4 个开关 | enable_compression/enable_prompt_caching/memory_update_enabled/proxy_url -> 缺 | API-015 | ✅ Fixed（2026-07-25，fix-11）：重验确认原声称过时，实际差异为嵌套层级；已拍平为 orig 平铺 + AgentConfig 直读，PATCH 同步写 AgentConfig 保持读写一致 |
| ✅ I-021 | /api/skills 条目缺 9 个展示字段 | name_zh/description_zh/always_show/warnings 等 -> 全缺，中文列表缺名称描述 | API-016 | ✅ Fixed（2026-07-25，fix-15）：frontmatter 解析增强，9 键补齐；platform_version/uploaded_at 由 fix-17 upload_meta 供给；local_modified_at 无 mtime API 恒 null（另案） |
| ✅ I-022 | /api/brand 缺 13 个品牌键 | product_name/logo_url/activated/... -> 仅 `{device_id}` | API-017 | ✅ Fixed（2026-07-25，fix-18）：显式白名单构造 orig 13 键，顺带封堵 derive(ToJson) 泄露 license_key 的安全问题 |
| ✅ I-023 | /api/onboard/status 缺 needs_onboard/branded | 引导门禁字段缺失，**需人工确认**行为影响 | API-018 | ✅ Fixed（2026-07-25，fix-18，gate 已批准）：needs_onboard/phase/branded 三键按 orig models_configured? 语义派生，未配置模型的部署恢复引导面板 |
| ✅ I-024 | /api/version 缺更新检查字段 | current/latest/needs_update/cli_command -> 缺，**需确认**是否有意重设计 | API-019 | ✅ Fixed（2026-07-25，fix-18，gate 已批准）：五键补齐 + 进程内 1h latest 缓存（失败也缓存 None，对齐 orig）；cli_command 回落 "mbopenclacky"（有意偏差） |
| ✅ I-025 | /api/sessions/:id/skills 返回空数组 | orig 同位置 53 个技能 -> current `[]`，**需确认**是数据差异还是加载未实现 | API-022 | ✅ Fixed（2026-07-25，fix-15）：确认为 stub，已接真实扫描（builtin+user 合并、user 覆盖、过滤 user_invocable:false），条目为 orig session 形状 |
| ✅ I-027 | interrupt 后缺 session_update(idle)/progress(done) | 仅发 `interrupted` 一帧（handlers_ws.mbt:323）-> 前端状态栏卡在 running | WS-003 | ✅ Fixed（fix-07） |
| ✅ I-028 | 运行结束状态值为 "completed" 而非 "idle" | 前端 `patch.status==="idle"` 才触发 Tasks/Skills 刷新与 clearProgress（ws-dispatcher.js:268）-> 全部不执行 | WS-004 | ✅ Fixed（fix-07） |
| ✅ I-029 | task_finished 投递不到任何正常客户端 | 走了 `broadcast_global` 只发 global_subs（hub.mbt:140），按会话订阅的前端永远收不到 -> 完成提示音失效 | WS-005 | ✅ Fixed（fix-07） |
| ✅ I-030 | 会话摘要字段名与前端期望不符 | `latest_latency_ms` vs 前端读 `latest_latency`（sessions.js:3301），且缺 error_code/top_up_url/raw_message/model_id/card_model/channel_info -> 延迟信号永不显示；与 I-012 同源 | WS-007 | ✅ Fixed（fix-09）：`latest_latency` 已改为对象 `{ttft_ms, duration_ms}`；error_code/top_up_url/raw_message/model_id/card_model/channel_info 六字段已补齐 |

## P3（8 条）

| ID | 标题 | 要点 | 来源 | 状态 |
|---|---|---|---|---|
| ✅ I-032 | 部分 404 错误体缺 `ok:false` | /api/mcp/:name/tools、/api/skills/:name/content | API-020 | ✅ Fixed（fix-20）：两处 404 错误体补 `ok:false`（handlers_mcp.mbt、handlers_skills.mbt），错误文案保持现状（diff 仅缺 ok） |
| ✅ I-033 | /api/store/* 缺 `ok` 字段 | 前端若以 resp.ok 判成败会误判 | API-021 | ✅ Fixed（fix-20）：`handle_store_list`/`handle_store_installed` 补 `ok:true`；残留：`/api/store/skills` 仍缺 ok/warning（不在本批范围） |
| ✅ I-034 | /api/agents 条目缺 avatar | - | API-023 | ✅ Fixed（fix-20）：按 orig 语义透传——agent 目录有 avatar.png 则 `avatar:"/agent_avatar/<id>"`，否则 null；当前资产无 avatar 文件故值为 null。完全对齐 orig 字符串值需补 avatar 资产 + /agent_avatar 路由（另立 spec） |
| ✅ I-035 | /api/backup/status 缺 config/dest_dir/is_wsl | - | API-024 | ✅ Fixed（fix-20）：`handle_backups_list`（/api/backup/status 别名唯一来源）补 orig DEFAULT_CONFIG 九键 config、dest_dir（= backups_dir()）、is_wsl（`@utils.is_wsl()`，与 orig wsl? 语义一致） |
| ✅ I-036 | /api/browser/status 缺 chrome_version | - | API-025 | ✅ False positive（fix-20 审核判定）：BrowserStatus 已含 `chrome_version:String?` 且 derive(ToJson)，status 响应包含此字段；值为 null 与 orig 未配置时行为一致，无需修改 |
| ✅ I-037 | i18n key `sessions.untitled` 缺失显示原始 key | 上游也缺该 key，但 current 因 I-002/I-011 实际触发；`I18n.t` 返回 key 使 `\|\| "Untitled"` 兜底失效 | UI-004 | ✅ Fixed（fix-20）：web/i18n.js en/zh 均补 `sessions.untitled`（"Untitled"/"未命名会话"），登记 web/PATCHES.md P3-003 |
| ✅ I-038 | 删除会话出现一次 DELETE net::ERR_ABORTED | 疑似前端双发 DELETE，最终生效；需人工确认 | UI-007 | ✅ Fixed（fix-20）：根因定位——非双发（两个 deleteSession 定义后者覆盖前者，只发一次）；实为 Chromium 对**未消费响应体**的 204 fetch 报 net::ERR_ABORTED（隔离实验证实，与 boot 无关）。修复：两处 deleteSession 补 `await res.text()`（PATCHES.md P3-002）。根治需服务端改 Content-Length 分帧（另立 spec） |
| ✅ I-039 | 首页 networkidle 15s 未达成（orig 2.8s vs current 16.8s） | 存在长挂请求，不影响交互，需定位具体请求 | UI-008 | ✅ Fixed（fix-20）：抓包定位为 auth.js `_probe()` 的 `GET /api/sessions?limit=1`——只读 r.ok 不消费 body，chunked+keep-alive 下 Chromium 永不完成该请求（响应字节经 TCP 代理验证完整到达）。修复：`_probe` 补 `await r.arrayBuffer()`（PATCHES.md P3-001），实测 networkidle 693ms 达成 |
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

## fix-10 ~ fix-20 批次遗留与新发现（2026-07-25，建议另立 spec）

1. **crescent bridge 剥掉 query string**：`event.req.path()` 不含查询串，billing 等端点的 period/days/limit 参数 live 请求不生效（解析逻辑已实现并有测试）。需 bridge 层把 query 并入 params。
2. **POST /api/dirs/mkdir 请求体键名不兼容**：前端发 `{parent,name}`，后端读 `path`（orig 收 `parent`）。fix-12 审核已上报，未入 scope。
3. **`/api/store/skills` 缺 `ok`/`warning` 键**：fix-20 I-033 只修了 store list/installed 两端点。
4. **agents 头像资产与 `/agent_avatar` 路由缺失**：I-034 已按 orig 语义透传（无资产时 null），要显示头像需补资产 + 路由。
5. **trash restore 语义不完备**：会话删除是物理删除，restore 只移清单条目、无法恢复会话文件（orig 是移动文件，存储层范畴）。
6. **skills `local_modified_at` 恒 null**：`@fs`/`@sys` 无文件 mtime API，需新增 FFI。
7. **服务端 Content-Length 分帧**：I-038/I-039 的根治方案（当前前端已逐个消费响应体绕行，crescent 层大修另案）。
8. **`lib/billing/billing_store.mbt` `ensure_billing_dir` 多级目录失效**：`@path.Path::dirname` 对 `"a/b/c"` 返回空串导致递归不触发、`append` 静默失败（生产路径单层不受影响）。
9. **媒体 `available`/`aliases` 恒空**：Providers 无媒体模型目录，设置页 custom 模式无预设下拉选项。
10. **fix-17 真实平台联通性未端到端验证**：publish 五步流程仅 mock 平台白盒覆盖，需有效 license 环境实测。
