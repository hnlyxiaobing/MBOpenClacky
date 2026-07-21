# TUI 遗留问题与技术债务清单

> **创建日期**: 2026-07-21
> **来源**: `specs/completed/2026-07-20_tui-integration-restoration.md` 验收后的遗留事项 + 用户实测反馈（Windows 乱码）
> **状态**: 全部待处理，按优先级排序
> **快速索引**:
>
> | # | 问题 | 严重度 | 预估工作量 |
> |---|------|--------|-----------|
> | 1 | Windows 控制台界面乱码 | **P0（阻塞 Windows 用户使用）** | 0.5 天 |
> | 2 | `commit_through` 实现与文档语义相反 | 高（引发 #3） | 0.5 天 |
> | 3 | 消息区写满后无滚动（live 截断方向错误） | 高（长会话必然触发） | 1-2 天 |
> | 4 | 流式管线双端断裂（StreamChunk 从不 emit） | 高（"流式显示"在真实 LLM 下不生效） | 2-3 天 |
> | 5 | HookEvent 事件队列变体是死代码 | 中（架构债务，非正确性问题） | 2 天 |
> | 6 | Windows 上 HTTP 同步阻塞冻结 UI | 中（Windows 特有体验问题） | 1-2 天 |
> | 7 | 全量测试 8 个失败（Windows 平台假设） | 低（测试代码问题） | 0.5 天 |
> | 8 | `%ERRORLEVEL%` 提前展开误判退出码 | 低（被测试假阳性掩盖） | 0.5 天 |
> | 9 | 真实 TTY 人工验证未完成 | 流程项 | 0.5 天 |

---

## 问题 1：Windows 控制台界面乱码（用户实测）

### 现象

在 Windows Terminal / PowerShell 中运行 `_build/native/release/build/cmd/cmd.exe`，界面边框显示为 `鈑€鈑€...`、`鈑屝摃` 等怪汉字，英文文案（"Type a message..."）和颜色正常。

### 根本原因

**程序从未调用 `SetConsoleOutputCP(CP_UTF8)`，而中文 Windows 控制台默认输出代码页是 936 (GBK)。**

解码链已逐环验证：

1. MoonBit `String` → UTF-8 字节，经 `@async` 写路径在 Windows 上走 `WriteFile`（`.mooncakes/moonbitlang/async/src/internal/event_loop/io_windows.c:414`），**不是 `WriteConsoleW`**，没有 Unicode 旁路；
2. 控制台如何解码这批字节完全由输出代码页决定。界面 box-drawing 字符 `─` 的 UTF-8 编码是 `E2 94 80`，按 GBK 解码正好得到 `鈥€` 系怪字——与截图指纹完全吻合；
3. 全仓库（含 `.mooncakes` 依赖）grep `SetConsoleOutputCP` / `chcp` / `65001` **零命中**，即没有任何环节设置过代码页。

ANSI 颜色正常是因为 tty 依赖包（`moonbit-community/tty@0.3.0`）的 raw mode 已正确开启 `ENABLE_VIRTUAL_TERMINAL_PROCESSING`（`.mooncakes/moonbit-community/tty/state.c:130-142`）——**转义序列解析和字节解码是两个独立环节**，前者 OK 不代表后者 OK。

界面涉及的 UTF-8 字符位置：box-drawing `─│┌┐└┘`（`lib/tui/node.mbt:111-160`、`lib/tui/layout_manager.mbt:158-185`、`lib/tui/command_suggestions.mbt:202-243`）、Braille spinner `⠋⠙⠹`（`lib/tui/progress_stack.mbt:225-226`）、`✓✗☑☐⚠`（`cmd/main.mbt:787-793`、`lib/tui/markdown.mbt:352-357`）。

### 解决办法（推荐方案 A）

**方案 A（侵入最小，约 30 行 C + 几行 MoonBit）**：启动时 FFI 设置控制台代码页。

- 在 `lib/tui/tui.mbt` 的 `run_tui_interactive` 入口（`cmd/main.mbt:628` 调用处）：`GetConsoleOutputCP` 保存原值 → `SetConsoleOutputCP(65001)` + `SetConsoleCP(65001)`，退出时恢复（RAII，与 `with_raw_mode` 同作用域）。
- `SetConsoleCP(65001)` 同时修复**输入侧**：tty 开了 `ENABLE_VIRTUAL_TERMINAL_INPUT`，但中文输入在 GBK 输入代码页下会以 GBK 字节到达，同样需要切。
- 现成模板可直接复用：`lib/utils/sys_native.c:9-13`（`#ifdef _WIN32` + `windows.h` 写法）+ `lib/utils/moon.pkg` 的 `"native-stub"` 配置 + `lib/utils/sys_ext.mbt:10` 的 `extern "C"` 声明。

**方案 B（降级提示）**：启动时检测 `GetConsoleOutputCP() != 65001` 则提示用户先 `chcp 65001` 或改用 Windows Terminal。体验差，且同样需要 FFI。

**方案 C（纯文档）**：README 注明 Windows 用户需 `chcp 65001`。只能作为 A 的配套。

### 困难点

1. 代码页是控制台会话级共享状态，程序异常退出（raw mode 异常路径）可能不恢复原值——需在 `with_raw_mode` 同一作用域做 RAII 恢复；实际影响有限（cmd 进程退出后 console 销毁）。
2. `lib/tui/moon.pkg` 已有 `link: { "native": { "cc-link-flags": "-lcurl" } }`，添加 native-stub 时必须保留该 link 配置。
3. 修好解码后可能暴露**第二形态**问题（见下表），需用户配合确认。

### 乱码形态速查表（修好后用于区分残留问题）

| 形态 | 特征 | 根因 | 对策 |
|------|------|------|------|
| 怪汉字（鈥€）但颜色正常 | UTF-8 被 GBK 解码 | 缺 `SetConsoleOutputCP(65001)`（**本次截图即此形态**） | 方案 A |
| ANSI 原样显示（`[31m`、`[2J`） | VT 处理未生效 | 旧版控制台 / 重定向 / `SetConsoleMode` 失败 | 关闭"旧版控制台"，勿重定向 |
| 空心方块 □ 但位置正确 | 字体缺字形 | conhost 字体不含 box-drawing/braille（GDI 无 font-fallback） | 换 Consolas/Cascadia 字体或 Windows Terminal |
| 边框错位重影但不是错字 | 东亚模糊宽度 | CP936 下 conhost 把 U+2500 系按 2 格渲染但光标走 1 格 | 切 65001 或 Windows Terminal |

---

## 问题 2：`OutputBuffer::commit_through` 实现与文档语义相反

### 问题

文档注释（`lib/tui/output_buffer.mbt:249-254`）和设计 spec（`specs/completed/2026-07-01_tui-inline-migration.md:355`）都说语义是"commit 指定 id **及更早**的 entry"，但实现（`output_buffer.mbt:255-269`）的 `found` 标志置位后才 commit，实际效果是"commit 指定 id **及之后**的 entry"。

### 根本原因与原理

id 从 1 单调递增、entries 按追加顺序存储。唯一调用方是 `LayoutManager::commit_all`（`lib/tui/layout_manager.mbt:194-196`）：

```moonbit
pub fn LayoutManager::commit_all(self : LayoutManager) -> Unit {
  self.output.commit_through(self.output.entry_count())
}
```

`entry_count()` 在无 entry 被移除时恰好等于最新 entry 的 id，于是反语义下 **`commit_all()` 实际只 commit 最新一条 entry**，之前所有 entry 永久保持 live 状态。这引发两个后果：

1. **每帧重绘浪费**：`redraw_live`（`layout_manager.mbt:83-116`）每帧把所有 live entry 全部行清区重写，"committed 行绝不重绘"的不变量只对最新一条生效；
2. **定位模型错位**：`redraw_live` 用 `start_row = msg_top + committed_lines`，假设 committed 行是行流**前缀**，而实际被 commit 的是行流**尾部**的最新 entry——会清掉屏幕上 committed entry 的物理行并在其位置重写旧 live 行，真实 TTY 下可能造成内容重复/错位（eval 走 `full_redraw` 路径所以没暴露）。

该 bug 能存活的原因：**全仓库没有任何 wbtest 覆盖 `commit_through`**。

### 解决办法

1. 先补语义单元测试（"id 及更早"的期望行为），再翻转实现：`found` 置位**前** commit，匹配到 id 后 break；
2. `commit_all` 改为取最后一个 entry 的真实 id（新增 `last_entry_id()` 或在 OutputBuffer 内部实现），消除"count == id"的隐式耦合（一旦 trim 生效两者脱钩，现有写法会一条都不 commit，更糟）。

### 困难点

- 代码量极小（一行级），难点在验证：翻转后旧 entry 变 committed 会激活 `trim_if_needed`（`output_buffer.mbt:466-475`）和 `replace`/`remove` 的不可变约束（`output_buffer.mbt:181-199`），需确认没有路径依赖"旧 entry 仍可改"（已 grep 确认生产代码无 `output.remove` 调用，风险低）；
- 视觉效果只能在真实 TTY 下确认，eval 模拟器掩盖该问题。

---

## 问题 3：消息区写满后无滚动，且 live 截断方向错误

### 问题

`LayoutManager::redraw_live`（`lib/tui/layout_manager.mbt:83-116`）在消息区写满时直接放弃：

```moonbit
let available = self.msg_height - committed_lines
if available <= 0 { return }   // L91-93：写满后新输出永远不上屏
```

并且未满但溢出时，`max_lines = min(live_lines.length(), available)` 取 `live_lines[0..max_lines]`——`live_lines` 按旧→新排列，所以**保留最旧头部、丢弃最新尾部**。正确行为应相反：正在流式输出的最新内容永远画不上屏，画面"冻结"在旧内容上。

### 根本原因

原始设计（`specs/completed/2026-07-01_tui-inline-migration.md:441-455` 的 paint_new_lines 伪码，对标 Ruby 版）是**利用终端自身滚屏**：每输出一行到固定区边界就在底部输出 `\n` 让终端把顶行推入 scrollback，同时调 `commit_oldest_lines(1)` 让 buffer 状态与物理屏幕同步。`OutputBuffer::commit_oldest_lines`（`output_buffer.mbt:280-303`，支持 entry 内部分提交）就是为"一次滚一行"设计的。

但后续的 Master Plan（`2026-07-15_tui-overhaul-master-plan.md`）改用了"每帧整体重画 live 区"模型，丢掉了增量滚动设计，`commit_oldest_lines` 变成**无任何调用点的死代码**，满屏情形留下 `available <= 0 → return` 的死路。eval 场景 `long_output_scroll` 走 `full_redraw` → `render_output_area`（取尾部 N 行），**绕过了** `redraw_live`，所以测试捕获不到。

### 解决办法

- **保守方案（推荐先落地）**：`available <= 0` 或溢出时，调用 `commit_oldest_lines(溢出量)` 然后用 `render_output_area` 整体重画消息区（"翻页"式）。违反"committed 行绝不重绘"的性能不变量，但视觉等价、风险小；
- **激进方案（对齐原设计）**：给 `ScreenBuffer` 增加 DECSTBM scroll region 支持（目前 API 只有 `move_cursor/clear_to_eol/write_string` 等，`screen_buffer.mbt:59-112`，无 scroll region 封装），按 paint_new_lines 伪码做增量滚动。

### 困难点

1. **必须先修问题 2**：`committed_lines` 定位前缀模型在反语义下已错位，再引入行级部分提交会让 `start_row` 计算彻底失效，两者必须一起修；
2. **语义陷阱**：`replace` 拒绝 `committed_line_offset > 0` 的 entry（静默返回 None）——**正在流式更新的 live entry 绝不能被 `commit_oldest_lines` 波及**，滚动量计算必须排除最新 live entry；
3. **联动失效**：trim 启动后 entry id 与 `entry_count()` 脱钩，`commit_all` 的 `id=count` 技巧立即失效（见问题 2）；
4. 激进方案的终端兼容性：scroll region 在 conhost/mintty/Windows Terminal 行为不一；输入区固定在底部，整屏 `\n` 会把输入栏顶上去，必须用受限 scroll region 或滚后强制重画固定区；
5. 回归验证依赖真实 TTY，eval 覆盖不到。

---

## 问题 4：流式管线双端断裂——`StreamChunk` 在生产代码中从未被 emit

### 问题

这是在调查问题 5 时的**新发现**，比原 spec 记录的 P2-3 更严重：整条流式管线（StreamChunk → streaming_buffer → messages）在真实 LLM 路径上**两端都是断的**。

- 消费端（TUI 侧）完好：`agent_hooks.mbt:241-248` 的 `StreamChunk(chunk)` 分支会累积 `s.streaming_buffer`；`agent_output_sync.mbt` 的 Tick 轮询能把它渲染成"流式效果"；
- 但 **emit 端不存在**：全仓 grep `emit(StreamChunk` 只命中测试文件 `lib/agent/hook_wbtest.mbt:110`。`Agent::think_async`（`lib/agent/react.mbt:289-310`）调用的是非流式的 `call_llm_async`（`lib/agent/llm_caller.mbt:123`——单次 POST、整包解析、无 SSE），只 emit `MessageAdded` + `AfterLlmCall`。

**后果**：生产中 `streaming_buffer` 永远为空，`AfterLlmCall` 里 `if s.streaming_buffer.length() > 0` 的 messages 推送不会触发，用户看到的"回复"实际走的是其他路径（回复内容需从 `MessageAdded`/agent 消息历史进入 TUI）；spec 验收的"流式回复实时显示"只在 hook 被人工触发的测试路径下成立，**真实 LLM 调用下 TUI 只会在 AgentDone 后一次性显示回复**。另外 SSE 流式解析的基础设施其实已存在（`lib/client/stream.mbt` 的聚合器有测试），但没有接入生产路径。

### 根本原因

组件开发与集成分两阶段进行（与本次修复的集成断裂同根因）：hooks 的消费侧、客户端的 SSE 聚合器各自完成并有测试，但 `react.mbt` 的 LLM 调用点从未切换到流式 API。

### 解决办法

1. 在 `lib/client` 增加/启用流式请求路径（SSE，`stream.mbt` 聚合器复用），`call_llm_async` 增加流式变体；
2. `lib/agent/react.mbt` 的 `think_async` 改调流式变体，每个 chunk 到达时 `hook_manager.emit(StreamChunk(chunk))`；
3. 聚合完成后逻辑不变（`AfterLlmCall` 收尾，`agent_output_sync` 的"live entry 原位替换为最终 Markdown 渲染文本"机制正好处理定稿）。

### 困难点

1. **Windows 上做了也没用（见问题 6）**：HTTP 在 Windows 是同步阻塞的，单线程运行时下一个 chunk 到达前 Tick 不会发射、UI 不会刷新——流式渲染在 Windows 必须先解决问题 6 才有意义；
2. SSE 解析要处理分块边界、keep-alive 注释行、各 provider 的流式格式差异（`lib/client/stream.mbt` 聚合器的覆盖范围需核实）；
3. 错误处理路径增加：流式中途断连的 partial buffer 如何收尾（`ErrorOccurred`/`RunCompleted` 分支已清 buffer，需验证语义一致）；
4. 工作量 2-3 天，原 spec 的 P2-3 估算完全没包含这部分。

---

## 问题 5：`TuiEvent.HookEvent` 变体是死代码（事件驱动架构未落地）

### 问题

`HookEvent(@agent.HookEvent)` 变体在 `lib/tui/tui_event.mbt:13` 定义、在 `lib/tui/tui_controller.mbt:672` 被匹配（`HookEvent(_) => self.dirty = true`），但**全仓库无构造点**。hooks 通过闭包捕获 `Ref[TuiState]` 直接修改 state（`agent_hooks.mbt:52-61` 注册、`dispatch_hook_event` L90-297 分发），绕过 `events : @aqueue.Queue[TuiEvent]`（`tui_controller.mbt:41`）队列。文件头注释（`tui_event.mbt:1-6`）声称的"所有事件推入单一队列"与现状不符。控制器靠 200ms Tick 轮询 state（`tui_controller.mbt:648-670` + `agent_output_sync.mbt`）实现刷新。

### 为什么当前不是正确性问题

单线程协作式 async 下无竞态，依据充分：

- agent 由 `start_agent` 经 `group.spawn`（`tui_controller.mbt:1021`）启动，与主循环同属一个 `@async.with_task_group`，协程只在 await 点切换；
- 唯一 OS 线程是 HTTP 卸载线程（`lib/client/http_thread.c:5` 注释明确写明），只写 pipe，不碰 MoonBit 侧 state；
- `HookManager::emit`（`lib/agent/hook.mbt:88-92`）是同步 for 循环，`dispatch_hook_event` 全程无 await，每次 state 修改对主循环是原子的。

### 解决办法（若要做）

1. hook 注册闭包改为 `fn(event) { events.put(HookEvent(event)) }`（队列在 handler 创建前已初始化，`tui_controller.mbt:82`，无顺序问题）；
2. `dispatch_hook_event`（约 200 行）整体搬到 `main_loop` 的 `HookEvent(ev)` 分支；
3. `agent_output_sync` 的 buffer-diff 轮询可被直接 append 取代，但 `sync_messages` 的 Markdown 渲染 + live entry 去重机制需保留，Tick 本身还要承担 spinner 动画不能删。

### 困难点

1. **签名阻抗**：`HookManager.register` 回调是同步 `(HookEvent) -> Unit`，而 `Queue.put` 是 async——需确认 aqueue 有同步 `try_put`，否则要把 `HookManager` 改 async（波及 web/SSE 侧所有注册点）；
2. **与问题 4 强耦合**：如果目标是"逐 token 实时渲染"，光做队列桥接没有意义，必须先接通 StreamChunk emit 端；如果目标只是消灭死变体，2 天足够（但收益也仅仅是架构一致性）；
3. 时序验证：hooks 事件与 AgentDone 从同一 agent 协程 FIFO 入队，顺序天然保持，风险低，但需要补控制器级测试。

---

## 问题 6：Windows 上 HTTP 同步阻塞冻结整个 UI

### 问题

`lib/client/http_async.mbt:77-80` 注释明确写明：`http_post_async` 在 Windows 上**退化为同步阻塞调用**（"This blocks the current coroutine until the response arrives"）。由于 MoonBit 运行时是单线程协作式调度，LLM 请求期间：**Tick 不发射、终端输入不处理、spinner 不转、Ctrl-C 无法取消**——UI 完全冻结直到响应返回。

### 根本原因

Windows 的 HTTP 后端（WinHTTP）没有接入 `@async` 事件循环的非阻塞机制；Unix 侧经 libcurl + 卸载线程（`lib/client/http_thread.c`）实现了"同步 HTTP 不阻塞事件循环"，Windows 侧该卸载路径缺失或未启用。

### 解决办法

1. 把 Windows HTTP 也卸载到 OS 线程（复用/移植 `http_thread.c` 的 pipe 通知模式：线程做同步 WinHTTP 请求，完成时写 pipe，事件循环读 pipe 唤醒）；
2. 或在 Windows 上使用支持异步的 HTTP API（WinHTTP 异步回调 / WinRT `HttpClient`），改造成本更高。

### 困难点

1. C 层线程与 MoonBit 运行时的交互约定（pipe 句柄、内存所有权）需要照搬现有 `http_thread.c` 的成熟模式，但 WinHTTP 与 libcurl 的请求/响应模型差异不小；
2. 是问题 4（流式显示）在 Windows 上的**前置条件**——不解决它，流式在 Windows 零收益；
3. 验证需要真实网络 + 真实 TTY，无法完全靠单元测试覆盖。

---

## 问题 7：全量测试 8 个失败（全部是测试代码的 Windows 平台假设）

### 问题

`moon test` 全量 2814 个测试中 8 个失败，逐个核实后**全部是测试代码假定 Unix 环境**，被测功能本身按设计工作：

| # | 测试位置 | 根因 |
|---|---------|------|
| 1-2, 5 | `lib/tool/shell_exec_wbtest.mbt:17,26,74` | 命令用 sh 语法 `$VAR` 读环境变量，cmd.exe 不展开 |
| 3 | `lib/tool/shell_exec_wbtest.mbt:46` | 假定 `/tmp` 存在且 `pwd` 可用（cmd 用 `cd`） |
| 4 | `lib/tool/shell_exec_wbtest.mbt:53` | `;` 在 cmd.exe 不是命令分隔符（应用 `&`） |
| 6 | `cmd/cmd_stub_activation_wbtest.mbt:15` | 同 #1，`echo val=$CLACKY_TEST_VAR` 是 sh 语法 |
| 7-8 | `lib/channel/channel_wbtest.mbt:202,246` | 硬编码写 `/tmp/...`，Windows 下解析为 `<当前盘符>:\tmp\...`，目录不存在写入失败 |

背景机制：`run_shell_command`（`lib/tool/shell_exec.mbt:111`）经 FFI `mb_system`（C `system()`）执行，Windows 上走 `cmd.exe /c`，env 前缀用 `set "VAR=val"`（`shell_exec.mbt:128-144`）——实现侧已做平台分支，是测试没做。

### 解决办法

- shell 相关 6 个：测试内做平台分支（复用 `OS=Windows_NT` 检测，或把 `shell_exec.mbt:64` 的 `shell_is_windows` 提升为 pub），Windows 分支用 `%VAR%`、`cd`、`&`、`%TEMP%`；
- channel 2 个：临时目录从 `TEMP`/`TMPDIR` 取（参考 `shell_exec.mbt:52` 的 `shell_temp_dir` 模式）。

### 困难点

纯测试改动，难度低；不涉及 Unix 行为变更，风险很低。注意不要让平台分支退化为"Windows 下跳过断言"。

---

## 问题 8：`%ERRORLEVEL%` 提前展开导致退出码误判

### 问题

`lib/tool/shell_exec.mbt:143` 用 `echo ..._%ERRORLEVEL%__` 捕获退出码，但 cmd.exe 在**解析整行时**就展开 `%ERRORLEVEL%`（早于命令执行）：

- 以 `exit N` 结尾的命令直接终止 cmd，标记没写入，走 `sys_exit` 回退碰巧正确（所以现有 `exit 3`/`exit 7` 测试通过）；
- 但"失败却不终止 cmd"的命令（如未识别命令，ERRORLEVEL=9009）会被标记为解析时刻的值 0 → **错误地报成功**。`cmd` 包的 "execute_hook runs command and succeeds" 测试就是靠这个假阳性通过的。

### 解决办法

`cmd.exe /v:on /c` 启用延迟展开，标记改用 `!ERRORLEVEL!`；补一个"非 exit 方式失败"的回归测试。Unix 分支（`'$?'`）无此问题，不受影响。

### 困难点

改动小，但要注意 `/v:on` 对整行其他 `%VAR%` 展开时序的影响（`build_env_prefix` 生成的 `set "VAR=val"` 与目标命令同行，需验证延迟展开下环境变量仍能正确传入子命令）。

---

## 问题 9：真实 TTY 人工验证未完成（流程项）

本轮修复（消息渲染、Markdown、补全、历史、Banner、Theme、ProgressStack、流式）全部通过单元测试 + eval 模拟器验证，但 eval 模拟器走 `VirtualScreen` + `full_redraw` 路径，**掩盖了 `redraw_live` 的真实终端行为**（问题 2/3 的定位错位、截断方向问题 eval 都测不到）。需要人工在真实终端确认：

- 发送消息后 `[assistant]` 回复显示、Markdown 着色正确；
- 长会话（输出超一屏）后新旧内容不错位、不重复（重点暴露问题 2/3）；
- spinner 动画、命令补全下拉框、历史回溯、Banner、`/theme` 切换的实际观感；
- Ctrl-C 取消、终端 resize 的行为；
- Windows 上确认问题 1 修复后的显示效果（对照乱码形态速查表）。

---

## 建议处理顺序

1. **问题 1**（乱码）——阻塞 Windows 用户，半小时级改动，最先做；
2. **问题 2 → 问题 3**（commit 语义 + 滚动）——有严格先后依赖，一起修，长会话正确性的根基；
3. **问题 7 + 问题 8**（测试平台假设 + ERRORLEVEL）——低成本，顺手清掉，让全量测试变绿；
4. **问题 6 → 问题 4**（Windows HTTP 卸载 → 流式管线）——有先后依赖，Windows 流式体验的关键路径；
5. **问题 5**（HookEvent 事件化）——架构债务，在问题 4 落地后顺势做（StreamChunk 事件化才有实际收益），或降级为"删除死变体 + 修正文件头注释"的最小处理；
6. **问题 9** 贯穿始终：每一步涉及渲染管线的改动都应做真实 TTY 验证。
