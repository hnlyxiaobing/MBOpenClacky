# Web UI 次要功能补全 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: 讨论中  
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: 无  
> **来源差距**: G21 - Session 列表缺少 pinned 优先排序；G22 - Session 列表缺少 q_scope 和 date 过滤参数；G23 - timeout schema 描述错误；G24 - latest_cron_updated_at 始终返回 null  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

当前 Web UI 存在多个次要功能问题：

1. **Session 列表缺少 pinned 优先排序**：Ruby 版本支持 pinned session 排在前面
2. **Session 列表缺少 q_scope 和 date 过滤参数**：Ruby 版本支持按范围和日期过滤
3. **timeout schema 描述错误**：描述写 "default: 30000" 但实际为 60000ms
4. **latest_cron_updated_at 始终返回 null**：Ruby 版本返回最后更新时间

**影响**：用户体验不完善，功能缺失。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "Session 列表无 pinned 排序" | `grep "pinned" lib/web/` | 0 命中 | 确认缺失 |
| "Session 列表无 q_scope 过滤" | `grep "q_scope" lib/web/` | 0 命中 | 确认缺失 |
| "timeout schema 描述错误" | 读取 terminal.mbt | 描述为 "default: 30000" | 确认错误 |
| "latest_cron_updated_at 返回 null" | `grep "latest_cron_updated_at" lib/web/` | 找到函数，返回 null | 确认问题 |

### 详细分析

**Session 列表排序问题**：

当前 Session 列表没有 pinned 优先排序：

```moonbit
fn get_sessions() -> Array[Session] {
  // 直接返回，没有 pinned 排序
  return sessions
}
```

**Ruby 参考**：

```ruby
def get_sessions
  sessions.sort_by { |s| [s.pinned ? 0 : 1, s.updated_at] }
end
```

**Session 列表过滤问题**：

当前没有 q_scope 和 date 过滤参数：

```moonbit
fn get_sessions(q_scope?, date?) -> Array[Session] {
  // 没有过滤逻辑
  return sessions
}
```

**Ruby 参考**：

```ruby
def get_sessions(q_scope: nil, date: nil)
  result = sessions
  result = result.select { |s| s.scope == q_scope } if q_scope
  result = result.select { |s| s.date == date } if date
  result
end
```

**timeout schema 描述错误**：

```moonbit
// lib/tool/terminal.mbt
/// timeout: Int (default: 30000) - Timeout in milliseconds
```

实际默认值是 60000ms。

**latest_cron_updated_at 问题**：

```moonbit
fn latest_cron_updated_at() -> String? {
  return null  // 始终返回 null
}
```

**Ruby 参考**：

```ruby
def latest_cron_updated_at
  CronJob.maximum(:updated_at)&.iso8601
end
```

## 决策 [必填 - 含为什么]

1. **决策 1**：为 Session 列表添加 pinned 优先排序
   - **为什么**：与 Ruby 行为对齐，提升用户体验

2. **决策 2**：为 Session 列表添加 q_scope 和 date 过滤参数
   - **为什么**：与 Ruby 行为对齐，支持高级过滤

3. **决策 3**：修复 timeout schema 描述
   - **为什么**：避免用户困惑

4. **决策 4**：实现 latest_cron_updated_at 功能
   - **为什么**：与 Ruby 行为对齐，支持 cron 功能

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/session_controller.mbt` | 修改 | 添加 pinned 排序和过滤逻辑 |
| `lib/tool/terminal.mbt` | 修改 | 修复 timeout schema 描述 |
| `lib/web/cron_controller.mbt` | 修改 | 实现 latest_cron_updated_at |
| `lib/web/session_controller_wbtest.mbt` | 修改 | 添加测试 |
| `lib/web/cron_controller_wbtest.mbt` | 修改 | 添加测试 |

### 不涉及文件

- `lib/agent/` - Agent 层不变
- `lib/config/` - 配置层不变

## 实施计划 [必填]

### 任务包 1：Session 列表 pinned 排序（预估 0.5 天）

1. 修改 `lib/web/session_controller.mbt` 中的 `get_sessions` 函数：
   ```moonbit
   fn get_sessions() -> Array[Session] {
     sessions.sort_by(fn(s) {
       (if s.pinned { 0 } else { 1 }, s.updated_at)
     })
   }
   ```
2. 编写白盒测试验证排序行为
3. 运行 `moon test lib/web` 确保测试通过

### 任务包 2：Session 列表过滤参数（预估 0.5 天）

1. 修改 `get_sessions` 函数，添加 q_scope 和 date 参数：
   ```moonbit
   fn get_sessions(q_scope?, date?) -> Array[Session] {
     var result = sessions
     if q_scope is Some(scope) {
       result = result.filter(fn(s) { s.scope == scope })
     }
     if date is Some(d) {
       result = result.filter(fn(s) { s.date == d })
     }
     result
   }
   ```
2. 编写白盒测试验证过滤行为
3. 运行 `moon test lib/web` 确保测试通过

### 任务包 3：修复 timeout schema 描述（预估 0.5 天）

1. 修改 `lib/tool/terminal.mbt` 中的 timeout 描述：
   ```moonbit
   /// timeout: Int (default: 60000) - Timeout in milliseconds
   ```
2. 编写白盒测试验证描述正确
3. 运行 `moon test lib/tool` 确保测试通过

### 任务包 4：实现 latest_cron_updated_at（预估 0.5 天）

1. 修改 `lib/web/cron_controller.mbt` 中的 `latest_cron_updated_at` 函数：
   ```moonbit
   fn latest_cron_updated_at() -> String? {
     // 查询最后更新的 cron job
     let latest = cron_jobs.max_by(fn(a, b) { a.updated_at.compare(b.updated_at) })
     latest.map(fn(job) { job.updated_at.to_iso8601() })
   }
   ```
2. 编写白盒测试验证功能
3. 运行 `moon test lib/web` 确保测试通过

## 验收标准 [必填]

- [ ] Session 列表 pinned session 排在前面
- [ ] Session 列表支持 q_scope 过滤
- [ ] Session 列表支持 date 过滤
- [ ] timeout schema 描述正确（default: 60000）
- [ ] latest_cron_updated_at 返回正确的更新时间
- [ ] `moon check lib/web` 0 errors
- [ ] `moon check lib/tool` 0 errors
- [ ] `moon test lib/web` 全部通过
- [ ] `moon test lib/tool` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| Session 排序逻辑错误 | 低 | 充分测试 |
| 过滤参数实现错误 | 低 | 充分测试 |
| latest_cron_updated_at 查询复杂 | 中 | 参考 Ruby 实现 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本 | 基于 gap-analysis 文档创建 |
