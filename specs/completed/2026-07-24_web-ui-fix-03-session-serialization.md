# 会话序列化格式对齐（时间戳/字段名/模型字段） · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 已通过对抗性审核（2026-07-24），进入开发  
> **关联总览**: `docs/web-ui-issues.md` I-011, I-012, I-030  
> **来源差距**: I-011 - 时间戳 epoch 字符串导致 "NaN/NaN"；I-012 - model 字段 null 导致模型切换器隐藏；I-030 - latest_latency_ms 字段名不匹配  
> **依赖**: 无（与 I-002 独立，但 I-002 修复后这些字段才会在新会话中体现）  
> **优先级**: P1  
> **灰度 key**: 无

## 问题描述 [必填]

`SessionSummary` 序列化存在三处与前端期望不兼容的问题：

1. **时间戳格式错误（I-011）**：`created_at` / `updated_at` 序列化为 epoch 毫秒字符串（如 `"13429275854279"`），前端 `new Date(string)` 返回 Invalid Date，侧边栏显示 "NaN/NaN NaN:NaN"。
2. **model 字段缺失（I-012）**：`GET /api/sessions` 列表项 `model: null`，前端按 `s.model` 决定模型切换器显隐，导致切换器必隐藏。
3. **latest_latency 字段名不匹配（I-030）**：后端序列化为 `latest_latency_ms`，前端读 `latest_latency`（sessions.js:3301），延迟信号永不显示。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 时间戳是 epoch ms 字符串 | `grep "fn current_timestamp_ms" lib/agent/session_data.mbt` + 读第 538-541 行 | `current_time_ms().to_string()` 返回如 "13429275854279" | 确认：非 ISO 8601 |
| created_at 赋值来源 | `grep "current_timestamp_ms" lib/agent/agent.mbt` | 第 98 行 `created_at: current_timestamp_ms()` | 确认：Agent 构造时赋值 |
| updated_at 是 TODO | 读 `lib/web/handlers_ws.mbt` 第 243 行 | `updated_at: sd.created_at, // TODO(P1): track real updated_at` | 确认：updated_at 暂等于 created_at |
| SessionSummary.model 字段 | 读 `lib/web/types.mbt` 第 66-85 行 | `model : String?` 字段存在 | 字段存在但赋值来源需验证 |
| model 赋值来源 | 读 `lib/web/handlers_ws.mbt` 第 241 行 | `model: sd.model_name` 其中 sd 来自 list_sessions（磁盘） | 磁盘 SessionData 有 model_name 字段 |
| SessionData.model_name | 读 `lib/agent/session_data.mbt` 第 183 行 | `model_name : String?` | 确认：SessionData 有此字段 |
| to_session_data 赋值 | 读 `lib/agent/session_data.mbt` 第 215 行 | `model_name: Some(self.client.model)` | 确认：内存 agent 有值，但磁盘恢复时可能丢失 |
| latest_latency_ms 字段名 | 读 `lib/web/types.mbt` 第 77 行 | `latest_latency_ms : Int?` | 确认：字段名为 latest_latency_ms |
| 前端期望 latest_latency | 文档引用 `web/sessions.js:3301` | 前端读 `s.latest_latency` | 确认：字段名不匹配 |
| 前端期望 ISO 8601 | 文档引用 `web/sessions.js:1663` | `new Date(created_at)` 按 ISO 解析 | 确认：前端期望 ISO 8601 |
| ToJson 实现 | `grep "impl ToJson.*SessionSummary" lib/web/types.mbt` | 需确认是否有自定义 to_json | 待验证 |

### 详细分析

**时间戳格式**：
- `current_timestamp_ms()` 返回 `current_time_ms().to_string()`，即 epoch 毫秒数字的字符串形式
- 前端 `new Date("13429275854279")` 将字符串参数当作日期文本解析（非数字），返回 Invalid Date
- 修复方向：改为 ISO 8601 格式（如 `"2026-07-24T16:30:00.000Z"`），或改为纯数字类型让 JS `new Date(number)` 正确解析

**model 字段**：
- `SessionSummary.model` 赋值为 `sd.model_name`（SessionData.model_name）
- 磁盘加载的会话：`model_name` 来自反序列化的 JSON，若会话文件中无此字段则为 None
- 内存中的会话：`to_session_data()` 设置 `model_name: Some(self.client.model)`，有值
- 问题出在磁盘会话恢复时 model_name 可能丢失，需确认持久化逻辑

**latest_latency_ms 字段名**：
- 后端字段名 `latest_latency_ms`，前端期望 `latest_latency`
- 简单的字段名对齐即可

## 决策 [必填 - 含为什么]

> 2026-07-24 对抗性审核修订：审核定位了四个真实根因，其中两个颠覆原方案（见审核验证记录）。

1. **先修 Windows epoch 根源（C FFI 少减 1601→1970 偏移）**：`lib/agent/time_stub.c:14-18` 的 Windows 分支 `GetSystemTimeAsFileTime/10000` 得到的是 **1601 纪元毫秒**，未减 `11644473600000` 偏移，导致 Windows 上所有 `current_time_ms()` 快 369 年（"13429275854279" = 2395 年）。同仓库 `lib/billing/time_stub.c:19` 已有正确写法（`t/10000 - 11644473600000LL`），照抄修正。Unix 分支（gettimeofday）正确不动。此修复同时纠正 session id（`s_<ts>`）、todo/memory 时间戳等所有调用点。

2. **时间戳改 ISO 8601（对齐 orig 的本地偏移格式）**：orig 格式为 `"2026-07-24T12:22:34+08:00"`。在 `time_stub.c` 新增两个 FFI：`mbopenclacky_iso8601_now()`（Windows: GetLocalTime + TIME_ZONE_INFORMATION 算偏移；Unix: localtime_r + strftime %z）与 `mbopenclacky_ms_to_iso8601_local(ms)`（用于旧数据转换）。`current_timestamp_ms()` 改返回 ISO 并更名 `current_timestamp_iso()`。**调用点逐个甄别，不盲目替换**：`agent.mbt:98`（created_at）、`session_manager.mbt:160`、`session_serializer.mbt`、`handlers_session_ext.mbt:26` 等展示/序列化用途改 ISO；`memory.mbt`、`todo.mbt`、`compressor_chunk.mbt` 若用于文件名/内部 id（ISO 含 `:` 是 Windows 文件名非法字符），改用 `current_time_ms()` 保持 epoch 数字。

3. **旧数据兼容转换（两种脏格式）**：`load_session` 反序列化 `created_at` 时：非纯数字 → 视为 ISO 原样保留；纯数字且 > 10^13（≈2286 年后的 Unix ms，只可能是 Windows-epoch 脏数据）→ 减 11644473600000 后转 ISO；其余纯数字 → Unix epoch ms 转 ISO。

4. **model 字段：修 Option 序列化往返断裂，而非展示层 fallback**（打回原决策 2）：根因是 `SessionData` 的 `ToJson` 把 `model_name: String?` 写成 `Array(["kimi-k2.7-code"])`（session_data.mbt:373 经 Option derive），而 `from_json:447` 只认 `String` → 重载后恒为 None → API `model: null`。修复：`from_json` 兼容 `String` 与 `[String]` 两种格式；`ToJson` 改为输出纯 `String`/`null`（新文件干净）。原方案的"fallback 到 config 默认模型"降级为最后兜底（仅用于真正缺失 model_name 的历史文件），不作为主修复。

5. **latest_latency 是形状问题，不是改名**（打回原决策 3）：前端 `_renderSignal` 期望对象 `{ttft_ms, duration_ms, output_tokens, tps, ...}`（sessions.js:3320 文档），且以 `lat.ttft_ms` 为显隐条件。`SessionSummary.latest_latency_ms: Int?` 改为 `latest_latency`（JSON 对象），由 `SessionData.latest_ttft_ms` + `latest_latency_ms`(duration) 构造 `{ttft_ms, duration_ms}`；两者皆 None 时输出 null（前端隐藏信号，正确行为）。自定义 ToJson（types.mbt:193）同步改键名。

6. **updated_at 保持 = created_at**：前端 `_relativeTime(s.updated_at || s.created_at)` 已有兜底，不引入文件 mtime 等额外机制（避免过度设计），TODO 注释保留。POST /api/sessions 响应补 `updated_at` 字段（= created_at）。

### 审核验证记录（2026-07-24 对抗性审核补充）

| 声称/方案 | 验证 | 结果 |
|------|------|------|
| spec 10 项声称（时间戳/model/字段名等） | 读 session_data.mbt、types.mbt:60-230、handlers_ws.mbt | 确认属实 |
| epoch 数值本身异常（1.34e13 = 2395 年） | 读 lib/agent/time_stub.c:14-18 vs lib/billing/time_stub.c:19 | **根因确认**：Windows 分支未减 1601→1970 偏移，billing 副本写法正确可照抄 |
| "model fallback 到默认模型"（原决策 2） | 磁盘文件实证：`model_name: Array([String(kimi-k2.7-code)])`；from_json:447 只认 String | **打回**：根因是 Option 序列化往返断裂，fallback 会把会话标错模型 |
| "latest_latency 简单改名即可"（原决策 3） | 读 sessions.js:3320-3360 `_renderSignal` | **打回**：前端期望对象 `{ttft_ms,...}` 且以 ttft_ms 为显隐条件，是形状问题 |
| SessionSummary ToJson 自定义 | types.mbt:193-230 | 确认自定义 impl，Option 输出 String/null，键名需手改 |
| 前端 updated_at 用法 | sessions.js:2141 `updated_at \|\| created_at` | 有兜底，保持 created_at 即可 |
| ISO 含 `:` 影响文件名用途调用点 | grep 全部 11 个 current_timestamp_ms 调用点 | 确认需逐个甄别（memory/todo/compressor 可能用于文件名） |
| orig 时间戳格式 | orig /api/sessions 响应 `"2026-07-24T12:22:34+08:00"` | ISO 8601 本地偏移，前端 new Date 可解析 |

<!-- MoonBit 约束检查：
- AOT 约束：不涉及
- crescent 路由：不涉及
- FFI：修改 lib/agent/time_stub.c（修偏移 + 新增 2 个 ISO 函数），time.mbt 增加 extern 声明；lib/agent/moon.pkg 的 native-stub 已含 time_stub.c（需确认），无新增 C 文件
- mooncakes 依赖：无新增
- 测试：native-only
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/time_stub.c` | 修改 | Windows 分支减 11644473600000 偏移（照抄 lib/billing/time_stub.c:19）；新增 `mbopenclacky_iso8601_now()`、`mbopenclacky_ms_to_iso8601_local(ms)` 两个函数 |
| `lib/agent/time.mbt` | 修改 | 新增两个 extern 声明（`#cfg(target="native")`）；非 native 平台 stub 返回 UTC 固定串或空 |
| `lib/agent/session_data.mbt` | 修改 | `current_timestamp_ms()` → `current_timestamp_iso()`（返回 ISO 8601 本地偏移）；`load_session`/`from_json` 的 created_at 兼容转换（两种 epoch 脏格式 → ISO）；`model_name` from_json 兼容 String\|[String]、ToJson 改纯 String |
| `lib/agent/agent.mbt`、`session_manager.mbt`、`session_serializer.mbt`、`memory.mbt`、`todo.mbt`、`compressor_chunk.mbt` | 修改 | current_timestamp 调用点逐个甄别：展示/序列化用 ISO；文件名/id 用途改 `current_time_ms()` |
| `lib/web/types.mbt` | 修改 | `SessionSummary.latest_latency_ms: Int?` → `latest_latency`（对象或 null）；自定义 ToJson 改键名与形状 |
| `lib/web/handlers.mbt` | 修改 | `handle_list_sessions`：latest_latency 对象构造 + model 兜底（仅历史缺字段文件）；POST 响应补 `updated_at` |
| `lib/web/handlers_ws.mbt` | 修改 | `send_session_list` 同步上述构造逻辑（提取公共函数） |
| `lib/web/handlers_session_ext.mbt` | 修改 | exported_at 调用点改 ISO |
| 相关 `*_wbtest.mbt` | 修改 | epoch→ISO 转换、model_name 双格式解析、latency 对象构造的单测 |

### 不涉及文件

- 前端 JS（零修改，前端逻辑正确，是后端数据格式问题）
- WS 协议事件类型（仅 session 摘要形状对齐前端既有期望）
- `lib/billing/`（其 time_stub.c 写法正确，作为修复参照）
- `lib/agent/session_store.mbt` 的目录遍历逻辑（仅 from_json 内字段解析变化）

## 实施计划 [必填]

### 任务包 1：Windows epoch 根源 + ISO FFI（0.5 天）
- `time_stub.c`：修偏移；新增 `mbopenclacky_iso8601_now()` 与 `mbopenclacky_ms_to_iso8601_local(ms)`（本地时区偏移格式，对齐 orig `"2026-07-24T12:22:34+08:00"`）
- `time.mbt`：extern 声明 + `pub fn current_iso8601() -> String`、`pub fn ms_to_iso8601(Int64) -> String`
- 单测：Windows 上 `current_time_ms()` 与 Unix 一致（1.7e12 量级，1970 纪元）

### 任务包 2：时间戳 ISO 化 + 旧数据兼容（0.5 天）
- `current_timestamp_ms()` → `current_timestamp_iso()`；11 个调用点逐个甄别替换
- `from_json` created_at 兼容转换（ISO 原样 / >1e13 Windows-epoch / 其余 Unix epoch → ISO）
- 单测：三种输入格式的转换结果

### 任务包 3：model_name 序列化往返修复（0.5 天）
- `from_json` 兼容 `String` 与 `[String]`；`ToJson` 改输出纯 `String`/`null`
- 检查 SessionData 其他 `String?` 字段是否有同样断裂（sub_model、reasoning_effort、last_error 等逐一核对 from_json 匹配分支）
- 单测：两种格式文件加载后 model_name 均为 Some

### 任务包 4：latest_latency 对象 + model 兜底（0.5 天）
- `SessionSummary.latest_latency_ms: Int?` → `latest_latency`（`{ttft_ms, duration_ms}` 或 null）
- 构造逻辑提取公共函数（handlers.mbt 与 handlers_ws.mbt 共用）；model 兜底仅对 None 的历史数据
- POST /api/sessions 响应补 `updated_at`
- moon check / moon test lib/agent lib/web / release build / UI 复测

## 验收标准 [必填]

- [x] Windows 上 `created_at` / `updated_at` 为正确 ISO 8601（2026 年，非 2395 年），前端 `new Date()` 正确解析
- [x] 侧边栏会话时间显示正常（非 "NaN/NaN NaN:NaN"），旧脏数据（两种 epoch 格式）加载后同样正常（Playwright 实测显示 "Yesterday 18:24"，`fix03-ui-verify.json`）
- [x] `GET /api/sessions` 与 WS `session_list` 列表项 `model` 为纯字符串非 null（新会话），历史会话经兜底/双格式解析非 null（E2E：脏数据会话 model 恢复为 `kimi-k2.7-code`）
- [x] 模型切换器可见且显示正确模型名（截图 `fix03-ui-verify.png`：信息栏显示 kimi-k2.7-code，下拉可点开）
- [x] 会话文件重存后 `model_name` 为纯字符串（不再是数组，E2E step2 验证）
- [x] 有 ttft 数据的会话 `latest_latency` 为对象且前端延迟信号显示；无数据时为 null 且信号隐藏（E2E 实测 null 分支；对象形状由单测三种情形覆盖）
- [x] `moon check` 0 errors（lib/web, lib/agent）
- [x] `moon test lib/web lib/agent` 通过（540/540，主 agent 独立复验一致）
- [x] `moon build --target native --release cmd` 通过（C 改动无新警告）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 旧会话文件两种 epoch 脏格式误判 | 中 | 阈值 >1e13 判定 Windows-epoch（Unix ms 到 2286 年才达 1e13，安全边界大）；单测覆盖三种格式 |
| Option 序列化格式变更影响其他 String? 字段 | 中 | 任务包 3 逐一核对 SessionData 全部 Option 字段的 from_json；全部加双格式兼容 |
| ISO 字符串含 `:` 被用于文件名 | 中 | 调用点逐个甄别，文件名用途改 current_time_ms()；grep 验证无遗漏 |
| C 时区偏移计算错误（夏令时等） | 低 | Windows 用 TIME_ZONE_INFORMATION（含 DST 修正），Unix 用 strftime %z（系统处理） |
| 修改 time_stub.c 影响 billing | 低 | billing 有自己独立的 time_stub.c，互不影响 |

## 依赖关系 [必填]

- **前置依赖**: 无（独立可实施；I-002 已完成，新会话创建即持久化，本修复效果立即可见）
- **后置依赖**: 无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | I-011 + I-012 + I-030 P1 序列化格式对齐 |
| 2026-07-24 | 对抗性审核修订：定位 4 个真实根因——(1) Windows C FFI 未减 1601→1970 偏移（epoch 本身错 369 年，billing 副本有正确写法）；(2) model null 根因是 Option 序列化往返断裂（写 Array 读只认 String），打回"默认模型 fallback"为主方案（降级为兜底）；(3) latest_latency 是对象形状问题而非改名，打回原决策 3；(4) current_timestamp_ms 的 11 个调用点需逐个甄别（ISO 的 `:` 是 Windows 文件名非法字符）。补充 8 项审核验证记录 | 审核证伪 2 项原决策、发现 1 个更深层根因 |
| 2026-07-24 | 开发完成，验收通过。改动：`lib/agent/time_stub.c`（重写，修 1601 偏移 + 2 个 ISO FFI）、`time.mbt`、`session_data.mbt`（current_timestamp_iso + normalize_created_at + opt_string_field/opt_string_json，受损 Option 字段为 model_name/reasoning_effort/sub_model 三个）、`lib/web/types.mbt`（SessionLatency）、`handlers.mbt`、`handlers_ws.mbt`、相关 wbtest（+7 测试）。11 个调用点全部判为 ISO（无一用于文件名；唯一文件名场景在测试代码，已改 current_time_ms）。验证：moon test 540/540（双重复验）；E2E 全过（fix03-e2e.json，用户真实脏数据会话转换成功）；Playwright UI 实测侧边栏时间正常、模型切换器可见（fix03-ui-verify.json/png）。偏差：memory/todo 历史条目的 epoch 串不转换（spec 范围只含 SessionData.created_at）；E2E 实测 latest_latency 为 null 分支（对象形状由单测覆盖） | 实现与验证完成，归档 |
