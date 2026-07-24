# 会话摘要字段补全（I-030 残留）· 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 讨论中  
> **关联总览**: `docs/web-ui-issues.md`  
> **关联历史 spec**: `specs/completed/2026-07-24_web-ui-fix-03-session-serialization.md`（I-030 已修部分：latest_latency 对象化）  
> **来源差距**: I-030 残留 - 会话摘要缺 error_code/top_up_url/raw_message/model_id/card_model/channel_info（P2）  
> **依赖**: fix-06（前端验收环境）

## 问题描述 [必填]

fix-03 已把 `latest_latency` 修为对象 `{ttft_ms, duration_ms}`，但 I-030 的其余六个字段仍未输出：`error_code` / `top_up_url` / `raw_message` / `model_id` / `card_model` / `channel_info`。前端 `web/sessions.js:3301` 附近按这些字段渲染错误信号（如余额不足的 top-up 引导），当前永不显示。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "SessionSummary 缺六字段" | `Read lib/web/types.mbt:84-104` | 结构体含 id/name/.../latest_latency/pinned/agent_profile/sub_model/sub_model_options/reasoning_effort，无 error_code/top_up_url/raw_message/model_id/card_model/channel_info | 确认 |
| "channel_info 数据已存在" | `Grep "channel_info" lib/agent/session_data.mbt` | `SessionData.channel_info : ChannelInfo?`（:185）且 to_json/from_json 均已处理（:386-387, :446-448） | 确认数据源就绪，仅摘要层未透传 |
| "error 文本已存在" | `Grep "last_error" lib/agent/session_data.mbt` | `SessionData.last_error : String`（:192） | 确认 error 字符串有源 |
| "orig 字段语义" | `Grep "top_up_url|error_code|card_model" D:/MoonBit/openclacky/lib/clacky` | `client.rb:611-667` 从错误体提取 error_code（如 insufficient_credit）、top_up_url；`json_ui_controller.rb:104-107` show_error 携带三字段；`agent.rb:252` card_model 取自 base_entry["model"] | 确认 orig 语义：error_code/top_up_url/raw_message 来自 LLM 错误提取，card_model 是卡片展示的模型名 |
| "model_id 当前状态" | fix-03 已修 `model_name` 序列化；`SessionSummary.model : String?` 存在 | `model` 已有，`model_id`/`card_model` 是额外别名/派生字段 | 需按 orig 摘要形状确定三字段各自取值 |

### 详细分析

六个字段分两类：

- **可直接透传**：`channel_info`（SessionData 已有）、`model_id`（可取 model_name）、`card_model`（orig 语义为卡片模型名，需读 orig session 摘要构建代码确认与 model 的差异）。
- **需新增提取链路**：`error_code`/`top_up_url`/`raw_message` 来自 LLM 错误响应提取（orig `client.rb` 的 `extract_error_code`）。当前项目需查 `lib/client/` 错误处理是否已提取 error_code；若未提取，scope 上限为"在错误对象中新增 error_code/top_up_url 提取并沉淀到 SessionData"，不做 UI 层扩展。

## 决策 [必填 - 含为什么]

1. **在 `SessionSummary` 增加六字段而不是另建类型**：前端按摘要条目平铺读取，另建类型会导致列表/详情两处不同步；fix-03 已在此结构上演进，延续之。
2. **error 三字段（error_code/top_up_url/raw_message）按"有则输出、无则省略/null"处理**：仅当 session 处于错误状态且有提取结果时出现，避免给正常会话摘要注水。
3. **先验证 `lib/client/` 是否已有错误码提取**，没有再决定是否在 client 层补提取：若补提取超出"摘要字段"范畴，允许把 error 三字段拆为本 spec 的任务包 2，channel_info/model_id/card_model 作为任务包 1 先行交付。
4. **MoonBit 约束检查**：结构体字段扩展 + derive/手写 ToJson 调整，无动态 trait/crescent/FFI 问题；注意 SessionSummary 为 `pub(all)`，`moon info` 需更新 `.mbti`。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/types.mbt` | 修改 | SessionSummary 增加六字段及 ToJson |
| `lib/web/handlers.mbt`、`lib/web/handlers_ws.mbt`（send_session_list） | 修改 | 摘要构建点填充新字段（审核修正：原写 handlers_session_ext.mbt 有误，实际构建点在 handlers.mbt:53 与 handlers_ws.mbt:240） |
| `lib/agent/session_data.mbt` | 可能修改 | 若 error 三字段需沉淀到 SessionData |
| `lib/client/`（错误处理） | 可能修改 | 若无 error_code/top_up_url 提取则补（任务包 2） |
| `lib/web/pkg.generated.mbti` | 修改 | `moon info` 更新 |

### 不涉及文件

- `latest_latency` 已实现部分（fix-03 已完成，不重做）。
- 前端 `web/**`。
- WS 帧序问题（fix-07/fix-08 范围）。

## 实施计划 [必填]

### 任务包 1：透传字段（预估 0.5 天）
- SessionSummary 增加 channel_info/model_id/card_model；读 orig 摘要构建代码确认 card_model 与 model 的取值差异。
- 两个构建点填充；白盒测试。

### 任务包 2：错误字段链路（预估 1 天）
- 验证 `lib/client/` 错误提取现状；缺则参照 orig `extract_error_code` 补 error_code/top_up_url 提取。
- 沉淀到 SessionData（last_error 旁边新增字段），摘要层输出 error_code/top_up_url/raw_message。
- 白盒测试 + 构造错误会话的端到端验证。

## 验收标准 [必填]

- [ ] GET /api/sessions 与 WS session_list 摘要条目含六字段（正常会话 error 三字段可为 null/省略）
- [ ] 构造 LLM 错误（如 402/insufficient_credit 模拟）后摘要含 error_code/top_up_url/raw_message
- [ ] 前端错误信号（延迟指示、top-up 引导）在 Playwright 走查中可见
- [ ] `moon check` 0 errors（lib/web、lib/agent）；`moon test lib/web lib/agent` 通过；`moon info` 无 diff 残留

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| error 提取链路改动扩到 lib/client 公共错误路径 | 中 | 拆任务包 2 独立交付；提取失败时三字段缺省不阻断 |
| card_model 与 model 语义在原项目中也含混 | 低 | 以 orig 摘要构建代码为准逐字段抄语义；差异写进验证记录 |
| 历史会话文件缺新字段 | 低 | from_json 缺省 None/空串兜底（fix-03 已有先例） |

## 依赖关系 [必填]

- **前置依赖**：fix-06（前端验收环境）；fix-03 已完成（本 spec 在其基础上增量）。
- **后置依赖**：无。

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | I-030 残留六字段起草 |
| 2026-07-24 | 审核修正：发现 1 个文件名错误并修正。改动范围原写 handlers_session_ext.mbt，实际 SessionSummary 构建点在 handlers.mbt:53（REST）与 handlers_ws.mbt:240（WS send_session_list）。其余验证通过：SessionSummary@types.mbt:84 缺六字段确认；channel_info@session_data.mbt:185 + to_json@:386-387 + from_json@:446-448 确认；last_error@:192 确认；lib/client/ 无 error_code/top_up_url 提取确认（0 命中，任务包 2 需求成立）。无 AOT/crescent/FFI 约束。 | 对抗性审核 + 第一性原理校验 |
