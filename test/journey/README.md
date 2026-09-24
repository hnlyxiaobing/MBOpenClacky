# Journey E2E 运行手册（层 9）

`cmd journey` 驱动**真实编译产物**走完整用户旅程：真实子进程（server / `--message`）、
真实网络栈（REST + WebSocket）、进程内 TUI 模拟器（真实 ReAct），上游统一指向
进程内 mock LLM 服务器（确定性、零成本）。定位是「代替用户日常手工验证」的自动化
E2E，与层 4 的单步场景回放互补：层 4 验证界面单步行为，层 9 验证端到端链路。

运行器规格见 `specs/draft/2026-09-23_journey-e2e-runner.md`；测试体系总览见
`docs/testing.md`。

## 日常档：一条命令

```bash
moon build --target native --release cmd
BIN=./_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe
"$BIN" journey --repo .            # 全量 18 条旅程
"$BIN" journey --repo . --filter cli_ --verbose   # 只跑 CLI 面
```

- 退出码：`0` 全绿；`1` ≥1 旅程失败（产品红）；`2` 用法错误；`3` 基础设施错误
  （二进制缺失/探测失败——「运行器坏」与「产品红」分开）。
- 报告落 `_build/journey/journey_<日期>.<txt|json|md>`（`--format` / `--out` 可调）。
- 旅程串行执行，每条旅程有独立看门狗（步级超时 + 旅程级超时 + 子进程硬杀），
  任何路径都不会挂起（moon test 挂起教训的设计对策）。

## 定时无人值守（Windows 任务计划程序）

当前注册的是「先构建再跑」变体（每天用最新代码）：

```bat
schtasks /Create /TN "MBOpenClacky Journey E2E" /SC DAILY /ST 08:30 /F ^
  /TR "cmd /c cd /d D:\MoonBit\MBOpenClacky && (moon build --target native --release cmd && _build\native\release\build\hnlyxiaobing\MBOpenClacky\cmd\cmd.exe journey --repo .) >> _build\journey\scheduled.log 2>&1"
schtasks /Run /TN "MBOpenClacky Journey E2E"     # 立即演练一次
```

轻量变体（直接跑现有二进制、省约 1 分钟构建）：去掉 `moon build ... && ` 前缀即可。
构建失败时 `&&` 短路、旅程不跑、错误落同一日志（不会误报「产品红」）。
运行器不依赖调用者的 `USERPROFILE`（子进程一律用沙箱 home），也无需交互输入。
注销：`schtasks /Delete /TN "MBOpenClacky Journey E2E" /F`。

## 失败证据与台账

- **证据包**（临时）：失败旅程的完整复现材料落
  `_build/journey/<时间戳>/<场景id>/`——`journey.json`（相位/步骤轨迹、断言明细、
  端口）、`mock_requests.jsonl`（上游请求原文）、`ws_frames.jsonl`（双向 WS 帧）、
  `rest_log.jsonl`、`child_*_stdout/stderr/exit.txt`、`config.toml`（种子配置）、
  `workspace/`（文件副作用终态）、`screenshots/` + `final_screen.txt`（TUI 虚拟屏）。
  绿色旅程默认删除证据（`--keep-all` 保留）。
- **台账**（入库）：`docs/journey-failures.md` 由每次运行自动维护（marked 段）。
  失败 → upsert 到「未修复」段（首次失败/最近失败/连续失败/摘要/证据路径）；
  **同场景重跑转绿 → 自动移入「已修复」段，闭环无需手工步骤**。人工批注写
  curated 段（BUG 引用等）。运行器不 commit，只提示 `git diff`。
- 一次只跑一个运行器（手动与定时重叠由使用者自律）；台账写入为整文件覆写。

## 场景编写（`test/journey/scenarios/*.json`）

顶层字段：`id`（台账键）、`title`、`area`（web/cli/tui）、`description`（进失败记录
的人话描述）、`timeout_ms`（旅程看门狗）、`server_port`（建议端口，冲突自动 +1）、
`permission_mode`（种子配置与 TUI agent 的权限模式）、`seed`（工作区种子文件）、
`llm_steps`（mock 上游剧本，格式与 test/e2e 完全一致：content / tool_calls /
error / stream_cut 顺序回放）、`phases`（相位列表）、`assertions`（终局断言）。

步骤动作（`phases[].steps[].action`）：

| 动作 | 关键字段 | 说明 |
|---|---|---|
| `spawn_server` | — | 起 server 子进程并轮询 /health |
| `http` | method/path/body/capture/headers/timeout_ms | 真实 TCP REST；capture 从响应 JSON 取点路径字段 |
| `ws_connect` / `ws_send` / `ws_wait_event` | url / frame / event,timeout_ms | 连 `/ws`、发帧、按事件 `type_name()` 等待 |
| `spawn_cli` / `spawn_bin` / `wait_child` | message/json/mode/continue、args、timeout_ms/capture | 子进程 CLI 与任意子命令；wait 可从 stdout JSON capture |
| `kill_child` / `kill_child_mid_run` | after_mock_request | 硬杀 / 上游第 N 次请求后硬杀（崩溃模拟） |
| `tui_new` / `tui_type` / `tui_press` / `tui_send` / `tui_screenshot` | cols,rows / text / key / timeout_ms | 进程内模拟器；tui_send 提交已键入文本走**真实 ReAct** |
| `sleep` | sleep_ms | 纯等待。不是断言，而是**配速**：需要在事件之间拉开真实间隔时使用（如秒级时间戳下的「活跃会话上浮」断言） |
| `assert` | assertions | 步内断言（共享 AssertionKind 词表） |

断言复用 `test/eval/assertions.mbt` 的统一词表（含旅程新增：`exit_code`、
`stdout_contains` / `stderr_contains` / `stdout_not_contains` / `stderr_not_contains` /
`stdout_json_path_eq`、`ws_frame_contains`、`ws_event_received` / `ws_event_count_at_least`、
`mock_request_count` / `mock_request_contains`、`json_path_ne`）。注意 `json_path_eq` /
`json_path_ne` / `stdout_json_path_eq` 的期望值是 stringify 形式（字符串值带引号，写
`"\"ok\""`）；路径走对象键与数组下标（如 `sessions.0.id`），下标越界或段落类型不匹配
一律判失败（见 `context.mbt` 的 `journey_json_walk`）。

占位符：`{port}` `{mock_port}` `{workspace}` `{home}` `{capture:<name>}`。

**编写纪律**：禁止时间类断言（响应文本/耗时随环境漂移）；mock 剧本是顺序回放，
请按「每旅程恰好 N 次上游请求」设计 `mock_request_count` 护栏；不确定的行为
（如崩溃后是否存在会话文件）不要硬断言，要么不断言要么用宽容区间。

## 真模型定期档（周检）

日常档刻意全 mock（确定性、可归因）。真模型质量由层 8 覆盖，建议每周手动跑：

```bash
"$BIN" eval --live --repo . --trials 3      # test/capability/tasks 全量 10 任务
```

审阅 `docs/eval/<日期>.md`；失败任务在台账 curated 段登记批注并引用报告。
真模型**不进**旅程场景（成本与随机性归因问题），两档严格分离。
