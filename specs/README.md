# Specs 目录

本目录是 MBOpenClacky 项目的 **活 spec** 体系，所有开发决策的真相源。

> **核心原则**: No Spec, No Code — 超过 100 行改动的任务，先写 spec 再动手。

## 目录结构

```
specs/
├── README.md              ← 你在这里
├── _templates/            ← spec 和任务包模板
│   ├── idea-doc-template.md
│   ├── task-package-template.md
│   └── incremental-spec-template.md
├── draft/                 ← 草稿 spec（待对抗性审查）
├── active/                ← 进行中的 spec
├── completed/             ← 已完成的 spec（归档）
├── deprecated/            ← 被否决或废弃的 spec（方案变更、需求不再适用等）
└── decisions/             ← 架构决策记录（ADR）
```

## 工作流

1. **新任务** → 从 `_templates/` 选模板，在 `draft/` 创建 spec
2. **审查** → 通过对抗性审查后移入 `active/`
3. **开发中** → spec 随开发推进不断回写（活 spec）
4. **checkpoint** → 协作中发现的东西沉淀回 spec
5. **完成后** → spec 从 `active/` 移到 `completed/`
6. **废弃时** → spec 从 `active/` 移到 `deprecated/`（方案变更、需求不再适用等）

## Spec 文件命名规范

- 格式：`YYYY-MM-DD_<short-slug>.md`
- 日期为创建日期
- slug 用 kebab-case

## Active Spec 索引

当前无活跃 spec。所有历史 spec 已归档至 `completed/`（86 份）或 `deprecated/`（5 份）。
\r
## 模板说明

| 模板 | 用途 | 适用场景 |
|------|------|---------|
| `idea-doc-template.md` | 0→1 启动 spec | 全新功能/项目，目标还不清楚时 |
| `incremental-spec-template.md` | 1→N 增量 spec | 在现有系统上修改/修复 |
| `task-package-template.md` | 任务包 | 每轮具体执行的任务切片 |
