# LLM 重试循环 + Fallback 激活 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: 讨论中  
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: 无  
> **来源差距**: G01 - LLM 调用无重试，Fallback 状态机为死代码  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

当前 `lib/agent/llm_caller.mbt` 存在两个关键问题：

1. **无重试循环**：HTTP 429/5xx 错误直接抛出 `RetryableError` 终止整个会话。Ruby 实现有 10 次重试 + 5 秒间隔，而 MoonBit 版本完全没有重试逻辑。

2. **Fallback 状态机为死代码**：`FallbackState` 类型定义存在（`PrimaryOk`/`FallbackActive`/`Probing`），但没有任何代码执行状态转换。当主模型不可用时，无法自动切换到备用模型。

**影响**：任何瞬时网络错误或模型服务过载都会导致 agent 运行失败，用户体验极差。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "无重试循环" | `grep -r "RetryableError" lib/agent/` | 6 命中，仅在 llm_caller.mbt 中 raise | 确认缺失：无 catch/retry 逻辑 |
| "Fallback 为死代码" | `grep -r "FallbackState" lib/agent/` | 类型定义在 agent.mbt，无状态转换 | 确认缺失：状态机未实现 |
| "重试常量已定义" | 读取 llm_caller.mbt 第 9-17 行 | `retries_before_fallback=3`, `max_retries_on_fallback=5`, `fallback_cooldown_seconds=1800` | 确认存在：常量已定义但未使用 |

### 详细分析

**当前 LLM 调用流程**（`llm_caller.mbt`）：

```
call_llm_async()
  → 构建请求
  → http_post_async()
  → 成功 → 返回 response
  → HTTP 429/5xx → raise RetryableError
  → 其他错误 → raise BadRequestError/AgentError
```

**问题**：`RetryableError` 被 raise 后，没有任何代码捕获它进行重试。错误直接传播到 `react_loop_async`，导致整个 run 失败。

**Fallback 状态机**（`agent.mbt`）：

```moonbit
pub(all) enum FallbackState {
  PrimaryOk
  FallbackActive(Int)  // Int = retry_count
  Probing
} derive(Eq, Debug)
```

状态转换规则在注释中描述：
- PrimaryOk → FallbackActive: 连续 3 次 RetryableError
- FallbackActive → Probing: 冷却期（30 分钟）到期
- Probing → PrimaryOk: 探测调用成功
- Probing → FallbackActive: 探测调用失败

但这些转换从未被实现。

**Ruby 参考实现**（`openclacky/lib/clacky/agent/llm_caller.rb`）：

```ruby
def call_with_retry
  retries = 0
  begin
    call_primary_or_fallback
  rescue RetryableError => e
    retries += 1
    if retries >= MAX_RETRIES
      activate_fallback if consecutive_failures >= RETRIES_BEFORE_FALLBACK
      raise
    end
    sleep(retry_delay(retries))
    retry
  end
end
```

## 决策 [必填 - 含为什么]

1. **决策 1**：实现指数退避重试（最多 10 次，基础延迟 5 秒，最大 60 秒）
   - **为什么**：与 Ruby 行为对齐，指数退避避免在服务过载时加剧压力
   
2. **决策 2**：连续 3 次 RetryableError 后激活 Fallback 模型
   - **为什么**：与 Ruby 行为对齐，3 次是合理的阈值，避免单次故障就切换
   
3. **决策 3**：Fallback 激活后 30 分钟冷却期，到期后探测主模型恢复
   - **为什么**：与 Ruby 行为对齐，30 分钟足够服务恢复，探测机制避免永久停留在 Fallback

4. **决策 4**：在 `llm_caller.mbt` 中实现重试循环，在 `react_loop_async` 中集成 Fallback 状态机
   - **为什么**：职责分离，重试逻辑在 LLM 调用层，Fallback 状态管理在 Agent 层

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/llm_caller.mbt` | 修改 | 添加重试循环逻辑 |
| `lib/agent/react.mbt` | 修改 | 集成 Fallback 状态机转换 |
| `lib/agent/agent.mbt` | 修改 | 添加 Fallback 相关辅助方法 |
| `lib/agent/llm_caller_wbtest.mbt` | 新建 | 重试和 Fallback 的白盒测试 |

### 不涉及文件

- `lib/client/` - HTTP 客户层不变
- `lib/config/` - 配置层不变（常量已在 llm_caller.mbt 中定义）

## 实施计划 [必填]

### 任务包 1：重试循环实现（预估 1 天）

1. 在 `llm_caller.mbt` 中创建 `call_with_retry_async` 函数
2. 实现指数退避延迟计算：`min(base_delay * 2^retries, max_delay)`
3. 捕获 `RetryableError`，计数重试次数
4. 达到最大重试次数（10）后，抛出最终错误
5. 添加 `clear_llm_error` 调用（重试成功时清除错误记录）
6. 编写白盒测试验证重试行为

### 任务包 2：Fallback 状态机集成（预估 1 天）

1. 在 `agent.mbt` 中添加 `record_retryable_failure` 方法
2. 实现状态转换逻辑：
   - PrimaryOk → FallbackActive：连续失败计数达到 3
   - FallbackActive → Probing：冷却期（30 分钟）到期
   - Probing → PrimaryOk：探测成功
   - Probing → FallbackActive：探测失败
3. 在 `react_loop_async` 中调用状态机更新
4. 实现模型切换逻辑（切换到 `fallback_model` 配置）
5. 编写白盒测试验证状态转换

### 任务包 3：集成测试（预估 0.5 天）

1. 测试场景：瞬时网络错误 → 重试成功 → 继续正常运行
2. 测试场景：持续失败 → 触发 Fallback → 使用备用模型
3. 测试场景：Fallback 模式 → 冷却期到期 → 探测主模型恢复
4. 验证 `moon check` 和 `moon test` 通过

## 验收标准 [必填]

- [ ] HTTP 429/5xx 错误触发重试，最多 10 次
- [ ] 重试使用指数退避（5s, 10s, 20s, ..., 最大 60s）
- [ ] 重试成功后清除错误记录，继续正常运行
- [ ] 连续 3 次 RetryableError 后激活 Fallback 模型
- [ ] Fallback 模型从 `config.fallback_model` 读取
- [ ] Fallback 激活后 30 分钟冷却期
- [ ] 冷却期到期后探测主模型恢复
- [ ] 探测成功 → 切回主模型
- [ ] 探测失败 → 继续使用 Fallback，重置冷却期
- [ ] `moon check lib/agent` 0 errors
- [ ] `moon test lib/agent` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 重试期间阻塞事件循环 | 中 | 使用 async/await，确保不阻塞 |
| Fallback 模型配置为空 | 低 | 检查 `fallback_model` 是否为空字符串，为空时跳过切换 |
| 冷却期时间戳存储 | 低 | 使用 Agent 结构体字段存储最后失败时间 |
| 与现有错误处理冲突 | 中 | 保留原有错误类型，仅在 RetryableError 时重试 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：T06（工具输出截断）可能依赖本 spec 的重试机制

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本 | 基于 gap-analysis 文档创建 |
