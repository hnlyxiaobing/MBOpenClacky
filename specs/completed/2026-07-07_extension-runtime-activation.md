# Extension Runtime System 激活（让扩展 API 真正可执行）· 增量 Spec

> **创建日期**: 2026-07-07  
> **状态**: 已评审，进入实施  
> **关联历史 spec**: `specs/completed/2026-07-07_cmd-stub-activation.md`（AOT shell 执行模式确立）  
> **灰度 key**: N/A

## 问题描述

`lib/web/ext_dispatcher.mbt` 的 `make_ext_handler()` 当前返回桩 JSON：

```json
{"extension":"meeting","handler":"transcribe","timeout_ms":30000,"status":"stub"}
```

这意味着所有通过 `/api/ext/<name>/` 挂载的扩展路由虽然能正确注册到 crescent 路由表，但请求到达后只会返回一个 `"status":"stub"` 的占位响应——**扩展 API 完全不可用**。

原项目 OpenClacky 的扩展系统是一个核心差异化能力：

| 维度 | 原项目 (Ruby) | MBOpenClacky 现状 |
|------|-------------|-------------------|
| 扩展容器发现 | `ExtensionLoader`（483 行）三层源（builtin/installed/local）+ `ext.yml` 解析 | ❌ 缺失（`ext_loader.mbt` 只读 JSON/TOML 路由描述符） |
| API 路由执行 | `ApiExtension` 基类 + route DSL + `require` 动态加载 handler.rb | ❌ 桩响应 |
| 超时与错误信封 | `ApiExtensionDispatcher`（133 行）timeout + JSON error envelope | ❌ 无执行 |
| 6 个内置扩展 | coding、ext-studio、general、git、meeting、time_machine | ❌ 0 个可用 |
| 扩展贡献类型 | panels / api / skills / agents / channels / patches / hooks（7 种） | ⚠️ 仅 api 路由注册（桩），其余 6 种未实现 |

cmd-stub-activation spec 已明确将"扩展运行时"划归为独立的 web 任务包——**本 spec 即为该任务包**。

## 现状分析（代码地形）

### 已就绪的基础设施

1. **`lib/web/ext_loader.mbt`**（190 行）— 能解析 JSON 扩展描述符，产出 `ApiExtension` 结构体（name、version、routes[]、enabled）。
   > **评审核实**：TOML 分支（`parse_ext_simple`）只解析 `name`/`version`/`enabled` 三个顶层键，**routes 恒为空数组**——TOML 描述符实际不能定义路由。本 spec 的 `command` 字段仅在 JSON 描述符中支持，TOML 描述符维持现状（不扩展）。
2. **`lib/web/ext_dispatcher.mbt`**（116 行）— 能将 enabled 扩展的路由注册到 crescent App，路由方法映射正确（GET/POST/PUT/DELETE）。
   > **评审核实**：路由挂载在 server.mbt 的 `/api` group 内的 `/ext` 子组，最终路径为 `/api/ext/<name>/<path>`（dispatcher 内注释 [C2] 已说明避免双重 `/api` 前缀）。**注意：`/api/ext/*` 受全局 auth 中间件保护**，端到端验证需携带 API Key（或不设置 `MBOPENCLACKY_WEB_API_KEY` 启动）。
3. **`lib/web/server.mbt`** — 启动时调用 `load_api_extensions()` + `ExtensionDispatcher::new()` + `register_routes()`
4. **`cmd/shell_exec.mbt`**（179 行）— cmd-stub-activation 已建立 `run_shell_command()` helper：
   - `mb_system` C FFI（`lib/tool/tool_stubs.c`）执行 shell 命令
   - 输出重定向到临时文件 + `__CLACKY_DONE_<token>_<exitcode>__` marker
   - 环境变量注入（执行前 set、执行后 unset）——**见下方并发警告**
   - 跨平台（Windows `cmd.exe /c` / Unix `sh -c`）
   - UTF-8 NUL 终止 C 字符串转换
5. **`lib/web/middleware/`** — auth、timeout、error_envelope 中间件已实现

> **⚠️ 评审发现（并发安全）**：`run_shell_command` 当前通过
> `@sys.set_env_var` / `unset_env_var` 修改**父进程全局环境**来传递 env vars。
> cmd 层（hook/patch）是顺序执行没有问题，但 web server 是并发处理请求的——
> 两个扩展请求同时进入会互相污染 `CLACKY_EXT_*` 变量。提升到 lib 层时必须改为
> **env 内联到命令前缀**：Unix 用 `env 'K=V' ... sh -c '<cmd>'`（或 `K=V K2=V2 <cmd>`，
> 值需 shell 转义），Windows 用 `cmd /c "set K=V&& set K2=V2&& <cmd>"`。
> 同理，输出临时文件名的 `shell_exec_counter` 全局计数器在并发下需保证唯一性
> （计数器 + 时间戳组合即可，MoonBit native 单线程 event loop 下计数器自增本身无 race）。

### 核心差距

```
原项目执行链：
  HTTP 请求 → dispatcher.handle() → ApiExtensionLoader.ensure_fresh(ext_id)
           → klass = registry[ext_id]  (动态 require 的 Ruby 类)
           → instance = klass.new(req, res, route, params, http_server)
           → instance.invoke()  → 路由 block 执行 → json/text/error! halt
           → timeout 包裹 + JSON error envelope

MBOpenClacky 执行链（目标）：
  HTTP 请求 → crescent 路由匹配 → make_ext_handler 闭包
           → [当前断点] 返回 stub JSON
           → [目标] 构造请求上下文 → 执行 handler command → 捕获输出 → 返回响应
```

**MoonBit 是 AOT 编译语言**，无法像 Ruby 那样运行时 `require` handler 文件。cmd-stub-activation spec 已确立：动态行为通过 **shell command 执行** 实现（hook、patch 均如此）。

### 原项目 handler 上下文（需要在 MoonBit 版本中映射）

| Ruby handler 上下文 | MoonBit 等价方案 |
|---------------------|------------------|
| `req.method` / `req.path` | 环境变量 `CLACKY_EXT_METHOD` / `CLACKY_EXT_PATH` |
| `params`（路径参数） | 环境变量 `CLACKY_EXT_PARAMS`（JSON） |
| `query`（查询参数） | 环境变量 `CLACKY_EXT_QUERY`（原始 query string） |
| `json_body`（请求体） | 临时文件 `CLACKY_EXT_BODY_FILE`（JSON body 写入文件，脚本读取） |
| `session_manager` / `config` | 环境变量 `CLACKY_CONFIG_DIR`（指向 ~/.clacky/，脚本自行读取） |
| `json(data)` / `text(str)` | 脚本 stdout 输出（JSON 或纯文本，由 Content-Type header 指示） |
| `error!(msg, status)` | 脚本 stderr 输出 JSON `{"error":"...","status":4xx}` + 非零退出码 |
| `timeout` 包裹 | Unix: `timeout <sec>` 命令包裹；Windows: 文档注明限制 |

## 决策

### 决策 1：handler 执行用 shell command 模式（与 hook/patch 同构）

**为什么**：cmd-stub-activation 已验证此模式可行且跨平台。MoonBit AOT 无法动态加载代码，shell 执行是唯一诚实的运行时扩展方案。handler 脚本可以是任意语言（Ruby/Python/Shell/Node），只要能读环境变量 + stdin/文件、写 stdout。

### 决策 2：扩展描述符新增 `command` 字段

**当前** `ExtensionRoute` 只有 `handler_name`（逻辑名）。**新增** `command` 字段指定要执行的 shell 命令：

```json
{
  "name": "meeting",
  "version": "0.1.0",
  "enabled": true,
  "routes": [
    {
      "method": "POST",
      "path": "/transcribe",
      "handler_name": "transcribe",
      "command": "ruby ~/.clacky/ext/local/meeting/api/transcribe.rb",
      "timeout_ms": 30000
    }
  ]
}
```

**为什么**：与 patch descriptor 的 `command` 字段同构。每个路由绑定一个命令，调度时执行该命令。支持 `~` 展开（home 目录）。无 `command` 的路由回退到桩响应并记录警告。

> **评审修正**：仅 JSON 描述符支持 `command`。TOML 简易格式（`parse_ext_simple`）
> 本就不支持 routes（恒为空数组，已核实），不在本 spec 扩展。

### 决策 3：请求上下文通过环境变量 + 临时文件传递

- 环境变量：`CLACKY_EXT_NAME`、`CLACKY_EXT_ROUTE`、`CLACKY_EXT_METHOD`、`CLACKY_EXT_PATH`、`CLACKY_EXT_QUERY`、`CLACKY_EXT_PARAMS`（JSON）、`CLACKY_CONFIG_DIR`
- 请求体：写入临时文件，路径通过 `CLACKY_EXT_BODY_FILE` 环境变量传递
- 脚本输出：stdout 全部捕获作为响应体

**为什么**：环境变量是最通用的跨语言传递方式。请求体可能很大，用文件避免命令行参数长度限制。

> **评审修正（并发安全）**：env vars **不得**沿用 cmd 层"父进程 set/unset"方式
> （web server 并发请求会互相污染）。lib 层 `run_shell_command` 必须把 env 内联
> 进子进程命令：Unix 前缀 `env 'K=V' ...`（值单引号转义），Windows 用
> `set K=V&& ...` 链。这是阶段 1 的硬性要求，不是可选优化。

### 决策 4：响应协议 — stdout 为响应体，退出码决定状态

- 退出码 0：stdout 作为 HTTP 200 响应体（默认 `Content-Type: application/json`）
- 退出码非 0：stderr 解析为 JSON `{"error":"...","status":N}`，返回对应 HTTP 状态码；解析失败则返回 500 + 原始 stderr
- 脚本可通过 stdout 第一行输出 `Content-Type: <type>` header 覆盖默认类型

**为什么**：简洁、可测试、与 Unix 工具链一致。

### 决策 5：超时用 `timeout` 命令包裹（Unix），Windows 文档注明

- Unix：`timeout <sec> <command>`，超时返回 504 Gateway Timeout
- Windows：`mb_system` 无超时能力，handler 应自行快速返回；文档注明限制

**为什么**：与 cmd-stub-activation 中 hook 超时方案一致，不引入新依赖。

### 决策 6：错误信封复用已有 `error_envelope.mbt`

已有的 `lib/web/middleware/error_envelope.mbt` 统一错误格式，扩展 handler 错误也走此信封：

```json
{"error": "handler script exited with code 1", "code": "EXT_EXEC_ERROR", "hint": "Check stderr output"}
```

## 改动范围

- **涉及包**：`lib/web`（主要）、`cmd/`（shell_exec 迁移到 lib 共享）
- **涉及文件**：
  - `lib/web/ext_dispatcher.mbt` — `make_ext_handler` 重写为真实 shell 执行
  - `lib/web/ext_loader.mbt` — `ExtensionRoute` 新增 `command` 字段 + `~` 展开
  - `lib/web/ext_dispatcher.mbt` — 新增请求上下文构造、超时包裹、响应解析
  - `lib/web/handlers_ext.mbt`（新建或合入 ext_dispatcher）— 可选：REST 端点查询扩展状态
  - `lib/web/ext_dispatcher_wbtest.mbt`（新建）— 单元测试
  - `lib/tool/shell_exec.mbt`（新建）— 将 `cmd/shell_exec.mbt` 的 `run_shell_command` 提升到 lib 层共享
  - `lib/tool/moon.pkg` — 声明 `mb_system` extern（如果尚未暴露）
  - `cmd/shell_exec.mbt` — 改为引用 `lib/tool/shell_exec.mbt`
- **不涉及**：
  - 扩展容器发现（`ext.yml` 三层源扫描）— 属于后续 `extension-loader-comprehensive` spec
  - panel/skill/agent/channel/patch/hook 贡献类型 — 各自独立 spec
  - 扩展热重载（`ensure_fresh`）— AOT 下无意义，不做
  - 路径参数正则匹配（`/users/:id`）— 当前用精确路径匹配，正则匹配属后续增量

## 实施计划

### 阶段 1：shell_exec 提升到 lib 层（0.5 天）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 1.1 | `lib/tool/shell_exec.mbt`（新建） | 从 `cmd/shell_exec.mbt` 移植 `run_shell_command`、`to_c_string`、marker 解析；**env vars 改为内联进命令前缀**（Unix `env 'K=V'` / Windows `set K=V&&`），不再修改父进程环境 |
| 1.2 | `lib/tool/shell_exec.mbt` | 复用已有 `mb_system` FFI（`terminal_exec.mbt` 已声明 `c_system`；同包可直接复用或另声明同名 extern，`tool_stubs.c` 无需改动） |
| 1.3 | `cmd/moon.pkg` + `cmd/shell_exec.mbt` | cmd/moon.pkg **新增 `lib/tool` import**（评审核实：当前未导入），`cmd/shell_exec.mbt` 删除，调用点改为 `@tool.run_shell_command`；`cmd/cmd_stub_activation_wbtest.mbt` 中相关测试同步迁移/改引用 |
| 1.4 | `lib/tool/shell_exec_wbtest.mbt`（新建） | 基础测试：echo 命令、退出码、env 内联传递、两次调用互不污染 |

### 阶段 2：ExtensionRoute 扩展 + 描述符解析（0.5 天）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 2.1 | `lib/web/ext_loader.mbt` | `ExtensionRoute` 新增 `command : String` 字段 |
| 2.2 | `lib/web/ext_loader.mbt` | `parse_ext_json` 解析 `command` 字段 + `~` 展开为 home 目录 |
| 2.3 | `lib/web/ext_loader.mbt` | 无 `command` 的路由标记 `command = ""`，dispatcher 回退桩响应 |

### 阶段 3：make_ext_handler 真实实现（1 天）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 3.1 | `lib/web/ext_dispatcher.mbt` | 重写 `make_ext_handler` 为 async 闭包，执行 `route.command` |
| 3.2 | `lib/web/ext_dispatcher.mbt` | 新增 `build_ext_env_vars()`：构造 CLACKY_EXT_* 环境变量 |
| 3.3 | `lib/web/ext_dispatcher.mbt` | 新增 `write_body_to_temp()`：请求体写入临时文件 |
| 3.4 | `lib/web/ext_dispatcher.mbt` | 新增 `parse_ext_response()`：解析 stdout + 退出码 → HttpResponse |
| 3.5 | `lib/web/ext_dispatcher.mbt` | 超时包裹：Unix 用 `timeout <sec>` 前缀 |
| 3.6 | `lib/web/ext_dispatcher.mbt` | 无 `command` 的路由回退桩响应 + `println` 警告 |

### 阶段 4：测试与验证（0.5 天）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 4.1 | `lib/web/ext_dispatcher_wbtest.mbt`（新建） | 测试：有 command 路由执行真实脚本、无 command 回退桩、超时处理、退出码映射 |
| 4.2 | 创建测试扩展 | `~/.clacky/api_extensions/test-echo.json` + 一个 echo 脚本 |
| 4.3 | 端到端验证 | 启动 server，curl `/api/ext/test-echo/hello` 验证真实执行 |

## 验收标准

- [ ] `ExtensionRoute` 新增 `command` 字段，JSON 描述符正确解析
- [ ] 有 `command` 的路由：执行 shell 命令，返回真实 stdout 作为响应体
- [ ] 无 `command` 的路由：回退桩响应 + 控制台警告日志
- [ ] handler 脚本可通过环境变量读取 `CLACKY_EXT_NAME`/`CLACKY_EXT_METHOD`/`CLACKY_EXT_PATH`/`CLACKY_EXT_QUERY`
- [ ] handler 脚本可通过 `CLACKY_EXT_BODY_FILE` 环境变量读取请求体
- [ ] 退出码 0 → HTTP 200；非 0 → stderr 解析为错误信封，HTTP 状态码映射
- [ ] Unix 下 `timeout` 命令包裹生效（超时返回 504）
- [ ] `~` 在 command 中展开为 home 目录
- [ ] `shell_exec` 成功从 cmd 层提升到 lib/tool 层，env 传递改为命令内联（并发安全），cmd 层调用点改引用 `@tool.run_shell_command`
- [ ] `moon check` 0 errors
- [ ] `moon test lib/web` 全部通过
- [ ] `moon test lib/tool` 全部通过
- [ ] 端到端：创建测试扩展 + echo 脚本，curl（携带 API Key 或无 key 启动）验证真实执行

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| handler 执行任意 shell 命令 | 高（本身即设计目的） | 仅从 `~/.clacky/api_extensions/` 加载；enabled=false 可禁用；执行前打印命令日志；`/api/ext/*` 本身受全局 auth 中间件保护 |
| shell_exec 提升到 lib 层影响 cmd 链接 | 中 | **评审核实：cmd/moon.pkg 当前并未 import lib/tool**，需新增 import；`mb_system` 符号在 libtool.a 中已存在，链接无冲突；增量验证 `moon build cmd` |
| web 并发请求下 env vars 互相污染 | 高 | **必须** env 内联进命令（决策 3 评审修正）；不复用 cmd 层 set/unset 模式 |
| 请求体大文件写入临时目录 | 低 | 使用 @path TEMP 目录；执行后删除临时文件 |
| Windows 无 timeout 包裹 | 低 | 文档注明；handler 应快速返回；后续可考虑 Job Object 超时 |
| stdout 二进制数据（图片等） | 低 | 当前仅支持文本响应；二进制响应属后续增量 |
| 路径参数未实现（`:id` 正则匹配） | 低 | 当前精确路径匹配；正则匹配属后续增量 spec |

## 明确不做

- ❌ 扩展容器三层源发现（builtin/installed/local + ext.yml）— 独立 spec
- ❌ panel/skill/agent/channel/patch/hook 贡献类型 — 各自独立 spec
- ❌ 扩展热重载 — AOT 下无意义
- ❌ 路径参数正则匹配（`/users/:id`）— 后续增量
- ❌ 二进制响应（图片/文件下载）— 后续增量
- ❌ `clacky ext` CLI 子命令 — 独立 spec

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-07 | 初始版本 | 项目对比分析识别为最高优先级开发点 |
| 2026-07-07 | 评审修正：env vars 必须内联进命令（web 并发安全，硬性要求）；cmd/moon.pkg 需新增 lib/tool import（原文"cmd 已链接 tool"不实）；TOML 描述符不支持 routes（不扩展 command）；端到端验证需带 API Key；实施计划阶段 1 细化 | 结合代码实读评审（cmd/moon.pkg、parse_ext_simple、run_shell_command set/unset 模式） |
