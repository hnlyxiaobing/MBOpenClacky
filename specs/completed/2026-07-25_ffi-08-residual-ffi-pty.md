# 残余 C 收敛与 PTY 社区包评估 · 增量 Spec

> **创建日期**: 2026-07-25
> **状态**: 已完成
> **关联总览**: `2026-07-25_ffi-c-reduction-overview.md`（S-FFI-08）
> **来源差距**: `docs/ffi-c-code-report.md` 第 3、7、8 节 + FFI 必要性总结（核查修订：PTY/Console/chdir/uname/本地时区仍需 FFI）
> **依赖**: S-01~07（前面迁移稳定后再收敛残余）
> **后置**: 无

## 问题描述 [必填]

S-01~07 完成后，项目残留 C 实际为 **943 行**（对抗性审核实测，见下表；初稿估计 ~850 行偏低），分散在多个包，对应四类确属「OS API 生态空白」的场景：

- `lib/tui/console_cp_native.c`（53 行）：Windows 控制台代码页。
- `lib/utils/sys_native.c`（134 行）：`chdir`/`osrelease`（uname）。
- `lib/agent/time_stub.c`（39 行）：本地时区 offset。
- `lib/tool/pty_stubs.c`（348 行）：POSIX PTY（Windows 返回 -1）。
- `lib/tool/tool_stubs.c`（10 行）：同步 `system()` 包装 `mb_system`。
- `lib/brand/crypto_native.c`（218 行）：AES/CSPRNG（安全保留）。
- `lib/brand/brand_stubs.c`（141 行）：无 OpenSSL 极简构建的 fallback（初稿清单遗漏）。

本 spec 不追求零 C，而是：① 评估 PTY 社区包替换可行性；② 决策 `mb_system()` 同步语义；③ 残余 C 收敛与统一保留注释。

## 现状分析 [必填 - 含代码验证]

### 验证记录（对抗性审核复核后）

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| tui console_cp FFI | `grep -n "_ffi" lib/tui/console_cp_ext.mbt` | `set_console_utf8_ffi:12, restore_console_cp_ffi:18` | 调用点 :25/:31 ✅ |
| utils 残余 FFI | `grep -n "_ffi" lib/utils/sys_ext.mbt` | `chdir_ffi:10, osrelease_ffi:16`（getcwd 由 S-01 删） | chdir/osrelease 保留 ✅ |
| agent offset 残余 | `grep -n "extern" lib/agent/time.mbt` | `local_offset_minutes_ffi:11 = mbopenclacky_local_offset_minutes`；time_stub.c 实测 39 行（初稿 ~20 偏低） | 保留 ✅ |
| pty FFI | `grep -n "extern \"C\"" lib/tool/pty_ffi.mbt` | `mb_pty_spawn/read/write/close_fd/kill_pid/available/time_ms`（7 个） | PTY 全套 ✅ |
| pty 包装层 | `grep -n "priv struct" lib/tool/pty.mbt` | `PtyHandle:34`，方法 spawn/read_raw/write_raw/close/kill + init/exec_with_marker/read_until_marker | 仅 pty_session.mbt 使用 ✅ |
| tool mb_system | `grep -rn "mb_system" lib cmd --include="*.mbt"` | `terminal_exec.mbt:8` extern 声明 `c_system`，`shell_exec.mbt:184` 调用；`tool_stubs.c:8` 为 C `system()` 强定义 | **仍是同步 C system()**（S-06 并未重写它，初稿正确）✅ |
| PTY Windows 不可用 | `grep -n "_WIN32\|return -1" lib/tool/pty_stubs.c` | `#else /* _WIN32 */` 分支全部 return -1（:290-348） | Windows 回退 system() ✅ |
| 官方无 PTY | 核查报告 §3 + FFI 必要性总结 | core/x/async 均无 PTY；社区 `moonbit-community/pty` 内部 C FFI | ✅ |
| 全项目 C 残留 | `find lib -name '*.c' \| xargs wc -l` | **943 行**（7 文件，见问题描述；初稿 ~850 偏低，且漏计 brand_stubs.c 141 行、crypto_native.c 实 218 非 ~400） | 已修正 ✅ |
| shell_exec 调用栈 async | 追踪见下 | `Tool::execute` 在 S-06 已改 async（`lib/tool/trait.mbt:19`）；`run_shell_command` 全部调用点均可 async | 可换 @async/process ✅ |

### `run_shell_command` 调用点追踪（mb_system 决策依据）

| 调用点 | 所在函数 | async？ |
|--------|---------|---------|
| `lib/tool/terminal.mbt:247`（经 `execute_command_sync`/`execute_command`） | `Terminal::execute` | ✅（trait `async fn execute`，impl 继承 async） |
| `lib/agent/patch_chain.mbt:276`（`execute_hook` ← `check_before`） | `Agent::execute_single_tool`（`tool_executor.mbt:70` 为 `pub async fn`） | ✅ 可传播 |
| `lib/web/ext_dispatcher.mbt:495` | `make_ext_handler` 返回 `async (@crescent.Event) -> &@core.Responder` | ✅ |
| `lib/web/handlers_media.mbt:106,138` | `async fn handle_media_video_understand` | ✅ |
| `cmd/hook_loader.mbt:82`（`execute_hook`） | `cmd/main.mbt:644`，处于 `async fn run_agent` | ✅ 可传播 |
| `cmd/patch_loader.mbt:98`（`apply_patches`） | `cmd/main.mbt:627`，处于 `async fn run_agent` | ✅ 可传播 |

### PTY 社区包评估记录（任务包 1）

- **获取**：`moon add moonbit-community/pty` 成功，版本 **0.2.2**（repo: moonbit-community/tonyfettes-pty）。其依赖 `moonbitlang/async@0.19.4` 由 moon 解析到本项目统一的 **0.20.2**，无版本冲突。
- **API 覆盖**（`pkg.generated.mbti`）：`@pty.spawn(group, argv, cols?, rows?, no_wait?)`（async、TaskGroup 挂载）、`reader() -> @raw_fd.RawFd`（async read）、`write(Bytes)`（async）、`wait() -> Int`（async，真实退出码）、`cancel()`、`close()`、`resize(cols,rows)`、`pid()`。覆盖本项目所需的 spawn/read/write/close/kill/wait/resize 全集。
- **Windows ConPTY**：`pty_win32.c`（373 行）实现 CreatePseudoConsole + CreateProcessA —— 本项目现有 `pty_stubs.c` Windows 分支仅 return -1，**ConPTY 是纯增量能力**。
- **async 集成**：master fd 注册进 `moonbitlang/async` 事件循环，读写挂起而非阻塞线程；现有实现是 C 侧 select 阻塞轮询，会卡住事件循环线程。
- **适配成本**：无 cwd 参数（init 时发 `cd` 行解决）；read_raw 超时用 `@async.with_timeout_opt` 实现；marker 会话逻辑（pty_marker.mbt）原样保留；wasm 目标用 `pty_session_wasm.mbt` 回退。重写集中在 pty.mbt/pty_session.mbt 两文件。
- **结论**：**替换**。三项净增益全部成立——外包维护（853 行平台 C 归上游）、async 集成（消除事件循环阻塞）、Windows ConPTY（从无到有）。非「只换一层包装」。
- **Windows 实机冒烟发现并已修复的三处鲁棒性问题**（本机 bash.exe 解析为 WSL bash，经 ConPTY 真实跑通 PTY 路径）：
  1. **marker 误匹配**：慢 shell 在 `stty -echo` 生效前回显 wrapper，回显文本含 marker 前缀 + `%s` 占位符，旧前缀匹配会误判完成。修复：`read_until_marker` 改为**解析式检测**（`pty_parse_exit_code` 扫全部出现点，只认「前缀 + 数字 + __」）。
  2. **光标寻址吞输出**：bash readline 的 `[?25l`/`[9;1H` 等序列把 marker 与输出并成一行，按行删 marker 会连真实输出一起删。修复：`pty_clean_output` 第一步改为 `pty_truncate_at_marker`（在真实 marker 处截断，marker 之前皆为输出）。
  3. **spawn argv**：bash 以 `--noprofile --norc --noediting -s` 启动，关闭 readline 行编辑（消除 bracketed-paste/光标序列来源）并跳过启动文件噪音；非 bash shell 不加参数。
- **新增 native 冒烟测试** `lib/tool/terminal_exec_smoke_wbtest.mbt`：经 Terminal 工具全链路（PTY 优先、回退兜底）验证 echo 输出与 `(exit 3)` 退出码传播。

### mb_system 决策记录（任务包 2）

- **决策**：**替换为 `@async/process::run`，删除 `tool_stubs.c`**。依据：全部调用点已处于或可传播至 async 上下文（见上表），无需同步语义保留。
- **Windows 实现要点**：`@process.run` 对 argv 做 MSVC 风格转义（`\"`），cmd.exe 不识别——旧 system() 路径之所以能用，是因为 cmd.exe 原样接收命令文本。因此 Windows 上把命令写入临时 `.bat`（首行 `@echo off`，防止批处理回显污染父进程 stdout/测试驱动 NDJSON），以 `cmd.exe /v:on /c <bat>` 执行。Unix 直接 `sh -c`（argv 传递无引号问题）。
- **退出码语义**：`@process.run` 直接返回真实退出码，删除原 Unix 端 `(sys_exit >> 8) & 0xFF` wait-status 移位回退。
- **行为变化（已核实）**：批处理上下文内未定义的 `!VAR!` 延迟展开结果为空串（旧命令行路径下保留字面量）——仅影响 `shell_exec_wbtest` 一处断言，已按新语义更新（测试意图「跨调用不污染环境」不变）。
- **附带修复的潜伏 bug**：`terminal.mbt` Windows 标记原用 `%ERRORLEVEL%`，在单行命令行上于解析期（即命令执行前）展开，永远拿到上一个退出码；bat + /v:on 成为统一路径后改为 `!ERRORLEVEL!` 延迟展开，执行后求值，修复该 bug。

### 残余 C 收敛决策记录（任务包 3）

- **决策**：**保持分散（按包内聚），统一保留注释规范**，不做跨包合并。理由：残余文件分属 4 个独立包（agent/utils/tui/brand），各自有独立依赖图与 native-stub 链接配置；跨包合并至多省 ~30 行，却要新增包间依赖或依赖隐式跨包 C 符号解析，改动风险大于收益。
- 每个保留 C 文件头部已补「RETAINED (S-FFI-08) + 保留理由 + 引用核查报告章节 + 本 spec」注释。

## 决策 [必填 - 含为什么]

1. **PTY：替换为 `moonbit-community/pty@0.2.2`**：净增益明确（上游维护 + async 事件循环集成 + Windows ConPTY 从无到有）；删除本地 `pty_stubs.c`（348 行）/`pty_ffi.mbt`/`pty_ffi_wasm.mbt`。
2. **`mb_system()`：换 `@async/process::run`，删除 `tool_stubs.c`**：调用栈已全部 async（S-06 后 `Tool::execute` 为 async，`cmd/main.mbt` 为 `async fn main`）；Windows 侧经临时 .bat 规避 cmd.exe 不识别 MSVC argv 转义的问题。
3. **残余 C 保持分散、统一注释**：跨包合并收益不明显且引入耦合；以统一「RETAINED」注释承载保留理由。
4. **crypto/brand-stubs 保留有据**：注释引用核查报告 §9 与 FFI 必要性总结（密码学原语 — 成立）。

MoonBit AOT 约束检查：无动态加载 trait，无影响。

## 改动范围 [必填]

### 涉及文件（实际）

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tool/pty_stubs.c` / `pty_ffi.mbt` / `pty_ffi_wasm.mbt` | 删除 | 由 moonbit-community/pty 替代 |
| `lib/tool/pty.mbt` | 重写 | PtyHandle 基于 `@pty.Pty`，全 async；marker 逻辑保留 |
| `lib/tool/pty_session.mbt` | 重写 | `execute_command`/`execute_command_pty` 改 async + TaskGroup |
| `lib/tool/pty_session_wasm.mbt` | 新增 | wasm 回退（无 PTY，直连 execute_command_sync stub） |
| `lib/tool/tool_stubs.c` | 删除 | mb_system 由 @async/process 替代 |
| `lib/tool/terminal_exec.mbt` / `terminal_exec_wasm.mbt` | 重写 | `async run_system_command`：Unix `sh -c`；Windows 临时 .bat + `cmd.exe /v:on /c` |
| `lib/tool/shell_exec.mbt` | 修改 | `run_shell_command` 改 async；删 `to_c_string`；退出码回退去 wait-status 移位 |
| `lib/tool/terminal.mbt` | 修改 | `execute_command_sync` 改 async；删 cmd.exe/sh -c 字符串包装层 |
| `lib/tool/moon.pkg` | 修改 | 删 native-stub；targets 更新；import 增加 async/process、moonbit-community/pty |
| `lib/agent/patch_chain.mbt` | 修改 | `check_before`/`execute_hook` 改 async（`check_after` 无 shell 调用，保持同步） |
| `cmd/hook_loader.mbt` / `cmd/patch_loader.mbt` | 修改 | `execute_hook`/`apply_patches` 改 async（`Map.each` 闭包改为 for 循环） |
| `lib/web/ext_dispatcher.mbt` | 修改 | handler 闭包显式 `async fn` 标注 |
| 测试 | 修改 | shell_exec/patch_chain/extension/web/cmd 相关 wbtest 改 `async test`；一处 Windows 断言按 bat 语义更新；lib/extension/moon.pkg 增加 async import（测试需要） |
| `moon.mod` | 修改 | `moon add moonbit-community/pty@0.2.2` |
| 5 个保留 C 文件 | 注释 | RETAINED 头部注释（见任务包 3） |

### 不涉及文件

- `lib/brand/crypto_native.c`、`lib/brand/brand_stubs.c`（仅加注释，逻辑不动）
- `moonbit-community/tty`（TUI 底层，不在本项目范围）

## 实施计划 [必填]

### 任务包 1：PTY 社区包评估（实际 ~0.5 天）
- 拉取 `moonbit-community/pty@0.2.2`，核对 API/ConPTY/async 集成 → **替换**（评估记录见上）
- 重写 pty.mbt/pty_session.mbt，删 pty_stubs.c/pty_ffi*.mbt，新增 wasm 回退

### 任务包 2：mb_system 同步语义决策（实际 ~0.5 天）
- 调用栈追踪确认全 async → 换 `@async/process::run`，删 tool_stubs.c
- Windows .bat 方案规避 cmd.exe argv 转义问题

### 任务包 3：残余 C 收敛 + 注释（实际 ~0.5 天）
- 决策：保持分散 + 统一 RETAINED 注释（理由见上）
- 验证门：`moon check` + 全量 `moon test`

## 验收标准 [必填]

- [x] `moon check` 0 errors
- [x] 全量 `moon test` 通过（3061/3061 = S-07 基线 3059 + 新增 2 个 PTY 冒烟测试）
- [x] PTY 评估有明确结论：**替换**（moonbit-community/pty@0.2.2，理由见评估记录）
- [x] `mb_system()` 决策有明确结论：**替换为 @async/process**，tool_stubs.c 已删
- [x] 每个保留的 C 文件含「保留理由 + 引用」注释
- [x] `moon fmt` 通过
- [x] `moon build --target native --release cmd` 成功；`moon info` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 | 实际结果 |
|------|------|---------|---------|
| 社区 pty API 不全/不稳定 | PTY 功能退化 | 评估不通过则保留现状 | 未发生：API 覆盖全集且解析到统一 async 0.20.2 |
| mb_system 改 async 破坏同步契约 | 调用点行为变 | 全调用点追踪 + 全量测试 | 未发生：6 个调用点全部可 async，3059 测试全过 |
| Windows cmd.exe 不识别 @process 的 MSVC argv 转义 | shell 执行全失败 | 临时 .bat 方案 + `@echo off` 防 stdout 污染 | 已解决（测试驱动 NDJSON 被回显污染即由此发现） |
| Windows 上 ConPTY 首次激活 PTY 路径 | 行为差异 | bash.exe 不在 PATH 时 spawn 失败自动回退 @process 路径 | 冒烟验证通过 |
| 残余收敛改动引入回归 | 构建失败 | 决策为不合并、仅注释 | 未发生 |

## 依赖关系 [必填]

- **前置依赖**：S-01~07（前面迁移稳定后再收敛残余，避免交叉干扰）
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-25 | 初始版本 | 依据 reduce-ffi-c-dependency-plan.md §7 |
| 2026-07-25 | 对抗性审核：实测 C 残留 943 行（初稿 ~850 偏低；漏计 brand_stubs.c 141 行；crypto_native.c 实 218 非 ~400；time_stub.c 实 39 非 ~20）；确认 mb_system 仍是 C system()（S-06 未重写它）；确认 shell_exec 调用栈全 async | Harness v2 审核清单复核「验证记录」 |
| 2026-07-25 | PTY 评估结论：**替换**（moonbit-community/pty@0.2.2，三项净增益成立）；mb_system 决策：**换 @async/process**（删除 tool_stubs.c，Windows 走临时 .bat）；残余 C 决策：**保持分散 + 统一 RETAINED 注释** | 三个任务包实施完成 |
| 2026-07-25 | 完成：moon check 0 errors；moon test 3061/3061；release build 成功（cmd.exe 可运行）；fmt/info 通过。最终残余 C：5 文件 610 行（time_stub.c 44 + sys_native.c 140 + console_cp_native.c 58 + crypto_native.c 222 + brand_stubs.c 146；较收敛前增量为 RETAINED 注释行；较本 spec 前 943 行净删 333 行：pty_stubs.c 348 + tool_stubs.c 10 删除，注释 +25） | 验收通过，归档 specs/completed/ |
