# Codemaps 目录

本目录存放 MBOpenClacky 各核心包的 **代码地形索引**（CODEMAP）。

> **核心原则**: 节约上下文 — 不用把整个 repo 塞给模型，用一份摘要导航按需回读。

## 用途

- 1→N 场景起手：让模型先读 codemap 定位地形
- 跨包改动前：快速了解影响面
- 新成员上手：快速理解包结构

## 文件命名

- 格式：`<package-name>.md`
- 例如：`agent.md`、`client.md`、`web.md`

## 核心包清单

| 包 | 文件 | 职责 |
|----|------|------|
| agent | `agent.md` | ReAct 循环、LLM 调用、会话管理 |
| client | `client.md` | LLM API 客户端、SSE 流式 |
| tool | `tool.md` | Tool trait + 14 个内置工具 |
| browser | `browser.md` | 浏览器自动化（tool 包子系统） |
| skill | `skill.md` | SKILL.md 解析、注册、进化引擎 |
| mcp | `mcp.md` | MCP 协议（Stdio/HTTP） |
| channel | `channel.md` | 6 个 IM 适配器 |
| server | `server.md` | Cron 调度、浏览器管理、Git 面板 |
| web | `web.md` | REST 服务器、90+ 端点、前端 SPA |
| tui | `tui.md` | TUI 控制器、组件 |
| config | `config.md` | TOML 配置加载 |
## 如何生成

1. 让 AI 扫描包目录和关键文件
2. 提取入口函数、关键类型、调用链、外部依赖、风险点
3. 按 `codemap-template.md`（见方案文档 §4.5）格式输出
