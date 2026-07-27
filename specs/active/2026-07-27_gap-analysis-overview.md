# Gap Analysis Overview · 任务拆分总览

> **创建日期**: 2026-07-27  
> **状态**: 讨论中  
> **来源文档**: `project-gap-analysis-2026-07-27.md`  
> **参考模板**: `specs/_templates/incremental-spec-template.md`

## 核心目标

将 MBOpenClacky vs OpenClacky 对比分析中发现的 24 个 Bug、40+ 功能差距、7 个行为不兼容项拆分为可执行的 spec，按优先级排序，确保每个 spec 的 scope 适中（单人 1-3 天可完成）。

## 任务拆分表

| ID | 任务名称 | Spec 文件 | 类型 | 优先级 | 预估天数 | 依赖 |
|----|---------|-----------|------|--------|---------|------|
| T01 | LLM 重试循环 + Fallback 激活 | `2026-07-27_llm-retry-fallback.md` | 增量 | P0 | 2 | 无 |
| T02 | 压缩阈值 + 截断计数修复 | `2026-07-27_compression-threshold-truncation.md` | 增量 | P0 | 1 | 无 |
| T03 | 错误响应格式统一 | `2026-07-27_error-response-format.md` | 增量 | P0 | 1 | 无 |
| T04 | MCP 配置加载实现 | `2026-07-27_mcp-config-loading.md` | 启动 | P0 | 2 | 无 |
| T05 | Fake Tool Call 检测器 | `2026-07-27_fake-tool-call-detection.md` | 启动 | P1 | 1 | 无 |
| T06 | 工具输出截断 + 压缩回滚 | `2026-07-27_tool-output-truncation.md` | 增量 | P1 | 1 | 无 |
| T07 | Time Machine 接入工具执行器 | `2026-07-27_time-machine-integration.md` | 增量 | P1 | 1 | 无 |
| T08 | Provider vision 能力修复 | `2026-07-27_provider-vision-capabilities.md` | 增量 | P1 | 1 | 无 |
| T09 | SKILL.md frontmatter 兼容性 | `2026-07-27_skill-frontmatter-compat.md` | 增量 | P1 | 1 | 无 |
| T10 | Terminal 工具增强 | `2026-07-27_terminal-tool-enhancements.md` | 增量 | P1 | 2 | 无 |
| T11 | Agent 人格加载系统 | `2026-07-27_agent-persona-loading.md` | 启动 | P1 | 2 | 无 |
| T12 | Session 上下文注入 | `2026-07-27_session-context-injection.md` | 启动 | P1 | 1 | 无 |
| T13 | WS token 级流式推送 | `2026-07-27_ws-token-streaming.md` | 启动 | P2 | 2 | 无 |
| T14 | 项目规则加载系统 | `2026-07-27_project-rules-loading.md` | 启动 | P2 | 2 | 无 |
| T15 | 补充 Provider 预设 | `2026-07-27_provider-presets-additions.md` | 增量 | P2 | 1 | T08 |
| T16 | Web UI 次要功能补全 | `2026-07-27_web-ui-minor-features.md` | 增量 | P2 | 2 | 无 |
| T17 | 自动记忆更新系统 | `2026-07-27_auto-memory-update.md` | 启动 | P2 | 2 | 无 |
| T18 | 行为不兼容修复 | `2026-07-27_behavior-compat-fixes.md` | 增量 | P2 | 1 | 无 |

## 依赖关系图

```
T01 (LLM 重试+Fallback) ──────────────────────────────┐
T02 (压缩阈值+截断计数) ──────────────────────────────┤
T03 (错误响应格式) ──────────────────────────────────┤
T04 (MCP 配置加载) ──────────────────────────────────┤
                                                       ▼
T05 (Fake Tool Call) ──────────────────────────────► 可并行开发
T06 (工具输出截断+压缩回滚) ──────────────────────────┤
T07 (Time Machine 接入) ─────────────────────────────┤
T08 (Provider vision) ───────────────────────────────┤
                                                       ▼
T15 (补充 Provider 预设) ◄── 依赖 T08
```

## 代码现实验证

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "LLM 无重试循环" | `grep -r "RetryableError" lib/agent/` | 6 命中，但无 catch 处理 | 确认缺失：错误被 raise 但未被捕获重试 |
| "Fallback 状态机为死代码" | `grep -r "FallbackState" lib/agent/` | 类型定义存在，但无状态转换逻辑 | 确认缺失：状态机未实现 |
| "compression_threshold 默认 10000" | 读取 `lib/config/agent.mbt` | 第 40 行确认 `compression_threshold: 10000` | 确认：应为 150000 |
| "truncation_count 非 length 时重置" | 读取 `lib/agent/react.mbt` 第 227 行 | `_ => { truncation_count = 0` | 确认：Ruby 为 task 级别不重置 |
| "错误响应格式为嵌套对象" | 读取 `lib/web/middleware/error_envelope.mbt` | `{ "error": Json::object(fields) }` | 确认：应为扁平字符串 |
| "MCP 配置加载为 TODO" | 读取 `lib/mcp/registry.mbt` | `load_from_file` 返回空注册表 | 确认：TODO stub |
| "HTTP transport 为 TODO" | 读取 `lib/mcp/http_transport.mbt` | `start()` 仅设置 `is_alive = true` | 确认：TODO stub |
| "Kimi 标记为 text_only" | `grep "kimi" lib/config/provider.mbt` | `capabilities: ModelCapabilities::text_only()` | 确认：应为 vision |
| "is_multiline_command 检查 `<<`" | 读取 `lib/tool/terminal.mbt` 第 62 行 | `if command.find("<<") is Some(_)` | 确认：会误判 `echo "a << b"` |
| "Time Machine 未接入工具" | `grep -r "record_file_before_change" lib/tool/` | 0 命中 | 确认：未被调用 |

### 验证结论

文档中的技术声称**基本准确**，所有 P0 级别的问题均已通过代码验证确认。spec 创建应基于这些验证后的事实。

## 共享验收标准

所有 spec 均需满足：

- [ ] `moon check` 0 errors（涉及的包）
- [ ] `moon test lib/<pkg>` 全部通过
- [ ] 与 Ruby 行为对齐（除非 spec 中明确标注为 MoonBit 有意修改）
- [ ] 不引入新的 breaking change

## 合并顺序

### 第一批（P0，可并行）
1. T01: LLM 重试循环 + Fallback 激活
2. T02: 压缩阈值 + 截断计数修复
3. T03: 错误响应格式统一
4. T04: MCP 配置加载实现

### 第二批（P1，可并行）
5. T05: Fake Tool Call 检测器
6. T06: 工具输出截断 + 压缩回滚
7. T07: Time Machine 接入工具执行器
8. T08: Provider vision 能力修复
9. T09: SKILL.md frontmatter 兼容性
10. T10: Terminal 工具增强
11. T11: Agent 人格加载系统
12. T12: Session 上下文注入

### 第三批（P2，可并行）
13. T13: WS token 级流式推送
14. T14: 项目规则加载系统
15. T15: 补充 Provider 预设（依赖 T08）
16. T16: Web UI 次要功能补全
17. T17: 自动记忆更新系统
18. T18: 行为不兼容修复

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本 | 基于 gap-analysis 文档拆分 |
