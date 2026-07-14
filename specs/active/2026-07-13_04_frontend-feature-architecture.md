# Web 前端 Feature-based 架构迁移 · 启动 Spec (IDEA_DOC)

> **创建日期**: 2026-07-13
> **状态**: 讨论中
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G4（P1 重要功能差距）
> **关联历史**: `specs/completed/2026-07-09_web-frontend-panels-completion.md`（Web 面板已补齐）
> **来源差距**: G4 - Web 前端 Feature-based 架构迁移
> **负责人**: TBD
> **依赖**: G6 依赖本 spec（组件放置在 feature 架构下）；G1 可独立于本 spec

## 核心目标

将 `web/js/` 当前 flat 结构（21 个 JS 文件平铺，共 6,831 行）迁移为原项目的 feature-based 架构：每个功能模块包含 `store.js`（状态管理 + API 封装）和 `view.js`（DOM 渲染 + 交互处理），实现关注点分离和可维护性提升。

## 现状分析（经代码验证）

- **21 个 JS 文件**平铺在 `web/js/` 下（共 6,831 行），无 `i18n/` 子目录（i18n 功能已整合到 `i18n.js` 中）
- **所有模块已使用 Plain Object 模式**（如 `const Chat = {...}`、`const App = {...}`），与原项目风格一致，迁移时无需改变模块模式
- **`app.js`（353 行）** 包含：统一 `API` 包装器（get/post/put/del）、`App` 主对象（初始化所有模块、`bindEvents` 导航逻辑、`showView` 面板切换、模态框管理、全局通知）
- **导航逻辑** 在 `app.js` `bindEvents()` 中，通过 `navModules` 数组映射按钮 ID -> 视图 -> 模块
- 当前各模块（如 `billing.js`、`channels.js`）混合了状态管理、API 调用和 DOM 渲染，无 store/view 分离

## 关键能力

- **Feature-based 目录结构**：`web/js/features/<module>/store.js` + `view.js`，每个模块独立管理状态和视图。
- **store.js 统一模式**：状态管理（列表、详情、加载状态）、API 调用封装（复用 `app.js` 中已有的 `API` 包装器）、事件订阅（`WS.on`）。
- **view.js 统一模式**：DOM 渲染（`innerHTML` 或 `createElement`）、用户交互处理（click/submit 事件委托）、事件分发（`dispatchEvent` 或回调）。
- **渐进式迁移**：每次迁移一个功能模块，保持旧文件兼容，全部迁移完成后删除旧文件。
- **公共模块抽取**：`API` 包装器从 `app.js` 抽取为 `web/js/core/api.js`，各 store 复用。

## 明确不做

- 不引入前端框架（React/Vue/Svelte）（原因：保持零依赖，对齐原项目原生 JS 架构）。
- 不修改后端 API 契约（原因：store.js 封装现有 API 调用，不改变契约）。
- 不重写 UI 样式（原因：仅重构架构，不改变视觉呈现）。
- 不做 ws-dispatcher 集成（原因：G1 独立 spec，本 spec 仅迁移架构，架构支持后续集成）。

## 关键决策（含为什么）

1. **store/view 分离而非 MVC**：原项目用 store/view 模式，简单直接，不需要 controller 层（交互逻辑在 view 中）。
2. **每个模块独立文件，不合并打包**：保持开发调试友好，不需要构建工具链。
3. **渐进式迁移，旧文件保留到迁移完成**：降低风险，每个模块迁移后立即验证，不阻塞其他开发。
4. **store 用 Plain Object 而非 Class**：对齐原项目风格，当前代码已使用此模式，保持一致。
5. **`API` 包装器抽取为公共模块**：当前 `API` 定义在 `app.js` 中，迁移后各 store 需独立引用，抽取到 `web/js/core/api.js`。
6. **`app.js` 保留为应用入口**：`app.js` 瘦身为初始化协调器 + 模块注册，导航逻辑迁移到 `web/js/core/navigation.js`。
7. **迁移顺序按依赖和复杂度**：先迁移独立模块（brand/backup/trash/version），再迁移复杂模块（sessions/channels/billing/mcp），最后迁移核心模块（chat/workspace/settings）。

## 改动范围

### 涉及文件

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | `web/js/core/api.js` | 从 app.js 抽取 `API` 包装器 |
| 新建 | `web/js/core/navigation.js` | 从 app.js 抽取导航逻辑 |
| 新建 | `web/js/features/*/store.js` + `view.js` | 15+ 个功能模块迁移 |
| 修改 | `web/js/app.js` | 瘦身为初始化协调器 |
| 修改 | `web/index.html` | 更新脚本引用路径 |
| 删除 | 旧 flat 文件（迁移完成后） | 逐步删除 |

### 迁移模块清单

| 模块 | 当前文件 | 迁移目标 | 复杂度 |
|------|---------|---------|--------|
| backup | backups.js | features/backup/ | 低 |
| billing | billing.js | features/billing/ | 中 |
| brand | brand.js | features/brand/ | 低 |
| channels | channels.js | features/channels/ | 中 |
| extensions | marketplace.js | features/extensions/ | 中 |
| mcp | mcp.js | features/mcp/ | 中 |
| model-tester | model_test.js | features/model-tester/ | 低 |
| profile | profile.js | features/profile/ | 低 |
| share | share.js | features/share/ | 低 |
| skills | skills.js + skills_enhanced.js | features/skills/ | 高 |
| tasks | tasks.js | features/tasks/ | 低 |
| trash | trash.js | features/trash/ | 低 |
| version | versions.js | features/version/ | 低 |
| workspace | workspace.js | features/workspace/ | 中 |
| onboard | onboard.js | features/onboard/ | 中 |
| sessions | sessions.js | features/sessions/ | 高 |
| schedules | schedules.js | features/schedules/ | 中 |
| meeting | meeting.js | features/meeting/ | 中 |
| media | media.js | features/media/ | 中 |
| git | git_panel.js | features/git/ | 中 |
| browser | browser.js | features/browser/ | 低 |
| creator | creator.js | features/creator/ | 中 |

**不迁移的文件**（保留在 `web/js/` 根或 `web/js/core/`）：
- `app.js`（应用入口，瘦身）
- `websocket.js`（传输层，保留）
- `chat.js`（核心聊天，复杂度高，最后迁移或保留）
- `i18n.js` + `i18n/`（i18n 框架，保留）
- `notifications.js`（全局通知，迁移到 `core/`）

## 实施计划（任务包切分）

### 任务包 1：公共模块抽取（0.5 天）
- 抽取 `API` 包装器到 `web/js/core/api.js`
- 抽取导航逻辑到 `web/js/core/navigation.js`
- 修改 `app.js` 引用新路径

### 任务包 2：低复杂度模块迁移（1.5 天）
- 迁移 8 个低复杂度模块：brand/backup/trash/version/profile/share/model-tester/browser/tasks
- 每个模块拆分为 store.js + view.js
- 验证功能不回归

### 任务包 3：中复杂度模块迁移（2 天）
- 迁移 9 个中复杂度模块：billing/channels/mcp/extensions/workspace/onboard/schedules/meeting/media/git/creator
- 每个模块拆分为 store.js + view.js
- 验证功能不回归

### 任务包 4：高复杂度模块迁移（1.5 天）
- 迁移 sessions + skills 模块
- chat.js 暂不迁移（与 G1 ws-dispatcher 有耦合，待 G1 完成后评估）

### 任务包 5：清理与验证（0.5 天）
- 删除所有旧 flat 文件
- 更新 `index.html` 脚本引用
- 全面板功能验证

## 验收维度

- [ ] 20+ 个功能模块完成 store/view 拆分
- [ ] `API` 包装器抽取为 `core/api.js`，所有 store 复用
- [ ] 导航逻辑抽取为 `core/navigation.js`
- [ ] 所有现有功能不回归（手动验证每个面板）
- [ ] 旧 flat 文件全部删除，无残留引用
- [ ] `web/js/app.js` 瘦身至 < 100 行（仅初始化协调）
- [ ] `web/index.html` 脚本引用更新为 feature 路径
- [ ] 浏览器中手动验证所有面板功能正常

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 迁移过程中引入回归 | 高 | 每个模块迁移后立即验证；保留旧文件直到全部迁移完成 |
| 脚本加载顺序变化导致依赖错误 | 中 | `index.html` 中按依赖顺序排列脚本；公共模块先加载 |
| chat.js 与 G1 ws-dispatcher 耦合 | 中 | chat.js 最后迁移或暂不迁移，待 G1 完成后评估 |
| 迁移工作量可能超出预估 | 中 | 按复杂度分批，低复杂度先行，高复杂度最后 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G4，P1 重要功能 |
| 2026-07-13 | 审核修正：修正文件数 29 -> 33（实际计数）；补充"现状分析"中已有 Plain Object 模式的确认；补充 `API` 包装器抽取方案；补充完整迁移模块清单（20+ 模块，非 15 个）；标注 chat.js 暂不迁移（与 G1 耦合）；补充改动范围、实施计划、风险评估 | 对抗性审核 + 第一性原理校验 |
