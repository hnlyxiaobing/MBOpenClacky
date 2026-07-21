# Web Parity 主控：受管 fork 策略与阶段依赖 · 增量 Spec

> **创建日期**: 2026-07-21  
> **状态**: 讨论中（draft，待对抗性审核）  
> **关联总览**: `docs/web_ui_replication_plan.md`（调查结论 + 三方案对抗性审查）  
> **关联历史 spec**: `docs/web_ui_comparison_report.md`（7-20 功能差距清单）  
> **来源差距**: Web UI 布局/功能与原项目结构性不一致（用户实测反馈）  
> **依赖**: 无；为 web-parity-01 ~ 05 的公共前置  
> **灰度 key**: 无

## 问题描述 [必填]

当前项目 Web UI（web/mb MoonBit SPA）与原项目（Ruby openclacky）布局结构性不一致、大量按钮功能不可用。经 `docs/web_ui_replication_plan.md` 对抗性审查（可用性 35 / 易用性 25 / 可维护性 25 / 可扩展性 15 加权评分：受管 A 8.4 > 裸奔 A 7.4 > 并存 5.7 > 自研 4.4），确定采用**受管 fork 方案 A**：整体移植原项目静态前端，MoonBit 后端对齐其后端契约。本 spec 定义该方案的全局纪律、阶段拆解与依赖关系；各阶段细则见 01~05 子 spec。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 原项目前端是纯静态零构建资产 | `find D:/MoonBit/openclacky/lib/clacky/web -type f \| wc -l`、`du -sh` | 87 文件、3.0MB，手写 JS/CSS/HTML + vendor 库 | 确认可直接拷贝 |
| 原项目前端规模 | `wc -l`（顶层 *.js/css/html + components/core/features/ext_ui） | 27,601 + 10,683 ≈ 38,000 行 | 自研对齐不可行 |
| web/mb 已投入规模 | `find web/mb/main -name '*.mbt' \| xargs wc -l` | 15,289 行（归档前测量） | 沉没成本，不改结论 |
| 上游活跃度 | `git log --since="3 months ago" --oneline`（openclacky 仓库） | 768 提交，其中 300 触及 `lib/clacky/web` | 必须钉版本，不追 master |
| 上游同步基线 | `git describe --tags`（openclacky 仓库） | `v1.4.0-19-g042772e`（HEAD=042772e0c8cb，v1.4.0 后 19 提交） | 基线 = v1.4.0 tag（或本机 HEAD，实施时决策，见决策 2） |
| 原项目许可证 | `head LICENSE.txt`（openclacky） | MIT；本仓库 LICENSE 已声明衍生 | 资产复制合规 |
| 模板占位符 | `grep -n '{{BRAND_NAME}}\|{{EXT_SCRIPTS}}' web/index.html`（原项目） | 6, 38, 1279（BRAND_NAME）、1540（EXT_SCRIPTS） | P0 服务端替换点确认 |
| 本项目静态服务能力 | 读 `lib/web/static_server.mbt` | `process_template` 已存在；`spa_fallback` :132-152；MIME 表 :21-45 | 可复用改造 |
| 本项目鉴权 | 读 `lib/web/middleware/auth.mbt`、`lib/web/server.mbt:142-162` | Bearer/query/cookie 三携带 + 限流已有；loopback 绕过需 `MBOPENCLACKY_DEV_ALLOW_LOOPBACK=1`（server.mbt:147-156） | 缺"默认放开 loopback" |
| 归档动作已完成 | `ls web/ web/legacy_mb/` | web/{index.html, dist, legacy_mb/{mb, css, js}} | 本 spec 创建前已执行（用户指令） |
| 归档后构建引用 | `grep "web/mb" moon.mod` → 已改 `web/legacy_mb` | moon.mod:27 已更新 | 完成；`moon check` 报 `Cannot load the core file`，用原 exclude 值复测同错，确认为预存工具链环境故障，与本次改动无关 |

### 详细分析

- 原前端后端契约（120 REST 端点 + 单 WS `/ws` + loopback 免鉴权 + 两个模板占位符）完整清单见 `docs/web_ui_replication_plan.md` 第一节。
- 本项目路由唯一事实来源：`lib/web/server.mbt` `build_app()`（:130-616）；`lib/web/router.mbt` 已废弃。
- 当前 `web/index.html` 引用 `mb/index.js`、`css/`、`js/lib/`，归档后 7071 首页处于**预期内的破损状态**，由 P0（web-parity-01）恢复。

## 决策 [必填 - 含为什么]

1. **采用受管 fork 方案 A，废弃自研对齐（方案 B）**：parity 在 B 路径上渐进不可达（剩余量 ≥ 已投入的 15.3k 行，且上游以 ~3 UI 提交/天移动）；rabbita 0.12.4 + `extern "js"` 手拼 DOM 是内生缺陷源。
2. **同步基线钉 v1.4.0 tag，不追 master**：上游每天 ~3 个 UI 提交，追 master = 同步成本失控；release tag 是上游自己定义的稳定性边界。本机检出的 HEAD（v1.4.0+19）与 v1.4.0 的 19 个提交差异在实施 P0 时 `git diff v1.4.0..HEAD -- lib/clacky/web` 评估，若含 web 修复则以 HEAD 为基线并在 `web/UPSTREAM_SYNC.md` 记录精确 commit hash。
3. **五条受管纪律**（对抗性审查产出，全部子 spec 必须遵守）：
   - 钉版本：按 tag 同步，节奏季度级或按上游 minor 版本；
   - 零修改：前端代码唯一永久 delta = 品牌资产（logo/favicon/产品名，法律必需）；任何其它本地改动记入 `web/PATCHES.md` 并随同步重放，清单长度趋向 0；
   - 裁剪而非半残：MoonBit AOT 做不到的扩展面板（meeting/ext-studio 等依赖 Ruby 运行时 handler 的）经 `{{EXT_SCRIPTS}}` 不注入整体裁掉，UI 不留死按钮；
   - 独有能力走扩展缝：`/api/ext/*` + `{{EXT_SCRIPTS}}` 注入，不改 fork 前端；
   - legacy 退役线：`web/legacy_mb/` 在 P2 验收通过后删除（见 web-parity-05）。
4. **后端 API 以原契约为公共 API 演进**：本项目自设路径（`/api/models`、`/api/schedules`、`/api/git/*` 等）在 P3 逐簇对齐后于 P4 删除；保留 SSE 端点至 P4（无消费者后移除）。
5. **品牌 delta 最小化**：`{{BRAND_NAME}}` 服务端替换为 "MBOpenClacky"；logo/favicon 替换资产在 P0 以占位 SVG 先行，正式设计资产后补。

<!-- MoonBit 约束检查：
- AOT 约束：本方案核心收益之一就是绕开"运行时加载扩展无法实现 trait"——扩展面板裁剪/壳命令化，见 web-parity-05。
- crescent 路由：原前端不用 SSE，crescent 不支持 chunked 的短板被规避；WS 已有实现（lib/web/broadcast/hub.mbt）可复用。
- FFI：不涉及。
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `specs/draft/2026-07-21_web-parity-0*.md` | 新建 | 本系列 6 个 spec |
| `web/legacy_mb/` | 已归档 | web/mb、web/css、web/js 已移入（本 spec 创建前执行） |
| `moon.mod` | 已修改 | exclude 更新为 `web/legacy_mb` |

各阶段具体改动见子 spec 的"改动范围"节。

### 不涉及文件

- `lib/agent/`、`lib/tui/`（本系列只动 web 层）
- `web/legacy_mb/` 内部代码（只归档/退役，不维护）

## 实施计划 [必填]（阶段拆解与依赖）

```
00 主控（本 spec）
 └─ 01 P0 资产移植 + 静态服务 + 鉴权放开        ← 无前置，立即可做
     └─ 02 P1 WS /ws 协议 + 会话核心 REST       ← 依赖 01（前端已就位可实测）
         ├─ 03 P2 设置/Profile/记忆/技能/代理    ← 依赖 02（聊天主链路可用后）
         └─ 04 P3 次级面板簇（git/时光机/trash/  ← 依赖 02；与 03 可并行
                billing/backup/cron/channels/
                mcp/version/share/onboard/media）
             └─ 05 P4 扩展裁剪定案 + legacy      ← 依赖 03+04 验收通过
                退役 + 旧端点清理 + 文档收尾
```

- **关键路径**：01 → 02 → (03 ∥ 04) → 05。01 阻塞一切（首页不可用）；02 阻塞所有交互类验收。
- **每阶段验收门槛**（进下一阶段前必须全绿）：该阶段 spec 的验收标准 + Playwright 探针（`.test_web_compare/` 模式，7070 vs 7071 同视口截图/DOM 探针）+ `moon check` 0 errors + `moon test` 相关包通过。
- 任务包粒度、文件清单、预估见各子 spec。

## 验收标准 [必填]（系列级终验）

- [ ] 原前端**零修改**运行在本项目后端（唯一 delta = 品牌资产 + `web/PATCHES.md` 清单且清单为空或仅品牌项）
- [ ] 1440x900 视口下首页/会话页/新建会话/设置五分区截图与原项目视觉一致（允许品牌差异）
- [ ] 核心闭环全通：建会话（agent/目录/模型）→ 发消息 → WS 实时回复与工具调用 → 中断 → 重命名/置顶/删除/导出 → 附件上传 → 主题/语言切换
- [ ] UI 上无死按钮：所有可见入口要么功能可用，要么经 `{{EXT_SCRIPTS}}` 裁剪后不可见
- [ ] `web/legacy_mb/` 已删除；自设旧端点已清理；`codemaps/web.md`、README、THIRD_PARTY_LICENSES 已更新
- [ ] `moon check` 0 errors；`moon test` 全量通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| fork 漂移：上游持续演进，本地 fork 过时 | 中 | 钉 tag + 季度同步；零修改纪律把同步成本压到"拷贝+回归" |
| 本地补丁累积导致同步成本指数上升 | 高 | `web/PATCHES.md` 强制登记；任何补丁需 reviewer 确认无法走扩展缝 |
| WS 事件字段与 `ws-dispatcher.js` 期望不完全同构，渲染静默异常 | 高 | P1 以 `ws-dispatcher.js:140-441` 为权威清单逐事件核对；历史/实时事件共用同一序列化函数 |
| Windows 路径语义（盘符、越界检查）与原前端假设不符 | 中 | P1 `/api/dirs`、P3 文件端点按 `http_server.rb:4354-4467` 行为对齐，Windows 实测 |
| 会话数据格式与 SessionSummary 字段（session_registry.rb:517-543）不兼容 | 高 | P1 首批任务即做字段映射表与兼容层 |
| 工具链故障（moon check 报 core file 缺失）阻塞验证 | 中 | 预存环境问题，与本系列无关但阻塞验收；需先修复本机 moon 安装（重跑安装脚本或修复 ~/.moon/lib） |

## 依赖关系 [必填]

- **前置依赖**：无（`docs/web_ui_replication_plan.md` 调查已完成；归档已执行）
- **后置依赖**：web-parity-01 ~ 05 全部依赖本 spec 的纪律与基线决策

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-21 | 初始版本：受管 A 方案主控，五条纪律，01~05 阶段拆解与依赖图；同步基线 v1.4.0-19-g042772e 经 `git describe` 验证 | 用户确认按受管 A 方案拆解开发方案 |
| 2026-07-21 | 审核修正：8 项对抗性检查全通过（文件存在/函数名/路由行号/AOT 约束/crescent API/模板完整/无过工程化）；原项目 http_server.rb（lib/clacky/server/，6970 行）、ws-dispatcher.js（472 行）存在确认；moon.mod exclude 已更新为 web/legacy_mb | 对抗性审核 + 第一性原理校验 |
