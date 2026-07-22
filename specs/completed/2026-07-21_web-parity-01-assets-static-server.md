# Web Parity P0：原前端资产移植 + 静态服务与鉴权适配 · 增量 Spec

> **创建日期**: 2026-07-21  
> **状态**: 已完成（implemented 2026-07-21）  
> **关联总览**: `docs/web_ui_replication_plan.md`  
> **关联历史 spec**: `specs/active/2026-07-21_web-parity-00-managed-fork-master.md`（主控）  
> **来源差距**: Web UI 首页在归档后处于预期内破损状态；原前端未就位前一切后续工作无法实测  
> **依赖**: web-parity-00（纪律与基线决策）  
> **灰度 key**: 无

## 问题描述 [必填]

让 `http://localhost:7071/` 渲染出与原项目 `http://127.0.0.1:7070/` 一致的首页骨架（顶栏、侧栏、主题、i18n）。本阶段只做"静态资产 + 静态服务 + 鉴权放行 + 首屏数据探针端点"，不做任何交互功能；交互属 P1+。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 原前端资产清单 | `find D:/MoonBit/openclacky/lib/clacky/web -type f` | 87 文件：index.html、app.css、app.js、auth.js、i18n.js、sessions/settings/skills/theme/utils/ws/ws-dispatcher.js、components/、core/、features/（16 簇）、ext_ui/（4 panel）、vendor/（5 库）、品牌图（logo_nav_dark.png、favicon.svg、icon*.svg、apple-touch-icon-180.png）、design-sample.*、weixin-qr.html | 确认拷贝全集 |
| 模板占位符位置 | `grep -n '{{BRAND_NAME}}\|{{EXT_SCRIPTS}}'`（原 index.html） | BRAND_NAME: 6, 38, 1279；EXT_SCRIPTS: 1540 | P0 替换点 |
| 原服务端静态行为 | 读 `http_server.rb:348-382` | FileHandler 挂 `/`，`Cache-Control: no-store`；`/`、`/index.html` 做占位符替换；无 SPA fallback；`?pure=true` 时 EXT_SCRIPTS 置空 | 对齐目标明确 |
| 本项目静态服务 | 读 `lib/web/static_server.mbt` | `StaticServer::new("web")`（server.mbt:572）；`process_template` 已有；`spa_fallback` :132-152 存在（保留无害，原前端 hash 路由不触发）；MIME 表 :21-45 需核对 .svg/.png/.woff2 | 可复用改造 |
| 鉴权现状 | 读 `lib/web/middleware/auth.mbt:189-194`、`lib/web/server.mbt:142-162` | 白名单仅 `/health` + `GET /api/version`；loopback 绕过需 env `MBOPENCLACKY_DEV_ALLOW_LOOPBACK=1` | 需改为默认放行 loopback（对齐 http_server.rb:2941 行为） |
| 原前端首屏依赖 | 读 `web/auth.js`（原项目） | `Auth.check()` 探测 `GET /api/sessions?limit=1`，401 弹密码框；localhost 免鉴权后直接通过 | P0 必须提供该端点的原契约响应形状 |
| 本项目 `/api/sessions` 现状 | `lib/web/server.mbt:179` | 存在但响应形状为自设 | 需对齐 `{sessions, has_more, cron_count, latest_cron_updated_at}`（session_registry.rb:517-543 字段集） |
| 受归档影响的测试 | `grep web/ test/scenarios/web/` | `test/scenarios/web/static_js_accessible.json` 断言 `GET /mb/index.js` 200 + javascript MIME | 归档后必失败，本阶段重写为新前端探针 |
| 陈旧产物 | `ls web/dist` | web/dist/index.js 为旧编译产物（与 web/mb 源不一致，归档前已确认陈旧） | 本阶段删除 |
| i18n 无后端依赖 | 读原 `web/i18n.js` | en/zh 常量内嵌（2123 行），`X-Lang` 头仅用于服务端文案 | P0 无需实现 i18n 端点 |

### 详细分析

P0 是纯"通管道"阶段：资产落位 + 两个占位符替换 + no-store + loopback 免鉴权 + `/api/sessions` 探针形状。原前端对缺失的 `/api/*` 与 `/ext_ui/*` 有容错（扩展失败静默降级），首屏除 `/api/sessions` 外的 404 不阻塞渲染（部分面板显示空态，属 P1+ 范围）。

## 决策 [必填 - 含为什么]

1. **整集拷贝含 ext_ui 与 vendor**：87 文件全拷。理由：零修改纪律要求不挑拣；ext_ui 面板 JS 是否生效由 `{{EXT_SCRIPTS}}` 注入控制（P0 注空串 = 全裁），文件在盘上无害。
2. **`{{EXT_SCRIPTS}}` P0 恒替换为空串**：git/time_machine 面板依赖 P3 宿主 API，提前注入会留死按钮（违反"裁剪而非半残"）。
3. **`{{BRAND_NAME}}` 硬编码 "MBOpenClacky"**：brand 配置系统是 P3 范围；先硬编码，P3 接 `/api/brand/*` 时改为读配置。
4. **品牌图先行用原资产 + 登记**：logo_nav_dark.png/favicon.svg 等是 OpenClacky 品牌资产，法律上必须替换；P0 为求快速可视先拷贝，同步在 `web/PATCHES.md` 登记为"待替换品牌 delta"，正式 SVG 占位设计在 P4 前完成。
5. **loopback 免鉴权默认开**：对齐原项目（http_server.rb:2941：绑定 localhost 或请求来自 loopback 即放行）；保留 env 开关可关（`MBOPENCLACKY_DEV_ALLOW_LOOPBACK=0` 反向语义），非 loopback 绑定时仍要求 key。
6. **删除 `web/dist/`**：陈旧产物，避免与 fork 前端混淆。
7. **保留 `spa_fallback`**：原前端 hash 路由不依赖它，但对误输路径更友好，且删除无收益。

<!-- MoonBit 约束检查：纯静态服务 + 模板替换，不涉及 AOT/FFI/crescent 限制。-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `web/**`（87 文件） | 新建（拷贝） | 源：上游 v1.4.0 tag（或按 00 决策 2 评估后的 HEAD）`lib/clacky/web/`；覆盖现有 `web/index.html` |
| `web/UPSTREAM_SYNC.md` | 新建 | 记录同步基线（上游 repo、tag/commit hash、拷贝日期、文件数校验） |
| `web/PATCHES.md` | 新建 | fork 补丁登记簿，首条 = 品牌资产待替换 |
| `web/dist/` | 删除 | 陈旧产物 |
| `lib/web/static_server.mbt` | 修改 | HTML 响应做 `{{BRAND_NAME}}`/`{{EXT_SCRIPTS}}` 替换；全部响应加 `Cache-Control: no-store`；MIME 表补 .svg/.png/.woff/.woff2/.ico 核对 |
| `lib/web/middleware/auth.mbt` 或 `lib/web/server.mbt` | 修改 | loopback 请求默认免鉴权（可 env 关闭） |
| `lib/web/server.mbt`（`/api/sessions` handler） | 修改 | GET 响应形状对齐 `{sessions:[SessionSummary], has_more, cron_count, latest_cron_updated_at}`；支持 `limit`（≤50，默认 20）、`before`、`q`、`type`、`exclude_type` 参数 |
| `test/scenarios/web/static_js_accessible.json` | 重写 | 改为探针：`GET /` 200 且含 `id="top-header"` 与已替换的品牌名（无 `{{BRAND_NAME}}` 残留）；`GET /app.js` 200 + javascript MIME + no-store 头 |
| `codemaps/web.md` | 修改 | 前端架构段更新为 fork 资产 + 静态服务 |
| `THIRD_PARTY_LICENSES.md` | 修改 | vendor 库来源改为 `web/vendor/*`（原前端自带），删除 `web/js/lib` 条目 |

### 不涉及文件

- `web/legacy_mb/`（仅归档，不动）
- `lib/web/sse/`、`lib/web/broadcast/`、`lib/web/handlers*.mbt` 聊天链路（P1）
- 任何 `/api/ext/*`、`/ext_ui/*` 路由（P0 让其自然 404，前端容错）

## 实施计划 [必填]

### 任务包 1：资产落位（0.5 天）
- 评估 `git diff v1.4.0..HEAD -- lib/clacky/web`（上游仓库）定基线；拷贝 87 文件到 `web/`；删 `web/dist/`；写 `UPSTREAM_SYNC.md`/`PATCHES.md`。

### 任务包 2：静态服务适配（1 天）
- `static_server.mbt`：占位符替换（BRAND_NAME="MBOpenClacky"、EXT_SCRIPTS=""）、no-store、MIME 核对补全；`?pure=true` 透传语义（EXT_SCRIPTS 恒空，行为等价）。

### 任务包 3：鉴权与首屏探针（1 天）
- loopback 默认免鉴权；`/api/sessions` 响应形状对齐 + SessionSummary 字段映射表（对照 session_registry.rb:517-543：id/name/working_dir/status/created_at/updated_at/total_tasks/total_cost/cost_source/error/model/permission_mode/source/agent_profile/pinned/latest_latency，缺字段先给缺省值并登记 TODO 到 P1）。

### 任务包 4：测试与文档（0.5 天）
- 重写 static_js_accessible.json；更新 codemaps/web.md、THIRD_PARTY_LICENSES.md；Playwright 首屏对比截图（7070 vs 7071）。

## 验收标准 [必填]

- [ ] `GET /` 返回的 HTML 含 `id="top-header"`、品牌名 "MBOpenClacky"、无 `{{` 占位符残留、带 `Cache-Control: no-store`
- [ ] 浏览器打开 7071：顶栏（侧栏开关/logo/搜索/分享/主题切换）、侧栏骨架渲染，与原项目 7070 同视口截图布局一致（允许 logo 差异）
- [ ] 中文界面可用（localStorage `clacky-lang=zh` 后 data-i18n 生效）
- [ ] 亮/暗主题切换生效（`data-theme` 属性 + localStorage `clacky-theme`）
- [ ] loopback 访问无密码框；`GET /api/sessions?limit=1` 返回原契约形状
- [ ] Console 无 JS 解析错误（扩展/API 404 导致的功能降级提示可接受）
- [ ] `test/scenarios/web/` 探针全 PASS；`moon check` 0 errors（lib/web）；`moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| SessionSummary 字段缺口导致侧栏渲染异常（如 7-20 报告的日期占位符 bug） | 中 | 缺字段给类型正确的缺省值；渲染异常项登记 P1 修复 |
| 品牌资产未及时替换即对外发布 | 中（法律） | `web/PATCHES.md` 首条登记 + 系列级终验勾选 |
| vendor 库与 legacy `web/js/lib` 版本混淆 | 低 | legacy 已归档隔离；THIRD_PARTY_LICENSES 同步改 |
| 上游 HEAD 与 v1.4.0 的 19 提交含 web 修复但未打 tag | 低 | 任务包 1 先评估 diff 再定基线，记录 hash |

## 依赖关系 [必填]

- **前置依赖**：web-parity-00（纪律/基线）；归档已完成
- **后置依赖**：web-parity-02（P1）在本阶段前端就位后才能实测 WS/REST 对齐

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-21 | 初始版本：资产 87 文件、占位符位置、鉴权现状、受影响测试均经 grep/读码验证 | 受管 A 方案 P0 落地 |
| 2026-07-21 | 审核修正：交叉引用 draft→active；8 项对抗性检查通过（StaticServer::new :572 精确、process_template 存在、spa_fallback :132、handle_websocket :636、test 文件存在确认）；行号微偏差属参考信息 | 对抗性审核 + 第一性原理校验 |
