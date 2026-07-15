# Web 前端组件补齐（code-editor / notify / sidebar / onboard / datepicker） · 增量 Spec

> **创建日期**: 2026-07-13
> **状态**: 讨论中
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