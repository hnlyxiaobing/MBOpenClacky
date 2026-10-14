# Specs 目录

本目录保存 MBOpenClacky 的规格、决策和历史交付证据。**代码事实以源码与测试为准；spec 是工作记录和决策依据，不是实时状态表。**

## 目录结构

```text
specs/
├── README.md        本索引
├── _templates/      idea / incremental spec / task package 模板
├── draft/           草稿或待评审方案
├── active/          已通过评审、正在实施
├── completed/       已验收归档
├── deprecated/      被否决或被新方案替代
└── decisions/       ADR 与方法论决策
```

## Harness v2 工作流

1. 新任务在 `draft/` 创建 `YYYY-MM-DD_<slug>.md`，使用 `_templates/` 对应模板。
2. 任何“缺失/未实现”声明先用源码、测试和运行结果核验；gap 文档只是假设。
3. 所有 `[必填]` 章节填完后做对抗性评审。
4. 评审通过后移入 `active/`，实现过程持续回写验证结果。
5. 验收后移入 `completed/`，在 [CHANGELOG](../docs/CHANGELOG.md) 记录行为变化。
6. 方案失效或被替代时移入 `deprecated/`，不要留在 active。

MoonBit AOT 约束：运行期热加载扩展不能实现 trait，命令式扩展行为使用 shell command。crescent 的 PATCH/PUT/DELETE 等能力必须查源码确认后再写入 spec。

## 当前状态（2026-10-14）

- `specs/active/` 当前为空。
- `specs/draft/` 当前包含 benchmark gate、journey runner、agent profile/system prompt 对齐，以及用户场景自动化设计等待评审/待实施方案。
- `specs/completed/` 保存已交付批次；不要在 README 重复维护其大表或历史测试数字。
- `specs/decisions/` 是长期事实来源，包括 Harness v2 与 typed engine protocol leaf boundary。

需要了解当前功能和缺口时，优先读：

- [项目状态](../docs/project-status.md)
- [测试体系](../docs/testing.md)
- [真话台账](../docs/known-gaps.md)
- [优化提升计划](../docs/improvement-execution-plan.md)

## 命名与模板

| 模板 | 用途 |
|---|---|
| `idea-doc-template.md` | 0→1 方向/问题定义 |
| `incremental-spec-template.md` | 1→N 增量变更 |
| `task-package-template.md` | 一轮可执行任务切片 |

文件名使用 `YYYY-MM-DD_<kebab-case-slug>.md`；日期是创建日期，slug 描述目标而不是过程。
