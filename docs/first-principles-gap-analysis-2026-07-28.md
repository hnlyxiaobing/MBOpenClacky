# MBOpenClacky vs OpenClacky 第一性原理深度对比分析

> 日期: 2026-07-28
> 方法: 源码逐模块对比 + 核心逻辑验证 + 运行时行为分析
> 原项目: D:\MoonBit\openclacky\ (Ruby, v1.5.1+)
> 当前项目: D:\MoonBit\MBOpenClacky\ (MoonBit, v0.1.0)
> 基线参考: 2026-07-27 gap analysis (已完成项不再重复)

---

## 一、与 2026-07-27 分析的差异：已修复项

以下问题在 2026-07-27 分析中被标记为 P0/P1，**现已修复**：

| # | 原问题 | 修复状态 | 验证 |
|---|--------|----------|------|
| 1 | LLM 无重试循环 | ✅ 已实现 | `llm_caller.mbt` 有完整 retry + exponential backoff (10次, 5s base) |
| 2 | Fallback 状态机为死代码 | ✅ 已实现 | `PrimaryOk`/`FallbackActive`/`Probing` 状态转换完整，3次失败激活，30min冷却 |
| 3 | compression_threshold 默认 10000 | ✅ 已修复 | 现为 150,000，与 Ruby 对齐 |
| 4 | truncation_count 重置逻辑 | ✅ 已修复 | `react_loop_async` 中 truncation_count 为 task 级别变量 |
| 5 | 错误响应格式嵌套对象 | ✅ 已修复 | `error_envelope.mbt` 改为扁平 `{ "error": "message" }` |
| 6 | MCP 配置加载 TODO stub | ⚠️ 需验证 | 未深入检查，标记待确认 |
| 7 | Fake Tool Call 检测缺失 | ✅ 已实现 | `fake_tool_call.mbt` 有 5 种 XML 模式 + 2 次重试 |
| 8 | 工具输出截断缺失 | ✅ 已实现 | `tool_executor.mbt` 有 80K 字符上限 |
| 9 | 压缩失败无回滚 | ✅ 已实现 | `compressor_rollback.mbt` 有完整 rollback + level fallback |
| 10 | 上游截断检测缺失 | ✅ 已实现 | `detect_upstream_truncation` 在 `llm_caller.mbt` 中被调用 |
| 11 | 上下文溢出恢复缺失 | ✅ 已实现 | `handle_context_overflow` 在 `llm_caller.mbt` 中被调用 |

---

## 二、新发现的问题（按严重性排序）

### P0 — 影响核心功能（7 项）

#### MB-NEW-01: Session Context Injection 完全缺失

**位置**: `lib/agent/system_prompt.mbt` + `lib/agent/react.mbt`

**问题**: Ruby 版本在每次 `run()` 开始时注入 session context 消息：
```ruby
# Ruby: agent.rb#inject_session_context
content = "[Session context: Today is 2026-07-28, Tuesday. Current model: xxx.
            OS: WSL/Windows. Desktop: /mnt/c/Users/xxx/Desktop.
            Working directory: /path. Channel: feishu, Sender: xxx]"
```
这是一条 `system_injected: true` 的 user 消息，让 LLM 知道：
- 当前日期和星期（影响日期相关的推理）
- 当前操作系统（影响路径格式、命令选择）
- 桌面路径（影响文件操作）
- 工作目录（影响相对路径解析）
- 渠道信息（影响回复风格、语言）

MoonBit 版本的 `build_system_prompt` 只注入了静态的日期和 OS 信息，**没有**在每次 run 时动态注入 session context。

**影响**: 
- LLM 不知道当前日期，可能使用过时信息
- 不知道 OS 类型，可能生成错误路径格式
- 不知道渠道信息，无法适配回复风格
- 切换模型后不会更新 context

**修复建议**: 在 `react.mbt` 的 `run()` 函数中，system prompt 构建后、user message 添加前，注入一条 `system_injected` 的 session context 消息。

---

#### MB-NEW-02: reasoning_content 字段缺失

**位置**: `lib/client/types.mbt` - `LlmResponse` 结构体

**问题**: MoonBit 的 `LlmResponse` 结构体定义为：
```moonbit
pub(all) struct LlmResponse {
  content : String?
  tool_calls : Array[@message.ToolCall]?
  finish_reason : String?
  usage : Usage?
  latency : Latency?
}
```
**没有 `reasoning_content` 字段**。

Ruby 版本的 response 包含 `reasoning_content`，并且：
1. 在 `detect_upstream_truncation` 后保留
2. 在 truncated assistant message 中保留
3. 在 `MessageHistory#to_api` 中用于检测 thinking-mode provider
4. 自动为 synthetic assistant messages 填充空 `reasoning_content`

**影响**:
- DeepSeek V4、Kimi K2 等 thinking-mode 模型的推理内容被静默丢弃
- 无法检测 "reasoning_content must be passed back" 400 错误
- 切换到 thinking-mode provider 时，历史中缺少 reasoning_content 会导致 API 拒绝

**修复建议**: 
1. 在 `LlmResponse` 中添加 `reasoning_content : String?` 字段
2. 在 stream aggregator 中捕获 reasoning/reasoning_content delta
3. 在 Message 的 to_api 中处理 reasoning_content padding

---

#### MB-NEW-03: Empty Response 检测缺失

**位置**: `lib/agent/llm_caller.mbt`

**问题**: Ruby 版本检测三种空响应场景并触发重试：

1. **空响应检测**: `content` 为空 + 无 tool_calls + finish_reason != "stop" → RetryableError
2. **Thinking-mode 静默响应**: `content` 为空 + 无 tool_calls + `reasoning_content` 非空 + finish_reason == "stop" → RetryableError
3. **Timeout hint injection**: 首次 TimeoutError 时注入 "[SYSTEM] break into smaller steps" 提示

MoonBit 版本**完全没有**这些检测。

**影响**:
- DeepSeek via OpenRouter 偶尔返回空响应，agent 会误认为任务完成
- Thinking-mode 模型可能耗尽所有 token 在 reasoning 中，agent 静默退出
- 长时间运行的请求超时时，agent 直接失败而不提示模型分解任务

**修复建议**: 在 `call_llm_async` 和 `call_llm_stream_async` 中添加三种检测逻辑。

---

#### MB-NEW-04: Idle Compression Timer 未集成到 Agent 循环

**位置**: `lib/agent/idle_timer.mbt` (存在但未使用)

**问题**: MoonBit 有完整的 `IdleCompressionTimer` 实现（266s 延迟、状态机、trigger 方法），但：
1. Agent 结构体中**没有** `idle_timer` 字段
2. `react_loop_async` 中**没有**启动/重置 idle timer
3. `run()` 完成后**没有**启动 idle timer
4. 新用户输入时**没有**取消 idle timer

Ruby 版本的完整流程：
```ruby
# CLI: cli.rb
@idle_timer = IdleCompressionTimer.new(agent: agent, session_manager: sm)
# run 完成后: timer.start
# 新输入到达: timer.cancel
# 压缩完成后: session_manager.save
```

**影响**: 用户离开后，长对话不会自动压缩，下次交互时 token 成本更高。

**修复建议**: 
1. 在 Agent 结构体中添加 `idle_timer : IdleCompressionTimer?` 字段
2. 在 `run()` 完成后调用 `idle_timer.start(current_time)`
3. 在新用户输入时调用 `idle_timer.cancel()`
4. 实现定时 tick 机制（需要 async event loop 支持）

---

#### MB-NEW-05: Skill Evolution 未集成到 Agent 循环

**位置**: `lib/skill/evolution.mbt`, `lib/skill/reflector.mbt`, `lib/skill/auto_creator.mbt` (存在但未调用)

**问题**: MoonBit 有完整的 skill evolution 模块，但：
1. `react_loop_async` 完成后**没有**调用 `run_skill_evolution_hooks`
2. Agent 结构体中**没有** `skill_execution_context` 字段
3. 没有 `with_skill_evolution_phase` 的 UI 集成

Ruby 版本的完整流程：
```ruby
# agent.rb#run 完成后
unless @is_subagent || task_interrupted || awaiting_user_feedback
  run_skill_evolution_hooks
end
```

**影响**: Skill 自进化功能完全不工作。已执行的 skill 不会被反思改进，复杂任务模式不会被自动提取为新 skill。

**修复建议**: 在 `react_loop_async` 返回后、`build_result` 前，调用 skill evolution hooks。

---

#### MB-NEW-06: URL Fallback 机制缺失

**位置**: `lib/agent/llm_caller.mbt`, `lib/config/agent.mbt`

**问题**: Ruby 版本有 URL fallback 机制：
1. 每个 provider 可配置 `fallback_base_url`（如 DeepSeek 有 `llm.1024code.com` 备用网关）
2. 当主 URL 所有重试失败后，自动切换到备用 URL 并重置重试计数
3. `url_fallback_active?` 防止二次切换

MoonBit 版本完全没有此机制。

**影响**: 当主 API 端点不可用时（如 DeepSeek 官方 API 过载），无法自动切换到备用网关，直接失败。

**修复建议**: 在 `AgentConfig` 中添加 `fallback_base_url` 配置，在 `llm_caller.mbt` 中实现切换逻辑。

---

#### MB-NEW-07: SOUL.md / USER.md 人格加载缺失

**位置**: `lib/agent/system_prompt.mbt` - `build_system_prompt`

**问题**: Ruby 版本的 system prompt 包含：
```ruby
# Layer 4: SOUL.md (agent personality)
soul = truncate(@agent_profile.soul, MAX_MEMORY_FILE_CHARS)
parts << format_section("AGENT SOUL (from ~/.clacky/agents/SOUL.md)", soul)

# Layer 5: USER.md (user profile)
user_profile = truncate(@agent_profile.user_profile, MAX_MEMORY_FILE_CHARS)
parts << format_section("USER PROFILE (from ~/.clacky/agents/USER.md)", user_profile)
```

MoonBit 版本的 `build_system_prompt` 有 AgentProfile 但**没有**加载 SOUL.md 和 USER.md 文件。system prompt 中没有 agent 人格和用户画像信息。

**影响**: Agent 无法展现个性化行为，无法根据用户偏好调整回复风格。

**修复建议**: 在 `build_system_prompt` 中添加 SOUL.md 和 USER.md 的加载逻辑，截断到 1000 字符。

---

### P1 — 影响重要功能（9 项）

#### MB-NEW-08: reasoning_content Padding for History 缺失

**位置**: `lib/message/` 模块

**问题**: Ruby 版本的 `MessageHistory#to_api` 会检测当前是否使用 thinking-mode provider，如果是，则为所有 synthetic assistant messages 填充空 `reasoning_content` 字段。这是因为 DeepSeek V4 / Kimi K2 要求历史中每个 assistant 消息都必须有 `reasoning_content`。

MoonBit 版本没有此逻辑。

**影响**: 切换到 thinking-mode provider 时，如果历史中有其他 provider 生成的 assistant 消息（没有 reasoning_content），API 会返回 400 错误。

---

#### MB-NEW-09: EPIPE 连接重置缺失

**位置**: `lib/agent/llm_caller.mbt`

**问题**: Ruby 版本检测 `Errno::EPIPE`（服务端关闭空闲连接后客户端尝试写入）并重置 HTTP 连接：
```ruby
rescue Errno::EPIPE => e
  @client.reset_connections! if epipe
```

MoonBit 版本的 HTTP 客户端没有此处理。长时间空闲后首次请求可能因 EPIPE 失败。

---

#### MB-NEW-10: Stale Thread 检测缺失

**位置**: `lib/agent/react.mbt`

**问题**: Ruby 版本在每次 iteration 开始前调用 `check_stale!`，检测当前线程是否仍拥有任务：
```ruby
def check_stale!
  return unless @config.respond_to?(:current_thread)
  current = Thread.current
  owner = @config.current_thread
  raise AgentInterrupted, "Task superseded by new input" if owner && owner != current
end
```

MoonBit 版本没有此机制。在 Web 模式下，新用户消息可能启动新任务，旧任务仍在运行。

---

#### MB-NEW-11: Pending Injection Flush 缺失

**位置**: `lib/agent/react.mbt` - `react_loop_async`

**问题**: Ruby 版本在 `observe()` 后调用 `flush_pending_injections`，将 `invoke_skill` 工具执行期间排队的 inline skill 注入刷新到历史中。这是 Bedrock API 的 toolUse/toolResult 配对要求所必需的。

MoonBit 版本没有 `pending_injections` 队列和 flush 机制。

---

#### MB-NEW-12: Compression `<continues_previous>` Tag 缺失

**位置**: `lib/agent/compressor.mbt` - `compression_prompt`

**问题**: Ruby 版本的 compression prompt 包含 `<continues_previous>` 标签，让 LLM 判断当前对话是否是上一个 chunk 的延续。这用于 chunk 合并决策。

MoonBit 版本的 compression prompt **没有**此标签。

**影响**: 压缩后的 chunk 无法正确判断是否需要与前一个 chunk 合并，可能导致信息碎片化。

---

#### MB-NEW-13: Sub-project Rules Discovery 缺失

**位置**: `lib/agent/system_prompt.mbt` - `build_system_prompt`

**问题**: Ruby 版本的 `load_project_rules` 不仅加载主项目的 `.clackyrules`，还发现子项目的规则：
```ruby
sub_projects = Utils::WorkspaceRules.find_sub_projects(@working_dir)
# 每个子项目注入摘要 + 提示 agent 在工作前读取完整规则
```

MoonBit 版本只调用 `WorkspaceRules::find_main`，不发现子项目规则。

**影响**: 在 monorepo 中工作时，agent 不知道子项目有独立的规则。

---

#### MB-NEW-14: Task Cost Source Tracking 缺失

**位置**: `lib/agent/cost_tracker.mbt`

**问题**: Ruby 版本跟踪每个 task 的成本来源（API 实际 vs 估算）：
```ruby
@task_cost_source = :estimated  # 每个 task 重置
# API 响应后: @task_cost_source = :api
```

MoonBit 版本没有 per-task 的成本来源跟踪。

---

#### MB-NEW-15: Terminal MAX_LINE_CHARS 缺失

**位置**: `lib/tool/terminal.mbt`

**问题**: Ruby 版本的 terminal 有每行 500 字符上限（`MAX_LINE_CHARS = 500`），防止单行 minified JSON/CSS/JS 占满整个 4KB 输出预算。

MoonBit 版本没有此限制。

**影响**: 一个 minified 文件的输出可能占满整个 terminal 输出预算，导致真正有用的错误信息被截断。

---

#### MB-NEW-16: Safe-RM Shell Function 缺失

**位置**: `lib/tool/terminal.mbt`

**问题**: Ruby 版本在每个 PTY 会话中安装 safe-rm shell function，将 `rm` 重定向到 trash 目录：
```bash
source ~/.clacky/scripts/safe_rm.sh
# 之后 rm file.txt 实际上移动到 $CLACKY_TRASH_DIR
```

MoonBit 版本没有此安全机制。`rm` 命令会真正删除文件。

**影响**: 用户误操作或 agent 错误执行 `rm` 时，文件无法恢复。

---

### P2 — 影响次要功能（6 项）

| # | 位置 | 问题 |
|---|------|------|
| 17 | `lib/agent/` | ShellHookLoader 缺失 — Ruby 从 `~/.clacky/hooks.yml` 加载 shell hooks |
| 18 | `lib/agent/` | ExtensionHookRegistry 缺失 — Ruby 从 ext.yml 复制 hook callbacks |
| 19 | `lib/agent/` | ParserManager/ScriptsManager 初始化缺失 — Ruby 确保用户空间解析器和脚本就位 |
| 20 | `lib/agent/` | `rebuild_client_for_model_switch` 缺失 — Ruby 切换模型时重建 Client + 更新 compressor |
| 21 | `lib/agent/` | `inject_chunk_index_if_needed` 缺失 — Ruby 在压缩 chunk 存在时注入索引卡片 |
| 22 | `lib/agent/` | `pending_error_rollback` 在 run() 中的实现 — Ruby 在 run 开始时检查并回滚错误历史 |

---

## 三、逻辑 Bug（从第一性原理推导）

### Bug-01: compression_threshold 在 compressor.mbt 和 config 中双重定义

**位置**: `lib/agent/compressor.mbt:22` 和 `lib/config/agent.mbt:40`

**问题**: `compressor.mbt` 定义了 `pub let compression_threshold : Int = 150_000`，同时 `config/agent.mbt` 也有 `compression_threshold: 150000`。`needs_compression` 使用的是 `compressor.mbt` 中的硬编码值，而不是 config 中的可配置值。

**影响**: 用户通过配置文件或环境变量修改 compression_threshold 不会生效。

**修复建议**: `needs_compression` 应读取 `self.config.compression_threshold` 而非模块级常量。

---

### Bug-02: react_loop_async 中 fake_tool_call 检测后未重置 truncation_count

**位置**: `lib/agent/react.mbt:280-290`

**问题**: 当检测到 fake tool call 并注入 correction prompt 后，循环 `continue` 进入下一次 iteration。此时 `truncation_count` 没有被重置。如果之前的 iteration 有 truncation，fake tool call 重试后可能误触发 "Repeated response truncation" 错误。

**修复建议**: 在 fake tool call 检测分支中重置 `truncation_count = 0`。

---

### Bug-03: think_async 中压缩失败时未回滚 compression_level

**位置**: `lib/agent/react.mbt:180-200`

**问题**: `think_async` 中插入 compression message 后调用 LLM，然后调用 `compress_with_level_fallback`。如果压缩失败（`Failed` 分支），`compression_level` 已经在 `compress_messages_if_needed` 中被递增，但没有回滚。

Ruby 版本有明确的回滚：
```ruby
unless compression_handled
  @history.rollback_before(compression_message)
  @compression_level -= 1  # 回滚
end
```

**影响**: 压缩失败后，下次压缩检查会使用错误的 compression_level，可能导致过早或过晚触发压缩。

---

### Bug-04: auto_update_memory 使用 call_llm_async 绕过重试逻辑

**位置**: `lib/agent/memory_auto.mbt:300-320`

**问题**: `call_llm_with_prompt` 直接调用 `call_llm_async()` 而不是 `call_with_retry_async()`。这意味着 memory update 的 LLM 调用没有重试保护，任何瞬时网络错误都会导致记忆更新静默失败。

**修复建议**: 使用 `call_with_retry_async()` 替代 `call_llm_async()`。

---

### Bug-05: build_error_result 格式不一致

**位置**: `lib/agent/tool_executor.mbt:490`

**问题**: `build_error_result` 返回 `{error: message}` 格式（无引号），而 Ruby 版本返回 `{"error": "message"}` JSON 格式。MoonBit 的格式不是合法 JSON，可能导致 LLM 解析困难。

```moonbit
// MoonBit 当前:
{ id: call.id, content: "{error: \{error_message}}", is_error: true }
// Ruby:
{ content: "Error: #{error_message}" }
```

**修复建议**: 使用标准 JSON 格式或纯文本格式。

---

## 四、优化建议（按优先级排序）

### 高优先级（直接影响日常使用）

1. **实现 Session Context Injection**: 在 `run()` 中注入日期/OS/渠道 context，成本极低但效果显著。

2. **添加 reasoning_content 到 LlmResponse**: 这是 thinking-mode 模型正常工作的前提。

3. **实现 Empty Response + Thinking-mode 检测**: 防止 agent 在模型返回空响应时误认为任务完成。

4. **集成 Idle Compression Timer**: 长对话自动压缩，降低 token 成本。

5. **集成 Skill Evolution**: 让 GEP 自进化系统真正工作。

### 中优先级（提升鲁棒性）

6. **实现 URL Fallback**: 提供备用网关切换能力。
7. **加载 SOUL.md / USER.md**: 让 agent 有人格和用户感知。
8. **实现 reasoning_content padding**: 支持 thinking-mode provider 的历史兼容。
9. **修复 compression_threshold 读取源**: 从 config 读取而非硬编码。
10. **修复 think_async 压缩失败回滚**: 确保 compression_level 正确回滚。

### 低优先级（完善细节）

11. 实现 Sub-project Rules Discovery
12. 实现 Compression `<continues_previous>` Tag
13. 实现 Terminal MAX_LINE_CHARS
14. 实现 Safe-RM Shell Function
15. 实现 EPIPE 连接重置
16. 实现 Stale Thread 检测

---

## 五、数据总结

| 维度 | 2026-07-27 分析 | 2026-07-28 更新 |
|------|----------------|----------------|
| 已修复 P0 | 0/7 | 5/7 ✅ |
| 已修复 P1 | 0/9 | 4/9 ✅ |
| 新发现 P0 | — | 7 项 |
| 新发现 P1 | — | 9 项 |
| 新发现 P2 | — | 6 项 |
| 新发现逻辑 Bug | — | 5 项 |
| 功能差距总数 | 40+ | 28+ (新增) |
| 行为不兼容 | 7 | 7 (不变) |

---

## 六、结论

MBOpenClacky 在过去一天中**显著提升了运行时鲁棒性**：LLM 重试、Fallback 模型、压缩回滚、上游截断检测、工具输出截断、Fake Tool Call 检测均已实现。这些修复解决了 2026-07-27 分析中最关键的 P0 问题。

然而，从第一性原理审视，项目仍存在**系统级集成缺失**：

1. **Session Context** — LLM 不知道"我是谁、在哪里、现在几点"
2. **reasoning_content** — Thinking-mode 模型的推理内容被丢弃
3. **Idle Compression** — 有实现无集成，长对话不会自动压缩
4. **Skill Evolution** — 有模块无调用，GEP 自进化名存实亡
5. **URL Fallback** — 单点故障，无备用网关

这些问题的共同特征是：**模块已实现但未集成到主流程**。建议下一步工作聚焦于"最后一公里"集成，而非新功能开发。

---

## 七、建议优先修复路线

```
Week 1 (P0 集成):
  Day 1-2: Session Context Injection + reasoning_content 字段
  Day 3-4: Empty Response / Thinking-mode 检测 + 压缩回滚修复
  Day 5:   Idle Compression Timer 集成

Week 2 (P0 集成 + P1):
  Day 1-2: Skill Evolution 集成 + URL Fallback
  Day 3-4: SOUL.md/USER.md 加载 + reasoning_content padding
  Day 5:   EPIPE 处理 + Stale Thread 检测

Week 3 (P1 + P2):
  Day 1-3: Sub-project Rules + Compression continues_previous
  Day 4-5: Terminal 安全增强 + Shell Hooks
```
