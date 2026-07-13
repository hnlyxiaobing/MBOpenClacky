# Vendor 库集成（CodeMirror / 本地化 CDN 库） · 增量 Spec

> **创建日期**: 2026-07-13
> **状态**: 讨论中
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G15（P2 增强性差距）
> **关联历史**: `specs/completed/2026-07-09_web-frontend-panels-completion.md`
> **来源差距**: G15 - vendor 库集成
> **依赖**: G4（feature-based 架构迁移，vendor 库放置在 `web/js/vendor/` 目录）

## 问题描述

原项目 `web/vendor/` 包含 5 个第三方库。当前项目已有的库加载情况如下（经代码验证）：

| 库 | 用途 | 当前状态 | 加载方式 |
|----|------|---------|---------|
| CodeMirror | 代码编辑器 | ❌ **唯一缺失** | 无 |
| highlight.js | 代码高亮 | ✅ 已集成 | 本地 `web/js/lib/highlight.min.js` |
| KaTeX | 数学公式渲染 | ✅ 已集成 | CDN `cdn.jsdelivr.net/npm/katex@0.16.11` |
| marked.js | Markdown 渲染 | ✅ 已集成 | 本地 `web/js/lib/marked.min.js` |
| qrcode.js | 二维码生成 | ✅ 已集成 | CDN `cdn.jsdelivr.net/npm/qrcode@1.5.4` |

**结论**：4/5 库已集成。仅 CodeMirror 缺失。KaTeX 和 QRCode 通过 CDN 加载（离线不可用），可选择性本地化。

## 现状分析（经代码验证）

- `web/js/lib/` 目录有 2 个文件：`marked.min.js`、`highlight.min.js`（本地 vendored）
- `web/index.html` 加载方式：
  - `marked.min.js` 和 `highlight.min.js` 从本地 `js/lib/` 加载
  - KaTeX 从 CDN 加载（`index.html:13-14`），`chat.js:492` 使用 `katex` 渲染数学公式
  - QRCode 从 CDN 加载（`index.html:15`），`share.js:104` 使用 `QRCode` 生成二维码
- **无 `web/vendor/` 目录**（原 spec 正确）
- **原 spec 的 "KaTeX ❌ 缺失" 和 "qrcode.js ❌ 缺失" 均有误**

## 决策

1. **仅新增 CodeMirror**：4/5 库已集成，本 spec 实际只需引入 CodeMirror。
2. **CodeMirror 用 v6（当前稳定版）**：原项目用 v5，v6 是模块化重构版本，包体积更小。
3. **KaTeX 和 QRCode 可选本地化**：当前 CDN 加载在离线环境不可用。如需离线支持，将 CDN 库下载到 `web/js/lib/`。优先级低于 CodeMirror 集成。
4. **统一 vendor 目录为 `web/js/lib/`**：现有库已在 `web/js/lib/`，CodeMirror 也放此目录，不新建 `web/vendor/`。
5. **各库按需加载**：CodeMirror 仅在代码编辑面板使用时动态加载。

## 改动范围

- **涉及文件**：
  - 新增 `web/js/lib/codemirror/`：CodeMirror 6 核心 + 语言包 + 主题
  - 可选：下载 KaTeX 和 QRCode 到 `web/js/lib/`（替换 CDN 引用）
  - 修改 `web/index.html`：添加 CodeMirror script 引用（如选择本地化 CDN 库，也修改对应引用）
  - 新增 `web/js/lib/README.md`：说明各库版本和来源
- **不涉及**：后端、TUI、Extension 框架

## 实施计划（任务包切分）

1. **CodeMirror 6 集成**（必做）：下载核心包 + 语言包（JavaScript/JSON/Markdown/YAML），放入 `web/js/lib/codemirror/`。
2. **CDN 库本地化**（可选，低优先级）：下载 KaTeX（JS + CSS + fonts）和 QRCode 到 `web/js/lib/`，修改 `index.html` 引用。
3. **加载机制**：CodeMirror 按需动态加载。
4. **验证**：浏览器中验证代码编辑器功能。

## 验收标准

- [ ] CodeMirror 6 可正常加载和编辑代码
- [ ] （可选）KaTeX 和 QRCode 离线可用
- [ ] CodeMirror 按需加载，不影响首屏性能
- [ ] 现有 highlight.js、marked.js、KaTeX、QRCode 功能不受影响

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| CodeMirror 6 包体积较大 | 中 | 仅打包需要的语言模式 |
| KaTeX fonts 路径问题（如本地化） | 中 | 验证 CSS 中字体路径相对于 `web/` 根目录 |
| CDN 本地化后版本不一致 | 低 | 版本锁定在 `README.md` 中记录 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G15，P2 增强性 |
| 2026-07-13 | 审核修正：修正"KaTeX ❌ 缺失"的错误（已通过 CDN 加载，`chat.js:492` 使用）；修正"qrcode.js ❌ 缺失"的错误（已通过 CDN 加载，`share.js:104` 使用）；修正"highlight.js 和 marked.js 通过 CDN 引入"的错误（实际为本地 `web/js/lib/`）；实际仅 CodeMirror 缺失，大幅缩减改动范围；CDN 库本地化降级为可选项 | 对抗性审核 + 第一性原理校验 |
