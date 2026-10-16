# MBOpenClacky 项目变更日志

> 记录项目每次完成的重要功能、Bug 修复及关键重构，便于回顾每日工作进展。

---

## 格式说明

```
### YYYY-MM-DD  标题
- [类型] 变更描述
  - 详细说明（可选）
```

类型标签：
- `[feat]` — 新功能
- `[fix]` — Bug 修复
- `[refactor]` — 代码重构
- `[perf]` — 性能优化
- `[test]` — 测试相关
- `[docs]` — 文档相关
- `[chore]` — 工程配置 / 依赖 / CI

---

## 变更记录

### 2026-10-16  发布 0.3.1（文档与脚本全面修订）

- `[chore]` **版本发布**：`moon.mod` / `cmd` VERSION / TUI `app_version` / Web `handlers_version` VERSION 四处一致升到 `0.3.1`，repo-stats 三处块同步重生成。
- `[docs]` **全仓文档/脚本准确性扫描**：修正 3 处「moon.work 含 vendored members」的过时表述（实为 `third_party/clap` 模块内 vendored 包）；归档两条已修复缺口（e2e 死等、013 少录请求）至 resolved-gaps；修正 testing.md journey 数（23→26）与 web-e2e 条件跳过数（4→7）；test-report 笔误与层 8 结论（修复后 10/10）；development-efficiency 的 CI 缓存策略标注为已证伪；journey-failures 清除两条失效场景的孤儿条目；README 补全文档索引、更新产物体积描述。
- `[fix]` **known_gaps.sh Windows bug**：`awk -v secfile=` 会把 `$TMP_DIR` 的反斜杠当转义符吞掉，导致 `generate` 静默抹掉 auto-scan 段、`check` 恒报 stale；改为 `ENVIRON` 传参。EXIT trap 改为容错写法。
- `[refactor]` `install.sh`/`install.ps1` 的二产物定位统一走 `scripts/release_binary.sh`（当前布局优先），清理过时注释。

### 2026-10-16  CI 作业拆分与 e2e 死等根因修复

- `[test]` **`test/e2e` 拆为独立 CI 作业**（`f798c57`）：整包跑 `test/e2e` 在 Windows 本地与 Linux CI 均出现死等（`MockLlmServer::serve` 串行单连接无读取上限，请求头未送达的 attempt 永久 parked accept，`shutdown()` 后 task group 永不 join）。拆分后死等只吃掉独立作业（`timeout-minutes: 15`），主步骤回到 ~110s；repo-stats 门禁改读 `moon_test_main.log` + `moon_test_e2e.log` 拼接，口径 4071+15=4086 不变。
- `[fix]` **e2e mock server 卡死与 013 竞态根因修复**（`1f21bcf`）：accept 包 `with_timeout_opt(200)`、每连接包 `with_timeout_opt(30000)`；剧本 013 偶发 `10 != 11` 的根因坐实为 `set_retry_delay_override_for_test` 的进程级 Ref 被并发剧本 `defer` 还原清掉，改为钩子只设不清 + `accept_grace_ms=200`。本地整包 64.7s→21.7s；`conn_deadline_ms=1` 反证 6 条剧本红。两条缺口从 known-gaps 归档至 resolved-gaps。
- `[chore]` repo-stats 门禁日志口径修正（`bb2296b`）：只读主步骤日志，缺失即显式失败，不回退混日志。
- `[test]` journey 场景 23→**26** 条（Web 10 / TUI 5 / CLI 11）。
- `[docs]` 台账登记间歇性 013 证据与两管线远程复验结论（`a3ef65c`、`01b9ce7`）。

### 2026-10-15  发布 0.3.0（版本对齐 0.2.0→0.3.0，mooncakes 新版本）

- `[chore]` **版本发布**：`moon.mod` / `cmd` VERSION / TUI `app_version` / Web `handlers_version` VERSION 四处一致升到 `0.3.0`，并同步 README/AGENTS/project-status 的 repo-stats 块。这是继 mooncakes 上 `0.1.3` 之后发布的新版本（本地 `0.2.0` 从未发布到 registry）。
- `[feat]` 自 `v0.2.0` 基线以来的主要能力：Agent shell hook 系统（7 个生命周期事件）、OpenAI Responses API（`/v1/responses`）支持、多渠道真实收发接线（飞书/Telegram/Discord/钉钉/企微/微信）、媒体生成（图像/视频/语音/转写）真实 provider 调用、benchmark 显式基线闸门、层9 用户旅程 E2E runner（`cmd journey`）。
- `[chore]` **依赖收口**：迁移到 registry `Milky2018/css@0.6.0`，移除废弃 vendored `mbtpdf`，刷新前端 vendor 库并去掉最后一处 CDN 依赖。
- `[chore]` **发布解阻：清理依赖图中的旧格式包**（最终依赖状态，取代上一条中已被移除的 `Milky2018/css`）：
  - TUI 宽度计算从 `mizchi/tui@0.10.2` 迁到 `moonbit-community/unicodewidth@0.2.1`——项目只用到其 core 的两个宽度函数，改由本地 `lib/tui/cjk_width.mbt`（基于 UAX#11）重新实现 `char_display_width`/`string_display_width`，TUI 本体仍为自研；`lib/tui/parity_probe_wbtest.mbt` 校验宽度语义 parity。同时移除孤立依赖 `Milky2018/css`。
  - `DzmingLi/clap@0.2.8` 是 registry 上的最新版且仍只带旧格式 `moon.pkg.json`（新工具链拒绝），而 `moon publish` 会脱离本地 `vendor`、纯从 registry 拉依赖跑干净 `moon check`，因此该旧格式传递依赖会中断发布校验。clap 仅依赖 `moonbitlang/core`，遂以 MIT 许可 vendored 进本模块 `third_party/clap`（保留 `@clap` 别名，仅 `cmd` 消费；对 upstream 逐字保留，仅在该包 `moon.pkg` 内放宽 `warnings = "-20-79-82"`）。详见 `third_party/clap/VENDOR.md`。
  - 结果：`moon check -d` 0 error/0 warning，`moon publish --dry-run` 的解包干净校验通过（Server 202 Accepted）。

### 2026-10-14  前端 vendor 库刷新 + 依赖清理 + crater-core 增量重排地基

- `[chore]` **依赖收口**：移除 `vendor/milky2018-css` 工作区成员，改用 registry `Milky2018/css@0.6.0`（0.6.0 已把 `Float` 重命名为 `CssFloat`，nightly error-4003 的 vendor 绕行不再需要）；同时删除已废弃的 vendored `mbtpdf`。
- `[chore]` **前端 vendor 库刷新**：highlight.js 11.11.1→11.12.0、marked 18.0.5→18.1.1、KaTeX 0.16.11→0.19.0、qrcode-generator 1.4.4→2.0.4，并重新打包 CodeMirror 6（导出面仍是 27 个全局名，已实测）。新增 `web/vendor/README.md` 记录版本、来源与许可。
- `[fix]` **微信登录页去 CDN**：`web/weixin-qr.html` 的二维码库从 `cdn.jsdelivr.net` 改为本地 `web/vendor/qrcodejs/`，前端运行时不再依赖任何 CDN，与 `docs/web-ui-parity.md` 的声明一致；补丁登记见 `web/PATCHES.md` P3-004。
- `[chore]` **vendored `mizchi/crater-core`：增量重排地基 + 布局开销**：新增 `Node.dom_id` / `Node::set_uid` 与 `UidRegistry` / `stabilize_uids`（跨重建稳定 uid），以及 `node_is_clean` / `set_node_clean_predicate` 记忆化开关；另把布局热路径的 `String::has_prefix`（每次调用都分配跳表）换成 `str_has_prefix`，并让 `Dimension::Calc` / `MathFn` 的 fallback 按可用宽高真实求值。记忆化开关默认不安装，静态全量布局路径行为不变。**当前无调用方**：驱动 `compute_tree_incremental` 尚未实现，且 vendor 副本只带 `node/` 与 `layout_types.mbt`（不含 `layout/`），这两批改动只有 vendored 库内的自洽性，没有本仓库可见的行为变化。
- `[chore]` test/web-e2e 的 `@playwright/test` 升到 `^1.64.1`。
- `[docs]` 清除已删除的 `vendor/milky2018-css` 残留引用（`AGENTS.md`、`Dockerfile`、`scripts/repo_stats.sh`）；`web/UPSTREAM_SYNC.md` 更新文件基数（89→91）、vendor 冲突策略与 rsync 排除项，避免下次上游同步静默回退库版本。

### 2026-10-14  文档全面校准与去冗余

- `[docs]` 重写 README、快速入门、项目状态、测试体系和优化计划，删除主观完成度、过时对比表和重复命令。
- `[docs]` 修正当前事实：14 个注册工具、16 个默认 Skill + 3 个扩展 Skill、10 个扩展清单、Journey 23 条（Web 9 / TUI 5 / CLI 9）、真模型任务 10 条。
- `[docs]` 将渠道状态更新为当前源码事实：Telegram 长轮询、企微 WebSocket、Discord Gateway、钉钉 Stream Mode 和 webhook 接收路径均已接线。
- `[docs]` 合并 Web 浏览器 E2E 的一次性验证报告为 `test/web-e2e/README.md`，补充 21 spec / 114 tests、非 CI 与本机路径限制。
- `[docs]` 清理 known-gaps 顶部已解决条目，保留当前边界；修正 spec 索引、TUI/Web 回归命令、AI 使用闸门和 upstream sync 的旧入口。
- `[chore]` CI 与 Docker 构建改用 MoonBit `latest` 稳定版工具链，不再安装 nightly。
- `[chore]` 刷新 codebase-memory 索引，新增 ADR-0002，记录 MoonBit 图谱覆盖限制与源码兜底规则。

### 2026-09-23  开发计划批次闭环 + 任务集扩充 + benchmark 规格

- `[fix]` **Web 状态码回落**：`response_to_core` 补全 status 映射，不再把 5xx 吞成 200
- `[fix]` **JSON 转义**：错误构造器改用 `to_json()` 转义 message，产出合法 JSON
- `[fix]` **stdout 污染**：`[stream-summary]` 诊断行改走 stderr C stub
- `[fix]` **updated_at 回退**：`build_session_summary` 投影真实字段，排序加 id 确定性 tie-break
- `[feat]` **渠道接收侧**：Telegram 长轮询、企微 WebSocket、钉钉 Stream Mode 三条接收链路接线
- `[feat]` **MCP stdio server**：完整 JSON-RPC 2.0 server（initialize/tools/list/tools/call）
- `[feat]` **备份 ZIP 真打包** + **trash 磁盘移动** + **browser 卫生管理**
- `[chore]` **死代码清理**：删除 `lib/hook/shell_loader.mbt`（零调用 + 静默 Allow 陷阱）
- `[test]` **任务集扩充** 6→10 条 + **benchmark 规格** `specs/draft/2026-09-23_benchmark-gate.md`
- `[docs]` 文档校准、known-gaps/testing/README 同步

### 2026-09-23  E2E 用例第二批 + 层 9 场景校验修复

- `[fix]` **14a 退避假红**：高负载下 sleep 膨胀只保留下界判失败，上界改诊断
- `[test]` **18a hook 加载护栏**：4 例覆盖缺目录/TOML/JSON/混入非法文件
- `[test]` **层 9 场景修复**：会话排序改确定性名称、URL 编码修正（crescent 不解码）
- `[docs]` 台账闭环、known-gaps 86→84 命中

### 2026-09-23  E2E 基建首批落地（JSON 路径数组下标 + 断言词表扩展 + 闸门用例）

- `[test]` **JSON 路径支持数组下标**：`sessions.0.updated_at`，越界返回 None
- `[test]` **断言词表 29→32 种**：新增 `stdout_not_contains`/`stderr_not_contains`/`json_path_ne`
- `[test]` **Spec A 闸门用例 1a/2a**：状态码回落 + 错误体 JSON 合法性，`plan_fix_pending` 闸门锁 CI

### 2026-09-23  用户旅程 E2E 工作流（层 9 · cmd journey）

- `[feat]` **`cmd journey` 子命令**：驱动真实编译产物走 13 条端到端旅程（Web 5/TUI 3/持久化 3/CLI 2），mock 上游进程内托管，沙箱隔离不触碰真实 home
- `[feat]` **失败自动记录闭环**：证据包写 `_build/journey/`，台账 `docs/journey-failures.md` 自动维护，同场景转绿即自动关闭
- `[feat]` **Web/TUI 驱动**：真实 TCP REST + WS journal + 虚拟屏 Agent 注入
- `[feat]` **断言词表扩展**：8 个旅程种类 + 真模型定期档（capability 4→6）
- `[docs]` testing.md/README/test/journey/README + spec 归档
- 验证：13/13 旅程全绿；Windows 任务计划程序注册每日 08:30

### 2026-09-23  eval 报告管线与 CLI 入口统一

- `[refactor]` **统一断言枚举 `AssertionKind`**（20 种）：TUI/Web 适配器收敛为单一解析与求值
- `[refactor]` **统一报告 `UnifiedReport` + 三渲染器**：text/json/markdown
- `[feat]` **统一 CLI 入口 `cmd eval`**：`--tui/--web/--offline/--live` 四后端同一子命令
- `[refactor]` **性能基准接入统一管线**
- `[docs]` testing.md 层 4 改写 + 数字重新生成

### 2026-09-23  执行计划收尾（WP-3.4~3.6）+ 文档集状态对齐

- `[feat]` **性能基准改为真实执行**：`grep_search` avg 99ms（此前恒 0ms）
- `[fix]` **Windows 本机全量测试解除阻塞**：`lib/mcp` python3 stdio 测试 Windows 跳过
- `[docs]` **执行计划与路线图重写**为"结论+索引"形态（470→159 / 184→102 行）
- `[docs]` **五处文档与代码脱节修正**：media REST 已接线、层 7 驱动已真实、渠道状态对齐等
- `[docs]` **测试命令统一**：scoped 全量一条命令（Windows/Linux 通用）

### 2026-09-22  Web 会话 JSONL 事件流（WP-3.2）

- `[feat]` **三端会话日志闭环**：`SessionLogProducer` 下沉 `lib/agent`，Web 端 per-session 独立 producer，四退出路径 flush
- `[test]` 6 条新测试（压缩 Summary/双压缩/空缓冲/seq 续写/WS 全链路）
- `[docs]` spec 归档 `specs/completed/`

### 2026-09-22  MCP HTTP 传输接线（WP-3.3）

- `[feat]` **MCP 双传输**：Stdio + Streamable HTTP（`@async/http`），SSE 逐帧扫描 + 会话 ID 回带
- `[test]` 13 条全走真实 socket（同进程临时端口，无外网）
- `[docs]` spec 归档

### 2026-09-22  旧会话只读迁移投影（WP-3.1）

- `[fix]` **32 个历史会话全部可见**：Debug-repr → Json 递归投影 + Option 旧包装容忍 + 字段变体兼容
- `[fix]` **只读保证**：磁盘字节不变，投影只在内存构造
- `[test]` 14 条新用例（投影/保真/格式标签/旧包装）

### 2026-09-22  全平台消息编辑/撤回接线（WP-1.6）

- `[feat]` **编辑/撤回真实端点**：Telegram editMessageText/deleteMessage、Discord PATCH/DELETE + get_current_user、飞书 DELETE + 新增 http_delete
- `[fix]` **Discord download_attachment 静默假成功→真实 GET**
- `[test]` mock TCP 基建补三平台路由 + 闸门测试改写

### 2026-09-22  执行计划/路线图状态核对

- `[docs]` **逐项代码核对 17 个工作包**：9 完成 / 1 作废 / 7 未开始
- `[docs]` **补正三处失真**：benchmark 空循环 0ms、WP-1.6 声明与实现不一致、WP-3.5 仍挂死
- `[docs]` 路线图/项目状态/known-gaps 同步

### 2026-09-22  `cmd eval --live` 真模型能力评测（WP-2.2）

- `[feat]` **真模型评测一条命令跑通**：`test/eval/live_harness.mbt` + 4 条任务，入口 `cmd eval --live`
- `[feat]` **模型解析可指名**：`MBOPENCLACKY_*` > `config.toml` > DeepSeek 兜底
- `[fix]` **工具面收窄**：重建受限 registry（file_reader/write/edit/grep/glob，无 shell/网络）
- `[test]` 假 runner + mock LLM 端到端 + 模型解析优先级
- 首次真模型运行：12/12 trial、33/33 断言、可重复性 1.0

### 2026-09-22  GEP 技能反思做实（WP-2.1）

- `[feat]` **真实 LLM 反思**：prompt 构建 + 容错 JSON 解析（剥离代码围栏/字符级花括号配平）
- `[feat]` **追加式进化日志**（`evolution_log.json`，上限 500 条）+ **回写前备份**
- `[fix]` **Web 进化端点真实实现**：transcript 必填、apply opt-in、历史过滤/限量接线
- `[fix]` **错误响应 JSON 转义** + **查询串从 URL 提取**（不在 HttpRequest.params）

### 2026-09-22  渠道配置单一真相源贯通

- `[fix]` **`~` 从未展开→渠道配置恒不加载**：新增 `expand_config_path`（`@utils.home_dir()`）
- `[fix]` **Web 面板双真相源→单一真相源**：删除进程内 ChannelEntry，全部读写 ChannelManager
- `[feat]` **配置写入原语**：`save_config`/`set_platform_enabled`/`apply_config`/`spawn_gateways`
- `[fix]` **微信适配器硬要求 app_id/app_secret→改为可选**
- `[fix]` **channel-manager 技能修正**：channels.yml→channels.json，逐平台列出完整 settings 键
- `[feat]` **面板 Diagnostics 接真实探针** + **密钥掩码全平台统一**

### 2026-09-22  文档归并 + 构建脚本归位

- `[docs]` **删除两份黑客松一次性文档**：改造开发计划 + 一页项目说明；生命力内容沉淀为路线图 §7
- `[chore]` **`build-script.js` 从根目录归位 `scripts/`**：同步 moon.mod/CI/Dockerfile/cmd 四处引用

### 2026-09-22  连通性探针真实化 + 卫生清理

- `[feat]` **四平台探针真实化**：telegram getMe / 企微 gettoken / 微信 getupdates / 钉钉 accessToken
- `[fix]` **删除两处不可达同步处理器**（违反诚实契约）
- `[fix]` **离线评测报告改落 `_build/eval/`**（不污染工作区）
- `[chore]` **`moon fmt` 漂移清零**：首次全仓 `moon fmt --check` 通过

### 2026-09-22  钉钉/企微/微信 send 接线（WP-1.2~1.4）

- `[feat]` **三渠道发送侧真接线**：钉钉 Stream Mode + download_file_url、企微 message/send、微信 sendmessage
- `[feat]` **微信 AES-128-ECB 落地**：`moonbitlang/x/crypto` aes_ecb + 自实现 PKCS#7（取消 FFI 评估）
- `[test]` 通用 mock TCP server 覆盖三渠道 + AES FIPS-197 向量

### 2026-09-22  飞书 send/receive 接线（WP-1.1）

- `[feat]` **飞书六 API 真接线**：send/update/upload_image/upload_file/download_resource/fetch_chat_history
- `[fix]` **契约修正**：content 改为字符串化 JSON（原形状对真实 API 必失败）
- `[feat]` **HttpMethod 新增 Patch** + http_patch 便捷包装

### 2026-09-21  品牌资产重制 + 媒体生成接线（WP-0.1 / WP-1.5）

- `[feat]` **媒体生成接线**：四端点从 501 stub→真实调用（OpenAI 兼容 + DashScope + Gemini）
- `[feat]` **品牌资产 MBOpenClacky 化**：六个品牌文件以青蓝渐变+气泡设计重制，品牌法律矛盾关闭

### 2026-09-21  文档校准与去冗余 + 优化路线图

- `[docs]` **新增 `docs/improvement-roadmap.md`**：分 P0-P3 级路线图
- `[fix]` **构建产物路径全仓校正**、**警告口径对齐 CI**、**TUI 命令表按代码重写**、**渠道完成度去夸大**
- `[chore]` **删除 `docs/web-ui-test-plan.md`**：一次性对比方法学，可复用内容并入 web-ui-parity.md

### 2026-09-21  脚本体系瘦身：15→8 个

- `[chore]` **删除 8 个已失效脚本**：patch_crescent.sh / setup_yoga.sh / install_browser.sh / with_msvc_env.sh / test_sse_server.py / extract_i18n_keys.ps1+README / check-crypto-build.ps1
- `[fix]` **install.sh/ps1 修复**：删除不做事的逻辑、构建校验口径对齐（`--release cmd`）
- `[refactor]` **install.ps1 MSVC 激活合并**为单函数
- `[chore]` **warn_count.sh 改为真正闸门**：默认预算 0，超预算非零退出

### 2026-09-21  测试体系统一 + 目录合并 + 过程文档清理

- `[chore]` **根 `benchmark/` 并入 `test/`**，`docs/testing.md` 重写为 8 层门禁唯一真相源
- `[chore]` **`tests/` → `test/`**：17 份夹具迁入，22 处路径同步改写
- `[chore]` **删除 4 份一次性过程文档**：acceptance / wrap-up-plan / stub-audit / eval 日期快照
- `[chore]` **删除 `codemaps/`**（26 份代码地形索引，与 .qoder/repowiki 重复）

### 2026-09-21  2026-09 收尾（wrap-up T1–T13）

- `[feat]` **`cmd eval --offline`**：工具白名单 + 沙箱 + 断言原语 + 评分 JSON，3 任务 × 2 重复
- `[feat]` **压缩→Summary 端到端** + **TUI 路径会话日志 flush**
- `[feat]` **`scripts/repo_stats.sh`**：数字单一事实来源 + CI 闸门
- `[fix]` **版本对齐** 0.1.3→0.2.0 + **真话卫生**（README 会话兼容性表述修正）
- `[fix]` **两处跨平台测试夹具**：`/proc` 断言改为双平台可复现构造

### 2026-08-23  stubfix 批次（01-08）全部实施完成

- `[feat]` **stubfix-05~08**：调度器持久化、Telegram 真发送、WsClient + Discord 网关、四基础设施模块真实现
- `[fix]` **对抗性审查修复 8 项 C 级 + 12 项 W 级缺陷**：错误传播/Int64 溢出/心跳/孤儿接线/backup 三连假成功等
- `[test]` 23 个新 wbtest（调度器 10/backup 5/discord 4/output_dir 4）
- `[docs]` stubfix 9 份 spec 全部归档至 specs/completed/

### 2026-08-21  编译告警清零 + 28 份 P5/P6 spec 归档

- `[fix]` **编译告警清零**（4 个 unreachable_code）：`moon check` 0 errors / 0 warnings
- `[docs]` **28 份 spec 全部归档**：16 份 P5 BUG 修复 + 12 份 P6 矩阵残留簇
- `[docs]` **文档指标校准**：源文件 299 / 测试 197 / 用例 3,843 / REST 218 端点

### 2026-08-05  TUI 渲染层再重构 + 全面对齐原版

- `[refactor]` **TUI 废弃 mizchi/tui VNode 渲染**，改为自研行级重绘 + 前缀 diff
- `[feat]` **TUI 全面对齐原版**：状态栏置底、无框输入区、todo 自动显隐、命令语义对齐
- `[feat]` **技能发现对齐原版**：5 条发现路径，同名后者覆盖
- `[fix]` **CI/Docker 构建修复**：补提交未提交的 Agent 方法及测试

### 2026-08-03  Web UI 7 项修复 + 4 项 spec + 复测 4 项

- `[fix]` **Web UI 修复**：历史消息重复、头像路由、模型选择丢失、错误路径持久化等
- `[feat]` **4 项 spec 归档**：Windows 构建断链、模型标识统一、历史分页游标化、目录选择器
- `[fix]` **复测根因修复**：`replace`→`replace_all`、默认模型双概念统一、占位会话名自动重命名

### 2026-07-29  Agent 增量规格 + 文档整理

- `[feat]` **agent-01~08 规格全部实现**：session context 注入、reasoning_content 透传、压缩阈值配置化、空闲压缩定时器、skill evolution hooks
- `[docs]` **docs/ 删减合并**：删除 7 份过时文档，新增 tui-architecture.md

### 2026-07-28  TUI mizchi 基础迁移 + parity 修复

- `[refactor]` **TUI 渲染层迁移至 mizchi/tui VNode**（Phase 1-4）
- `[feat]` **tui-parity-01~08 规格实施**：状态栏、斜杠命令、banner、输入区、窄屏自适应

### 2026-07-27  gap 分析 18 项差距全部实现

- `[feat]` **gap 分析规格全部实现**：MCP 配置加载 + HTTP transport、Time Machine 接入、WebSocket 流式推送、LLM 重试/fallback 统一化

### 2026-07-26  web-ui2 规格实施 + 告警清零

- `[feat]` **web-ui2-04~10 规格实施**：Skills YAML 解析、Channels 字段、Agents 本地化、汇率格式化、Dirs 路径、Session 契约、Response 清理
- `[fix]` **moon check 告警清零**：~500 warnings→0（supported_targets + E0020 弃用）

### 2026-07-25  FFI C 依赖消减（S-FFI-01~08）

- `[refactor]` **自写 C 代码 16 文件/4,781 行→5 文件/610 行**；`-lcurl` 全项目清零
  - HTTP→`@async/http`、进程→`@async/process`、PTY→`moonbit-community/pty`、ZIP→纯 MoonBit
  - 保留 5 个 C 文件（OS 生态空白/安全审计理由）

### 2026-07-16  端口统一 + 文档全量校准

- `[chore]` **默认端口 7070→7071**（与原版 OpenClacky 区分）
- `[docs]` **核心指标全量同步**：源文件 309 / 测试 103 / REST ~154 / 完成度 ~95%
- `[docs]` **Web 前端托管 fork**：上游 87 文件导入 + 87 管理面板 + i18n 692 key

### 2026-07-15  i18n 翻译补齐

- `[feat]` **i18n 翻译补齐**：692 keys，覆盖率 99.4%，中英文对称 100%
- `[docs]` Spec 归档 + 4 个 i18n 维护工具脚本

### 2026-07-13  文档指标同步 + 合并废弃文档

- `[docs]` **指标同步**：源文件 258 / 测试 73 / 技能 16 / warnings ~522
- `[docs]` **合并删除 2 个过时文档**：brand-crypto-migration→并入 getting-started、gap_analysis→并入 project-status

### 2026-07-12  Spec 归档与文档同步

- `[docs]` **3 份 spec 归档**：wasm-gc 可行性（暂缓）、web-api-contract（6 端点实现）、priority-analysis
- `[docs]` **project-status 同步**：移除已过时已知问题，更新模块完成度

### 2026-07-08  文档合并精简

- `[docs]` **docs/ 精简 10→3 个文档**：删除 5 个过时文档 + 归档 2 个到 specs/
- `[docs]` **文档职责分工确定**：README（介绍）→ getting-started（入门）→ project-status（状态）→ CLAUDE.md（架构速查）→ AGENTS.md（开发规范）→ CHANGELOG（变更历史）

### 2026-07-07  浏览器工具完善 + Web 管理面板后端全量实现

- `[feat]` **浏览器工具**：scroll 原生回退、fill focus/blur 增强、escape_js_string、截图参数透传、快照阈值门控
- `[feat]` **Web 8 个管理面板后端全量实现**：Trash/Git/MCP/Schedules/Channels/Backup/Billing/Browser，72 handler，2,741 行，零 stub

### 2026-07-06  CI/CD + Harness 方法论 + Codemaps

- `[chore]` **GitHub Actions CI**：`moon check` + `moon build` + `moon test` 自动触发
- `[chore]` **Docker 镜像自动构建** + **Harness 方法论落地**（specs/ 目录结构）
- `[docs]` **Codemaps 代码地形索引**（10 个核心包）

### 2026-07-03  功能扩展

- `[feat]` **Terminal PTY 执行** + **Web API 扩展**（汇率/图片/媒体/OCR/onboard/版本，90+ 端点）
- `[feat]` **MCP 技能提供方** + **TUI 视觉增强**（大字体/思考动词）
- `[feat]` **默认技能 11→16 个**

### 2026-07-01  Eval 框架重构 + Browser 拆分 + TUI 布局修复

- `[refactor]` **Eval 框架提取到 `test/`**：三层架构（通用引擎→适配层→场景定义）
- `[refactor]` **Browser 模块拆为 5 文件** + **Vision OCR** + **PDF OCR 回退**
- `[fix]` **TUI 布局修复**：Yoga 空桩根因定位 + 根布局约束 + 状态栏重构至底部
- `[feat]` **安装脚本增强**：自动安装 MoonBit / 版本解析 / 中国镜像

### 2026-06-30  部署阻碍修复 + Ruby→MoonBit 架构重构总结

- `[fix]` **P0/P1 测试失败全修复**：1,341/1,341 通过（AES-GCM FFI / session_registry / mcp types / static_server）
- `[fix]` **C FFI 链接修复**（moon #1488 + #1595）+ **Dockerfile 重写** + **端口统一 7070**
- `[refactor]` **Ruby→MoonBit 架构重构总结**：27 包 / Checked Error / Option / struct+trait / AOT / Hook / AnyAdapter / GEP
- `[docs]` **模块对齐表**：18 模块已超越 Ruby 原版，4 模块待改进

### 2026-06-30  Native 编译修复 + TUI Windows 渲染修复

- `[fix]` **Windows MSVC 兼容**：移除全局链接标志 / MB_WEAK 宏 / MSVC 条件编译 / vswhere 检测
- `[fix]` **TUI Windows 渲染**：VT Processing 时序 / C stub 签名 / 行尾清除 / TextBuffer FFI / GetProcAddress

### 2026-06-26  Phase 22 差距填补 + Phase 21 业务功能补齐

- `[feat]` **Phase 22**：Web 安全/广播基础设施 / 浏览器增强 / AES-GCM C FFI / TUI 控制器增强
- `[feat]` **Phase 21**：Terminal 核心 / 消息压缩 / Session 增强 / Agent 配置 / Brand 配置 / TUI 基础 / Web 前端 / CLI 入口
- `[perf]` 编译警告 672→276

### 2026-06-25  Phase 20 文档校准

- `[docs]` **全量文档校准**：修正源文件/测试/行数/用例数/警告数，修复 CLAUDE.md 重复 bug

### 2026-06-23  Phase 19 文档校准 + Phase 18 深度补齐

- `[docs]` **Phase 19**：全量文档校准，CLAUDE.md 全面重写
- `[feat]` **Phase 18**：计费系统 / 模型定价 / 平台 HTTP / 服务器增强 / Utils 扩展 / 消息历史 / Agent 增强 / 默认资源
- `[test]` 测试用例 507→969

### 2026-06-17  Phase 12-17 全量实现

- `[feat]` **Phase 12**：MCP 协议（9 文件）+ 技能进化（4 文件）
- `[feat]` **Phase 13**：Time Machine + Agent Profile + Idle Timer + Workspace Rules + TUI 增强
- `[feat]` **Phase 14**：Web 前端 SPA（8 文件）+ REST API 扩展（68+ 端点）
- `[feat]` **Phase 15**：多模态（parser/media/vision 三包）
- `[feat]` **Phase 16**：运维集成（cron/scheduler/browser_manager/backup/discover）
- `[feat]` **Phase 17**：IM 渠道（6 平台）+ Brand/License + Shell Hook + Telemetry
- `[test]` 507 测试全通过

### 2026-06-17  Phase 11 核心补齐

- `[feat]` Bedrock Converse API + Provider 6→12 个 + 3 新工具（总数 11→14）+ 201 测试

### 2026-05-23  Phase 2-10 核心框架搭建

> 项目创建当日完成 Phase 0-10 全部实现。

- **Phase 2**: LLM 客户端（OpenAI/Anthropic + SSE）
- **Phase 3**: 工具系统（10 模块 + ToolRegistry）
- **Phase 4**: Agent 核心（ReAct + Fallback + 成本 + 压缩）
- **Phase 5**: CLI 入口
- **Phase 6**: 会话持久化
- **Phase 7**: TUI + Hook 事件系统
- **Phase 8**: Web 服务器（20+ 端点 + SSE + WebSocket）
- **Phase 9**: 技能系统
- **Phase 10**: Agent 增强（Memory/SubAgent/Todo）
- 测试用例：0→466