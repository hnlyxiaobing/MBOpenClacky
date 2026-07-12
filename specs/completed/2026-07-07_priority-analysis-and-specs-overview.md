# MBOpenClacky 项目对比分析与优先级排序 · 决策文档

> **创建日期**: 2026-07-07  
> **状态**: 已完成（决策已执行，优先项已由后续 spec 覆盖）  
> **分析对象**: MBOpenClacky (MoonBit 重写) vs OpenClacky (Ruby 原版)  
> **原项目路径**: `D:\MoonBit\openclacky\`  
> **当前项目路径**: `D:\MoonBit\MBOpenClacky\`  
> **分析日期**: 2026-07-07

---

## 一、分析背景

上次 gap analysis（2026-06-30）已被标记为过时。自那以后项目完成了大量工作：

- 8 份 spec 已完成归档（CI/CD pipeline、web-admin-panels、cmd-stub-activation、browser-tool-completion、skills-web-api）
- `moon check` 0 errors / 452 warnings（上次 426）
- 源文件 242 个 + 测试 61 个（上次 248 + 62）
- 源代码 ~53,914 行（原项目 ~65,326 行 Ruby）

本次分析基于**当前代码实读**（非历史文档），聚焦"什么还没做、什么最重要"。

---

## 二、项目指标对比（2026-07-07 实测）

| 指标 | MBOpenClacky | OpenClacky (Ruby) | 差异 |
|------|-------------|-------------------|------|
| 源文件数 | 242 .mbt | 211 .rb | MB 多 15%（包粒度更细） |
| 源代码行数 | ~53,914 | ~65,326 | MB 少 17%（MoonBit 更精炼） |
| 测试文件数 | 61 _wbtest.mbt | ~140 _spec.rb | MB 少 56% |
| 测试用例数 | 1,400+ | 未运行 | MB 密度更高 |
| 编译状态 | 0 errors, 452 warnings | N/A（解释型） | MB 可编译 |
| Web 端点数 | 214 | ~33（http_server.rb 内） | MB 端点更丰富 |
| 内置 Skill 数 | 17 | 17 | ✅ 对齐 |
| 内置工具数 | 14+ | 16 | ⚠️ 差异小 |
| IM 渠道数 | 6 | 6 | ✅ 对齐 |
| CI/CD | ✅ GitHub Actions | ✅ GitHub Actions | ✅ 对齐 |

---

## 三、功能差距矩阵（按模块）

| 模块 | 覆盖度 | 关键差距 | 优先级 |
|------|--------|---------|--------|
| **Extension Runtime** | ~20% | `make_ext_handler` 返回桩 JSON；6 个内置扩展不可用；7 种贡献类型仅 api 路由注册 | 🔴 P0 |
| **Auth 安全** | ~85% | Loopback bypass 硬编码绕过认证 | 🔴 P0 |
| **TUI** | ~80% | Phase 6 未完成：dialog/modal 缺失（工具确认被拒绝）、4 个废弃文件未清理 | 🟡 P1 |
| **Web 前端** | ~45% | 无 i18n、无第三方库（CodeMirror/highlight.js/KaTeX）、管理面板部分缺失 | 🟡 P1 |
| **Vision/OCR** | ~70% | LLM 调用仍为 placeholder | 🟠 P2 |
| **Crypto** | ~90% | `derive_key` 用迭代 SHA-256 而非 PBKDF2 | 🟠 P2 |
| **Server 运维** | ~75% | 无进程守护（systemd）、无日志轮转、无 docker-compose | 🟠 P2 |
| **Extension 容器发现** | ~10% | 无 `ext.yml` 三层源（builtin/installed/local）扫描 | 🟢 P3 |
| **Extension 贡献类型** | ~10% | panel/skill/agent/channel/patch/hook 贡献类型均未实现 | 🟢 P3 |

---

## 四、优先级排序与依据

### P0-1：Extension Runtime System 激活（最高价值）

**为什么最高优先**：
1. **核心差异化能力**：扩展系统是 OpenClacky 的核心卖点——允许用户用任意语言编写自定义 API 端点。当前完全不可用。
2. **阻塞 6 个内置扩展**：coding、ext-studio、general、git、meeting、time_machine 均无法运行。
3. **基础设施已就绪**：`ext_loader.mbt`（描述符解析）+ `ext_dispatcher.mbt`（路由注册）已完成，cmd-stub-activation 已建立 shell 执行模式（`run_shell_command`），只差"最后一公里"接线。
4. **投入产出比极高**：预估 2.5 天工作量，解锁整个扩展生态。

**Spec**: `specs/active/2026-07-07_extension-runtime-activation.md`

### P0-2：Auth Loopback Bypass 修复（最紧迫安全修复）

**为什么高优先**：
1. **安全漏洞**：任何来自 localhost 的请求完全绕过认证，在反代/Docker/SSH 隧道场景下可被利用。
2. **修复成本低**：预估 0.5-1 天，核心改动是移除硬编码 bypass + 添加配置开关。
3. **不应推迟**：安全问题越晚修复成本越高。

**Spec**: `specs/active/2026-07-07_auth-loopback-bypass-fix.md`

### P1-1：TUI Phase 6 完成（功能完整性）

**为什么中高优先**：
1. **功能阻断**：需要确认的工具在 TUI 中被直接拒绝（`build_denied_result`），Agent 核心能力受限。
2. **迁移收尾**：Phase 0-5 已完成，Phase 6 是最后一个阶段，完成后 TUI 迁移正式结束。
3. **技术债清理**：4 个废弃文件（496 行）影响代码可维护性。

**Spec**: `specs/active/2026-07-07_tui-phase6-completion.md`

---

## 五、已排除的项（本次不写 spec）

| 项 | 排除原因 |
|----|---------|
| Web 前端 i18n / 第三方库集成 | 工作量大（2-4 周），且不影响核心功能；属中期独立 spec |
| Extension 容器发现（ext.yml 三层源） | 依赖 Extension Runtime 先完成；属后续增量 |
| Extension 贡献类型（panel/skill/agent 等） | 依赖 Extension Runtime 先完成；各自独立 spec |
| Vision/OCR placeholder | 影响面小（仅扫描版 PDF）；属 P2 |
| derive_key PBKDF2 | 功能性可用（有 TODO），非阻塞性安全问题；属 P2 |
| 进程守护 / 日志轮转 | 运维层面，不影响功能；属 P2 |
| WASM target 测试 | tty + crescent FFI 限制；非业务功能 |

---

## 六、实施建议

### 建议执行顺序

```
P0-2 Auth Fix (0.5-1天)     ──→ 安全基线
    ↓
P0-1 Extension Runtime (2.5天) ──→ 核心能力解锁
    ↓
P1-1 TUI Phase 6 (3天)       ──→ 功能完整性
```

**为什么 Auth Fix 先于 Extension Runtime**：安全修复应优先，且工作量小、风险低、可快速验收。Extension Runtime 虽然价值更高，但需要更多时间和 checkpoint。

### Harness 流程要求

三份 spec 均遵循增量 spec 模板（`specs/_templates/incremental-spec-template.md`），待审核通过后按以下流程推进：

1. **审核**：逐份 spec 审核——决策是否合理、范围是否清晰、验收标准是否可验证
2. **切任务包**：每份 spec 按阶段切分为任务包（已在内含实施计划）
3. **do it → checkpoint → 验收**：每个任务包走完整 Harness 流程
4. **多层 Safety Net**：自验（验收报告）→ 自测（`moon test`）→ 他测（AI review）→ CI/CD

---

## 七、Spec 索引

| Spec | 路径 | 优先级 | 预估工期 |
|------|------|--------|---------|
| Extension Runtime 激活 | `specs/active/2026-07-07_extension-runtime-activation.md` | P0 | 2.5 天 |
| Auth Loopback Bypass 修复 | `specs/active/2026-07-07_auth-loopback-bypass-fix.md` | P0 | 0.5-1 天 |
| TUI Phase 6 完成 | `specs/active/2026-07-07_tui-phase6-completion.md` | P1 | 3 天 |

---

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-07 | 初始版本 | 项目对比分析完成，识别 3 个优先开发点并编写 spec |
| 2026-07-07 | 评审通过（附修正）：Auth 漏洞升级为"可远程利用"（伪造 XFF 头即绕过，crescent 无 socket addr）；Extension Runtime 补并发安全硬性要求（env 内联）；TUI Phase 6 确认机制改为同步 callback、TodoArea 降级为接线。三份 spec 状态改为"已评审，进入实施" | 结合代码实读逐份评审 |
