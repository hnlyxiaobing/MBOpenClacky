# Web UI 第二轮修复批次总览（web-ui2-01 ~ web-ui2-10）

> **创建日期**: 2026-07-26  
> **状态**: 进行中  
> **关联总览**: `web-ui-comparison-test-report.md`（2026-07-26 对比测试，23 项 bug）  
> **前置批次**: fix-06 ~ fix-20（`specs/completed/`，2026-07-25 全部完成）  
> **方法论**: `specs/decisions/harness-methodology-v2-upgrade.md`（Gap 验证 + Spec 审核）

## 背景

fix-06~20 批次（fix 39 项 issues、5 项 gaps）于 2026-07-25 完成后，2026-07-26 进行了新一轮 MBOpenClacky vs openclacky 的 Web UI 对比测试，发现 23 项新 bug（BUG-001~023）。本批次按 Harness v2 方法论处理：**先逐条用 grep/glob/file_reader + 实跑服务器 curl 验证每个 bug 在当前代码库的真实状态**，再按根因/模块归并为 10 个 spec，写入 `specs/draft/`。

## 关键验证发现（对抗性审查素材）

Harness v2 核心原则：**gap 文档是假设，不是 ground truth**。本次验证发现 1 项报告声称已过时：

- **BUG-007 的 LIST 端点声称已过时**：报告称 `GET /api/sessions`（列表）使用 `session_id`/`last_status`/`model_name`/缺 `card_model`。实跑 `curl /api/sessions` 验证：列表已在前序 fix-09 改用 `SessionSummary`（types.mbt:84），字段已是 `id`/`status`/`model`/`model_id`/`card_model`/`error_code`/`top_up_url`/`raw_message`。**列表端点无需再修**。BUG-007 的真实问题仅剩 DETAIL/CREATE 端点（仍用 `SessionData::to_json` 的 `session_id`），已并入 web-ui2-02。

其余 22 项 bug 经 curl 实测 + 代码定位全部确认（BUG-009 为 Windows 专属，WSL 无法复现双斜杠，但代码根因 `dirs_fwd_slashes` 无去重已确认）。

## 验证方法

- **API 对比**：实跑 `cmd.exe server`（端口 7071，release 构建），对每个端点 curl 取真实响应。
- **代码定位**：grep/glob/file_reader 定位每个 bug 的 handler/根因，记录文件:行号。
- **磁盘验证**：读 `~/.mbopenclacky/sessions/*.json` 确认 system 提示词存于 SessionData.messages（BUG-001/002）。

## 覆盖范围

23 项 bug 全部分配 spec，无遗漏：

| Spec | 优先级 | 来源 BUG | 核心问题 | 主要文件 |
|------|--------|---------|---------|---------|
| web-ui2-01 | P0 | 001, 002 | 系统提示词 API 泄露（messages/fork） | protocol/events.mbt, handlers_session_ext.mbt |
| web-ui2-02 | P1 | 007(部分), 023 | 创建/详情端点缺 id 字段，聊天流程阻断 | handlers.mbt, session_data.mbt |
| web-ui2-03 | P1 | 008, 021, 022 | DELETE 空 body + 回收站清空会话端点缺失 | handlers.mbt, handlers_trash.mbt, server.mbt |
| web-ui2-04 | P1 | 003, 020 | skills 多行描述解析为 "\|"，source 命名 | skill/loader.mbt, handlers_skills.mbt |
| web-ui2-05 | P1 | 005 | channels 缺平台专属字段 | handlers_channels.mbt |
| web-ui2-06 | P1 | 006, 017 | 仅 2 agent、无中文/头像、缺 ext-developer | handlers_agents.mbt, assets/agents/, default_profiles.mbt |
| web-ui2-07 | P1 | 004 | 汇率 date/updated_at 格式错误 | handlers_exchange_rate.mbt |
| web-ui2-08 | P1 | 009 | Windows 目录路径双斜杠/混合分隔符 | handlers_dirs.mbt |
| web-ui2-09 | P1 | 010, 011 | POST 缺 name 校验 + PATCH 缺 ok 字段 | handlers.mbt, handlers_session_ext.mbt |
| web-ui2-10 | P2/P3 | 012~016, 018, 019 | 响应字段清理批次（version/WS/local-image/config/onboard/profile） | handlers_version/ws/local_image/configtest/onboard/profile |

## 执行顺序与依赖

按"安全优先 + 最被依赖者优先"排序，文件级无硬冲突，多数可并行：

```
P0 安全（立即）:
  web-ui2-01（系统提示词泄露）—— 与 web-ui2-02 互补消除消息泄露面，但实现独立

P1 核心:
  web-ui2-02（创建/详情 id）—— 顺带消除详情端点消息泄露，建议与 01 同批
  web-ui2-03（DELETE/trash 契约）
  web-ui2-09（会话变更契约）

P1 模块独立（可并行）:
  web-ui2-04, 05, 06, 07, 08

P2/P3 收尾:
  web-ui2-10（字段清理批次，参照 fix-20 模式）
```

硬性依赖：无跨 spec 文件冲突的强制顺序。web-ui2-01 与 web-ui2-02 都触及"消息泄露"但作用于不同端点（messages/fork vs create/detail），建议同批实施以彻底消除 prompt 泄露面。

## 与原项目契约的对齐原则

所有 spec 以 `web-ui-comparison-test-report.md` 中记录的"期望行为（原项目）"为契约基准，修复目标为逐键对齐 orig 响应形状，而非自创契约。敏感字段（token/路径/system 提示词）一律不向客户端明文暴露。

## 下一步

1. ⏳ 对抗性审核：10 份 spec 逐条复核验证记录、文件:行号、MoonBit 约束、过度设计检查。
2. ⏳ 审核通过后移入 `specs/active/`，进入开发。
3. ⏳ 实施后重跑对比测试，确认 23 项 bug 清零。

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-26 | 初始版本 | web-ui2-01~10 起草完成，建立批次索引。全部 bug 经实跑 curl + 代码验证。关键修正：BUG-007 LIST 声称已过时（fix-09 已修复），仅 DETAIL/CREATE 纳入 web-ui2-02 |
| 2026-07-26 | 审核修正：对抗性审核完成。10 份 spec 全部通过 8 项检查；共修正 9 处行号/路径错误（spec 01/02/03/06/07/08/09/10），spec 04/05 无事实错误。所有"缺失"声称、文件名、MoonBit 约束、crescent 能力均经 grep/glob/file_reader 复核。无过度设计、无模板缺节、无循环依赖 | 对抗性审核 + 第一性原理校验 |
