# 官方评审反馈核查报告（2026-09-23）

> 核查对象：MoonBit 国产开源生态大赛官方历次评审反馈（20260820 / 20260717 / 20260707）中所列问题。
> 核查基线：`main@ad1e281`（= origin/main，工作区干净），工具链 `moon 0.1.20260921 (e46d2ed 2026-09-21)`。
> 核查方式：源码审查 + 本机命令实测 + mooncakes.io / GitHub Actions 在线核查。所有结论均附文件路径、行号或实际命令输出。

---

## 一、概述

三次反馈共涉及 17 条具体问题（含重复点名项），本次逐条核查后结论分布：

| 结论 | 数量 | 说明 |
|---|---|---|
| 已修复 | 13 | 有本机实测或在线证据支撑 |
| 部分修复 | 2 | SQLite 申报口径、渠道接收侧残留（均已如实登记） |
| 无法判定 | 2 | 最新提交 ad1e281 的 GitHub Actions 当次结论（in progress）；0.1.3 与 0.2.0 差异逐项比对 |
| 仍存在（低优先） | 2 | mooncakes 版本落差（0.2.0 未发布）；test/e2e 时序断言负载敏感（本次新发现） |

核心判断：**反馈中反复点名的"不能构建/测试/运行、CI 失败、stub 未清零、许可缺失、包未发布"等阻塞性问题均已修复并有实测证据**；剩余问题集中在"发布节奏、申报口径确认、已知范围外功能（渠道接收侧）"，均已在 `docs/known-gaps.md` 真话台账中如实登记。

---

## 二、核查结论总表

### 20260820 批次（正式验收未通过）

| # | 官方指出问题 | 结论 | 关键证据 |
|---|---|---|---|
| 1 | 成本已实装（保持确认） | ✅ 已实装（维持） | `lib/pricing/cost_calculator.mbt:58-120` 完整实现；`model_pricing.mbt` 683 行定价表 |
| 2 | 渠道发送仍 stub | ✅ 已修复 | 6 平台 send 全部真实 HTTP：`lib/channel/{feishu,wecom,weixin,telegram,discord,dingtalk}.mbt`；git: `bdc9272`/`c16f2c7`（WP-1.1~1.4） |
| 3 | Discord 网关仍 stub | ✅ 已修复 | `lib/channel/discord_gateway.mbt`（435 行）：Hello/Identify/心跳/Resume/退避重连全生命周期；git: `075af9f`（stubfix-05~08） |
| 4 | MCP stdio 仍 stub | ✅ 已修复 | `lib/mcp/stdio_transport.mbt`（562 行）：真实子进程 spawn + JSON-RPC 请求/响应关联；含 python3 真实子进程集成测试；git: `07d83f0` |
| 5 | 办公文档解析仍 stub | ✅ 已修复 | `lib/parser/` 重写为 MoonBitMark 引擎适配层（`moonbitmark_adapter.mbt:52-82` 真实调用 `MarkItDown::convert`）；六个 stub parser 已删除；git: `fb3649e` |

### 20260717 批次（验收未通过）

| # | 官方指出问题 | 结论 | 关键证据 |
|---|---|---|---|
| 1 | 快照不能构建 | ✅ 已修复 | `moon build --target native --release cmd` → "ran 77 tasks, now up to date"，产物 `cmd.exe` 8.69 MB（2026-09-23 21:01） |
| 2 | 不能测试 | ✅ 已修复 | 本机全量（lib+cmd+test，含 lib/mcp）：**Total tests: 4077, passed: 4077, failed: 0** |
| 3 | 不能运行 | ✅ 已修复 | `moon run cmd -- --version` → `MBOpenClacky v0.2.0`，EXIT=0；`selftest` 20/20 |
| 4 | CI 没有成功证据 | ✅ 已修复 | CI badge = **passing**、Docker badge = **passing**（在线实测）；历史红因 `50d365d` 修复 |
| 5 | 申报的 SQLite 持久化未实现 | ⚠️ 部分修复（口径已改） | 代码中仍无 SQLite；README `:66-79` 已转为**架构决策章节**（选择 JSON 文件方案，含对比与理由）。详见 §3.2.5 |
| 6 | 成本计算仍为占位 | ✅ 已修复 | 同 20260820#1 |
| 7 | 部分渠道仍为占位逻辑 | ⚠️ 大部分修复 | send/编辑/撤回已全部接线；接收侧 3 处（Telegram getUpdates、企微 WS、钉钉 Stream）为**诚实报错 stub**，已登记 `known-gaps.md:204` 等。详见 §3.2.7 |
| 8 | 部分扩展仍为占位逻辑 | ✅ 基本修复 | `lib/extension/` 16 文件、约 3800 行真实实现；唯一 MVP 限制 `verifier.mbt:159`（依赖自动解析仅警告）已登记台账 |
| 9 | 精确包名未发布到 mooncakes.io | ✅ 已修复 | `hnlyxiaobing/MBOpenClacky` 可查询，已发布 0.1.0~0.1.3；⚠️ 注意 0.2.0 尚未发布（见 §四） |
| 10 | 修复缺失 C 文件与 native 头文件 | ✅ 已修复 | 全部 8 个 native-stub C 文件与声明一一对应（见 §3.3.3）；`stdlib.h`/OpenSSL 均已就位 |
| 11 | README 命令及 CI 全部通过 | ✅ 已修复 | README 中 build/run/selftest/eval/journey 命令逐条实测通过；CI 双 badge 绿 |
| 12 | 补齐 marked/highlight 第三方许可与来源说明 | ✅ 已修复 | `THIRD_PARTY_LICENSES.md:9-10`；vendor 文件保留版权头（hljs v11.11.1 BSD-3-Clause / marked v18.0.5 MIT） |

### 20260707 批次（预验收）

| # | 官方指出问题 | 结论 | 关键证据 |
|---|---|---|---|
| 1 | `moon test` 失败 | ✅ 已修复 | 4077/4077 通过（本机）；CI 绿 |
| 2 | 运行入口失败（`moon run cmd -- --version` 不能正常运行） | ✅ 已修复 | 实测输出 `MBOpenClacky v0.2.0`，EXIT=0 |
| 3 | native 构建因 C 代码缺 `stdlib.h` 失败 | ✅ 已修复 | 8 个 C 文件齐全且构建通过；`browser_popen.c:15` 等 `#include <stdlib.h>` 在列 |
| 4 | OpenSSL/架构链接问题 | ✅ 已修复 | `scripts/build-script.js:25-38` 平台分流：Windows 用 BCrypt 自动链接（`ff9ab4b`）、Linux/macOS 注入 `-lcrypto`；`lib/brand/moon.pkg:16-26` 与 `cmd/moon.pkg:38-46` 注释完整 |
| 5 | GitHub Actions 最近均为失败 | ✅ 已修复 | CI/Docker 双 badge passing；失败根因（裸 `moon test` 连带 vendor/mbtpdf）已由 `50d365d` 修复并复验 |
| 6 | Linux CI 缺少 `curl/curl.h` 所需开发依赖 | ✅ 已修复 | 全仓无 `curl/curl.h` 引用；libcurl 已整体移除（git: `aa1b3e0` "drop libcurl build and runtime dependency"）；HTTP 走纯 MoonBit `@async/http`（`THIRD_PARTY_LICENSES.md:22`） |
| 7 | 发布到 mooncakes.io | ✅ 已修复 | 见 20260717#9 |
| 8 | 确保 `hnlyxiaobing/MBOpenClacky` 可查询 | ✅ 已修复 | https://mooncakes.io/docs/hnlyxiaobing/MBOpenClacky 在线可访问 |

---

## 三、逐条详述与证据

### 3.1 20260820 批次详述

#### 3.1.1 渠道发送实装

六个平台适配器均已接入真实 HTTP 传输（非 stub）：

- `lib/channel/feishu_api.mbt`（576 行）、`feishu.mbt`（480 行）：send/update(PATCH)/upload(multipart)/download/history 全链路（WP-1.1，git `c16f2c7`）
- `lib/channel/wecom.mbt`（673 行）+ `wecom_api.mbt`（182 行）：gettoken 缓存 + message/send，`errcode!=0` 一律报错（WP-1.3，git `bdc9272`）
- `lib/channel/weixin.mbt`（874 行）+ `weixin_api.mbt`（508 行）：AES-128-ECB/PKCS#7 + iLink sendmessage（WP-1.4，git `bdc9272`）
- `lib/channel/telegram.mbt:272-285`：send_text 经 `http_post_json` 真实发送
- `lib/channel/dingtalk.mbt`（691 行）+ `dingtalk_api.mbt`（466 行）：双 token 缓存 + open_stream_connection/download_file_url（WP-1.2）
- `lib/channel/discord_api.mbt`：编辑/撤回/取用户/multipart 上传/CDN 下载全部真实 REST（WP-1.6，git `1087269`）

反假成功契约有测试把守：`lib/channel/channel_wbtest.mbt:2050-2112` 的 "False-success gate" 断言任何未接线端点必须报真实传输错误（`assert_false(msg.contains("not implemented"))`）。台账对 6 平台 40+ 行 stub 标记逐一转 `fixed`（`docs/known-gaps.md:179-218`）。

#### 3.1.2 Discord 网关实装

`lib/channel/discord_gateway.mbt:1-15` 头部声明并实现完整 Gateway v10 生命周期：

```
/// Connect -> Hello (op 10) -> Identify (op 2) -> Heartbeat loop (op 1/11)
/// -> Dispatch events (op 0) -> Resume on disconnect (op 6)
```

特性：自动心跳（含 jitter）、会话断线恢复（Resume）、致命关闭码检测（不再重连）、重连失败指数退避。配套 `ws_client.mbt`（WebSocket 薄封装，`@async.websocket` 零新增依赖）与 `discord_wbtest.mbt`（ISO8601 时区表驱动、溢出回归）。

#### 3.1.3 MCP stdio 实装

`lib/mcp/stdio_transport.mbt`（562 行，native 主体）+ `task_group.mbt`（MCP 读循环的常驻 TaskGroup 基础设施）：

- 真实子进程 spawn、行级 JSON-RPC 分发、请求/响应 id 关联、超时与并发乱序应答
- `stdio_transport_wbtest.mbt:105-116` 提供"真实 python3 子进程"集成测试（initialize 握手、tools/list、tools/call、-32601、超时、双重 stop、并发乱序）
- 文件内 518-550 行的 `stub` 字样均为 **WASM 目标回退**（`/// (WASM stub - process spawning not supported)`），native 路径为真实实现；台账标注 `范围外（wasm）`（`known-gaps.md:224-229`）
- 附加：HTTP 传输也已接线（WP-3.3，`http_transport.mbt` 439 行，git `109e3b8`），实现 Streamable HTTP/SSE 与会话头回带

#### 3.1.4 办公文档解析实装

`lib/parser/` 已从脚手架重写为 MoonBitMark 引擎薄适配层（git `fb3649e` "rewrite lib/parser as thin MoonBitMark adapter, delete six stub parsers"）：

- `parser_manager.mbt:2-9` 注释确认"删除全部六个 XxxParser 文件"
- `moonbitmark_adapter.mbt:52-82`：白名单六格式（.pdf/.docx/.pptx/.xlsx/.doc/.wps）→ `engine.convert(path)` 真实转换 → `ParseResult` 映射（含 1MB 截断护栏）
- `.et/.dps` 诚实报错（决策 9，`moonbitmark_adapter.mbt:20-21`），不伪装支持
- 验收测试：`parser_wbtest.mbt`（361 行，含六格式管线、错误路径、.et/.dps 拒绝）

### 3.2 20260717 批次详述

#### 3.2.1~3.2.4 构建 / 测试 / 运行 / CI

见 §二总表与 §附录命令记录。补充说明：

- 类型检查：`moon check -d` 本机复验通过（touch `cmd/main.mbt` 强制重检后 "ran 3 tasks, now up to date"，无 error/warning 输出）；CI 的 `Type check` 与 `Warning budget gate` 步骤在绿 badge 运行中通过（`.github/workflows/ci.yml:57-61`）
- 测试口径说明：本机全量 4077 = CI 一步口径 3981（`README.md:26` 机器生成表）+ `lib/mcp` 96（CI 第二步单独跑，`.github/workflows/ci.yml:144-156`），数字吻合
- 运行证据链：`--version` → `selftest` 20/20（"native vs moon run differences: none"）→ `eval --offline` 16/16 断言、可重复性 1.0 → `journey` 13/13（2026-09-23 20:58 运行报告，真实二进制驱动 Web/TUI/CLI/持久化全链路）

#### 3.2.5 SQLite 持久化（部分修复：以架构决策替代实现）

事实核查：

- 全仓 grep（`*.mbt`）"sqlite" 仅 3 处命中，均为**非实现代码**：`lib/tool/tool_wbtest.mbt:39`（选项文本测试）与 `lib/tool/glob.mbt:323-324`（二进制扩展名过滤列表）
- `moon.mod` 无任何 SQLite 依赖；无 sqlite3 C stub
- 会话持久化实际为 **JSON 文件方案**（含 2026-09-22 WP-3.1 的旧格式只读迁移投影、JSONL 事件流）

申报口径变化：

- `README.md:66-79` 现有专节「架构决策：会话持久化：JSON 文件 vs SQLite」，六维对比表 + 结论"JSON 文件方案…是更合适的选择"，并如实标注限制（"上游 openclacky 原始会话文件样本不在手，未做端到端比对"）
- mooncakes.io 上 0.1.3 的 README 同样包含该章节（在线可见）

**结论**：SQLite 未实现的事实未变；项目已将其转为公开的架构决策并如实说明。**若官方验收口径仍要求 SQLite 本体，此项未满足**——需与官方确认以 JSON 决策替代是否可接受；建议在申报材料中同步该口径。

#### 3.2.6 成本计算

`lib/pricing/cost_calculator.mbt:58-120` `calculate_cost`：模型定价查找（`get_pricing`）→ 超阈值分层（`context_threshold`）→ 输入/输出/cache 写/cache 读四项成本分别计算 → `CostResult` 明细；`model_pricing.mbt` 683 行价格表（含 `pricing_wbtest.mbt` 227 行测试）。非占位。

#### 3.2.7 部分渠道占位（大部分修复）

现状矩阵（`docs/project-status.md:194-205` 按代码核对）：

| 平台 | 发送 | 编辑/撤回 | 接收 | 说明 |
|---|---|---|---|---|
| Telegram | ✅ | ✅ | ❌ 未接线 | `telegram.mbt:250` 长轮询 TODO 如实保留 |
| Discord | ✅ | ✅ | ✅ 网关 | 心跳/Resume 已接线 |
| 飞书 | ✅ | ✅ | ✅ webhook | |

- **发送侧：修复**（见 §3.1.1）
- **接收侧残留 3 处**：Telegram `getUpdates` 长轮询、企微 WebSocket、钉钉 Stream Mode —— 均为**诚实报错 stub（不静默假成功）**，已登记为范围外：`known-gaps.md:204`、`improvement-execution-plan.md:114-118`、`improvement-roadmap.md:74-76`（已列下一步排序第 1 项）

#### 3.2.8 部分扩展占位（基本修复）

`lib/extension/` 真实实现：loader（406 行）/ marketplace（586 行）/ scaffold（433 行）/ verifier（219 行）/ packager（181 行）/ patch_loader（123 行）。唯一 MVP 限制：`verifier.mbt:159` 依赖自动解析未实现（仅警告），已登记台账（`known-gaps.md:220`）。

#### 3.2.9~3.2.12 mooncakes 发布 / C 文件 / README 命令 / 许可

- mooncakes：见 §3.3.7；补充——本地 `moon.mod:1,3` 名称为 `hnlyxiaobing/MBOpenClacky`、版本 0.2.0，与 registry 包名一致；⚠️ registry 最新仍为 0.1.3
- C 文件与头文件：见 §3.3.3
- README 命令：build/run/selftest/inspect/eval/journey/benchmark 实测通过（见 §附录）；测试命令口径注记见 §四 P3-1
- 许可：`THIRD_PARTY_LICENSES.md:5-13` 的 "Web UI Libraries (`web/vendor/`)" 表列出 highlight.js (BSD-3-Clause) 与 marked.js (MIT) 及目录；vendor 文件头保留完整版权声明（`highlight.min.js:1-5`：v11.11.1、(c) 2006-2024 Josh Goebel、BSD-3-Clause；`marked.min.js:2-5`：v18.0.5、(c) 2018-2026 MarkedJS、MIT、附 GitHub URL）；根 NOTICE 另有依赖全表与设计来源说明。`web/index.html:1554-1563` 确认两库为真实加载项

### 3.3 20260707 批次详述

#### 3.3.1 / 3.3.2 moon test 与运行入口

- `moon test`（本机、debug、无并行负载）全量 4077/4077，EXIT=0（见 §附录 A-6）
- `moon run cmd -- --version` → `MBOpenClacky v0.2.0`，EXIT=0（§附录 A-5）——这正是反馈点名的命令

#### 3.3.3 C 文件与 native 头文件

native-stub 声明与文件存在性全量核对（`moon.pkg` 6 处声明 ↔ Glob 8 个 `.c` 文件，一一对应）：

| 包 | 声明文件 | 存在 |
|---|---|---|
| lib/utils | sys_native.c | ✅（140 行，含 `#include <stdlib.h>` :12） |
| lib/brand | crypto_native.c, brand_stubs.c | ✅（222 + 146 行） |
| lib/agent | time_stub.c | ✅（44 行） |
| lib/tui | console_cp_native.c | ✅（58 行） |
| lib/billing | billing_time_stub.c | ✅（46 行） |
| lib/tool | stat_native.c, browser_popen.c | ✅（97 + 91 行，均含 `<stdlib.h>`） |

#### 3.3.4 OpenSSL / 架构链接

`scripts/build-script.js:25-38`（moon.mod prebuild 入口）对链接做平台分流：

```
Windows：不注入 -lcrypto（BCrypt 由 crypto_native.c 的 #pragma comment 自动链接；
         注入会 LNK1181），输出空 link_configs
Linux/macOS：为 cmd、lib/brand、lib/web 注入 link_libs: ['crypto']
```

git 佐证：`ff9ab4b fix(build): skip -lcrypto on Windows, rely on BCrypt auto-link`。Docker 构建阶段安装 `libssl-dev`（`Dockerfile:26`），运行阶段安装 `libssl3`（`Dockerfile:108`）。

#### 3.3.5 GitHub Actions

在线核查（2026-09-23）：

- `https://github.com/hnlyxiaobing/MBOpenClacky/actions/workflows/ci.yml/badge.svg` → `<title>CI - passing</title>`
- `.../docker.yml/badge.svg` → `<title>Docker - passing</title>`
- Actions 页面共 333 次运行记录；历史失败根因（裸 `moon test` 连带执行 `vendor/mbtpdf` 自带测试触发 ICE）已由 git `50d365d` 修复、`30649f0` 记录复验；Docker 失败根因（产物路径两处写错）已由 `020ec26`/`7770730` 修复
- ⚠️ 最新提交 `ad1e281` 的 CI #166 / Docker #166 抓取时状态 **In progress**——当次结论无法判定（不影响历史全绿的判断）

#### 3.3.6 curl/curl.h 开发依赖

- 全仓 grep `curl/curl.h`：**0 命中**
- git 历史显示该问题存在过并已被移除：`ebf87d6`（当时安装 libcurl dev deps）→ `7f66e4e`（加 curl link flag）→ `04630e6`（C stubs 换成 MoonBit/async）→ **`aa1b3e0 chore(ci): drop libcurl build and runtime dependency`（根治）**
- 现 HTTP 传输为纯 MoonBit（`moonbitlang/async/http`），`THIRD_PARTY_LICENSES.md:22` 明示 "libcurl/WinHTTP are no longer used"
- 当前 `.github/workflows/ci.yml:19-21` 不再安装任何 apt 包（注释说明 ubuntu-22.04 runner 预装 build-essential 与 libssl-dev）；唯一用到 `curl` 命令的是下载工具链脚本（:35）与 Docker 健康检查（`Dockerfile:134`），均为系统自带命令而非开发头文件

#### 3.3.7 mooncakes.io 发布

在线核查（2026-09-23）：

- 包页 https://mooncakes.io/docs/hnlyxiaobing/MBOpenClacky 可访问，`hnlyxiaobing/MBOpenClacky` **可查询**
- 已发布版本：0.1.0 / 0.1.1 / 0.1.2 / **0.1.3 (latest)**，last updated 26 days ago（对应 git `c4b3fa4 chore(release): v0.1.3`，2026-08-28）
- 包元数据正常（MIT、仓库链接、依赖 11 项、下载 24 次）
- ⚠️ **版本落差**：本地 `moon.mod:3` 已是 0.2.0（git `v0.2.0` tag 存在），registry 最新仍为 0.1.3——0.2.0 尚未发布到 mooncakes.io

### 3.4 特别关注方向专项核查汇总

| 方向 | 结论 | 一句话证据 |
|---|---|---|
| 构建可用（缺失 C 文件、native 头文件） | ✅ | 8 C 文件齐全；`moon build` 77 tasks 成功产出 8.69 MB 二进制 |
| OpenSSL 及架构链接 | ✅ | build-script.js 平台分流；Windows 二进制实测运行 |
| `moon run cmd -- --version` | ✅ | `MBOpenClacky v0.2.0`，EXIT=0 |
| `moon test` 与运行入口 | ✅ | 4077/4077；selftest 20/20 |
| GitHub Actions / Linux CI curl.h | ✅ | 双 badge passing；libcurl 已整体移除 |
| mooncakes.io / 包名可查询 | ✅（附落差） | 0.1.0~0.1.3 已发布可查询；0.2.0 未发布 |
| SQLite 持久化 | ⚠️ | 无 SQLite；已转为 README 架构决策（JSON 方案） |
| 成本计算 | ✅ | cost_calculator.mbt 完整实现 + 定价表 |
| 渠道发送 | ✅ | 6 平台真实 HTTP + 反假成功测试把守 |
| Discord 网关 | ✅ | discord_gateway.mbt 完整生命周期 |
| MCP stdio | ✅ | 真实子进程 + python3 集成测试（WASM 回退除外） |
| 办公文档解析 | ✅ | MoonBitMark 引擎适配（六 stub parser 已删除） |
| 部分渠道/扩展占位 | ⚠️（范围外残留） | 渠道接收侧 3 处诚实 stub；扩展仅 1 处 MVP 限制 |
| marked/highlight 许可与来源 | ✅ | THIRD_PARTY_LICENSES.md + vendor 版权头 + NOTICE |

---

## 四、仍存在问题的清单与优先级

| 优先级 | 问题 | 影响 | 建议修复方向 |
|---|---|---|---|
| **P1** | **mooncakes.io 版本落差**：registry 最新 0.1.3，本地已 0.2.0（26 天未发布） | 评审如果安装最新发布包看到的是旧快照，可能重复此前判定 | 在下一批改动冻结后执行 `moon publish` 发布 0.2.0（或更新版本号再发）；发布前跑 `moon check -d` + 全量测试 + `repo_stats.sh check` |
| **P1** | **SQLite 申报口径待确认**：代码无 SQLite，README 已改 JSON 架构决策 | 若官方验收硬性要求 SQLite 本体则仍不满足；若是申报材料口径问题则已澄清 | 与官方确认"JSON 文件持久化决策"是否可接受；若必须 SQLite，需先立 spec（MoonBit 侧需 sqlite3 C FFI 或纯 MoonBit 实现，属大工程） |
| **P2** | **渠道接收侧 3 处未接线**：Telegram `getUpdates` 长轮询（`telegram.mbt:250`）、企微 WebSocket、钉钉 Stream Mode | "6 平台 IM 渠道"的接收能力不完整；目前均为诚实报错（不假成功） | 按 `improvement-roadmap.md:74-76` 排序执行：复用 WP-1.1~1.4 的 mock-TCP 验证模式与 `ChannelManager` 单一真相源；Telegram 长轮询最简单（HTTP 轮询），建议先做 |
| **P2** | **cmd/cli_mcp.mbt 的"MCP server 暴露"未接线**（`known-gaps.md:154-157`）：仅支持作为 MCP client，不支持被其他编辑器以 stdio 方式调用本项目 | 对外集成面缺失（不影响内部 MCP client 功能） | 依赖子进程 FFI 能力（MoonBit AOT 约束），需 spec 评估；可作为 P2 独立工作包 |
| **P3** | **test/e2e 退避断言负载敏感**（本次新发现）：`test/e2e/scenarios_wbtest.mbt:54-63` 墙钟窗口 [2000, 20000]ms，重负载下实测 22768ms 越界致测试进程崩溃（0xc0000409）；单独重跑 14/14 通过 | 高负载机器/CI 上可能偶发假红（本次即复现 1 次）；不影响产品功能 | 建议：① 窗口上限放宽到 30s；② 或将退避断言改为可注入时钟的确定性测试（`lib/agent/llm_caller_wbtest.mbt` 已有固定 5s 的单元级断言，层面 3 场景断言可降级为诊断输出） |
| **P3** | **README 测试命令注释滞后**：`README.md:140-144` 仍写"统一 --release：debug 模式受编译器 ICE 影响"，而 CI 已改为 scoped debug 模式（`.github/workflows/ci.yml:144-156`），AGENTS.md 亦说明 debug 可用且更快 | 文档与 CI 行为不一致（不影响功能） | 更新 README 注释与命令示例，与 AGENTS.md/CI 口径对齐 |
| **P3** | **known-gaps 其余范围外 open 项**（约 60 条扫描命中中的 open 子集）：品牌服务端 HTTP（license/心跳/技能商店）、telemetry HTTP、web 备份 ZIP 打包、任务快照 diff/restore_preview、远程扩展下载、worker 重启、trash stub 语义、TUI 主题检测、browser 运维 FFI、wasm 回退 stub 等 | 均为已文档化、有意保留的范围外项；不影响核心验收功能 | 按 `docs/improvement-roadmap.md` 与 `docs/improvement-execution-plan.md` 现有排序择机处理；建议先做 P2 两项 |

---

## 五、结论

1. **阻塞级问题已全部消除**。三次反馈中直接导致验收失败的构建/测试/运行/CI/发布/许可六类问题，本次均有本机实测或在线证据证明已修复：native 构建成功、全量测试 4077/4077、`moon run cmd -- --version` 正常、CI 与 Docker 双 badge passing、包名在 mooncakes.io 可查询、marked/highlight 许可与来源说明齐全。

2. **20260820 反馈点名的四个"仍 stub"项已全部实装**：渠道发送（6 平台真实 HTTP）、Discord 网关（完整生命周期）、MCP stdio（真实子进程，附 python3 集成测试）、办公文档解析（MoonBitMark 引擎适配，六个 stub parser 已删除）。反假成功契约有专门测试把守（`channel_wbtest.mbt:2050+`）。

3. **两项"部分修复"均为已如实登记的诚实缺口**（SQLite 转架构决策、渠道接收侧 3 处诚实 stub），不存在静默假成功；`docs/known-gaps.md` 真话台账（86 条扫描命中 / 160 条 curated 行，CI 校验）使缺口状态可机器复核。

4. **新增发现 2 项低风险问题**（mooncakes 0.2.0 未发布、test/e2e 时序断言负载敏感）与若干文档口径小差异，修复成本低，建议纳入下一批收尾提交。

5. **送审前建议动作**：① 发布 0.2.0 至 mooncakes.io；② 与官方确认 SQLite 口径；③（可选）按 P2 推进渠道接收侧接线以彻底关闭"6 平台渠道"的能力落差。

---

## 附录 A：本次核查执行的命令与输出摘要

| # | 命令 | 结果 |
|---|---|---|
| A-1 | `moon version` | `moon 0.1.20260921 (e46d2ed 2026-09-21)` |
| A-2 | `moon check -d`（缓存命中） | `Finished. moon: no work to do` |
| A-3 | `moon check -d`（touch `cmd/main.mbt` 强制重检） | `Finished. moon: ran 3 tasks, now up to date`，无 error/warning 输出 |
| A-4 | `moon build --target native --release cmd` | `Finished. moon: ran 77 tasks, now up to date`；产物 `_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe`（8.69 MB，2026-09-23 21:01） |
| A-5 | `moon run cmd -- --version` | `MBOpenClacky v0.2.0`，EXIT=0 |
| A-6 | 全量 `moon test`（debug；`lib`+`cmd`+`test` 全部 `moon.pkg`，含 `lib/mcp`） | `Total tests: 4077, passed: 4077, failed: 0`，EXIT=0 |
| A-6b | 首次全量运行（与其他编译命令并行、高负载） | `test/e2e` 时序断言失败（`FATAL: 退避间隔越界: req1→req2 = 22768ms，期望量级 [2000, 20000]ms`，`scenarios_wbtest.mbt:62`），测试进程 exit `0xc0000409`；单独重跑恢复 ⇒ 判定为负载敏感 flaky |
| A-7 | `moon test test/e2e`（单独重跑） | `Total tests: 14, passed: 14, failed: 0`，EXIT=0 |
| A-8 | `cmd.exe selftest --repo .` | `summary: 20/20 probes passed`；`native vs moon run differences: none`，EXIT=0 |
| A-9 | `cmd.exe eval --offline --repo .` | `completion_rate:1, verification_rate:1, repeatability:1`（16/16 断言），EXIT=0 |
| A-10 | journey 报告 `_build/journey/journey_2026-09-23.txt`（2026-09-23 20:58 运行） | `Total: 13  Passed: 13  Failed: 0`（Web 5 / TUI 3 / 持久化与重启 3+ / CLI 2）；台账 `docs/journey-failures.md` 无未修复行 |
| A-11 | WebFetch `.../workflows/ci.yml/badge.svg` | `<title>CI - passing</title>` |
| A-12 | WebFetch `.../workflows/docker.yml/badge.svg` | `<title>Docker - passing</title>` |
| A-13 | WebFetch `github.com/hnlyxiaobing/MBOpenClacky/actions` | 333 次运行；最新 `ad1e281` 的 CI #166 / Docker #166 为 In progress；#165 及之前已完成并有耗时记录 |
| A-14 | WebFetch `mooncakes.io/docs/hnlyxiaobing/MBOpenClacky` | 可查询；0.1.0/0.1.1/0.1.2/0.1.3(latest)，last updated 26 days ago |
| A-15 | Glob `lib/**/*.c` | 8 个 C 文件全部存在（对应 6 处 native-stub 声明） |
| A-16 | Grep `curl/curl.h`（全仓） | 0 命中 |
| A-17 | Grep `sqlite`（`*.mbt`） | 3 处非实现命中（测试字面量 + 扩展名列表），无实现代码 |
| A-18 | git log（`--since=2026-08-15` 及关键字检索） | 关键修复提交链：`07d83f0`(MCP stdio)、`fb3649e`(parser 重写)、`6a4e226`(channel 诚实错误)、`bdc9272`/`c16f2c7`(渠道发送接线)、`1087269`(编辑撤回)、`aa1b3e0`(移除 libcurl)、`ff9ab4b`(Windows 跳过 -lcrypto)、`50d365d`(修复 CI 红)、`eb9ec18`/`109e3b8`(Web JSONL/MCP HTTP) |

## 附录 B：本次核查引用的主要文件

- 构建/链接：`scripts/build-script.js`、`lib/brand/moon.pkg`、`cmd/moon.pkg`、`Dockerfile`、`.github/workflows/ci.yml`、`.github/workflows/docker.yml`
- 功能实现：`lib/pricing/cost_calculator.mbt`、`lib/pricing/model_pricing.mbt`、`lib/parser/*.mbt`、`lib/mcp/stdio_transport.mbt`、`lib/mcp/http_transport.mbt`、`lib/channel/*.mbt`、`lib/extension/*.mbt`
- 合规：`THIRD_PARTY_LICENSES.md`、`NOTICE`、`README.md`（§会话持久化）、`web/vendor/hljs/highlight.min.js`、`web/vendor/marked/marked.min.js`、`web/PATCHES.md`
- 台账与状态：`docs/known-gaps.md`、`docs/project-status.md`、`docs/improvement-roadmap.md`、`docs/improvement-execution-plan.md`、`docs/CHANGELOG.md`
- 测试基础设施：`test/e2e/scenarios_wbtest.mbt`、`lib/channel/channel_wbtest.mbt`

---

*报告生成：2026-09-23 · 核查人：Qoder（AI 助手）· 基线 commit：`ad1e281`*