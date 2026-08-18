# 终端与杂项工具对齐（terminal / todo / trash / browser / feedback / skill / web，矩阵§2）· 增量 Spec

> **创建日期**: 2026-08-18  
> **状态**: 已通过对抗性审查（2026-08-18）· 已移入 `specs/active/`
> **关联总览**: `specs/draft/2026-08-18_diff-harness-matrix-backlog-overview.md`；diff-harness `docs/FEATURE_MATRIX.md` §2（terminal/todo/trash/browser/feedback/skill/web 部分）  
> **关联历史 spec**: 无同簇既有 spec（16 份 p5 spec 中无 terminal/misc 工具专簇；`2026-08-14_p5-tool-result-json-format.md` 与本 spec 的"结构化结果"条目有交叉，实施时以该 spec 的 JSON 结论为统一格式基准）；矩阵旧台账编号已被覆盖，本 spec 一律使用 `矩阵§2/条目名` 锚点  
> **来源差距**: P1 静态对齐矩阵（2026-08-12）§2 中 terminal/todo/trash/browser/feedback/invoke_skill/web_search/web_fetch 的 partial/missing 条目，2026-08-18 逐条对当前代码复核  
> **依赖**: B2（security 正则拦截修复后 terminal 的拦截文案/语义联动）；B2 image_inject 链路的产出侧在本 spec  
> **灰度 key**: 无

## 问题描述 [必填]

矩阵§2 执行类工具簇（security/registry/executor 部分已归 B2）复核后确认以下分歧仍然成立：

### terminal（高危集中区）

1. **前台超时未生效（missing，功能性级）**：`execute_command_sync` 的 `_timeout_ms` 参数在函数体内完全未使用，`run_system_command` 无限阻塞等待——模型传入的 timeout 与慢命令自动延长逻辑全部形同虚设；Ruby 有前台超时 + idle 早退 + 运行中 session 先行返回三层语义。
2. **background 语义反转（partial）**：background 模式先同步执行完命令（`execute_command` 阻塞等待），再 `mark_running`——与"后台立即返回、轮询取输出"语义相反，长命令会让整个 agent 循环卡死。
3. **kill 不真杀进程（partial）**：`TerminalSessionManager::kill`/`kill_all` 仅置 `status = Killed`，底层进程不受影响（`pty.mbt` 的 `PtyHandle::kill` 存在但未被 session 管理路径调用）。
4. **rm→trash 拦截缺失（missing，数据丢失级）**：Ruby 用 safe_rm.sh 把 `rm` 重写为进回收站；MB 无任何拦截，模型执行 `rm` 即永久删除。与 B2 条目"拦截层整体失效"叠加，MB 侧删除保护为零。
5. **多行命令误拦尾部换行（partial）**：`is_multiline_command` 对任意 `\n`/`\r` 命中，尾部单个换行（模型常见输出）也被拦截要求写文件。
6. **交互输入未实现（missing）**：session_id + input 返回 "not yet supported"。
7. **参数 schema 差异（partial）**：无 `env` 参数；timeout 单位毫秒（Ruby 秒）。
8. **输出清洗缩水（partial）**：`\r` 折叠/退格/CSI 终止符/回显剥离仅部分实现；溢出截断只留头部（Ruby 头 60%+尾 40%）且落盘文件名固定互相覆盖（Ruby 随机名）。
9. **Security 拦截文案吞原因（partial）**：`make_safe` 抛出的具体原因被丢弃，统一返回 "[Security] command validation failed"。
10. **CLACKY_SESSION_ID 注入缺失（missing）**、**结果格式拼文本 vs 结构化 Hash（partial）**、**描述文案完全不同（partial）**、**执行后端登录 shell 语义（unclear，PTY 失败退回 sh -c）**。

### todo_manager

11. **action 集合差异（partial）**：Ruby add/list/complete/remove/clear+批量；MB add/update/list/remove/set_deps（`complete`/`clear`/批量缺失；`update`/`set_deps` 为 MB 变体）。
12. **批量操作 / 自动清理 / 自动清空 / 提醒文案缺失（missing）**；**结果纯文本 vs 结构化 Hash（partial）**。

### trash_manager

13. **四个 action 全是固定文案桩（missing，功能性级）**：list/status/restore/delete 全部返回写死的占位文案（"Trash is empty"、"Files: 0" 等），无任何真实文件系统操作——工具整体是空壳；且与条目 4 联动：没有真实回收站，rm 拦截重写也无落点。
14. **会话 trash 类方法（unclear）**：Ruby 会话级 trash 方法的 MB 等价物未核查。

### browser

15. **截图管线缩水（partial）**：不下采样、超 150KB 仅警告、base64 丢弃（`[image_inject]` 占位无消费方——消费链路归 B2 决策 9，本 spec 负责产出侧：下采样 + 双落盘 + 载荷保留）。
16. **act kind 默认值映射 / 错误分类提示（unclear）**；**结果纯文本 vs 结构化+截断（partial）**。

### request_user_feedback / invoke_skill

17. **awaiting_feedback 硬编码 false（missing）**：`act_async` 中 `let awaiting_feedback = false`，Ruby 的等待用户反馈/auto_reply 语义整体缺失——request_user_feedback 工具无法真正挂起 run 等待回答。
18. **invoke_skill 参数面（partial）**：Ruby skill_name+task 双必填；MB arguments 选填。**fork_agent 子代理执行路径缺失（missing）**：全代码库无 `fork_agent` 消费（与 B7 fork_subagent 簇联动）。**注入机制差异（partial）**：MB 把技能全文作为工具结果返回；Ruby 短文案 + assistant 消息注入。

### web_search / web_fetch

19. **web_search：自定义 searcher（~/.clacky/searchers）缺失（missing）；输出拼文本且 max_results 硬裁剪到 20（Ruby 不裁剪）（partial）；描述/UA 池/超时重试/Bing 竞速多处差异（partial）**。
20. **web_fetch URL 校验语义反转（partial）**：MB 自动补 scheme 并把 http:// 改写为 https://（`normalize_url`）；Ruby 拒绝非 http(s) 且不篡改协议——改写可能把仅 http 可用的内网服务打挂。
21. **web_fetch 正文处理缩水（partial）**：仅去标签；无 script/style 剔除、空白折叠、title/meta 提取。**截断全文落盘 temp_file 缺失（missing）**：仅追加 "[truncated]"，模型无法读取全文。

## 现状分析 [必填 - 含代码验证]

### 验证记录（2026-08-18，对当前 HEAD 复核）

| 声称 | 验证方式 | 结果 | 结论 |
|------|---------|------|------|
| `_timeout_ms` 未生效 | 读 `lib/tool/terminal.mbt:191-260` | 参数出现在签名 L194，函数体 L197-259 零引用；`run_system_command` 无超时 | 证实 |
| background 同步执行 | 读 `lib/tool/terminal.mbt:450-462` | `execute_command` 阻塞完成后才 `mark_running` | 证实 |
| kill 仅置状态 | 读 `lib/tool/terminal_session.mbt:141-145,173-177` | `s.status = Killed`，无进程信号；`pty.mbt:174` PtyHandle::kill 未被接入 | 证实 |
| 多行误拦尾部换行 | 读 `lib/tool/terminal.mbt:54-62` | `command.find("\n")` 任意位置命中 | 证实 |
| 交互输入未实现 | 读 `lib/tool/terminal.mbt:391` | "interactive input not yet supported" | 证实 |
| 拦截文案吞原因 | 读 `lib/tool/terminal.mbt:433-435` | catch 丢弃异常载荷，固定文案 | 证实 |
| rm→trash 拦截 | Grep `safe_rm` 全库 | 0 匹配 | 证实 |
| CLACKY_SESSION_ID 注入 | Grep `CLACKY_SESSION_ID` 全库 | 0 匹配 | 证实 |
| trash_manager 全桩 | 读 `lib/tool/trash_manager.mbt:123-138` | list/status 固定文案；无 @fs 操作 | 证实 |
| awaiting_feedback 硬编码 | 读 `lib/agent/react.mbt:241` | `let awaiting_feedback = false` | 证实 |
| 截图 base64 丢弃 | 读 `lib/tool/browser_screenshot.mbt` + Grep image_inject | 占位符无消费方（B2 已核） | 证实 |
| invoke_skill 无 fork_agent | Grep `fork_agent` lib/tool | 0 匹配 | 证实 |
| web_fetch URL 改写 | 读 `lib/tool/web_fetch.mbt:172-183` | http→https 改写 + 无 scheme 自动补 https | 证实 |
| web_fetch 无 temp_file | 读 `lib/tool/web_fetch.mbt:101-107` | 仅 `+ "\n[truncated]"` | 证实 |
| todo action 集合 | 读 `lib/tool/todo_tool.mbt` schema 段（矩阵行引用 L19-58） | add/update/list/remove/set_deps | 证实 |
| 输出清洗/截断策略 | 读 `lib/tool/output_cleaner.mbt`（矩阵行引用 L41-43,117-215） | 与矩阵声明一致；逐函数核对留任务包 0 | 静态证实 |
| browser act kind / 登录 shell 语义 | 未逐行核对 | — | unclear，任务包 0 实测 |

Ruby 参照（openclacky，只读）：`tools/terminal.rb`（L66-93/120-129/180-203/258-259/433-442/526-549/1358-1361/1378-1464）、`output_cleaner.rb:25-56`、`todo_manager.rb:19-43,137-357`、`trash_manager.rb:14-34,389-533`、`browser.rb:122-142,186-206,303-432`、`request_user_feedback.rb`、`agent.rb:1241-1243,1299-1331`、`invoke_skill.rb:11-69`、`web_search.rb:34-327`、`web_fetch.rb:33-40,68-90,131-154,215-220`。

### 影响面

条目 1+2+3 组合意味着 MB 侧 terminal 面对长命令无保护（卡死 agent 循环）、对已启动进程无控制（kill 无效）；条目 4+13 组合意味着删除类操作在 MB 侧**既无拦截也无回收站兜底**，是全部 12 簇中数据丢失风险最高的组合之一。条目 17 使 request_user_feedback 成为死工具。

## 决策 [必填 - 含为什么]

1. **决策 1（terminal 超时）**：`execute_command_sync` 接入真实超时——`run_system_command` 按 timeout 限时，超时后按 Ruby 语义处置（kill 子进程 + 返回已产出输出 + 超时标记），不做"超时即整杀丢输出"。
   - **为什么**：timeout 是模型控制长命令的唯一手段，参数已收、schema 已承诺而不生效，属于契约违约。
2. **决策 2（background 真后台）**：background 模式改为真正异步：立即注册 session 并返回 session_id，进程在后台运行，poll 语义对齐 Ruby（session_id + input:"" 查询当前输出）。
   - **为什么**：同步执行后标记 running 在语义上是谎言，模型按 hint 去 poll 时命令其实已结束，且长命令阻塞整个循环。
3. **决策 3（kill 真杀）**：session manager 持有底层进程句柄（PTY 或 @process），kill 时发送终止；`PtyHandle::kill` 接入管理路径。
   - **为什么**：kill 无效使超时/取消/资源回收全链条失效。
4. **决策 4（rm 拦截 + 真回收站）**：先实现 trash_manager 真实行为（决策 5），再移植 Ruby safe_rm 拦截重写（`rm` → 进回收站，保留 Ruby 的路径豁免与确认语义）。
   - **为什么**：顺序上回收站是拦截的落点；二者都缺时 MB 侧无任何删除保护。
5. **决策 5（trash_manager 去桩化）**：四个 action 实现真实文件系统操作（trash 目录、list/status 真实统计、restore 移回、delete 真删），语义对齐 Ruby `trash_manager.rb`；会话级 trash 方法按任务包 0 核查结论处置。
   - **为什么**：固定文案桩使工具注册了但功能为零，模型得到虚假成功反馈。
6. **决策 6（多行命令）**：拦截前先 trim 尾部空白/换行，仅对真实多行（中间换行/heredoc）拦截，文案沿用 Ruby。
   - **为什么**：尾部换行是模型输出的高频噪声，误拦导致不必要的写文件往返。
7. **决策 7（输出清洗与截断）**：补齐 `\r` 折叠/退格/CSI 终止符/回显剥离；溢出截断改头 60%+尾 40%，落盘随机文件名；与 p5-stream-truncation 的截断文案约定保持一致。
   - **为什么**：尾部信息（错误栈通常在末尾）只留头会丢失，固定文件名互相覆盖使 full_output_file 引用失效。
8. **决策 8（参数面与文案）**：schema 增加 `env` 参数；timeout 单位按 Ruby 语义对齐（秒）或双单位兼容并文档注明；Security 拦截结果透传 make_safe 的具体原因；描述文案按 B1 决策 7 同原则修正（不逐字搬 Ruby，消除矛盾、补齐真实能力声明）。
   - **裁决点**：timeout 单位翻转影响既有 schema 消费方（TUI/Web 展示），若影响面大则以"双单位 + 默认秒"兼容。
9. **决策 9（todo）**：action 集合对齐 Ruby（补 complete/clear/批量），MB 独有 update/set_deps 作为超集保留（先例：BUG-0016~0019 裁决原则）；批量/自动清理/提醒文案按 Ruby 移植；结果格式与 p5-tool-result-json-format 结论统一。
10. **决策 10（browser 截图产出侧）**：下采样至 150KB 限制内（超限压缩而非仅警告）、双落盘（临时 + 会话目录）、base64 载荷按 B2 决策 9 定义的旁路格式产出；act kind 默认值映射与错误分类按任务包 0 核对结论对齐。
11. **决策 11（awaiting_feedback）**：移植 Ruby 等待语义：request_user_feedback 执行时 run 以 awaiting_feedback 状态挂起（`build_result(Success)` 前检查），server/TUI 侧的应答通道按既有 confirmation 队列机制扩展。
    - **为什么**：该工具是 agent 主动求取用户输入的唯一通道，硬编码 false 等于功能不存在。
12. **决策 12（invoke_skill）**：task 参数改必填（或按 Ruby 双必填对齐）；注入机制改为短文案结果 + assistant 消息注入技能全文；fork_agent 路径与 B7 fork_subagent 统一设计（本 spec 只留接入点）。
13. **决策 13（web_fetch）**：删除 http→https 改写，非 http(s) 显式拒绝（对齐 Ruby）；script/style 剔除 + 空白折叠 + title/meta 提取按 Ruby 移植；截断时全文落盘 temp_file 并在结果中给出路径。
    - **为什么**：协议篡改可能造成目标不可达且难以诊断；temp_file 是模型获取长页面全文的唯一通道。
14. **决策 14（web_search）**：输出不裁剪（对齐 Ruby），max_results 语义按 Ruby；自定义 searcher 目录加载移植；UA 池/超时重试/Bing 竞速按 Ruby 对齐。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tool/terminal.mbt` | 修改 | 超时接入、真后台、多行 trim、拦截原因透传、env/timeout 单位、结果格式 |
| `lib/tool/terminal_session.mbt` | 修改 | 进程句柄持有、kill 真杀、交互输入通道 |
| `lib/tool/output_cleaner.mbt` | 修改 | 清洗补齐、头 60%+尾 40%、随机落盘名 |
| `lib/tool/pty.mbt` | 修改 | kill 接入会话管理路径 |
| `lib/tool/trash_manager.mbt` | 重写级修改 | 四 action 真实实现 |
| `lib/tool/todo_tool.mbt` | 修改 | action 集合补齐、批量、提醒文案 |
| `lib/tool/browser.mbt` / `browser_screenshot.mbt` / `browser_action.mbt` | 修改 | 下采样、载荷保留、kind 映射、错误分类 |
| `lib/tool/invoke_skill.mbt` | 修改 | task 必填、注入机制、fork_agent 接入点 |
| `lib/tool/web_fetch.mbt` | 修改 | URL 校验反转修正、正文处理、temp_file |
| `lib/tool/web_search.mbt` | 修改 | 不裁剪、自定义 searcher、UA/重试 |
| `lib/agent/react.mbt` | 修改 | awaiting_feedback 语义（与 B2 的 denied 改造同文件，串行合入） |
| 各工具 wbtest | 修改/新建 | 逐决策回归 |

### 不涉及文件

- security.mbt/registry.mbt/tool_executor.mbt（B2）；请求格式面（B4）；fork_subagent 本体（B7）；image_inject 消费链路（B2 决策 9，本 spec 产出侧）。

## 实施计划 [必填]

### 任务包 0：实证与核对（预估 0.5 天）
1. 探针实证：`sleep 300` + timeout=1000 当前无限阻塞（静态→运行实证）。
2. 逐函数核对 unclear 条目：browser act kind 默认映射、执行后端登录 shell 语义、会话级 trash 方法。
3. 核对 Ruby 参照行号有效性。

### 任务包 1：terminal 控制面（预估 2 天）
1. 真实超时 + 超时处置语义；kill 真杀（句柄接入）；background 真异步。
2. 多行 trim；交互输入通道（session_id+input）。
3. env 参数、timeout 单位、拦截原因透传、CLACKY_SESSION_ID 注入。
4. wbtest：超时/kill/poll 生命周期用例。

### 任务包 2：trash + rm 拦截 + todo（预估 1.5 天）
1. trash_manager 真实实现；safe_rm 拦截重写接入（依赖 B2 正则拦截层已修复）。
2. todo action 补齐 + 批量 + 提醒文案。

### 任务包 3：输出清洗 + browser + feedback（预估 1.5 天）
1. output_cleaner 补齐与截断策略。
2. browser 截图下采样/落盘/载荷；kind 映射与错误分类。
3. awaiting_feedback 挂起语义。

### 任务包 4：skill/web + 收尾（预估 1.5 天）
1. invoke_skill 参数与注入；fork_agent 接入点。
2. web_fetch/web_search 对齐。
3. `moon check` + 全量 `moon test` 无回归。

## 验收标准 [必填]

- [ ] timeout 参数真实生效：超时命令返回已产出输出 + 超时标记，不阻塞 agent 循环
- [ ] background 命令立即返回 session_id，poll 可取增量输出，kill 终止真实进程
- [ ] 尾部带单个换行的命令不被误拦；真实多行仍拦截
- [ ] `rm` 被重写进回收站；trash_manager list/status/restore/delete 全部真实生效（wbtest 文件系统级断言）
- [ ] 溢出输出头 60%+尾 40%，full_output_file 随机名且可读取
- [ ] Security 拦截结果包含具体原因
- [ ] request_user_feedback 执行后 run 以 awaiting_feedback 挂起，应答后继续
- [ ] invoke_skill task 必填校验生效；技能全文走 assistant 注入
- [ ] web_fetch 不改写协议、拒绝非 http(s)；截断页面给出 temp_file 路径且文件存在
- [ ] web_search max_results 不硬裁剪
- [ ] `moon check` 0 errors；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 真后台/超时涉及平台进程模型差异（Windows cmd vs POSIX PTY） | 高 | 任务包 1 先做平台差异矩阵（wbtest 双平台跑）；PTY 路径与 sh -c 回退路径分别处理 |
| trash_manager 真实化后与 server API 的 trash DELETE 路由（B9）语义耦合 | 中 | B9 的 DELETE 无条件清空条目以本 spec 的真实 trash 为前提，实施顺序 B3 先于 B9 |
| safe_rm 拦截改写误伤合法 rm 用法（如 rm -i 交互） | 中 | 照搬 Ruby 豁免规则；wbtest 覆盖常见 rm 形态 |
| awaiting_feedback 挂起与 TUI/server 双端应答通道 | 中 | 复用 confirmation 队列机制；先 CLI 单端验证再接 server |
| 截图下采样依赖图片编解码能力 | 中 | MoonBit 无内建编解码时以外部命令/降级策略处置，任务包 3 先调研 |

## 依赖关系 [必填]

- **前置依赖**：B2 任务包 1（security 正则拦截修复）——safe_rm 拦截依赖拦截层真实生效。
- **后置依赖**：B9（trash DELETE 路由）以本 spec 真实 trash 为前提；B7 fork_subagent 落地后回填 invoke_skill fork_agent 接入点；image_inject 消费链路联调随 B2 任务包 4。
- **交叉**：timeout 单位与结果格式决策需与 p5-tool-result-json-format、p5-stream-truncation 结论对齐。

## 变更记录 [必填]

- 2026-08-18：创建（diff-harness 矩阵§2 terminal/misc 残留条目核实落 spec；16 项验证记录完成，2 项 unclear 留任务包 0 实测）。
