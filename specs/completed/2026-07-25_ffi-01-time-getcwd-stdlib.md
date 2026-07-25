# 时间戳与工作目录迁移至 core/env · 增量 Spec

> **创建日期**: 2026-07-25
> **状态**: 讨论中
> **关联总览**: `2026-07-25_ffi-c-reduction-overview.md`（S-FFI-01）
> **来源差距**: `docs/ffi-c-code-report.md` 第 2、4、7 节（核查修订：billing/agent 毫秒时间戳「已不成立」、getcwd「已不成立」）
> **依赖**: 无
> **灰度 key**: 无

## 问题描述 [必填]

`lib/billing` 与 `lib/agent` 各有一份 `time_stub.c` 提供「毫秒级 Unix 时间戳」，`lib/utils/sys_native.c` 提供 `getcwd`。这些 C stub 在 2026-07 的工具链下已被官方 `moonbitlang/core/env` 完全覆盖：

- `@env.now() -> UInt64`：原生返回 Unix 纪元毫秒数（native 后端绑定 `moonbit_get_ms_since_epoch`）。
- `@env.current_dir() -> String?`：原生返回当前工作目录。

`billing/time_stub.c`（32 行）可整体删除；`agent/time_stub.c`（119 行）的毫秒部分可删，仅保留「本地时区偏移检测」一项真实空白；`utils/sys_native.c` 的 `getcwd` 部分可删，`chdir`/`osrelease` 保留（S-FFI-08 收敛）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| `@env.now() -> UInt64` 存在 | `cat ~/.moon/lib/core/env/pkg.generated.mbti` | 含 `pub fn now() -> UInt64` | 确认可替代毫秒时间戳 |
| `@env.current_dir() -> String?` 存在 | 同上 | 含 `pub fn current_dir() -> String?` | 确认可替代 getcwd |
| billing 毫秒 FFI 调用点 | `grep -n billing_ms_since_epoch_ffi lib/billing/*.mbt` | `billing_record.mbt:73(decl),:80(call)` | 单一调用点 |
| agent 三个时间 FFI | `grep -n "_ffi" lib/agent/time.mbt` | `:6 ms_since_epoch_ffi / :30 iso8601_now_ffi / :34 ms_to_iso8601_local_ffi`，调用点 :11/:40/:53 | 三 FFI |
| utils getcwd/chdir/osrelease | `grep -n "_ffi" lib/utils/sys_ext.mbt` | `chdir_ffi:10, getcwd_ffi:16, osrelease_ffi:22` | getcwd 可替，余保留 |
| osrelease 被 WSL 检测使用 | `grep -rn osrelease_ffi lib/` | `environment_detector.mbt:64` | osrelease 不可删（保留） |
| `x/time` 无本地时区检测 | `grep -in local\|detect README.mbt.md`（x/time） | 仅命中 calendar system | 本地 offset 仍需 C |

### 详细分析

- `lib/billing/billing_record.mbt`：`billing_ms_since_epoch_ffi()` 仅在 `:80` 一处调用，返回 `Int64`；替换为 `@env.now().to_int64()`（毫秒值不溢出有符号范围）。
- `lib/agent/time.mbt`：
  - `ms_since_epoch_ffi()`（:11）-> `@env.now().to_int64()`。
  - `iso8601_now_ffi`/`ms_to_iso8601_local_ffi`：格式化改用 `x/time` 的 `ZonedDateTime::from_unix_second` + `fixed_zone(offset)` + `to_string()`；offset 仍由 C 读取（`GetTimeZoneInformation`/`localtime_r` 的 `tm_gmtoff`）。把 119 行 C 收敛为单一 `mbopenclacky_local_offset_minutes() -> Int`（~20 行）。
- `lib/utils/sys_ext.mbt`：`pub fn current_dir()`（:36）现返回 `getcwd_ffi()`；改用 `@env.current_dir()`（`None` 时返回空串以保持现有契约）。`change_dir`/`osrelease_ffi` 保留不动。

## 决策 [必填 - 含为什么]

1. **毫秒时间戳统一用 `@env.now()`**：官方原生实现，消除两份重复 C stub；语义等价。
2. **agent ISO8601 仅保留 offset C 函数**：本地时区自动检测是已核实的生态空白（`x/time` 仅提供 `fixed_zone`/`from_tzif2`，需自行提供偏移）；把 C 职责压到最小（只读 offset），格式化交 `x/time`。**注意**：`ZonedDateTime::to_string()` 会附加 `[ZoneName]` 后缀（如 `+08:00[+08:00]`），与旧格式 `+08:00` 不一致，需用 `datetime.to_string() + offset.to_string()` 拼接。
3. **getcwd 用 `@env.current_dir()`**：原生 API，删除 `sys_native.c` 中 getcwd 分支；`chdir`/`osrelease` 因无官方等价物保留（chdir 改自身进程 CWD、uname 取内核版本均无 core/x API）。
4. **`@env.now()` 返回 `UInt64`，原 FFI 返回 `Int64`**：调用点取 `.to_int64()`，毫秒值远未达 `Int64` 上限，安全。

MoonBit AOT 约束检查：不涉及动态加载 trait，无影响。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/billing/billing_record.mbt` | 修改 | 删 `extern`(:73)，:80 改 `@env.now().to_int64()` |
| `lib/billing/moon.pkg` | 修改 | 删 `native-stub: ["time_stub.c"]` |
| `lib/billing/time_stub.c` | 删除 | 整文件 |
| `lib/agent/time.mbt` | 修改 | ms_since_epoch 改 `@env.now()`；ISO8601 改 `x/time` + offset FFI |
| `lib/agent/time_stub.c` | 修改 | 收敛为单一 `mbopenclacky_local_offset_minutes()` |
| `lib/agent/moon.pkg` | 修改 | 加 `moonbitlang/x/time` import |
| `lib/utils/sys_ext.mbt` | 修改 | `current_dir()` 改 `@env.current_dir()` |
| `lib/utils/sys_native.c` | 修改 | 删 getcwd 分支，保留 chdir/osrelease |

### 不涉及文件

- `lib/utils/environment_detector.mbt`（osrelease 消费方，不变）
- `lib/agent/moon.pkg` 的 `-lcurl`（传递依赖 lib/client，本 spec 不动）

## 实施计划 [必填]

### 任务包 1：billing 时间戳（预估 0.5 天）
- 删 `billing/time_stub.c` 与 moon.pkg native-stub
- `billing_record.mbt:80` 改 `@env.now().to_int64()`
- 验证门：`moon check` + `moon test lib/billing`

### 任务包 2：agent 时间戳 + offset 收敛（预估 1 天）
- `ms_since_epoch_ffi` -> `@env.now().to_int64()`
- `time_stub.c` 重写为单一 `mbopenclacky_local_offset_minutes()`（Windows/POSIX 双分支）
- `time.mbt` ISO8601 用 `x/time` `ZonedDateTime`+`fixed_zone` 重写
- `lib/agent/moon.pkg` 加 `moonbitlang/x/time`
- 验证门：`moon test lib/agent`（校验 session 时间戳格式不变）

### 任务包 3：utils getcwd（预估 0.5 天）
- `sys_ext.mbt::current_dir()` 改 `@env.current_dir()`（`None`->空串）
- `sys_native.c` 删 getcwd 分支
- 验证门：`moon test lib/utils`

## 验收标准 [必填]

- [ ] `moon check` 0 errors（lib/billing, lib/agent, lib/utils）
- [ ] `moon test lib/billing` 通过
- [ ] `moon test lib/agent` 通过，session 时间戳 ISO8601 格式与迁移前一致
- [ ] `moon test lib/utils` 通过
- [ ] `lib/billing/time_stub.c` 已删除，moon.pkg 不再含 native-stub
- [ ] `lib/agent/time_stub.c` 仅剩 offset 函数（wc -l 显著下降）
- [ ] `moon fmt` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| ISO8601 格式字符串与旧实现细微差异 | session 元数据时间格式变化 | 任务包 2 用迁移前后样本对比校验；`x/time::ZonedDateTime::to_string` 会附加 `[ZoneName]` 后缀，需改用 `datetime.to_string() + offset.to_string()` 拼接以匹配旧格式 |
| `@env.now()` 在不同后端精度差异 | 毫秒值偏差 | native 后端绑定 `moonbit_get_ms_since_epoch`，已核实语义等价 |
| offset C 函数 Windows DST 处理 | 夏令时偏移错误 | 保留原 `GetTimeZoneInformation` 的 StandardBias/DaylightBias 逻辑不变 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无（作为「stdlib 替换 C」方法论验证，为后续 spec 提供范式与信心基础）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-25 | 初始版本 | 依据 reduce-ffi-c-dependency-plan.md §4.1-4.3 |
| 2026-07-25 | 审核修正：`ZonedDateTime::to_string()` 会附加 `[ZoneName]` 后缀，需用 `datetime.to_string() + offset.to_string()` 拼接 | 对抗性审核发现 x/time API 行为与 spec 预期不符 |
