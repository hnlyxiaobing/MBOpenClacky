# Web Parity P1：WS /ws 协议 + 会话核心 REST（聊天主链路）· 增量 Spec

> **创建日期**: 2026-07-21  
> **状态**: 已完成（implemented）  
> **关联总览**: `docs/web_ui_replication_plan.md`（§1.2 WS 协议全表、§1.3 会话核心簇）  
> **关联历史 spec**: `specs/active/2026-07-21_web-parity-00-managed-fork-master.md`、`...-01-assets-static-server.md`  
> **来源差距**: 原前端聊天全部走单端点 WS `/ws`；本项目现有 `/ws/sessions/:id`（自设消息类型）+ SSE 伪流式，与原契约不兼容  
> **依赖**: web-parity-01（前端就位，可浏览器实测）  
> **灰度 key**: 无

## 问题描述 [必填]

实现原前端聊天主链路的后端契约：单端点 WebSocket `/ws`（8 种上行消息、30+ 种下行事件）+ 会话核心 REST（CRUD/消息历史/fork/export/模型切换）+ 附件与目录端点 + 模型配置端点。验收标准 = 用原前端零修改完成"建会话→发消息→看回复与工具调用→中断→管理会话"全流程。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 原前端无 SSE | `grep -r EventSource D:/MoonBit/openclacky/lib/clacky/web` | 0 命中；服务端无 text/event-stream | 确认：实时通道只有 WS |
| 原 WS 上行消息集 | 读 `http_server.rb:6199-6257` | subscribe / message / edit_message / confirmation / interrupt / run_task / list_sessions / ping 共 8 种 | 实现清单 |
| 原 WS 下行事件权威清单 | 读 `web/ws-dispatcher.js:140-441` | 30+ 事件（session_list/subscribed/session_update(全量+增量)/history_user_message/assistant_message/tool_call/tool_args/tool_result/tool_error/tool_stdout/progress/complete/request_confirmation/request_feedback/interrupted/info/warning/success/error/phase_start/phase_end/token_usage/diff/file_preview/shell_preview/todo_update/upgrade_*/server_stop 等） | 逐事件核对基准 |
| assistant 推送粒度 | 读 `web_ui_controller.rb:436` emit 集合 | 按整条/按块推 `assistant_message`，无 token 级流式 | 降低对齐难度：本项目 hook 事件聚合后按条推即可 |
| 本项目 WS 现状 | 读 `lib/web/handlers.mbt:636-777`、`lib/web/broadcast/hub.mbt` | `/ws/sessions/:id`：ping/subscribe/list_sessions/interrupt/message；message 路径经 hook 实时广播事件（真实时）；多客户端扇出 hub 已有 | 可复用 hub 与 hook 广播；需改为单端点 + subscribe 切会话 + 事件名/字段对齐 |
| 本项目会话 REST 现状 | `lib/web/server.mbt:179-219` | 已有 GET/POST sessions、GET/DELETE :id、:id/restore、fork、rename、working_dir、messages、export(自设 POST) 等 | 大量 handler 可复用，工作是路径/形状对齐 |
| 原会话核心端点清单 | 读 `http_server.rb:510-758` | GET/POST /api/sessions（q/q_scope/date/type/exclude_type 过滤）、GET/PATCH/DELETE :id（PATCH 支持 name 与 pinned）、POST :id/fork、GET :id/messages(limit≤100, before 浮点时间戳)、PATCH :id/model、GET :id/export(**zip 二进制**)、GET :id/skills、GET :id/files | 差距清单 |
| 原消息历史与 WS 事件同构 | 读 `http_server.rb:5738 api_session_messages` | `{events:[与 WS 事件同构], has_more}` | 历史/实时必须共用同一序列化函数 |
| 附件/目录端点 | 读 `http_server.rb:3667,4419,4467` | POST /api/upload(multipart 字段 `file`)→{ok,name,path}；GET /api/dirs?path&show_hidden→{root,path,parent,home,default,entries[dir]}；POST /api/dirs/mkdir{parent,name} | 本项目 server.mbt:445-457 有 /api/dirs、mkdir、/api/files/upload，形状待核对 |
| 模型配置端点 | 读 `http_server.rb:5299,5491,5559,5611,5642,5656,5717` | GET /api/config、POST/PATCH/DELETE /api/config/models*、POST :id/default、POST /api/config/test、GET /api/providers | 本项目自设路径 /api/models*（handlers_extra.mbt:449+）需迁移 |
| 本项目 SSE 端点 | `lib/web/server.mbt:195` 区域、`lib/web/sse/sse.mbt` | POST :id/chat/stream 存在；伪流式（handlers.mbt:311 TODO） | 保留至 P4 清理；新前端不消费 |

### 详细分析

P1 是系列中工作量与风险最高的阶段，核心难点有三个：① WS 事件字段与 `ws-dispatcher.js` 期望的逐字段同构；② 历史消息（REST）与实时事件（WS）共用序列化，否则切会话后渲染不一致；③ SessionSummary 字段集与本项目会话模型的映射（P0 已建缺省值，本阶段填真值：total_tasks/total_cost/model/pinned/latest_latency 等）。

## 决策 [必填 - 含为什么]

1. **新建 `/ws` 单端点，保留旧 `/ws/sessions/:id` 至 P4**：新前端只连 `/ws`；旧端点唯一消费者是 legacy 前端，删它属 P4 清理，避免本阶段爆炸式改动。
2. **事件序列化单一入口**：新建 `lib/web/protocol/`（或同等内聚模块）承载"原契约事件类型 + JSON 序列化"，REST messages 与 WS 推送共用。理由：同构是硬约束，两处手写必然漂移。
3. **assistant 按条推送，不做 token 级**：原前端本就如此设计；本项目 hook 的 `stream`(chunk) 事件在 WS 路径聚合为完整 `assistant_message` 后再推。若未来要打字机效果，走 `{{EXT_SCRIPTS}}` 扩展缝，不改契约。
4. **`request_confirmation` 阻塞语义用异步等待实现**：原 Ruby 阻塞 agent 线程 300s 等浏览器回 `confirmation`；MoonBit 侧用 async 等待 + 超时，不阻塞 WS 读循环（hub 已是扇出结构）。
5. **`GET :id/export` 对齐为 zip 二进制下载**（Content-Disposition: attachment）：本项目现有 POST export/export-zip 保留至 P4，新契约 GET 优先。
6. **错误事件透出可读 message**：沿用 7-20 报告缺陷 #4 的修复方向，error 事件带 `{error, code?}`，`insufficient_credit` 等特殊码对齐原形状。
7. **PATCH :id 同时支持 name 与 pinned**：对齐 `api_rename_session`（http_server.rb:5765），并广播 `session_updated`。

<!-- MoonBit 约束检查：
- crescent WS：已有 /ws/sessions/:id 实现在用（handlers.mbt:636），单端点 /ws 是同一能力的不同路由形状，不声称新能力。
- AOT：不涉及动态 trait。
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/protocol/*.mbt`（新包） | 新建 | 原契约事件模型 + 序列化（WS 事件、messages 历史事件、SessionSummary 形状）+ `moon.pkg` |
| `lib/web/server.mbt` | 修改 | 挂 `/ws`；会话核心端点形状对齐（PATCH :id 支持 pinned、GET :id/export zip、:id/messages 参数与形状、GET :id/skills、:id/files）；模型端点挂 `/api/config/models*`（旧 `/api/models*` 暂留） |
| `lib/web/handlers_ws.mbt`（或 handlers.mbt 内新段） | 新建/修改 | `/ws` 消息循环：8 种上行消息分发；subscribe 维护 session→conn 映射；message 触发 agent 运行并经 hub 广播 |
| `lib/web/broadcast/hub.mbt` | 修改 | 支持"全局连接 + 按 session_id 订阅"模型（当前为按路径参数绑定） |
| `lib/web/handlers.mbt` | 修改 | sessions/messages/export handler 形状对齐；复用 protocol 序列化 |
| `lib/web/handlers_extra.mbt` | 修改 | 模型 CRUD 增 `/api/config/models*` 别名或迁移（响应形状对齐 {id,index,model,base_url,api_key_masked,anthropic_format,type} + current_index/current_id） |
| `lib/web/hooks→事件映射`（agent hooks 适配层） | 新建/修改 | agent 运行 hook → protocol 事件（tool_call/tool_result/progress/complete/error...） |
| `lib/web/upload`（handlers 内） | 修改 | `/api/upload` multipart 对齐；`/api/dirs`、`/api/dirs/mkdir` 响应形状对齐（root/path/parent/home/default/entries） |
| `test/scenarios/web/*.json` | 新建若干 | WS 协议场景（subscribe/message/interrupt/confirmation）、REST 形状探针 |
| `test/` WS 集成测试 | 新建 | 用 WS 客户端跑"发消息→收 assistant_message→complete"闭环（可用 mock agent 或真实小模型） |

### 不涉及文件

- `web/`（零修改纪律；本阶段不得改前端任何文件）
- `lib/web/sse/`（保留至 P4）
- 设置/Profile/技能等 P2 端点；git/time_machine 等 P3 端点

## 实施计划 [必填]

### 任务包 1：protocol 包 + SessionSummary 填真值（1 天）
- 事件类型建模与序列化；SessionSummary 字段映射表落地（对照 session_registry.rb:517-543）；单测覆盖序列化形状。

### 任务包 2：/ws 端点与上行消息（2 天）
- 路由 + 握手 + 读循环；ping/list_sessions/subscribe（含 session_update 全量快照 + subscribed 回复）；hub 改造支持会话订阅；断线重连语义（前端自动重发 subscribe，服务端幂等）。

### 任务包 3：message → agent 运行 → 事件广播（2 天）
- hooks 适配层：agent 事件 → protocol 事件 → hub；history_user_message 回显；interrupt/confirmation/edit_message/run_task；错误码对齐。

### 任务包 4：会话 REST 对齐（1.5 天）
- 列表过滤参数、PATCH name/pinned、fork、messages 分页、export zip、:id/skills、:id/files（Windows 路径越界检查对齐 http_server.rb:4354-4467）。

### 任务包 5：附件/目录/模型端点（1 天）
- /api/upload、/api/dirs*、/api/config + /api/config/models* + /api/config/test + /api/providers。

### 任务包 6：端到端验收（0.5 天）
- 浏览器实测全流程 + Playwright 对比（聊天页 DOM 探针）；场景测试落库。

## 验收标准 [必填]

- [ ] 原前端零修改完成：新建会话（选 agent 类型/工作目录/模型）→ 发消息 → 实时看到 progress/tool_call/assistant_message → complete；中断按钮生效
- [ ] 切换会话后历史消息渲染与实时事件一致（同构序列化）
- [ ] `request_confirmation` 出现时前端确认框可用，回应后 agent 继续
- [ ] 会话列表：搜索/类型过滤/分页（Load more）/重命名/置顶/删除/fork 均可用
- [ ] 附件上传（multipart）后消息可携带 files；新建会话目录浏览器可用
- [ ] 设置页 Models 分区：模型列表/增删改/设默认/测试连接可用
- [ ] 会话导出下载 zip
- [ ] `moon check` 0 errors（lib/web）；`moon test lib/web` 通过；新增 WS 场景测试 PASS

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| WS 事件字段与 dispatcher 期望逐字段不同构 → 渲染静默异常 | 高 | 以 ws-dispatcher.js:140-441 为权威逐事件核对；每事件写一个序列化单测；浏览器实测兜底 |
| agent hooks 事件与原事件语义映射不全（如无 phase/subagent 对应物） | 中 | 映射表先行；无对应物的事件登记 TODO 到 P3/P4，前端对未知事件容错 |
| hub 改造影响旧 /ws/sessions/:id 与 SSE 路径 | 中 | 旧路径保留不改；hub 新能力以新方法扩展，旧方法签名不动 |
| Windows 路径（盘符、.. 越界）在 dirs/files 端点出错 | 中 | 对照 Ruby 实现逐行为对齐；Windows 实测 D 盘多目录 |
| LLM 端点兼容性（7-20 报告缺陷 #3 的 ark/volces 失败）阻塞聊天验收 | 高 | 该缺陷修复（lib/client）是 P1 任务包 3 的前置条件；若未修，验收用可用端点 |

## 依赖关系 [必填]

- **前置依赖**：web-parity-01（前端就位）；LLM client 可用性（7-20 报告缺陷 #3，若仍存在需先行修复）
- **后置依赖**：web-parity-03、04 的所有交互验收依赖本阶段 WS/REST 基座

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-21 | 初始版本：WS 上下行消息集、REST 差距清单、同构序列化决策均经读码验证（http_server.rb / ws-dispatcher.js / handlers.mbt / server.mbt） | 受管 A 方案 P1 落地 |
| 2026-07-21 | 审核修正：交叉引用 draft→active（2 处）；8 项对抗性检查通过（/ws/sessions/:id 路由 :609+handler :636 确认、会话 REST :180-201 确认、meetings 重复注册确认）；crescent WS 已有实现不涉及新能力 | 对抗性审核 + 第一性原理校验 |
