# 项目规则加载系统 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: 已完成  
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: 无  
> **来源差距**: G09 - 项目规则加载系统缺失  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

**审核修正**：原 IDEA_DOC 声称"MoonBit 版本仅有占位注释 'Phase 5+'"，经对抗性审核确认为 **FALSE**。

实际情况：`lib/utils/workspace_rules.mbt` 已完整实现项目规则加载系统，包括：
- 支持 `.clackyrules`、`.cursorrules`、`CLAUDE.md` 三种格式 ✓
- `find_main()` 查找主规则文件 ✓
- `find_sub_projects()` 查找子项目规则 ✓（已完整实现，非 TODO）
- `to_prompt_section()` 格式化为系统提示段落 ✓
- 有完整的白盒测试 ✓

**实际缺口**：`lib/agent/system_prompt.mbt` 的 `build_system_prompt()` Layer 4 仍为占位注释 `// Layer 4: Project rules (placeholder for Phase 5+ file loading)`，未调用 `WorkspaceRules::find_main()` 和 `to_prompt_section()`。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "仅有占位注释 'Phase 5+'" | `grep "Phase 5" lib/agent/system_prompt.mbt` | 1 命中：`// Layer 4: Project rules (placeholder for Phase 5+ file loading)` | 确认占位存在，但非"仅有" |
| "workspace_rules.mbt 存在" | `glob "lib/utils/workspace_rules*.mbt"` | 2 文件：workspace_rules.mbt + workspace_rules_wbtest.mbt | **确认存在且已实现** |
| "find_main 已实现" | `grep "fn.*find_main" lib/utils/workspace_rules.mbt` | 1 命中 | 确认已实现 |
| "find_sub_projects 已实现" | `grep "fn.*find_sub_projects" lib/utils/workspace_rules.mbt` | 1 命中 | 确认已实现（非 TODO） |
| "to_prompt_section 已实现" | `grep "fn.*to_prompt_section" lib/utils/workspace_rules.mbt` | 1 命中 | 确认已实现 |
| "system_prompt 未调用 WorkspaceRules" | `grep "WorkspaceRules\|workspace_rules" lib/agent/system_prompt.mbt` | 0 命中 | **确认缺失**：集成点缺失 |

### 详细分析

**workspace_rules.mbt 已完整实现**（`lib/utils/workspace_rules.mbt`）：

```moonbit
let rule_file_names : Array[String] = [
  ".clackyrules", ".cursorrules", "CLAUDE.md",
]

pub fn WorkspaceRules::find_main(dir : String) -> WorkspaceRules {
  // 搜索规则文件，优先级：.clackyrules > .cursorrules > CLAUDE.md
  // ... 已完整实现
}

pub fn WorkspaceRules::find_sub_projects(dir : String) -> Array[(String, String)] {
  // 扫描一级子目录，已完整实现（非 TODO）
  // ...
}

pub fn WorkspaceRules::to_prompt_section(self : WorkspaceRules) -> String? {
  // 格式化规则文本用于系统提示注入
  // ...
}
```

**system_prompt.mbt 未集成**（`lib/agent/system_prompt.mbt`）：

```moonbit
// Layer 4: Project rules (placeholder for Phase 5+ file loading)  ← 仅占位
```

## 决策 [必填 - 含为什么]

1. **决策 1**：在 `build_system_prompt()` Layer 4 中调用 `WorkspaceRules::find_main()`
   - **为什么**：workspace_rules.mbt 已实现，只需接入

2. **决策 2**：使用 `working_dir` 作为规则搜索根目录
   - **为什么**：项目规则应在工作目录中查找

3. **决策 3**：规则文件不存在时跳过（不报错）
   - **为什么**：不是所有项目都有规则文件

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/system_prompt.mbt` | 修改 | Layer 4 替换占位注释为实际 `WorkspaceRules` 调用 |
| `lib/agent/system_prompt_wbtest.mbt` | 修改 | 添加规则注入测试 |

### 不涉及文件

- `lib/utils/workspace_rules.mbt` - 已完整实现，不变
- `lib/utils/workspace_rules_wbtest.mbt` - 已有测试，不变

## 实施计划 [必填]

### 任务包 1：集成 WorkspaceRules 到 system_prompt（预估 0.5 天）

1. 在 `build_system_prompt()` Layer 4 中替换占位注释：
   ```moonbit
   // Layer 4: Project rules
   let rules = @utils.WorkspaceRules::find_main(self.working_dir)
   let sub_rules = @utils.WorkspaceRules::find_sub_projects(self.working_dir)
   // 合并 sub_rules 到 rules
   match rules.to_prompt_section() {
     Some(section) => sections.write_string(section)
     None => ()
   }
   ```
2. 确认 `lib/utils` 在 `lib/agent` 的依赖中（检查 moon.pkg.json）
3. 编写白盒测试验证规则注入
4. 运行 `moon test lib/agent` 确保测试通过

## 验收标准 [必填]

- [ ] `build_system_prompt()` 调用 `WorkspaceRules::find_main()`
- [ ] `.clackyrules` 文件内容注入到系统提示
- [ ] `CLAUDE.md` 文件内容注入到系统提示
- [ ] `.cursorrules` 文件内容注入到系统提示
- [ ] 无规则文件时系统提示正常（不报错）
- [ ] `moon check lib/agent` 0 errors
- [ ] `moon test lib/agent` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| lib/utils 不在 agent 依赖中 | 中 | 检查 moon.pkg.json 并添加依赖 |
| 文件读取失败 | 低 | 已有错误处理（catch 返回 None） |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无（可与 T11、T12 在同一文件协同修改）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本（IDEA_DOC） | 基于 gap-analysis 文档创建 |
| 2026-07-27 | 审核修正：1) "仅有占位注释"改为"workspace_rules.mbt 已完整实现，仅 system_prompt.mbt 未集成"（find_main/find_sub_projects/to_prompt_section 均已实现）；2) 从 IDEA_DOC 升级为增量 spec | 对抗性审核 + 第一性原理校验 |
