# Agent 人格加载系统 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: 已完成  
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: 无  
> **来源差距**: G07 - Agent 人格加载系统缺失  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

**审核修正**：原 IDEA_DOC 声称"MoonBit 版本完全缺失"，经对抗性审核确认为 **FALSE**。

实际情况：`lib/agent/profile.mbt` 已实现完整的人格加载系统，包括从 `~/.mbopenclacky/agents/` 加载 SOUL.md、USER.md、base_prompt.md 和 system_prompt.md。但 `lib/agent/system_prompt.mbt` 的 `build_system_prompt()` 未调用 `AgentProfile::build_system_prompt_section()`，导致人格内容未注入系统提示。

**影响**：人格文件已加载但未实际使用，系统提示使用硬编码的通用角色定义。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "人格加载系统完全缺失" | `grep "SOUL\|USER\.md\|load_global_file" lib/agent/profile.mbt` | **4 命中**：`load_global_file("SOUL.md")`、`load_global_file("USER.md")` | **FALSE**：人格加载已实现 |
| "build_system_prompt_section 存在" | `grep "build_system_prompt_section" lib/agent/` | 5 命中（profile.mbt + pkg.generated.mbti） | 确认存在 |
| "system_prompt.mbt 未调用 profile" | `grep "profile\|AgentProfile\|build_system_prompt_section" lib/agent/system_prompt.mbt` | 0 命中 | **确认缺失**：集成点缺失 |
| "default_profiles.mbt 存在" | `glob "lib/agent/default_profiles*.mbt"` | 1 命中 | 确认存在（内置 profile 规范） |

### 详细分析

**profile.mbt 已实现**（`lib/agent/profile.mbt`）：

```moonbit
pub fn AgentProfile::load_for_name(name : String) -> AgentProfile {
  let profile_dir = resolve_profile_dir(name)
  match profile_dir {
    Some(dir) => {
      let system_prompt = load_file_content(dir + "/system_prompt.md")
      let soul_content = load_global_file("SOUL.md")     // ✓ SOUL.md 已加载
      let user_content = load_global_file("USER.md")      // ✓ USER.md 已加载
      let base_prompt = load_global_file("base_prompt.md")
      { config, system_prompt, soul_content, user_content, base_prompt }
    }
    None => AgentProfile::default_profile()
  }
}

pub fn AgentProfile::build_system_prompt_section(self : AgentProfile) -> String {
  // 组合：base_prompt + soul + user + profile-specific prompt
  // ... 已完整实现
}
```

**system_prompt.mbt 未集成**（`lib/agent/system_prompt.mbt`）：

```moonbit
pub fn Agent::build_system_prompt(self : Agent) -> String {
  // Layer 1: Brand confidentiality notice
  // Layer 2: Agent role definition (硬编码 "You are an AI coding assistant")
  // Layer 3: Base behavior rules
  // Layer 4: Project rules (placeholder for Phase 5+ file loading)  ← 未集成
  // Layer 5: Working directory context
  // Layer 6: Current model information
  // Layer 7-9: Skills, Memory, Tasks
  // ← 未调用 AgentProfile::build_system_prompt_section()
}
```

**缺口**：仅缺少 `build_system_prompt()` 对 `AgentProfile` 的调用。

## 决策 [必填 - 含为什么]

1. **决策 1**：在 `build_system_prompt()` 中调用 `AgentProfile::build_system_prompt_section()`
   - **为什么**：profile.mbt 已实现完整加载逻辑，只需接入

2. **决策 2**：将 profile 内容作为 Layer 2（替换硬编码的 role definition）
   - **为什么**：人格内容应定义 agent 角色，替换通用硬编码

3. **决策 3**：保留截断逻辑（最大字符数限制）
   - **为什么**：避免系统提示过长

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/system_prompt.mbt` | 修改 | 在 `build_system_prompt()` 中调用 `AgentProfile::build_system_prompt_section()`，替换 Layer 2 硬编码 |
| `lib/agent/agent.mbt` | 修改 | 确保 Agent 持有 `AgentProfile` 引用（如尚未持有） |
| `lib/agent/system_prompt_wbtest.mbt` | 修改 | 添加集成测试 |

### 不涉及文件

- `lib/agent/profile.mbt` - 已完整实现，不变
- `lib/agent/default_profiles.mbt` - 内置规范不变
- `lib/agent/profile_types.mbt` - 类型定义不变

## 实施计划 [必填]

### 任务包 1：集成 AgentProfile 到 system_prompt（预估 1 天）

1. 检查 Agent struct 是否持有 `AgentProfile` 引用（如无则添加）
2. 在 `build_system_prompt()` 中，将 Layer 2 替换为：
   ```moonbit
   // Layer 2: Agent persona (from profile)
   let persona = self.profile.build_system_prompt_section()
   if persona.length() > 0 {
     sections.write_string(persona)
   } else {
     // Fallback to hardcoded role
     sections.write_string(format_prompt_section("Role", "You are an AI coding assistant..."))
   }
   ```
3. 编写白盒测试验证人格内容注入
4. 运行 `moon test lib/agent` 确保测试通过

### 任务包 2：处理路径和截断（预估 0.5 天）

1. 确认 `resolve_profile_dir` 使用 `~/.mbopenclacky/agents/` 路径
2. 应用截断逻辑（参考 `truncate_text` 函数）
3. 编写测试验证截断行为

## 验收标准 [必填]

- [ ] `build_system_prompt()` 调用 `AgentProfile::build_system_prompt_section()`
- [ ] SOUL.md 内容注入到系统提示
- [ ] USER.md 内容注入到系统提示
- [ ] 无 profile 时 fallback 到硬编码角色定义
- [ ] `moon check lib/agent` 0 errors
- [ ] `moon test lib/agent` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| Agent struct 未持有 profile | 中 | 检查并添加字段 |
| 人格内容过长 | 低 | 使用已有 truncate_text 函数 |
| 路径不匹配 | 低 | 确认 ~/.mbopenclacky/agents/ 路径 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：T12（Session 上下文注入）可与此 spec 在同一文件协同修改

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本（IDEA_DOC） | 基于 gap-analysis 文档创建 |
| 2026-07-27 | 审核修正：1) "完全缺失"改为"已实现但未集成"（profile.mbt 已加载 SOUL.md/USER.md，仅 system_prompt.mbt 未调用）；2) 从 IDEA_DOC 升级为增量 spec | 对抗性审核 + 第一性原理校验 |
