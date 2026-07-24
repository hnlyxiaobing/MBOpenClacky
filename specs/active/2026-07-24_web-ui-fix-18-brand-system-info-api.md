# 品牌与系统信息 API 对齐 · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 讨论中  
> **关联总览**: `docs/web-ui-gaps.md`、`docs/web-ui-issues.md` I-022, I-023, I-024  
> **关联历史 spec**: `specs/completed/2026-07-24_web-ui-fix-04-api-response-wrappers.md`（API 形状对齐同方法论）、`specs/completed/2026-07-22_web-replication-10-brand-config-media.md`（brand 域既有工作）  
> **来源差距**: I-022 `/api/brand` 缺 13 个品牌键；I-023 `/api/onboard/status` 缺 needs_onboard/branded；I-024 `/api/version` 缺更新检查字段  
> **依赖**: 前置 fix-06  
> **优先级**: P2  
> **灰度 key**: 无

## 问题描述 [必填]

三个系统信息端点与同源前端（上游 v1.4.0 托管 fork，见 `web/UPSTREAM_SYNC.md`）消费的字段不匹配，均为 P2：

1. **I-022**：`GET /api/brand` 运行时实际只返回 `{device_id}`，缺 orig 的 13 个品牌键（`product_name/package_name/logo_url/support_contact/support_qr_url/theme_color/homepage_url/branded/activated/expired/license_expires_at/user_licensed/license_user_id`）。前端 `web/features/brand/view.js` 依赖 `info.logo_url`/`info.theme_color`/`info.product_name`/`info.homepage_url` 渲染 logo、favicon、主题色与首页链接，全部失效。
2. **I-023**：`GET /api/onboard/status` 返回 `{completed, step, skipped}`（onboard.json 状态机），缺 orig 的 `{needs_onboard, phase, branded}`。前端 `web/components/onboard.js:27` 以 `data.needs_onboard` 做引导门禁——字段缺失时门禁恒为 false，未配置模型的用户不再被引导，**行为影响需人工确认**。
3. **I-024**：`GET /api/version` 返回 `{current_version, version, available_update, changelog}`，缺 orig 的 `{current, latest, needs_update, launcher, cli_command}`。前端 `web/features/version/store.js:66-69` 直读 `data.current/latest/needs_update/cli_command`，更新提示完全失效。**需确认是否为有意重设计**（current 把远端检查挪到了 `POST /api/version/check`）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| GET /api/brand 路由到 handle_brand_config | `grep -n "brand" lib/web/server.mbt` | server.mbt:311 `br.get("", event => handle_brand_config(...))`；631-642 行为重复注册的 deprecated 组 | 确认 |
| handle_brand_config 返回 cfg.to_json() | 读 `lib/web/handlers_brand.mbt:58-65` | `BrandConfig::load(dir).to_json()`，`derive(ToJson)` | 确认 |
| 运行时实际仅返回 {device_id} | 读 `logs/web-compare/2026-07-24/api-diff.json` endpoints["/api/brand"] | current shape.keys 仅 `device_id: string`；orig 13 键全在 | 确认（derive ToJson 对 None 字段不输出键，故全空配置下只剩 device_id） |
| orig /api/brand 返回 brand.to_h 13 键 | 读 `D:/MoonBit/openclacky/lib/clacky/server/http_server.rb:2843-2846` 与 `brand_config.rb:1602-1618` | to_h 输出 product_name/package_name/logo_url/support_contact/support_qr_url/theme_color/homepage_url/branded/activated/expired/license_expires_at/user_licensed/license_user_id | 确认 13 键清单 |
| 13 键在 current BrandConfig 均有来源 | 读 `lib/brand/config.mbt:6-22,138-184` | 字段 product_name/package_name/logo_url/support_contact/support_qr_url/theme_color/homepage_url/license_expires_at/license_user_id 均在；派生方法 `is_branded()`(138)/`activated()`(154)/`expired(current_time)`(162)/`user_licensed()`(174) 均在 | 确认可补齐，无数据缺口 |
| **偏差**：cfg.to_json() 会泄露 license_key | 读 `lib/brand/config.mbt:14,22` | `license_key : String?` 在 derive(ToJson) 结构体内，一旦配置即随 GET /api/brand 明文输出；orig to_h 从不含 license_key | gap 文档未记录的安全问题，本 spec 一并修复 |
| 前端消费 /api/brand 的字段 | `grep -n "info.logo_url\|info.theme_color\|info.product_name\|info.homepage_url" web/features/brand/view.js` | view.js:205-365 读 theme_color/logo_url/product_name/homepage_url；settings.js:1438 读 product_name | 确认前端真实消费 |
| GET /api/onboard/status 返回 onboard.json 状态 | 读 `lib/web/handlers_onboard.mbt:206-213,181-187` | 返回 `{completed, step, skipped}`，无 needs_onboard/branded/phase | 确认 |
| orig /api/onboard/status 语义 | 读 `http_server.rb:965-976` | `needs_onboard = !models_configured?`，phase="key_setup"；`branded = BrandConfig.load.branded?`；orig agent_config.rb:443 `models_configured? = !models.empty? && !current_model.nil?` | 确认 orig 语义 |
| current 有等价判定能力 | 读 `lib/config/agent.mbt:9`（`models : Array[ModelConfig]`）；`handlers_onboard.mbt:283` 已用 `server_ref.val.config.current_model()` | 可实现 `!models.is_empty() && current_model() is Some(_)` | 确认无数据缺口 |
| 前端门禁消费 needs_onboard/phase | 读 `web/components/onboard.js:27-50` | `if (!data.needs_onboard) return { needsOnboard: false }`；按 phase 分流 key_setup/soul_setup | 确认：字段缺失 → 门禁失效（未配置模型用户不被引导） |
| GET /api/version 现状 | 读 `lib/web/handlers_version.mbt:125-137` | 返回 `{current_version, version, available_update:null, changelog:""}`，纯本地无远端检查 | 确认 |
| orig /api/version 语义 | 读 `http_server.rb:2940-2954` | `{current, latest, needs_update, launcher, cli_command}`；latest 来自 `fetch_latest_version_cached`（1 小时缓存，http_server.rb:3284）；cli_command = branded 且有 package_name 时取 package_name，否则 "openclacky"；launcher = ENV["CLACKY_LAUNCHER"] \|\| "cli" | 确认 orig 语义 |
| current 已有远端检查与版本比较原语 | 读 `lib/web/handlers_version.mbt:11,34-118` | `GITHUB_LATEST_URL`、`fetch_latest_version()`、`version_is_newer()` 已存在，现仅被 POST /check、/upgrade 使用 | 确认可复用，只需加缓存 |
| 前端消费 /api/version 字段 | 读 `web/features/version/store.js:63-69,113` | 直读 `data.current/latest/needs_update/cli_command`，仅调 GET /api/version（从未调 POST /check） | 确认：不补字段则更新提示永久失效 |
| 品牌键的模板消费方 | 读 `lib/web/template_processor.mbt:5,22-48,92-96` | 仅用 `{{BRAND_NAME}}` 占位符，经 `BrandConfig::load` 取 display name，与 /api/brand 响应形状无关 | 确认不受影响 |
| 品牌资产来源 | `Glob assets/**` + 读 `lib/brand/config.mbt:243-244` | brand 键来自 `~/.mbopenclacky/brand/brand.toml` 与 distribution 刷新（apply_distribution 白名单 7 键）；assets/ 下无品牌 JSON | 确认键来源为 brand.toml/distribution |

### 详细分析

| 端点 | 当前响应 | orig 响应 | 前端影响 |
|------|---------|----------|---------|
| `GET /api/brand` | 运行时 `{device_id}`（derive ToJson 省略 None 字段；若配置了 license_key 还会明文泄露） | 13 键（值可为 null，键恒存在） | brand/view.js 的 logo/favicon/主题色/首页链接全部失效 |
| `GET /api/onboard/status` | `{completed, step, skipped}` | `{needs_onboard, phase?, branded}` | onboard.js 门禁恒 false，key_setup 引导不触发 |
| `GET /api/version` | `{current_version, version, available_update, changelog}` | `{current, latest, needs_update, launcher, cli_command}` | version/store.js 更新提示失效 |

三个端点的修复均为"响应形状对齐"，不涉及存储格式、WS 协议、路由新增。crescent 仅用到已注册的 `get("")`，无新 HTTP 方法需求。

## 决策 [必填 - 含为什么]

1. **I-022：显式构造 orig 13 键响应，弃用 cfg.to_json()**。理由：(a) derive ToJson 省略 None 字段导致键缺失，且无法输出 branded/activated/expired/user_licensed 四个派生布尔；(b) 顺带消除 license_key 明文泄露——显式 `Json::object` 只放白名单键，是封堵泄露的最直接方式；(c) 与 fix-04 的"显式包装"决策一脉相承。键值来源：7 个字符串字段直取 Option（None → null，与 orig to_h 行为一致——orig 的 nil 也序列化为 null 且键保留）；`branded=is_branded()`、`activated=activated()`、`expired=expired(now_seconds())`、`user_licensed=user_licensed()`、`license_expires_at` 直取（current 存 ISO 字符串，orig 存 iso8601，格式兼容）。原 `POST /api/brand`、`/status`、`/config` 等其他 brand 端点不动。

2. **I-023（推荐方案，人工确认为开发前 gate）**：`GET /api/onboard/status` 在保留 `{completed, step, skipped}` 的基础上增补 `{needs_onboard, phase, branded}`：`needs_onboard = !(config.models 非空 && current_model() is Some(_))`，`phase = "key_setup"`（仅 needs_onboard=true 时输出），`branded = BrandConfig::load(...).is_branded()`。理由：与 orig 语义逐字段对齐，前端门禁零修改恢复；保留原三键不破坏现有消费者。**Gate**：issues 文档标注"需人工确认行为影响"——恢复门禁后，未配置模型的部署会重新弹出引导面板，需人工确认这是期望行为（orig 行为）而非干扰，确认后方可进入开发。soul_setup phase 不在本 spec 实现（orig 注释提及但当前路由分支未返回它，current 已有独立 `/api/onboard/skip-soul` 流程）。

3. **I-024（推荐方案，人工确认为开发前 gate）**：`GET /api/version` 对齐 orig 五键 `{current, latest, needs_update, launcher, cli_command}`，保留现有 `current_version/version/available_update/changelog` 四键兼容（纯新增键，低风险）。`latest` 复用 `fetch_latest_version()` + `version_is_newer()`，**增加进程内 TTL 缓存（1 小时，对齐 orig fetch_latest_version_cached）**，避免每次 GET 都打 GitHub；远端失败时 `latest=null, needs_update=false`。`cli_command` = branded 且 package_name 非空时取 package_name，否则 `"mbopenclacky"`（orig 回落 "openclacky"，本项目二进制名不同，属有意偏差）。`launcher` = 环境变量 `CLACKY_LAUNCHER`（保持与 orig 相同的变量名，部署脚本可复用）缺省 `"cli"`。**Gate**：issues 文档标注"需确认是否有意重设计"——current 把远端检查放在 POST /api/version/check 可能是有意避免 GET 触发外网请求；需人工确认"GET 带缓存的远端检查"可接受后再开发。若确认为有意重设计，则改为只补 `current` 键并让前端适配（备选方案，不在本 spec 默认路径）。

4. **MoonBit 约束检查**：不涉及运行时动态加载 trait（AOT 约束不触发）；不新增路由方法，crescent 既有 `get("")` 足够，未声称任何 crescent 能力缺失；不涉及 FFI/C stub。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_brand.mbt` | 修改 | `handle_brand_config` 改为显式构造 orig 13 键 JSON（白名单，不再输出 license_key 等内部字段） |
| `lib/web/handlers_onboard.mbt` | 修改 | `handle_onboard_status` 增补 needs_onboard/phase/branded 三键（需读 server_ref.val.config，签名从 `_server_ref` 改为 `server_ref`） |
| `lib/web/handlers_version.mbt` | 修改 | `handle_version_info` 增补 current/latest/needs_update/launcher/cli_command；新增进程内 latest 缓存（Ref + TTL） |
| `lib/web/handlers_brand_wbtest.mbt` 或新建白盒测试 | 新建/修改 | 13 键存在性、派生布尔正确性、license_key 不泄露断言 |
| `lib/web/handlers_onboard_wbtest.mbt` 或新建 | 新建/修改 | needs_onboard 两分支（有/无模型配置）断言 |
| `lib/web/handlers_version_wbtest.mbt` 或新建 | 新建/修改 | 五键存在性、缓存 TTL 行为（注入时间源或短 TTL）断言 |

### 不涉及文件

- 前端 JS 零修改（字段补齐后 fork 前端原生消费，与 fix-04 同一原则）
- `lib/web/server.mbt`（三个端点路由已注册，无路由变更）
- `lib/brand/config.mbt`（BrandConfig 结构、load/save、to_h 均不动；仅为 handler 换响应构造方式）
- `lib/web/template_processor.mbt`（仅用 `{{BRAND_NAME}}`，与响应形状无关）
- `POST /api/brand`、`/api/brand/status`、`/api/brand/activate`、`/api/brand/skills*`（I-022 只覆盖 GET /api/brand 形状）
- `POST /api/version/check`、`POST /api/version/upgrade`（现有形状保留，不属 I-024）
- 相邻 issue：I-014~I-021（billing/config/skills/creator 键名）、I-025（sessions/:id/skills 空数组）、I-032~I-040（P3 批），均不纳入
- onboard 的 device flow、complete、skip-soul 等其他端点

## 实施计划 [必填]

### 任务包 0：人工确认 gate（开发前，0.5 天）
- 向维护者确认 I-023：恢复 `needs_onboard` 门禁（orig 行为）是否符合预期——未配置模型的部署将重新弹引导面板
- 向维护者确认 I-024：GET /api/version 带 1 小时缓存的远端检查是否可接受，还是有意重设计走备选方案
- 两项确认结论记入本 spec 变更记录；任一被否决则对应任务包替换为备选方案或撤项

### 任务包 1：I-022 /api/brand 13 键（0.5 天）
- `handle_brand_config` 改为显式 `Json::object` 输出 13 键，派生布尔用 `now_seconds()` 辅助函数（文件内已有）
- 白盒测试：空配置下 13 键全在（值为 null/false）；种植 license_key 断言响应不含该键

### 任务包 2：I-023 /api/onboard/status 门禁字段（0.5 天，gate 通过后）
- `handle_onboard_status` 读 `server_ref.val.config`，补 needs_onboard/phase/branded
- 白盒测试：models 为空 → needs_onboard=true + phase="key_setup"；models 非空且有 current → needs_onboard=false

### 任务包 3：I-024 /api/version 更新检查字段（0.5 天，gate 通过后）
- 新增模块级 latest 缓存（`Ref[(String?, Int)]` + 3600s TTL），GET 命中缓存则不打外网
- `handle_version_info` 补五键；cli_command 取 brand package_name 回落 "mbopenclacky"；launcher 读 `CLACKY_LAUNCHER` 缺省 "cli"
- 白盒测试：五键存在；远端失败路径 latest=null/needs_update=false

## 验收标准 [必填]

- [ ] `GET /api/brand` 返回 orig 13 键（空配置下值为 null/false 但键恒在），且任何配置下不含 `license_key`
- [ ] `GET /api/onboard/status` 含 `needs_onboard/branded`，无模型配置时 `needs_onboard=true, phase="key_setup"`；保留 `completed/step/skipped`
- [ ] `GET /api/version` 含 `current/latest/needs_update/launcher/cli_command`，连续两次 GET 仅触发一次远端请求（缓存生效）
- [ ] 前端 brand 面板（logo/主题色/product_name）、onboard 门禁、version 更新提示在同源前端下行为与 orig 一致（Playwright 或手工复测）
- [ ] `moon check` 0 errors（lib/web）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| I-023 恢复门禁改变现网行为（未配置模型用户被弹引导） | 中 | 人工确认 gate（任务包 0）；保留 completed/step/skipped 三键不破坏现有消费者 |
| I-024 GET 触发外网请求被认定为有意重设计 | 中 | 人工确认 gate；缓存 TTL 对齐 orig 1 小时；远端失败静默降级 latest=null |
| I-022 改显式构造后遗漏某字段消费方 | 低 | 白名单 13 键为 orig 全集超集方向对齐；derive 原输出的内部字段（license_key 等）本就不应暴露 |
| 进程内缓存导致升级后 latest 陈旧 | 低 | TTL 1 小时与 orig 一致；POST /api/version/check 保持实时检查不受缓存影响（实现时明确两路径） |
| derive ToJson 省略 None 的行为跨 core 版本变化 | 低 | 修复后不再依赖 derive 行为，显式构造即免疫 |

## 依赖关系 [必填]

- **前置依赖**：fix-06（按任务指派；fix-01~fix-05 已归档于 `specs/completed/`，fix-06 起系列 spec 并行撰写中）。本 spec 三个端点修复本身在代码上与 fix-06 无文件级冲突（不同 handler 文件），依赖关系按指派记录
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | I-022 + I-023 + I-024 P2 系统信息 API 对齐 |
| 2026-07-24 | 审核修正：对抗性审核通过。逐条验证：handle_brand_config@handlers_brand.mbt:58-65 确认返回 cfg.to_json()（derive(ToJson)）；BrandConfig@config.mbt:6-20 含 license_key@:14 且 derive(ToJson) 确认安全泄露风险成立；handle_onboard_status@handlers_onboard.mbt:207-213 确认返回 {completed,step,skipped}（spec 写 :206 差 1 行）；handle_version_info@handlers_version.mbt:125-137 确认返回 {current_version,version,available_update:null,changelog:""}；GITHUB_LATEST_URL@:11+version_is_newer@:53 确认可复用；路由重复注册@server.mbt:311+632 确认。orig Ruby 逐行验证：api_brand_info@:2843 返回 brand.to_h 确认；api_onboard_status@:965-976 返回 {needs_onboard,phase?,branded} 确认（needs_onboard=!models_configured?）；api_get_version@:2940-2954 返回 {current,latest,needs_update,launcher,cli_command} 确认（latest=fetch_latest_version_cached 1h 缓存，cli_command=branded?package_name:"openclacky"，launcher=ENV["CLACKY_LAUNCHER"]||"cli"）。人工确认 gate（I-023 门禁恢复+I-024 GET 远端检查）已标注。无事实性错误。 | 对抗性审核 + 第一性原理校验 |
