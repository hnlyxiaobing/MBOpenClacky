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
