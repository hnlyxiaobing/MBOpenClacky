# 渠道连通性探针真实化 + 遗留卫生清理 · 增量 Spec

> **创建日期**: 2026-09-22
> **状态**: 已完成（2026-09-22 实现并验收通过，直接落入 completed）
> **关联总览**: `docs/improvement-execution-plan.md`（WP-1.2~1.4 收尾时暴露的遗留项，本身不在 WP 列表内）
> **关联历史 spec**: `specs/completed/2026-09-22_wp-1.2-1.4-channel-send-wiring.md`（本次探针复用了该批次的客户端与 mock 手法）
> **来源差距**: known-gaps 台账 `lib/web/handlers_channels.mbt` 8 行命中（336/387/389/391/393/448/472/718）
> **依赖**: 无
> **灰度 key**: 无

## 问题描述 [必填]

WP-1.2~1.4 把钉钉/企微/微信的发送侧接通后，暴露出同一区域的四类"文档与事实不一致"的遗留问题：

1. **连通性探针名不副实**：`POST /api/channels/:id/test` 只对飞书/Discord 做真实探测，telegram/wecom/weixin/dingtalk 直接返回 `("not_implemented", ...)`——而现在这四家都有可用的只读认证接口，返回"未实现"既不诚实也无用。
2. **不可达且伪造成功的同步处理器**：`handle_channels_send`（sync）在不做任何派发的情况下返回 `"success": true`，`handle_channels_test`（sync）只做字段校验却挂在"连通性测试"名下。两者都不在线上路由上（`server.mbt` 的 bridge 早已指向异步版本），但作为 `pub` 函数留在公共 API 中是个陷阱——一旦有人误接线就是假成功。
3. **离线评测污染工作区**：`cmd eval --offline`（CI 闸门）把报告写进 `docs/eval/<date>.md`，每次本地跑评测都留一个未跟踪产物。
4. **格式化漂移**：`moon fmt --check` 全仓失败，涉及 7 个与本次改动无关的文件。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令/方式 | 结果 | 结论 |
|------|---------|------|------|
| "四平台探针未实现" | 实读 `lib/web/handlers_channels.mbt:383-395` | 四分支均返回 `("not_implemented", ...)` | 确认缺口 |
| "线上路由走异步版本" | 读 `lib/web/server.mbt:466,472` + `handlers_bridge.mbt:222-228,1070-1076` | bridge → `handle_channels_test_async` / `handle_channels_send_async` | 同步版本不可达 |
| "sync send 伪造成功" | 实读 `handlers_channels.mbt:752-760`（改前） | `"success": true`，注释"we would call the channel adapter" | 确认违反 stubfix-02 契约 |
| "sync 处理器无调用方" | `grep -rn "handle_channels_test(\|handle_channels_send(\|test_channel_adapter" lib test cmd`（*.mbt） | 仅定义处命中，零调用方（测试只用 `_async`） | 确认可删 |
| "router 的表只是名字" | 读 `lib/web/router.mbt:1-3,271-286` | 文件标注 `@deprecated`，"kept for unit-test coverage only"，`add_route` 存的是字符串名 | 删除函数不影响路由测试 |
| "前端不调 test/send/users" | `grep -rn "api/channels" web/` | 仅 `/api/channels`（列表）与 `/api/channels/:id/enabled` | 无前端依赖 |
| "微信缺便宜的探针接口" | 读 `weixin_api.mbt`（getupdates/sendmessage/sendtyping/getuploadurl/download） | 无 getMe 类接口；`build_get_updates_request` 硬编码 `timeout: 40` | 需新增短超时探针方法 |
| "Telegram 错误字段未被解析" | 读 `http_helper.mbt::extract_api_error` | 只尝试 error/message/msg/errmsg | Telegram 的 `description` 落空为 "Unknown API error" |
| "x/crypto ECB 已在依赖内" | 读 `.mooncakes/moonbitlang/x/crypto/pkg.generated.mbti` | `aes_ecb_encrypt/decrypt` 在列 | 见 WP-1.4 spec，本次不涉 |
| "eval 报告写 docs/eval" | 实读 `cmd/eval.mbt:112-116` | `out_dir` 默认 `repo/docs/eval`；CI 以 `eval --offline` 为闸门 | 确认每次运行留未跟踪产物 |
| "fmt 漂移范围" | `moon fmt --check` 全仓 | 7 个文件不合格（cmd×3、lib/server×1、test/eval×3，含 `moon.pkg` 注释前空格） | 确认与本次改动无关 |

### 详细分析

**探针的可测性边界**：`handle_channels_test_async` 只把 `webhook_url`/`api_key`/`secret` 三个字段透传给探针（`ChannelEntry` 结构如此），没有可注入 base URL 的通道，因此无法像渠道包那样用本地 mock 做 happy-path 往返。这与既有飞书/Discord 探针同口径——它们的测试也只覆盖"凭据缺失/未知平台"分支。故本次的确定性验证落在"凭据缺失 → failed + 诊断信息"上，happy path 需真实凭据，属已知限制并在 CHANGELOG 中如实标注。

**为什么必须删而不是改**：两个同步处理器都不可达。伪造成功的那个即使改注释也仍是假成功实现；正确做法是删除，让唯一的实现（异步版本）成为唯一事实。台账里 `472`/`718` 两行用 "stub" 描述它们，删除后这两行自然闭环。

**`handle_channels_users` / `handle_channels_group_history` 未在本 spec 范围**：这两个**是**线上端点（bridge 指向同步实现），当前恒返回空数组并用 "For now" 注释标注。它们的诚实修需要按平台实现成员/历史拉取（飞书 im/v1/chats members、Discord guild members 等），是独立工作包；本 spec 不动其行为，仅在报告中登记为已知限制。

## 决策 [必填 - 含为什么]

1. **决策 1（探针实现方式）**：四平台各写一个与 `test_feishu_connectivity`/`test_discord_connectivity` 同形的 `async fn`，走真实只读接口：Telegram `getMe`（复用 `TelegramApiClient::get_me_url`/`request_headers`）、企微 `WeComApiClient::get_access_token`、钉钉 `DingTalkApiClient::request_access_token`、微信 `WeixinApiClient::probe_connectivity`。
   - **为什么**：这些认证/只读调用已在 WP-1.2~1.4 验证可用，直接复用即"用真话替换占位"；GET/短超时调用无副作用。
2. **决策 2（微信探针用 1 秒 getupdates）**：新增 `WeixinApiClient::probe_connectivity`，POST `getupdates` 但把 `timeout` 设为 1 秒（不复用硬编码 40 秒的接收循环构建器），并把 `ret != 0` 透出为错误。
   - **为什么**：iLink 没有 getMe 类接口；`getupdates` 是唯一只读且能暴露 token 失效的调用。连通性测试若阻塞 40 秒不可接受。
3. **决策 3（补齐 Telegram 错误字段）**：在 `extract_api_error` 的兜底链末尾追加 `description`。
   - **为什么**：Telegram 的失败报文是 `{"ok":false,"description":"..."}`；不补则该渠道的错误会退化成 "Unknown API error"，探针的诊断价值下降。放在链末不影响既有字段优先级。
4. **决策 4（删除而非保留同步处理器）**：删除 `handle_channels_send`、`handle_channels_test` 与私有 `test_channel_adapter`。
   - **为什么**：不可达（线上走 bridge → async）+ 伪造成功（违反 stubfix-02 诚实契约）。保留它们等于保留一个"接线即假成功"的陷阱；项目约定也支持删除确认无用的代码。`retracted` 不适用（不是误报），故台账行按 `fixed` 记录。
5. **决策 5（离线报告落 `_build/eval`）**：`out_dir` 默认改为 `repo/_build/eval`；`--out` 仍可覆盖；同步更新 CLI help 与 `tool_harness` 文档注释。
   - **为什么**：`eval --offline` 是 CI 闸门，闸门不应产生需要人工清理的仓库产物；而 `docs/eval/<date>.md` 的价值在于**真模型**运行的可入库证据（WP-2.2），故保留该目录给 live 路径。
6. **决策 6（fmt 漂移单独处理）**：对漂移文件做定点 `moon fmt`（不裸跑全仓 fmt），`test/eval/moon.pkg` 的多余空格手改（formatter 只报不改 pkg 文件）。
   - **为什么**：`moon fmt` 会重写无关文件，定点处理避免把格式化噪音混进本次语义改动；`moon fmt --check` 由红转绿是本项完成的判据。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及动态加载 trait
- crescent 路由：未新增/删除路由，仅删除了不在路由上的公共函数（router.mbt 已 @deprecated）
- FFI：不涉及
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_channels.mbt` | 修改 | 四平台探针接线；重写 `test` 处理器的文档；删除两个同步处理器与 `test_channel_adapter`；Discord 注释改引 WP-1.6 |
| `lib/web/handlers_channels_wiring_wbtest.mbt` | 修改 | 用"凭据缺失 → failed"契约替换 `not_implemented` 断言；六平台参数化覆盖 |
| `lib/channel/weixin_api.mbt` | 修改 | 新增 `probe_connectivity` |
| `lib/channel/http_helper.mbt` | 修改 | `extract_api_error` 追加 `description` |
| `lib/channel/channel_wbtest.mbt` | 修改 | Telegram `description` 字段解析用例 |
| `lib/channel/channel_http_mock_wbtest.mbt` | 修改 | mock 增加 `getupdates` 路由；探针往返与 token 失效用例 |
| `cmd/eval.mbt` | 修改 | 离线报告默认目录改 `_build/eval`；文档同步 |
| `cmd/main.mbt` | 修改 | `eval` 子命令两条 help 文本同步 |
| `test/eval/tool_harness.mbt` | 修改 | `to_markdown` 文档注释去掉硬编码路径 |
| `test/eval/moon.pkg`、`cmd/inspect.mbt`、`cmd/session_log_producer_wbtest.mbt`、`lib/server/scheduler_wbtest.mbt` | 修改 | 纯格式化（清除既有漂移） |
| `lib/channel/pkg.generated.mbti`、`lib/web/pkg.generated.mbti` | 自动 | `moon info` 重新生成 |

### 不涉及文件

- `handle_channels_users` / `handle_channels_group_history` 的恒空返回——需按平台实现成员/历史拉取，独立工作包（已在报告中登记）
- `router.mbt`（@deprecated 的旧路由表，仍保留名字字符串）
- 线上路由注册（`server.mbt`）——本 spec 未增删路由
- 渠道包各 adapter 的发送逻辑——WP-1.2~1.4 已完成

## 实施计划 [必填]

### 任务包 1：探针接线（lib/web + lib/channel）
- `extract_api_error` 补 `description`；`WeixinApiClient::probe_connectivity`
- 四平台探针函数 + 处理器分支替换 + 文档重写

### 任务包 2：删除伪造成功的同步处理器
- 删 `handle_channels_send`/`handle_channels_test`/`test_channel_adapter`；Discord 注释改引 WP-1.6

### 任务包 3：评测报告路径与 fmt 漂移
- `cmd/eval.mbt` 默认目录 + help/文档同步；定点格式化 7 个漂移文件

### 任务包 4：测试与验收归档
- wbtest：六平台凭据缺失契约、探针 mock 往返与 token 失效、Telegram 错误字段
- 台账 8 行转 `fixed`；`repo_stats` 重新生成；CHANGELOG 与 spec 归档

## 验收标准 [必填]

- [x] `POST /api/channels/:id/test` 对六平台均做真实探测；无 `not_implemented` 分支（`grep` 该文件无 not implemented/not yet/stub 命中，仅余被抑制的占位词域术语）
- [x] 凭据缺失时返回 `failed` + 平台诊断信息（六平台参数化测试）
- [x] 微信探针为 1 秒超时（mock 断言请求体 `timeout == 1`），token 失效透出错误
- [x] Telegram 的 `description` 能被解析为错误信息
- [x] 两个不可达同步处理器已删除，公共 API 中不再存在伪造成功的 send/capability 入口（`mbti` 同步）
- [x] `moon fmt --check` 全仓通过（此前 7 个文件不合格）
- [x] `cmd eval --offline` 报告落 `_build/eval/`，不再产生 `docs/eval/` 未跟踪产物
- [x] `moon check -d` 全仓 0 错 0 警（312 tasks）；`lib/channel` 444/444、`lib/web` 477/477；CI 同口径 scoped 套件 3864/3864；`selftest` 18/18；`eval --offline` 3/3
- [x] `known_gaps.sh check` 绿（112 → 104 live hits）；`repo_stats.sh check` 绿（3864）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 删除两个 `pub` 函数影响外部调用方 | 低 | `grep` 全仓确认零调用方 + 前端不调这两个端点；`moon check -d` 全仓编译验证 |
| 探针的 happy path 无自动化验证 | 中 | 与飞书/Discord 探针同口径的已知限制；CHANGELOG 与本节如实标注，不宣称已验证真实平台连通 |
| 微信 1 秒 getupdates 在无消息时仍可能略慢 | 低 | 探针为用户显式触发（点"测试"），1 秒可接受；不放在自动轮询路径上 |
| 评测报告改目录导致既有文档引用失效 | 低 | 全仓 `grep docs/eval` 后同步 CLI help 与 `tool_harness` 注释；WP-2.2（live）的 docs/eval 意图保留 |
| 格式化提交与语义改动混在同一提交 | 低 | fmt 漂移文件已在 spec/CHANGELOG 中逐条列出，便于复核；未使用裸 `moon fmt` |

## 依赖关系 [必填]

- **前置依赖**：WP-1.2~1.4（探针复用的客户端与 mock 手法）
- **后置依赖**：无。`handle_channels_users`/`group_history` 的恒空返回、以及 `docs/eval/` 的真模型报告属独立工作包

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-09-22 | 初始版本（实现与验收同批完成） | - |