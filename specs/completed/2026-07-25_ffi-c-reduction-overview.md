# FFI C 依赖消减 · Spec 拆解总览

> **创建日期**: 2026-07-25
> **状态**: 已完成
> **依据**: `docs/reduce-ffi-c-dependency-plan.md`
> **来源差距**: `docs/ffi-c-code-report.md`（已对抗性修订）

## 背景

依据 `docs/reduce-ffi-c-dependency-plan.md` 的四阶段方案，把 4,781 行自写 C / FFI 迁移到 MoonBit 生态（官方 `moonbitlang/async` / `core` / `x` 及社区包）。本总览负责把方案拆成 scope 适中的增量 spec，并给出执行优先级与依赖拓扑。

## 拆解原则

- **scope 适中**：单个 spec 只覆盖一个内聚的迁移主题，删 C 行数控制在 ~1,700 行以内；client HTTP（1,714 行）因高度耦合保留为单 spec，内部按任务包拆分。
- **可独立验证**：每个 spec 自带 `moon check` + 对应 `moon test` 验收门，互不阻塞（除明确标注的依赖）。
- **先验证路径再攻坚**：低风险的纯生态直替先行，建立「stdlib 替换 C」的验证范式，再进 `@async` 进程/HTTP 迁移。
- **安全不妥协**：AES/CSPRNG（OpenSSL/BCrypt）不迁移，`-lcrypto` 保留。

## Spec 清单与优先级（已按「优先级 + 被依赖程度」排序）

| 序号 | Spec | 删 C 行数(估) | 风险 | 前置依赖 | 被谁依赖 |
|------|------|------|------|---------|---------|
| 01 | [时间戳与工作目录迁移至 core/env](2026-07-25_ffi-01-time-getcwd-stdlib.md) | ~70 | 低 | 无 | 方法论基础（验证 stdlib 直替路径） |
| 02 | [ZIP 归档迁移至纯 MoonBit Deflate](2026-07-25_ffi-02-zip-pure-moonbit.md) | 545 | 低 | 无 | 无 |
| 03 | [git 命令 popen 迁移至 @async/process](2026-07-25_ffi-03-git-popen-async-process.md) | ~130 | 中 | 无 | S-04（@async/process 用法验证） |
| 04 | [浏览器进程管理迁移至 @async/process 双向管道](2026-07-25_ffi-04-browser-process-async.md) | 645 | 中 | S-03 | 无 |
| 05 | [Web multipart 上传迁移至 @async/http](2026-07-25_ffi-05-web-multipart-async-http.md) | 395 | 中 | 无 | S-07 |
| 06 | [HTTP 传输层迁移至 @async/http](2026-07-25_ffi-06-client-http-transport-async.md) | ~1,714 | 中高 | S-05（@async/http 用法验证） | S-07 |
| 07 | [brand HTTP GET 迁移 + -lcurl 全项目清理](2026-07-25_ffi-07-brand-httpget-lcurl-cleanup.md) | ~80 | 中 | S-05, S-06 | 无（依赖闭环） |
| 08 | [残余 C 收敛与 PTY 社区包评估](2026-07-25_ffi-08-residual-ffi-pty.md) | - | 低 | S-01~07 | 无 |

**合计可删 C ≈ 3,580+ 行**（S-08 为收敛/评估，不计删量）；残留约 850 行（crypto/console/chdir+uname/时区offset）。

## 依赖拓扑图

```
S-01 (time/getcwd)  ──┐
                      ├── 方法论验证（低风险探路）
S-02 (zip)  ──────────┘   独立

S-03 (git popen) ──→ S-04 (browser process)
                      [@async/process 用法链]

S-05 (multipart) ──→ S-06 (client HTTP) ──→ S-07 (-lcurl 清理)
   [@async/http 用法链]                      [依赖闭环]
                      ↑
S-06 也建议先有 S-05 验证 @async/http 字节体用法

S-01~07 全部完成 ──→ S-08 (残余收敛 + PTY 评估)
```

## 排序说明（"优先级最高，最被依赖"的依据）

1. **S-01 最先**：零依赖、最低风险（纯 `@env.now()`/`current_dir()` 直替），且作为「stdlib 替换 C stub」的验证范式，是后续所有 spec 的方法论前置（过程依赖）。
2. **S-02 次之**：零依赖、独立高收益（删 545 行 vendored miniz），无下游消费者风险。
3. **S-03 → S-04**：`@async/process` 用法链，S-03 简单（popen 等价）先验证用法，S-04 复用模式做复杂双向管道。
4. **S-05 → S-06 → S-07**：`@async/http` 用法链。S-05 先验证字节体上传用法，S-06（核心战役）复用，S-07 收尾清理 `-lcurl`（依赖 S-05 client 不再上 libcurl、S-06 web 不再上 libcurl）。
5. **S-08 最后**：收敛残余 C、评估 PTY 社区包，依赖前面所有迁移稳定。

## 流程遵循

- 所有 spec 先入 `specs/draft/`，经 `spec-adversarial-reviewer` 对抗性审核（验证每条 grep 声称、AOT 约束、scope 合理性）后移入 `specs/active/`。
- 每个 spec 实施时遵循 AGENTS.md：编辑最小化、包内自洽、`moon check` 紧循环、`moon fmt`。
- 实施完成后归档至 `specs/completed/`。

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-25 | 初始版本，拆 8 个 spec | 依据 reduce-ffi-c-dependency-plan.md |
| 2026-07-25 | 全部完成：S-01~08 逐个经对抗性审核后实施并验收 | 实测成果：删 C 共约 3,600+ 行（S-02 545 + S-04 645 + S-05 395 + S-06 1,766 + S-07 269 + S-08 333），`-lcurl` 全项目清零，残余 C 收敛至 5 文件 610 行（time_stub 44 / sys_native 140 / console_cp 58 / crypto_native 222 / brand_stubs 146）；PTY 决策为替换（moonbit-community/pty@0.2.2，获 Windows ConPTY + async 集成）；验收：`moon check` 0 errors、全量 `moon test` 3061/3061、release 构建成功。未验证项（真实浏览器冒烟、12 provider 网络冒烟、品牌分发刷新冒烟、POSIX 代理 env 行为回归）详见各 spec 残留风险 |
