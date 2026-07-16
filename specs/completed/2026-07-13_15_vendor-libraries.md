# Vendor 库集成（CodeMirror / 本地化 CDN 库） · 增量 Spec

> **创建日期**: 2026-07-13
> **状态**: 已完成
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G15（P2 增强性差距）
> **关联历史**: `specs/completed/2026-07-09_web-frontend-panels-completion.md`
> **来源差距**: G15 - vendor 库集成
> **依赖**: G4（feature-based 架构迁移，vendor 库放置在 `web/js/vendor/` 目录）

## 问题描述

原项目 `web/vendor/` 包含 5 个第三方库。当前项目所有 5 个库均已集成，但 KaTeX、QRCode 和 CodeMirror 6 通过 CDN 加载（离线不可用）。本 spec 的实际范围从"集成 CodeMirror"变更为"CDN 库本地化以支持离线使用"。

| 库 | 用途 | 当前状态 | 加载方式 |
|----|------|---------|---------|
| CodeMirror 6 | 代码编辑器 | ✅ 已集成 | CDN `esm.sh/codemirror@6.0.1`（`web/mb/public/editor.js`） |
| highlight.js | 代码高亮 | ✅ 已集成 | 本地 `web/js/lib/highlight.min.js` |
| KaTeX | 数学公式渲染 | ✅ 已集成 | CDN `cdn.jsdelivr.net/npm/katex@0.16.11` |
| marked.js | Markdown 渲染 | ✅ 已集成 | 本地 `web/js/lib/marked.min.js` |
| qrcode.js | 二维码生成 | ✅ 已集成 | CDN `cdn.jsdelivr.net/npm/qrcode@1.5.4` |

**结论**：5/5 库已集成。剩余工作：将 CDN 加载的库（CodeMirror 6、KaTeX、QRCode）本地化到 `web/js/lib/`，实现完全离线可用。

## 现状分析（经代码验证）

- `web/js/lib/` 目录有 2 个文件：`marked.min.js`、`highlight.min.js`（本地 vendored）
- `web/index.html` 加载方式：
  - `marked.min.js` 和 `highlight.min.js` 从本地 `js/lib/` 加载
  - KaTeX 从 CDN 加载（`index.html:13-14`）
  - QRCode 从 CDN 加载（`index.html:15`）
  - CodeMirror 6 从 CDN 加载（`index.html:16`：`<script type="module" src="mb/public/editor.js">`，该文件从 `esm.sh` 动态导入 CodeMirror 6 核心 + markdown 语言包 + oneDark 主题）
- **CodeMirror 6 集成架构**：`web/mb/public/editor.js`（86 行）通过 ES module 从 `esm.sh` 动态导入 CodeMirror 6，自动挂载到 `.code-editor-host` div；`web/mb/main/code_editor.mbt`（47 行）是 MoonBit/rabbita 组件，渲染 host div + 隐藏 textarea 回退
- **无 `web/vendor/` 目录**（原 spec 正确）
- **原 spec 的 "CodeMirror ❌ 缺失"、"KaTeX ❌ 缺失"、"qrcode.js ❌ 缺失" 均有误——所有 5 个库已集成**

## 决策

1. **CodeMirror 6 已集成，无需引入**：`web/mb/public/editor.js` 通过 CDN 动态加载 CodeMirror 6，`web/mb/main/code_editor.mbt` 提供 MoonBit 组件。当前架构已满足需求。
2. **本 spec 范围缩小为 CDN 库本地化（离线支持）**：将 KaTeX、QRCode、CodeMirror 6 从 CDN 依赖改为本地 `web/js/lib/` 加载，实现完全离线可用。
3. **CodeMirror 6 本地化需调整加载方式**：当前 `editor.js` 使用 ES module `import` 从 `esm.sh` 加载，本地化需改为相对路径导入或打包后的 bundle。
4. **优先级**：KaTeX 本地化 > QRCode 本地化 > CodeMirror 6 本地化（CodeMirror 6 的 ES module 本地化最复杂）。
5. **统一 vendor 目录为 `web/js/lib/`**：所有本地化库放入此目录，新增 `README.md` 记录版本和来源。

## 改动范围

- **涉及文件**：
  - 新增 `web/js/lib/katex/`：KaTeX JS + CSS + fonts（替换 `index.html` 中 CDN 引用）
  - 新增 `web/js/lib/qrcode/`：QRCode JS（替换 `index.html` 中 CDN 引用）
  - 新增 `web/js/lib/codemirror/`：CodeMirror 6 bundle（替换 `editor.js` 中 `esm.sh` CDN 导入）
  - 修改 `web/index.html`：替换 KaTeX 和 QRCode CDN 引用为本地路径
  - 修改 `web/mb/public/editor.js`：替换 `esm.sh` 导入为本地路径（或打包为 bundle）
  - 新增 `web/js/lib/README.md`：说明各库版本和来源
- **不涉及**：后端、TUI、Extension 框架、MoonBit 代码

## 实施计划（任务包切分）

1. **KaTeX 本地化**（优先级最高）：下载 KaTeX v0.16.11 JS + CSS + fonts 到 `web/js/lib/katex/`，修改 `index.html:13-14` 引用。
2. **QRCode 本地化**：下载 QRCode v1.5.4 到 `web/js/lib/qrcode/`，修改 `index.html:15` 引用。
3. **CodeMirror 6 本地化**（最复杂）：将 `editor.js` 中的 `esm.sh` 导入替换为本地 bundle，或使用打包工具生成 `web/js/lib/codemirror/bundle.js`。
4. **验证**：断开网络后验证所有功能正常。

## 验收标准

- [ ] 断开网络后 KaTeX 数学公式渲染正常
- [ ] 断开网络后 QRCode 二维码生成正常
- [ ] 断开网络后 CodeMirror 6 代码编辑器正常加载
- [ ] 现有 highlight.js、marked.js 功能不受影响
- [ ] `web/js/lib/README.md` 记录所有库版本和来源

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| CodeMirror 6 ES module 本地化复杂 | 中 | 可先本地化 KaTeX/QRCode，CodeMirror 6 本地化可推迟或用打包工具（esbuild）生成 bundle |
| KaTeX fonts 路径问题 | 中 | 验证 CSS 中字体路径相对于 `web/` 根目录 |
| CDN 本地化后版本不一致 | 低 | 版本锁定在 `README.md` 中记录 |
| CodeMirror 6 本地化后 editor.js 需要修改 | 中 | 保留 CDN 回退：优先本地，本地不可用时回退 CDN |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G15，P2 增强性 |
| 2026-07-13 | 审核修正：修正"KaTeX ❌ 缺失"的错误（已通过 CDN 加载）；修正"qrcode.js ❌ 缺失"的错误（已通过 CDN 加载）；修正"highlight.js 和 marked.js 通过 CDN 引入"的错误（实际为本地 `web/js/lib/`）；实际仅 CodeMirror 缺失，大幅缩减改动范围；CDN 库本地化降级为可选项 | 对抗性审核 + 第一性原理校验 |
| 2026-07-16 | 审核修正：**CodeMirror 6 已通过 CDN 集成**（`web/mb/public/editor.js` 从 `esm.sh` 动态导入，`web/mb/main/code_editor.mbt` 为 MoonBit 组件）；修正"CodeMirror ❌ 唯一缺失"的重大错误（5/5 库已全部集成）；spec 范围从"集成 CodeMirror"变更为"CDN 库本地化（离线支持）"；更新现状分析补充 `web/mb/` rabbita 前端架构；更新决策、改动范围、实施计划、验收标准全面反映新现实 | 对抗性审核 + 第一性原理校验 |
| 2026-07-16 | **实施完成**：KaTeX v0.16.11 本地化到 `web/js/lib/katex/`（JS + CSS + 21 fonts）；QRCode v1.5.4 通过 esbuild 打包为 IIFE 到 `web/js/lib/qrcode/qrcode.min.js`（原 CDN 地址无效，实际从未加载）；CodeMirror 6 通过 esbuild 打包为 ESM bundle 到 `web/js/lib/codemirror/bundle.js`（含 codemirror@6.0.1 + @codemirror/lang-markdown@6.3.0 + @codemirror/theme-one-dark@6.1.2）；修改 `web/index.html` 替换所有 CDN 引用为本地路径；修改 `web/mb/public/editor.js` 替换 esm.sh 导入为本地 bundle；新增 `web/js/lib/README.md` 记录所有库版本和来源 | 实施 |