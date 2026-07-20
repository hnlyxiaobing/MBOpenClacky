# agent — ReAct 循环 · 会话管理 · 成本追踪

> 路径: `lib/agent/` · 42 个 .mbt（32 源 + 10 测试）+ 1 .c · 项目核心调度包

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `Agent::run(user_input)` | `react.mbt` | **主入口** — 启动 ReAct 循环（Think→Act→Observe） |
| `Agent::new(...)` | `agent.mbt` | 构造 Agent 实例，注入 client/config/tool_registry |
| `restore_session_enhanced(config, data)` | `session_restore.mbt` | 从持久化 SessionData 恢复 Agent 状态 |
| `list_sessions()` / `load_session(id)` | `session_store.mbt` | 会话列表/加载 |

## 关键类型

### 核心 Struct
- **`Agent`** — 中央调度器，持有 client、config、tool_registry、skill_registry、memory_store、todo_manager、agent_pool、history、hook_manager
- **`SessionData`** — 会话持久化 DTO（session_id, messages, stats, time_machine, channel_info...）
- **`RunResult`** — run() 返回值（status, session_id, iterations, total_cost_usd, cache_stats）

### 状态枚举
- **`AgentStatus`** — `Idle | Running | WaitingForInput | Error | Completed`
- **`AgentSource`** — `Manual | Cron | Channel`
- **`RunStatus`** — `Success | Error | Interrupted`
- **`FallbackState`** — `PrimaryOk | FallbackActive(Int) | Probing`（模型降级状态机）

### 子系统
- **`HookManager`** + **`HookEvent`** — 生命周期事件总线（20+ 事件类型）
- **`MemoryStore`** / **`MemoryEntry`** — 持久化记忆（5 类：UserPreference/ProjectInfo/TaskSummary/ExpertKnowledge/LearnedSkill）
- **`TodoManager`** / **`TodoItem`** — 任务依赖图（支持 blocked_by）
- **`AgentPool`** / **`SubAgentHandle`** — 子 Agent 池（max_running/max_idle 控制）
- **`TimeMachineState`** / **`TaskSnapshot`** — 时间机器（文件快照 undo/redo）
- **`IdleCompressionTimer`** — 空闲压缩触发器
- **`AgentProfile`** / **`ProfileSpec`** — Agent 配置文件抽象（支持 system_prompt/skill_whitelist）
- **`PatchChain`** / **`PatchRule`** / **`PatchAction`** — 工具执行补丁系统（每次工具调用前后评估，`Allow`/`Block(reason)`，支持声明式模式匹配与命令式 shell hook）

### 压缩体系
- **`CompressionConfig`** / **`CompressionContext`** / **`CompressionStats`** — 上下文压缩参数与统计
- 关键常量: `message_count_threshold`, `max_recent_messages`, `target_compressed_tokens`

## 核心调用链

```
Agent::run(user_input)
  ├─ build_system_prompt()           # system_prompt.mbt — 组装系统提示词
  ├─ react_loop()                    # react.mbt
  │   ├─ think() → call_llm()       # llm_caller.mbt — 调用 LLM API
  │   │   └─ client.send_request()  # → lib/client
  │   ├─ act() → execute_single_tool()  # tool_executor.mbt
  │   │   ├─ is_safe_operation()    # security.mbt — 权限检查
  │   │   └─ tool.execute()         # → lib/tool
  │   └─ observe() → 追加 tool result 到 history
  ├─ compress_messages_if_needed()   # compressor.mbt — 上下文压缩
  └─ handle_context_overflow()       # 溢出处理（Standard/Aggressive）
```

## 文件职责分组

| 文件组 | 文件 | 职责 |
|--------|------|------|
| 核心循环 | `agent.mbt`, `react.mbt`, `llm_caller.mbt`, `tool_executor.mbt` | ReAct 循环、LLM 调用、工具执行 |
| 会话管理 | `session_data.mbt`, `session_manager.mbt`, `session_store.mbt`, `session_restore.mbt`, `session_serializer.mbt` | 会话 CRUD、恢复、fork、ZIP 导出/导入（依赖 `lib/zip`） |
| 补丁系统 | `patch_chain.mbt` | PatchChain/PatchRule/PatchAction、工具调用前后拦截（Allow/Block） |
| 压缩体系 | `compressor.mbt`, `compressor_chunk.mbt`, `compressor_helper.mbt` | 上下文压缩、分块摘要 |
| 成本追踪 | `cost_tracker.mbt`, `status.mbt` | 费用计算、状态管理 |
| 记忆系统 | `memory.mbt`, `memory_types.mbt` | 持久化记忆存储 |
| 任务管理 | `todo.mbt`, `todo_types.mbt` | 任务依赖图 |
| 时间机器 | `time_machine.mbt`, `time_machine_types.mbt` | 文件快照 undo/redo |
| Hook 系统 | `hook.mbt` | 生命周期事件总线 |
| 子 Agent | `subagent.mbt`, `agent_pool.mbt`, `agent_result.mbt` | 子 Agent 编排 |
| Profile | `profile.mbt`, `profile_types.mbt`, `default_profiles.mbt` | Agent 配置文件 |
| 技能管理 | `skill_manager.mbt` | Agent 技能加载/查询/摘要方法 |
| 系统提示 | `system_prompt.mbt` | 系统提示词组装 |
| 空闲压缩 | `idle_timer.mbt` | 空闲压缩定时器 |
| 时间 | `time.mbt`, `time_stub.c` | 时间工具（C FFI） |

## 外部依赖

- `lib/client` — LLM API 调用
- `lib/config` — AgentConfig、ModelConfig
- `lib/message` — Message、ToolCall 消息类型
- `lib/tool` — ToolRegistry、Tool 执行
- `lib/skill` — SkillRegistry、技能加载
- `lib/zip` — 会话 ZIP 导出/导入（`session_serializer.mbt`）
- `moonbitlang/x/fs` — 文件系统操作
- `moonbitlang/core/json` — JSON 序列化

## 风险点

1. **全局会话目录** — `ensure_sessions_dir()` 使用固定路径 `~/.mbopenclacky/sessions/`，并发写入可能冲突
2. **压缩精度** — 压缩后 token 估算使用 `estimate_token_count()`（简单字符除法），与实际 tokenizer 有偏差
3. **Fallback 状态机** — `FallbackState` 转换依赖 `retries_before_fallback` / `fallback_cooldown_seconds` 常量，边界条件复杂
4. **TimeMachine 文件快照** — 大文件快照可能占用大量磁盘空间
5. **Hook 同步回调** — `HookManager.emit()` 是同步调用，耗时回调会阻塞 ReAct 循环
