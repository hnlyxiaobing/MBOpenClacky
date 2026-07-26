# Web UI Parity Report

最后更新: 2026-07-26 | 上游基线: [OpenClacky v1.5.0](https://github.com/clacky-ai/openclacky)

All 44 web UI issues (5 gap items + 39 issue items) have been resolved.

## Summary

| 类别 | 数量 | 状态 |
|---|---|---|
| Gaps (features not yet implemented) | 5 | All resolved |
| Issues (bugs in existing features) | 39 | All resolved |
| **Total** | **44** | **100% resolved** |

## Gap Resolution

| ID | Description | Resolution |
|---|---|---|
| G-001 | Web UI 前端资源未同步 | 上游 v1.5.0 完整同步 (87 files, 2026-07-24) |
| G-002 | Markdown 渲染 + 代码高亮 | `lib/web/markdown_renderer.mbt` 集成 highlight.js + KaTeX |
| G-003 | 对话搜索面板 | `lib/web/search_engine.mbt` 实现 |
| G-004 | Web eval 测试框架 | `lib/web/eval/` 模块 + `test/scenarios/web/` |
| G-005 | Git 扩展面板 | `web/ext_ui/git_panel.js` |

## Issue Resolution Summary

Fixed across 8 fix iterations (fix-01 through fix-08):

- **Template processing**: `{{BRAND_NAME}}` / `{{EXT_SCRIPTS}}` 运行时替换
- **Server routing**: crescent 路由配置 (404 处理、静态文件、WebSocket)
- **Model config**: provider/model/key 绑定、settings 面板数据流
- **Session management**: 创建/恢复/删除 conversation、中断响应
- **Streaming**: SSE 事件解析、渐进式渲染
- **Cross-platform**: Windows 路径规范化、CRLF 处理
- **Extension panels**: `ext_ui/` 模块加载机制
- **Dynamic features**: model aliases、background theme、reload-header

## Verification

- **Manual**: 所有 web eval 场景通过 (`test/scenarios/web/`)
- **Automated**: `moon test lib/web` 通过
- **Regression**: `web-ui-test-plan.md` 定义 50+ 检查点

## Related Docs

- `web-ui-test-plan.md` — 详细的回归测试计划
- `web/UPSTREAM_SYNC.md` — 上游同步基线与流程
- `web/PATCHES.md` — 活跃补丁清单
