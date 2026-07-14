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
├── active/                ← 进行中的 spec
├── completed/             ← 已完成的 spec（归档）
├── deprecated/            ← 被否决或废弃的 spec（方案变更、需求不再适用等）
└── decisions/             ← 架构决策记录（ADR）
```

## 工作流

1. **新任务** → 从 `_templates/` 选模板，在 `active/` 创建 spec
2. **开发中** → spec 随开发推进不断回写（活 spec）
3. **checkpoint** → 协作中发现的东西沉淀回 spec
4. **完成后** → spec 从 `active/` 移到 `completed/`
5. **废弃时** → spec 从 `active/` 移到 `deprecated/`（方案变更、需求不再适用等）

## Spec 文件命名规范

- 格式：`YYYY-MM-DD_<short-slug>.md`
- 日期为创建日期
- slug 用 kebab-case

## Active Spec 索引（2026-07-09 差距分析驱动）
\r
本轮基于 2026-07-08 差距分析（结论已沉淀至 `docs/project-status.md`）划分 15 个任务，详见总览文档：
\r
`active/2026-07-09_gap-driven-task-breakdown-overview.md`
\r
| 优先级 | ID | 任务 | spec 文件 | 姿态 |
|---|---|---|---|---|
| P0 | P0-1 | `moon test` 链接修复 | `2026-07-09_moon-test-link-fix.md` | incremental-spec |
| P0 | P0-2 | Web API 契约对齐 | `2026-07-09_web-api-contract-alignment.md` | incremental-spec |
| P0 | P0-3 | Brand crypto 加固 | `2026-07-09_brand-crypto-hardening.md` | incremental-spec |
| P0 | P0-4 | wasm-gc 目标可行性 | `2026-07-09_wasm-gc-target-feasibility.md` | idea-doc |
| P1 | P1-1 | Extension 框架 MVP | `2026-07-09_extension-framework-mvp.md` | idea-doc |
| P1 | P1-2 | 默认扩展迁移 | `2026-07-09_default-extensions-port.md` | idea-doc |
| P1 | P1-3 | 会议能力支持 | `2026-07-09_meeting-support.md` | idea-doc |
| P1 | P1-4 | Web 前端面板补齐 | `2026-07-09_web-frontend-panels-completion.md` | idea-doc |
| P1 | P1-5 | REST API 补齐 | `2026-07-09_rest-api-completion.md` | incremental-spec |
| P1 | P1-6 | TUI Rich UI 收尾 | `2026-07-09_tui-rich-ui-completion.md` | incremental-spec |
| P1 | P1-7 | 后端国际化 | `2026-07-09_backend-i18n.md` | idea-doc |
| P2 | P2-1 | 部署模板 | `2026-07-09_deployment-templates.md` | idea-doc |
| P2 | P2-2 | 分发打包 | `2026-07-09_distribution-packaging.md` | idea-doc |
| P2 | P2-3 | Warnings 削减 | `2026-07-09_warnings-reduction.md` | incremental-spec |
| P2 | P2-4 | 测试覆盖扩展 | `2026-07-09_test-coverage-expansion.md` | incremental-spec |
\r
## 模板说明

| 模板 | 用途 | 适用场景 |
|------|------|---------|
| `idea-doc-template.md` | 0→1 启动 spec | 全新功能/项目，目标还不清楚时 |
| `incremental-spec-template.md` | 1→N 增量 spec | 在现有系统上修改/修复 |
| `task-package-template.md` | 任务包 | 每轮具体执行的任务切片 |
