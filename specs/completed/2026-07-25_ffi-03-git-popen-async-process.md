# git 命令 popen 迁移至 @async/process · 增量 Spec

> **创建日期**: 2026-07-25
> **状态**: 已完成
> **关联总览**: `2026-07-25_ffi-c-reduction-overview.md`（S-FFI-03）
> **来源差距**: `docs/ffi-c-code-report.md` 第 5、6 节
> **依赖**: 无
> **后置**: 被 S-04 复用 `@async/process` 用法

## 问题描述 [必填]

两处 git 命令执行依赖 C，但**对抗性审核发现其中一处是纯死代码**：

1. `lib/server/git_exec.c`（124 行）+ `lib/server/git_exec.mbt`（29 行）：`popen()` 捕获 git 输出。**`run_git_command` 无任何调用方**——全项目 grep 仅命中自身定义、`pkg.generated.mbti` 导出和 specs 文档。应直接删除，而非迁移。

2. `lib/web/git_exec.c`（6 行）+ `lib/web/git_exec.mbt`（45 行）：`system()` 把输出重定向到临时文件再读回（`git_capture_output`），是缺少 popen 时的 workaround。**9 个非 session 版 `handle_git_*` handler 也是死代码**——`lib/web/server.mbt` 中无路由注册，无调用方。真正在用的是 5 个 `handle_session_git_*` 端点（`server.mbt:243-256`）。

因此本 spec 的实际工作：
- **删除** `lib/server/git_exec.c` + `lib/server/git_exec.mbt`（死代码）
- **删除** `lib/web/handlers_git.mbt` 中 9 个非 session `handle_git_*` handler（死代码）
- **迁移** `lib/web/git_exec.mbt` 的 `git_capture_output`/`git_run`/`git_run_in_dir` 到 `@async/process`，供 5 个 session handler 使用
- **删除** `lib/web/git_exec.c`，从 `lib/web/moon.pkg` 移除 `native-stub` 项

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| server `run_git_command` 是死代码 | `grep -rn 'run_git_command' lib/ cmd/ --include='*.mbt'` | 仅命中 `lib/server/git_exec.mbt` 自身 + `pkg.generated.mbti` | 确认无调用方 |
| web 9 个非 session handler 无路由注册 | `grep -n 'handle_git_status\|...\|handle_git_checkout' lib/web/server.mbt` | 0 命中 | 确认死代码 |
| web 5 个 session handler 有路由注册 | `grep -n 'handle_session_git' lib/web/server.mbt` | `:243-256` 5 条路由 | 确认活跃代码 |
| `lib/web/git_exec.mbt` 被 session handler 调用 | `cat lib/web/handlers_git.mbt` | `is_git_repo`/`git_run_in_dir`/`git_run` 被 5 个 session handler 使用 | 确认需迁移 |
| `@async/process` 支持 `cwd` 参数 | `grep -n 'cwd' .mooncakes/moonbitlang/async/src/process/process.mbt` | `run()` 和 `collect_output()` 均有 `cwd? : StringView` | 可替代 `cd dir && git ...` 拼接 |
| crescent handler 是 async | `grep -n 'HttpHandler' .mooncakes/hnlyxiaobing/crescent/src/handler.mbt` | `struct HttpHandler(async (Event) -> &Responder noraise)` | handler 可直接改 async |
| `lib/web` 已 import `moonbitlang/async` | `grep async lib/web/moon.pkg` | 已 import | 无需新增依赖 |
| `lib/server` 未 import `moonbitlang/async` | `grep async lib/server/moon.pkg` | 未 import | 但 server 侧整文件删除，无需 import |

### 详细分析

**lib/server 侧（删除）**：
- `lib/server/git_exec.mbt`：`pub fn run_git_command(command: String) -> String`（native 用 `git_exec_ffi`，wasm 返回 `""`）。
- `lib/server/git_exec.c`：124 行，`popen()` + 动态 buffer + UTF-8↔UTF-16 转换。
- 结论：整文件删除，`lib/server/moon.pkg` 的 `native-stub` 移除 `git_exec.c`（保留 `browser_process.c` 给 S-04）。

**lib/web 侧（迁移 + 删除死代码）**：
- `lib/web/git_exec.mbt`：`git_capture_output` 构造 `sh -c '... > .git_panel_output.tmp 2>&1'`，调 `system()`，再 `@fs.read_file_to_string` 读回。临时文件 workaround 删后可消失。
- `lib/web/handlers_git.mbt`（601 行）：
  - 5 个 session handler（`handle_session_git_status/diff/log/branches/commit`）：活跃，需迁移。
  - 9 个非 session handler（`handle_git_status/diff/stage/unstage/commit/push/pull/branches/checkout`）：死代码，删除。
  - 辅助函数：`git_capture_output`/`git_run`/`git_run_in_dir`/`is_git_repo`/`git_shell_escape`/`git_output_is_error`/`parse_git_files`/`git_split_lines`/`session_working_dir` 等。其中 `git_capture_output`/`git_run`/`git_run_in_dir` 需改 async；`is_git_repo` 内部调用 `git_capture_output`，也需改 async。

**API 映射**：
- 原：`git_capture_output("cd " + escape(dir) + " && git " + args)` → 返回 `String`
- 新：`@async/process::collect_output("git", [args], cwd=dir)` → 返回 `(Int, &@io.Data, &@io.Data)`，取 stdout 转 String
- 原 `git_run(args)`（当前目录）→ `collect_output("git", [args])`
- 原 `git_run_in_dir(dir, args)` → `collect_output("git", [args], cwd=dir)`

**参数数组化 vs shell 拼接**：
- 原代码用字符串拼接 `git commit -m 'msg'`，`git_shell_escape` 做 POSIX 单引号转义。
- `@async/process::collect_output` 接受 `ArrayView[String]`，无需 shell 转义，更安全。
- 但 `git diff HEAD -- file` 这类多参数命令需拆成数组：`["diff", "HEAD", "--", file]`。
- `git add file1 file2` 需拆成 `["add", "file1", "file2"]`。
- 因此 `git_run`/`git_run_in_dir` 的签名应从 `String` 改为 `Array[String]`，调用点同步调整。

## 决策 [必填 - 含为什么]

1. **server 侧直接删除而非迁移**：`run_git_command` 无调用方，迁移是浪费。删除 `git_exec.c` + `git_exec.mbt` 即完成 server 侧 FFI 消减。
2. **web 侧删除 9 个非 session handler**：无路由注册、无调用方，属于历史遗留。保留只会让 `handlers_git.mbt` 从 601 行膨胀到更多，删除后文件聚焦 session 端点。
3. **web 侧 `git_capture_output`/`git_run`/`git_run_in_dir` 改 async + 参数数组化**：`@async/process::collect_output` 是官方 popen 等价物，参数数组化消除 shell 注入面，删除临时文件 workaround。
4. **不引入 `@async.run` 桥接**：crescent handler 已是 async，session handler 可直接改 async，无需桥接。

MoonBit AOT 约束检查：无动态加载 trait，无影响。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/server/git_exec.mbt` | 删除 | 整文件，死代码 |
| `lib/server/git_exec.c` | 删除 | 整文件 |
| `lib/server/moon.pkg` | 修改 | `native-stub` 移除 `git_exec.c`（保留 `browser_process.c`） |
| `lib/web/git_exec.mbt` | 重写 | `git_capture_output`/`git_run`/`git_run_in_dir` 改 `@async/process::collect_output`，参数从 `String` 改 `Array[String]`，删临时文件逻辑 |
| `lib/web/git_exec.c` | 删除 | 整文件 |
| `lib/web/moon.pkg` | 修改 | `native-stub` 移除 `git_exec.c`（保留 `multipart_upload.c` 给 S-05） |
| `lib/web/handlers_git.mbt` | 重写 | 删除 9 个非 session handler；5 个 session handler + 辅助函数改 async；`git_run`/`git_run_in_dir` 调用点改数组参数 |
| `lib/web/pkg.generated.mbti` | 重新生成 | `moon info` 自动更新 |

### 不涉及文件

- `lib/web/multipart_upload.c`（S-05 处理）
- `lib/server/browser_process.c`（S-04 处理）
- `lib/web/server.mbt`：路由注册不变（session 端点已注册，非 session 端点本就不存在）

## 实施计划 [必填]

### 任务包 1：删除 server 侧死代码（预估 0.5 天）
- 删除 `lib/server/git_exec.mbt`、`lib/server/git_exec.c`
- 修改 `lib/server/moon.pkg`：`native-stub` 移除 `git_exec.c`
- 验证门：`moon check lib/server` 0 errors

### 任务包 2：web 侧 git_exec 迁移（预估 1 天）
- 重写 `lib/web/git_exec.mbt`：
  - `git_capture_output` 删除（被 `collect_output` 替代）
  - `git_run(args : Array[String]) -> String`：当前目录，调 `collect_output("git", args)`
  - `git_run_in_dir(dir : String, args : Array[String]) -> String`：调 `collect_output("git", args, cwd=dir)`
  - 两者均 async，返回 stdout 的 String 表示
  - 删除 `git_system_ffi` extern C 声明、`git_run_command`、临时文件逻辑
- 删除 `lib/web/git_exec.c`
- 修改 `lib/web/moon.pkg`：`native-stub` 移除 `git_exec.c`
- 验证门：`moon check lib/web` 0 errors

### 任务包 3：web 侧 handlers_git 重写（预估 1 天）
- 删除 9 个非 session `handle_git_*` handler
- 5 个 session handler 改 `pub async fn`
- 辅助函数 `is_git_repo` 改 async（内部调 `git_run_in_dir`）
- 所有 `git_run`/`git_run_in_dir` 调用点从字符串拼接改数组参数
  - 例：`git_run("status --porcelain")` → `git_run(["status", "--porcelain"])`
  - 例：`git_run_in_dir(dir, "commit -m " + escape(msg))` → `git_run_in_dir(dir, ["commit", "-m", msg])`
  - 例：`git_run_in_dir(dir, "diff HEAD -- " + escape(file))` → `git_run_in_dir(dir, ["diff", "HEAD", "--", file])`
- `git_shell_escape` 函数删除（参数数组化后不再需要）
- 验证门：`moon check lib/web` 0 errors

### 任务包 4：集成验证（预估 0.5 天）
- `moon fmt`
- `moon info`（重新生成 `pkg.generated.mbti`）
- `moon check` 全项目 0 errors
- `moon test lib/web`（git 面板相关测试不回归）
- `moon test lib/server`（不回归）
- `moon build --target native --release cmd` 确认可构建

## 验收标准 [必填]

- [ ] `lib/server/git_exec.c`、`lib/server/git_exec.mbt` 已删除
- [ ] `lib/web/git_exec.c` 已删除
- [ ] `lib/web/handlers_git.mbt` 中 9 个非 session handler 已删除
- [ ] `lib/web/git_exec.mbt` 无 `system()`/`popen` FFI，无临时文件逻辑
- [ ] `git_run`/`git_run_in_dir` 使用 `@async/process::collect_output`，参数为 `Array[String]`
- [ ] 5 个 session handler 为 `pub async fn`
- [ ] `moon check` 0 errors（全项目）
- [ ] `moon test lib/web` 通过
- [ ] `moon test lib/server` 通过
- [ ] `moon fmt` 通过
- [ ] `moon info` 通过，`pkg.generated.mbti` 已更新
- [ ] 不再产生 `.git_panel_output.tmp` 临时文件

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| `collect_output` 返回 `&@io.Data` 转 String 方式不确定 | 实现阻塞 | 查 `@io.Data` API（`to_string()`/`read_all()` 等），参考 `moonbitlang/async` 其他用法 |
| 参数数组化后 `git_shell_escape` 删除，但某些路径含空格 | 行为差异 | `collect_output` 直接传参数数组，无 shell 解析，天然安全；测试含空格路径场景 |
| session handler 改 async 后 crescent 路由注册不兼容 | 编译错误 | 已验证 `HttpHandler` 是 `async (Event) -> &Responder noraise`，直接兼容 |
| `is_git_repo` 中 `git rev-parse --is-inside-work-tree` 的 exit code 非 0 时行为 | 误判非 repo | 原代码读 stdout 判断 `"true"`，新代码同样读 stdout；exit code 非 0 时 stdout 为空，自然走 `!= "true"` 分支，行为一致 |
| 删除 9 个非 session handler 后，前端是否有调用 | 前端 404 | 已验证无路由注册，前端不可能调用到这些端点；若前端有硬编码 URL，会在网络层 404，非本 spec 引入的问题 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：S-04 复用本 spec 建立的 `@async/process` 用法范式

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-25 | 初始版本 | 依据 reduce-ffi-c-dependency-plan.md §5.1 |
| 2026-07-25 | 对抗性审核修订 | 发现 server 侧 `run_git_command` 和 web 侧 9 个非 session handler 均为死代码，方案从「迁移」改为「删除死代码 + 迁移活跃代码」；参数从 shell 拼接改数组化；删除 `git_shell_escape` |
