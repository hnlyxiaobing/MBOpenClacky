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
