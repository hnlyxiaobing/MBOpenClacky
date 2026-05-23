# MBOpenClacky 项目变更日志

> 记录项目每次完成的重要功能、Bug 修复及关键重构，便于回顾每日工作进展。

---

## 格式说明

```
### YYYY-MM-DD  标题
- [类型] 变更描述
  - 详细说明（可选）
```

类型标签：
- `[feat]` — 新功能
- `[fix]` — Bug 修复
- `[refactor]` — 代码重构
- `[perf]` — 性能优化
- `[test]` — 测试相关
- `[docs]` — 文档相关
- `[chore]` — 工程配置 / 依赖 / CI

---

## 变更记录

### 2026-05-23  Phase 2 LLM 客户端核心实现

- `[feat]` 实现 LLM 客户端核心 `lib/client/client.mbt`（410 行）
  - Client struct：API 密钥 / base_url / 模型 / API 类型 / Provider ID
  - 请求构建分发（build_request_body / build_simple_request）
  - 响应解析分发（parse_response）
  - 工具结果格式化（format_tool_results）
  - API 端点 / HTTP 头 / URL 构建（api_path / request_headers / build_url）
  - Prompt Caching 检测（Claude 3.5+ 模型匹配）
  - HTTP 错误映射（400-599 状态码 → 可读错误信息）
  - HTML 响应检测与错误信息提取
  - 流式选项注入（add_stream_options / add_stream_flag）
- `[feat]` 实现 OpenAI 消息格式 `lib/client/format_openai.mbt`（333 行）
  - 请求构建：消息转换、工具定义、vision 过滤、reasoning_effort
  - 响应解析：choices/message/usage/tool_calls 提取
  - 工具结果格式化：canonical tool result 消息构建
  - Prompt Caching：末位工具 cache_control 注入
- `[feat]` 实现 Anthropic 消息格式 `lib/client/format_anthropic.mbt`（480 行）
  - 请求构建：系统消息分离、工具格式转换（parameters→input_schema）
  - 消息转换：tool_use 块、tool_result 块、图片 base64 处理
  - 响应解析：content blocks / stop_reason 映射 / usage 归一化
  - reasoning/thinking 支持（adaptive thinking + effort 配置）
  - Anthropic API 路径检测（/v1/messages vs messages）
- `[feat]` 实现 SSE 流式处理 `lib/client/stream.mbt`（559 行）
  - 通用 SSE 帧解析器（event/data 逐帧提取）
  - StreamCallback trait（流式进度通知接口）
  - OpenAiStreamAggregator：流式内容/工具调用/usage 聚合
  - AnthropicStreamAggregator：content_block 流式聚合（text/tool_use/thinking_delta）
- `[feat]` 扩展 `lib/client/types.mbt`（97 行）
  - Usage：from_openai / from_anthropic 工厂方法（cache 归一化）
  - LlmResponse：text_only / has_tool_calls / is_finished 便捷方法
  - Latency：duration_ms / ttft_ms 延迟度量
- `[chore]` `lib/client/moon.pkg` 新增依赖：`@config`（lib/config）
- `[test]` 新增 `lib/client/client_wbtest.mbt` 白盒测试（38 个用例）
  - SSE 帧解析（7）、OpenAI 请求构建（3）、OpenAI 响应解析（3）
  - Anthropic 请求构建（3）、Anthropic 响应解析（4）
  - 工具结果格式化（3）、错误信息提取（4）
  - Prompt Caching 检测（3）、URL 构建（4）
  - OpenAI 流式聚合（4）、Anthropic 流式聚合（2）、Usage 工具（2）

### 2026-05-23  清理 .qoder/repowiki 误追踪 + 开发计划文档

- `[chore]` 从 Git 索引移除 `.qoder/repowiki/`（29 个文件），该目录已在 .gitignore 中
- `[docs]` 新增 `docs/development-plan.md`：更新里程碑统计与 Phase 2 行动计划

### 2026-05-23  新增 .gitignore，清理 _build/ 构建产物

- `[chore]` 创建 `.gitignore`，排除 `_build/`、`.mooncakes/`、`.repos/`、`.qoder/`、`*.mbti` 等生成文件
- `[fix]` 从 Git 索引中移除 `_build/` 目录（580+ 个构建产物文件），本地文件保留

### 2026-05-23  配置加载与 Provider 预设系统

- `[feat]` 新增 `lib/utils/` 工具包
  - `env.mbt` — 环境变量类型安全访问（字符串/布尔/整数）
  - `path.mbt` — 配置目录路径解析（home_dir、config_dir、config_file、sessions_dir、skills_dir）
  - `utils_wbtest.mbt` — 白盒测试（环境变量读写、路径构建、整数解析）
- `[feat]` 实现配置加载器 `lib/config/loader.mbt`
  - TOML 配置文件读写（settings 节 + models 数组）
  - 环境变量覆盖（`MBOPENCLACKY_API_KEY` / `BASE_URL` / `MODEL` / `VERBOSE`）
  - 默认配置路径 `~/.mbopenclacky/config.toml`
- `[feat]` 实现 Provider 预设系统 `lib/config/provider.mbt`
  - `ApiType` 枚举（OpenAICompletions / AnthropicMessages / Bedrock / OpenAIResponses）
  - `Providers` 内置预设：OpenClacky、OpenRouter、Anthropic、OpenAI、DeepSeek、Qwen
  - Lite model 映射与 fallback model 链
  - 通过 base_url 或 id 自动匹配 Provider
- `[refactor]` `AgentConfig` 所有字段改为 `mut`，支持运行时修改
- `[chore]` `lib/config/moon.pkg` 新增依赖：`bobzhang/toml`、`moonbitlang/x/fs`、`moonbitlang/x/path`、`moonbitlang/x/sys`、`lib/utils`
- `[test]` 新增 `lib/config/config_wbtest.mbt` 白盒测试（29 个用例）
  - 覆盖：默认值、TOML 解析/序列化/往返、Provider 查询、环境变量叠加、模型选择

### 2026-05-23  项目初始化与基础框架搭建

- `[feat]` 建立项目目录结构
  - `cmd/` — 入口程序
  - `lib/agent` — Agent 核心模块
  - `lib/client` — LLM API 客户端
  - `lib/config` — 配置管理
  - `lib/errors` — 错误类型定义
  - `lib/message` — 消息结构
  - `lib/skill` — 技能系统
  - `lib/tool` — 工具系统
- `[chore]` 配置 `moon.mod.json` 及各包 `moon.pkg`
- `[docs]` 添加项目 README 与 MIT LICENSE

---

<!-- 新记录请添加在此行上方 -->
