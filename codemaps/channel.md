# channel — 6 个 IM 适配器 · 消息收发 · WebSocket 网关

> 路径: `lib/channel/` · 20 文件（src=18, test=2）· 即时通讯平台接入层

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `ChannelManager::new(config_path)` | `manager.mbt` | 创建频道管理器 |
| `ChannelManager::start()` | `manager.mbt` | 启动所有已配置的频道适配器 |
| `ChannelManager::send_to(platform, chat_id, text)` | `manager.mbt` | 向指定平台发送消息 |
| `ChannelManager::handle_webhook(platform, json)` | `manager.mbt` | 处理 Webhook 回调 |
| `Adapter::start(callback)` | `adapter.mbt` | 各适配器启动（trait 方法） |

## 关键类型

### Trait
- **`Adapter`** — 核心 trait：`platform_id()`, `start(callback)`, `stop()`, `send_text()`, `update_message()`, `validate_config()`

### 适配器枚举
- **`AnyAdapter`** — 6 个适配器的 sum type：`Feishu | WeCom | Telegram | Discord | DingTalk | Weixin`

### 各平台适配器 + API Client
| 平台 | Adapter | ApiClient | 特殊组件 |
|------|---------|-----------|----------|
| 飞书 | `FeishuAdapter` | `FeishuApiClient` | TokenCache |
| 企微 | `WeComAdapter` | — | `WeComWsState`, `WeComUploadState` |
| Telegram | `TelegramAdapter` | `TelegramApiClient` | long-polling |
| Discord | `DiscordAdapter` | `DiscordApiClient` | `GatewayState` |
| 钉钉 | `DingTalkAdapter` | `DingTalkApiClient` | Stream 连接 |
| 微信 | `WeixinAdapter` | `WeixinApiClient` | `WeixinSendQueue`, AES 加解密 |

### 消息模型
- **`ChannelEvent`** — 统一事件（event_type, platform, chat_id, sender, text, attachments, chat_type）
- **`ChannelConfig`** — 频道配置（platform, enabled, settings）
- **`Attachment`** / **`AttachmentType`** — 附件（Image | File | Audio | Video）
- **`SendResult`** — 发送结果（message_id, success, error）

### 辅助类型
- **`Platform`** — `Feishu | WeCom | Weixin | Telegram | Discord | DingTalk`
- **`ChatType`** — `Direct | Group`
- **`EventType`** — `Message | Command | Join | Leave`
- **`TokenCache`** — Token 缓存（自动刷新）
- **`GatewayState`** — Discord Gateway 连接状态
- **`GatewayOpcode`** — Discord Gateway 操作码
- **`HttpHeaders`** — HTTP 头构建器
- **`RetryConfig`** — 重试配置

### 错误
- **`ChannelError`** — 频道错误子类型

## 核心调用链

```
# 消息接收
ChannelManager::start()
  └─ for each config: Adapter::start(callback)
      ├─ Feishu: webhook 回调
      ├─ WeCom: WebSocket 长连接 (WeComWsState)
      ├─ Telegram: long-polling (getUpdates)
      ├─ Discord: Gateway WebSocket (GatewayState)
      ├─ DingTalk: Stream 连接
      └─ Weixin: long-polling + AES 解密

# 消息发送
ChannelManager::send_to(platform, chat_id, text)
  └─ AdapterRegistry::find(platform) → AnyAdapter
      └─ Adapter::send_text(chat_id, text, reply_to?)
          └─ ApiClient::send_message(...)  # HTTP POST

# Webhook 处理
ChannelManager::handle_webhook(platform, json)
  └─ Adapter::parse_event(json) → ChannelEvent
  └─ message_callback(event)
```

## 文件职责分组

| 文件组 | 文件 | 职责 |
|--------|------|------|
| 核心框架 | `adapter.mbt`, `manager.mbt`, `registry.mbt`, `types.mbt`, `http_helper.mbt` | Adapter trait、ChannelManager、AdapterRegistry |
| 飞书 | `feishu.mbt`, `feishu_api.mbt`, `feishu_message_parser.mbt` | 飞书适配 |
| 企微 | `wecom.mbt`, `wecom_ws.mbt` | 企微 WebSocket 适配 |
| Telegram | `telegram.mbt` | Telegram long-polling 适配 |
| Discord | `discord.mbt`, `discord_api.mbt`, `discord_gateway.mbt` | Discord Gateway 适配 |
| 钉钉 | `dingtalk.mbt`, `dingtalk_api.mbt` | 钉钉 Stream 适配 |
| 微信 | `weixin.mbt`, `weixin_api.mbt` | 微信适配（AES 加解密、发送队列） |

## 外部依赖

- **HTTP** — 各平台 REST API（通过 `lib/client` 的 http_post/http_get）
- **WebSocket** — Discord Gateway、企微 WS、钉钉 Stream

## 风险点

1. **Token 过期** — 各平台 Token 刷新策略不同，`TokenCache` 需正确设置 `refresh_threshold`
2. **Discord Gateway 重连** — `GatewayState` 重连逻辑复杂（resume/reconnect/identify），网络抖动可能导致死循环
3. **微信 AES 加解密** — `weixin_aes_encrypt/decrypt` 自实现，密钥派生安全性需验证
4. **消息分片** — Telegram 4096 字符限制、微信分片发送，边界处理易出错
5. **附件下载** — 各平台附件 URL 需鉴权，过期后无法下载
