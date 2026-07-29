# LlmResponse reasoning_content 字段 · 增量 Spec

> **创建日期**: 2026-07-29
> **状态**: 已完成
> **来源差距**: gap-analysis MB-NEW-02（reasoning_content 字段缺失）
> **依赖**: 无
> **预估工时**: 0.5 天

## 问题描述 [必填]

MBOpenClacky 的 `LlmResponse` 结构体没有 `reasoning_content` 字段。DeepSeek V4、Kimi K2 等 thinking-mode 模型会返回 `reasoning_content`（推理过程），该字段被静默丢弃。

**影响**：
- thinking-mode 模型的推理内容丢失，用户无法看到模型的思考过程
- 切换到 thinking-mode provider 时，历史中缺少 `reasoning_content` 会导致 API 返回 400 错误（部分 provider 要求历史中每个 assistant 消息都有 `reasoning_content`）
- 无法检测 "reasoning_content must be passed back" 类型的错误

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| LlmResponse 无 reasoning_content | `grep "reasoning_content" lib/` | 0 命中 | **确认缺失** |
| LlmResponse 结构体定义 | `file_reader lib/client/types.mbt` | 字段：content, tool_calls, finish_reason, usage, latency | **确认**：无 reasoning_content |
| stream aggregator 不处理 reasoning | `grep "reasoning" lib/client/` | 0 命中 | **确认**：流式聚合器不捕获 reasoning delta |

### 当前 LlmResponse 定义

```moonbit
pub(all) struct LlmResponse {
  content : String?
  tool_calls : Array[@message.ToolCall]?
  finish_reason : String?
  usage : Usage?
  latency : Latency?
}
```

## 决策 [必填 - 含为什么]

1. **添加 `reasoning_content : String?` 字段**：因为 thinking-mode 模型（DeepSeek、Kimi K2）需要此字段传递推理内容。不添加则这些模型的推理过程被静默丢弃。
2. **在 stream aggregator 中捕获 reasoning delta**：因为流式响应中 reasoning_content 以 delta 形式到达，需要聚合。OpenAI 格式用 `choices[0].delta.reasoning_content`，Anthropic 格式用 `thinking` content block。
3. **在 Message 的 to_api 中处理 reasoning_content padding**：因为部分 provider 要求历史中所有 assistant 消息都有 reasoning_content 字段，缺失时需填充空字符串。

## 改动范围 [必填]

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/client/types.mbt` | 修改 | `LlmResponse` 添加 `reasoning_content : String?` 字段 |
| `lib/client/client_stream.mbt` | 修改 | OpenAI stream aggregator 捕获 `reasoning_content` delta |
| `lib/client/anthropic_stream.mbt` | 修改 | Anthropic stream aggregator 捕获 `thinking` content block |
| `lib/agent/react.mbt` | 修改 | 保存 assistant message 时携带 reasoning_content |
| `lib/message/message.mbt` | 修改 | Message 结构体添加 `reasoning_content` 字段；`to_api` 中 padding |

### 不涉及文件

- `lib/client/llm.mbt`：非流式调用路径（如果存在）需同步修改，但优先级低
- `lib/tui/`：TUI 层暂不显示 reasoning_content（后续可扩展）

## 实施计划 [必填]

### 任务包 1：添加字段（0.1 天）
- `LlmResponse` 添加 `reasoning_content : String? = None`
- `Message` 添加 `reasoning_content : String? = None`

### 任务包 2：流式聚合（0.2 天）
- OpenAI stream aggregator：检测 `delta.reasoning_content` 并聚合
- Anthropic stream aggregator：检测 `thinking` content block 并聚合
- 返回 `LlmResponse` 时设置 `reasoning_content`

### 任务包 3：历史 padding（0.1 天）
- `react.mbt` 保存 assistant message 时携带 `reasoning_content`
- `to_api` 中为 thinking-mode provider 的历史消息 padding 空 `reasoning_content`

### 任务包 4：测试（0.1 天）
- wbtest：验证 reasoning_content 被正确解析和传递
- wbtest：验证 padding 逻辑

## 验收标准 [必填]

- [x] `LlmResponse` 包含 `reasoning_content` 字段
- [x] OpenAI 流式响应正确聚合 reasoning_content
- [x] Anthropic 流式响应正确聚合 thinking content
- [x] assistant message 保存时携带 reasoning_content
- [x] `moon check` 0 errors
- [x] `moon test lib/client` 通过
- [x] `moon test lib/agent` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| Message 结构体变更影响序列化 | 中 | 新字段设为 Optional，旧数据兼容 |
| padding 逻辑误判 provider 类型 | 低 | 通过检测历史中是否已有 reasoning_content 来判断 |

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-29 | 初始版本 | gap-analysis MB-NEW-02 验证确认 |
