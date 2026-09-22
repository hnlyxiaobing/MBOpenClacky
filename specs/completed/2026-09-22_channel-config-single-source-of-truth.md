# 渠道配置单一真相源贯通（配置路径 → 运行时 → Web 面板 → channel-manager 技能） · 增量 Spec

> **创建日期**: 2026-09-22
> **状态**: 已完成（2026-09-22 实现并验收通过，归档至 completed）
> **关联总览**: `docs/improvement-execution-plan.md`（WP-1.2~1.4 收尾时暴露的产品面缺口，本身不在 WP 列表内）
> **关联历史 spec**: `specs/completed/2026-09-22_leftover-hygiene-and-connectivity-probes.md`（本 spec 修正其"探针 happy path 无出口"的实现前置）、`specs/completed/2026-07-17_02_channel-placeholder-fixes.md`（确立 JSON 路径与 schema）
> **来源差距**: 新发现（非台账既有行）；台账 `lib/web/handlers_channels.mbt` 8 行此前已 `fixed`，本 spec 处理其**未覆盖的产品面**
> **依赖**: WP-1.1~1.4（已完成的渠道发送接线）
> **灰度 key**: 无

## 问题描述 [必填]

渠道配置链路上有**四处**与事实不符的断点，使"配置好的渠道"在生产中整体不生效：

0. **【最严重】默认配置路径根本读不到**：`lib/web/server.mbt:75` 以字面量 `"~/.mbopenclacky/channels.json"` 构造 `ChannelManager`，而 `moonbitlang/x/fs` 不做 `~` 展开（`grep` 其源码无 expand/HOME/tilde 处理），`lib/channel` 内也无任何展开逻辑。故 `load_config` 的 `@fs.path_exists` 对 `"~/..."` 恒为 false → 返回 `Ok` 且 `configs=[]` → **零适配器被注册**。即使使用者按文档手工创建了该文件，运行时依旧读不到。
1. **运行时真相**：`~/.mbopenclacky/channels.json`，schema `{channels:[{platform,enabled,settings:{...}}]}`（`ChannelManager::load_config`）；适配器所需平台专属凭据全部来自 `settings`。
2. **Web 面板**：`lib/web/handlers_channels.mbt` 的进程内 `channels_store`（`ChannelEntry` 仅 `webhook_url`/`api_key`/`secret` 三个扁平字段），**不落盘、不读盘、从不写入 ChannelManager**。面板状态与 toggle 均只作用于它。
3. **channel-manager 技能**：`assets/skills/channel-manager/SKILL.md:46,140,315` 指示 Agent 写 **`~/.mbopenclacky/channels.yml`**，且其 schema 是**按平台嵌套的扁平 YAML 映射**（`channels: → feishu: → app_id/app_secret/domain`），与运行时的"数组 + `settings` 子对象"**结构不同**；`lib/channel/moon.pkg` 无 YAML 解析器。

已核实的后果：

- 面板 `/api/channels` 恒返回六平台 `has_config:false` → "Not configured"；`has_token` 更是被硬编码为 `false`（`handlers_channels.mbt:70,74-78`），而 `web/weixin-qr.html:183` 正依赖该字段；
- `PATCH /api/channels/:platform/enabled` 只翻转内存条目，不落盘、不影响运行时，进程重启即丢失；
- 面板 "Set Up" / "Test" 按钮最终都落到写 `channels.yml` 的技能路径 → 配置无任何运行时效果；
- 上一批次刚做真实的四平台连通性探针（`POST /api/channels/:id/test`）**无任何调用方**（前端只调 list 与 enabled）；且其配置来源是空库，微信 `uin` 在 Web 路径下永远取不到（`ChannelEntry` 无此键、无 fallback），只能得到 "Missing uin setting"；
- `send_to` / `is_platform_configured` 在生产中恒失败/恒 false（因第 0 条），webhook 接收路径（`handlers_bridge.mbt:274`）因此全部丢弃事件。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令/方式 | 结果 | 结论 |
|------|---------|------|------|
| "默认路径的字面 `~` 未被展开" | `grep -rn "home_dir\|expand_tilde" lib/channel/ lib/web/`；`grep -rn "expand\|HOME\|tilde" .mooncakes/moonbitlang/x/fs/*` | `lib/channel` 零命中；`lib/web` 仅 ext_* 有 `expand_tilde`/`@utils.home_dir()`；fs 源码无展开逻辑 | **确认：默认路径恒读不到** |
| "本机不存在 channels.json" | `test -f ~/.mbopenclacky/channels.json` | NO（同理生产环境无任何渠道被加载） | 确认当前不生效 |
| "仓库惯例是 home_dir + Path::join" | 读 `lib/brand/config.mbt:40-50`、`lib/billing/billing_store.mbt:105-118` | 均以 `@utils.home_dir()` / `USERPROFILE`+`HOME` 拼路径 | 确认修法有既有范式 |
| "Web 渠道条目只有三个字段" | 读 `lib/web/handlers_channels.mbt:9-20` | `ChannelEntry{webhook_url,api_key,secret,...}` | 确认 |
| "Web 渠道库仅在本文件+1 测试" | `grep -rn "channels_store\|ChannelEntry"`（排除 `_build`/`.git`/`specs`） | 仅 `handlers_channels.mbt`、`handlers_channels_wiring_wbtest.mbt:39-55`，及生成物 `pkg.generated.mbti:326` | 确认可删 |
| "无任何写 channels.json 的代码" | `grep -rn "channels\.json" --include=*.mbt .` | 仅 `lib/channel/manager.mbt:9`（注释）与 `lib/web/server.mbt:75`（字面量）；无 writer，也无通用保存助手指向它 | 确认需新增写入原语 |
| "运行时 settings 键（完整）" | `grep -n 'settings.get' lib/channel/{feishu,wecom,telegram,discord,dingtalk,weixin}.mbt` | feishu: `bot_id`/`bot_secret`/`webhook_url`/`app_id`/`app_secret`；wecom: `corp_id`/`agent_id`/`secret`/`token`/`encoding_aes_key`/`api_base`；telegram: `bot_token`；discord: `bot_token`/`application_id`；dingtalk: `app_key`/`app_secret`/`access_token`/`secret`/`webhook_url`/`robot_code`；weixin: `app_id`/`app_secret`/`token`/`encoding_aes_key`/`api_base`/`uin` | 面板三字段无法满足任一平台 |
| "`api_key` 不被任何适配器读取" | `grep -n "api_key" lib/channel/*.mbt`（适配器） | 0 命中；面板的 `api_key` 字段对适配器无意义 | 推翻"api_key 有 fallback"的早期说法 |
| "面板按钮走技能而非 REST" | 读 `web/features/channels/view.js:21-22,37-38,53-54,189-197` | `setupCmd:"/channel-manager setup <p>"`、`testCmd:"/channel-manager doctor"` | 确认 |
| "前端只调 list 与 enabled" | `grep -rn "api/channels" web/` | `store.js:54`（GET）、`store.js:65`（PATCH enabled）、`weixin-qr.html:183`（GET 轮询） | `POST /:id/test` 无调用方；**QR 页依赖 `has_token`** |
| "技能 schema 结构也不同，非仅路径" | 读 `assets/skills/channel-manager/SKILL.md:140-149,166-175,194-199,315` | YAML、平台为键、字段扁平；含 `domain`/`method` 等运行时从不读取的键 | 确认 |
| "JSON 是既定决策" | 读 `specs/completed/2026-07-17_02_channel-placeholder-fixes.md:42` | "改用 JSON 格式…路径调整为 `~/.mbopenclacky/channels.json`，不引入 YAML 依赖" | 技能文档与既定决策冲突 |
| "`reload()` 不重建适配器" | 读 `lib/channel/manager.mbt:200-214` | stop → load_config → start；从不调 `create_adapter_from_config` | 仅 reload 不足以应用变更 |
| "registry 无清理原语" | 读 `lib/channel/registry.mbt`（64 行） | 仅 register/find/all/list_names/has/size | 需新增 clear |
| "`@fs` 无 rename，无法原子替换" | 读 `lib/agent/session_manager.mbt:93-113`（注释明写）、`lib/server/scheduler.mbt:489` | 采用 read+write+remove 变通 | 原子重命名方案不可实现 |
| "写盘原语齐备" | 读 `lib/channel/moon.pkg` + `grep "@fs.write" lib/` | `@fs.write_string_to_file`/`remove_file`/`path_exists`/`read_file_to_string` 均在用 | 可实现写+删的替换 |
| "无 lib/web 外调用方" | `grep -rn "handle_channels_" cmd/ test/ assets/` | 零命中；仅 `lib/web/server.mbt:452-464` 路由 + `handlers_bridge.mbt` 桥接 | 改造面收敛于 lib/web |

### 详细分析

**第 0 条是根因，也是最便宜的高价值修复**：它使整个渠道子系统在生产中处于"永不加载"状态。`server.mbt:75` 的字面量 `~` 既不报错也不告警（`load_config` 对不存在的文件按"空配置"处理），因此问题长期隐形。同类字面量在 `lib/tool/browser.mbt:417`、`lib/agent/time_machine.mbt:9` 亦存在，但**不在本 spec 范围**（仅登记）。

**为什么必须删除而不是同步 `channels_store`**：它只有三个扁平字段（且 `api_key` 对适配器无意义），装不下 `settings` 的平台专属键；任何"同步"方案都要双向映射并继续维护两套模型。删除后面板成为 `ChannelManager` 的投影与写入端。

**`handle_channels_test_async` 是本 spec 的核心触点**：它把 `ChannelEntry` 三字段塞进 `settings`（`handlers_channels.mbt:369-383`），因此探针从未用真实凭据探测过。改由 manager 的 `ChannelConfig` 直接取用后，探针才有实际价值（也让上一批次的四平台探针首次有出口）。

**技能路径是"Set Up with Agent"的唯一实现**：面板不收集凭据（Agent-First，`store.js:3-6` 明写 "no config forms"），故技能写入的文件路径与 schema 若不修，Agent 引导式配置在产品上永久失效。

## 决策 [必填 - 含为什么]

1. **决策 0（先修默认路径解析）**：`ChannelManager` 构造/加载前把 `~` 展开为真实 home（`@utils.home_dir()` + `@path.Path::join`，与 `lib/brand/config.mbt`、`lib/billing/billing_store.mbt` 同范式），展开失败时返回可诊断错误而非静默空配置。
   - **为什么**：不修则"单一真相源"指向一个运行时读不到的文件，后续所有工作无意义；且静默空配置违反项目"诚实纪律"（不可诊断的降级）。
2. **决策 1（唯一真相源 = `channels.json`）**：删除 `ChannelEntry`/`channels_store`；list/status/create/update/delete/enabled 全部改为读写 `ChannelManager`（configs + registry + active_channels），并写回同一文件。
3. **决策 2（在 `lib/channel` 增加写入与应用原语）**：新增 `save_config`、`set_platform_enabled`、`upsert_platform`、`remove_platform`、`apply_config` 与 `AdapterRegistry::clear`。
   - **为什么**：全仓无写入能力（已验证）；放在 `lib/channel` 可被 CLI/TUI/Web 复用并就近单测。用 `apply_config` 而非 `reload`：后者复用旧 registry，新增/禁用平台不会反映到适配器。
4. **决策 3（settings 全量透传 + 密钥掩码）**：API 接受/返回全量 `settings`；返回时命中密钥键（`secret`/`app_secret`/`bot_secret`/`bot_token`/`token`/`access_token`/`api_key`/`encoding_aes_key`/`client_secret` 及 `*_secret`/`*_token` 后缀）一律只输出 `has_<key>` 布尔，不输出明文。`has_token` 由真实 `settings` 推导（替代硬编码 false），保持 `weixin-qr.html` 契约。
   - **为什么**：`settings` 必须能装凭据（否则接不通），而 REST 响应是明文出口；沿用既有 `has_api_key`/`has_secret` 约定并推广。
5. **决策 4（探针取 manager 的真实配置）**：`handle_channels_test_async` 的 `ChannelConfig` 改为从 manager 取该平台已存配置（含全量 settings）；未配置平台返回可诊断 `failed`。settings 中若含 `base_url`/`api_base` 则沿用（适配器已有该约定），从而支持离线 mock 验证 happy path。
6. **决策 5（前端 Test 按钮改调 REST 探针）**：`view.js` 的 Test 按钮由 `/channel-manager doctor` 改为 `POST /api/channels/:platform/test` 并渲染 `test_result`/`latency_ms`/`error`；Setup 保持 Agent-First（技能修正后即可生效）。
   - **为什么**：Test 语义是"现在探测连通性"，REST 端点已实现且是唯一带延迟与平台错误原话的路径。
7. **决策 6（技能与文档对齐真实路径+schema）**：重写 `channel-manager/SKILL.md` 的 status/setup/doctor/enable/disable，统一写 `~/.mbopenclacky/channels.json` 的 `{channels:[{platform,enabled,settings:{...}}]}`，并逐平台列出**完整** settings 键名；删去运行时从不读取的 `domain`/`method` 键；修正 `product-help/SKILL.md:81`。
8. **决策 7（写盘不做伪原子）**：采用 `@fs.write_string_to_file` 直写（`@fs` 无 rename），失败时如实返回错误；不宣称原子替换。
   - **为什么**：`lib/agent/session_manager.mbt:95` 已明确该库无 rename；引入伪原子逻辑会掩盖失败。
9. **决策 8（TaskGroup 归属）**：`lib/channel` 的 `apply_config` 只做"停止 + 清 registry + 重建 + 启动"，**不**持有 TaskGroup；由 `lib/web` 在调用后复用同包内的 `ws_task_group`（`handlers_ws.mbt:53` 的包级 Ref，`server.mbt:1012` 安装）调用 `start_with_gateway(group)` 重新 spawn Discord gateway。
   - **为什么**：避免 `lib/channel` 反向依赖 `lib/web`；句柄不可得时如实降级为"需重启进程"并写台账，不伪造热生效。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及动态加载 trait
- crescent 路由：不新增/删除路由；`handle_channels_test_async` 增加 manager 参数（同步 `handle_channels_test_bridge` 一并改）
- FFI：不涉及（JSON 用既有 `@json`，写盘用既有 `moonbitlang/x/fs`）
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/channel/manager.mbt` | 修改 | 路径展开（home_dir/Path::join）；新增 `save_config`/`set_platform_enabled`/`upsert_platform`/`remove_platform`/`apply_config` |
| `lib/channel/registry.mbt` | 修改 | 新增 `clear`（丢弃陈旧适配器） |
| `lib/channel/weixin.mbt` | 修改 | `WeixinAdapter::new` 的 `app_id`/`app_secret` 由硬要求改为可选（iLink 路径不使用）；`validate_config` 改为要求 `token` 并在缺 `uin` 时报诊断 |
| `lib/web/handlers_channels.mbt` | 重构 | 删除 `ChannelEntry`/`channels_store`；各端点改 manager 投影/写入；`has_token` 由真实 settings 推导；探针取真实配置；`handle_channels_test_async` 增加 manager 参数 |
| `lib/web/handlers_bridge.mbt` | 修改 | list/create/update/delete/toggle/**test** 各 bridge 传入 `server_ref.val.channel_manager`（test bridge 在 `:222-228`） |
| `lib/web/server.mbt` | 修改 | `init_channel_manager` 使用展开后的路径；配置变更后复用 `ws_task_group` 重 spawn gateway |
| `lib/web/handlers_channels_wiring_wbtest.mbt` | 修改 | 改用临时目录 `channels.json` 播种（现 `wiring_seed_channel` 重置内存库的写法失效）；新增持久化/掩码/探针取配置用例 |
| `lib/channel/channel_wbtest.mbt`、`channel_p2_wbtest.mbt` | 修改 | `save_config` 往返、`set_platform_enabled` 落盘、`apply_config` 重建适配器、`clear`、路径展开 |
| `web/features/channels/store.js` | 修改 | 新增 `test(platform)` 调 REST 探针 |
| `web/features/channels/view.js` | 修改 | Test 按钮渲染真实探测结果；Setup 保持 Agent 路径 |
| `assets/skills/channel-manager/SKILL.md` | 修改 | 全节对齐 `channels.json` 路径与真实 schema（完整 settings 键名） |
| `assets/skills/product-help/SKILL.md` | 修改 | `:81` 路径改为 `channels.json` |
| `docs/project-status.md` | 修改 | `:198-203` 渠道成熟度已失真（称飞书/企微"未接 HTTP 传输"），按本 spec 后的真实可达性复核 |
| `docs/CHANGELOG.md`、`docs/known-gaps.md`、`docs/improvement-execution-plan.md` | 修改 | 记录本 WP；新增并闭环台账行；执行计划登记新 WP |
| `lib/channel/pkg.generated.mbti`、`lib/web/pkg.generated.mbti` | 自动 | `moon info` 重新生成 |

### 不涉及文件

- `web/features/channels/store.js` 的 Agent-First 设计（**不**新增凭据表单）
- 各平台适配器与 `*_api.mbt` 的发送/探针逻辑（WP-1.1~1.4 已完成）
- `handle_channels_users` / `handle_channels_group_history` 的成员/历史拉取（独立工作包，沿用既有登记）
- `lib/tool/browser.mbt:417`、`lib/agent/time_machine.mbt:9` 的同型字面 `~` 路径（超出范围，仅登记台账）
- `docs/getting-started.md`（经查无渠道配置内容，无需改动）

## 实施计划 [必填]

### 任务包 1：路径解析 + `lib/channel` 写入与应用原语（预估 1 天）
- 路径展开（决策 0）+ 展开失败的可诊断错误；`AdapterRegistry::clear()`
- `save_config`（`{channels:[...]}` 直写，失败报错）/`set_platform_enabled`/`upsert_platform`/`remove_platform`
- `apply_config()`：stop → clear → load_config → init → start（不含 gateway；由 lib/web 包装）
- wbtest：路径展开断言、往返保真（settings 原样）、落盘后 load 一致、禁用平台不再注册适配器

### 任务包 2：Web 端点改投影与写入（预估 1 天）
- 删除 `ChannelEntry`/`channels_store`；list 由 manager 投影 `enabled`/`running`/`has_config`/掩码摘要/真实 `has_token`
- create/update/delete/enabled 走写入原语，失败返回可诊断 400/404
- `handle_channels_test_async` 取 manager 中该平台配置；未配置平台返回可诊断 failed
- bridge（含 test）传入 manager；`moon check` 紧循环

### 任务包 3：技能与文档对齐（预估 0.5 天）
- 重写 `channel-manager/SKILL.md`：写 `channels.json` 真实 schema，逐平台列全 settings 键；doctor 增"文件存在且 schema 可解析"检查
- `product-help/SKILL.md`、`project-status.md` 同步

### 任务包 4：前端 Test 接真实探针（预估 0.5 天）
- `store.js` 增 `test(platform)`；`view.js` 渲染 `test_result`/`latency_ms`/`error`
- 手工验证（无真实凭据时如实说明，不宣称已验证平台连通）

### 任务包 5：测试、验收与归档（预估 0.5 天）
- wbtest 全覆盖；`moon check -d` 0 错 0 警；`lib/channel`/`lib/web` scoped 全绿；`selftest`；`eval --offline`
- 台账新增/闭环、`repo_stats.sh` 重新生成、CHANGELOG、spec 归档

## 验收标准 [必填]

- [x] 默认配置路径被解析为真实 home：`expand_config_path` 纯函数用例（`~/x` + home → 拼接结果不含 `~`；`~` → home；无 `~` 原样；home 缺失/空 → 可诊断 Err；中间 `~` 不动）；**端到端**：以 `USERPROFILE` 指向隔离 home 启动 release 服务，`GET /api/channels` 如实回报已配置平台的 `has_config:true`
- [x] `grep -rn "channels_store\|ChannelEntry" --include=*.mbt lib/` → **0 命中**（双真相源与内存库已删除，含 `next_channel_id`/`find_channel_index`）
- [x] `GET /api/channels` 的 `enabled`/`running`/`has_config`/`has_token` 来自 `ChannelManager` 与真实 settings：实测 telegram/weixin 为 `true`、其余四平台 `has_config:false`；未配置报表层亦有断言
- [x] `PATCH /api/channels/:platform/enabled` 后配置文件内容随之变化，重新加载后保持（`channels_toggle_enabled persists to the config file` 用例；并断言设置项（如 `bot_token`）在开关往返中保留）
- [x] REST 响应**不含**任何明文密钥：`channels_list never serializes credential values` + `channels_status is projected from the manager` 断言 `secret-token`/`secret-uin`/`SECRET-TOK-VALUE` 不出现、`has_*` 出现；`web_handlers_wbtest` 的 `fix04-ak-plain`/`fix04-sk-plain` 用例沿用
- [x] `handle_channels_test_async` 使用配置文件中的 settings：隔离 home 实测微信探针返回真实平台响应 `HTTP Error 412`（不再是 "Missing uin setting" 短路）、Telegram 返回真实 `Unauthorized`、未配置平台返回 `Platform is not configured: feishu`、未知平台 400
- [x] `assets/skills/channel-manager/SKILL.md` 与 `product-help/SKILL.md` 不再**指示**写 `channels.yml`（全仓仅剩 1 处否定式说明 + 3 处 CHANGELOG/计划/路线图的历史叙述），schema 逐平台列出完整 settings 键名并与 `load_config` 一致
- [x] 面板 Test 按钮触发 `POST /api/channels/:platform/test`：`web/` 内已无 `/channel-manager doctor` 命中；浏览器实测点击 Diagnostics 在卡片内渲染出真实结果（微信 `HTTP Error 412:`、未配置飞书 `Platform is not configured: feishu`）
- [x] `handle_channels_users` / `group_history` 行为未变（仍为恒空数组，属独立工作包）
- [x] `moon check -d` 全仓 312 tasks 0 错 0 警；`moon test --release lib/channel lib/web lib/web/handler` **987/987**（lib/channel 460、lib/web 489、handler 38）；`selftest` 18/18；`eval --offline` 3/3
- [x] `scripts/known_gaps.sh check` 绿（104 live hits / 162 curated rows / 118 项域术语抑制）；`scripts/repo_stats.sh check` 绿；`moon fmt --check` 全仓通过
- [x] 台账复核：本次改动**未引入** TODO/stub 标记，故无新增台账行可闭环（台账为标记驱动，新增行必须有对应扫描命中）；两条无标记缺陷（`~` 路径、微信 `app_id` 硬要求）按项目约定记入 CHANGELOG 与本文而非台账

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 删除 `channels_store` 破坏既有测试 | 中 | 已确认调用方仅本文件 + 1 个 wbtest；测试同步改为临时目录播种，`moon check -d` 兜底 |
| 路径展开改变既有行为（原本"静默空配置"） | 中 | 展开后若文件不存在仍按空配置（保持不报错），但**存在且解析失败必须报错**；测试覆盖两种情形 |
| 密钥掩码遗漏某个键导致凭据泄露 | 高 | 键名规则 + 逐平台 settings 键清单双向覆盖；验收项含"响应不含明文"断言 |
| `@fs` 无 rename，直写有半写窗口 | 低 | 决策 7：直写 + 失败报错，不伪造原子性；如实记录 |
| 运行期重建适配器影响 Discord gateway | 中 | 决策 8：复用 `ws_task_group` 重 spawn；句柄不可得则如实降级并写台账 |
| `weixin-qr.html` 依赖的 `has_token` 契约被破坏 | 中 | 决策 3 要求 `has_token` 由真实 settings 推导；前端契约纳入验收 |
| 真实平台凭据不可得致 happy path 无法端到端验证 | 中 | 与既有探针同口径：mock（settings 带 `base_url`）+ 缺失分支覆盖；CHANGELOG 如实标注 |
| 技能改动后 Agent 仍按旧格式写 | 低 | 技能为单文件且 `user_invocable`；doctor 节新增显式 schema 校验步骤 |

## 依赖关系 [必填]

- **前置依赖**：WP-1.1~1.4（发送接线，已完成）；`2026-07-17_02`（JSON 路径决策，已完成）
- **后置依赖**：`handle_channels_users`/`group_history` 的真实成员/历史拉取；WP-1.6（update/delete_message）；前端契约测试可纳入本 spec 的探针端点

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-09-22 | 初始版本（draft） | - |
| 2026-09-22 | draft 第 2 版：新增"默认路径字面 `~` 未展开"为根因；修正 settings 键清单为完整版并删除"api_key fallback"误述；补 `weixin-qr.html` 的 `has_token` 契约、test bridge 签名、`@fs` 无 rename、TaskGroup 归属；移除无内容的 getting-started.md | 对抗性评审发现 2 处事实错误与 4 处范围遗漏 |
| 2026-09-22 | 实施中新增两项范围（实测发现）：①`WeixinAdapter::new` 硬要求 iLink 路径不使用的 `app_id`/`app_secret`，致已配置微信渠道无法构造、永不启动 → 改为可选并修正 `validate_config`；②`platform_extra_fields` 的 web-ui2-05 平台字段契约（`app_id`/`domain`/`allowed_users`/`bot_id`/`base_url`/`has_token`）保留为占位并由真实值覆盖，避免破坏既有契约测试 | 端到端实测（隔离 HOME 起服务）暴露的阻塞与既有契约约束 |
| 2026-09-22 | 实现与验收同批完成，归档至 completed；DoD 数据见"验收标准"节 | - |