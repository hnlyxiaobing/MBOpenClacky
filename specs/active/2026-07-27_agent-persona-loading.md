# Agent 人格加载系统 · 启动 Spec (IDEA_DOC)

> **创建日期**: 2026-07-27  
> **状态**: 讨论中  
> **负责人**: 待定

## 核心目标

实现 Agent 人格加载系统，从 `~/.clacky/agents/` 目录加载 SOUL.md、USER.md 和 Agent Profile，替代当前硬编码的通用提示。Ruby 版本支持从多个位置加载人格文件，MoonBit 版本完全缺失。

## 关键能力

- 从 `~/.clacky/agents/SOUL.md` 加载系统人格
- 从 `~/.clacky/agents/USER.md` 加载用户信息
- 从 `~/.clacky/agents/<name>/system_prompt.md` 加载 Agent 特定提示
- 支持截断（最大 1000 字符）
- 支持 session 上下文注入（日期、模型、OS）

## 明确不做

- **不做动态热重载**（原因：复杂度高，重启生效即可）
- **不做多语言支持**（原因：当前仅支持中文和英文）
- **不做人格编辑 UI**（原因：文件编辑即可）

## 关键决策（含为什么）

1. **决策 1**：使用 MoonBit 的文件 I/O API 读取人格文件
   - **为什么**：MoonBit 标准库支持文件操作

2. **决策 2**：人格文件截断到 1000 字符
   - **为什么**：与 Ruby 行为对齐，避免系统提示过长

3. **决策 3**：session 上下文注入在每次对话开始时执行
   - **为什么**：确保日期、模型、OS 信息是最新的

## 验收维度

- [ ] 能够加载 SOUL.md 文件
- [ ] 能够加载 USER.md 文件
- [ ] 能够加载 Agent 特定的 system_prompt.md
- [ ] 人格文件截断到 1000 字符
- [ ] session 上下文注入正确
- [ ] `moon check lib/agent` 0 errors
- [ ] `moon test lib/agent` 全部通过

## 待后续推进时补充

- 人格文件编辑 UI
- 多语言支持
- 动态热重载

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本 | 基于 gap-analysis 文档创建 |
