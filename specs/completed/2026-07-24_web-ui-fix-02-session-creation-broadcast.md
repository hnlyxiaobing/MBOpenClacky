# 新建会话创建与广播流程修复 · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 已通过对抗性审核（2026-07-24），进入开发  
> **关联总览**: `docs/web-ui-issues.md` I-002, I-026  
> **来源差距**: I-002 - 新建会话发首条消息后被弹回新建页；I-026 - PATCH 新会话 404  
> **依赖**: I-001（server 崩溃修复，需 server 存活才能验证会话流程）  
> **优先级**: P0  
> **灰度 key**: 无

## 问题描述 [必填]

新建会话（POST /api/sessions）后发送首条消息时，前端被弹回新建页（`#new`），assistant 回复永不渲染。根因是后端 WS 广播的 `session_list` 事件**不包含刚创建的会话**——`send_session_list` 只读取磁盘上的持久化会话（`@agent.list_sessions()`），而新会话在首条消息处理完成前仅存在于内存 `active_agents` 中。

同一存储双轨问题也导致 PATCH /api/sessions/:id 对新会话返回 404（I-026），因为 `handle_session_patch` 同样只读磁盘。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| send_session_list 只读磁盘 | `grep "fn send_session_list" lib/web/handlers_ws.mbt` + 读第 223-253 行 | 第 224 行 `let all_sessions = @agent.list_sessions()`，遍历磁盘文件 | 确认：不含内存中的 active_agents |
| list_sessions 读磁盘 | `grep "fn list_sessions" lib/agent/session_store.mbt` + 读第 97-127 行 | 第 100 行 `@fs.read_dir(dir)`，遍历 .json 文件 | 确认：纯磁盘读取 |
| handle_get_session 有内存 fallback | 读 `lib/web/handlers.mbt` 第 160-193 行 | 第 184-186 行：`load_session(id)` 为 None 时查 `active_agents.get(id)` | 确认：GET 有 fallback，但 session_list 没有 |
| handle_session_patch 只读磁盘 | 读 `lib/web/handlers_session_ext.mbt` 第 497-510 行 | 第 510 行 `@agent.load_session(id)`，None 时无 fallback 直接 404 | 确认：PATCH 无内存 fallback |
| POST /api/sessions 存入 active_agents | 读 `lib/web/handlers.mbt` 第 130-155 行 | 第 144 行 `server_ref.val.active_agents[session_id] = agent` | 确认：新会话存内存，未持久化 |
| WS subscribe 有内存 fallback | 读 `lib/web/handlers_ws.mbt` 第 188-197 行 | `load_session(target)` None 时查 `active_agents.get(target)` | 确认：subscribe 有 fallback |
| 前端 setAll 后检查 activeId | 文档引用 `web/sessions.js` Sessions.setAll() | activeId 不在列表则跳回 `#new` | 确认：前端守卫导致跳回 |

### 详细分析

存储双轨问题一览表：

| 操作 | 读磁盘 (`load_session`) | 读内存 (`active_agents`) | 问题 |
|------|:---:|:---:|------|
| GET /api/sessions（列表） | ✅ | ❌ | 新会话不在列表 |
| WS session_list 广播 | ✅ | ❌ | 同上 |
| GET /api/sessions/:id | ✅ | ✅（fallback） | 正常 |
| WS subscribe | ✅ | ✅（fallback） | 正常 |
| PATCH /api/sessions/:id | ✅ | ❌ | 新会话 404 |
| DELETE /api/sessions/:id | ✅ | ❓ | 需确认 |

**根因**：`send_session_list`（WS 广播）和 `handle_session_patch`（REST PATCH）缺少与 `handle_get_session`/`handle_ws_subscribe` 一致的 `active_agents` fallback。

## 决策 [必填 - 含为什么]

> 2026-07-24 对抗性审核修订：原"读取处合并内存会话"方案（决策 1-3）**整体打回**——审核发现原项目参考实现用的是**创建即持久化**，且原方案存在三处问题（见下方审核验证记录）。

1. **创建即持久化（对齐原项目）**：`handle_create_session` 在 `active_agents[session_id] = agent` 之后立即 `@agent.save_session(agent.to_session_data())`（catch IO 错误仅降级不失败——内存轨道仍在，退化为现状）。原项目 `build_session`（http_server.rb:6760-6763）的注释明确写了这一意图："Persist an initial snapshot so the session is immediately visible in registry.list (which reads from disk). Without this, new sessions only appear after their first task."一处改动根治整个双轨类 bug：WS session_list、GET /api/sessions、PATCH、rename 全部自然命中磁盘轨道。比"3+ 处读取点合并"更简单、更接近参考实现、且无后续维护负担。

2. **PATCH/rename 同步内存 agent 名称**：持久化后 `load_session` 必命中，无需内存 fallback；但必须解决"重命名后首条消息运行会用内存旧名覆盖磁盘新名"的问题。原项目 `api_rename_session` 是先 `agent.rename(new_name)` 更新活 agent 再 save。当前项目 `Agent.name` 为不可变字段且无 rename 方法——在 `lib/agent/agent.mbt` 将 `name` 改为 `mut` 并新增 `pub fn Agent::rename(self, new_name)`；`handle_session_patch` 与 `handle_session_rename` 在写盘前，若 `active_agents` 中有该 agent 则同步 rename。

3. **不修改读取路径**：`send_session_list`、`handle_list_sessions`、`list_sessions()` 均不动（磁盘轨道已有数据）。不做任何内存合并逻辑。

4. **补齐 rename 路由**：原 spec 只覆盖 `handle_session_patch`，审核发现 `handle_session_rename`（PATCH /api/sessions/:id/rename，UI 实际使用的路由）有同样的 404 bug，一并修复。

### 审核验证记录（2026-07-24 对抗性审核补充）

| 声称/方案 | 验证 | 结果 |
|------|------|------|
| spec 全部 7 项声称（send_session_list 读磁盘等） | 读 handlers_ws.mbt:180-258、handlers.mbt:7-209、handlers_session_ext.mbt:490-631 | 全部确认属实 |
| GET /api/sessions 只读磁盘 | handlers.mbt:21 | 确认；UI-001 中"GET 含新会话"是因为首条消息已开始处理并持久化，时间窗问题 |
| DELETE 有双轨处理 | handlers.mbt:203-204 | 确认无问题 |
| 原方案"合并内存会话" | 对照原项目 build_session（http_server.rb:6758-6763） | **打回**：原项目明确采用创建即持久化；合并方案需改动 3+ 读取点且与参考实现分歧 |
| "Agent struct 不变"（原 spec 不涉及列表） | lib/agent/agent.mbt:9-12 | **证伪**：`name` 不可变、无 rename 方法，内存同步必须改 agent.mbt |
| 重命名会被首条消息覆盖 | orig api_rename_session（agent.rename→save）；当前 Agent 无 rename | 确认风险真实存在，纳入决策 2 |
| handle_session_rename 同病 | handlers_session_ext.mbt:128 | 确认同样无 fallback 直接 404，纳入范围 |
| enforce_session_cap 影响 | lib/agent/session_manager.mbt:15 | 无影响（cap=200 删最旧，新会话最新） |

<!-- MoonBit 约束检查：
- AOT 约束：不涉及动态加载 trait，无影响
- crescent 路由：不涉及新路由
- FFI：不涉及
- mooncakes 依赖：无新增
- 测试：native-only
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers.mbt` | 修改 | `handle_create_session` 创建后立即 `save_session`（catch 降级） |
| `lib/web/handlers_session_ext.mbt` | 修改 | `handle_session_patch`、`handle_session_rename` 写盘前同步内存 agent 名称 |
| `lib/agent/agent.mbt` | 修改 | `name` 字段改 `mut`；新增 `pub fn Agent::rename()` |
| `lib/agent/*_wbtest.mbt` 或 `lib/web/*_wbtest.mbt` | 修改 | rename 及创建持久化的单元测试 |

### 不涉及文件

- `lib/web/handlers_ws.mbt`（send_session_list 不动，磁盘轨道已有数据）
- `lib/agent/session_store.mbt`（`list_sessions()` 保持纯磁盘语义）
- 前端 JS（零修改，前端逻辑正确，是后端数据缺失）
- WS 路由/协议层

## 实施计划 [必填]

### 任务包 1：创建即持久化（0.5 天）
- `handle_create_session`（handlers.mbt:147 附近）：`active_agents[session_id] = agent` 后调用 `@agent.save_session(data) catch { ... }`，IO 失败仅降级（内存轨道仍在），不影响 201 响应
- 验证：POST /api/sessions 后立即 GET /api/sessions 与 WS session_list 均含新会话

### 任务包 2：Agent::rename + 内存同步（0.5 天）
- `lib/agent/agent.mbt`：`name` 改 `mut`，新增 `pub fn Agent::rename(self : Agent, new_name : String) -> Unit`
- `handle_session_patch`、`handle_session_rename`：写盘前若 `active_agents.get(id)` 存在则同步 rename
- 单元测试：rename 后 `to_session_data().name` 为新名

### 任务包 3：端到端验证（0.5 天）
- moon check / moon test lib/agent lib/web
- 实机复测 UI-001/UI-006 流程：新建会话→发消息不弹回、回复渲染；新建会话立即重命名 200；重命名后发首条消息名字不丢

## 验收标准 [必填]

- [x] 新建会话后，WS `session_list` 广播包含新会话（创建即持久化，磁盘轨道立即可见；E2E 实测 subscribe 后 session_list 含新会话）
- [x] 新建会话后发送首条消息，前端进入会话视图，不被弹回 `#new`（Playwright 实测 final hash `#session/<id>`，`logs/web-compare/2026-07-24/fix02-ui-verify.json`）
- [x] assistant 回复正常渲染（WS 帧嗅探 + DOM 双重验证：assistant_message content 非空且 .msg-assistant 渲染对应文本）
- [x] PATCH /api/sessions/:id 与 PATCH /api/sessions/:id/rename 对新会话返回 200，不返回 404（E2E 均 200）
- [x] 重命名新会话后发送首条消息，会话名不被覆盖回旧名（E2E `name_after_message` 保持重命名值）
- [x] 创建后磁盘立即存在会话文件（`~/.mbopenclacky/sessions/s_*.json` 创建即存在）
- [x] `moon check` 0 errors（lib/web、lib/agent）
- [x] `moon test lib/web lib/agent` 通过（531/531，主 agent 独立复验一致）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 创建时空会话落盘，用户建而不发产生空会话文件 | 低 | 与原项目行为一致；会话可见可删；enforce_session_cap(200) 兜底 |
| save_session IO 失败影响创建响应 | 低 | catch 降级：内存轨道仍在，退化为现状，201 照常返回 |
| Agent.name 改 mut 影响其他构造点 | 低 | 仅字段可变性变化，构造函数签名不变；moon check 全量验证 |
| 重命名与并发首条消息竞态 | 低 | 单线程事件循环，rename 与 run 的 persist 顺序执行 |

## 依赖关系 [必填]

- **前置依赖**: I-001（WSL1 server crash fix，已完成）——server 需存活才能验证会话流程
- **后置依赖**: I-011（时间戳格式修复，fix-03）——session_list 中的时间戳格式错误会导致侧边栏显示 "NaN/NaN"，需配合修复

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | I-002 + I-026 P0 核心流程修复 |
| 2026-07-24 | 对抗性审核修订：打回"读取处合并内存会话"整体方案，改为对齐原项目的创建即持久化（原项目 build_session:6760-6763 注释明确此意图）；新增决策 2（Agent::rename 内存同步，防止重命名被首条消息覆盖）；handle_session_rename 纳入范围；改动范围修正（lib/agent/agent.mbt 必须修改，原"不涉及"证伪）；补充 8 项审核验证记录 | 审核发现原方案与参考实现分歧且范围遗漏 2 处 |
| 2026-07-24 | 开发完成，验收通过。改动：`lib/agent/agent.mbt`（name 改 mut + Agent::rename + 单测）、`lib/web/handlers.mbt`（创建即 save_session，catch 降级）、`lib/web/handlers_session_ext.mbt`（patch/rename 写盘前同步内存 agent 名）。验证：moon test 531/531（双重复验）；E2E 五项全过（`logs/web-compare/2026-07-24/fix02-e2e.json`）；Playwright UI 实测不弹回、回复渲染（fix02-ui-verify.json + WS 帧嗅探 probe）。偏差：lib/web 集成测试层未新增用例（无现成 build_app 测试设施，仅加 agent 层单测） | 实现与验证完成，归档 |
