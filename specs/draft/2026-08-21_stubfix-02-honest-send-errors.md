# 渠道假成功 stub 改诚实报错（Telegram/WeCom/Weixin）· 增量 Spec

> **创建日期**: 2026-08-21
> **状态**: 讨论中
> **关联总览**: `specs/draft/2026-08-21_stubfix-00-overview.md`（来源：stub 审装状态审计报告 2.1 节风险提示 + 第五节建议 2）
> **关联历史 spec**: 无
> **来源差距**: 审计报告 2.1「Telegram/WeCom/Weixin send_text 假成功 stub -- 静默丢消息」
> **依赖**: 无（建议与 stubfix-01 同批次合入）
> **灰度 key**: 无

## 问题描述 [必填]

三个平台的 `send_text` 返回 `success: true` 但实际什么都没发生，属**静默丢消息**（数据完整性事故级别）：

1. **Telegram**：返回伪造 message_id `"tg_msg_" + chat_id`（telegram.mbt:261-284），无任何 HTTP 调用。
2. **WeCom**：构建 WebSocket 帧后不发送，`wecom.mbt:142-144` TODO 后直接返回成功；接收侧 `start` 仅 `mark_connected()` 设标志位（假连接）。
3. **Weixin**：消息入队后从不发送，返回 `"weixin_msg_pending"` + `success: true`（weixin.mbt:206-280）。

对比：飞书 API 层高层 `send_message` 是诚实报错型（返回 Err），审计明确指出诚实报错远比假成功安全。真正实装前，假成功必须先改为 `Err("not implemented")`，让调用方（stubfix-01 接线后的 web send API、未来的 agent 出站链路）能感知失败。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "Telegram 伪造 message_id" | `grep -n "tg_msg_" lib/channel/telegram.mbt` | telegram.mbt:286 `message_id: "tg_msg_" + chat_id`（审计行号 261-284 区间内，实读确认） | 确认假成功 |
| "Weixin 假 pending" | `grep -n "weixin_msg_pending" lib/channel/weixin.mbt` | weixin.mbt:285 `Ok({ message_id: "weixin_msg_pending", success: true, ... })` | 确认假成功 |
| "WeCom 构帧不发" | `grep -n "TODO.*send\|mark_connected" lib/channel/wecom.mbt` | wecom.mbt:104 `mark_connected()` 假连接；审计引用的 121-148 构帧丢弃路径属实 | 确认假成功 |
| "返回类型可表达失败" | 审计 2.1 表格 + adapter trait 签名 | send_text 返回 `Result`/含 success/error 字段的结构，Err 通道可用 | 确认改动纯逻辑层，无需改类型 |
| "飞书是诚实报错参照" | 审计 2.1 节 feishu_api.mbt:171-190 | 高层 send_message 返回 Err | 参照确认 |

### 详细分析

三个 adapter 的 `send_text` 均构造了与真实现相同的成功返回体（message_id/success=true/error=None），调用方无法区分真假。审计报告在 2.1 节将此列为比 stub 本身更严重的风险："这比诚实报错危险得多"。

假成功的存在使 stubfix-01 的接线（web send API 真调 adapter）失去意义--用户在 Web UI 点击发送显示成功，消息实际丢失。因此本 spec 是 stubfix-01 的语义前置（技术上无编译依赖，行为上必须先行或同批）。

注意范围区分：本 spec 只改**假成功 -> 诚实报错**；把三个平台的发送真正实装分别是 stubfix-06（Telegram，P2）与后续 WeCom/Weixin 实装 spec（依赖 WebSocket/长轮询基础设施，backlog）。其余诚实报错型 stub（飞书 multipart 上传、Discord edit_message 等审计 2.1 列表）不在本 spec 重复处置--它们已返回 Err，无数据完整性风险，实装优先级由总览 backlog 排序。

## 决策 [必填 - 含为什么]

1. **决策 1（错误语义）**：三平台 `send_text` 统一返回 `Err("Telegram/WeCom/Weixin send is not implemented yet")`（或对应结构 `success:false, error:Some(...)`），删除伪造 message_id 与 pending 占位。
   - **为什么**：诚实报错是 stub 期唯一安全形态（审计 P0 原则）；错误消息含平台名，便于调用方与用户定位。
2. **决策 2（接收侧同步降级）**：`start` 不再置连接标志/假 enqueued 状态，直接返回 Err("receive not implemented") 或保持"未启动"状态语义；`stop` 幂等无害化。
   - **为什么**：mark_connected/入队等假状态会让 status/validate 误报可用；假状态与假成功同源，一并清除。
3. **决策 3（wbtest 期望翻转）**：既有断言"发送成功"的 wbtest 用例改为断言 Err；保留三平台真实现实装后的回归骨架（标注 TODO-stubfix-06/backlog 引用）。
   - **为什么**：测试与新语义一致；翻转后测试即闸门，防止未来回归到假成功。
4. **决策 4（不做部分实装）**：不在本 spec 顺手实现 Telegram HTTP 发送（虽然审计评估"半小时工作量"）。
   - **为什么**：spec 单一职责（行为修正 vs 功能新增）；stubfix-06 独立承载，其验收含真实 HTTP mock 链路，与本 spec 的纯行为翻转混在一起会使审查焦点失焦。

MoonBit 约束检查：不涉及 FFI/AOT/trait 动态加载；改动为纯逻辑分支。✅

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/channel/telegram.mbt` | 修改 | send_text 假成功体 -> Err；getUpdates TODO 注释保留（实装属 backlog） |
| `lib/channel/wecom.mbt` | 修改 | send_text 构帧丢弃路径 -> Err；start 的 mark_connected 假连接 -> 未启动语义（决策 2） |
| `lib/channel/weixin.mbt` | 修改 | send_text 假 pending -> Err；入队死逻辑清除；AES TODO 保留注释 |
| `lib/channel/telegram_wbtest.mbt` / `channel_wbtest.mbt`（相关用例） | 修改 | 成功断言 -> Err 断言（决策 3） |

### 不涉及文件

- `lib/channel/wecom_ws.mbt` -- 协议层（帧构建/ACK 匹配）是 stubfix-07 WebSocket 实装的复用资产，保留
- `lib/channel/feishu.mbt`、`dingtalk.mbt`、`discord_api.mbt` -- 真发送平台不碰；其诚实报错型 stub（update_message/edit_message 等）由 backlog 排序
- `lib/channel/weixin_api.mbt` 的 AES stub -- 已是 TODO 注释形态，实装属 backlog
- web 端 handler -- stubfix-01 负责 send API 的错误透传展示

## 实施计划 [必填]

### 任务包 1：三平台行为翻转 + 测试（预估 0.5 天）

1. telegram.mbt / wecom.mbt / weixin.mbt 的 send_text、start 假状态路径改 Err（决策 1/2）。
2. 对应 wbtest 断言翻转；新增"假成功零回归"闸门用例（断言任何 send 路径不返回 success:true）。
3. `moon check` 0 errors；`moon test lib/channel` 全绿。

### 任务包 2：全量回归（预估 0.25 天）

1. 全量 `moon test` 无回归（重点：channel 相关 P2 差分用例是否依赖旧假成功行为，如有则按决策 3 翻转期望并在 known_failure 登记说明）。
2. `moon fmt`、`moon info`。

## 验收标准 [必填]

- [ ] `TelegramAdapter::send_text` / `WeComAdapter::send_text` / `WeixinAdapter::send_text` 均返回失败（Err 或 success:false + error 含 "not implemented"）
- [ ] 全仓库 grep 不再存在 `tg_msg_`、`weixin_msg_pending` 伪造标识
- [ ] WeCom `start` 不再产生假连接状态（status/validate 不误报可用）
- [ ] 相关 wbtest 断言翻转并通过；新增假成功闸门用例
- [ ] `moon check` 0 errors（lib/channel）
- [ ] `moon test lib/channel` 通过；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 既有 wbtest/差分用例依赖旧假成功行为 | 中 | 任务包 1 逐条翻转；diff-harness 侧期望与 Ruby 原版对齐裁决（Ruby 侧真实发送，MB 侧诚实 Err 在差分框架登记为已知差异） |
| web UI 用户突然看到三平台发送失败（此前"成功"） | 低 | 这是预期行为修正；UI 错误信息含 "not implemented" 自解释；发布说明注明 |
| 未来实装时 Err 分支被误保留 | 低 | 决策 3 的回归骨架标注 stubfix-06/backlog 引用，实装 spec 验收含"删除 not implemented 分支" |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：stubfix-01（send API 接线后错误可透传到 Web UI，两 spec 同批次合入效果最佳）；stubfix-06（Telegram 实装后删除对应 Err 分支）；WeCom/Weixin 实装 spec（backlog）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-21 | 初始版本 | stub 审计报告 2.1 节风险提示 + P0 建议 2 |
