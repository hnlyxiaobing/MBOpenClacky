# client — LLM API 客户端 · SSE 流式 · 多 Provider 适配

> 路径: `lib/client/` · 12 mbt（9 源 + 3 测试）· LLM 通信层（HTTP 传输基于 `@async/http`，无 C FFI）

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `Client::new(api_key, base_url, model, api_type)` | `client.mbt` | 构造 LLM 客户端 |
| `Client::build_request_body(SendRequest)` | `client.mbt` | 根据 ApiType 路由到对应 format 模块 |
| `Client::parse_response(Json)` | `client.mbt` | 解析 LLM 响应（路由到 OpenAI/Anthropic/Bedrock） |
| `Client::format_tool_results(response, results)` | `client.mbt` | 将工具结果格式化为对应 API 格式的消息 |
| `http_post(url, body, headers, timeout)` / `http_get(url, headers, timeout)` | `platform_http.mbt` | 异步 HTTP POST/GET（`pub async fn`，基于 `@async/http`，TLS 走系统根证书） |
| `http_post_async(url, body, headers, timeout_ms)` / `http_post_stream_async(...)` | `http_async.mbt` | 异步 HTTP POST / 流式 POST（`@async/http`，供 SSE 流式响应使用） |
| `parse_sse_frames(buffer)` | `stream.mbt` | 解析 SSE 帧流 |

## 关键类型

### 核心 Struct
- **`Client`** — LLM 客户端（api_key, base_url, model, api_type, provider_id, vision_supported）
- **`SendRequest`** — 请求参数（messages, model, tools, max_tokens, enable_caching, reasoning_effort）
- **`LlmResponse`** — 统一响应（content, reasoning_content, tool_calls, finish_reason, usage, latency）
- **`Usage`** — Token 用量（input_tokens, output_tokens, cache_creation, cache_read）
- **`Latency`** — 延迟指标（duration_ms, ttft_ms）

### HTTP 层
- **`HttpResponse`** — HTTP 响应（status_code, body, headers）
- **`HttpError`** — 错误枚举（Timeout | ConnectionFailed | ServerError | ClientError | AllHostsFailed）
- **`HttpMethod`** — GET/POST/PUT/DELETE
- **`PlatformHttpClient`** + **`PlatformHttpConfig`** — 带 failover 的 HTTP 客户端（primary/fallback host）

### SSE 流式聚合器
- **`OpenAiStreamAggregator`** — OpenAI SSE 帧聚合
- **`AnthropicStreamAggregator`** — Anthropic SSE 帧聚合
- **`BedrockStreamAggregator`** — Bedrock SSE 帧聚合
- **`SseFrame`** — 单帧（event, data）

### Trait
- **`StreamCallback`** — `on_chunk(seq, content_len)` 流式回调接口

## 核心调用链

```
Agent::call_llm()
  └─ Client.build_request_body(SendRequest)
      ├─ build_openai_request()      # format_openai.mbt
      ├─ build_anthropic_request()   # format_anthropic.mbt
      └─ build_bedrock_request()     # format_bedrock.mbt
  └─ http_post(url, body, headers)   # @async/http（platform_http.mbt）
  └─ Client.parse_response(json)
      ├─ parse_openai_response()
      ├─ parse_anthropic_response()
      └─ parse_bedrock_response()
```

## 文件职责分组

| 文件 | 职责 |
|------|------|
| `client.mbt` | Client 主体、请求构建、响应解析、HTTP 函数 |
| `format_openai.mbt` | OpenAI Completions API 请求/响应格式 |
| `format_anthropic.mbt` | Anthropic Messages API 请求/响应格式 |
| `format_bedrock.mbt` | AWS Bedrock Converse API 请求/响应格式 |
| `stream.mbt` | SSE 帧解析、三种 StreamAggregator |
| `types.mbt` | LlmResponse、Usage、Latency、SendRequest 等类型 |
| `platform_http.mbt` | 带 failover 的 HTTP 客户端、`http_post`/`http_get`（`@async/http` 传输） |
| `http_async.mbt` | `http_post_async` / `http_post_stream_async`（`@async/http`，流式 SSE） |

## 外部依赖

- `lib/config` — ApiType 枚举
- `lib/message` — Message、ToolCall 消息类型
- `moonbitlang/core/json` — JSON 序列化
- `moonbitlang/async`（`@async/http`）— HTTP 传输（替代原 libcurl/WinHTTP C FFI，S-FFI-06）

## 风险点

1. **POSIX 代理环境变量回归** — `@async/http` 在 POSIX 下不读取 `HTTPS_PROXY`/`NO_PROXY`（libcurl 时代隐式 honor，属行为回归）；`PlatformHttpConfig.proxy_url` 字段保留但尚未接线
2. **超时粒度** — 现为整请求总超时；原 WinHTTP 的 open/read 分别超时不再支持（`open_timeout_ms` 仅作兼容）
3. **SSE 解析边界** — `parse_sse_frames()` 按 `\n\n` 分帧，异常帧可能导致数据丢失
4. **错误重试** — `is_retryable()` 判断逻辑需覆盖 429/500/503 等场景
5. **Provider 格式差异** — 三种 API 格式的 tool_results 格式化逻辑不同，易出错
