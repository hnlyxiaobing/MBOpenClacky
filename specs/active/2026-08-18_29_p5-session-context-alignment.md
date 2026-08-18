# Session Context 对齐（OS 探测 / Desktop / session_date 按日去重）· 增量 Spec

> **创建日期**: 2026-08-14  
> **状态**: 讨论中  
> **关联总览**: diff-harness `reports/BUGS.md` BUG-0033；`reports/p5_fix_unit_clustering.md` FU-13  
> **关联历史 spec**: `specs/completed/2026-07-29_agent-01-session-context-injection.md`（本 spec 是其对齐补全：该 spec 实现了注入机制本身，但未对齐 Ruby 的字段集与按日去重语义）  
> **来源差距**: P3 链路层差分（全部剧本 req_0001 messages[1]）  
> **依赖**: 无（批次 5，低风险；与 FU-01/FU-02 不同文件，可并行）  
> **灰度 key**: 无

## 问题描述 [必填]

P3 全剧本链路对比实锤：MB 侧注入的 session context 与 Ruby 侧存在三处字段级差异（`runs/001_read_edit_file/{ruby,moonbit}/requests/req_0001.json` messages[1]）：

1. **OS 探测为 `unknown`**：Ruby 侧 `OS: WSL/Windows`，MB 侧 `OS: unknown`。
2. **缺 `Desktop` 字段**：Ruby 侧 `Desktop: /mnt/c/Users/hnlyh/Desktop`，MB 侧无。
3. **缺 `session_date` 与按日去重**：Ruby 侧消息携带 `"session_date": "2026-08-14"`，且仅在"本会话尚无当日 context"时注入（跨日刷新）；MB 侧无该字段，且 `run()` **每次无条件注入**一条 context 消息。

Ruby 侧原文（req_0001 msg[1]）：
```
[Session context: Today is 2026-08-14, Friday. Current model: mock-model. OS: WSL/Windows. Desktop: /mnt/c/Users/hnlyh/Desktop. Working directory: /tmp/diffharness_ruby_hdvuv567]
```
MB 侧原文：
```
[Session context: Today is 2026-08-14, Friday. Current model: mock-model. OS: unknown. Working directory: /tmp/diffharness_moonbit_kcv1i704]
```

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "MB build_session_context 无 Desktop/Channel 字段" | 读 `lib/agent/react.mbt:13-21` | 模板为 `Today is \{date}, \{weekday}. Current model: \{model}. OS: \{os}. Working directory: \{wd}` | 确认缺 Desktop/Channel |
| "MB detect_os 仅读环境变量 OS/OSTYPE" | 读 `lib/agent/system_prompt.mbt:44-53` | `env_var("OS")` → `env_var("OSTYPE")` → `"unknown"`，无任何平台探测 | 确认探测手段薄弱 |
| "OS=unknown 的直接原因：harness 下两变量均缺席" | 读 `diff-harness/scripts/run_scenario.py:72-89`（env = `{**os.environ, ...}`）+ 实测 req_0001 | MB 侧 cmd.exe 是从 WSL 启动的 Windows 原生进程（ruby 侧探测出 WSL 可证 harness 在 WSL 内执行），WSL 环境本就无 `OS`（Windows 专有变量），`OSTYPE` 亦未透传到 Windows 进程环境 → 落入 `"unknown"` | 确认根因（环境变量探测在 WSL 互操作场景下必然失效） |
| "即使纯 Windows 原生运行，标签也与 Ruby 不对应" | 对比 `system_prompt.mbt:44-53` 与 `environment_detector.rb:90-97` | MB 会输出 `Windows_NT`；Ruby 标签体系为 `WSL/Windows` / `macOS` / `Linux` / `Unknown` | 确认需按 Ruby 标签体系重写 |
| "MB 每次 run 无条件注入、无按日去重" | 读 `lib/agent/react.mbt:56-73` | `run()` 每次 push ctx_msg，无日期检查 | 确认缺失 |
| "MB Message 无 session_date/session_context 字段" | 读 `lib/message/message.mbt:36-54` | 字段列表：role/content/tool_calls/tool_call_id/name/reasoning_content/task_id/created_at/system_injected/memory_update/subagent_*/token_usage/compressed_summary/transient | 确认缺失 |
| "Ruby 按日去重机制" | 读 `openclacky/lib/clacky/agent.rb:2156-2163`、`message_history.rb:177-182` | `inject_session_context_if_needed`：`return if @history.last_session_context_date == today`；`last_session_context_date` 取最近 `session_context` 消息的 `session_date` | 确认参照实现 |
| "Ruby context 构建规则（OS/Desktop 可省略、Channel 可选）" | 读 `openclacky/lib/clacky/agent.rb:2175-2208` | `os != :unknown ? "OS: #{os_label}" : nil`、`desktop ? "Desktop: #{desktop}" : nil`，parts.compact 拼接；`@channel_info` 存在时追加 Channel/Sender；消息带 `system_injected/session_context/session_date` | 确认参照实现 |
| "Ruby OS/Desktop 探测实现" | 读 `openclacky/lib/clacky/utils/environment_detector.rb:9-21,90-139` | `os_type` 读 `/proc/version` 含 "microsoft" → `:wsl`；`desktop_path` WSL 下经 `powershell.exe [Environment]::GetFolderPath("Desktop")` + `wslpath` 转 `/mnt/...` | 确认参照实现 |
| "MB 已有可复用的 WSL 探测" | 读 `lib/utils/environment_detector.mbt:46-49,60-78` | `is_wsl()` 检查 `WSL_DISTRO_NAME`/`WSL_INTEROP` 环境变量；`is_wsl1()` 已有 `osrelease_ffi` native stub（`lib/utils/sys_ext.mbt:16`） | 确认可复用，无需新增 FFI |
| "e2e 当前不做 session context 断言" | 读 `test/e2e/golden.mbt:4-5`；`grep "Session context\|session_date" test/e2e/*.mbt` | golden.mbt 注释明示"session context、latency 字段、display_text 等已登记为 BUG-0033~0035，不属于本测试的断言面"；grep 0 命中 | 确认断言空缺，修复后需补 |

### 详细分析

**OS=unknown 的根因链**（本 spec 核心结论）：

MB 的 `detect_os()`（`lib/agent/system_prompt.mbt:44-53`）只查两个环境变量。diff-harness P3 链路中，ruby 侧进程跑在 WSL 内（其 `/proc/version` 探测得 `:wsl`），而 MB 侧 cmd.exe 是经 WSL 互操作启动的 **Windows 原生进程**——WSL 的 Linux 环境里没有 Windows 专有的 `OS` 变量，`OSTYPE` 也不存在于透传给 Windows 进程的环境块中，两个变量均缺席，遂落入兜底 `"unknown"`。

推而广之：环境变量探测在 MB 的实际部署形态下**恒不可靠**——cmd.exe 是 Windows 原生二进制，其运行平台永远是 Windows，真正需要区分的是"被谁启动"（纯 Windows 终端 vs WSL 互操作）。Ruby 的标签体系（`os_label`：`WSL/Windows`/`macOS`/`Linux`/`Unknown`）描述的是 Ruby 进程自身平台；MB 侧对应的语义应是"Windows 原生（WSL 互操作启动）→ `WSL/Windows`"。`lib/utils/environment_detector.mbt` 已有 `is_wsl()`（`WSL_DISTRO_NAME`/`WSL_INTEROP` 在 WSL 互操作启动时会透传到 Windows 进程环境，diff-harness 的 `env = {**os.environ, ...}` 不剥离它们），可直接复用，无需读 `/proc/version`（Windows 原生进程也读不到）。

**session_date 会进入请求体**：Ruby 把 `session_date` 作为消息 hash 的普通键，经 `message_format/open_ai.rb:76-79` 的恒等转换直接进 wire JSON（req_0001 msg[1] 实测可见）。因此 MB 侧新增字段后，`to_api_message()` 不得剥离它——这是"内部字段出现在对外请求体"的又一样例，但 BUG-0033 台账期望行为明确"字段集与 Ruby 对齐"，按判定总则照齐（与 FU-14 中 BUG-0034/0035 的 A/B 裁决相互独立）。

**Desktop 路径形态**：Ruby WSL 下输出 `/mnt/c/Users/<u>/Desktop`。MB 为 Windows 原生进程，天然可得 `C:\Users\<u>\Desktop`（`USERPROFILE` + `\Desktop`，存在性检查后采用）；WSL 互操作场景下做确定性的盘符转换（`C:\...` → `/mnt/c/...`，等价于 wslpath 的纯字符串规则），即可与 Ruby 输出同构。非 WSL 的纯 Windows 场景保留 Windows 路径形态（Ruby 在 Windows 原生运行时 `os_type=:unknown`，会省略 OS/Desktop 两字段——该形态下无逐字节基准，按合理行为处理）。

**Channel/Sender**：Ruby 仅在 `@channel_info` 存在时追加（Web/IM 渠道）；CLI/非交互模式无此信息，本 spec 不实现，留待渠道功能对齐时处理。

## 决策 [必填 - 含为什么]

1. **决策 1**：重写 `detect_os()` 为平台标签探测，复用 `@utils.is_wsl()`：`is_wsl()` → `"WSL/Windows"`；否则 Windows 原生 → `"Windows"`（Ruby 无此标签的对等物，见决策 2 的省略规则）。探测结果进程级缓存（`Ref[String?]`），避免每条 context 重复查 env。
   - **为什么**：环境变量 `OS/OSTYPE` 探测在 WSL 互操作与多数 CI 环境下必然失效（实测 req_0001 得 `unknown`）；cmd.exe 恒为 Windows 原生，平台信息应来自部署形态而非环境变量猜测。`is_wsl()` 已存在且被 `browser_detector` 等模块使用，语义匹配"WSL 互操作启动"这一真实场景。
2. **决策 2**：对齐 Ruby 的字段省略规则——os 标签为 `"unknown"` 等价态时**省略** OS 字段而非输出 `OS: unknown`；Desktop 探测失败时省略 Desktop 字段。
   - **为什么**：Ruby `inject_session_context` 用 `parts.compact`（`agent.rb:2184-2190`）实现该语义；逐字段对齐才能消除 diff 噪音。
3. **决策 3**：Desktop 探测 = `USERPROFILE` + `\Desktop`（`@fs.is_dir` 验证存在），WSL 场景（`is_wsl()`）转换为 `/mnt/<drive>/...` 小写盘符形式。
   - **为什么**：Ruby WSL 路径经 powershell.exe + wslpath 得到的正是该形态；MB 原生侧无需 fork 子进程，纯字符串规则确定性等价。`USERPROFILE` 缺席或目录不存在时按决策 2 省略字段。
4. **决策 4**：`Message` 增加 `session_date : String?` 与 `session_context : Bool?` 字段；`MessageHistory` 增加 `last_session_context_date()`；`run()` 注入前判 `history.last_session_context_date() == today` 则跳过。序列化对齐 Ruby 泄漏语义：`session_date` 在 `to_json` 中输出且 `to_api_message()` 不剥离。
   - **为什么**：按日去重是 Ruby 防"同一会话每天只注入一次"的设计（`agent.rb:2156-2163` 注释：cache-safe，context 总插在当前 user 消息前）；MB 每次 run 无条件注入会在长会话中累积冗余 context 消息，且与 Ruby 请求序列不可比。`session_context` 标记是去重查询的索引键（对齐 `message_history.rb:180`）。
5. **决策 5（不做）**：不实现 Channel/Sender 追加（CLI 模式无 channel_info）；不追求 Desktop 路径在"非 WSL 纯 Windows"形态下的逐字节对齐（无 Ruby 基准）。
   - **为什么**：两者在 P3 harness 场景下均不可观测，属于超范围设计。

MoonBit 约束检查：不涉及动态加载 trait、不新增 FFI（`is_wsl()` 纯环境变量，`osrelease_ffi` 本 spec 不用）、不新增依赖。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/system_prompt.mbt:44-53` | 修改 | `detect_os()` 重写为平台标签探测（复用 `@utils.is_wsl()`，进程级缓存）；Layer 6 静态注入处（同文件 :118）同步使用新标签 |
| `lib/agent/react.mbt:13-21` | 修改 | `build_session_context()`：补 Desktop 字段、OS/Desktop 省略规则、拼接对齐 Ruby parts.compact 语义 |
| `lib/agent/react.mbt:56-73` | 修改 | `run()` 注入前加按日去重守卫；ctx_msg 带 `session_date`/`session_context` 字段 |
| `lib/message/message.mbt:36-54,57-89,185-203,206-` | 修改 | `Message` 增加 `session_date`/`session_context` 字段；`to_json` 输出 `session_date`（Some 时）与 `session_context`（true 时）；`from_json` 回补；`to_api_message` 保留两字段（对齐 Ruby 泄漏语义，见决策 4） |
| `lib/message/history.mbt` | 修改 | 增加 `MessageHistory::last_session_context_date() -> String?`（对齐 `message_history.rb:177-182`） |
| `lib/agent/agent_wbtest.mbt` | 修改 | 新增：OS 标签探测（mock env）、Desktop 省略规则、按日去重（构造昨日 session_date 的 history → 注入新 context；当日 → 跳过） |
| `lib/message/message_wbtest.mbt`（或等价文件） | 修改 | session_date/session_context 序列化与 from_json 往返 |
| `test/e2e/scenarios_wbtest.mbt` | 修改 | 全部剧本补 req_0001 session context 结构化断言（见验收标准） |

### 不涉及文件

- `lib/utils/environment_detector.mbt` — `is_wsl()` 现成可用，不改
- `lib/agent/time.mbt` — `current_iso8601()`/`current_weekday()` 现成可用，不改
- `lib/client/`、`lib/agent/llm_caller.mbt` — 不涉及 LLM 调用层
- Channel/Sender 注入 — CLI 模式无 channel_info，超范围

## 实施计划 [必填]

### 任务包 1：OS 标签探测与 Desktop 字段（预估 0.5 天）

1. `detect_os()` 重写：`is_wsl()` → `"WSL/Windows"`；否则 `"Windows"`；探测结果缓存。
2. 新增 `detect_desktop() -> String?`：`USERPROFILE\Desktop` 存在性检查；`is_wsl()` 时转 `/mnt/<drive>/...`。
3. `build_session_context()` 改 parts 拼接：OS/Desktop 按决策 2 省略规则；单测覆盖四种组合（有/无 OS × 有/无 Desktop）。

### 任务包 2：session_date 字段与按日去重（预估 0.5 天）

1. `Message` 增 `session_date`/`session_context` 字段 + 序列化/反序列化/`to_api_message` 保留。
2. `MessageHistory::last_session_context_date()`。
3. `run()` 注入守卫；单测覆盖：首次注入、当日跳过、跨日重注入。

### 任务包 3：e2e 断言补齐与链路回归（预估 0.5 天）

1. `test/e2e/scenarios_wbtest.mbt`：新增通用断言函数（如 `assert_session_context(requests)`），解析 requests[0] 的 messages[1]，断言：
   - content 以 `[Session context: Today is <今日日期>, <星期>` 开头；
   - 含 `Current model: mock-model.`、`OS: WSL/Windows.`、`Desktop: /mnt/`（前缀）、`Working directory: <workdir>`（结构化包含断言，非逐字节——workdir 为每轮随机临时目录）；
   - 消息 JSON 含 `session_date` 键且值为今日日期；
   - 单剧本内仅注入一次（按日去重：全部请求中 session context 消息数 == 1）。
2. 全量 `moon test` 无回归；diff-harness 复跑剧本 001 两侧对比，确认 msg[1] 差异收敛至仅剩 working directory 随机段。

## 验收标准 [必填]

- [ ] MB session context 含真实 OS 标签（WSL 互操作场景为 `WSL/Windows`），不再出现 `OS: unknown`（unknown 时省略字段）
- [ ] Desktop 字段存在且 WSL 场景为 `/mnt/<drive>/...` 形态；探测失败时字段省略而非输出空值
- [ ] 注入按日去重：同一日内多次 `run()` 仅一条 session context；`session_date` 出现在请求体 messages[1]
- [ ] `test/e2e` 全部 11 个已执行剧本补上实施计划任务包 3 所列断言点并转绿
- [ ] `moon check` 0 errors（lib/agent、lib/message、test/e2e）
- [ ] `moon test lib/agent`、`moon test lib/message`、`moon test test/e2e` 全部通过
- [ ] 全量 `moon test` 无回归
- [ ] diff-harness 复跑 001：`reports/p3/001_read_edit_file_diff.md` msg[1] 差异收敛（仅余 workdir 随机段）；BUG-0033 台账转 fixed

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| WSL 互操作环境变量（WSL_DISTRO_NAME/WSL_INTEROP）未透传到 Windows 进程 | 中 | diff-harness 实测透传（`env = {**os.environ, ...}` 不剥离）；透传缺席时退化为 `Windows` 标签，不崩溃；单测 mock env 覆盖两分支 |
| Desktop 路径转换与 Ruby wslpath 输出存在形态差（如 8.3 短名、符号链接） | 低 | 仅做盘符/分隔符纯字符串转换；e2e 用前缀断言（`/mnt/`）而非全路径逐字节 |
| session_date 进请求体属内部字段泄漏，未来若 FU-14 裁决选 B（归一化抹除）会产生口径冲突 | 低 | 两 spec 独立：BUG-0033 台账期望行为明确"字段集与 Ruby 对齐"；若 FU-14 选 B，compare 归一化表统一追加 session_date 即可 |
| `system_prompt.mbt` Layer 6 静态注入的 OS 同步变化，可能影响其他依赖 `Windows_NT` 字样的下游 | 低 | grep 全库确认无对该字样的断言；`moon test` 全量回归兜底 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无强依赖；修复后 diff-harness compare 的 req_0001 噪音降低，利于后续剧本对比定位真实差异。与 FU-14（`2026-08-18_23_p5-observability-stats-fields.md`）在 `message.mbt`/`to_api_message` 上有文件交叠，建议同批评审时统一序列化字段口径

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-14 | 初始版本 | P5 归并分析 FU-13（BUG-0033） |
