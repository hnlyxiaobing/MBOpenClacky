# Web Admin Panels — 8 个管理面板后端全量实现

> **状态**: ✅ 已完成
> **日期**: 2026-07-07
> **Phase**: 26

## 项目目标

将 Web 管理面板的 8 个后端 handler 文件从 stub/TODO 占位状态转为真实业务实现，覆盖回收站、Git、MCP、定时任务、IM 渠道、备份、计费、浏览器控制全部模块。

## 实现摘要

| 面板 | 文件 | 行数 | Handler 数 | 核心能力 |
|------|------|------|-----------|----------|
| Trash | `handlers_trash.mbt` | 325 | 9 | 统一回收站：批量恢复/删除、类型过滤、过期追踪 |
| Git | `handlers_git.mbt` | 305 | 5 | 完整 Git 操作：status/diff/stage/commit/push/pull/branch，C FFI（`git_exec.c`） |
| MCP | `handlers_mcp.mbt` | 221 | 5 | MCP 服务器 CRUD、工具列表与执行，McpRegistry 集成 |
| Schedules | `handlers_schedules.mbt` | 451 | 11 | Cron 定时任务 CRUD、手动触发、执行历史，Scheduler 集成 |
| Channels | `handlers_channels.mbt` | 410 | 8 | 6 平台 IM 适配器 CRUD、连通性测试 |
| Backup | `handlers_backup.mbt` | 527 | 17 | 文件快照创建/恢复/删除，文件系统持久化 |
| Billing | `handlers_billing.mbt` | 316 | 8 | BillingStore 集成、套餐激活、用量导出 |
| Browser | `handlers_browser.mbt` | 186 | 9 | BrowserManager 集成（预存实现） |
| **合计** | **8 文件** | **2,741** | **72** | **零 stub/TODO 残留** |

## 验收状态

- ✅ `moon check`：0 errors
- ✅ 全部 72 个 handler 函数真实实现，无 stub/TODO 残留
- ✅ 前端 JS 语法全部通过（对应 8 个管理面板前端页面）
- ✅ 构建修复：`lib/web/moon.pkg` 换行符修复、billing 元组类型修复、schedules Map API 修复
- ✅ Git 面板 C FFI（`git_exec.c`）实现 shell 命令执行

## 遗留风险

1. **Git 面板 C FFI 平台兼容** — `git_exec.c` 使用 `popen()` 执行 shell 命令，Windows MSVC 下需验证 `_popen` 兼容性
2. **Backup 文件安全** — 备份路径直接拼接，需防路径遍历攻击
3. **Billing 数据持久化** — 当前 BillingStore 为内存实现，重启丢失数据
4. **前端集成测试** — 后端 handler 已实现，但前端到后端的端到端集成尚未自动化测试覆盖
5. **WebSocket 事件广播** — 部分管理面板操作（如定时任务执行）的实时通知尚未通过 WebSocket 推送
