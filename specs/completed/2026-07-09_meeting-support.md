# 会议能力支持 · 启动 Spec (IDEA_DOC)

> **创建日期**: 2026-07-09  
> **状态**: 已完成  
> **关联总览**: `2026-07-09_gap-driven-task-breakdown-overview.md`（P1-3）  
> **关联历史**: 原项目 `lib/clacky/default_extensions/meeting/`（api/panels/skills + ext.yml）  
> **负责人**: Agent-D

## 核心目标

补齐原项目完全缺失的会议（Meeting）能力：会议会话后端、Web 会议面板、`meeting-summarizer` skill，使"会议结束后自动生成结构化纪要"这一原项目能力在 MoonBit 版可用。

## 关键能力

- **会议会话模型**：创建/列出/结束会议，关联消息流与参与者。
- **会议后端**：REST 端点（list / create / get / summarize / end）+ 会话持久化。
- **meeting-summarizer skill**：从会议 transcript 生成结构化摘要（关键决策、行动项、讨论要点），对齐已安装的 `meeting-summarizer` skill 描述。
- **Web 会议面板**：会议列表、会议详情、触发摘要。
- **meeting 默认扩展壳**：与 P1-2 协作，承载面板/skill 入口。

## 明确不做

- 不做实时音视频会议（原因：超出 AI Agent 文本会议范畴）。
- 不做会议日程/邀请系统（原因：原项目亦无）。
- 不做 TUI 会议面板（原因：会议以 Web 为主；TUI 集成由 P1-6 处理触发入口）。

## 关键决策（含为什么）

1. **会议 = 特殊会话**：复用 `lib/agent` 会话持久化与 transcript，避免新建存储。
2. **摘要由 skill 生成**：对齐已安装 `meeting-summarizer` skill，复用 skill 执行管道，不另起摘要引擎。
3. **后端 REST 与 P1-5 共享 handler 风格**：保持一致性。
4. **面板放 P1-4 统一补**：本 spec 定义后端 + skill + 契约，前端面板在 P1-4 落地，避免耦合。

## 验收维度

- [x] 会议会话可创建/列出/结束并持久化
- [x] `meeting-summarizer` skill 可对 transcript 产出结构化纪要
- [x] 会议 REST 端点有 wbtest
- [x] Web 面板可触发摘要并展示（与 P1-4 联调）
- [x] `moon check` 0 errors

## 待后续推进时补充

- 会议 transcript 来源（IM 渠道转录 vs 手动录入）
- 摘要模板与输出格式细化
- 与 meeting 默认扩展的最终接线

## 变更记录

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-07-09 | 初始版本 | 差距分析 P1-3，原项目完全缺失 |
| 2026-07-13 | 实施完成：meeting.mbt 数据模型+Store、handlers_meeting.mbt REST handlers、wbtest 9个测试、server.mbt 路由注册、meeting-summarizer SKILL.md、meeting ext.yml+贡献资源 | 开发实施 |
