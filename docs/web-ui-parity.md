# Web UI 对齐状态

> 更新日期：2026-08-11
> 回归测试步骤见 [web-ui-test-plan.md](web-ui-test-plan.md)。

## 总体结论

Web UI（`lib/web` 后端 + `web/` 前端）与基准 OpenClacky 的对齐经过三轮系统性修复：

| 轮次 | 范围 | 结果 |
|------|------|------|
| 第一轮（~2026-07-26） | 44 项（5 项功能差距 + 39 项 issue） | 全部解决 |
| 第二轮（2026-07-26，27 项 BUG-001~027） | 经 `web-ui2-00~10` specs 及后续修复 | 25 项已修复，2 项未解决（见下） |
| 第三轮（2026-08-03） | 7 项 bug 对抗性审查 + 晚间 4 项根因修复 | 全部闭环 |

### 第二轮归档 specs（`specs/completed/2026-07-26_web-ui2-*.md`）

web-ui2-01~10 覆盖：system prompt 泄露、会话创建/删除契约、YAML block scalar 解析、channels 平台字段、agents 本地化、汇率日期格式、路径规范化、会话变更契约、响应字段清理。

### 第三轮关键修复摘要（2026-08-03）

7 个 bug 的对抗性审查发现原修复多数不完整，根因修复如下：

1. **历史消息丢失**：`run_ws_agent` 错误路径补 `save_session`；`get_or_create_agent` 重建 agent 时恢复磁盘历史。
2. **模型下拉不刷新**：面板展开时重置守卫 + 配置变更事件刷新。
3. **工作目录斜杠混杂**：统一正斜杠规范化；根因是 `String::replace` 只换首个 → 改 `replace_all`。
4. **Session 自动命名**：REST 兜底 + `limit=50`；占位名在首条消息后按内容自动重命名。
5. **Agent 头像 404**：**原修复无效**——路由虽注册但被静态中间件 SPA fallback 短路。补中间件豁免 + 路径穿越白名单。
6. **模型选择不生效**：创建路径已修；重启恢复路径查找键不匹配 → `m.model` 匹配 + `current_model_id` 规范化。
7. **历史消息重复**：**原修复无效**——`created_at` 生产路径恒 None，`has_more` 恒 true。补后端打时间戳 + 前端无游标停止分页。

## 未解决问题

| 编号 | 问题 | 现状 |
|------|------|------|
| BUG-026 | `BeforeLlmCall` 仍发送 `phase_start` 事件，前端可能将正文并入折叠段 | 未修复 |

## 已知限制（按设计）

- 媒体生成端点（`POST /api/media/image` / `video` / `audio/speech` / `audio/transcription`）返回 501 stub；视频理解已通过 FFmpeg 抽帧 + LLM vision 实现。
- 前端第三方依赖已全部本地 vendor 化（`web/vendor/`），无 CDN 运行时依赖。

## 回归方式

```bash
moon run cmd -- server        # 启动 Web 服务（端口 7071）
```

按 [web-ui-test-plan.md](web-ui-test-plan.md) 中的用例执行回归；REST 契约相关断言可参考 `lib/web/*_wbtest.mbt`。
