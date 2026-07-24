# API 响应包装层与路由修复 · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 已通过对抗性审核（2026-07-24），进入开发  
> **关联总览**: `docs/web-ui-issues.md` I-003, I-004, I-005, I-006  
> **来源差距**: I-003 MCP 尾斜杠 404；I-004 GET /api/sessions/:id 缺 session 包装；I-005 GET /api/channels 裸数组；I-006 GET /api/cron-tasks 裸数组  
> **依赖**: 无  
> **优先级**: P1  
> **灰度 key**: 无

## 问题描述 [必填]

四个 API 端点的响应格式或路由注册与前端期望不兼容，导致多个面板不可用：

1. **I-003**：`GET /api/mcp`（无尾斜杠）返回 404，MCP 面板整体不可用。路由只注册了 `mcp.get("/")`（匹配 `/api/mcp/`），未注册空路径。
2. **I-004**：`GET /api/sessions/:id` 返回平铺的 SessionData，前端读 `resp.session.*` 全 undefined。
3. **I-005**：`GET /api/channels` 返回裸数组，前端读 `data.channels` 得 undefined。
4. **I-006**：`GET /api/cron-tasks` 返回裸数组，前端读 `data.cron_tasks` 得 undefined。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| MCP 只注册 `/` | 读 `lib/web/server.mbt` 第 349-356 行 | 第 355 行 `mcp.get("/", ...)`，无 `mcp.get("", ...)` | 确认：`/api/mcp` 404，`/api/mcp/` 200 |
| cron-tasks 用空路径 | 读 `lib/web/server.mbt` 第 419-420 行 | 第 420 行 `ct.get("", ...)` | cron-tasks 路由无尾斜杠问题，但响应格式有问题 |
| sessions/:id 返回平铺 | 读 `lib/web/handlers.mbt` 第 182 行 | `ToJson::to_json(data)` 直接序列化 SessionData | 确认：无 `{session: ...}` 包装 |
| channels 返回裸数组 | 读 `lib/web/handlers_channels.mbt` 第 117 行 | `Json::array(items).stringify()` | 确认：裸数组 |
| cron-tasks 返回裸数组 | 读 `lib/web/handlers_schedules.mbt` 第 272 行 | `schedules_json.to_json().stringify()` | 确认：裸数组 |
| GET /api/sessions 已有包装 | 读 `lib/web/types.mbt` 第 233-242 行 | `SessionListResponse` 的 ToJson 输出 `{sessions: [...], has_more: ...}` | 确认：列表端点已有包装 |
| crescent 支持 `get("")` | `grep 'get(""...' lib/web/server.mbt` | cron-tasks、schedules 等组已用 `ct.get("", ...)` | 确认：crescent 支持空路径注册 |

### 详细分析

| 端点 | 当前响应 | 前端期望 | 修复方式 |
|------|---------|---------|---------|
| `GET /api/mcp` | 404 | 200 + MCP 服务器列表 | 增加 `mcp.get("", ...)` 路由 |
| `GET /api/sessions/:id` | `{session_id, name, messages, ...}`（平铺） | `{session: {session_id, name, ...}}` | 包装 SessionData |
| `GET /api/channels` | `[{...}, {...}]`（裸数组） | `{channels: [{...}, {...}]}` | 包装数组 |
| `GET /api/cron-tasks` | `[{...}, {...}]`（裸数组） | `{cron_tasks: [{...}, {...}]}` | 包装数组 |

## 决策 [必填 - 含为什么]

1. **MCP 路由增加空路径注册**（保留原决策 1）：`mcp.get("", ...)` 与 `mcp.get("/", ...)` 指向同一 handler。crescent `get("")` 已有先例（cron-tasks）。同时核对 `/api/mcp/` 响应形状与 orig `/api/mcp` 一致（`{configured, config_path, servers:[...]}`，已初验键名一致，实现时逐项字段比对）。

2. **sessions/:id 包装 `{session: ...}`**（保留原决策 2，补充理由与范围）：当前 fork 前端有 `ApiNorm.unwrapSession` 双形状适配（web/utils.js:84-107），UI 未直接破；但 **orig v1.5.0 前端已删除 ApiNorm，直读 `data.session`**（orig sessions.js:2337）——包装是前端 v1.5.0 同步（G-001）的前置条件。注意 `handle_get_session` 的内存 fallback 分支（fix-02 加的 `agent.to_session_data()`）必须同样包装。ApiNorm 兼容两种形状，包装后当前前端不受影响。

3. **channels 不止包装，需项级对齐 + 密钥脱敏**（修订原决策 3）：
   - 包装 `{channels: [...]}`；
   - 语义对齐 orig：返回**所有支持平台**（含未配置的），每项 `{platform, enabled, running, has_config}`——前端按平台卡片渲染，依赖 `has_config`/`running`（view.js:79-109），当前只返回已配置条目且无这两个字段，面板必然全显示"未配置"；
   - **安全修复**：当前 `channel_entry_to_json` 在 GET 响应中返回明文 `api_key`/`secret`（handlers_channels.mbt:62-66），orig 只返回 `has_token` 等安全字段（platform_safe_fields）——改为不输出明文密钥，用 `has_api_key`/`has_secret` 布尔替代。

4. **cron-tasks 项形状对齐 orig**（修订原决策 4）：包装 `{cron_tasks: [...]}` 之外，项从 `{id, schedule_id, cron_expression, message, next_execution, run_count}` 对齐为 orig 的 `{name, content, cron, enabled, scheduled}`（orig scheduler.rb:137-143；前端 tasks/view.js:142-157 依赖 `t.scheduled`/`t.cron`/`t.content`）。映射：`cron=cron_expression`、`content=message`、`scheduled=true`（调度条目恒有 schedule）。保留原有字段无妨（前端只读需要的）。
   - `/api/schedules` 别名：无前端消费者（仅 deprecated router.mbt 与老测试 handler_tests.mbt:250），与 cron-tasks 共用同一包装，老测试同步更新。
   - **范围外记为差距**：orig 的 cron 列表还合并"手动任务文件"（无调度的 prompt 文件，scheduled=false），当前项目无此概念 → 记入 `docs/web-ui-gaps.md` G-005，不在本 spec 实现。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及
- crescent 路由：已验证 `get("")` 可用（cron-tasks 等已用），不声称"crescent 不支持"
- FFI：不涉及
- mooncakes 依赖：不涉及
-->

### 审核验证记录（2026-07-24 对抗性审核补充）

| 声称/方案 | 验证 | 结果 |
|------|------|------|
| spec 7 项声称（路由/包装） | 读 server.mbt、handlers*.mbt 对应行 | 确认属实 |
| 前端读 `resp.session.*` 全 undefined（I-004 原始记录） | 读 web/utils.js:84-107 ApiNorm | **修正**：fork 前端有双形状适配，UI 未破；但 orig v1.5.0 已删 ApiNorm 直读 data.session（sessions.js:2337），包装是 G-001 升级前置 |
| channels 仅缺包装 | 读 channel_entry_to_json + channels/view.js:74-130 + orig api_list_channels | **加深**：项缺 has_config/running；orig 返回所有平台 current 只返回已配置；**GET 明文返回 api_key/secret**（orig 仅 has_token 等安全字段） |
| cron-tasks 仅缺包装 | 读 schedule_to_api_json + tasks/view.js:138-157 + orig scheduler.rb:129-145 | **加深**：项形状不兼容（缺 scheduled/cron/content 三键）；orig 还合并手动任务文件（记 G-005） |
| /api/schedules 前端期望 | grep web/ 全目录 | 无消费者；仅 deprecated router + handler_tests.mbt:250 |
| MCP 响应形状 | handlers_mcp.mbt:9-29 + mcp/view.js:71 | 键名 {configured, config_path, servers} 一致，实现时逐项复核 |
| fix-02 fallback 分支一致性 | handlers.mbt:179-186 | 内存 fallback 返回平铺，包装决策需同步覆盖该分支 |

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/server.mbt` | 修改 | MCP group 增加 `mcp.get("", ...)` 路由 |
| `lib/web/handlers.mbt` | 修改 | `handle_get_session` 包装 `{session: ...}`（含 fix-02 的内存 fallback 分支） |
| `lib/web/handlers_channels.mbt` | 修改 | `handle_channels_list` 包装 + 返回所有平台 + `{platform, enabled, running, has_config}` 项形状 + 密钥脱敏（has_api_key/has_secret 替代明文） |
| `lib/web/handlers_schedules.mbt` | 修改 | `handle_schedules_list` 包装 `{cron_tasks: [...]}`；`schedule_to_api_json` 项形状对齐 orig（补 scheduled/cron/content 键） |
| `lib/web/handler/handler_tests.mbt` | 修改 | `/api/schedules` 包装断言同步更新 |
| 相关 `*_wbtest.mbt` | 修改 | 包装/项形状/脱敏的白盒测试 |

### 不涉及文件

- 前端 JS（零修改，前端期望的格式正确）
- `lib/web/types.mbt`（SessionSummary 的 ToJson 不变）
- `lib/agent/` 层（不涉及）
- WS 协议层（不涉及）
- channels 的 POST/PUT/DELETE 写路径（存储格式不变，仅 GET 列表输出脱敏）

## 实施计划 [必填]

### 任务包 1：MCP 路由修复（0.5 天）
- 在 `lib/web/server.mbt` 的 MCP group 中增加 `mcp.get("", ...)` 指向同一 handler
- 比对 `/api/mcp/` 响应与 orig `/api/mcp` 的 servers 项字段（name/type/status 等），不齐则补齐
- 验证 `GET /api/mcp` 和 `GET /api/mcp/` 均返回 200 且形状一致

### 任务包 2：sessions/:id 包装（0.5 天）
- `handle_get_session`：两个分支（磁盘命中 + fix-02 内存 fallback）均包装 `{session: ...}`
- 白盒测试验证包装结构

### 任务包 3：channels 列表对齐 + 脱敏（0.5 天）
- 包装 `{channels: [...]}`
- 返回所有支持平台（复用 `normalize_platform` 的平台清单），未配置平台 `has_config=false/enabled=false/running=false`
- 已配置条目：`has_config=true`，`running` 由 ChannelEntry.status 推导
- 脱敏：移除明文 api_key/secret，改 `has_api_key`/`has_secret` 布尔

### 任务包 4：cron-tasks 列表对齐（0.5 天）
- 包装 `{cron_tasks: [...]}`
- `schedule_to_api_json` 增加 `cron`（=cron_expression）、`content`（=message）、`scheduled`（=true）键，保留原键兼容
- `handler_tests.mbt` 的 `/api/schedules` 断言同步更新

## 验收标准 [必填]

- [x] `GET /api/mcp`（无尾斜杠）返回 200，MCP 面板正常加载（Playwright 复测无 JSON 解析错误，`fix04-ui-verify.json`）
- [x] `GET /api/mcp/`（有尾斜杠）仍返回 200；顶层键与 orig 完全一致（E2E step1）
- [x] `GET /api/sessions/:id` 返回 `{session: {...}}` 结构（含内存 fallback 分支，白盒测试两分支覆盖 + E2E step2）
- [x] `GET /api/channels` 返回 `{channels: [...]}`，含全部 6 平台条目，每项有 `platform/enabled/running/has_config`（E2E step3 + 白盒测试）
- [x] `GET /api/channels` 响应不含明文 api_key/secret（白盒测试种植密钥断言不泄露；E2E 递归扫描）
- [x] `GET /api/cron-tasks` 返回 `{cron_tasks: [...]}`，项含 `name/content/cron/enabled/scheduled`（E2E step4 建-验-删）
- [x] 前端频道面板、定时任务面板正确渲染（Playwright：channels 6 张平台卡片正常分组渲染，tasks 空态正常，零 console 错误）
- [x] `moon check` 0 errors（lib/web）
- [x] `moon test lib/web` 通过（347/347，主 agent 独立复验一致）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| channels 语义变化（返回未配置平台）影响现有消费者 | 低 | 前端按平台卡片渲染本就预期全平台列表；TUI/其他消费者 grep 确认无依赖裸数组 |
| 密钥脱敏影响 channels 编辑回显 | 中 | 检查前端编辑表单是否依赖 GET 返回的明文密钥回填——若是则改为编辑时单独获取（orig 用 has_token 方案，前端表单对应设计）；当前前端 v1.4.0 的 channels 表单为只读配置卡片，实测验证 |
| cron 项新增键破坏现有消费者 | 低 | 纯新增键，原键保留 |
| 包装后破坏已有测试 | 低 | 更新白盒测试中验证响应结构的断言（handler_tests.mbt:250） |
| sessions/:id 包装影响 ApiNorm | 低 | ApiNorm 显式兼容 `{session:...}` 与平铺两种形状（utils.js:96-102） |

## 依赖关系 [必填]

- **前置依赖**: 无
- **后置依赖**: G-001（前端 v1.5.0 同步）依赖 sessions/:id 包装；G-005（手动任务文件概念）由本 spec 审核发现，另立差距记录

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | I-003 + I-004 + I-005 + I-006 P1 API 格式修复 |
| 2026-07-24 | 对抗性审核修订：I-004 修复理由修正为 v1.5.0 前端同步前置（fork 前端 ApiNorm 双形状适配，UI 未破），补内存 fallback 分支包装；I-005 加深为项级对齐（has_config/running/全平台语义）+ 密钥明文泄露安全修复；I-006 加深为项形状对齐（scheduled/cron/content）；新增 G-005（手动任务文件）差距记录；补充 7 项审核验证记录 | 审核发现 2 处问题加深、1 处安全问题、1 处修复理由修正 |
| 2026-07-24 | 开发完成，验收通过。改动：`server.mbt`（mcp.get("")）、`handlers_mcp.mbt`（servers 项补 has_env/has_headers/url-null，与 orig 顶层键完全一致）、`handlers.mbt`（get_session 两分支包装）、`handlers_channels.mbt`（包装 + 全平台 + has_config/running + 脱敏 has_api_key/has_secret，channel_entry_to_json 唯一调用方即列表，写路径不含密钥无需改）、`handlers_schedules.mbt`（包装 + cron/content/scheduled 三键）、handler_tests.mbt 老断言同步。验证：moon test 347/347（双重复验）；E2E 全过（fix04-e2e.json）；Playwright 三面板渲染正常零 console 错误。偏差：MCP servers 项级比对因 7075 无配置只能静态对齐；channels 脱敏实证靠白盒种植测试（用户未配置频道） | 实现与验证完成，归档 |
