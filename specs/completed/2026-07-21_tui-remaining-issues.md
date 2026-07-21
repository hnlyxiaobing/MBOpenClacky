# TUI 遗留问题与技术债务修复 · 增量 Spec

> **创建日期**: 2026-07-21  
> **状态**: 开发中（已通过对抗性审核）  
> **关联总览**: `docs/tui_remaining_issues.md`（TUI 遗留问题与技术债务清单）  
> **关联历史 spec**: `specs/completed/2026-07-20_tui-integration-restoration.md`（TUI 集成断裂修复，2026-07-21 验收通过，其变更记录明确将本批问题留待后续 spec）  
> **来源差距**: 集成修复验收后的 9 项遗留事项 + Windows 用户实测反馈（控制台乱码）  
> **依赖**: 无外部前置 spec（本 spec 为 TUI 体验的后续治理）  
> **灰度 key**: 无

<!-- 
  v2 规则：标有 [必填] 的章节不可留空，否则 spec 不允许进入 active/。
  "现状分析"已包含"经代码验证"标记，列出实际执行的 grep/glob 命令和结果。
  本 spec 先放 specs/draft/，通过对抗性审核后移入 specs/active/。
-->

## 问题描述 [必填]

`2026-07-20_tui-integration-restoration.md` 已验收通过（22/22 eval 场景 PASS、271 单元测试通过），但验收建立在"单元测试 + eval 模拟器"之上。`docs/tui_remaining_issues.md` 系统梳理了验收后暴露的 9 项遗留问题，按优先级排序如下：

| # | 问题 | 严重度 | 预估工作量 |
|---|------|--------|-----------|
| 1 | Windows 控制台界面乱码（box-drawing/Braille/符号显示为怪汉字） | **P0（阻塞 Windows 用户使用）** | 0.5 天 |
| 2 | `OutputBuffer::commit_through` 实现与文档语义相反（"及更早"变成"及之后"） | 高（引发 #3） | 0.5 天 |
| 3 | 消息区写满后无滚动，且 live 截断方向错误（丢弃最新尾部） | 高（长会话必然触发） | 1-2 天 |
| 4 | 流式管线双端断裂：`StreamChunk` 在 agent 生产路径从不 emit | 高（"流式显示"在真实 LLM 下不生效） | 2-3 天 |
| 5 | `TuiEvent.HookEvent` 变体是死代码（事件队列未落地） | 中（架构债务，非正确性问题） | 2 天 |
| 6 | Windows 上 HTTP 同步阻塞冻结整个 UI | 中（Windows 特有体验问题） | 1-2 天 |
| 7 | 全量测试 8 个失败（测试代码的 Windows 平台假设） | 低（测试代码问题） | 0.5 天 |
| 8 | `%ERRORLEVEL%` 提前展开导致退出码误判 | 低（被测试假阳性掩盖） | 0.5 天 |
| 9 | 真实 TTY 人工验证未完成（流程项） | 流程项 | 0.5 天 |

**本质**：集成修复把组件接通了，但留下三类债务——(a) Windows 平台适配（#1/#6，FFI 代码页 + HTTP 阻塞）；(b) 渲染算法正确性（#2/#3，commit 语义与滚动，eval 模拟器走 `full_redraw` 路径掩盖了 `redraw_live` 的真实终端行为）；(c) 流式架构未接通（#4/#5，组件各自完成有测试，但 `react.mbt` 的 LLM 调用点从未切换到流式 API）。#7/#8 是测试代码的 Unix 假设，#9 是贯穿始终的人工验证流程项。

---

## 现状分析 [必填 - 含代码验证]

### 验证记录

> 以下验证针对 `docs/tui_remaining_issues.md` 的每一项关键"缺失/已有/死代码"声称，执行实际 grep/glob/file_reader 命令并记录结果。验证环境：工作目录 `/mnt/d/MoonBit/MBOpenClacky`。

#### 问题 1：Windows 控制台代码页未设置

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 全仓库无 `SetConsoleOutputCP`/`chcp 65001` 调用 | `grep "SetConsoleOutputCP\|SetConsoleCP\|chcp\|65001\|CP_UTF8"` 全仓 | `CP_UTF8` 仅出现在 `lib/brand/crypto_native.c:115,120`、`lib/client/http_native.c:129,134`、`lib/client/http_thread.c` 的 `MultiByteToWideChar(CP_UTF8, ...)` 字符串转换中；**无任何 `SetConsoleOutputCP`/`SetConsoleCP`/`chcp` 调用** | 确认：从未设置控制台输出/输入代码页（`CP_UTF8` 命中均为字符串编码转换，非控制台代码页设置） |
| FFI 模板 `lib/utils/sys_native.c` 存在且含 `#ifdef _WIN32` + `windows.h` | `glob "lib/utils/sys_native.c"` + `file_reader` | 存在；L9-13 `#ifdef _WIN32` `#define WIN32_LEAN_AND_MEAN` `#include <windows.h>` `#pragma comment(lib, "kernel32.lib")` | 确认：现成 C 模板可复用 |
| `lib/utils/moon.pkg` 有 `native-stub` 配置 | `file_reader lib/utils/moon.pkg` | `"native-stub": [ "sys_native.c" ]` | 确认 |
| `lib/utils/sys_ext.mbt` 有 `extern "C"` 声明模板 | `grep "extern \"C\"" lib/utils/` | `sys_ext.mbt:10` `extern "C" fn chdir_ffi(path: String) -> Int`、`sys_ext.mbt:16` `getcwd_ffi` | 确认：extern "C" 声明模式可复用 |
| `lib/tui/moon.pkg` 已有 `-lcurl` link 配置（添加 native-stub 时须保留） | `grep "cc-link-flags\|native-stub\|lcurl" lib/tui/moon.pkg` | L24 `link: { "native": { "cc-link-flags": "-lcurl" } }` | 确认：添加 C stub 时必须保留该 link 配置 |
| box-drawing/Braille/spinner 字符存在于 TUI 渲染文件 | `grep "─\|│\|┌\|└\|⠋\|⠙\|⠹" lib/tui/` | `command_suggestions.mbt:202`(`┌───`)、`progress_stack.mbt`(3 命中 spinner)、`node.mbt`(10 命中)、`layout_manager.mbt`(20 命中) 等 | 确认：UTF-8 多字节字符广泛用于界面，GBK 解码必乱码 |

#### 问题 2：`commit_through` 语义与文档相反

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 文档注释声称"commit 指定 id 及更早的 entry" | `file_reader output_buffer.mbt:247-272` | L249-253 注释："Mark an entry and all entries **before** it ... all entries up to and including the one with the given id" | 确认：文档语义 = id 及更早 |
| 实现实际 commit "id 及之后" | 同上，L255-269 | `found` 在 `entry.id == id` 时置 true，**同一迭代内** `if found && !entry.is_committed()` 才 commit -> id 之前的 entry `found=false` 不 commit，id 及之后的 entry 才 commit | 确认：实现与文档语义相反 |
| 唯一调用方 `commit_all` 用 `entry_count()` 当 id | `grep "commit_all\|commit_through" lib/tui/layout_manager.mbt` | L194-195 `commit_all` -> `self.output.commit_through(self.output.entry_count())` | 确认：反语义下 `commit_all` 只 commit 最新一条 entry |
| 无 wbtest 覆盖 `commit_through` | `grep "commit_through" lib/tui/*_wbtest.mbt test/` | 0 命中（生产/测试均无直接测试） | 确认：bug 存活因无测试 |

#### 问题 3：满屏无滚动 + 截断方向错误

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| `redraw_live` 满屏时 `available <= 0 { return }` | `file_reader layout_manager.mbt:83-120` | L91-93 `let available = self.msg_height - committed_lines` `if available <= 0 { return }` | 确认：写满后新输出永不上屏 |
| 溢出时取 `live_lines[0..max_lines]` 保留最旧头部 | 同上 | L104-108 `max_lines = if live_lines.length() > available { available } ...`，写入 `live_lines[0..max_lines]` | 确认：丢弃最新尾部（流式最新内容画不上屏） |
| `commit_oldest_lines` 是无调用点的死代码 | `grep "commit_oldest_lines"` 全仓 | 仅 `output_buffer.mbt:280`（定义）命中；无任何生产/测试调用点 | 确认：死代码 |

#### 问题 4：`StreamChunk` 在 agent 生产路径从不 emit

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| `think_async` 调用非流式 `call_llm_async` | `file_reader react.mbt:285-315` | L289 `async fn Agent::think_async`、L296 `let response = self.call_llm_async()`，仅 emit `BeforeLlmCall`(L295)/`MessageAdded`(L304)/`AfterLlmCall`(L305)，**无 `emit(StreamChunk`** | 确认：agent 路径不 emit StreamChunk |
| `call_llm_async` 是非流式（单次 POST、无 SSE） | `grep "call_llm_async" lib/agent/llm_caller.mbt` | L123 `pub async fn Agent::call_llm_async(self) -> @client.LlmResponse` | 确认：非流式 |
| `emit(StreamChunk` 命中情况 | `grep "emit\(StreamChunk"` 全仓 | `lib/agent/hook_wbtest.mbt:110`（测试）、`web/mb/main/chat_cell.mbt:487`（web 端 `scheduler.add(emit(StreamChunk(chunk)))`） | **修正文档措辞**：并非"只命中测试文件"，web 端 `chat_cell.mbt` 也有 emit；但该 emit 属 web 路径，与 TUI/agent 无关，**agent react.mbt 生产路径确认无 emit** |
| SSE 聚合器基础设施存在 | `glob "lib/client/stream*.mbt"` | `lib/client/stream.mbt` 存在 | 确认：基础设施已存在但未接入生产路径 |

#### 问题 5：`HookEvent` 变体是死代码

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| `HookEvent` 变体定义在 `tui_event.mbt:13` | `grep "HookEvent(" lib/tui/` | `tui_event.mbt`（定义）、`tui_controller.mbt:672`（`HookEvent(_) => self.dirty = true` 匹配） | 确认：定义 + 匹配 |
| 无构造点 | 同上 | 0 处构造 `HookEvent(...)` 的生产代码 | 确认：死变体，hooks 经 Ref 直改 state |

#### 问题 6：Windows HTTP 同步阻塞

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| Windows 上 `http_post_async` 退化为同步 | `file_reader http_async.mbt:70-90` | L77-86 `#cfg(platform="windows")` 分支注释："This blocks the current coroutine until the response arrives"，调用 `http_post`（同步） | 确认：Windows 阻塞 |
| Unix 侧卸载线程机制存在（可移植参考） | `file_reader http_thread.c:1-15` | 文件头注释："Spawns an OS thread to perform synchronous HTTP without blocking MoonBit's single-threaded async event loop ... writes the result to a pipe" | 确认：Unix 卸载模式存在，Windows 侧缺失 |

#### 问题 7：8 个测试失败的 Windows 平台假设

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| `shell_exec_wbtest.mbt` 用 sh 语法 `$VAR` | `file_reader shell_exec_wbtest.mbt:14-30` | L17 `run_shell_command("echo VAL=$CLACKY_TEST_SHELLVAR", ...)` | 确认：sh 语法，cmd.exe 不展开 |
| `shell_exec_wbtest.mbt` 假定 `/tmp` | `grep "/tmp\|pwd" lib/tool/shell_exec_wbtest.mbt` | L47 `working_dir=Some("/tmp")`、L49 断言 `== "/tmp"` | 确认：Unix 路径假设 |
| `channel_wbtest.mbt` 硬编码 `/tmp/...` | `file_reader channel_wbtest.mbt:198-250` | L202 `let path = "/tmp/mbopenclacky_test_channels_load.json"`、L246 `/tmp/mbopenclacky_test_channels_invalid.json` | 确认：硬编码 /tmp |

#### 问题 8：`%ERRORLEVEL%` 提前展开

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| `shell_exec.mbt:143` 用 `%ERRORLEVEL%` 捕获退出码 | `file_reader shell_exec.mbt:125-148` | L143 区域 `"..._%ERRORLEVEL%__ >> ..."` | 确认：cmd.exe 解析时即展开，早于命令执行 |

### 详细分析

**渲染管线现状（已验证）**：

```
think_async (react.mbt:289)
  └─ call_llm_async()              [非流式，单次 POST 整包解析]
  └─ emit(BeforeLlmCall / MessageAdded / AfterLlmCall)
  ✗ 从不 emit(StreamChunk)

agent_hooks (AfterLlmCall)
  └─ s.messages.push("[assistant] {streaming_buffer}")
  └─ s.streaming_buffer = ""        [streaming_buffer 永远为空，因无 StreamChunk]

tui_controller (AgentDone)
  └─ agent_output_sync 同步 messages -> OutputBuffer
  └─ commit_all() -> commit_through(entry_count())
      └─ [问题2] 反语义：只 commit 最新一条 entry，旧 entry 永久 live
  └─ redraw_live()
      └─ [问题3] available<=0 -> return（满屏死路）
      └─ [问题3] 溢出取 live_lines[0..max]（丢弃最新尾部）
```

**断裂点总结**：
1. **Windows 解码**（#1）：UTF-8 字节经 `WriteFile` 写入，控制台按 GBK(936) 解码 -> box-drawing `─`(E2 94 80) 解码为 `鈥€` 系怪字。
2. **commit 语义**（#2）：`commit_through` 反语义 -> `commit_all` 只 commit 最新一条 -> committed_lines 定位模型错位。
3. **滚动**（#3）：满屏 `return` + 截断方向错误 + `commit_oldest_lines` 死代码。依赖 #2 先修。
4. **流式 emit**（#4）：`think_async` 不 emit `StreamChunk` -> `streaming_buffer` 永远为空 -> 真实 LLM 下"流式显示"不生效（只在 hook 人工触发的测试路径成立）。
5. **事件队列**（#5）：`HookEvent` 死变体，hooks 经 Ref 直改 state，靠 200ms Tick 轮询刷新。单线程下无竞态，是架构债务非正确性问题。
6. **Windows HTTP**（#6）：`http_post_async` Windows 分支同步阻塞 -> 请求期间 Tick 不发射、UI 冻结。是 #4 在 Windows 的前置条件。
7. **测试**（#7/#8）：测试代码 Unix 假设 + `%ERRORLEVEL%` 提前展开误判。

---

## 决策 [必填 - 含为什么]

1. **单一 spec 涵盖 9 项问题，按任务包分层推进**：而非拆成 6 个独立 spec。理由：问题间存在严格依赖链（#3 依赖 #2；#4 依赖 #6 在 Windows；#5 依赖 #4 才有实际收益），拆分会产生大量跨 spec 依赖，难以追踪。这与源头 spec `tui-integration-restoration` 的做法一致（10 项问题 7 任务包一个 spec）。本 spec 内任务包按依赖顺序推进。

2. **问题 1 采用方案 A（FFI 设置控制台代码页）而非方案 B/C**：启动时 `GetConsoleOutputCP` 保存原值 -> `SetConsoleOutputCP(65001)` + `SetConsoleCP(65001)`，退出时 RAII 恢复。理由：侵入最小（约 30 行 C + 几行 MoonBit），直接修复根因；方案 B（降级提示）体验差且仍需 FFI，方案 C（纯文档）只能作配套。现成模板可直接复用（`sys_native.c` 的 `#ifdef _WIN32` + `sys_ext.mbt` 的 `extern "C"` + `moon.pkg` 的 `native-stub`）。`SetConsoleCP(65001)` 同时修复输入侧（中文输入在 GBK 输入代码页下以 GBK 字节到达）。

3. **问题 2 与问题 3 合并修复，且 #2 必须先于 #3**：理由：`committed_lines` 定位前缀模型在 #2 反语义下已错位，再引入行级部分提交（#3）会让 `start_row` 计算彻底失效。先补 `commit_through` 语义单元测试（"id 及更早"期望），再翻转实现（`found` 置位**前** commit，匹配后 break），最后修 `commit_all` 取真实 last id（消除 count==id 隐式耦合，trim 后两者脱钩）。

4. **问题 3 采用保守方案（翻页式重画）先落地**：`available <= 0` 或溢出时调用 `commit_oldest_lines(溢出量)` 然后用 `render_output_area` 整体重画消息区。理由：激进方案（DECSTBM scroll region）需给 `ScreenBuffer` 增加新 API，且 conhost/mintty/Windows Terminal 行为不一、输入区固定底部整屏 `\n` 会顶上去，风险大。保守方案虽违反"committed 行绝不重绘"性能不变量，但视觉等价、风险小。语义陷阱：滚动量计算必须排除正在流式更新的最新 live entry（`replace` 拒绝 `committed_line_offset > 0`）。

5. **问题 7 + 问题 8 顺手清掉，让全量测试变绿**：测试内做平台分支（复用 `OS=Windows_NT` 检测或把 `shell_is_windows` 提升为 pub），Windows 分支用 `%VAR%`/`cd`/`&`/`%TEMP%`；`%ERRORLEVEL%` 改用 `cmd.exe /v:on /c` + `!ERRORLEVEL!`。理由：纯测试改动，难度低，不涉及 Unix 行为变更，风险很低。注意不让平台分支退化为"Windows 下跳过断言"。

6. **问题 6 -> 问题 4 顺序修复（Windows 流式体验关键路径）**：理由：#6 是 #4 在 Windows 的前置条件——HTTP 同步阻塞下，下一个 chunk 到达前 Tick 不发射、UI 不刷新，流式在 Windows 零收益。先把 Windows HTTP 卸载到 OS 线程（复用/移植 `http_thread.c` 的 pipe 通知模式），再接通流式管线。

7. **问题 4 流式管线接通方案**：在 `lib/client` 启用流式请求路径（SSE，复用 `stream.mbt` 聚合器），`call_llm_async` 增加流式变体；`react.mbt` 的 `think_async` 改调流式变体，每个 chunk 到达时 `hook_manager.emit(StreamChunk(chunk))`；聚合完成后逻辑不变（`AfterLlmCall` 收尾，`agent_output_sync` 的 live entry 原位替换机制处理定稿）。理由：消费端（TUI 侧）完好，只缺 emit 端；SSE 基础设施已存在未接入。

8. **问题 5 降级为最小处理，或在 #4 落地后顺势做**：理由：#5 在单线程协作式 async 下无竞态（`HookManager::emit` 同步 for 循环、`dispatch_hook_event` 全程无 await），是架构债务非正确性问题。若目标是"逐 token 实时渲染"，光做队列桥接无意义，必须先接通 #4 的 StreamChunk emit 端。最小处理方案：删除死变体 + 修正 `tui_event.mbt` 文件头注释（去掉"所有事件推入单一队列"的虚假声称），收益是架构一致性；完整方案（hook 注册闭包改为 `events.put(HookEvent(event))`、`dispatch_hook_event` 搬入 `main_loop`）留作 #4 后的可选项。

9. **问题 9 贯穿始终**：每一步涉及渲染管线的改动都应做真实 TTY 验证，因为 eval 模拟器走 `VirtualScreen` + `full_redraw` 路径，掩盖了 `redraw_live` 的真实终端行为（#2/#3 的定位错位、截断方向问题 eval 都测不到）。

<!-- MoonBit 约束检查：
- AOT 约束：本 spec 不涉及运行时动态加载 trait，所有改动为静态编译。#5 的 HookEvent 队列化如涉及 async `Queue.put`，需确认 aqueue 有同步 `try_put`（否则要把 HookManager 改 async，波及 web/SSE 侧注册点）——此项在 #5 实施时再核实，本 spec 决策为"降级最小处理"，暂不触发该约束。
- crescent 路由：本 spec 不涉及 web 路由。
- FFI：#1 涉及 C 库（windows.h 的 SetConsoleOutputCP），需在 `lib/tui` 新增 native-stub C 文件并在 `moon.pkg` 配置 `native-stub`，且必须保留现有 `-lcurl` link 配置；#6 涉及 C 线程（移植 http_thread.c 模式）。
- mooncakes 依赖：#1/#6 复用现有 windows.h / libcurl / WinHTTP，无新依赖。
-->

---

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/console_cp_native.c`（新建） | 新建 | #1：C stub，`#ifdef _WIN32` 下封装 `set_console_utf8()`/`restore_console_cp()`（`SetConsoleOutputCP`+`SetConsoleCP`），POSIX 下空实现 |
| `lib/tui/moon.pkg` | 修改 | #1：增加 `"native-stub": [ "console_cp_native.c" ]`，**保留**现有 `link: { "native": { "cc-link-flags": "-lcurl" } }` |
| `lib/tui/console_cp_ext.mbt`（新建） | 新建 | #1：`extern "C"` 声明 `set_console_utf8`/`restore_console_cp` |
| `lib/tui/tui.mbt` 或 `cmd/main.mbt` | 修改 | #1：`run_tui_interactive` 入口处 RAII 调用 set/restore（与 `with_raw_mode` 同作用域） |
| `lib/tui/output_buffer.mbt` | 修改 | #2：翻转 `commit_through` 实现（found 置位前 commit，匹配后 break）；新增 `last_entry_id()` 或修正 `commit_all` 取真实 id；#3：激活 `commit_oldest_lines` 调用 |
| `lib/tui/output_buffer_wbtest.mbt`（新建或补充） | 新建 | #2：补 `commit_through` 语义单元测试（"id 及更早"期望） |
| `lib/tui/layout_manager.mbt` | 修改 | #2：`commit_all` 改取真实 last id；#3：`redraw_live` 满屏/溢出时调 `commit_oldest_lines` + `render_output_area` 重画（排除最新 live entry） |
| `lib/agent/llm_caller.mbt` | 修改 | #4：`call_llm_async` 增加流式变体（SSE，复用 `stream.mbt` 聚合器） |
| `lib/agent/react.mbt` | 修改 | #4：`think_async` 改调流式变体，每个 chunk `hook_manager.emit(StreamChunk(chunk))` |
| `lib/client/http_async.mbt` | 修改 | #6：Windows 分支改为卸载到 OS 线程（pipe 通知），替换同步 `http_post` |
| `lib/client/http_thread.c`（或新建 Windows 变体） | 修改/新建 | #6：移植 pipe 通知模式到 Windows（WinHTTP 同步请求 + pipe 写回） |
| `lib/tool/shell_exec.mbt` | 修改 | #8：`%ERRORLEVEL%` 改 `cmd.exe /v:on /c` + `!ERRORLEVEL!` |
| `lib/tool/shell_exec_wbtest.mbt` | 修改 | #7：平台分支，Windows 用 `%VAR%`/`cd`/`&`/`%TEMP%` |
| `cmd/cmd_stub_activation_wbtest.mbt` | 修改 | #7：平台分支 |
| `lib/channel/channel_wbtest.mbt` | 修改 | #7：临时目录从 `TEMP`/`TMPDIR` 取 |
| `lib/tui/tui_event.mbt` | 修改 | #5（最小处理）：修正文件头注释，去掉"所有事件推入单一队列"虚假声称；（完整方案）保留 HookEvent 变体待 #4 后接入 |
| `lib/tui/tui_controller.mbt` | 修改 | #5（完整方案）：`HookEvent(ev)` 分支接入 `dispatch_hook_event`（#4 落地后） |

### 不涉及文件

- `lib/tui/agent_hooks.mbt`（hooks 消费侧完好，#4 只补 emit 端，不改 hooks 逻辑；#5 完整方案才改注册闭包）
- `lib/tui/markdown.mbt`/`command_suggestions.mbt`/`banner.mbt`/`theme.mbt`/`progress_stack.mbt`/`input_area.mbt`（组件已完整，集成在源头 spec 已完成）
- `lib/tui/screen_buffer.mbt`（#3 保守方案不改 ScreenBuffer API；激进方案的 scroll region 封装不在本 spec 范围）
- `web/`（web 端 `chat_cell.mbt` 已有 `emit(StreamChunk)`，本 spec 只治理 TUI/agent 路径）

---

## 实施计划 [必填]

> 按依赖顺序分任务包。建议处理顺序：#1 -> #2+#3 -> #7+#8 -> #6 -> #4 -> #5 -> #9 贯穿。

### 任务包 1：#1 Windows 控制台 UTF-8 代码页（预估 0.5 天）

**目标**：消除 Windows 控制台乱码，box-drawing/Braille/符号正常显示。

1. 新建 `lib/tui/console_cp_native.c`：`#ifdef _WIN32` 下实现 `mbopenclacky_set_console_utf8() -> Int`（保存原 CP、`SetConsoleOutputCP(65001)`+`SetConsoleCP(65001)`、返回原 CP 供恢复）与 `mbopenclacky_restore_console_cp(Int) -> Unit`；POSIX 下空实现返回 0。
2. 新建 `lib/tui/console_cp_ext.mbt`：`extern "C" fn set_console_utf8() -> Int` / `restore_console_cp(Int) -> Unit` 声明。
3. 修改 `lib/tui/moon.pkg`：增加 `"native-stub": [ "console_cp_native.c" ]`，保留 `-lcurl`。
4. 在 `run_tui_interactive` 入口（`with_raw_mode` 同作用域）调用 set，异常/正常退出路径 restore（RAII）。
5. 验证：Windows Terminal 运行 `cmd.exe`，边框/spinner/符号正常；对照乱码形态速查表确认无第二形态问题。

### 任务包 2：#2 commit_through 语义翻转 + #3 滚动修复（预估 1.5-2.5 天）

**目标**：长会话输出不错位、不重复、不冻结；流式最新内容永远可见。

1. **先补测试**：新建 `commit_through` 语义单测——给定 id，断言"id 及更早"的 entry 变 committed、id 之后不受影响。
2. **翻转实现**：`commit_through` 改为匹配到 id 时 commit 当前及之前所有 entry，匹配后 break（或 found 置位前 commit）。
3. **修正 commit_all**：新增 `OutputBuffer::last_entry_id()` 或内部实现，`commit_all` 取真实最后 entry id，消除 count==id 耦合（防 trim 后失效）。
4. **滚动修复**：`redraw_live` 中 `available <= 0` 或溢出时，计算溢出量（排除最新 live entry），调 `commit_oldest_lines(溢出量)`，再用 `render_output_area` 整体重画消息区。
5. 验证：`moon test lib/tui`；真实 TTY 长会话（输出超一屏）确认新旧内容不错位、不重复、流式最新可见。

### 任务包 3：#7 测试平台分支 + #8 ERRORLEVEL（预估 0.5 天）

**目标**：全量 `moon test` 在 Windows 变绿。

1. `shell_exec_wbtest.mbt` 5 个：平台分支，Windows 用 `%VAR%`/`cd /d`/`&`/`%TEMP%`（复用 `shell_is_windows` 检测，必要时提升为 pub）。
2. `cmd_stub_activation_wbtest.mbt` 1 个：同上。
3. `channel_wbtest.mbt` 2 个：临时目录从 `TEMP`/`TMPDIR` 取（参考 `shell_exec.mbt` 的 `shell_temp_dir` 模式）。
4. `shell_exec.mbt:143`：`%ERRORLEVEL%` 改 `cmd.exe /v:on /c` + `!ERRORLEVEL!`；验证 `/v:on` 下 `build_env_prefix` 的 `set "VAR=val"` 仍正确传入子命令。
5. 补"非 exit 方式失败"回归测试（如未识别命令 ERRORLEVEL=9009 应报失败）。
6. 验证：`moon test` 全量 0 失败；Unix 行为不变。

### 任务包 4：#6 Windows HTTP 卸载到 OS 线程（预估 1-2 天）

**目标**：Windows 上 LLM 请求期间 UI 不冻结，为 #4 流式铺路。

1. 移植 `http_thread.c` 的 pipe 通知模式到 Windows：线程做同步 WinHTTP 请求，完成时写 pipe，事件循环读 pipe 唤醒。
2. `http_async.mbt` 的 `#cfg(platform="windows")` 分支改为走卸载线程路径（替换同步 `http_post`）。
3. 照搬现有 `http_thread.c` 的成熟交互约定（pipe 句柄、内存所有权）。
4. 验证：Windows 上发送消息，请求期间 spinner 转、Ctrl-C 可取消、输入可响应。

### 任务包 5：#4 流式管线接通（预估 2-3 天）

**目标**：真实 LLM 调用下 TUI 流式显示生效。

1. `lib/client` 启用流式请求路径（SSE），复用 `stream.mbt` 聚合器；`call_llm_async` 增加流式变体（逐 chunk 回调）。
2. `react.mbt` 的 `think_async` 改调流式变体，每个 chunk 到达 `hook_manager.emit(StreamChunk(chunk))`。
3. 聚合完成后逻辑不变（`AfterLlmCall` 收尾，`agent_output_sync` live entry 原位替换为最终 Markdown）。
4. 处理 SSE 分块边界、keep-alive 注释行、各 provider 流式格式差异（核实 `stream.mbt` 覆盖范围）。
5. 错误处理：流式中途断连的 partial buffer 收尾（`ErrorOccurred`/`RunCompleted` 清 buffer，验证语义一致）。
6. 验证：Windows（需 #4 先完成）+ Unix 真实 LLM 调用，确认逐 token 流式显示。

### 任务包 6：#5 HookEvent 事件化（最小处理或完整方案，预估 0.5-2 天）

**目标**：消除死变体，达成架构一致性。

- **最小处理（推荐先落地）**：删除/标注 `HookEvent` 死变体，修正 `tui_event.mbt` 文件头注释（去掉"所有事件推入单一队列"虚假声称）。收益：架构一致性，0.5 天。
- **完整方案（#4 落地后可选）**：hook 注册闭包改为 `fn(event) { events.put(HookEvent(event)) }`，`dispatch_hook_event` 搬入 `main_loop` 的 `HookEvent(ev)` 分支，`agent_output_sync` 的 buffer-diff 轮询改直接 append（保留 `sync_messages` 的 Markdown 渲染 + live entry 去重；Tick 保留承担 spinner 动画）。需确认 aqueue 同步 `try_put`，否则要把 HookManager 改 async（波及 web/SSE 侧）。2 天。

### 任务包 7：#9 真实 TTY 人工验证（贯穿，预估 0.5 天/轮）

每步渲染管线改动后人工验证：
- 发送消息后 `[assistant]` 回复显示、Markdown 着色正确；
- 长会话（超一屏）新旧内容不错位、不重复（重点暴露 #2/#3）；
- spinner 动画、命令补全下拉框、历史回溯、Banner、`/theme` 切换观感；
- Ctrl-C 取消、终端 resize 行为；
- Windows 上 #1 修复后对照乱码形态速查表确认无残留。

---

## 验收标准 [必填]

### P0 阻塞项

- [ ] Windows Terminal 运行 `cmd.exe`，界面 box-drawing/Braille/spinner 正常显示，无怪汉字（#1，对照乱码形态速查表）
- [ ] `moon check` 0 errors（lib/tui + lib/client + lib/agent + lib/tool）

### 高优先级（渲染正确性 + 流式）

- [ ] `commit_through` 语义与文档一致（"id 及更早"），新增单测覆盖（#2）
- [ ] 长会话输出超一屏后新旧内容不错位、不重复、流式最新内容可见（#3，真实 TTY 验证）
- [ ] 真实 LLM 调用下 TUI 逐 token 流式显示（#4，Windows 需 #6 先完成）
- [ ] Windows 上 LLM 请求期间 spinner 转、Ctrl-C 可取消、UI 不冻结（#6）

### 低优先级（测试 + 架构）

- [ ] `moon test` 全量 0 失败（#7，Windows + Unix 均绿）
- [ ] 非 exit 方式失败的命令正确报失败（#8 回归测试）
- [ ] `HookEvent` 死变体已处理（删除或接入），`tui_event.mbt` 注释修正（#5）
- [ ] `moon test lib/tui` 通过（含新增 commit_through/滚动测试）
- [ ] `moon test lib/tool` + `lib/channel` 通过（#7）
- [ ] `moon fmt` + `moon info` 无异常

### 流程项

- [ ] 真实 TTY 人工验证清单逐项确认（#9，每轮渲染管线改动后）

---

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| #1 代码页是控制台会话级共享状态，异常退出可能不恢复原值 | 中 | 在 `with_raw_mode` 同一作用域做 RAII 恢复；实际影响有限（cmd 进程退出后 console 销毁） |
| #1 修好解码后暴露第二形态问题（ANSI 原样/空心方块/东亚模糊宽度） | 中 | 对照乱码形态速查表区分，分别对策（关旧版控制台/换字体/切 Windows Terminal） |
| #2 翻转后旧 entry 变 committed 激活 `trim_if_needed` 和 `replace`/`remove` 不可变约束 | 中 | 已 grep 确认生产代码无 `output.remove` 调用，风险低；翻转后回归测试 |
| #3 滚动量计算误伤正在流式的 live entry | 高 | `replace` 拒绝 `committed_line_offset > 0`，滚动量计算必须排除最新 live entry |
| #3 保守方案违反"committed 行绝不重绘"性能不变量 | 低 | 视觉等价、风险小；激进 scroll region 方案留作后续优化 |
| #4 SSE 各 provider 流式格式差异、分块边界解析不全 | 中 | 核实 `stream.mbt` 聚合器覆盖范围，补 provider 格式测试 |
| #4 流式中途断连 partial buffer 收尾语义不一致 | 中 | 验证 `ErrorOccurred`/`RunCompleted` 清 buffer 路径 |
| #5 完整方案需 HookManager 改 async，波及 web/SSE 注册点 | 高 | 先做最小处理（删死变体+改注释）；完整方案在 #4 落地后评估，确认 aqueue 同步 try_put |
| #6 WinHTTP 与 libcurl 请求/响应模型差异，C 线程交互约定移植 | 高 | 照搬现有 `http_thread.c` 成熟模式；Windows 真实网络验证 |
| #6 是 #4 在 Windows 的前置条件，顺序颠倒则 Windows 流式零收益 | 高 | 严格按 #6 -> #4 顺序 |
| #7 平台分支退化为"Windows 下跳过断言" | 中 | 用等价的 Windows 语法断言，不跳过 |
| #8 `/v:on` 影响 `build_env_prefix` 的 `set "VAR=val"` 时序 | 低 | 验证延迟展开下环境变量仍正确传入子命令 |
| #2/#3/#4 真实 TTY 行为 eval 测不到 | 高 | #9 贯穿人工验证，不依赖 eval 模拟器 |

---

## 依赖关系 [必填]

- **前置依赖**：无外部前置 spec（本 spec 为 `tui-integration-restoration` 验收后的后续治理）
- **内部依赖（严格顺序）**：
  - #2 必须先于 #3（committed_lines 定位模型在 #2 反语义下错位，先修语义再修滚动）
  - #6 必须先于 #4（Windows HTTP 阻塞下流式零收益）
  - #5 完整方案依赖 #4（StreamChunk 事件化才有实际收益）；最小处理方案无依赖可先行
- **可并行**：
  - #1（乱码）独立，最先做
  - #7+#8（测试）独立，可与 #1/#2/#3 并行
- **后置依赖**：
  - 真实 TTY 运行验证（#9）依赖每轮渲染管线改动完成
  - 激进 scroll region 方案（DECSTBM）作为 #3 保守方案的后续优化，不在本 spec 范围

---

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-21 | 初始版本：基于 `docs/tui_remaining_issues.md` 创建，9 项问题全部经 grep/glob/file_reader 代码验证（验证记录见表）。修正文档问题 4 一处不精确措辞：`emit(StreamChunk)` 并非"只命中测试文件"，web 端 `chat_cell.mbt:487` 也有 emit，但属 web 路径，agent `react.mbt` 生产路径确认无 emit。按依赖顺序切分 7 个任务包。 | `tui-integration-restoration` 验收后遗留 9 项问题需系统性治理，遵循 Harness v2 先验证后成 spec 流程 |
| 2026-07-21 | 审核修正：对抗性审核 8 项检查全部通过：(1) 5 项"missing"声称全部经 grep 确认（无 SetConsoleOutputCP、commit_oldest_lines 死代码、react.mbt 不 emit StreamChunk、HookEvent 无构造点、Windows HTTP 同步阻塞）；(2) 全部 17 个已存在文件路径经 glob 确认；(3) 全部 12 个函数名经 grep 确认（render_output_area/replace/is_fully_editable 等，replace 的 committed_line_offset==0 guard 通过 is_fully_editable() 间接实现，spec 描述准确）；(4) MoonBit AOT 约束已标注延后核实；(5) crescent 不涉及；(6) 无过度工程，决策理由充分；(7) 10 个 [必填] 标记齐全；(8) 5 个交叉引用文件全部确认存在。无事实性错误，审核通过。 | 对抗性审核 + 第一性原理校验 |
| 2026-07-21 | 开发完成（任务包 1-6 全部落地）：#1 新增 `lib/tui/console_cp_native.c`/`console_cp_ext.mbt`，`run_tui_interactive` RAII 设置/恢复控制台 UTF-8 代码页；#2 `commit_through` 语义翻转为"id 及更早"（先定位再提交，未知 id 不提交任何 entry），新增 `last_entry_id()`，`commit_all`/eval 适配器 4 处调用点全部改取真实 id，新增 6 个语义单测；#3 `redraw_live` 溢出时 `commit_oldest_lines`（排除最新 live entry）+ `render_output_area` 整体重画，live 截断方向改为保留最新尾部；#7 测试平台分支 10 处（shell_exec 5 + cmd_stub 3 + channel 2，Windows 用 `!VAR!` 延迟扩展/`&` 分隔符/TEMP 目录，断言等价不跳过）；#8 `%ERRORLEVEL%` 改 `cmd.exe /v:on /c` + `!ERRORLEVEL!` 并补 9009 回归测试；#6 Windows HTTP 经槽位+轮询卸载到 OS 线程（**偏离 spec 的 pipe 通知方案**：runtime 管道句柄已注册 IOCP，C 线程 overlapped 写会向事件循环投递无法解释的完成包，有崩溃风险；槽位方案复用 `perform_http` 零事件循环风险）；#4 流式管线全通：C 侧 Unix 帧式 pipe 流式线程/Windows 槽位流式 drain，`http_post_stream_async` 双平台，`SseBytePump` 字节级 SSE 重组（跨 chunk/UTF-8 边界安全），OpenAI/Anthropic 聚合器新增 `handle_delta`，`call_llm_stream_async`（Bedrock 无 SSE-over-HTTP 回退非流式），`think_async` 逐 chunk `emit(StreamChunk)`；#5 最小处理：删除 HookEvent 死变体 + 修正 `tui_event.mbt` 文件头注释。验证：`moon check` 0 errors；`moon test` 2831/2831（基线 2811/2821 修 10 个失败）；TUI eval 22/22 PASS；`moon fmt`/`moon info` 无异常。**遗留**：#9 真实 TTY 人工验证（交互式终端无法在本开发会话内执行，需人工按验收清单确认，尤其 #1 乱码修复观感、#3 长会话滚动、#4 真实 LLM 逐 token 流式）。 | 7 个任务包按依赖顺序实施，#6 因 IOCP 完成包安全问题偏离 spec 方案但达成同一目标 |
| 2026-07-21 | **#9 人工验证暴露并修复两个 bug**（用户实测 TUI 发消息报 `[error] hnlyxiaobing/MBOpenClacky/lib/errors.AgentError.AgentError`）：(1) **根因**：`http_thread.c` 两个 WinHTTP 变体（`perform_http`/`perform_http_win_stream`）`WinHttpSendRequest` 的 `dwTotalLength` 传 0 而非 `body_len`，带 body 的请求触发 `ERROR_INVALID_PARAMETER (0x57)` —— 该潜伏 bug 存在于预存代码的 Windows 分支，因 #6 前 Windows 异步路径从不走线程而从未被激活；同步路径（`http_native.c:231`）传参正确故 `--message` 正常。(2) **显示层**：`tui_controller.start_agent` 用 `"\{err}"` 插值 Error，只输出构造器全路径丢失 payload，改用既有的 `@errors.error_message()`。修复链路验证：本地 mock SSE 服务器（`scripts/test_sse_server.py`）端到端验证 sync/slot/stream 三条 Windows 路径全部 200 + 8 SSE 帧完整重组；`moon test` 2831/2831；release 构建确认含修复。同时保留 WinHTTP 失败点的具体错误消息（附错误码），不再被通用消息覆盖。 | 第一性原理定位：`--message`（同步）正常 vs TUI（异步流式）失败的差分实验 → 本地 mock 复现 → WinHTTP 参数比对 |
