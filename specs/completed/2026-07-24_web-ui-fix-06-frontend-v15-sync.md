# 前端基线 v1.4.0 → v1.5.0 同步 · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 讨论中  
> **关联总览**: `docs/web-ui-gaps.md` / `docs/web-ui-issues.md`  
> **关联历史 spec**: `specs/completed/2026-07-22_web-replication-02-asset-migration.md`（v1.4.0 全量导入）  
> **来源差距**: G-001 - 前端基线落后原项目一个大版本（v1.4.0 vs v1.5.0，P1）  
> **依赖**: 无（本批次 fix-06 ~ fix-20 的第一份，其余全部以本 spec 的产出为验收基准）

## 问题描述 [必填]

当前 `web/` 前端资产是上游 openclacky **v1.4.0** 的托管 fork（2026-07-22 导入），原项目已发布 **v1.5.0**。这导致两类问题：

1. v1.5.0 前端的新面板/新交互（主题切换入口、`#reload-header`、新会话 Advanced options、Extensions Brand 过滤 tab、accent 色板等，见 `docs/web-ui-issues.md` "已核实为 version-skew" 一节）在当前项目整体缺失。
2. 后续所有 API 契约对齐 spec（fix-07 ~ fix-20）的验收基准是"前端能正常消费"，而前端本身落后一个版本——契约对齐做到一半前端又升级，会造成返工。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "当前基线为 v1.4.0" | 读 `web/UPSTREAM_SYNC.md` 第 7 行 | `Baseline tag: v1.4.0` | 确认 |
| "原项目已 v1.5.0" | `cat D:/MoonBit/openclacky/lib/clacky/version.rb` | `VERSION = "1.5.0"` | 确认 |
| "fork 采用托管 fork 流程" | 读 `web/UPSTREAM_SYNC.md` Sync Procedure | 6 步 checklist（fetch/diff/rsync/补丁/回归/记录） | 确认存在现成流程 |
| "web/ext_ui/ 为本项目独有新增" | `docs/web-ui-gaps.md` 有意差异备忘 + `Glob "web/ext_ui/**"` | ext_ui 目录存在（git、time-machine 面板） | 确认，同步时必须保留 |
| "品牌资产为本地替换" | 读 `web/UPSTREAM_SYNC.md` Current Status + `web/PATCHES.md` P0-001 | **审核修正：声称错误**。PATCHES.md 明确写 "currently using upstream brand assets verbatim"（上游原始资产，待替换），UPSTREAM_SYNC.md Current Status 也写 "upstream originals still in place - P0-001 active"。品牌资产尚未替换为 MBOpenClacky 专用资产，P0-001 仍为 Pending replacement 状态。rsync --exclude 仍然需要（保护 P0-001 占位状态不被覆盖），但理由应修正 | 修正：资产为上游原始资产（P0-001 Pending），非本地替换 |
| "PATCHES.md 有活跃补丁" | 读 `web/UPSTREAM_SYNC.md` 第 17 行 | P0-001（品牌占位）Active，P0-002 retired | 确认，同步后需重放 |

### 详细分析

`web/UPSTREAM_SYNC.md` 已定义完整的季度同步流程（rsync + `--exclude` 品牌资产 + 重放 `PATCHES.md` 补丁 + 回归测试），本 spec 不需要发明新流程，只需按既定流程执行一次 v1.5.0 同步。需要注意：

- 流程中的 rsync 示例**没有排除 `ext_ui/`**——v1.4.0 导入时 ext_ui 尚不存在或已处理，本次必须显式确认 `--delete` 不会删掉本项目独有的 `web/ext_ui/`（git、time-machine 面板）。
- `index.html` 冲突策略（保留 `id="top-header"` + `{{BRAND_NAME}}`/`{{EXT_SCRIPTS}}` 模板占位）需继续遵守，模板处理由 `lib/web/template_processor.mbt` 完成，后端零改动。
- 同步完成后，`docs/web-ui-issues.md` 中 "已核实为 version-skew 或有意差异" 一节列出的项应随升级消失，需重新核对两份清单并在回写时更新状态。

## 决策 [必填 - 含为什么]

1. **严格复用 `web/UPSTREAM_SYNC.md` 的既定 rsync 流程，不发明新流程**：流程本身经过 v1.4.0 导入验证，spec 的价值在于执行纪律（排除清单、补丁重放、回写），而非方案设计。
2. **排除清单在既有品牌资产之外，新增 `--exclude='ext_ui/'`**：`--delete` 会删除上游不存在的文件，`web/ext_ui/` 是本项目独有能力（`docs/web-ui-gaps.md` 明确记录），不排除会被静默删除。
3. **同步后立即重跑 web 对比核对清单，但不修后端**：核对结果回写 `docs/web-ui-gaps.md` / `docs/web-ui-issues.md`（标注哪些 Open 项已随版本升级消失），后端契约修复留给 fix-07 ~ fix-20，保持本 spec 单一职责。
4. **MoonBit 约束检查**：本 spec 只涉及 `web/` 静态资产与 Markdown 回写，不涉及 AOT/trait/crescent/FFI，无约束风险。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `web/**`（除排除项） | 修改 | rsync 同步 v1.5.0 上游资产 |
| `web/UPSTREAM_SYNC.md` | 修改 | 回写新基线 tag/commit/文件数/日期 |
| `web/PATCHES.md` | 修改 | 重放补丁后更新状态 |
| `docs/web-ui-gaps.md` | 修改 | 核对后更新 G-001 状态及受影响条目 |
| `docs/web-ui-issues.md` | 修改 | 核对后更新 version-skew 相关条目状态 |

### 不涉及文件

- `lib/**`、`cmd/**`：后端代码零改动。
- `web/ext_ui/**`：本项目独有面板，只保留不修改。
- fix-07 ~ fix-20 涉及的任何 API/WS 行为修复。

## 实施计划 [必填]

### 任务包 1：同步前盘点（预估 0.5 天）
- 克隆上游 v1.5.0 tag；`diff -rq` 对比 v1.4.0 基线与 v1.5.0，记录文件级 delta 清单。
- 盘点 `web/` 中本地新增/修改（`ext_ui/`、`PATCHES.md` 列出的补丁、品牌资产），形成排除与重放清单。

### 任务包 2：执行同步（预估 0.5 天）
- 按 UPSTREAM_SYNC.md 流程 rsync（品牌资产 + `ext_ui/` 加入 exclude）。
- 重放 `PATCHES.md` 活跃补丁；处理 `index.html` 合并（保留模板占位）。
- 更新 `UPSTREAM_SYNC.md`（tag=v1.5.0、commit hash、文件数、日期）。

### 任务包 3：回归与清单核对（预估 1 天）
- `moon check` + `moon test lib/web`；启动 server 跑 `docs/web-ui-test-plan.md` 的关键路径（会话、MCP、计费、设置面板）。
- 逐项核对 `docs/web-ui-issues.md` version-skew 一节，更新两份清单状态并回写。

## 验收标准 [必填]

- [ ] `web/UPSTREAM_SYNC.md` 基线记录为 v1.5.0，含 commit hash 与同步日期
- [ ] `web/ext_ui/`、`PATCHES.md` 补丁、品牌占位资产同步后完好
- [ ] `moon check` 0 errors；`moon test lib/web` 通过
- [ ] 关键面板（聊天/MCP/计费/设置）人工或 Playwright 走查无新增破版
- [ ] `docs/web-ui-gaps.md` G-001 标记 Done；version-skew 条目在两份清单中完成状态更新

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| rsync `--delete` 误删 `ext_ui/` 或补丁文件 | 高 | 同步前 git 工作区干净可回滚；exclude 清单写入执行记录 |
| v1.5.0 前端消费了当前后端没有的 API 字段 | 中 | 正是 fix-07 ~ fix-20 要解决的；本 spec 只做核对记录，不在此修 |
| 上游 v1.5.0 资产与模板占位冲突（index.html 结构变化） | 中 | 按 Conflict Resolution 表合并；`moon test lib/web` 覆盖 template_processor |
| vendor 库升级引入新第三方许可证 | 低 | 按流程重新审计 `THIRD_PARTY_LICENSES.md` |

## 依赖关系 [必填]

- **前置依赖**：无。
- **后置依赖**：fix-07 ~ fix-20 全部——这些 spec 均为 API/WS 契约对齐，验收标准是"前端正常消费"，必须在本 spec 完成、前端基线稳定后执行，避免双重返工。

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | G-001 起草本批次第一份 spec |
| 2026-07-24 | 审核修正：发现 1 个事实性错误并修正。品牌资产声称"本地替换"实际为上游原始资产（P0-001 Pending replacement，PATCHES.md 明确写 "currently using upstream brand assets verbatim"）。其余 5 项声称全部验证通过：v1.4.0 基线、v1.5.0 上游版本、6 步同步流程、ext_ui/ 独有新增（web-ui-gaps.md:81 确认）、P0-001 Active/P0-002 retired。模板完整，无 AOT/crescent/FFI 约束。 | 对抗性审核 + 第一性原理校验 |
