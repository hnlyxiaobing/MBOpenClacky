# MCP 配置加载实现 · 启动 Spec (IDEA_DOC)

> **创建日期**: 2026-07-27  
> **状态**: 讨论中  
> **负责人**: 待定

## 核心目标

实现 MCP 配置文件加载功能，解析 `~/.mbopenclacky/mcp.json`，支持 stdio 和 HTTP 两种传输类型的 MCP 服务器配置。当前 `load_from_file` 和 `load_default` 都是 TODO stub，MCP 服务器集成功能完全不可用。

## 关键能力

- 解析 `mcp.json` 配置文件
- 支持 stdio 和 HTTP 两种传输类型
- 支持服务器启用/禁用控制
- 支持环境变量和命令行参数配置
- 提供默认配置路径（`~/.mbopenclacky/mcp.json`）

## 明确不做

- **不做热重载**（原因：复杂度高，后续 spec 处理）
- **不做连接池管理**（原因：当前 McpRegistry 已有基础实现）
- **不做认证/鉴权**（原因：MCP 协议本身不涉及）

## 关键决策（含为什么）

1. **决策 1**：使用 MoonBit 的 JSON 解析库解析配置文件
   - **为什么**：MoonBit 标准库已有 JSON 支持，无需引入额外依赖

2. **决策 2**：配置文件格式与 Ruby 版本保持兼容
   - **为什么**：方便用户从 Ruby 迁移到 MoonBit

3. **决策 3**：stdio 传输类型优先实现
   - **为什么**：stdio 是最常见的 MCP 服务器传输方式

## 验收维度

- [ ] 能够解析标准的 `mcp.json` 配置文件
- [ ] 支持 stdio 和 HTTP 两种传输类型
- [ ] 服务器配置正确加载到 `McpRegistry`
- [ ] 错误配置有清晰的错误提示
- [ ] `moon check lib/mcp` 0 errors
- [ ] `moon test lib/mcp` 全部通过

## 待后续推进时补充

- 热重载功能（增量 diff）
- 连接池管理
- 认证/鉴权支持

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本 | 基于 gap-analysis 文档创建 |
