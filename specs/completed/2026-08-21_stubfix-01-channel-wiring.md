# 渠道系统接线（ChannelManager 孤儿 + Webhook 断链 + Web API 脱节）· 增量 Spec

> **创建日期**: 2026-08-21
> **状态**: 已完成（2026-08-22 开发完成并验收通过，自 active 移入 completed）
> **关联总览**: `specs/active/2026-08-21_stubfix-00-overview.md`（来源：stub 实装状态审计报告 3.1/3.2/3.3 节 + 第五节建议 1）
> **关联历史 spec**: 无
> **来源差距**: 审计报告 3.1「ChannelManager 孤儿代码」、3.2「Webhook 接收链路断裂」、3.3「Web 渠道管理 API 与真实 adapter 脱节」
> **依赖**: 无
> **灰度 key**: 无

## 问题描述 [必填]

渠道模块（`lib/channel/`）整体是"孤儿代码"：adapter 层飞书/钉钉/Discord 的发送是真实现，但整条链路没有任何生产调用方。三个断点：

1. **ChannelManager 无人实例化**：web server 启动时不加载 `~/.mbopenclacky/channels.json`、不注册 adapter、不启动渠道；cmd/ 主程序同样不触碰。
2. **Webhook 接收链路断裂**：`POST /api/webhooks/:platform` -> `WebhookRegistry.handle` -> 必然 `Err("No handler registered for platform: ...")`。`WebhookRegistry::register` 定义存在（server.mbt:18）但生产代码零调用（仅 wbtest 调用）。`ChannelManager::handle_webhook` 实现完整（含去重）却无人接线。
3. **Web 管理 API 假成功**：`POST /api/channels/:id/send` 直接返回 `success: true` 而不调用任何 adapter（handlers_channels.mbt:548 注释自认 "For now, return success. In a real implementation, we would call the channel adapter."）；`POST /api/channels/:id/test` 只做字段非空校验，不做真实连通测试。

不做此接线，所有 adapter 实现（含后续 Telegram/WeCom 实装）都无法触达生产。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "ChannelManager 在 lib/channel 外零引用" | `grep -rln "ChannelManager" --include="*.mbt" lib/ cmd/ \| grep -v lib/channel/` | 0 命中 | 确认孤儿 |
| "WebhookRegistry 生产零注册" | `grep -rn "WebhookRegistry" lib/ cmd/` | server.mbt:18 定义 + handlers_bridge.mbt:244 注释引用；**全仓库零调用（含 wbtest）**。channel_wbtest.mbt:123/141 的 `registry.register(...)` 是 lib/channel adapter Registry 的调用，非 WebhookRegistry（审计报告混淆二者） | 确认断链 |
| "webhook 必返 No handler registered" | `grep -n "No handler registered" lib/web/server.mbt` | server.mbt:35 `None => Err("No handler registered for platform: " + platform)` | 确认 |
| "/api/channels/:id/send 假成功" | 实读 `lib/web/handlers_channels.mbt:548-560` | 注释 "For now, return success..." + 直接 `HttpResponse::ok({"success": true...})`，未调 adapter | 确认 |
| "ChannelManager API 完整可用" | `grep -n "pub fn\|pub async fn" lib/channel/manager.mbt` | `new(config_path)/load_config/on_message/start/stop/reload/send_to(async)/status/validate_all/handle_webhook` 全套存在 | 确认：接线即可用，无需重写 |
| "channels.json 加载逻辑存在" | 审计报告 3.1 节 + manager.mbt:47 `load_config` 存在 | 属实 | 确认 |
| "channels_store 与 ChannelConfig 两套平行模型" | 审计报告 3.3 节 | handlers_channels 使用独立 channels_store | 确认（本 spec 范围控制见决策 5） |
| "channels_store 为 web 层内存态" | 实读 `lib/web/handlers_channels.mbt:24` | `let channels_store : Ref[Array[ChannelEntry]] = Ref([])` 全局内存数组，无持久化 | 确认（决策 5 桥接的现实基础） |
| "路由已注册于 server.mbt build_app" | 实读 `lib/web/server.mbt:443-477,657` | crescent group：`ch.post("/:id/send")`(:464)、`ch.post("/:id/test")`、`wh.post("/:platform")`(:657)；router.mbt:3 注明"新路由加到 WebServer::start 的 crescent App" | 确认（审计引用的 router.mbt 非注册点） |
| "Discord get_current_user 可作连通探测" | 实读 `lib/channel/discord_api.mbt:119-134` | **假成功 stub**：TODO 后返回伪造 `{"id":"pending","username":"bot"}`，无 HTTP 调用 | **推翻**：不能作 test API 探测（决策 4 修订） |
| "飞书 token 获取有实现" | 实读 `lib/channel/feishu_api.mbt:66-102` | `request_token`/`get_token` 含真实请求构造与响应解析 | 确认可作飞书探测 |

### 详细分析

**发送链路现状**：`ChannelManager::send_to`（manager.mbt:189，async）-> registry -> 各 adapter send_text。飞书（http_post_json 真实现）、钉钉（三策略真发送）、Discord（真 POST）可用；Telegram/WeCom/Weixin 是假成功 stub（stubfix-02 处置）。链路终点真实，缺的是"把 ChannelManager 挂到 server 生命周期 + 把 web API 调用转成 send_to 调用"。

**接收链路现状**：飞书 URL 验证 challenge 特判存在（handlers_bridge.mbt:263-269，`handle_webhook_bridge` 主体 246-278），事件回调全平台断在 `WebhookRegistry.handle` 的空 handler 表。`ChannelManager::handle_webhook`（manager.mbt:236）签名与实现就绪，等一个 register 调用。

**生命周期现状**：web server（`moon run cmd -- server`，端口 7071）启动流程不包含渠道初始化；实例化点在 `cmd/main.mbt:706`（`@web.WebServer::new(config, api_key)`），生命周期方法 `WebServer::new/build_app/start`（server.mbt:66/187/965）。ChannelManager 需要：(a) 实例化 + load_config(channels.json)；(b) adapter 注册（飞书/钉钉/Discord/Telegram/WeCom/Weixin 六平台，按配置存在性）；(c) start（接收侧，如飞书 webhook 模式只需 handler 注册，Stream/WS 类暂为 TODO 不阻塞）。

## 决策 [必填 - 含为什么]

1. **决策 1（挂载点）**：在 web server 初始化流程（`WebServer::new`/`start` 阶段，实例化点 `cmd/main.mbt:706`）实例化全局唯一 `ChannelManager`，执行 `load_config` + 六平台 adapter 注册，并将 handler 注册进 `WebhookRegistry`；server 关闭时调 `stop`。
   - **为什么**：web server 是当前唯一的长驻入口（cmd 主程序为 TUI 会话式）；单例生命周期与 server 对齐，避免多实例状态分裂。
2. **决策 2（webhook 接线）**：`WebhookRegistry::register(platform, handler)` 的 handler 实现统一转发 `ChannelManager::handle_webhook(platform, body)`，仅对已配置平台注册（未配置平台保持现有 "No handler registered" 错误）。
   - **为什么**：`handle_webhook` 已含去重与事件分发（审计确认"写得挺完整"）；按配置注册避免未配置平台误报成功。
3. **决策 3（send API 真接线）**：`POST /api/channels/:id/send` 改为查 ChannelManager 配置 -> `send_to` -> 映射结果；保留现有响应 JSON 结构（success/message_id/error 字段），假成功注释删除。
   - **为什么**：调用方（Web UI）契约不变，行为从假变真；失败时 `success:false + error` 是既有结构，前端无需改动。
4. **决策 4（test API 增强）**：`POST /api/channels/:id/test` 在字段校验通过后追加真实轻量探测（按平台：飞书 request_token 获取（feishu_api.mbt:66-102 实现存在）/ Telegram getMe（URL 构建器已备，真发送依赖 stubfix-06）/ Discord 改用 `http_get_json` 直发 `GET /users/@me` 一次性探测（get_current_user 现为假成功 stub，实装真版后可切换，审核修正）/ 钉钉 robot ping；探测失败返回 connected:false + 错误）。
   - **为什么**：审计指出"测试显示 connected 不代表能连通"；探测必须建立在真 HTTP 调用上--初始版引用的 "Discord get_current_user" 经实读为假成功 stub（discord_api.mbt:119-134 返回伪造 pending 数据），沿用会造成 test API 二次假成功；实现分级：本 spec 先接 ChannelManager::validate_all + 飞书/Discord 真探测，Telegram 探测依赖 stubfix-06，WeCom/Weixin 依赖后续实装（返回 not implemented 诚实标记）。
5. **决策 5（两套模型暂不合并）**：本 spec 只做"接线"，不合并 channels_store 与 ChannelConfig/ChannelManager 两套模型；send 路径以 channels_store 的 channel_id 查 ChannelManager 配置的桥接映射实现（按 platform+配置字段匹配），模型统一列为后置依赖。
   - **为什么**：模型合并是数据迁移级别改动（含持久化格式），混入本 spec 会使审查面失控；接线先用桥接映射即可打通行为，合并另行立项。
6. **决策 6（启动失败不阻塞 server）**：channels.json 不存在/损坏时记日志、ChannelManager 保持空配置运行，server 正常启动。
   - **为什么**：渠道是增强能力，不能因其缺席导致主服务（agent/web）不可用；与 Ruby 原版"渠道可选"语义一致。

MoonBit 约束检查：
- AOT 约束：不涉及动态加载 trait；adapter 注册为编译期枚举分发（AnyAdapter 模式已有）。✅
- crescent 路由：路由已存在（/api/webhooks/:platform、/api/channels/:id/send、/test），只改 handler 内部实现。✅
- FFI：send_to 依赖的 http_post_json 走既有 @client FFI。✅

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/server.mbt` | 修改 | Server 构造/启动阶段：实例化 ChannelManager、load_config、注册六平台 adapter、WebhookRegistry handler 注册（决策 1/2）；关闭路径调 stop |
| `lib/web/handlers_bridge.mbt` | 修改 | webhook handler 实现改为转发 `ChannelManager::handle_webhook`（保留飞书 challenge 特判） |
| `lib/web/handlers_channels.mbt` | 修改 | send 端点真调 `send_to`（决策 3）；test 端点接真实探测（决策 4 分级） |
| `lib/web/server_wbtest.mbt`（或新增接线 wbtest） | 修改 | 新增：配置加载（正常/缺失/损坏三态）、webhook 转发、send 成功/失败映射用例 |
| `cmd/main.mbt`（启动入口 :706 `WebServer::new`） | 修改 | 仅在需传递全局 ChannelManager 实例时调整参数；若 server.mbt 内聚实例化则此文件不动 |

### 不涉及文件

- `lib/channel/` 各 adapter 实现 -- 发送真伪问题是 stubfix-02/06/07 的范围，本 spec 只接线
- channels_store 数据结构与持久化 -- 决策 5 明确不合并
- Stream Mode/WebSocket/Gateway 接收侧 -- stubfix-07 范围
- `cmd/channel_scaffold.mbt` -- 脚手架行为保留（审计 3.4 属设计内）

## 实施计划 [必填]

### 任务包 1：ChannelManager 生命周期挂载（预估 0.5 天）

1. server 启动序列插入渠道初始化（new -> load_config -> register 六平台 -> 空配置容错日志，决策 6）。
2. wbtest：正常配置加载后 status 返回六平台状态；channels.json 缺失时 server 可用。
3. `moon check` 0 errors。

### 任务包 2：webhook 接线（预估 0.5 天）

1. 按配置注册各平台 handler -> 转发 handle_webhook；未配置平台保持原错误。
2. 飞书 challenge 特判回归验证。
3. wbtest：已配置平台事件转发、未配置平台报错、去重生效。

### 任务包 3：send/test API 真接线（预估 0.5 天）

1. send：channel_id -> 配置桥接（决策 5）-> send_to -> 结果映射（含 adapter 假成功期间 Telegram/WeCom/Weixin 由 stubfix-02 先行改为诚实 Err，本包自然透传）。
2. test：validate_all + 飞书/Discord 真探测；Telegram/WeCom/Weixin 返回 connected:false + "not implemented" 诚实标记。
3. wbtest：send 成功（飞书 mock）、send 失败映射、test 各平台分级结果。

### 任务包 4：回归与验收（预估 0.5 天）

1. `moon run cmd -- server` 手动冒烟：无 channels.json 启动正常；配置飞书后 webhook 事件可达 handle_webhook（本地 curl challenge + 事件样例）。
2. `moon test lib/web`、`moon test lib/channel` 全绿；全量 `moon test` 无回归。

## 验收标准 [必填]

- [x] web server 启动时 ChannelManager 被实例化并加载 channels.json（日志或 status 端点可证）
- [x] channels.json 缺失/损坏时 server 正常启动（决策 6）
- [x] 已配置平台的 `POST /api/webhooks/:platform` 事件进入 `ChannelManager::handle_webhook`（wbtest 断言转发）
- [x] 未配置平台仍返回 "No handler registered"（行为不外溢）
- [x] `POST /api/channels/:id/send` 真实调用 adapter send 链路（wbtest 断言 send_to 被触达；假成功注释删除）
- [x] `POST /api/channels/:id/test` 返回真实探测结果（飞书/Discord 连通性；未实装平台诚实标记）
- [x] `moon check` 0 errors（lib/web、lib/channel）
- [x] `moon test lib/web`（469 通过）、`moon test lib/channel`（402 通过）；全量 `moon test` 3854/3855（唯一失败为预存在 billing flaky，与本次改动无关，见变更记录）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| send 接线后 Telegram/WeCom/Weixin 仍处假成功（若 stubfix-02 未先行） | 中 | 实施顺序上 stubfix-02 优先合入；接线后 Web UI 将暴露假成功问题，与审计 P0 建议一致，风险已被 stubfix-02 显式处置 |
| 两套模型桥接映射的字段对齐偏差（platform 命名/大小写） | 中 | 桥接函数集中一处 + wbtest 覆盖六平台命名映射 |
| server 启动顺序引入回归（渠道初始化阻塞主路由） | 低 | 初始化为同步快速路径（读配置+注册），无网络 IO；异常全捕获（决策 6） |
| webhook handler 注册后未配置平台误吞请求 | 低 | 决策 2 按配置注册，未配置平台走原错误路径并有 wbtest |
| handle_webhook 的去重/分发缺陷在真实流量下暴露 | 中 | wbtest 覆盖重复事件；渠道事件样例进 fixture |

## 依赖关系 [必填]

- **前置依赖**：无（技术上独立；强烈建议与 stubfix-02 同批次评审/合入，见风险表第一条）
- **后置依赖**：stubfix-06（Telegram 真发送后 test 探测升级为 getMe）；stubfix-07（WS/Stream 接收侧实装后 start 语义补全）；渠道模型合并（backlog）；channel_scaffold 生成的模板接入注册表（backlog）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-21 | 初始版本 | stub 审计报告 3.1/3.2/3.3 节，P0 建议 1 |
| 2026-08-22 | 审核修正：(1) WebhookRegistry::register 实为全仓库零调用（含 wbtest），原验证表把 lib/channel adapter Registry 的调用（channel_wbtest.mbt:123/141）误记为 WebhookRegistry 调用；(2) 推翻决策 4 中 "Discord get_current_user 可作探测"（实读为假成功 stub，返回伪造 pending 数据，改用 http_get_json 直发真探测）；(3) `cmd/server.mbt` 不存在，启动入口实为 `cmd/main.mbt:706`（WebServer::new），挂载点核准为 WebServer::new/build_app/start；(4) 路由注册位置补正：server.mbt build_app 的 crescent group（:443-477/:657），router.mbt 非注册点；(5) 飞书 challenge 行号修正 255-264 -> 263-269；补录 channels_store 为内存态 Ref 的事实；飞书 request_token 实现存在（feishu_api.mbt:66-102）核准 | 对抗性审核 + 第一性原理校验 |
| 2026-08-22 | 开发完成：(1) `ChannelManager::init`/`configured_platforms`/`is_platform_configured`/`create_adapter_from_config` 落地，`WebServer` 挂载 `channel_manager` 字段并在 `new` 时 `init_channel_manager`（失败仅记日志，决策 6）；(2) `handle_webhook_bridge` 按配置转发 `handle_webhook`（保留飞书 challenge 特判），未配置平台回退 webhook_registry；(3) `handle_channels_send` 真调 `send_to`（Err 映射 success:false），`handle_channels_test` 按平台分级探测（飞书 request_token / Discord GET /users/@me / 未实装平台诚实标记）；(4) 新增 13 个 wbtest（channel 4 + web wiring 9）；`moon check` 0 errors、`moon test lib/web` 469、`moon test lib/channel` 402 全绿、`moon info` 无 API 破坏。全量 `moon test` 3854/3855，唯一失败为预存在的 billing flaky（`_build/ct_billing_*` 残留累积，`ct_make_billing_store` 进程内计数器跨进程归零导致目录复用；清理残留后该测试单独跑通过），与本次改动无关 | 开发验收 + 归档 |
