# Web UI 对齐状态

> 更新日期：2026-07-29
> 本文档合并了原 `web-ui-comparison-test-report.md` 的结论。回归测试步骤见 [web-ui-test-plan.md](web-ui-test-plan.md)。

## 总体结论

Web UI（`lib/web` 后端 + `web/` 前端）与基准 OpenClacky 的对齐经过两轮系统性修复：

| 轮次 | 范围 | 结果 |
|------|------|------|
| 第一轮（~2026-07-26） | 44 项（5 项功能差距 + 39 项 issue） | 全部解决 |
| 第二轮（2026-07-26 对比测试，27 项 BUG-001~027） | 经 `web-ui2-00~10` specs 及后续修复批次处理 | 25 项已修复，2 项未解决（见下） |

第二轮修复对应的已归档 specs（`specs/completed/2026-07-26_web-ui2-*.md`）：

| Spec | 覆盖问题 |
|------|---------|
| web-ui2-01 system-prompt-leak | 会话消息 / fork 响应泄露 system prompt |
| web-ui2-02 session-create-detail-contract | 会话创建/详情响应缺 `id`、`status` 字段 |
| web-ui2-03 delete-trash-contract | DELETE 返回 `{"ok":true}`；补充 `DELETE /api/trash/sessions` 清空端点 |
| web-ui2-04 skills-yaml-block-scalar | YAML block scalar（`\|`、`>`）解析（`lib/skill/loader.mbt`） |
| web-ui2-05 channels-platform-fields | channels 平台字段 |
| web-ui2-06 agents-localization | 3 个内置 agent 及 `title_zh`/`description_zh`/`avatar` |
| web-ui2-07 exchange-rate-date-format | 汇率接口日期格式 YYYY-MM-DD |
| web-ui2-08 dirs-path-normalization | Windows 路径规范化 |
| web-ui2-09 session-mutation-contract | 会话变更接口契约 |
| web-ui2-10 response-field-cleanup | 响应字段清理 |

另有独立修复批次处理了会话创建、模型配置（默认模型 `type` 字段同步）、dispatcher 相关的 6 项 UI bug。

## 未解决问题

| 编号 | 问题 | 现状 |
|------|------|------|
| BUG-025 | 会话自动命名：首条消息后未根据内容自动生成会话名 | 未实现 |
| BUG-026 | `BeforeLlmCall` 仍发送 `phase_start` 事件（`lib/web/protocol/events.mbt`），前端可能将正文并入折叠段 | 未修复 |

## 已知限制（按设计）

- 媒体生成端点（`POST /api/media/image` / `video` / `audio/speech` / `audio/transcription`）返回 501 stub；视频理解已通过 FFmpeg 抽帧 + LLM vision 实现（`lib/web/handlers_media.mbt`）。
- 前端第三方依赖已全部本地 vendor 化（`web/vendor/`：codemirror、hljs、katex、marked、qrcode），无 CDN 运行时依赖。

## 回归方式

```bash
moon run cmd -- server        # 启动 Web 服务（端口 7071）
```

按 [web-ui-test-plan.md](web-ui-test-plan.md) 中的用例执行回归；REST 契约相关断言可参考 `lib/web/*_wbtest.mbt`。
