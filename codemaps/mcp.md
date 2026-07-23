# mcp — MCP 协议 · Stdio/HTTP 传输 · JSON-RPC 2.0 · 虚拟技能

> 路径: `lib/mcp/` · 16 mbt（9 源 + 7 测试）+ moon.pkg/.mbti · Model Context Protocol 实现

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `McpRegistry::load_default()` | `registry.mbt` | 从默认配置加载 MCP 服务器注册表 |
| `McpClient::from_spec(spec)` | `client.mbt` | 从 McpServerSpec 创建客户端 |
| `McpClient::initialize()` | `client.mbt` | 初始化 MCP 连接（握手） |
| `McpClient::call_tool(name, args)` | `client.mbt` | 调用 MCP 工具 |
| `parse_mcp_config(content)` | `types.mbt` | 解析 MCP 配置（JSON → Map[String, McpServerSpec]） |

## 关键类型

### 核心 Struct
- **`McpClient`** — MCP 客户端（name, transport, tools, server_info, next_id）
- **`McpRegistry`** — MCP 服务器注册表（clients, specs, idle_timeout）
- **`McpServerSpec`** — 服务器配置（name, server_type, command/url, args, env, headers）
- **`McpServerInfo`** — 服务器信息（name, version, capabilities）
- **`McpCapabilities`** — 能力声明（tools, prompts, resources）
- **`McpTool`** — MCP 工具描述（name, description, input_schema）

### 传输层
- **`Transport` trait** — `start()`, `stop()`, `alive()`, `send_message()`, `on_message()`, `stderr_tail()`
- **`StdioTransport`** — 标准输入/输出传输（command, args, env, cwd）
- **`HttpTransport`** — HTTP 传输（url, headers, session_id）
- **`TransportType`** — `Stdio | Http`

### JSON-RPC
- **`JsonRpcRequest`** — JSON-RPC 2.0 请求（jsonrpc, id, rpc_method, params）
- **`JsonRpcResponse`** — JSON-RPC 2.0 响应（jsonrpc, id, result, error）
- **`JsonRpcError`** — JSON-RPC 错误（code, message, data）

### 技能桥接
- **`SkillProvider`** — 将 MCP 工具暴露为技能（skill_dirs, registered_skills）
- **`SkillInfo`** — 技能信息（name, description, version, category, instructions）
- **`VirtualSkill`** — 虚拟技能（将 MCP server 的工具集合封装为技能）

### 错误
- **`McpError`** — MCP 协议错误
- **`TransportError`** — 传输层错误

## 核心调用链

```
# MCP 工具调用
Browser::mcp_call(tool_name, args)
  └─ McpRegistry::call_tool(server_name, tool_name, args)
      ├─ get_client(server_name) → McpClient?
      │   └─ if None: McpClient::from_spec(spec) → initialize()
      └─ McpClient::call_tool(name, args)
          └─ send_request_with_response("tools/call", params)
              ├─ Transport::send_message(json_rpc_request)
              └─ Transport::on_message → parse_jsonrpc_response()

# 虚拟技能发现
McpRegistry::virtual_skills()
  └─ for each client: client.tools_list()
      └─ VirtualSkill::from_mcp_server(name, tools)
```

## 文件职责分组

| 文件 | 职责 |
|------|------|
| `client.mbt` | McpClient 主体、initialize、call_tool、tools_list |
| `registry.mbt` | McpRegistry、服务器生命周期管理、idle 清理 |
| `transport.mbt` | Transport trait 定义 |
| `stdio_transport.mbt` | Stdio 传输实现 |
| `http_transport.mbt` | HTTP 传输实现 |
| `types.mbt` | McpServerSpec、JsonRpc 类型、配置解析 |
| `skill_provider.mbt` | SkillProvider — MCP 工具→技能桥接 |
| `virtual_skill.mbt` | VirtualSkill — MCP server 虚拟技能封装 |

## 外部依赖

- `moonbitlang/core/json` — JSON-RPC 序列化
- **C FFI** — Stdio 传输的进程间通信

## 风险点

1. **Stdio 进程泄漏** — `StdioTransport` 启动子进程后需确保 `stop()` 被调用
2. **idle 清理竞态** — `McpRegistry::cleanup_idle()` 可能在工具调用期间关闭连接
3. **JSON-RPC 错误处理** — `parse_jsonrpc_response()` 返回 None 时错误信息丢失
4. **HTTP session 管理** — `HttpTransport.session_id` 变更时旧 session 未显式关闭
5. **VirtualSkill 工具冲突** — 不同 MCP server 的同名工具可能冲突
