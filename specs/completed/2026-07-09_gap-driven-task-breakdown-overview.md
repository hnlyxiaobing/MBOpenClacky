# 基于差距分析的任务划分与 Spec 总览 · 决策文档

> **创建日期**: 2026-07-09  
> **状态**: 已完成  
> **依据**: `docs/project-status.md`（由 2026-07-08 差距分析沉淀而来）  
> **方法论**: `specs/decisions/harness-methodology-application-plan.md`（Harness 方法论）  
> **阶段姿态**: 本轮只产出 spec 文档，不进入开发

---

## 一、背景与目标

2026-07-08 完成的差距分析识别出 MBOpenClacky 与原 openclacky 的功能缺口，并按 P0/P1/P2 分级、给出 6 个 Agent 并行方向与三阶段路线图。本文档将该路线图落地为**可执行的最小混沌单元集合**：对每个单元选择合适的 Harness 姿态（0→1 用 idea-doc，1→N 用 incremental-spec），产出独立 spec 文件。

本轮**只写 spec，不做开发**。spec 通过评审后，再按阶段切任务包进入 do-it → checkpoint → 验收流程。

## 二、与已完成 spec 的关系

`specs/completed/` 已归档 8 份 spec，覆盖：CI/CD 流水线、web-admin-panels（8 个管理面板）、cmd-stub-activation、browser-tool-completion、skills-web-api、extension-runtime-activation、auth-loopback-bypass-fix、tui-phase6-completion。本轮 spec **聚焦差距分析中尚未覆盖的新增差距**，对已完成领域仅做增量收尾（如 TUI Rich UI 第二轮、Extension 框架从"运行时激活"升级为"完整 MVP"）。

## 三、代码现状核对（2026-07-09 实读）

编写 spec 前对 gap 文档的关键论断做了代码核对，发现两处需修正：

| gap 文档论断 | 代码实况 | 本轮处理 |
|---|---|---|
| `lib/client/moon.pkg` 中 `-lcurl` 被注释 | `-lcurl` **已开启**，但 `moon test` 仍链接失败（curl 符号未进入测试可执行文件） | spec 聚焦"测试目标链接标志传播"而非"开启注释" |
| Windows 加密使用弱桩回退 | `crypto_native.c` 在 Windows 已改用 **BCrypt/CNG**；弱桩仅在 `-DMBOPENCLACKY_NO_OPENSSL` 时编译 | 由"Windows 弱桩修复"调整为"brand crypto 加固"（PBKDF2、refresh_distribution HTTP 集成） |
| 6 个 API 端点后端缺失 | `lib/web` 中 grep 0 命中，确认全部缺失 | 维持 P0，纳入 web-api-contract-alignment |

## 四、任务划分总表

按优先级 × 负责方向组织。每个任务对应一份独立 spec。

### P0 — 基线修复（阻塞构建/部署/运行时）

| ID | 任务 | spec 文件 | 姿态 | 负责方向 |
|---|---|---|---|---|
| P0-1 | `moon test` 链接修复（curl/crypto 符号传播到测试可执行文件） | `2026-07-09_moon-test-link-fix.md` | incremental-spec | Agent-F（测试） |
| P0-2 | Web 前后端 API 契约对齐（6 个缺失端点 + 全量审计） | `2026-07-09_web-api-contract-alignment.md` | incremental-spec | ✅ 已完成归档 |
| P0-3 | Brand crypto 加固（derive_key PBKDF2、refresh_distribution HTTP、验证 Windows BCrypt） | `specs/completed/2026-07-09_brand-crypto-hardening.md` | incremental-spec | ✅ 已完成归档 |
| P0-4 | wasm-gc 目标可行性（tty/crescent FFI 依赖评估） | `2026-07-09_wasm-gc-target-feasibility.md` | idea-doc | ✅ 已完成归档（决策暂缓） |

### P1 — 功能完整性

| ID | 任务 | spec 文件 | 姿态 | 负责方向 |
|---|---|---|---|---|
| P1-1 | Extension 框架 MVP（Loader/Verifier/Packager/Scaffold/Publish/Marketplace + ext.yml 三层发现） | `2026-07-09_extension-framework-mvp.md` | idea-doc | Agent-C（扩展） |
| P1-2 | 默认扩展迁移（coding/general/git/time_machine/ext-studio） | `specs/completed/2026-07-09_default-extensions-port.md` | idea-doc | ✅ 已完成归档 |
| P1-3 | 会议能力（后端会话 + Web 面板 + meeting-summarizer skill） | `specs/completed/2026-07-09_meeting-support.md` | idea-doc | ✅ 已完成归档 |
| P1-4 | Web 前端面板补齐（扩展市场/创作者工作室/媒体生成/任务/代码编辑器/LaTeX/QRCode） | `2026-07-09_web-frontend-panels-completion.md` | idea-doc | Agent-B（Web 前端） |
| P1-5 | REST API 补齐（profile/memories/model CRUD/settings/share/benchmark/session-scoped git/time_machine/files/brand skills） | `2026-07-09_rest-api-completion.md` | incremental-spec | Agent-A（Web 后端） |
| P1-6 | TUI Rich UI 收尾（dialog/todo 完整集成、Rich UI 侧边栏、会议集成，第二轮） | `2026-07-09_tui-rich-ui-completion.md` | incremental-spec | Agent-D（TUI/会议） |
| P1-7 | 后端国际化（locales en/zh 迁移或统一前端 i18n） | `2026-07-09_backend-i18n.md` | idea-doc | Agent-A/B（共享） |

### P2 — 运维、生态、polish

| ID | 任务 | spec 文件 | 姿态 | 负责方向 |
|---|---|---|---|---|
| P2-1 | 部署模板（docker-compose / systemd / logrotate） | `2026-07-09_deployment-templates.md` | idea-doc | Agent-E（部署运维） |
| P2-2 | 分发打包（Homebrew 公式 / 卸载脚本 / 完整安装脚本 / Windows 安装包） | `2026-07-09_distribution-packaging.md` | idea-doc | Agent-E（部署运维） |
| P2-3 | MoonBit warnings 削减（522 → ≤200） | `specs/completed/2026-07-09_warnings-reduction.md` | incremental-spec | Agent-F（质量） | ✅ 已完成归档 |
| P2-4 | 测试覆盖扩展（Web/TUI/Extension eval 场景，1400+ → 2000+） | `specs/completed/2026-07-09_test-coverage-expansion.md` | incremental-spec | Agent-F（测试） | ✅ 已完成归档 |

## 五、并行与依赖关系

```
P0-1 (test link)  ─┐
P0-2 (api 契约)   ─┼─→ 解除构建/运行阻塞，P1 才能稳定合并
P0-3 (crypto)     ─┘

P1-1 (extension framework) ─→ P1-2 (默认扩展) ─→ P1-4 (扩展市场前端)
P1-3 (meeting) ─→ P1-6 (TUI 会议集成)
P1-5 (rest api) 与 P0-2 共享 web 后端 handler 风格，建议同一 Agent 连续推进
P1-7 (i18n) 可与任何前端任务并行

P2-* 无硬前置，可在 P1 进行中穿插
```

合并顺序：P0 全部 → P1-1/P1-5/P1-6 → P1-2/P1-3/P1-7 → P1-4 → P2-*。

## 六、每个 Agent 的 worktree 建议

```bash
git worktree add -b agent-a/web-backend   ../mb-agent-a   # P0-2 P1-5 P1-7
git worktree add -b agent-b/web-frontend  ../mb-agent-b   # P1-4 P1-7
git worktree add -b agent-c/extension     ../mb-agent-c   # P1-1 P1-2
git worktree add -b agent-d/tui-meeting   ../mb-agent-d   # P1-3 P1-6
git worktree add -b agent-e/deploy        ../mb-agent-e   # P2-1 P2-2
git worktree add -b agent-f/quality       ../mb-agent-f   # P0-1 P0-3 P0-4 P2-3 P2-4
```

## 七、验收共性（所有 spec 共用）

- `moon check` 0 errors
- `moon build --target native --release cmd` 成功
- 新增功能附带 `*_wbtest.mbt` 或 `test/` eval 场景
- `moon fmt` 通过、`moon info` 无非预期公共 API 变更
- 改动最小化、包内局部，跨包改动前 checkpoint

## 变更记录

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-07-09 | 初始版本，划分 15 个任务并产出对应 spec | 落地差距分析为可执行 spec |
| 2026-07-13 | 收尾：P2-3（warnings 削减）与 P2-4（测试覆盖扩展）均已达成并归档；本总览文档随之关闭 | 差距分析任务闭环 |
