# message - 消息模型 · 历史管理 · 工具调用 · 多模态内容

> 路径: `lib/message/` · 7 mbt（5 源 + 2 测试）+ moon.pkg/.mbti · LLM 对话消息的核心数据结构

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `Message::user(content)` | `message.mbt` | 构造用户消息 |
| `Message::assistant(content)` | `message.mbt` | 构造助手消息 |
| `Message::system(content)` | `message.mbt` | 构造系统消息 |
| `Message::tool_result(...)` | `message.mbt` | 构造工具结果消息 |
| `MessageHistory::new()` | `history.mbt` | 创建空消息历史 |
| `MessageHistory::from_messages(msgs)` | `history.mbt` | 从数组创建历史 |
| `MessageHistory::append(msg)` | `history.mbt` | 追加消息 |
| `MessageHistory::to_api()` | `history.mbt` | 转换为 API 请求格式 |
| `ToolCall::new(...)` | `tool_call.mbt` | 构造工具调用 |
| `Role::from_string(s)` | `role.mbt` | 字符串->Role 枚举 |

## 关键类型

### 核心 Struct
- **`Message`** - 消息（role, content: MessageContent, tool_calls, tool_call_id, created_at, name）
- **`MessageContent`** - 消息内容枚举：`Text(String) | Blocks(Array[ContentBlock])`
- **`MessageHistory`** - 消息历史管理（messages: Array[Message]）

### 角色
- **`Role`** - `System | User | Assistant | Tool`

### 多模态内容块
- **`ContentBlock`** - `Text(TextBlock) | Image(ImageBlock)`
- **`TextBlock`** - 文本块（text）
- **`ImageBlock`** - 图像块（url, media_type, data）

### 工具调用
- **`ToolCall`** - 工具调用（id, function: FunctionCall）
- **`FunctionCall`** - 函数调用（name, arguments）

## 核心调用链

```
Agent::run()
  └─ MessageHistory::append(Message::user(input))
  └─ Client.build_request_body()
      └─ MessageHistory::to_api() -> Array[Message]
          └─ Message::to_api_message() -> 过滤内部字段

LLM 返回 tool_calls
  └─ Message::assistant(content) + tool_calls=[ToolCall::new(...)]
  └─ Tool 执行完成
      └─ MessageHistory::append(Message::tool_result(...))
```

## 文件职责分组

| 文件 | 职责 |
|------|------|
| `message.mbt` | Message 结构、构造器、ToJson/FromJson、to_api_message |
| `history.mbt` | MessageHistory、追加/替换/截断/回滚/统计、pending_tool_calls 检测 |
| `content.mbt` | ContentBlock、TextBlock、ImageBlock 多模态内容块 |
| `role.mbt` | Role 枚举、to_string_value/from_string |
| `tool_call.mbt` | ToolCall、FunctionCall |

## 外部依赖

- `moonbitlang/core/json` - JSON 序列化（ToJson/FromJson）

## 风险点

1. **消息历史增长** - `MessageHistory` 无上限，长对话可能消耗大量内存
2. **token 估算** - `estimate_tokens()` 使用简单字符计数，与实际 tokenizer 有偏差
3. **tool_calls 完整性** - `pending_tool_calls()` 检查未配对的 tool_call，但截断后可能产生悬空
4. **多模态序列化** - ImageBlock 的 base64 数据可能很大，序列化/传输需注意
