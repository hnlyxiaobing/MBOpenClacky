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

| 优先级 | ID | 任务名称 | Spec 文件 | 类型 | 预估天数 | 依赖 |
|--------|-----|---------|-----------|------|---------|------|
| P0 | T01 | LLM 重试循环 + Fallback 激活 | `2026-07-27_llm-retry-fallback.md` | 增量 | 2 | 无 |
| P0 | T02 | 压缩阈值 + 截断计数修复 | `2026-07-27_compression-threshold-truncation.md` | 增量 | 1 | 无 |
| P0 | T03 | 错误响应格式统一 | `2026-07-27_error-response-format.md` | 增量 | 1 | 无 |
| P0 | T04 | MCP 配置加载实现 | `2026-07-27_mcp-config-loading.md` | 启动 | 2 | 无 |
| P1 | T05 | Fake Tool Call 检测器 | `2026-07-27_fake-tool-call-detection.md` | 启动 | 1 | 无 |
| P1 | T06 | 工具输出截断 + 压缩回滚 | `2026-07-27_tool-output-truncation.md` | 增量 | 1 | 无 |
| P1 | T07 | Time Machine 接入工具执行器 | `2026-07-27_time-machine-integration.md` | 增量 | 1 | 无 |
| P1 | T08 | Provider vision 能力修复 | `2026-07-27_provider-vision-capabilities.md` | 增量 | 1 | 无 |
| P1 | T09 | SKILL.md frontmatter 兼容性 | `2026-07-27_skill-frontmatter-compat.md` | 增量 | 1 | 无 |
| P1 | T10 | Terminal 工具增强 | `2026-07-27_terminal-tool-enhancements.md` | 增量 | 2 | 无 |
| P1 | T11 | Agent 人格加载系统 | `2026-07-27_agent-persona-loading.md` | 启动 | 2 | 无 |
| P1 | T12 | Session 上下文注入 | `2026-07-27_session-context-injection.md` | 启动 | 1 | 无 |
| P2 | T13 | WS token 级流式推送 | `2026-07-27_ws-token-streaming.md` | 启动 | 2 | 无 |
| P2 | T14 | 项目规则加载系统 | `2026-07-27_project-rules-loading.md` | 启动 | 2 | 无 |
| P2 | T15 | 补充 Provider 预设 | `2026-07-27_provider-presets-additions.md` | 增量 | 1 | T08 |
| P2 | T16 | Web UI 次要功能补全 | `2026-07-27_web-ui-minor-features.md` | 增量 | 2 | 无 |
| P2 | T17 | 自动记忆更新系统 | `2026-07-27_auto-memory-update.md` | 启动 | 2 | 无 |
| P2 | T18 | 行为不兼容修复 | `2026-07-27_behavior-compat-fixes.md` | 增量 | 1 | 无 |
\r
## 最近归档 Spec

### 2026-07-29 — Agent 增量 Spec（8 项完成）

| Spec | 名称 | 关键实现 | 测试 |
|------|------|---------|------|
| 01 | Session Context 注入 | `react.mbt:build_session_context()` — per-run 动态注入日期/星期/OS/工作目录 | 318/318 ✅ |
| 02 | reasoning_content 字段 | `LlmResponse.reasoning_content` + OpenAI/Anthropic/Bedrock 流式聚合 | 318/318 ✅ |
| 03 | 空响应检测 | `react_loop_async` 空 content 重试机制（含 thinking-mode 静响应） | 318/318 ✅ |
| 04 | compression_threshold 配置 | `AgentConfig.compression_threshold` → `needs_compression()` 使用配置值 | 318/318 ✅ |
| 05 | 压缩失败回滚 | `compress_with_safety` 失败时 `compression_level - 1` | 318/318 ✅ |
| 06 | URL Fallback | `try_url_fallback()` — 重试耗尽后切换备用 Base URL | 318/318 ✅ |
| 07 | Idle 压缩定时器 | `IdleCompressionTimer` — run 完成后启动，新输入取消，266s 触发 | 318/318 ✅ |
| 08 | Skill Evolution 集成 | `run_skill_evolution_hooks()` — 成功 run 后自动检测模式 | 318/318 ✅ |

## 模板说明

| 模板 | 用途 | 适用场景 |
|------|------|---------|
| `idea-doc-template.md` | 0→1 启动 spec | 全新功能/项目，目标还不清楚时 |
| `incremental-spec-template.md` | 1→N 增量 spec | 在现有系统上修改/修复 |
| `task-package-template.md` | 任务包 | 每轮具体执行的任务切片 |
