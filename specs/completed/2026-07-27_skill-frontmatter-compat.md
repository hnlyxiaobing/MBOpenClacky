# SKILL.md frontmatter 兼容性 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: completed (verified)  
> **验证日期**: 2026-07-27（对抗性审查通过 + moon test 全绿）
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: 无  
> **来源差距**: G14 - SKILL.md frontmatter 连字符不兼容  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

当前 `lib/skill/loader.mbt` 中的 `parse_frontmatter` 函数直接使用原始的 key，没有将连字符（`-`）转换为下划线（`_`）。Ruby 生态的 SKILL.md 文件使用 `disable-model-invocation`，而 MoonBit 解析为 `disable_model_invocation`，导致 Ruby 生态的 SKILL.md 文件无法被正确解析。

**影响**：从 Ruby 生态迁移的 SKILL.md 文件无法被 MoonBit 版本正确加载。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "frontmatter 解析无连字符处理" | 读取 `lib/skill/loader.mbt` 第 4-60 行 | `parse_frontmatter` 直接使用原始 key | 确认缺失 |
| "MoonBit 使用下划线" | `grep "disable_model_invocation" lib/skill/` | 11 命中 | 确认：MoonBit 使用下划线 |

### 详细分析

**当前 frontmatter 解析**（`lib/skill/loader.mbt`）：

```moonbit
pub fn parse_frontmatter(content : String) -> (Map[String, String], String) {
  // ...
  match line.find(":") {
    Some(colon_pos) => {
      let key_raw = line[0:colon_pos].trim().to_owned()
      let value_raw = line[colon_pos + 1:].trim().to_owned()
      if !key_raw.is_empty() {
        // 直接使用 key_raw，没有连字符转换
        fields[key_raw] = value_raw
      }
    }
  }
  // ...
}
```

**问题**：如果 SKILL.md 中使用 `disable-model-invocation: true`，解析后 key 是 `disable-model-invocation`，而不是 `disable_model_invocation`。

**Ruby 生态 SKILL.md 示例**：

```yaml
---
name: example-skill
description: Example skill
disable-model-invocation: true
user-invocable: false
---
```

**MoonBit 期望的格式**：

```yaml
---
name: example-skill
description: Example skill
disable_model_invocation: true
user_invocable: false
---
```

## 决策 [必填 - 含为什么]

1. **决策 1**：在 `parse_frontmatter` 中将连字符转换为下划线
   - **为什么**：保持与 Ruby 生态的兼容性

2. **决策 2**：转换逻辑应用于所有 key
   - **为什么**：避免为每个字段单独处理

3. **决策 3**：保留原始 key 作为备份（可选）
   - **为什么**：方便调试，但不用于实际解析

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/skill/loader.mbt` | 修改 | 修改 `parse_frontmatter` 函数 |
| `lib/skill/loader_wbtest.mbt` | 修改 | 添加连字符转换测试 |

### 不涉及文件

- `lib/skill/skill.mbt` - Skill 结构体不变
- `lib/skill/skill_registry.mbt` - 注册表不变

## 实施计划 [必填]

### 任务包 1：修改 parse_frontmatter 函数（预估 0.5 天）

1. 在 `parse_frontmatter` 中添加连字符转换逻辑：
   ```moonbit
   let key_normalized = key_raw.replace("-", "_")
   fields[key_normalized] = value_raw
   ```
2. 确保所有 key 都经过转换
3. 编写白盒测试验证转换行为：
   - 输入 `disable-model-invocation` → 输出 `disable_model_invocation`
   - 输入 `user-invocable` → 输出 `user_invocable`
   - 输入 `name` → 输出 `name`（无连字符）
4. 运行 `moon test lib/skill` 确保测试通过

### 任务包 2：集成测试（预估 0.5 天）

1. 测试场景：Ruby 生态 SKILL.md → 正确解析
2. 测试场景：MoonBit 生态 SKILL.md → 正确解析
3. 测试场景：混合格式 → 正确解析
4. 验证 `moon check` 和 `moon test` 通过

## 验收标准 [必填]

- [ ] `disable-model-invocation` 解析为 `disable_model_invocation`
- [ ] `user-invocable` 解析为 `user_invocable`
- [ ] 无连字符的 key 保持不变
- [ ] Ruby 生态 SKILL.md 可以正确加载
- [ ] MoonBit 生态 SKILL.md 可以正确加载
- [ ] `moon check lib/skill` 0 errors
- [ ] `moon test lib/skill` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 连字符转换导致 key 冲突 | 低 | 检查是否有 `disable-model-invocation` 和 `disable_model_invocation` 同时存在 |
| 性能影响 | 低 | 字符串替换开销很小 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本 | 基于 gap-analysis 文档创建 |
