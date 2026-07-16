# Skill auto_creator 完善 · 增量 Spec

> **创建日期**: 2026-07-13
> **状态**: 已完成
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G17（P2 增强性差距）
> **来源差距**: G17 - skill 模块 auto_creator 完善

## 问题描述

原项目 skill 模块包含 `auto_creator`（自动创建技能）功能。当前 `lib/skill/auto_creator.mbt`（205 行）**已存在并有基础实现**，但 `create_skill()` 为 placeholder，缺少真实 SKILL.md 文件生成和磁盘写入。

## 现状分析（经代码验证）

### `auto_creator.mbt` 已有实现（194 行）
- `AutoCreator` struct：`iteration_threshold`（默认 12）、`confidence_threshold`（默认 80）
- `CreationCandidate` struct：name、description、pattern_count、confidence
- `AutoCreator::new()` / `AutoCreator::with_thresholds()` 构造方法
- `AutoCreator::detect_candidates()`：**完整实现**，基于消息前缀匹配检测重复模式（非工具调用序列）
  - 检测条件：prefix 匹配 >= 3 次、消息长度 > 20 字符、非单词、confidence >= 阈值
  - `calculate_confidence()`：基于重复次数 + 长度方差
  - `generate_skill_name()`：从前缀生成技能名
- `AutoCreator::create_skill()`：**placeholder** - 有 TODO "Generate actual SKILL.md file content and write to disk"，返回占位字符串

### 已有集成
- `lib/skill/evolution.mbt:9`：`auto_creator : AutoCreator` 字段已接入 evolution 引擎
- `lib/skill/evolution_wbtest.mbt:133`：已有 "// AutoCreator tests" 测试
- `lib/skill/` 有 10 个 `.mbt` 源文件：`auto_creator.mbt`、`evolution.mbt`、`reflector.mbt`、`discovery.mbt`、`executor.mbt`、`loader.mbt`、`registry.mbt`、`default_skills.mbt`、`skill_wbtest.mbt`、`evolution_wbtest.mbt`（+ `pkg.generated.mbti` 自动生成）
- **无 `mod.mbt`**（原 spec 提到的文件不存在）

### 实际缺口
1. `create_skill()` 未实现真实 SKILL.md 生成和磁盘写入到 `~/.clacky/skills/`
2. 无 LLM 辅助技能描述生成
3. 无用户确认流程
4. 检测机制为消息前缀匹配，非工具调用序列模式（原 spec 提议的方案）

## 决策

1. **保留现有 prefix 匹配检测机制**：`detect_candidates()` 已完整实现且有 wbtest，不重写为工具调用序列模式。prefix 匹配虽不完美但已可用。
2. **`create_skill()` 补全真实实现**：生成 SKILL.md 内容（含描述 + 触发条件 + 工具调用序列），写入 `~/.clacky/skills/<name>/SKILL.md`。
3. **LLM 辅助描述生成**：可选增强。首版用模板生成描述，后续可接入 LLM 生成更自然的技能描述。
4. **用户确认接口**：在 `TuiState`（`lib/tui/state.mbt:135`）/ Web 层增加 `auto_creator_pending : Array[CreationCandidate]` 状态字段，各端轮询显示确认提示。注意：TUI 已于 2026-07-15 完成架构重构（5 个 spec），`TuiState` 结构已大幅变化，需对齐新架构。
5. **不新建 `mod.mbt`**：模块注册已在 `evolution.mbt` 中完成。

## 改动范围

- **涉及包**：`lib/skill`
- **涉及文件**：
  - 修改 `lib/skill/auto_creator.mbt`：补全 `create_skill()` 实现（SKILL.md 生成 + 磁盘写入）
  - 修改 `lib/skill/auto_creator_wbtest.mbt`（新建或扩展 `evolution_wbtest.mbt`）：覆盖 `create_skill()` 真实实现
  - 可选修改 `lib/tui/state.mbt`：增加 `auto_creator_pending` 字段
  - 可选修改 `lib/web/handlers_*.mbt`：增加 auto-creator 确认端点
- **不涉及**：`detect_candidates()` 重写（已有实现且通过测试）

## 实施计划（任务包切分）

1. **`create_skill()` 补全**：SKILL.md 模板生成 + 文件写入 `~/.clacky/skills/<name>/SKILL.md`
2. **wbtest 补充**：覆盖 `create_skill()` 成功/失败路径（confidence 不足、pattern_count 不足、文件写入）
3. **用户确认接口**（可选）：`auto_creator_pending` 状态 + TUI/Web 确认提示
4. **LLM 描述生成**（可选，低优先级）：接入 LLM 生成技能描述

## 验收标准

- [x] `create_skill()` 生成合法 SKILL.md 文件并写入 `~/.clacky/skills/`
- [x] confidence/pattern_count 不足时返回 `Err`
- [x] `moon check` 0 errors（`lib/skill`）
- [x] `moon test lib/skill` 通过
- [x] 现有 `detect_candidates()` 测试不受影响

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 消息前缀匹配检测不够精准 | 中 | 已有实现且通过测试，首版保留；后续可增强为工具调用序列匹配 |
| SKILL.md 文件写入权限问题 | 低 | `~/.clacky/skills/` 目录已由 `loader.mbt` 使用，权限已验证 |
| LLM 生成描述质量不稳定 | 低 | 首版用模板，LLM 为可选增强 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G17，P2 增强性 |
| 2026-07-13 | 审核修正：修正"缺少 auto_creator"的重大错误（`auto_creator.mbt` 已存在 205 行，`detect_candidates()` 完整实现，`evolution.mbt` 已集成，`evolution_wbtest.mbt` 已有测试）；修正触发阈值描述（实际为 iteration_threshold=12 + pattern_count>=3，非仅"3 次"）；修正检测机制描述（消息前缀匹配，非工具调用序列）；修正"无 `mod.mbt`"（文件不存在，注册在 `evolution.mbt`）；实际缺口仅为 `create_skill()` placeholder 补全 | 对抗性审核 + 第一性原理校验 |
| 2026-07-16 | 审核修正：修正文件数（10 个 .mbt 源文件，非 11）；`auto_creator_wbtest.mbt` 仍未创建；TUI 已于 2026-07-15 完成架构重构（5 个 TUI spec），`TuiState` 结构已大幅变化，用户确认接口方案需对齐新 TUI 架构；`create_skill()` 仍为 placeholder，无变化 | 对抗性审核 + 第一性原理校验 |
| 2026-07-16 | 开发完成：`create_skill()` 实现 SKILL.md 模板生成与磁盘写入；新增 `auto_creator_wbtest.mbt` 覆盖成功/失败路径；`moon check` 与 `moon test lib/skill --target native` 全部通过；用户确认接口与 LLM 描述生成按 spec 列为可选，本次未实现 | 按本 spec 达成开发目标后归档 |
