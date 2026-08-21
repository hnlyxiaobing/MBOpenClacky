# Stub 实装状态审计报告

> 审计日期：2026-08-21
> 审计范围：全仓库（lib/、cmd/），重点核验渠道发送、Discord 网关、MCP stdio、办公文档解析四个领域
> 审计方法：grep 定位 stub/TODO/placeholder 标记 + 逐文件精读实现，所有结论均有代码行号佐证

## 一、总结论

| 领域 | 实装状态 | 一句话结论 |
|------|---------|-----------|
| 渠道发送（IM outbound） | ⚠️ 部分实装但**断链** | adapter 层飞书/钉钉/Discord 发送是真实现，Telegram/WeCom/微信是假成功 stub；但整条链路**没有任何生产调用方** |
| Discord 网关（接收） | ❌ 未实装 | 纯协议函数库（payload 构建/解析/状态机齐全），WebSocket 连接、心跳定时器、事件循环全部是 TODO |
| MCP stdio | ❌ 未实装 | transport 的 start/stop/send_message 全是 placeholder，客户端请求必然抛错；HTTP transport 同样是 stub |
| 办公文档解析 | ❌ 未实装 | 6 种格式（docx/xlsx/pptx/pdf/doc/wps）全部返回占位符文本；缺 ZIP/OLE2/外部命令 FFI |

**最严重的横切发现：渠道模块整体是"孤儿代码"。**
- `ChannelManager` 在 `lib/channel/` 之外**零引用**（全仓库 grep 证实）
- Web 端 `POST /api/channels/:id/send` 直接返回假 success，注释明说没调 adapter（`lib/web/handlers_channels.mbt:553`）
- Web 端 `POST /api/webhooks/:platform` 走 `WebhookRegistry`，但**没有任何地方注册过 handler**，所有平台必返回 "No handler registered"（`lib/web/server.mbt:28`、`lib/web/handlers_bridge.mbt:273`）

---

## 二、四大领域详细分析

### 2.1 渠道发送（lib/channel/）

`http_helper.mbt` 中 `http_post_json`/`http_get_json` 是真实现（走 `@client` FFI，`lib/channel/http_helper.mbt:280-314`），所以"发送真伪"取决于各 adapter 是否调用它。

各平台逐项核验：

| 平台 | send_text | update_message | 接收侧（start） | 证据 |
|------|-----------|----------------|----------------|------|
| Feishu | ✅ 真发送 | ❌ stub（TODO PATCH，静默 Ok） | ⚠️ 靠 webhook（但 webhook 链路断，见 3.2） | feishu.mbt:91-137 真调 http_post_json；feishu.mbt:148-170 TODO |
| DingTalk | ✅ 真发送（三策略：sessionWebhook / robot API / webhook_url） | N/A（不支持编辑） | ❌ Stream Mode WebSocket 全 TODO | dingtalk.mbt:117-215；dingtalk.mbt:95 |
| Discord | ✅ 真发送 | ❌ stub（edit_message 未接 HTTP，返回伪造结果） | ❌ Gateway 未实装（见 2.2） | discord_api.mbt:60-69 真 POST；discord_api.mbt:77-99 stub |
| Telegram | ❌ **假成功 stub**（返回伪造 `"tg_msg_"+chat_id`，success=true） | ❌ stub | ❌ getUpdates 长轮询 TODO | telegram.mbt:261-284 |
| WeCom | ❌ **假成功 stub**（构建 WebSocket 帧后不发送，直接返回成功） | N/A | ❌ 假连接（仅 mark_connected 标志位） | wecom.mbt:121-148；wecom.mbt:143 TODO |
| Weixin | ❌ **假成功 stub**（消息入队后从不真正发送，返回 "weixin_msg_pending"） | N/A | ❌ 长轮询 TODO | weixin.mbt:206-280 |

**风险提示**：Telegram/WeCom/Weixin 的 send_text 返回 `success: true` 是**静默丢消息**——调用方以为发出去了，实际什么都没发生。这比诚实报错（如 feishu_api 高层 send_message 返回 Err）危险得多。

各平台 API 层其他 stub（诚实报错型，返回 Err）：
- `FeishuApiClient::send_message`（高层封装，与 adapter 内联实现重复且未接 HTTP）：feishu_api.mbt:171-190
- 飞书图片/文件上传（multipart）：feishu_api.mbt:250、273
- 飞书附件下载（GET）：feishu_api.mbt:301、327
- Discord：edit_message / delete_message / get_current_user / upload_file / download_attachment 全部 stub：discord_api.mbt:77-180
- 钉钉 Stream 连接 open、文件下载 URL：dingtalk_api.mbt:352-384、387-420
- 微信 AES-128-ECB 加解密未实现：weixin_api.mbt:346、367

### 2.2 Discord 网关（lib/channel/discord_gateway.mbt + discord.mbt）

**协议层（纯函数）完成度很高**：
- 全部 10 个 opcode 定义与转换（discord_gateway.mbt:24-102）
- 心跳/Identify/Resume payload 构建（:268-310）
- Hello/READY/InvalidSession 解析（:332-395）
- 心跳抖动、指数退避重连（5s 起，上限 60s）、致命关闭码判定（4004/4010-4014）（:190-225）
- Resume 条件判定与 resume_gateway_url 覆盖（:233-247）

**连接层完全未实装**：
- `DiscordAdapter::start` 只设标志位，`TODO: Connect to Gateway WebSocket via @websocket`（discord.mbt:88-108）
- `handle_gateway_event` 中所有需要**发送**的动作（心跳响应、Identify、Resume、Reconnect 重连、InvalidSession 后的重发）全部 TODO（discord.mbt:376-414）
- 心跳定时器不存在
- `edit_message` 是 stub，意味着流式回答的"逐段更新消息"在 Discord 上静默无效
- MESSAGE_CREATE 事件里 ISO 8601 时间戳不解析，恒返回 0（discord.mbt:293）

结论：**没有 WebSocket 客户端 FFI，Discord 机器人无法收到任何消息**。事件处理函数 `handle_gateway_event` 只有测试能触达。

### 2.3 MCP stdio（lib/mcp/stdio_transport.mbt）

**已实装（外围）**：mcp.json 配置解析（mcpServers 格式、多路径查找 ~/.mbopenclacky/mcp.json → .qoder/mcp.json → mcp.json）、JSON-RPC 编解码、虚拟技能生成、多服务器注册表管理。

**未实装（核心通信）**：
- `StdioTransport::start`：只设 `is_alive = true`，不 spawn 子进程（stdio_transport.mbt:56-60，TODO 注释明确 "FFI implementation needed"）
- `StdioTransport::stop`：只设标志位（:63-67）
- `StdioTransport::send_message`：`ignore(message)` 直接丢弃（:79-89）
- `McpClient::send_request`：发送后**必然 raise** `"Response handling requires async runtime"`（client.mbt:119-145）——没有请求-响应关联机制
- `McpRegistry::cleanup_idle`：空闲清理只删 last_used_at 为 None 的，时间戳比较是 TODO（registry.mbt:216-234）
- `last_used_at`/`started_at` 恒为 0（placeholder 时间戳）

**HttpTransport 同样是 stub**：send_message 同样 ignore（http_transport.mbt:70-77）。即 MCP 的两种 transport 都是空壳。

**影响面**：Web 端 `/api/mcp` 的 tools/call 端点真实存在并调用 `registry.call_tool`（handlers_mcp.mbt:412、492），但链路终结于必然抛错的 send_request——**用户在 Web UI 里配置的任何 MCP 服务器都无法真正连通**。

### 2.4 办公文档解析（lib/parser/）

6 种格式**全部**返回占位符文本，`ParseResult::success(placeholder, ...)` 伪装成功：

| 格式 | 状态 | 证据 | 缺什么 |
|------|------|------|--------|
| DOCX | ❌ placeholder | docx.mbt:38-54 | ZIP 读取 FFI（word/document.xml） |
| XLSX | ❌ placeholder | xlsx.mbt:41-56 | ZIP 读取 FFI（sharedStrings.xml + sheet*.xml） |
| PPTX | ❌ placeholder | pptx.mbt:38-54 | ZIP 读取 FFI |
| DOC | ❌ placeholder | doc.mbt:32-51 | OLE2 解析（或 antiword/catdoc 外部命令） |
| WPS | ❌ placeholder | wps.mbt:36-48 | 私有二进制格式解析 |
| PDF | ❌ placeholder | pdf.mbt:48-64 | 外部命令执行（pdftotext/pdfinfo）+ 临时文件写入 |

**讽刺的细节**：XML 解析辅助函数全部写好且看起来正确——docx 的 `extract_text_from_xml`/`extract_table_text`、xlsx 的 `build_shared_strings`/`parse_sheet_rows`/`format_as_table`——但因为拿不到 ZIP 里的 XML 内容，**这些函数在生产路径上永远不会被调用**（只有 wbtest 覆盖）。

`ParserManager::parse` 路由本身是完整的（parser_manager.mbt:24-35），`can_parse`/`supported_extensions` 如实上报 8 种扩展名——用户上传 .docx 会"成功"解析出 `[DOCX content placeholder...]` 字符串。

---

## 三、断链与接线缺失（比 stub 更优先修的问题）

### 3.1 ChannelManager 是孤儿代码
`ChannelManager`、`register_adapter`、`send_to` 在 `lib/channel/` 之外零调用（全仓库验证）。渠道配置文件 `~/.mbopenclacky/channels.json` 的加载逻辑存在但没人触发。cmd/ 主程序不启动渠道。

### 3.2 Webhook 接收链路断裂
`POST /api/webhooks/:platform` → `WebhookRegistry.handle` → `Err("No handler registered for platform: ...")`。唯一特殊路径是飞书 URL 验证 challenge（handlers_bridge.mbt:255-264）。没有任何代码把 webhook 事件接到 `ChannelManager::handle_webhook`（那个函数本身写得挺完整，含去重）。

### 3.3 Web 渠道管理 API 与真实 adapter 脱节
- `/api/channels/:id/send`：假成功（handlers_channels.mbt:553 "For now, return success..."）
- `/api/channels/:id/test`：只调 `validate_config()` 检查字段非空，不做真实连通测试（handlers_channels.mbt:336+）——测试显示 "connected" 不代表能连通
- channels_store 是独立的内存/文件存储，与 ChannelConfig/ChannelManager 是两套平行的模型

### 3.4 channel_scaffold 生成 stub 模板
`cmd/channel_scaffold.mbt` 是脚手架命令，生成的 adapter 模板自带 "stub: connect to {platform} API" 注释——设计如此，但意味着新增平台默认就是空壳。

### 3.5 其他不可用模块（全 FFI TODO，零功能）

以下模块的所有文件系统操作都是 TODO FFI，在当前 MoonBit 目标下**完全不可用**：

| 模块 | 文件 | TODO 数 | 影响 |
|------|------|---------|------|
| 备份管理器 | lib/server/backup_manager.mbt | 7 | 读配置、列文件、创建归档、删除旧备份全部不可用 |
| 脚本管理器 | lib/utils/scripts_manager.mbt | 4 | 列出脚本、验证文件存在都是 TODO |
| 媒体输出目录 | lib/media/output_dir.mbt | 8 | 创建目录、列出文件、清理、大小计算都是 TODO |
| 服务发现 | lib/server/discover.mbt | 4 | PID 文件读/写/删、进程存活检查都是 TODO |

其中 `output_dir` 是最关键的——它被 media-gen 等技能调用，意味着媒体生成后无法写入输出目录。

### 3.6 WeCom WebSocket 协议层（与 Discord 网关同类）

`lib/channel/wecom_ws.mbt`（441 行）与 Discord 网关模式相同：协议层完整（帧类型、Subscribe/SendMsg/Ping/Pong/Ack 帧构建、req_id 匹配、ACK 超时判定、三段式分块上传协议），但 `WeComWsState::mark_connected` 只是设标志位——没有真正的 WebSocket 连接。`WeComAdapter::send_text` 构建了帧但丢弃了（wecom.mbt:142-144）。

### 3.7 其他 placeholder

- `lib/skill/reflector.mbt:116`：技能改进逻辑是 placeholder（"real implementation would invoke LLM or code modification"），所有改进请求返回 "(placeholder)" 后缀
- `lib/web/handlers_skills.mbt:639-659`：进化引擎 Handler 是 stub（"pending evolution engine wiring"），触发进化请求和查询历史都返回空

---

## 四、其他发现的待完善点（四大领域之外）

| 位置 | 问题 | 严重度 |
|------|------|--------|
| lib/brand/license.mbt:129,146,187 | license activate/deactivate/heartbeat 的 HTTP 调用 stub（白标授权体系无法联网验证） | 中 |
| lib/brand/crypto.mbt:215 | WASM fallback stubs（native 真实现，属平台降级，非缺陷） | 低 |
| lib/telemetry/telemetry.mbt:110-146 | 遥测上报 HTTP POST 是 placeholder；匿名 ID 用简单哈希冒充 SHA256 | 中 |
| lib/server/scheduler.mbt:24,187,202 | 调度器**持久化是 stub**：不读 schedules.yml、任务不写盘、不删除任务文件——重启即丢；last_run_at 恒 0 | 高 |
| lib/channel/discord.mbt:293 | ISO 8601 时间戳解析缺失（影响所有平台消息时间戳准确性） | 低 |
| lib/channel/http_helper.mbt:44-61 | TokenCache 的过期判断是摆设（"we don't have real time in pure MoonBit"），token 永不过期刷新 | 中 |
| lib/mcp/client.mbt:60 | started_at/last_used_at 恒 0 | 低 |
| lib/channel/weixin.mbt:282 | 限流重试的延迟调度 TODO | 低 |
| lib/web/ext_dispatcher.mbt | extension 未配 command 时返回 stub 响应（设计内 fallback，有警告日志，非缺陷） | 信息 |

**误报排除**（grep "TODO" 命中但实为业务文本，不是未实装标记）：lib/agent/tool_executor.mbt、lib/agent/llm_caller.mbt、lib/tui/* 中的 TODO 命中基本是 todo 管理工具的提示文案与 Ruby 语义注释；lib/server/browser_process.mbt 的 stub 是 WASM 目标的降级实现（native 路径使用 `@process.spawn_orphan` 真实 spawn 子进程）；lib/server/browser_manager.mbt 的 start 是真实现（spawn + JSON-RPC + MCP 握手），web 端 handlers_browser.mbt 有完整接线（start/stop/mcp_call/status），仅配置读取和 ISO 时间戳是 TODO；lib/web/template_processor.mbt 的 placeholder 是模板变量的替换逻辑，不是未实装功能。

---

## 五、完善建议（按优先级）

1. **P0 - 打通接线（收益最大，改动最小）**：在 web server 启动时实例化 ChannelManager、加载 channels.json、注册 adapter、把 WebhookRegistry handler 接到 `ChannelManager::handle_webhook`、让 `/api/channels/:id/send` 真调 `send_to`。这一步不做，所有 adapter 实现都白费。
2. **P0 - 消灭假成功**：Telegram/WeCom/Weixin 的 send_text 在真正实现前应返回 `Err("not implemented")`，而不是 `success: true`。静默丢消息是数据完整性事故。
3. **P1 - MCP stdio transport**：实现子进程 spawn FFI（项目已有 `@async/process` 先例，browser_process.mbt 就是这么管理 chrome-devtools-mcp 子进程的，可复用其模式），并在 send_request 里做请求 ID 关联的响应等待。
4. **P1 - 办公文档解析**：最小可行路径是 DOCX/XLSX/PPTX 共用一个 ZIP 读取 FFI（MoonBit 侧 inflate + central directory 解析，或 shell 调 unzip），PDF 走外部命令 pdftotext。XML 解析函数已就绪，只差"把 XML 从 ZIP 里拿出来"这一步。
5. **P1 - 调度器持久化**：schedules.yml 读 + 任务文件写/删，否则定时任务重启全丢。
6. **P2 - Discord 网关**：依赖 WebSocket 客户端 FFI（与钉钉 Stream Mode、WeCom WebSocket 共用同一底层能力，建议一并规划）。协议层函数已齐，补连接层即可。
7. **P2 - Telegram 发送**：send_text 的 HTTP 调用模式与 Feishu/Discord 完全同构（build payload + http_post_json），半小时工作量，性价比极高。
8. **P3 - 各平台 API 层补全**：edit_message（Discord/飞书，影响流式输出体验）、媒体上传下载、微信 AES
9. **P3 - 基础设施模块**：output_dir（媒体生成落地）、backup_manager（备份归档）、scripts_manager（脚本管理）、discover（服务发现）——这些模块的 FFI TODO 是纯文件操作，实现模式简单（读/写文件 + 目录列表），可批量处理。

## 六、附录：stub 标记统计

- 全仓库 `.mbt` 源文件（不含测试）中 stub/TODO/placeholder 标记约 120 处，分布在 40+ 文件
- 重灾区：lib/channel/（42 处，四大平台接收侧）、lib/parser/（25 处，全部格式）、lib/mcp/（transport 层）、lib/server/scheduler.mbt、lib/server/backup_manager.mbt（7 处）、lib/media/output_dir.mbt（8 处）
- 诚实报错型 stub（返回 Err）约 15 处；假成功型 stub（返回 Ok/success）约 8 处——后者见第五节 P0
- 经对抗性审查补充：output_dir、backup_manager、scripts_manager、discover 四个模块的全 FFI TODO 遗漏已在 3.5 节补充；browser_manager 经核实为真实现（非 stub），已在误报排除中澄清
