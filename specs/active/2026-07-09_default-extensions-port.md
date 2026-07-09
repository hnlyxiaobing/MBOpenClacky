# 默认扩展迁移 · 启动 Spec (IDEA_DOC)

> **创建日期**: 2026-07-09  
> **状态**: 讨论中  
> **关联总览**: `2026-07-09_gap-driven-task-breakdown-overview.md`（P1-2）  
> **依赖**: `2026-07-09_extension-framework-mvp.md`（Loader/Verifier 先就绪）  
> **负责人**: Agent-C

## 核心目标

将原项目 `lib/clacky/default_extensions/` 下的内置扩展迁移为 MoonBit 项目的 `ext.yml` 声明式扩展，作为 builtin 层源加载，使开箱即用能力对齐原项目。原项目默认扩展：`coding`、`general`、`git`、`time_machine`、`ext-studio`、`meeting`。

## 关键能力

- 每个默认扩展有 `ext.yml` + 贡献资源（panel / skill / agent prompt / hook / patch）。
- 作为 builtin 层源被 Loader 自动发现，不可卸载。
- 迁移后行为对齐原项目（git 扩展提供 Git 工作流、time_machine 提供时间机器面板、ext-studio 提供创作者工作室入口等）。
- 与现有 `assets/agents/coding`、`assets/agents/general` Agent Prompt 复用而非重复。

## 明确不做

- 不迁移 `meeting` 默认扩展的会议后端（原因：会议能力由 P1-3 独立 spec，本扩展只放面板/skill 壳，后端由 P1-3 接入）。
- 不实现扩展运行时本身（原因：依赖 P1-1）。
- 不做前端面板 UI（原因：P1-4）。

## 关键决策（含为什么）

1. **声明式迁移**：原 Ruby 扩展含逻辑代码，MoonBit 版只能搬 manifest + 静态资源 + agent prompt；动态行为改为通过 hook/patch 配置或 builtin API 注册。
2. **builtin 层不可卸载**：保证开箱即用，对齐原项目 `default_extensions` 语义。
3. **复用 assets/agents**：避免 agent prompt 双份维护。
4. **逐个迁移、按依赖排序**：coding/general 无依赖先迁，git/time_machine 依赖对应后端能力，ext-studio 依赖 P1-1 的 scaffold。

## 验收维度

- [ ] coding / general / git / time_machine / ext-studio 五个扩展有合规 `ext.yml`
- [ ] 每个 builtin 扩展被 Loader 发现且 Verifier 通过
- [ ] 至少一个扩展可触发已注册 panel/hook
- [ ] Agent Prompt 无双份冗余
- [ ] `moon check` 0 errors

## 待后续推进时补充

- meeting 扩展后端对接（依赖 P1-3）
- 各扩展 hook/patch 的具体事件订阅清单
- 迁移后行为差异的回归测试

## 变更记录

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-07-09 | 初始版本 | 差距分析 P1-2 |
