# Windows 原生构建 LNK2019（moonbit_get_cli_args）· 增量 Spec

> **创建日期**: 2026-08-03
> **状态**: 已完成
> **关联总览**: `docs/2026-08-03-web-ui-fix-adversarial-review.md`（遗留问题 1）
> **关联历史 spec**: 无
> **来源差距**: 2026-08-03 对抗性审查 E2E 阶段发现
> **依赖**: 无

## 问题描述 [必填]

Windows 原生环境执行 `moon build --target native --release cmd`（AGENTS.md 记载的标准构建命令）链接失败：

```
cmd.obj : error LNK2019: 无法解析的外部符号 moonbit_get_cli_args，
  函数 _M0FP511moonbitlang1x3sys8internal3ffi14get__cli__args 中引用了该符号
cmd.exe : fatal error LNK1120
```

后果：Windows 上无法产出 `cmd.exe`，只能绕道 WSL 构建（Linux ELF），Windows 原生调试/交付链路断裂。`moon test` 不受影响（测试运行器不引用该符号）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "构建在 Windows 失败" | `moon build --target native --release cmd` | LNK2019 `moonbit_get_cli_args` | 确认（2026-08-03 实测） |
| "同一工作区 WSL 可构建" | WSL `moon build --target native --release cmd` | 成功，产出 ELF | 确认 |
| "两端工具链版本不同" | `moon version` | Windows `0.1.20260731`；WSL `0.1.20260713` | 确认 |
| "x/sys 使用 legacy intrinsic" | 读 `.mooncakes/moonbitlang/x/sys/internal/ffi/sys_native.mbt:16` | `internal_get_cli_args() = "$moonbit.get_cli_args"` | 确认 |
| "升级 x 不能解决" | 拉取 `raw.githubusercontent.com/moonbitlang/x/main/sys/internal/ffi/sys_native.mbt` | main 分支仍是 `$moonbit.get_cli_args`（最新发布 0.4.47，mooncakes.io API 证实） | **升级 x 无效，排除该方案** |
| "Windows 运行时缺 legacy 符号" | COFF 符号解析 `~/.moon/lib/libmoonbitrun.o`（1282 符号） | 仅 mimalloc（`mi_*`），无任何 `moonbit_*` 运行时函数 | 确认 |
| "legacy 符号在旧布局源码中" | `grep -n moonbit_get_cli_args ~/.moon/lib/runtime.c` | :2641 定义、:2721 另有 `moonbit_rt_get_cli_args` | 旧布局 `lib/runtime.c` 不再被 20260731 编译进链接 |
| "新布局提供 core 用符号" | `grep -n cli_args ~/.moon/lib/runtime/env.c` | :193 `moonbit_rt_get_cli_args` | 确认；且 `get_env_var` 等能正常链接（构建期仅缺 get_cli_args）佐证 `runtime/env.c` 参与链接而旧 `lib/runtime.c` 不参与 |
| "@sys.get_cli_args 源码范围唯一调用点" | `grep -rn "get_cli_args" --include="*.mbt" --include="*.mbti" cmd/ lib/ web/ test/` | 仅 `cmd/main.mbt:154`（其余命中为 specs/docs 自身） | 确认（其余 217 处 `@sys.*` 为 env var/exit，链接正常） |
| "core 替代 API 存在" | `grep "pub fn args" ~/.moon/lib/core/env/env.mbt`（两端工具链） | 两端均有 `pub fn args() -> Array[String]` | 确认 |

### 详细分析

第一性原理：`$moonbit.get_cli_args` 是**工具链运行时提供的内建符号**，不是 x 包自己能实现的。moon 0.1.20260731 的 Windows 发行采用新运行时布局（`~/.moon/lib/runtime/*.c`，dune 组织），其中只提供 `moonbit_rt_*` 新符号族（core `env` 包使用）；legacy `moonbit_get_cli_args` 只存在于旧布局 `lib/runtime.c`，而新工具链的链接管线不再编译它。WSL 端 0.1.20260713 仍是旧布局，符号尚在，所以同一份 x@0.4.43 在 WSL 能链接。

因此根因是**外部包（x）对工具链内建符号的假设与新版工具链运行时布局脱节**，且 x 上游（含 main 分支）尚未适配。在本仓库层面，唯一触发断链的是 `cmd/main.mbt:154` 的 `@sys.get_cli_args()`；core `env.args()` 与工具链同源发行，永远是自洽的。

## 决策 [必填 - 含为什么]

1. **用 core `@env.args()` 替换 `@sys.get_cli_args()`（仅此一处）**。为什么：core 与工具链同源，符号必然存在；改动最小（1 个调用点）；不引入依赖变更；两端工具链都已验证存在该 API。
2. **不升级 `moonbitlang/x`**。为什么：已验证 x@main 仍使用同一 legacy intrinsic，升级无助于本问题，且 `moon update` 会连带变更全部依赖，风险大。
3. **不回退 Windows 工具链到 20260713**（备选方案 B）。为什么：能立即绕过，但把问题推迟到下次工具链升级，且两端版本长期漂移本身已是维护负担；作为决策 1 万一受阻时的退路记录在此。
4. **向上游反馈**（非代码改动）：在 moonbitlang/x 提 issue 说明 `$moonbit.get_cli_args` 在 moon ≥ 0.1.20260731 Windows 原生运行时中不可用。为什么：根本修复应在上游，本仓库的替换是止血。

MoonBit 约束检查：不涉及动态加载 trait；不涉及 crescent 路由能力声称；不涉及 FFI 新增（反而是减少对问题 intrinsic 的依赖）。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `cmd/main.mbt` | 修改 | :154 `@sys.get_cli_args()` → `@env.args()`；核对调用处对 argv[0] 的假设（两者均返回完整 argv，语义一致，需在实现时确认 `all_args` 下游切片逻辑不变） |
### 不涉及文件

- `cmd/moon.pkg`——**无需修改**：已 import `moonbitlang/core/env` 且已在用（`cmd/ndjson_logger.mbt:26` `@env.now()`），经审核实测确认
- `moon.mod`（依赖版本不动）
- `lib/` 全部（x/sys 其余 API 链接正常，不替换）
- 任何 C 文件 / link 配置

## 实施计划 [必填]

### 任务包 1：替换调用点并双端验证（预估 0.5 天）
1. 修改 `cmd/main.mbt:154`（必要时 `cmd/moon.pkg` 加 import）。
2. `moon check` 0 errors。
3. Windows 原生 `moon build --target native --release cmd` 成功产出 `cmd.exe`；`cmd.exe --help` 正常输出。
4. WSL `moon build --target native --release cmd` 不回归；`./cmd.exe --help` 正常。
5. `moon test cmd`（如有测试）与 `moon test lib/config`（env 相关）通过。
6. 向上游 moonbitlang/x 提交 issue（链接记录到本 spec 变更记录）。

## 验收标准 [必填]

- [ ] Windows 原生 `moon build --target native --release cmd` 退出码 0，`cmd.exe` 存在且 `--help` 可用
- [ ] WSL 同命令构建不回归
- [ ] `moon check` 0 errors
- [ ] `moon test` 全量通过（native）
- [ ] `git diff` 仅含 `cmd/main.mbt`

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| `@env.args()` 与 `@sys.get_cli_args()` 返回值编码/内容差异（x/sys 按 UTF-8 解码；core Windows 下原生 UTF-16→String） | 低 | 实现时读 `main.mbt:154-170` 下游解析逻辑确认 argv 使用方式；core 的 Windows 路径处理实际更正确 |
| 未来 x 其他 API 也踩到 legacy intrinsic | 中 | 本次已全量 grep 确认仅 get_cli_args 断链；后续工具链升级时把本 spec 的验证命令加入 checklist |
| 工具链再次变更 runtime 布局影响 core env | 低 | core 与工具链同源发布，自洽性由上游保证；若两端同版本则行为一致 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无（AGENTS.md 构建命令恢复可信）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-03 | 初始版本 | 2026-08-03 E2E 发现 Windows 原生构建断链 |
| 2026-08-03 | 对抗性审核修订：验证命令范围收紧为源码范围；`cmd/moon.pkg` 从"可选修改"改为确认无需修改（已 import core/env 且在用）；验收 diff 范围相应收紧 | Spec Review Gate（PASS-WITH-FIXES，2 处低severity） |
| 2026-08-03 | 实施完成：cmd/main.mbt 改 @env.args()；Windows 原生构建产出 cmd.exe（--help 正常），WSL 构建不回归；moon check 0 error、全量 moon test 3243/3243。 从 specs/active/ 归档至 specs/completed/ | 开发验收通过（Harness 步骤 9-10） |
