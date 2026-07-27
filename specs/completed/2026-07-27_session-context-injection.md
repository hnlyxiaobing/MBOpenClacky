# Session 上下文注入 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: 已完成  
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: 无  
> **来源差距**: G08 - Session 上下文注入缺失  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

**审核修正**：原 IDEA_DOC 声称"MoonBit 版本完全缺失"，经对抗性审核确认为 **PARTIAL FALSE**。

实际情况：`lib/agent/system_prompt.mbt` 的 `build_system_prompt()` 已实现部分上下文注入：
- Layer 5: Working directory ✓（已注入）
- Layer 6: Current model information ✓（已注入）

**缺失项**：当前日期（YYYY-MM-DD）和操作系统信息（WSL/Windows/Linux/macOS）未注入。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "Session 上下文完全缺失" | `grep "current_date\|Today is\|Current model\|Working Directory" lib/agent/system_prompt.mbt` | **2 命中**：Layer 5 Working Directory、Layer 6 Model | **PARTIAL FALSE**：工作目录和模型已注入 |
| "当前日期未注入" | `grep "date\|today\|YYYY-MM-DD" lib/agent/system_prompt.mbt` | 0 命中 | 确认缺失 |
| "OS 信息未注入" | `grep "os\|operating system\|WSL\|Linux\|macOS" lib/agent/system_prompt.mbt` | 0 命中 | 确认缺失 |

### 详细分析

**system_prompt.mbt 现有层**（`lib/agent/system_prompt.mbt`）：

```moonbit
// Layer 5: Working directory context  ← 已实现
if self.working_dir.length() > 0 {
  sections.write_string(format_prompt_section("Working Directory", "Current working directory: \{wd}"))
}

// Layer 6: Current model information  ← 已实现
let model = self.client.model
sections.write_string(format_prompt_section("Model", "Using model: \{model}"))
```

**缺失**：当前日期和 OS 信息。Ruby 版本的系统提示包含 `[Session context: Today is 2026-07-27, Monday. Current model: XXX. OS: WSL/Windows.]` 格式的上下文。

## 决策 [必填 - 含为什么]

1. **决策 1**：在 Layer 6 之后添加 Layer 6.5：Session 上下文（日期 + OS）
   - **为什么**：与现有层结构对齐，不破坏已有层

2. **决策 2**：使用 `@env` API 获取当前时间和 OS 信息
   - **为什么**：MoonBit 标准库支持，无需额外依赖

3. **决策 3**：在对话开始时注入，模型切换时更新
   - **为什么**：确保上下文信息是最新的

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/system_prompt.mbt` | 修改 | 添加日期和 OS 上下文层 |
| `lib/agent/system_prompt_wbtest.mbt` | 修改 | 添加上下文注入测试 |

### 不涉及文件

- `lib/agent/profile.mbt` - 人格加载不变（T11 负责）
- `lib/utils/workspace_rules.mbt` - 规则加载不变（T14 负责）

## 实施计划 [必填]

### 任务包 1：添加日期和 OS 上下文（预估 0.5 天）

1. 在 `build_system_prompt()` 的 Layer 6 之后添加：
   ```moonbit
   // Layer 6.5: Session context (date + OS)
   let date_str = format_current_date()  // YYYY-MM-DD, weekday
   let os_str = detect_os()               // WSL/Windows/Linux/macOS
   sections.write_string(format_prompt_section(
     "Session Context",
     "Today is \{date_str}. OS: \{os_str}."
   ))
   ```
2. 实现 `format_current_date()` 使用 `@env.now()` 转换为日期字符串
3. 实现 `detect_os()` 检测运行环境
4. 编写白盒测试
5. 运行 `moon test lib/agent` 确保测试通过

## 验收标准 [必填]

- [ ] 系统提示包含当前日期（YYYY-MM-DD 格式）
- [ ] 系统提示包含操作系统信息
- [ ] 系统提示保留已有的工作目录和模型信息
- [ ] `moon check lib/agent` 0 errors
- [ ] `moon test lib/agent` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| @env API 限制 | 低 | 使用现有 @env.now() 已验证 |
| OS 检测不准 | 低 | 参考 Ruby 实现 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无（可与 T11 在同一文件协同修改）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本（IDEA_DOC） | 基于 gap-analysis 文档创建 |
| 2026-07-27 | 审核修正：1) "完全缺失"改为"部分已实现"（Working Directory + Model 已注入，仅缺日期和 OS）；2) 从 IDEA_DOC 升级为增量 spec | 对抗性审核 + 第一性原理校验 |
