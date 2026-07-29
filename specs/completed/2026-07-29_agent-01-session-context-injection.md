# Agent Session Context Injection · 增量 Spec

> **创建日期**: 2026-07-29
> **状态**: 已完成
> **来源差距**: gap-analysis MB-NEW-01（Session Context Injection 完全缺失）
> **依赖**: 无
> **预估工时**: 0.3 天

## 问题描述 [必填]

Ruby 版 OpenClacky 在每次 `run()` 开始时注入一条 `system_injected: true` 的 session context 消息，让 LLM 知道当前日期、OS、工作目录、渠道等运行时信息。

MBOpenClacky 的 `build_system_prompt` 只在 Layer 6 注入**静态**的日期和 OS，没有在每次 run 时动态注入 session context。LLM 不知道精确的当前时间、渠道信息、桌面路径等。

**影响**：
- 日期相关推理可能使用过时信息（system prompt 在 session 创建时生成，后续不更新）
- 不知道 OS 类型时可能生成错误路径格式（如 Windows vs Unix）
- Web/IM 渠道模式下不知道渠道信息，无法适配回复风格

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| react.mbt 无 session context 注入 | `grep "session.context\|Session context\|inject_session" lib/agent/react.mbt` | 0 命中 | **确认缺失** |
| system_prompt.mbt 有静态日期 | `file_reader lib/agent/system_prompt.mbt:100-120` | Layer 6 注入 `current_iso8601()` + `detect_os()` | **确认**：静态注入存在，但非 per-run 动态 |
| Ruby 版有完整 session context | gap-analysis 引用 `agent.rb#inject_session_context` | 包含日期/星期/OS/桌面/工作目录/渠道/发送者 | **确认**：基准实现完整 |

### 当前实现

`system_prompt.mbt` Layer 6 注入：
```
## Environment
Current date: 2026-07-29
Operating System: Windows_NT
```

Ruby 版在每次 run 注入：
```
[Session context: Today is 2026-07-29, Wednesday. Current model: xxx.
 OS: WSL/Windows. Desktop: /mnt/c/Users/xxx/Desktop.
 Working directory: /path. Channel: feishu, Sender: xxx]
```

## 决策 [必填 - 含为什么]

1. **在 `run()` 入口注入 session context 消息**：因为它让 LLM 获知精确运行时状态，直接影响日期推理、路径生成、渠道适配的质量。成本极低（一条 user 消息），效果显著。
2. **使用 `system_injected: true` 标记**：因为它与 Ruby 版行为一致，且 compressor 可据此区分注入消息与用户消息。
3. **包含日期/星期/OS/工作目录**：因为这些是 LLM 最常需要的上下文。渠道信息在 CLI 模式下可省略，Web/IM 模式下由上层注入。

## 改动范围 [必填]

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/react.mbt` | 修改 | 在 `run()` 或 `react_loop_async()` 入口，think 前注入 session context 消息 |
| `lib/agent/agent_wbtest.mbt` | 新增 | 验证 session context 消息被正确注入到 history |

### 不涉及文件

- `lib/agent/system_prompt.mbt`：静态环境信息保留，session context 是额外注入
- `lib/client/`：不涉及 LLM 调用层

## 实施计划 [必填]

### 任务包 1：实现注入逻辑（0.2 天）
- 新增 `fn build_session_context_message(self : Agent) -> String` 函数
- 生成 `[Session context: Today is {date}, {weekday}. OS: {os}. Working directory: {wd}]` 格式文本
- 在 `react_loop_async` 开头、首次 `think_async` 前，push 一条 `system_injected: true` 的 user 消息

### 任务包 2：回归测试（0.1 天）
- wbtest：验证 run 后 history 包含 session context 消息
- wbtest：验证 session context 包含当前日期

## 验收标准 [必填]

- [x] 每次 run 后 history 第一条（或前几条）包含 session context
- [x] session context 包含当前日期和星期
- [x] session context 包含 OS 类型
- [x] session context 包含工作目录
- [x] `system_injected: true` 标记正确
- [x] `moon check` 0 errors
- [x] `moon test lib/agent` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 增加每次 run 的 token 开销 | 低 | session context 约 50-80 tokens，相对于 system prompt 可忽略 |
| 压缩时 session context 被误压缩 | 低 | `system_injected` 标记已存在，compressor 可据此跳过 |

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-29 | 初始版本 | gap-analysis MB-NEW-01 验证确认 |
