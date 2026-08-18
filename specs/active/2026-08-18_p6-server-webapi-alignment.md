# Server / Web API 对齐（矩阵§9）· 增量 Spec

> **创建日期**: 2026-08-18  
> **状态**: 已通过对抗性审查（2026-08-18）· 已移入 `specs/active/`
> **关联总览**: `specs/draft/2026-08-18_diff-harness-matrix-backlog-overview.md`；diff-harness `docs/FEATURE_MATRIX.md` §9  
> **关联历史 spec**: 边界——server `--host/--port` CLI 参数与默认端口 7071 裁决归 B8 决策 8；trash 实体化（真实删除/恢复语义）归 B3 决策组（trash_manager 去桩化），本 spec 只负责 HTTP 路由契约；会话持久化差异归 B5；矩阵旧台账编号已被覆盖，一律使用 `矩阵§9/条目名` 锚点  
> **来源差距**: P1 静态对齐矩阵（2026-08-12）§9 partial/missing 条目，2026-08-18 逐条对当前代码复核  
> **依赖**: B3（trash 实体化先行，server 路由才有真实数据面）  
> **灰度 key**: 无

## 问题描述 [必填]

### 已被后续修复的矩阵声称（留证据，不进修复清单）

1. **XFF 伪造免认证（已被后续修复）**：矩阵声称 loopback 免认证依赖可伪造 X-Forwarded-For。当前 `lib/web/middleware/auth.mbt:5-11,213-221`：loopback bypass **默认关闭**，需 `MBOPENCLACKY_DEV_ALLOW_LOOPBACK=1` 显式开启，且 SECURITY NOTE 明示 header 可伪造；`auth_wbtest.mbt:151-157` 有"默认拒绝伪造 loopback"回归测试。残留：`extract_client_ip` 仍用 XFF 做限流/日志（已文档化为非安全边界）。
2. **trash DELETE 无条件清空（部分已被后续修复）**：矩阵声称 DELETE /api/trash 无视参数无条件清空。当前已拆分为三条路由：`DELETE /api/trash/:id`（单条，handlers_trash.mbt:344-358）、`DELETE /api/trash/sessions`（仅 session 类，L383-400）、`DELETE /api/trash`（全量清空，L362-376）。**残留**：全量清空路由仍 `ignore(request)` 无任何确认参数/范围参数，且 trash 本体是桩（B3），清空即永久丢失。
3. **时光机 restore_preview GET vs POST（已被后续修复）**：当前为 `POST`（server.mbt:292-294），与前端契约一致方向。

### 路由契约差异

4. **技能 toggle POST vs 前端 PATCH（partial，已核实）**：`sk.post("/:name/toggle")`（server.mbt:591-593）；同文件 mcp/channels 的 enabled 切换均用 `.patch("/:name/enabled")`（server.mbt:422-424,453-455），技能面是孤例，且与 Ruby/前端 PATCH 契约不符。
5. **`/api/projects` 全组缺失（missing，已核实）**：Grep lib/web 无 `/api/projects` 路由；trash list 的 `projects` 字段恒空数组（handlers_trash.mbt:215）无数据源。
6. **store/extensions/brand 等端点组 missing（missing，静态证实）**：矩阵列三组端点缺失，任务包 0 逐组核对现状。
7. **启动自动建会话 / X-Lang / config-search / ui 端点 missing（missing，静态证实）**：任务包 0 核对。

### WebSocket 协议面

8. **WS 附件丢弃（missing，已核实）**：`handle_ws_message` 只读 `content` 字段（handlers_ws.mbt:405-408），attachments/images 字段直接忽略；与 B8 决策 4 的 `-f`/`-i` 管线、B2 image_inject 联动。
9. **WS edit_message 恒截最后 user（partial，已核实）**：`handle_ws_edit_message` 固定找最后一条 user 消息截断（handlers_ws.mbt:439-457），无 message_id 定位参数；Ruby 支持按指定消息编辑。
10. **WS subscribe 无回放（missing，静态证实）**：订阅后不回放历史事件，任务包 0 核对回放契约。
11. **session_list has_more 恒 false（partial，已核实）**：`build_session_list_event` 硬编码 `"has_more": false`（protocol/types.mbt:278）；HTTP 面 `SessionListResponse.has_more` 是真实字段（types.mbt:134），WS 事件面缩水。

### 数据与展示面

12. **trash GET 统计空壳（partial，已核实）**：`handle_trash_list` 的 `total_size` 恒 0、`projects` 恒空（handlers_trash.mbt:212-218）；sessions 同样 total_size 恒 0（L236-241）。依赖 B3 trash 实体化提供真实字段。
13. **trash restore 契约差异（partial，静态证实）**：`handle_trash_restore` 仅从 trash 清单移除条目（L279-291），无真实文件恢复动作（桩，随 B3）。
14. **SPA fallback 200 vs 404（partial，已核实）**：not_found handler 对非 /api 路径回退 200 + index.html（server.mbt:888-903）；Ruby 对未知路径返回 404。裁决点：SPA 回退是 MB 超集保留还是对齐 404。
15. **品牌占位符 2 vs 4（partial，已核实）**：`process_template` 仅支持 `{{BRAND_NAME}}`/`{{EXT_SCRIPTS}}` 两个（template_processor.mbt:91-98）；Ruby 4 个。
16. **路由超时表前缀失配（partial，已核实）**：注释声称 `/api/sessions/*/chat/stream`，实现路由表是裸 `"/chat/stream"`/`"/chat"` 且 resolve 用 `has_prefix || contains`（middleware/timeout.mbt:35-36,51），任意 URL 含 "/chat" 子串即命中 120s 超时。
17. **401/429 语义与错误体差异（partial，静态证实）**：auth.mbt 限流/认证响应体格式与 Ruby 逐字段核对留任务包 0。
18. **公共路径多放 GET /api/version（partial，已核实）**：allowlist 含 `/health` 与 `GET /api/version`（auth.mbt:214 注释）；与 Ruby 白名单差异需裁决（version 信息公开面）。

## 现状分析 [必填 - 含代码验证]

### 验证记录（2026-08-18，对当前 HEAD 复核）

| 声称 | 验证方式 | 结果 | 结论 |
|------|---------|------|------|
| XFF loopback 免认证 | 读 `lib/web/middleware/auth.mbt:5-11,122-135,213-221` + `auth_wbtest.mbt:151-167` | bypass 默认关、env 门控、有防伪回归测试 | 已被后续修复（残留：限流用可伪造 IP，已文档化） |
| trash DELETE 无条件清空 | 读 `lib/web/handlers_trash.mbt:342-400` | 已拆 3 路由；全量路由仍 ignore(request) | 部分已被后续修复（残留数据丢失风险） |
| restore_preview 方法 | 读 `lib/web/server.mbt:292-294` | POST | 已被后续修复 |
| 技能 toggle POST | 读 `lib/web/server.mbt:422-424,453-455,591-593` | 技能 POST vs mcp/channels PATCH，孤例 | 证实 |
| WS 附件丢弃 | 读 `lib/web/handlers_ws.mbt:398-415` | 仅取 content | 证实 |
| edit_message 恒截最后 user | 读 `lib/web/handlers_ws.mbt:422-459` | 无 message_id 定位 | 证实 |
| session_list has_more 恒 false | 读 `lib/web/protocol/types.mbt:274-282` | 硬编码 false；HTTP 面有真实字段 | 证实（WS 面缩水） |
| trash 统计空壳 | 读 `lib/web/handlers_trash.mbt:199-243` | total_size 恒 0、projects 恒空 | 证实 |
| SPA fallback 200 | 读 `lib/web/server.mbt:885-903` | 非 /api 路径回退 index.html 200 | 证实 |
| 品牌占位符 2 个 | 读 `lib/web/template_processor.mbt:91-98` | 仅 BRAND_NAME/EXT_SCRIPTS | 证实 |
| 超时表前缀失配 | 读 `lib/web/middleware/timeout.mbt:27-57` | 裸 /chat 前缀 + contains 宽匹配 | 证实 |
| /api/projects 缺失 | Grep lib/web `api/projects` | 0 路由匹配 | 证实 |
| 公共路径白名单 | 读 `lib/web/middleware/auth.mbt:214` 注释 | /health + GET /api/version | 证实（与 Ruby 差异待裁决） |
| store/extensions/brand 端点、X-Lang、config-search、subscribe 回放、401/429 体 | 矩阵行号引用 | 未逐行核对 | 静态证实（任务包 0） |

Ruby 参照（openclacky，只读）：`web/api_app.rb`/路由定义、WS 协议文档、前端调用点。

### 影响面

数据丢失级：全量 trash 清空路由在 trash 本体桩化（B3）期间等于**永久删除无回滚**。前端断链级：技能 toggle 方法与前端 PATCH 契约不符直接 405。协议面：WS 附件丢弃使 Web UI 无法带附件/图片发起任务（与 CLI `-f`/`-i` 缺失共同构成附件管线全断）。超时表 `contains` 宽匹配可能给无关路由套上 120s 超时。

## 决策 [必填 - 含为什么]

1. **决策 1（技能 toggle 方法对齐）**：`sk.post("/:name/toggle")` 改为 `sk.patch("/:name/enabled")`，与 mcp/channels 既有形式及前端契约统一；旧路径保留一个版本的兼容重定向并记录移除期限。
   - **为什么**：同文件内三处资源两种动词，前端 PATCH 调用直接失败。
2. **决策 2（trash 路由安全化）**：`DELETE /api/trash` 全量清空要求显式确认参数（如 body `{"confirm": true}`）否则 400；真实删除/恢复语义等 B3 trash 实体化后接线；统计字段（total_size/projects）随实体化填充。
   - **为什么**：无条件全量清空 + 桩化 trash = 不可逆数据丢失；参数化确认是最低成本护栏。
3. **决策 3（WS 附件管线）**：`handle_ws_message`/`edit_message` 解析 attachments 字段（base64 或已上传文件引用），经 agent 消息注入（与 B2 image_inject、B8 `-i` 共用同一注入函数）。
4. **决策 4（edit_message 定位）**：协议增加可选 `message_id`，存在时按 ID 定位编辑点；缺省保持"最后一条 user"行为以兼容现有前端。
5. **决策 5（session_list has_more）**：WS 事件面按真实分页计算 has_more，复用 HTTP 面 SessionListResponse 逻辑。
6. **决策 6（超时表修正）**：路由表改为精确前缀（`/api/sessions/` + 后缀判定），resolve 移除 `contains` 宽匹配；注释与实现对齐。
7. **决策 7（/api/projects 与缺失端点组）**：按 Ruby 契约移植 /api/projects 组；store/extensions/brand/X-Lang/config-search/ui 端点任务包 0 核对后按优先级分期，无上游消费方的记录豁免。
8. **决策 8（裁决点组）**：SPA fallback 200——倾向保留（SPA 深链体验）并记录为 MB 超集裁决，但 /api 与 /ws 已排除，补静态资源扩展名白名单外的路径回 404 的细分；品牌占位符补齐 Ruby 第 3/4 个；GET /api/version 公开保留与否随 Ruby 白名单对齐（倾向对齐 Ruby 收紧并记录）；401/429 错误体按任务包 0 逐字段核对结论对齐。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/server.mbt` | 修改 | 技能 toggle 动词、/api/projects 路由注册 |
| `lib/web/handlers_trash.mbt` | 修改 | 全量清空确认参数、统计字段接线 |
| `lib/web/handlers_ws.mbt` | 修改 | attachments 解析、edit_message message_id |
| `lib/web/protocol/types.mbt` | 修改 | session_list has_more 真实化 |
| `lib/web/middleware/timeout.mbt` | 修改 | 前缀精确化、去 contains |
| `lib/web/template_processor.mbt` | 修改 | 占位符补齐 |
| `lib/web/handlers_projects.mbt`（新建） | 新建 | /api/projects 组 |
| `lib/web/middleware/auth.mbt` | 修改 | 白名单按裁决调整、401/429 体对齐 |
| 对应 wbtest | 修改/新建 | 逐决策回归 |

### 不涉及文件

- trash 本体实现（B3）；server 启动参数（B8）；附件注入函数本体（B2）；会话持久化（B5）。

## 实施计划 [必填]

### 任务包 0：复核与分期（预估 0.5 天）
1. store/extensions/brand、X-Lang、config-search、subscribe 回放、401/429 错误体五组静态证实条目逐行核对。
2. 缺失端点按前端消费方有无分期排序。

### 任务包 1：安全与契约修正（预估 1 天）
1. trash 全量清空确认参数；技能 toggle PATCH 化；超时表精确化。
2. wbtest：确认参数拒绝路径、toggle 动词、超时命中表。

### 任务包 2：WS 协议补齐（预估 1.5 天）
1. attachments 解析与注入接线（依赖 B2 注入函数）；edit_message message_id；session_list has_more。
2. wbtest：附件消息、编辑定位、分页标记。

### 任务包 3：端点组与收尾（预估 1.5 天）
1. /api/projects 组；品牌占位符；白名单/错误体按裁决落地。
2. `moon check` + 全量 `moon test` 无回归。

## 验收标准 [必填]

- [ ] `PATCH /api/skills/:name/enabled` 生效且前端契约联调通过；旧 POST 路径兼容期内可用
- [ ] `DELETE /api/trash` 无确认参数时返回 400，不再无条件清空
- [ ] WS message 携带 attachments 时附件进入 agent 消息（与 CLI `-i` 同一注入路径）
- [ ] edit_message 支持 message_id 定位；缺省行为不变
- [ ] WS session_list 的 has_more 与真实分页一致
- [ ] 超时表仅命中声明的 /api 前缀路由；无 contains 宽匹配
- [ ] /api/projects 组按 Ruby 契约可用
- [ ] `moon check` 0 errors；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| trash 路由改动与 B3 实体化时序冲突 | 中 | B3 先行；本 spec 任务包 1 只做参数护栏不动数据面 |
| 技能 toggle 动词变更破坏既有前端版本 | 中 | 兼容重定向保留一个版本并记录移除期限 |
| WS 附件注入引入大 payload 内存压力 | 中 | 附件大小上限与 B2/B8 附件管线共用同一限额常量 |
| /api/projects 移植牵出工作区模型差异 | 高 | 任务包 0 先核对 Ruby projects 数据模型与 MB 会话/目录模型映射 |

## 依赖关系 [必填]

- **前置依赖**：B3（trash 实体化）承载数据面；B2（image_inject 注入函数）承载附件注入。
- **后置依赖**：无。
- **交叉**：B8 决策 8 的 `--host/--port` 是本 spec 运行面的启动入口；B5 会话模型影响 /api/projects 与 WS 分页。

## 变更记录 [必填]

- 2026-08-18：创建（diff-harness 矩阵§9 残留条目核实落 spec；3 项矩阵声称已被后续修复留证据，10 项直接证实，5 项静态证实留任务包 0）。
