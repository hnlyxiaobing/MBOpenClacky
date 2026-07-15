# Web 前端组件补齐（code-editor / notify / sidebar / onboard / datepicker） · 增量 Spec

> **创建日期**: 2026-07-13
> **状态**: 已完成（2026-07-15 归档）
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G6（P1 重要功能差距）
> **关联历史**: `specs/completed/2026-07-09_web-frontend-panels-completion.md`（面板已补齐）
> **来源差距**: G6 — Web 前端组件（code-editor / notify / sidebar / onboard / datepicker）
> **依赖**: G4（feature-based 架构迁移，完成后才能合理放置组件）

## 问题描述

原项目 `web/components/` 包含 5 个关键前端组件，当前项目完全缺失。差距分析中它们被标记为影响代码编辑、通知、导航、引导、日期选择等核心交互功能。

| 组件 | 原项目规模 | 功能 |
|------|-----------|------|
| code-editor | CodeMirror 集成 | 代码编辑器（技能/扩展开发） |
| notify | 通知系统 | toast/alert 通知 |
| sidebar | 侧边栏导航 | 功能面板导航 |
| onboard | 引导流程 | 新用户 onboarding 步骤 |
| datepicker | 日期选择器 | 日期选择 UI |

## 现状分析

- 当前 `web/js/` 中无 `components/` 目录。
- **通知功能**：`web/js/notifications.js`（3,097 行）已实现完整的 `NotificationManager`，包含 toast UI 渲染（4 种类型：success/error/warning/info）、自动消失（success/info 3 秒）、手动关闭按钮、堆叠管理。**已具备 UI 渲染能力**，不是仅"数据层"。无需新建 notify 组件，但可重构为更通用的 `App.showNotification()` 接口（已存在）。
- **侧边栏**：`web/js/app.js` 的 `bindEvents()` 中有基础导航逻辑（`navModules` 数组映射按钮 -> 视图 -> 模块），侧边栏折叠/展开仅为 CSS class toggle。无独立 sidebar 组件。
- **引导流程**：`web/js/onboard.js` 存在，包含 onboard 步骤逻辑。
- **代码编辑器**：完全缺失。`chat.js` 的 `renderMarkdown` 已集成 highlight.js 做代码高亮，但无编辑能力。
- **日期选择器**：完全缺失。当前无使用场景需要日期选择器（schedules 用原生 input）。

## 决策

1. **组件放置在 `web/js/components/` 目录**：对齐原项目结构。**不依赖 G4 完成**--组件可独立开发放置在 `components/` 目录，feature-based 迁移后再调整引用路径。
2. **code-editor 用 CodeMirror 6**：原项目用 CodeMirror 5，本项目用 CodeMirror 6（当前稳定版本），通过 CDN 引入。**注意**：与 G15（vendor 库集成）存在重叠，G15 负责 CodeMirror 库的引入和配置，本 spec 的 code-editor 组件封装 G15 提供的底层能力。建议 G15 先行引入 CodeMirror 库，本 spec 再封装组件。
3. **notify 不新建，重构现有 `notifications.js`**：`NotificationManager` 已具备完整 UI 能力。仅需重构为更通用的组件接口（`Notify.show(message, type)`），并支持 Promise 化的确认对话框。
4. **sidebar 从 app.js 抽取**：将 `bindEvents()` 中的 `navModules` 数组和 `showView()` 逻辑抽取为独立组件，支持折叠/展开和高亮。
5. **onboard 组件化为步骤向导**：在现有 `onboard.js` 基础上，增加步骤向导 UI（步骤 1-4），状态驱动，支持前进/后退/跳过。
6. **datepicker 降优先级**：当前无明确使用场景（schedules 用原生 `<input type="date">`）。如无面板明确需求，可推迟到后续迭代。

## 改动范围

- **涉及文件**：
  - 重构 `web/js/notifications.js` -> `web/js/components/notify.js`（已有 UI 能力，重构接口）
  - 新增 `web/js/components/sidebar.js`
  - 修改 `web/js/onboard.js` -> 增加步骤向导 UI（或新增 `web/js/components/onboard-wizard.js`）
  - 新增 `web/js/components/code-editor.js`（依赖 G15 引入 CodeMirror 库）
  - ~~新增 `web/js/components/datepicker.js`~~（降优先级，推迟）
  - 修改 `web/js/app.js`（sidebar 引用迁移、notify 接口对接）
- **不涉及**：后端 API、TUI、Extension 框架
- **依赖**：code-editor 依赖 G15（vendor 库集成）先引入 CodeMirror；其他组件无硬依赖

## 实施计划（任务包切分）

1. **notify 组件**：toast 通知（success/error/warning/info）+ 自动消失 + 堆叠管理。
2. **sidebar 组件**：从 app.js 抽取导航逻辑，支持折叠/展开，高亮当前面板。
3. **onboard 组件**：步骤向导（步骤 1-4），状态驱动，支持前进/后退/跳过。
4. **datepicker 组件**：原生 date input + 自定义样式 + fallback。
5. **code-editor 组件**：CodeMirror 6 集成，语法高亮，行号，主题切换。
6. **集成验证**：各组件在对应面板中功能正常。

## 验收标准

- [ ] 5 个组件均实现且可独立使用
- [ ] notify 组件支持 4 种类型 toast，自动消失
- [ ] sidebar 组件支持折叠/展开，面板切换正常
- [ ] onboard 组件步骤向导完整（4 步）
- [ ] datepicker 组件在各浏览器中可正常选择日期
- [ ] code-editor 组件支持语法高亮和行号
- [ ] 现有功能不回归（通知、导航、引导流程正常）

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| CodeMirror 6 CDN 加载失败 | 中 | 提供 fallback textarea |
| sidebar 组件化后现有面板引用断裂 | 中 | 渐进式迁移，旧引用保留到新组件稳定 |
| datepicker 跨浏览器兼容 | 低 | 优先用原生 `<input type="date">`，仅在不支持的浏览器启用 polyfill |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G6，P1 重要功能 |
| 2026-07-13 | 审核修正：修正"notifications.js 仅为数据层"的错误描述（实际已有完整 toast UI）；修正 G4 依赖关系为软依赖（组件可独立开发）；标注 code-editor 与 G15 的重叠关系（G15 先引入库，本 spec 封装组件）；datepicker 降优先级（当前无明确使用场景）；修正 notify 决策为重构现有代码而非新建 | 对抗性审核 + 第一性原理校验 |

## 开发前校准分析（2026-07-15）

> 在编写任何代码前，对 `web/` 目录做了严格实读校准。结论：**本 Spec 描述的旧架构（`web/js/*.js` vanilla）已不存在，前端已完全迁移到 MoonBit + `rabbita` 框架（`web/mb/main/*_cell.mbt`）**。因此大部分决策需按当前架构重新映射。

### 现状 vs Spec 决策对照

| Spec 组件 | Spec 计划（`web/js/...`） | 当前架构实读结果 | 校准结论 |
|-----------|--------------------------|------------------|----------|
| **notify** | 重构 `notifications.js` → `components/notify.js` | 已是 rabbita cell：`web/mb/main/notification_cell.mbt`，含 4 类 toast + 自动消失 + 堆叠；通过 `app_notify` / `on_app_notify`（`bridge.mbt`）以 CustomEvent 解耦 | ✅ **已完成**，无需开发 |
| **sidebar** | 从 `app.js` 抽取导航逻辑 | 已是 rabbita：`bootstrap.mbt` 生成 sidebar HTML，`shell_cell.mbt` 负责路由 / 绑定 `js_bind_nav_buttons` / 折叠展开 | ✅ **已完成**，无需开发 |
| **onboard** | 组件化为步骤向导（4 步） | 已是 rabbita cell：`web/mb/main/onboard_cell.mbt`，3 步向导（welcome → configure → complete），状态驱动 + 前进/后退/跳过，对接 `/api/onboard/*` | ✅ **已完成**（实际为 3 步，功能等价） |
| **code-editor** | 新建 `components/code-editor.js`（CodeMirror 6） | `web/` 下无任何编辑器；`skills_cell.mbt` 的技能内容编辑器是纯 `<textarea>` | ❌ **唯一真实缺口** → 本次开发 |
| **datepicker** | 原生 date input + 自定义样式 | 当前无使用场景（`schedules_cell.mbt` 已用原生 `<input type="date">`） | ⏸ 维持 Spec 自身决策：降优先级，推迟 |

### 校准后开发方案（第一性原理）

- 仅 **code-editor** 需要新开发。其余 4 个组件在 rabbita 中已存在且功能达标，强行"重建"会引入回归风险，故不重复实现。
- code-editor 的集成落点遵循当前 rabbita 模式，而非旧 `components/` 目录：
  1. **加载层**：`web/mb/public/editor.js`（ES module，从 esm.sh CDN 引入 CodeMirror 6 + `@codemirror/lang-markdown` + `@codemirror/theme-one-dark`）。
  2. **FFI 桥接**：`bridge.mbt` 新增 `cm_set_doc(id, value)`，调用 `window.MBEditor.setDoc`。
  3. **组件封装**：`web/mb/main/code_editor.mbt` 提供 `code_editor_host(id, ta_id, value, on_change)`，渲染一个 `code-editor-host` <div> + 一个隐藏的、模型绑定的 <textarea>。
  4. **集成点**：`skills_cell.mbt` 的 `skills_editor_area` 用 `code_editor_host` 替换原 `<textarea>`；CodeMirror 编辑内容实时镜像回 <textarea>，复用既有 `EditorContentChanged` 更新回路（单一数据源）；CDN 失败时 <textarea> 自动作为 fallback 可见。
  5. **挂载时机**：`editor.js` 用 `MutationObserver` 监听 `code-editor-host` 节点出现即挂载，并对被 re-render 移除的实例自动 `destroy`，规避 rabbita 声明式重渲染与命令式 CodeMirror 的生命周期冲突。
- 入口 HTML（`web/index.html` 与 `web/mb/public/index.html`）引入 `editor.js`；CSS（`.code-editor-host`）补进 `web/css/style.css` 与 `web/mb/public/styles.css`。

### 验收映射

- [x] notify / sidebar / onboard：已在 rabbita 中满足 Spec 验收标准（无需改动）。
- [x] code-editor：CodeMirror 6 集成，Markdown 语法高亮 + 行号（basicSetup）+ oneDark 主题；CDN 失败有 textarea fallback。
- [x] 现有功能不回归：技能编辑器的 `on_change` 回路、保存/关闭逻辑保持不变。
- [ ] datepicker：按 Spec 决策维持推迟。

### 变更记录（本次）

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-15 | 开发前校准：确认前端已迁移到 rabbita，notify/sidebar/onboard 已实现，仅 code-editor 为缺口 | 代码实读 + 第一性原理，避免对过时 Spec 的机械执行 |
| 2026-07-15 | 新增 `web/mb/public/editor.js`（CodeMirror 6 加载器 + MutationObserver 自动挂载）、`bridge.mbt` 的 `cm_set_doc` FFI、`code_editor.mbt` 组件封装；`skills_cell.mbt` 集成；HTML/CSS 接入 | 实现 Spec 的 code-editor 功能目标，契合当前 rabbita 架构 |