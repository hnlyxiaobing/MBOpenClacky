# WebSocket 客户端基础设施 + Discord 网关连接层 · 增量 Spec

> **创建日期**: 2026-08-21
> **状态**: 实施中（2026-08-22 对抗性审核通过，自 draft 移入 active）
> **关联总览**: `specs/active/2026-08-21_stubfix-00-overview.md`（来源：stub 实装状态审计报告 2.2/3.6 节 + 第五节建议 6）
> **关联历史 spec**: 无
> **来源差距**: 审计报告 2.2「Discord 网关连接层完全未实装」+ 3.6「WeCom WebSocket 协议层完整但无连接」+ 建议 6「WS 客户端 FFI 三平台（Discord/钉钉 Stream/WeCom）共用」
> **依赖**: 无硬依赖（建议在 stubfix-01 之后实施，渠道接线完成后连接层才有生产入口）
> **灰度 key**: 无

## 问题描述 [必填]

三个平台的接收侧共用同一缺失能力：**WebSocket 客户端连接**。

1. **Discord 网关**（lib/channel/discord.mbt + discord_gateway.mbt）：协议层完成度很高（全部 10 个 opcode、心跳/Identify/Resume payload 构建、Hello/READY/InvalidSession 解析、心跳抖动、指数退避、致命关闭码判定），但连接层全 TODO--`DiscordAdapter::start` 只设标志位（discord.mbt:88-108），`handle_gateway_event` 中所有需要**发送**的动作（心跳响应、Identify、Resume、重连）全部 TODO（:376-414），心跳定时器不存在。**没有 WebSocket 客户端，Discord 机器人无法收到任何消息**。
2. **WeCom WebSocket**（lib/channel/wecom_ws.mbt，436 行）：协议层完整（帧类型、Subscribe/SendMsg/Ping/Pong/Ack、req_id 匹配、ACK 超时、分块上传），`mark_connected` 只是设标志位；发送侧构建帧后丢弃（wecom.mbt:142-144，stubfix-02 已改为诚实 Err）。
3. **钉钉 Stream Mode**（dingtalk.mbt:95 TODO）：WebSocket 连接未实装。

附加：discord.mbt:293 ISO 8601 时间戳解析缺失（MESSAGE_CREATE 恒返回 0），影响消息时间准确性（审计第四节同列 TokenCache 等时间戳问题，解法与 stubfix-04/05 共享时钟不同--此为字符串解析非时钟）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "Discord 协议层零 TODO、连接层 10 处 TODO" | `grep -c "TODO" lib/channel/discord.mbt lib/channel/discord_gateway.mbt` | discord.mbt: 10；discord_gateway.mbt: 0 | 确认：协议纯函数完成，连接/发送动作缺失 |
| "start 只设标志" | 审计 2.2 节 discord.mbt:88-108 | `TODO: Connect to Gateway WebSocket via @websocket` | 确认 |
| "事件发送动作全 TODO" | 审计 2.2 节 discord.mbt:376-414 | 心跳响应/Identify/Resume/重连 TODO | 确认 |
| "@websocket 引用存在" | discord.mbt TODO 注释提及 `@websocket` | 注释指向的包名在本仓库 moon.pkg 中未导入（属实）；**但 `.mooncakes/moonbitlang/async@0.21.0/src/websocket/` 已随既有依赖提供完整 WebSocket 子包** | **审核重大修正**：底层能力已存在，无需新增 |
| "@async.websocket 能力面" | 实读 `.mooncakes/moonbitlang/async/src/websocket/pkg.generated.mbti` + README + moon.pkg | `Conn::connect(url, headers?, proxy?)` async（含 wss -> https 映射，client.mbt:121）、send_text/send_binary/send_close/ping、recv() -> Message(Text/Binary)、CloseCode/WebSocketError 完整；RFC 6455 client & server；moon.pkg 直接 import `moonbitlang/async/tls`；js/wasm-gc 后端走 unimplemented.mbt 降级（native 无碍） | **确认路径 (c) 成立**：零新增依赖、TLS 内置 |
| "WeCom ws 协议层完整" | 审计 3.6 节 wecom_ws.mbt（实测 436 行，原记 441）+ `grep -n "mark_connected" lib/channel/wecom.mbt` | 帧构建/ACK 匹配/分块上传齐全；wecom.mbt:104 mark_connected 设标志 | 确认可复用资产 |
| "ISO 8601 解析缺失" | 审计 2.2 节 discord.mbt:293 | 恒返回 0 | 确认（本 spec 一并处置） |
| "进程/网络 FFI 先例" | browser_process（@process）+ http_helper（@client） | 管道与 HTTP FFI 模式存在；WebSocket 无需新 FFI（@async.websocket 随 async@0.21.0 已在依赖树内） | **审核修正**：原"确认需新增底层能力"结论过时 |

### 详细分析

**能力缺口是横切的**：Discord Gateway（wss://gateway.discord.gg）、钉钉 Stream Mode（wss 事件流）、WeCom 智能机器人 WebSocket 三者都只需要一个能力--带心跳保活的 WebSocket 客户端（连接、发送文本帧、接收帧回调、关闭/重连钩子）。审计建议 6 明确"建议一并规划"。

**实现路径选项（审核后已前置裁决）**：
- ~~(a) native-stub C FFI~~ / ~~(b) 纯 MoonBit over @client socket~~ / (c) 复用既有包 -- **裁决：路径 (c) 成立**。项目既有依赖 `moonbitlang/async@0.21.0` 自带 `websocket` 子包（RFC 6455 client & server、wss/TLS + proxy、native 目标支持；js/wasm-gc 走 unimplemented 降级，项目 native 无碍）。零新增依赖、零新 FFI。

本 spec 按能力分层组织：任务包 1 验证 @async.websocket 能力面并落地 WsClient 薄封装，任务包 2 起实施。协议层（Discord opcode/WeCom 帧）复用不动。

## 决策 [必填 - 含为什么]

1. **决策 1（能力优先、平台分层）**：本 spec 交付"WebSocket 客户端基础设施 + Discord 网关完整接线"；钉钉 Stream/WeCom 连接为后置依赖 spec（复用同一基础设施）。
   - **为什么**：三平台一次做完则单 spec 触及 5+ 文件且审查面过大（Harness 范围规则）；Discord 协议层完成度最高（零 TODO），是基础设施的理想首个消费者，能把"连接层补齐即机器人可用"验证到端到端。
2. **决策 2（基础设施形态，审核后更新）**：抽象为 `WsClient` 薄封装，底层直接采用 `@async.websocket`（`Conn::connect/send_text/recv/send_close/ping`）；`lib/channel/moon.pkg` 增加 `import "moonbitlang/async/websocket"`。
   - **为什么**：三平台需求收敛为同一接口；原"三路径裁决"已被依赖树现状前置回答（async@0.21.0 自带 websocket 子包，含 TLS/proxy）；薄封装保留 mock 点（wbtest 注入假 Conn 行为），消费者不直接依赖第三方 API 形状。
3. **决策 3（Discord 网关连接层）**：补齐 `DiscordAdapter::start`（连接 + 事件循环 spawn）、心跳定时器（按 HELLO 的 heartbeat_interval + 既有抖动函数）、Identify/Resume 发送、Reconnect/InvalidSession 重连、MESSAGE_CREATE 的 ISO 8601 解析；全部复用既有协议层函数。
   - **为什么**：协议层已就绪（验证记录第 1 条），连接层是纯接线 + 生命周期管理；ISO 8601 解析是同文件顺手项（独立小函数 + 单测）。
4. **决策 4（事件到生产链路）**：MESSAGE_CREATE 等事件经 `ChannelManager::on_message`（manager.mbt:119 已存在）进入消息处理链（stubfix-01 接线后可达 agent）。
   - **为什么**：避免连接层实装后事件仍止步于 adapter 内部（防"第二个孤儿层"）；on_message 签名已备。
5. **决策 5（重连与退避）**：断线按既有指数退避函数（5s 起、上限 60s）重连，致命关闭码（4004/4010-4014）不重连并暴露错误状态。
   - **为什么**：复用协议层已实现的判定（审计 2.2 确认齐全）；避免 token 失效场景下的重连风暴。

MoonBit 约束检查：
- AOT 约束：不涉及动态加载 trait。✅
- FFI：无新增 FFI（@async.websocket 为纯 MoonBit 依赖，native 已随 async 运行时链接）。✅（审核更新：原"待任务包 1 裁决"已关闭）
- wasm 目标：@async.websocket 在 js/wasm-gc 有 unimplemented 降级文件，`moon check` 全目标可过。✅

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/channel/ws_client.mbt` | 新建 | WsClient 薄封装（决策 2）：包一层 @async.websocket.Conn，暴露 connect/send_text/on_message/on_close/ping |
| `lib/channel/discord.mbt` | 修改 | start 真连接 + 事件循环；handle_gateway_event 的发送动作接线（心跳/Identify/Resume/重连，:376-414 TODO 清零）；ISO 8601 解析（:293）；事件转 on_message（决策 4） |
| `lib/channel/discord_wbtest.mbt`（或新增） | 修改 | 连接生命周期单测（mock WsClient）、心跳定时触发、重连退避、ISO 8601 解析表驱动用例 |
| `lib/channel/moon.pkg` | 修改 | 增加 `import "moonbitlang/async/websocket"`（无 native-stub/FFI 配置变更） |

### 不涉及文件

- `lib/channel/discord_gateway.mbt` -- 协议层零 TODO，纯复用
- `lib/channel/wecom_ws.mbt`、`dingtalk.mbt` -- 消费方 spec 后置（依赖本 spec 的 WsClient）
- `lib/channel/discord_api.mbt` 的 edit_message 等 stub -- stubfix-02 审核扩围已将 edit_message/delete_message/get_current_user/upload_file 翻转为诚实 Err；**完整实装**属 backlog（流式分段更新消息属 P3）

## 实施计划 [必填]

### 任务包 1：WsClient 薄封装与能力验证（预估 0.5 天，审核后缩减）

1. 验证 @async.websocket 能力面：本地 echo 服务器（@websocket.from_http_server，async 包 README 有现成模式）wbtest 往返；确认 wss/TLS 路径可链接（native 冒烟）。
2. WsClient 薄封装落地（connect/send_text/on_message/on_close/ping，含 mock 注入点）。
3. `moon check` 0 errors（全目标）。

### 任务包 2：Discord 网关连接层（预估 1 天）

1. start：连接 wss://gateway.discord.gg -> HELLO -> Identify -> READY；事件循环 TaskGroup 常驻。
2. 心跳定时器（interval + 抖动复用）；Reconnect/InvalidSession/断线退避重连（决策 5）。
3. ISO 8601 解析函数 + 表驱动单测。
4. 事件 -> `ChannelManager::on_message` 接线（决策 4）。
5. wbtest：mock WsClient 驱动完整状态机（HELLO->READY->MESSAGE_CREATE->心跳->断线->Resume）。

### 任务包 3：端到端验收（预估 0.5 天）

1. 真实 bot token 冒烟（可得时）：bot 上线、频道消息触发 on_message、心跳稳定、断网重连恢复。
2. 无 token 环境：mock 全状态机断言 + moon test lib/channel 全绿。
3. 全量 `moon test` 无回归；`moon fmt`、`moon info`。

## 验收标准 [必填]

- [ ] WsClient 薄封装可用（@async.websocket echo 往返 wbtest 通过；无新增 FFI/依赖）
- [ ] `DiscordAdapter::start` 建立真实网关连接并完成 Identify（mock 状态机断言 HELLO->Identify->READY 全序）
- [ ] 心跳按服务器 interval + 抖动发送；断线按退避重连；致命关闭码停止并报错
- [ ] MESSAGE_CREATE 事件解析出真实时间戳（ISO 8601 表驱动用例全过，不再恒 0）
- [ ] 事件进入 `ChannelManager::on_message`（stubfix-01 合入后链路可达 agent）
- [ ] discord.mbt 的连接层 TODO 清零（grep 断言）
- [ ] `moon check` 0 errors（lib/channel；含 wasm 降级路径）
- [ ] `moon test lib/channel` 通过；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| ~~三条实现路径均受阻~~（审核后降级） | ~~高~~ -> 低 | 路径已裁决（@async.websocket 随 async@0.21.0 实存，RFC 6455 + TLS）；残余风险仅为能力面细节（如 permessage-deflate 不支持），Discord 网关不要求压缩扩展，回退无压缩帧即可 |
| ~~WS over TLS 依赖（wss）~~（审核后降级） | ~~高~~ -> 低 | TLS 由 async/tls 子包承接（websocket moon.pkg 直接 import），无 C stub、无额外链接配置 |
| @async.websocket API 形态与 WsClient 抽象错配（如无逐帧回调、recv 为拉模式） | 低 | 事件循环用 TaskGroup + 循环 recv 拉取，与 Discord 协议层的轮询处理天然契合；错配部分由薄封装吸收 |
| 心跳/重连定时器与 async 运行时集成 | 中 | 复用 llm_caller 的 @async.sleep 模式；TaskGroup 生命周期绑定 adapter start/stop |
| 事件风暴/限速（Discord 1000 事件/s 上限） | 低 | 接收循环串行处理 + 丢弃策略日志；限速合规列 backlog |

## 依赖关系 [必填]

- **前置依赖**：无硬依赖；建议在 stubfix-01（渠道接线）之后，事件链路才有生产出口
- **后置依赖**：钉钉 Stream Mode 连接层 spec（复用 WsClient）；WeCom WebSocket 连接层 spec（复用 WsClient + wecom_ws 协议层）；Discord edit_message 流式更新（backlog）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-21 | 初始版本 | stub 审计报告 2.2/3.6 节 + P2 建议 6；实现路径裁决（任务包 1）待回写 |
| 2026-08-22 | 审核重大修正：发现项目既有依赖 moonbitlang/async@0.21.0 自带 websocket 子包（RFC 6455 client/server、wss TLS + proxy、native 支持），原"需新增 WebSocket 底层能力/三路径待裁决"前提过时；决策 2 改为直接采用 @async.websocket + WsClient 薄封装；任务包 1 从"调研三路径（1 天）"缩减为"能力验证 + 薄封装（0.5 天）"；风险表 R1/R2 由高降为低、删除 link.native 风险；FFI 约束检查关闭（无新增 FFI）；wecom_ws.mbt 行数修正 441->436；其余行号（discord.mbt:88-108/:376-414/:293、dingtalk.mbt:95、wecom.mbt:104）实读精确命中；退避（RECONNECT_BASE_DELAY_MS=5000）与抖动函数（discord_gateway.mbt:204/:8）实存确认 | 对抗性审核 + 依赖树实读（.mooncakes/moonbitlang/async/src/websocket/） |
