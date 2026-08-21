# MCP stdio transport 实装（子进程 spawn + 请求响应关联）· 增量 Spec

> **创建日期**: 2026-08-21
> **状态**: 讨论中
> **关联总览**: `specs/draft/2026-08-21_stubfix-00-overview.md`（来源：stub 实装状态审计报告 2.3 节 + 第五节建议 3）
> **关联历史 spec**: 无
> **来源差距**: 审计报告 2.3「MCP stdio transport 未实装：start/stop/send_message 全 placeholder，send_request 必抛错」
> **依赖**: 无
> **灰度 key**: 无

## 问题描述 [必填]

MCP 客户端的核心通信层全部是空壳，导致 Web UI 配置的任何 MCP 服务器都无法真正连通：

1. **StdioTransport::start**：只设 `is_alive = true`，不 spawn 子进程（stdio_transport.mbt:56-60，TODO 注释明说 "FFI implementation needed"）。
2. **StdioTransport::send_message**：`ignore(message)` 直接丢弃（:79-89）。
3. **McpClient::send_request**：发送后必然 raise `"Response handling requires async runtime"`（client.mbt:119-145）--没有请求-响应关联机制。
4. **配套缺陷**：`McpRegistry::cleanup_idle` 的时间比较是 TODO，`last_used_at`/`started_at` 恒 0（registry.mbt:216-234、client.mbt:60）。
5. **HttpTransport 同为 stub**（send_message ignore，http_transport.mbt:70-77）。

影响面：Web 端 `/api/mcp` 的 tools/list、tools/call 端点真实存在并调用 `registry.call_tool`（handlers_mcp.mbt:412、492），但链路终结于必然抛错的 send_request。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "stdio start 只设标志" | `grep -n "FFI implementation needed\|is_alive = true" lib/mcp/stdio_transport.mbt` | :58 TODO 注释 + :62 `self.is_alive = true` | 确认 |
| "send_message 丢弃" | 同上 | :88、:91 `ignore(message)` | 确认 |
| "send_request 必抛错" | `grep -n "async runtime" lib/mcp/client.mbt` | :137 `"Response handling requires async runtime (method: ...)"` | 确认 |
| "scheduler 式时间戳恒 0 同源" | `grep -n "TODO" lib/mcp/registry.mbt lib/mcp/client.mbt` | registry cleanup_idle 时间比较 TODO（审计 :216-234）、client started_at 恒 0（审计 :60） | 确认（时间戳能力与 stubfix-05 共用解法，见决策 5） |
| "spawn 子进程先例存在可复用" | `grep -n "spawn_orphan\|@process" lib/server/browser_process.mbt` | :39-42 `@process.read_from_process()`/`write_to_process()` 管道 + spawn_orphan 模式完整可用（审计 3.5 澄清此为真实现） | 确认复用路径，无需新 FFI |
| "JSON-RPC 编解码已就绪" | 审计 2.3 节"已实装（外围）" | mcp.json 解析、JSON-RPC 编解码、注册表管理均为真实现 | 确认只差通信层 |

### 详细分析

**browser_process.mbt 模式**（复用模板）：`@process.read_from_process()` 创建 stdout 读管道 -> `@process.write_to_process()` 创建 stdin 写管道 -> `spawn_orphan` 启动子进程并绑定管道 -> JSON-RPC 读写循环。chrome-devtools-mcp 子进程即由该模式管理（browser_manager.mbt 的 start 为真实现：spawn + JSON-RPC + MCP 握手）。

**请求-响应关联缺口**：MCP stdio 协议是 JSON-RPC over stdin/stdout，响应按 `id` 字段匹配请求。当前 `send_request` 无等待机制。MoonBit async 提供的 `TaskGroup::spawn`/channel 原语（.mooncakes async mbti 已验证）可实现：每请求创建 pending 表项（id -> promise/channel），读循环收到响应时按 id 唤醒。

**stderr 处理**：MCP 规范要求忽略/日志化 stderr（防止服务器把日志写进协议流）。browser_process 模式需确认 stderr 管道处置（实施时参照）。

## 决策 [必填 - 含为什么]

1. **决策 1（复用 spawn 模式）**：StdioTransport::start 用 `@process` 管道 + spawn_orphan 实现（对齐 browser_process.mbt），不自建 FFI。
   - **为什么**：项目内已有成熟先例（审计建议 3 明示"可复用其模式"）；避免新增 native-stub；spawn_orphan 使子进程生命周期独立于父进程崩溃。
2. **决策 2（请求-响应关联）**：send_request 改 async：自增 request id -> pending map 注册 -> 写 stdin -> 读循环任务按 id 匹配唤醒 -> 超时（默认 30s 可配）返回 Err。读循环由 TaskGroup::spawn_bg 常驻。
   - **为什么**：MCP JSON-RPC 的 id 匹配是协议要求；async 等待与 agent 工具链运行时一致（llm_caller 已用 @async.sleep）；超时防服务器挂死阻塞 agent。
3. **决策 3（初始化握手）**：start 时自动完成 MCP initialize 握手（initialize 请求 -> initialized 通知），失败则 stop 并返回启动错误。
   - **为什么**：MCP 协议要求握手后才能 tools/list、tools/call；提前失败优于半连接状态。
4. **决策 4（HTTP transport 范围控制）**：本 spec 只修 stdio；HttpTransport 维持诚实报错（当前 ignore 改为 Err("not implemented")，与 stubfix-02 同原则）。
   - **为什么**：stdio 是主流（npx/uvx 本地服务器）；HTTP transport 实装依赖独立网络栈决策（复用 @client FFI 可行但验证面大），混入将扩大审查面。
5. **决策 5（时间戳）**：引入真实时间戳能力（`@client` 或 async 时钟，与 stubfix-05 调度器共用同一解法），started_at/last_used_at/cleanup_idle 时间比较补全。
   - **为什么**：审计将 TokenCache/调度器/MCP 三处时间戳列为同源问题；本 spec 只补 MCP 侧消费点，时钟源的具体实现在任务包内验证选定（若需新增共享工具函数则放 lib/utils 并在 spec 回写）。

MoonBit 约束检查：
- AOT 约束：不涉及动态加载 trait。✅
- FFI：@process 为 moonbitlang/async 既有能力（browser_process 在用），无新增 native-stub。✅
- wasm 目标：@process 为 native-only；MCP transport 现状 wbtest 若有 wasm 目标需确认 stub 降级（`moon check` 必须过，遵循项目约定）。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/mcp/stdio_transport.mbt` | 修改 | start：管道创建 + spawn + initialize 握手（决策 1/3）；stop：进程终止 + 管道清理；send_message：写 stdin |
| `lib/mcp/client.mbt` | 修改 | send_request 改 async + id 关联 + 超时（决策 2）；started_at/last_used_at 真实时间戳 |
| `lib/mcp/registry.mbt` | 修改 | cleanup_idle 时间比较实装；call_tool 前置 ensure_started |
| `lib/mcp/http_transport.mbt` | 修改 | ignore -> 诚实 Err（决策 4） |
| `lib/mcp/*_wbtest.mbt` | 修改 | 新增：握手协议单测（mock 子进程用 echo/内置测试服务器）、超时、cleanup_idle |
| `lib/mcp/moon.pkg` | 修改 | import 增加所需 async/process 包 |

### 不涉及文件

- `lib/web/handlers_mcp.mbt` -- 端点已真实调用 registry，transport 修好后自动连通；错误展示增强列 backlog
- `lib/server/browser_process.mbt` -- 只复用模式不改它
- mcp.json 配置解析/虚拟技能生成 -- 已实装，不动

## 实施计划 [必填]

### 任务包 1：spawn + 管道 + 生命周期（预估 0.5 天）

1. StdioTransport::start/stop 按 browser_process 模式实装；stderr 日志化。
2. wbtest：启动/停止真实子进程（用系统 `cat` 或项目内 echo 型测试服务器）；is_alive 状态真实化。
3. `moon check` 0 errors。

### 任务包 2：initialize 握手 + 请求响应关联（预估 1 天）

1. 握手流程（决策 3）；失败清理路径。
2. send_request async 化：pending map + 读循环 + id 匹配 + 超时（决策 2）。
3. wbtest：JSON-RPC id 匹配、乱序响应、超时 Err、并发多请求。
4. `moon test lib/mcp` 通过。

### 任务包 3：registry 与 HTTP 诚实化 + 时间戳（预估 0.5 天）

1. cleanup_idle 时间比较、last_used_at 维护（决策 5）。
2. HttpTransport ignore -> Err。
3. wbtest：空闲清理触发；HTTP transport 报错。

### 任务包 4：端到端验收（预估 0.5 天）

1. `moon run cmd -- server` + Web UI 配置一个本地 stdio MCP 服务器（如 npx 型或 echo 测试服务器），tools/list 与 tools/call 全链路成功。
2. 全量 `moon test` 无回归；`moon fmt`、`moon info`。

## 验收标准 [必填]

- [ ] StdioTransport::start 真实 spawn 子进程并完成 MCP initialize 握手；失败返回明确错误（is_alive 真实反映）
- [ ] tools/list 请求经 send_request 获得真实响应（wbtest + 手动端到端）
- [ ] tools/call 全链路（Web UI -> handlers_mcp -> registry -> stdio -> 子进程 -> 响应）打通
- [ ] 响应按 JSON-RPC id 关联，乱序/并发请求正确匹配；超时返回 Err 而非挂死
- [ ] stop 终止子进程、管道清理无泄漏（重复 start/stop 幂等）
- [ ] cleanup_idle 按真实时间戳工作，last_used_at 不再恒 0
- [ ] HttpTransport 返回诚实 Err（不再 ignore）
- [ ] `moon check` 0 errors（lib/mcp）
- [ ] `moon test lib/mcp` 通过；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 子进程输出缓冲/半行 JSON-RPC 消息（按行分帧） | 中 | 读循环按 `\n` 分帧 + JSON 解析失败仅记日志跳过（不崩连接）；wbtest 构造半行/粘包用例 |
| npx/uvx 型服务器启动慢导致握手超时 | 中 | 握手超时独立配置（默认 60s）并区分"启动慢"与"启动失败"诊断信息 |
| Windows 路径/命令解析差异（cmd /c、.cmd 后缀） | 中 | 复用 browser_process 的 spawn 参数模式（同为 Windows native 环境）；wbtest 在 Windows 环境跑（项目主环境） |
| pending map 泄漏（响应永不到达） | 中 | 超时自动移除表项；stop 时清空全部 pending 并唤醒为 Err |
| async 读循环与 server 生命周期错配（server 关闭后循环残留） | 中 | stop 显式 cancel 读任务；TaskGroup 生命周期绑定 transport |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：MCP HTTP transport 实装（backlog）；Web UI MCP 错误展示增强（backlog）；时间戳共享工具如落地 lib/utils 则 stubfix-05 复用

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-21 | 初始版本 | stub 审计报告 2.3 节 + P1 建议 3 |
