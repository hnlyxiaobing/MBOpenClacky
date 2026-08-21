# WebSocket 客户端基础设施 + Discord 网关连接层 · 增量 Spec

> **创建日期**: 2026-08-21
> **状态**: 讨论中
> **关联总览**: `specs/draft/2026-08-21_stubfix-00-overview.md`（来源：stub 实装状态审计报告 2.2/3.6 节 + 第五节建议 6）
> **关联历史 spec**: 无
> **来源差距**: 审计报告 2.2「Discord 网关连接层完全未实装」+ 3.6「WeCom WebSocket 协议层完整但无连接」+ 建议 6「WS 客户端 FFI 三平台（Discord/钉钉 Stream/WeCom）共用」
> **依赖**: 无硬依赖（建议在 stubfix-01 之后实施，渠道接线完成后连接层才有生产入口）
> **灰度 key**: 无

## 问题描述 [必填]

三个平台的接收侧共用同一缺失能力：**WebSocket 客户端连接**。

1. **Discord 网关**（lib/channel/discord.mbt + discord_gateway.mbt）：协议层完成度很高（全部 10 个 opcode、心跳/Identify/Resume payload 构建、Hello/READY/InvalidSession 解析、心跳抖动、指数退避、致命关闭码判定），但连接层全 TODO--`DiscordAdapter::start` 只设标志位（discord.mbt:88-108），`handle_gateway_event` 中所有需要**发送**的动作（心跳响应、Identify、Resume、重连）全部 TODO（:376-414），心跳定时器不存在。**没有 WebSocket 客户端，Discord 机器人无法收到任何消息**。
2. **WeCom WebSocket**（lib/channel/wecom_ws.mbt，441 行）：协议层完整（帧类型、Subscribe/SendMsg/Ping/Pong/Ack、req_id 匹配、ACK 超时、分块上传），`mark_connected` 只是设标志位；发送侧构建帧后丢弃（wecom.mbt:142-144，stubfix-02 已改为诚实 Err）。
3. **钉钉 Stream Mode**（dingtalk.mbt:95 TODO）：WebSocket 连接未实装。

附加：discord.mbt:293 ISO 8601 时间戳解析缺失（MESSAGE_CREATE 恒返回 0），影响消息时间准确性（审计第四节同列 TokenCache 等时间戳问题，解法与 stubfix-04/05 共享时钟不同--此为字符串解析非时钟）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "Discord 协议层零 TODO、连接层 10 处 TODO" | `grep -c "TODO" lib/channel/discord.mbt lib/channel/discord_gateway.mbt` | discord.mbt: 10；discord_gateway.mbt: 0 | 确认：协议纯函数完成，连接/发送动作缺失 |
| "start 只设标志" | 审计 2.2 节 discord.mbt:88-108 | `TODO: Connect to Gateway WebSocket via @websocket` | 确认 |
| "事件发送动作全 TODO" | 审计 2.2 节 discord.mbt:376-414 | 心跳响应/Identify/Resume/重连 TODO | 确认 |
| "@websocket 引用存在" | discord.mbt TODO 注释提及 `@websocket` | 注释指向的 FFI 目标未落地（全仓库无 WebSocket 客户端实现） | 确认缺底层能力 |
| "WeCom ws 协议层完整" | 审计 3.6 节 wecom_ws.mbt 441 行 + `grep -n "mark_connected" lib/channel/wecom.mbt` | 帧构建/ACK 匹配/分块上传齐全；wecom.mbt:104 mark_connected 设标志 | 确认可复用资产 |
| "ISO 8601 解析缺失" | 审计 2.2 节 discord.mbt:293 | 恒返回 0 | 确认（本 spec 一并处置） |
| "进程/网络 FFI 先例" | browser_process（@process）+ http_helper（@client） | 管道与 HTTP FFI 模式存在，但无 WebSocket FFI | 确认需新增底层能力（本 spec 核心） |

### 详细分析

**能力缺口是横切的**：Discord Gateway（wss://gateway.discord.gg）、钉钉 Stream Mode（wss 事件流）、WeCom 智能机器人 WebSocket 三者都只需要一个能力--带心跳保活的 WebSocket 客户端（连接、发送文本帧、接收帧回调、关闭/重连钩子）。审计建议 6 明确"建议一并规划"。

**实现路径选项**：
- (a) native-stub C FFI（自写或引入小型 WS 库）：项目已有 native-stub 先例（browser_popen.c）；WS 协议（RFC 6455：握手升级、帧编解码、掩码、ping/pong）C 实现量可控。
- (b) 纯 MoonBit 实现 WS over @client socket：@client 当前暴露 HTTP 语义，是否可拿到原始 socket/TLS 流需实施时以 `moon ide doc` 查证（项目规则：声称"不支持"前必须 grep 验证）。
- (c) 复用既有包：mooncakes 是否有 WebSocket 客户端包（实施首步调研，规则同上）。

本 spec 按能力分层组织：任务包 1 先完成路径裁决（a/b/c），再实施。协议层（Discord opcode/WeCom 帧）复用不动。

## 决策 [必填 - 含为什么]

1. **决策 1（能力优先、平台分层）**：本 spec 交付"WebSocket 客户端基础设施 + Discord 网关完整接线"；钉钉 Stream/WeCom 连接为后置依赖 spec（复用同一基础设施）。
   - **为什么**：三平台一次做完则单 spec 触及 5+ 文件且审查面过大（Harness 范围规则）；Discord 协议层完成度最高（零 TODO），是基础设施的理想首个消费者，能把"连接层补齐即机器人可用"验证到端到端。
2. **决策 2（基础设施形态）**：抽象为 `WsClient` 能力层（connect(url, headers)/send_text/on_message 回调/on_close/心跳 ping 间隔钩子），实现路径（C stub / 纯 MoonBit / 依赖包）由任务包 1 裁决，裁决结论回写本 spec。
   - **为什么**：三平台需求收敛为同一接口；实现细节与消费者解耦，裁决前不锁死方案；遵循"先验证再声称不可行"的项目规则（crescent/@client 能力 grep 验证前置）。
3. **决策 3（Discord 网关连接层）**：补齐 `DiscordAdapter::start`（连接 + 事件循环 spawn）、心跳定时器（按 HELLO 的 heartbeat_interval + 既有抖动函数）、Identify/Resume 发送、Reconnect/InvalidSession 重连、MESSAGE_CREATE 的 ISO 8601 解析；全部复用既有协议层函数。
   - **为什么**：协议层已就绪（验证记录第 1 条），连接层是纯接线 + 生命周期管理；ISO 8601 解析是同文件顺手项（独立小函数 + 单测）。
4. **决策 4（事件到生产链路）**：MESSAGE_CREATE 等事件经 `ChannelManager::on_message`（manager.mbt:119 已存在）进入消息处理链（stubfix-01 接线后可达 agent）。
   - **为什么**：避免连接层实装后事件仍止步于 adapter 内部（防"第二个孤儿层"）；on_message 签名已备。
5. **决策 5（重连与退避）**：断线按既有指数退避函数（5s 起、上限 60s）重连，致命关闭码（4004/4010-4014）不重连并暴露错误状态。
   - **为什么**：复用协议层已实现的判定（审计 2.2 确认齐全）；避免 token 失效场景下的重连风暴。

MoonBit 约束检查：
- AOT 约束：不涉及动态加载 trait。✅
- FFI：若裁决走 native-stub，需 `moon.pkg.json` 配置 native-stub + link.native（browser_popen.c 先例）；实施时按项目规则配置。⚠️ 待任务包 1 裁决
- wasm 目标：WS 层需 stub 降级文件（对齐 browser_process 的 detect_stub 模式），`moon check` 必须过。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/channel/ws_client.mbt`（+ 若 C stub：`ws_client.c`、moon.pkg 配置） | 新建 | WsClient 能力层（决策 2）；实现路径由任务包 1 裁决回写 |
| `lib/channel/discord.mbt` | 修改 | start 真连接 + 事件循环；handle_gateway_event 的发送动作接线（心跳/Identify/Resume/重连，:376-414 TODO 清零）；ISO 8601 解析（:293）；事件转 on_message（决策 4） |
| `lib/channel/discord_wbtest.mbt`（或新增） | 修改 | 连接生命周期单测（mock WsClient）、心跳定时触发、重连退避、ISO 8601 解析表驱动用例 |
| `lib/channel/moon.pkg` | 修改 | 依赖/FFI 配置随决策 2 落地 |

### 不涉及文件

- `lib/channel/discord_gateway.mbt` -- 协议层零 TODO，纯复用
- `lib/channel/wecom_ws.mbt`、`dingtalk.mbt` -- 消费方 spec 后置（依赖本 spec 的 WsClient）
- `lib/channel/discord_api.mbt` 的 edit_message 等 stub -- 审计 2.1 诚实报错型，backlog（流式分段更新消息属 P3）

## 实施计划 [必填]

### 任务包 1：路径裁决与 WsClient 基础设施（预估 1 天）

1. 调研三路径：mooncakes WebSocket 包（moon search/add 试探）、@client socket 能力（moon ide doc + grep 既有用法）、C stub 方案（browser_popen.c 模式）；裁决结论与证据回写本 spec 变更记录。
2. WsClient 接口落地 + 最小实现（connect/send_text/on_message/on_close/ping）。
3. wbtest：本地 echo 服务器（或 mock 层）往返；`moon check` 0 errors（含 wasm stub 降级）。

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

- [ ] WsClient 基础设施可用（裁决结论与证据已回写 spec；wbtest 往返通过）
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
| 三条实现路径均受阻（无现成包、@client 无原始 socket、C stub 复杂度超预期） | 高 | 任务包 1 前置裁决即暴露；C stub 路径有 browser_popen.c 先例，RFC 6455 客户端子集（无扩展/无压缩）实现量可控；最坏情况缩小范围为"C stub 文本帧 + 固定心跳"最小集 |
| WS over TLS 依赖（wss） | 高 | C stub 路径需 TLS 库链接（Windows native：schannel 或内置小型 TLS）；裁决时明确 TLS 方案与体积影响；若 TLS 复杂度不可控，降级为"httpgw 代理模式"设计再议（回写 spec） |
| 心跳/重连定时器与 async 运行时集成 | 中 | 复用 llm_caller 的 @async.sleep 模式；TaskGroup 生命周期绑定 adapter start/stop |
| Windows native 链接配置（link.native）踩坑 | 中 | browser_popen.c 的既有配置为模板；任务包 1 冒烟即验证 |
| 事件风暴/限速（Discord 1000 事件/s 上限） | 低 | 接收循环串行处理 + 丢弃策略日志；限速合规列 backlog |

## 依赖关系 [必填]

- **前置依赖**：无硬依赖；建议在 stubfix-01（渠道接线）之后，事件链路才有生产出口
- **后置依赖**：钉钉 Stream Mode 连接层 spec（复用 WsClient）；WeCom WebSocket 连接层 spec（复用 WsClient + wecom_ws 协议层）；Discord edit_message 流式更新（backlog）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-21 | 初始版本 | stub 审计报告 2.2/3.6 节 + P2 建议 6；实现路径裁决（任务包 1）待回写 |
