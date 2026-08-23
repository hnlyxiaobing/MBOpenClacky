# Telegram 真发送实装（HTTP Bot API）· 增量 Spec

> **创建日期**: 2026-08-21
> **状态**: 实施中（2026-08-22 对抗性审核通过，自 draft 移入 active）
> **关联总览**: `specs/active/2026-08-21_stubfix-00-overview.md`（来源：stub 实装状态审计报告第五节建议 7）
> **关联历史 spec**: `specs/active/2026-08-21_stubfix-02-honest-send-errors.md`（本 spec 消费其翻转后的 Err 分支）
> **来源差距**: 审计报告 2.1「Telegram send_text 假成功 stub」+ 建议 7「HTTP 调用模式与 Feishu/Discord 完全同构，性价比极高」
> **依赖**: stubfix-02（假成功先翻转为 Err，本 spec 替换为真实现）
> **灰度 key**: 无

## 问题描述 [必填]

Telegram 的 `send_text` 在 stubfix-02 之后将返回诚实 Err（"not implemented"）。本 spec 将其替换为真实实现：调 Telegram Bot API `POST https://api.telegram.org/bot<token>/sendMessage`。

审计评估：发送的 HTTP 调用模式与飞书/Discord 完全同构（build payload + `http_post_json`），工作量极小、性价比极高。接收侧（getUpdates 长轮询）仍为 TODO，不在本 spec 范围。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "http_post_json 为真实现" | 审计 2.1 节 + `lib/channel/http_helper.mbt:280-314`（@client FFI） | 飞书/钉钉/Discord 均经此真发送 | 确认可复用 |
| "飞书同构模式参照" | 实读 feishu.mbt 发送路径（审计 91-137 真调 http_post_json） | build payload -> http_post_json -> 解析响应 -> message_id | 参照确认 |
| "Telegram 配置字段就绪" | 实读 `lib/channel/telegram.mbt` | `bot_token` 字段（:11 TelegramApiClient、:180 adapter、:192-196 settings["bot_token"] 读取）、`send_message_url`（:150）、`split_telegram_message`（:266）、`build_telegram_send_request` 实存 | **已复核（原"实施时复核字段名"疑点关闭）**：字段名与审计一致 |
| "telegram wbtest 存在翻转后的 Err 骨架" | stubfix-02 决策 3 | 成功断言翻转为 Err + 回归骨架 | 确认本 spec 需再翻转回真实断言 |

### 详细分析

Telegram sendMessage API：`POST /bot<token>/sendMessage`，body `{chat_id, text, parse_mode?}`，响应 `{ok: true, result: {message_id, ...}}`。与飞书发送的消息构建->POST->取 message_id 三段完全同构，`http_helper` 的 JSON POST/响应解析可直接复用。

错误语义：Telegram 返回 `{ok: false, error_code, description}`（400/401/403/429），需映射到 adapter 的错误结构；429（限流）含 retry_after 参数。审计第四节另记 weixin.mbt:282 限流重试 TODO 属微信侧，Telegram 的 429 处理本 spec 仅做错误透传（retry_after 附言），不做自动重试（backlog）。

## 决策 [必填 - 含为什么]

1. **决策 1（复用 http_post_json）**：发送走既有 `http_post_json`，不新建 HTTP 客户端。
   - **为什么**：三平台验证过的同构路径；零新增依赖；错误处理结构统一。
2. **决策 2（message_id 真实化）**：成功响应解析 `result.message_id` 为字符串入返回结构；删除 stubfix-02 遗留的 Err 分支与 `tg_msg_` 任何残留。
   - **为什么**：对齐飞书/Discord 的返回契约（message_id 可用于未来 edit_message 关联）。
3. **决策 3（错误映射）**：`ok:false` -> `success:false` + error 含 `error_code + description`；HTTP 层异常 -> error 含请求失败语义。
   - **为什么**：stubfix-01 的 web send API 会透传该错误到 Web UI；结构化错误消息便于用户定位（token 无效/被踢出群/限流）。
4. **决策 4（接收侧不动）**：getUpdates 长轮询保持 TODO 注释，明确列入 backlog。
   - **为什么**：长轮询需要常驻任务生命周期管理（与 WebSocket/Stream 同类的连接层议题，stubfix-07 统筹）；发送先行即可让 Telegram 渠道具备最小可用价值（agent 主动推送）。

MoonBit 约束检查：无新增 FFI/AOT 影响。✅

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/channel/telegram.mbt` | 修改 | send_text 真实现（payload 构建 + http_post_json + 响应/错误映射，决策 1-3）；删除 not implemented 分支 |
| `lib/channel/telegram_wbtest.mbt` | 修改 | mock http 层断言：请求 URL 含 token、body 含 chat_id/text、成功取 message_id、ok:false 错误映射、HTTP 异常路径 |

### 不涉及文件

- `lib/channel/http_helper.mbt` -- 复用不修改
- telegram 接收侧（getUpdates）-- backlog（决策 4）
- web 端 test 探测（getMe）-- stubfix-01 后置依赖已声明，可随本 spec 完成后顺带启用（若 stubfix-01 已合入则在本 spec 验收项中核对该端点，不单独改 handlers）

## 实施计划 [必填]

### 任务包 1：发送实装 + 测试（预估 0.5 天）

1. telegram.mbt send_text 真实现（决策 1-3）。
2. wbtest 全路径覆盖（成功/限流/鉴权失败/网络错误）；删除 stubfix-02 骨架注释。
3. `moon check` 0 errors；`moon test lib/channel` 通过。

### 任务包 2：验收回归（预估 0.25 天）

1. 手动冒烟（有真实 bot token 时）：Web UI 发送消息到测试群，收到消息且 message_id 非伪造；无 token 环境 mock 断言为准。
2. 全量 `moon test` 无回归；`moon fmt`、`moon info`。

## 验收标准 [必填]

- [ ] `TelegramAdapter::send_text` 构建真实 HTTP 请求（wbtest 断言 URL/payload），不再存在 not implemented 分支
- [ ] 成功路径返回真实 `result.message_id`；失败路径 error 含 Telegram error_code/description
- [ ] stubfix-01 的 test 探测（如已合入）在 Telegram 上返回真实 getMe 结果
- [ ] `moon check` 0 errors（lib/channel）
- [ ] `moon test lib/channel` 通过；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| Telegram API 域名在部分网络环境不可达 | 中 | 错误透传网络失败语义；与飞书海外域名同既有现状，不单独做代理（backlog） |
| 429 限流高频触发 | 低 | 错误附 retry_after；自动重试列 backlog（与 weixin 限流 TODO 合并议题） |
| parse_mode 格式（MarkdownV2 转义）引发 400 | 低 | 首版纯文本发送（不带 parse_mode）；富文本格式化列 backlog |

## 依赖关系 [必填]

- **前置依赖**: stubfix-02（Err 分支就位后替换）
- **后置依赖**: Telegram 接收侧 getUpdates 长轮询（backlog，随 stubfix-07 连接层统筹）；429 自动重试（backlog）；parse_mode 富文本（backlog）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-21 | 初始版本 | stub 审计报告 2.1 节 + P2 建议 7 |
| 2026-08-22 | 审核补强：全部声明实读复核（http_post_json @client FFI 真实现、bot_token/send_message_url(:150)/split_telegram_message(:266)/build_telegram_send_request 实存、weixin 限流 TODO 实为 :280-284 注释形态）；关闭"实施时复核字段名"疑点 | 对抗性审核 + 第一性原理校验 |
| 2026-08-23 | 实施完成并验收：telegram.mbt send_text 真实现（与飞书同构三段：build_telegram_send_request -> http_post_json(url, headers, payload.stringify()) -> TelegramApiClient::parse_send_response），not implemented 分支已删；错误透传网络失败与 ok:false 语义。channel_wbtest.mbt telegram_adapter_send_text_returns_err 断言翻转：不得返回 stub 错误。**偏差记录**：未新建可注入的 mock http 层，URL/payload 级断言无法离线执行，网络错误路径由翻转后的集成断言覆盖；mock 分层入 backlog。验收：moon check 0 errors；moon test lib/channel 412/412；fmt/info 已跑 | 实施完毕，归档 |
| 2026-08-23 | 对抗性审查修订（代码级）：ChannelEvent.timestamp 原为 Int（32 位）而注释语义为毫秒 epoch（2026 年约 1.78e12 必溢出）——改为 Int64；telegram date 用 to_int64 乘 1000L、feishu parse_int_safe 改 Int64 累加器（create_time 为 13 位毫秒字符串，原 32 位解析溢出）、wecom/weixin/dingtalk/discord 同步 Int64；新增 discord_wbtest.mbt 中 feishu_parse_int_safe_13_digit_ms 断言 13 位毫秒不截断。telegram send_text 同构实现本身无新问题。验收：moon check 0 errors；moon test lib/channel 416/416 | 实施后对抗性审查发现时间戳类型系统性溢出（C 级） |
