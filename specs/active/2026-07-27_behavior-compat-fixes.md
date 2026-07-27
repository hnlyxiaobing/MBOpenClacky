# 行为不兼容修复 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: 讨论中  
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: 无  
> **来源差距**: 行为不兼容项（7 个）  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

当前 MoonBit 版本与 Ruby 版本存在 7 个行为不兼容项：

1. **ConfirmAll 权限模式**：MoonBit 所有工具需确认，Ruby 自动执行所有工具
2. **配置格式**：MoonBit 使用 TOML，Ruby 使用 YAML
3. **memory_update_enabled 默认值**：MoonBit 为 false，Ruby 为 true
4. **Channel API 路径**：MoonBit 使用 PUT /api/channels/:id，Ruby 使用 POST /api/channels/:platform
5. **Skill toggle 方法**：MoonBit 使用 POST /:name/toggle，Ruby 使用 PATCH /:name/toggle
6. **Time machine restore_preview**：MoonBit 使用 POST，Ruby 使用 GET
7. **错误响应格式**：MoonBit 使用嵌套对象，Ruby 使用扁平字符串（已在 T03 处理）

**影响**：从 Ruby 迁移的用户可能遇到兼容性问题。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "ConfirmAll 权限模式不同" | `grep "ConfirmAll" lib/agent/` | 找到权限模式定义 | 确认差异 |
| "配置格式不同" | 检查配置文件 | TOML vs YAML | 确认差异 |
| "memory_update_enabled 默认值不同" | 读取 agent.mbt | `memory_update_enabled: false` | 确认差异 |
| "Channel API 路径不同" | `grep "channels" lib/web/` | 找到路由定义 | 确认差异 |
| "Skill toggle 方法不同" | `grep "toggle" lib/web/` | 找到路由定义 | 确认差异 |
| "Time machine restore_preview 方法不同" | `grep "restore_preview" lib/web/` | 找到路由定义 | 确认差异 |

### 详细分析

**ConfirmAll 权限模式**：

```moonbit
// lib/agent/agent.mbt
pub enum PermissionMode {
  ConfirmAll
  ConfirmSafes
  // ...
}
```

**Ruby 行为**：ConfirmAll 自动执行所有工具，"confirm" 仅指 request_user_feedback。
**MoonBit 行为**：ConfirmAll 所有工具需确认。

**配置格式**：

MoonBit 使用 TOML：
```toml
[agent]
max_tokens = 16384
```

Ruby 使用 YAML：
```yaml
agent:
  max_tokens: 16384
```

**memory_update_enabled 默认值**：

```moonbit
// lib/config/agent.mbt
pub fn AgentConfig::default() -> AgentConfig {
  {
    memory_update_enabled: false,  // Ruby 为 true
    // ...
  }
}
```

**Channel API 路径**：

```moonbit
// lib/web/channel_controller.mbt
router.put("/api/channels/:id", ...)
```

Ruby：
```ruby
post "/api/channels/:platform"
```

**Skill toggle 方法**：

```moonbit
// lib/web/skill_controller.mbt
router.post("/:name/toggle", ...)
```

Ruby：
```ruby
patch "/:name/toggle"
```

**Time machine restore_preview 方法**：

```moonbit
// lib/web/time_machine_controller.mbt
router.post("/restore_preview", ...)
```

Ruby：
```ruby
get "/restore_preview"
```

## 决策 [必填 - 含为什么]

1. **决策 1**：保留 MoonBit 的 ConfirmAll 行为（有意修改）
   - **为什么**：MoonBit 有意修改（Phase 6.3），提高安全性

2. **决策 2**：保留 TOML 配置格式（合理选择）
   - **为什么**：TOML 是 MoonBit 生态的标准格式

3. **决策 3**：将 memory_update_enabled 默认值改为 true
   - **为什么**：与 Ruby 行为对齐，避免用户困惑

4. **决策 4**：保留 MoonBit 的 API 路径和方法（已有前端适配）
   - **为什么**：前端已适配 MoonBit 的 API 设计

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/config/agent.mbt` | 修改 | 将 memory_update_enabled 默认值改为 true |
| `lib/config/agent_wbtest.mbt` | 修改 | 更新测试 |

### 不涉及文件

- `lib/agent/agent.mbt` - ConfirmAll 行为保持不变
- `lib/web/` - API 路径和方法保持不变
- `lib/config/config.mbt` - 配置格式保持不变

## 实施计划 [必填]

### 任务包 1：修复 memory_update_enabled 默认值（预估 0.5 天）

1. 修改 `lib/config/agent.mbt` 第 37 行：
   ```moonbit
   memory_update_enabled: true,  // 从 false 改为 true
   ```
2. 更新 `lib/config/agent_wbtest.mbt` 中的测试
3. 运行 `moon test lib/config` 确保测试通过

## 验收标准 [必填]

- [ ] memory_update_enabled 默认值为 true
- [ ] 用户配置文件可以覆盖默认值
- [ ] `moon check lib/config` 0 errors
- [ ] `moon test lib/config` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 现有用户配置冲突 | 低 | 用户配置文件会覆盖默认值 |
| 自动记忆更新功能未实现 | 中 | 需要 T17（自动记忆更新系统）支持 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：T17（自动记忆更新系统）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本 | 基于 gap-analysis 文档创建 |
