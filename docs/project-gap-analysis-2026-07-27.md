# MBOpenClacky vs OpenClacky 全面对比分析

> 日期: 2026-07-27
> 方法: 源码逐模块对比 + 关键逻辑验证
> 原项目: D:\MoonBit\openclacky\ (Ruby, v1.5.1)
> 当前项目: D:\MoonBit\MBOpenClacky\ (MoonBit, v0.1.0)

---

## 一、确认的 Bug

### P0 — 影响核心功能

| # | 位置 | 问题 | 影响 |
|---|------|------|------|
| 1 | `lib/agent/llm_caller.mbt` | **无重试循环**。HTTP 429/503 直接抛出异常终止整个会话。Ruby 有 10 次重试 + 5s 间隔。 | 任何瞬时网络错误都会导致 agent 运行失败 |
| 2 | `lib/agent/llm_caller.mbt` | **Fallback 状态机为死代码**。`FallbackActive`/`Probing`/`PrimaryOk` 类型存在但从未被转换。 | 主模型不可用时无法自动切换备用模型 |
| 3 | `lib/config/agent.mbt:40` | **compression_threshold 默认 10000**（Ruby 为 150000）。 | 对话稍长就触发压缩，频繁丢失上下文 |
| 4 | `lib/agent/react.mbt:227` | **truncation_count 在非 length 响应时重置为 0**。Ruby 的计数器在整个 task 期间不重置。 | 交替出现截断和正常响应时，永远不会触发 3 次截断保护 |
| 5 | `lib/web/middleware/error_envelope.mbt` | **错误响应格式为嵌套对象** `{ "error": { "status", "message" } }`，Ruby 为扁平字符串 `{ "error": "msg" }`。 | Web UI 前端所有错误提示显示为 `[object Object]` |
| 6 | `lib/mcp/registry.mbt` | **MCP 配置加载为 TODO stub**。`load_from_file` 不解析文件内容，`load_default` 返回空注册表。 | MCP 服务器集成功能完全不可用 |
| 7 | `lib/mcp/http_transport.mbt:40` | HTTP transport 标注 `TODO: FFI implementation needed`，`start()` 仅设置 `is_alive = true`。 | HTTP 类型 MCP 服务器无法通信 |

### P1 — 影响重要功能

| # | 位置 | 问题 | 影响 |
|---|------|------|------|
| 8 | `lib/agent/react.mbt` | **无 Fake Tool Call 检测**。Ruby 检测 5 种 XML 模式（`<invoke name=`等），最多重试 2 次。 | 部分模型在 content 中输出 XML 工具调用时，agent 静默退出 |
| 9 | `lib/agent/` | **无工具输出截断**。Ruby 有 80K 字符上限。 | 大型 glob/grep 结果可能撑爆上下文窗口 |
| 10 | `lib/agent/compressor.mbt` | **压缩失败无回滚**。Ruby 有 `rollback_before` + level 回退。 | 压缩中途失败会损坏对话历史 |
| 11 | `lib/agent/time_machine.mbt` | **Time Machine 未接入工具执行器**。`record_file_before_change` 从未在 write/edit 前被调用。 | 文件快照永远不会被创建，undo 功能无效 |
| 12 | `lib/config/providers.mbt` | **Kimi/Kimi-Coding 标记为 text_only**，Ruby 声明 `vision: true`。 | 发送给 Kimi 的图片被错误降级为磁盘引用 |
| 13 | `lib/config/providers.mbt` | **volcengine-ark 预设完全缺失**（Ruby 有 13 个模型 + 3 个端点变体）。 | 字节跳动 Ark 用户无法使用预设配置 |
| 14 | `lib/skill/` | **SKILL.md frontmatter 连字符不兼容**。Ruby 用 `disable-model-invocation`，MoonBit 解析为 `disable_model_invocation`。 | Ruby 生态的 SKILL.md 文件无法被正确解析 |
| 15 | `lib/web/` | **无 token 级 WS 流式推送**。MoonBit 聚合 StreamChunk 为单条 assistant_message。 | Web UI 无实时打字动画，用户体验退化 |
| 16 | `lib/tool/terminal.mbt` | **`is_multiline_command` 错误拒绝含 `<<` 的命令**。Ruby 仅检查实际换行符。 | `echo "a << b"` 等合法命令被误判为多行 |

### P2 — 影响次要功能

| # | 位置 | 问题 |
|---|------|------|
| 17 | `lib/config/providers.mbt` | MiniMax-M3、MiMo-v2-omni 缺少 vision 能力覆盖 |
| 18 | `lib/config/providers.mbt` | Kimi 模型列表过时（缺 kimi-k3, kimi-k2.7-code, kimi-k2.7-code-highspeed） |
| 19 | `lib/config/providers.mbt` | Qwen 缺少区域端点变体（cn/intl/us） |
| 20 | `lib/config/providers.mbt` | OpenClacky 预设缺少 image_models/video_models/audio_models 声明 |
| 21 | `lib/web/` | Session 列表缺少 pinned 优先排序 |
| 22 | `lib/web/` | Session 列表缺少 `q_scope` 和 `date` 过滤参数 |
| 23 | `lib/tool/terminal.mbt` | timeout schema 描述写 "default: 30000" 但实际为 60000ms |
| 24 | `lib/web/` | `latest_cron_updated_at` 始终返回 null |

---

## 二、功能差距（Ruby 有，MoonBit 缺失）

### 核心 Agent 层

| 功能 | Ruby 实现 | MoonBit 状态 |
|------|-----------|-------------|
| LLM 重试循环 (10次, 5s间隔) | `llm_caller.rb` 完整实现 | 缺失 |
| Fallback 模型激活 + 30min 冷却 | 状态机 + 时间戳检查 | 类型存在，逻辑缺失 |
| 上下文溢出恢复 (BadRequest → pop消息) | 两层策略: 标准(pop 1) + 激进(pop half) | `handle_context_overflow` 存在但从未被调用 |
| 上游截断检测 (空 tool_call args) | `UpstreamTruncatedError` + 一次性提示 | `detect_upstream_truncation` 存在但从未被调用 |
| Fake Tool Call 检测器 | 5 种 XML 模式, 2 次重试 | 完全缺失 |
| 自动记忆更新 (post-task subagent) | 任务完成后 LLM 驱动的白名单记忆持久化 | 仅有手动 memory tool |
| Skill 进化/反思/自动创建 | 3 个协调模块, 迭代阈值门控 | 完全缺失 |
| 项目规则加载 (.clackyrules/AGENTS.md) | `WorkspaceRules.find_main` + 子项目发现 | 占位注释 "Phase 5+" |
| SOUL.md / USER.md 人格加载 | 从 `~/.clacky/agents/` 加载, 截断 1000 字符 | 缺失 |
| Agent Profile 系统提示 | 从 `~/.clacky/agents/<name>/system_prompt.md` 加载 | 硬编码通用提示 |
| 文件/图片输入 (vision/OCR) | `run()` 接受图片+文件, OCR sidecar 降级 | `run()` 仅接受 String |
| Session 上下文注入 (日期/模型/OS) | 每日注入, 模型切换时更新 | 缺失 |
| 空闲压缩 (180s idle trigger) | `idle_compression_timer.rb` | 缺失 |
| 推理内容填充重试 | 检测 "reasoning_content must be passed back" 400 | 缺失 |

### 工具层

| 功能 | Ruby | MoonBit |
|------|------|---------|
| Terminal PTY 持久会话 | 真实 PTY, 会话复用, 消除冷启动 | 每次调用启动新进程 |
| Terminal 交互输入 | session_id + input 支持 | Stub: "not yet supported" |
| Terminal 空闲检测 (10s quiet) | 返回 "waiting" 状态 | 无 |
| Terminal Shell hooks (mise/direnv/nvm) | precmd/chpwd hooks | 无 |
| Terminal 输出清洗 (\r覆写/退格) | 5 步正则管道 | 仅 ANSI CSI/OSC 剥离 |
| Edit/Write diff 预览 | 执行前显示 unified diff | 缺失 |
| 工具结果图片注入 | 截图 → vision follow-up | 缺失 |
| TODO 提醒注入 | 每个非 todo 工具结果附加待办提醒 | 缺失 |

### Server/Web 层

| 功能 | Ruby | MoonBit |
|------|------|---------|
| Extension UI 服务 (/agent_ui/, /ext_ui/) | 完整静态服务 + 模板注入 | 缺失 |
| {{EXT_SCRIPTS}} 注入 | Panel 注册, agent webui 脚本 | 缺失 |
| WS 订阅时活跃状态重放 | 重放 shell stdout buffer | 缺失 |
| Loopback 认证绕过 (真实 TCP peer) | `req.peeraddr` 不可伪造 | 使用 X-Forwarded-For (可伪造) |
| Agent avatar 服务 (/agent_avatar/) | 从 extension 目录提供 | 缺失 |

### 子系统

| 功能 | Ruby | MoonBit |
|------|------|---------|
| Volcengine 媒体提供者 (Seedance) | 完整异步任务 + 轮询 + 多模态参考 | 缺失 |
| Feishu WS Client (实时消息接收) | `ws_client.rb` | 缺失 |
| DingTalk Stream Client | `stream_client.rb` | 缺失 |
| WeCom Media Downloader | `media_downloader.rb` | 缺失 |
| 加密品牌 Skill (AES-GCM) | SKILL.md.enc + 许可证门控解密 | 缺失 |
| 全局用户 Skill 目录 (~/.clacky/skills/) | 完整发现 + 加载 | 缺失 |
| MCP 空闲回收 (300s reaper) | 后台线程 | TODO 占位 |
| MCP 热重载 (保留活跃连接) | 增量 diff | 全量关闭重建 |

---

## 三、行为不兼容（设计决策差异）

| 项目 | Ruby 行为 | MoonBit 行为 | 备注 |
|------|-----------|-------------|------|
| ConfirmAll 权限模式 | 自动执行所有工具（"confirm"仅指 request_user_feedback） | 所有工具需确认 | MoonBit 有意修改(Phase 6.3)，但与原项目语义不同 |
| 配置格式 | YAML (`~/.clacky/config.yml`) | TOML (`~/.mbopenclacky/config.toml`) | 合理选择，但迁移用户需注意 |
| memory_update_enabled 默认值 | true | false | 行为差异 |
| Channel API 路径 | `POST /api/channels/:platform` | `PUT /api/channels/:id` | HTTP 方法不同 |
| Skill toggle 方法 | `PATCH /:name/toggle` | `POST /:name/toggle` | 前端可能发送 PATCH |
| Time machine restore_preview | `GET` | `POST` | 方法不匹配 |
| 错误响应格式 | `{ "error": "string" }` | `{ "error": { "status", "message" } }` | 前端兼容性问题 |

---

## 四、优化建议

### 高优先级

1. **实现 LLM 重试 + Fallback 激活**：这是生产可用性的基本要求。建议实现指数退避重试(最多10次)，连续3次失败后激活 fallback 模型，30分钟冷却后探测主模型恢复。

2. **修复 compression_threshold 默认值**：从 10000 改为 150000，与 Ruby 对齐。当前值会导致几乎每轮对话都触发压缩。

3. **统一错误响应格式**：改为 `{ "error": "message string" }` 以兼容现有前端，或同步修改前端 JS。

4. **实现 MCP 配置加载**：解析 `~/.mbopenclacky/mcp.json`，实现 stdio transport 的进程管理。

5. **接入工具输出截断**：在 tool_executor 中添加 80K 字符上限，超出时截断并附加提示信息。

6. **将 Time Machine 接入 tool_executor**：在 write/edit 工具执行前调用 `record_file_before_change`。

### 中优先级

7. **实现 Fake Tool Call 检测**：添加 5 种 XML 模式匹配，检测到后注入系统提示重试。

8. **修复 truncation_count 逻辑**：改为 task 级别计数，不在正常响应时重置。

9. **实现项目规则加载**：支持 .clackyrules / AGENTS.md / CLAUDE.md / .cursorrules 发现与注入。

10. **Terminal 工具增强**：实现持久会话池（消除冷启动）、交互输入支持、输出清洗改进。

11. **修复 Skill frontmatter 解析**：添加连字符→下划线规范化，兼容 Ruby 生态 SKILL.md。

12. **修复 provider vision 能力**：Kimi/Kimi-Coding 标记 vision:true，补充 MiniMax-M3/MiMo-omni 覆盖。

### 低优先级

13. 实现 WS token 级流式推送（打字动画）
14. 实现 post-task 自动记忆更新
15. 实现 Skill 进化/反思/自动创建
16. 补充 Volcengine 媒体提供者
17. 补充 Feishu/DingTalk 实时消息客户端
18. 实现 Extension UI 静态服务
19. 修复 loopback 认证绕过使用真实 TCP peer 地址
20. 补充 volcengine-ark LLM 预设

---

## 五、数据总结

| 维度 | 数据 |
|------|------|
| 确认 Bug 总数 | 24 (P0: 7, P1: 9, P2: 8) |
| 功能差距项 | 40+ |
| 行为不兼容项 | 7 |
| 优化建议 | 20 |
| MoonBit 独有优势 | 原生 AOT 编译(3.6MB 单文件)、Patch Chain 扩展机制、Memory 注入系统提示、CORS preflight 正确处理、更多 REST 端点(162 vs ~120) |

---

## 六、结论

MBOpenClacky 在 API 覆盖面和架构设计上已达到较高完成度（162 个端点、24 个包、3093 个测试），但在**运行时鲁棒性**方面存在关键短板：LLM 调用无重试/无 fallback、压缩阈值错误、MCP 不可用、Time Machine 未接入。这些问题使得项目在真实网络环境和长时间对话场景下不够稳定。

建议优先修复 P0 级别的 7 个 bug（尤其是 #1 重试循环和 #3 压缩阈值），这两项修复即可显著提升日常使用体验。
