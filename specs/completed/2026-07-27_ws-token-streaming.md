# WS token 级流式推送 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: 已完成  
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: 无  
> **来源差距**: G12 - WS token 级流式推送缺失  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

**审核修正**：原 IDEA_DOC 声称"MoonBit 版本完全缺失"，经审核发现这是**有意的设计决策**，而非简单缺失。

`lib/web/handlers_ws.mbt` 明确注释："Aggregates StreamChunk deltas into one complete assistant_message (spec decision 3: no token-level streaming on the WS path)"。

当前 MoonBit 将 LLM 的 StreamChunk 聚合为单条 `assistant_message` 后推送，Web UI 无实时打字动画。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "WS 聚合 StreamChunk" | `grep "StreamChunk\|aggregat" lib/web/handlers_ws.mbt` | 4 命中：确认聚合逻辑 + "spec decision 3" 注释 | 确认：有意设计决策 |
| "无 token 级推送" | `grep "token.*stream\|streaming.*token" lib/web/` | 0 命中（仅 configtest 中有 "no stream"） | 确认缺失 |
| "StreamChunk 事件存在" | `grep "StreamChunk" lib/web/protocol/events.mbt` | 1 命中：事件已定义 | 确认：事件已有，仅未在 WS 路径转发 |

### 详细分析

`lib/web/handlers_ws.mbt` 当前逻辑：

```
LLM 流式响应 -> StreamChunk 事件 -> 聚合为完整文本 -> 推送 assistant_message
```

期望逻辑：

```
LLM 流式响应 -> StreamChunk 事件 -> 同时推送 token 级 delta + 聚合
```

## 决策 [必填 - 含为什么]

1. **决策 1**：在 WS 路径中转发 StreamChunk delta 事件
   - **为什么**：StreamChunk 事件已在 protocol/events.mbt 中定义，只需在 WS handler 中转发

2. **决策 2**：保留聚合逻辑，token 推送与聚合并行
   - **为什么**：不破坏现有完整消息推送，仅添加实时 delta

3. **决策 3**：添加流式中断和恢复支持
   - **为什么**：用户可能需要中断流式响应

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_ws.mbt` | 修改 | 在聚合逻辑中添加 StreamChunk delta 转发 |
| `lib/web/protocol/events.mbt` | 修改 | 添加 token delta 事件类型（如尚无） |
| `lib/web/handlers_ws_wbtest.mbt` | 修改 | 添加流式测试 |

### 不涉及文件

- `lib/agent/` - Agent 层不变
- `lib/client/` - 客户端层不变

## 实施计划 [必填]

### 任务包 1：WS token delta 转发（预估 1 天）

1. 在 `handlers_ws.mbt` 的 StreamChunk 处理中，添加 delta 推送：
   ```moonbit
   StreamChunk(chunk) => {
     // 保留现有聚合
     buffer = buffer + chunk
     // 新增：实时推送 delta
     send_ws_event("token_delta", chunk)
   }
   ```
2. 添加流式中断处理
3. 编写白盒测试
4. 运行 `moon test lib/web` 确保测试通过

## 验收标准 [必填]

- [ ] Web UI 显示实时打字动画
- [ ] token 推送延迟小于 100ms
- [ ] 现有聚合逻辑不受影响
- [ ] 流式中断和恢复正常
- [ ] `moon check lib/web` 0 errors
- [ ] `moon test lib/web` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| WS 消息洪泛 | 中 | 添加节流/批量 |
| 与现有聚合冲突 | 低 | 保留聚合逻辑不变 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本（IDEA_DOC） | 基于 gap-analysis 文档创建 |
| 2026-07-27 | 审核修正：确认 gap 属实但为有意设计决策（"spec decision 3: no token-level streaming"）；StreamChunk 事件已在 events.mbt 中定义，仅需 WS 路径转发；从 IDEA_DOC 升级为增量 spec | 对抗性审核 + 第一性原理校验 |
