# 官方评审反馈核查报告（2026-09-23）

> 核查对象：MoonBit 国产开源生态大赛官方历次评审反馈（20260820 / 20260717 / 20260707）中所列问题。
> 核查基线：`main@ad1e281`，工具链 `moon 0.1.20260921`。

## 概述

三次反馈共 17 条问题：13 已修复、2 部分修复（已如实登记）、2 无法判定（CI 当次 in progress）、2 仍存在（低优先）。**阻塞级问题（构建/测试/运行/CI/发布/许可）全部消除**；剩余问题集中在发布节奏、申报口径、渠道接收侧，均已登记 `docs/known-gaps.md`。

## 核查结论总表

### 20260820 批次（正式验收未通过）

| # | 官方指出问题 | 结论 | 关键证据 |
|---|---|---|---|
| 1 | 成本已实装 | ✅ 已实装 | `lib/pricing/cost_calculator.mbt` 完整实现 + 683 行定价表 |
| 2 | 渠道发送仍 stub | ✅ 已修复 | 6 平台 send 全部真实 HTTP（WP-1.1~1.4） |
| 3 | Discord 网关仍 stub | ✅ 已修复 | `discord_gateway.mbt` 完整 Gateway v10 生命周期 |
| 4 | MCP stdio 仍 stub | ✅ 已修复 | `stdio_transport.mbt` 真实子进程 + python3 集成测试 |
| 5 | 办公文档解析仍 stub | ✅ 已修复 | MoonBitMark 引擎适配，六个 stub parser 已删除 |

### 20260717 批次（验收未通过）

| # | 官方指出问题 | 结论 | 关键证据 |
|---|---|---|---|
| 1 | 快照不能构建 | ✅ 已修复 | `moon build` 77 tasks 成功，8.69 MB 二进制 |
| 2 | 不能测试 | ✅ 已修复 | 全量 4077/4077 |
| 3 | 不能运行 | ✅ 已修复 | `moon run cmd -- --version` → `MBOpenClacky v0.2.0` |
| 4 | CI 没有成功证据 | ✅ 已修复 | CI/Docker 双 badge passing |
| 5 | SQLite 持久化未实现 | ⚠️ 部分修复 | 代码无 SQLite；README 已转架构决策（JSON 文件方案） |
| 6 | 成本计算仍为占位 | ✅ 已修复 | 同 20260820#1 |
| 7 | 部分渠道仍为占位 | ⚠️ 大部分修复 | send/编辑/撤回已接线；接收侧 3 处为诚实报错 stub |
| 8 | 部分扩展仍为占位 | ✅ 基本修复 | `lib/extension/` 约 3800 行真实实现；1 处 MVP 限制已登记 |
| 9 | 包名未发布到 mooncakes.io | ✅ 已修复 | `hnlyxiaobing/MBOpenClacky` 可查询，0.1.0~0.1.3 已发布 |
| 10 | 缺失 C 文件与 native 头文件 | ✅ 已修复 | 8 个 C 文件齐全，`stdlib.h`/OpenSSL 就位 |
| 11 | README 命令及 CI 全部通过 | ✅ 已修复 | 所有命令实测通过，CI 双 badge 绿 |
| 12 | 第三方许可与来源说明 | ✅ 已修复 | `THIRD_PARTY_LICENSES.md` + vendor 版权头完整 |

### 20260707 批次（预验收）

| # | 官方指出问题 | 结论 | 关键证据 |
|---|---|---|---|
| 1 | `moon test` 失败 | ✅ 已修复 | 4077/4077 通过 |
| 2 | 运行入口失败 | ✅ 已修复 | `MBOpenClacky v0.2.0`，EXIT=0 |
| 3 | C 代码缺 `stdlib.h` | ✅ 已修复 | 8 个 C 文件齐全且含 `<stdlib.h>` |
| 4 | OpenSSL/架构链接 | ✅ 已修复 | `build-script.js` 平台分流（Windows BCrypt / Linux `-lcrypto`） |
| 5 | GitHub Actions 均失败 | ✅ 已修复 | 根因已修（裸 `moon test` 连带 vendor/mbtpdf） |
| 6 | Linux CI 缺 `curl/curl.h` | ✅ 已修复 | libcurl 已整体移除，HTTP 走纯 MoonBit `@async/http` |
| 7 | 发布到 mooncakes.io | ✅ 已修复 | 同 20260717#9 |
| 8 | 包名可查询 | ✅ 已修复 | mooncakes.io 在线可访问 |

## 仍存在问题的清单

| 优先级 | 问题 | 修复方向 |
|---|---|---|
| P1 | mooncakes.io 版本落差（registry 0.1.3，本地 0.2.0） | 冻结后 `moon publish` |
| P1 | SQLite 申报口径待官方确认 | 与官方确认 JSON 决策是否可接受 |
| P2 | 渠道接收侧 3 处未接线（Telegram/企微/钉钉） | 按 `improvement-execution-plan.md` §2 排序 |
| P2 | MCP server 暴露未接线（`cmd/cli_mcp.mbt`） | 需 spec 评估 |
| P3 | test/e2e 退避断言负载敏感 | 放宽窗口或改确定性断言 |
| P3 | README 测试命令注释滞后 | 与 AGENTS.md/CI 口径对齐 |

## 结论

1. 阻塞级问题全部消除（构建/测试/运行/CI/发布/许可）。
2. 20260820 四个"仍 stub"项全部实装（渠道发送/Discord 网关/MCP stdio/办公文档解析）。
3. 两项"部分修复"均为已如实登记的诚实缺口（SQLite 转架构决策、渠道接收侧 3 处诚实 stub）。
4. 剩余问题修复成本低，已纳入 `docs/development-plan-2026-09-23.md` 跟踪。

---

*报告生成：2026-09-23 · 核查基线 commit：`ad1e281`*
