# Vendor Libraries

本地化的第三方前端库，用于离线支持。

## 库列表

| 库 | 版本 | 用途 | LICENSE | 来源 |
|----|------|------|---------|------|
| highlight.js | 11.9.0 | 代码语法高亮 | [BSD-3-Clause](LICENSE-highlightjs) | `web/js/lib/highlight.min.js` |
| marked.js | 12.0.2 | Markdown 渲染 | [MIT](LICENSE-marked) | `web/js/lib/marked.min.js` |
| KaTeX | 0.16.11 | 数学公式渲染 | [MIT](LICENSE-katex) | `web/js/lib/katex/` (npm: katex) |
| QRCode | 1.5.4 | 二维码生成 | [MIT](LICENSE-qrcode) | `web/js/lib/qrcode/` (npm: qrcode) |
| CodeMirror 6 | 6.0.1 | 代码编辑器 | [MIT](LICENSE-codemirror) | `web/js/lib/codemirror/bundle.js` |

## CodeMirror 6 Bundle

通过 esbuild 打包，包含以下包：

- `codemirror@6.0.1` (EditorView, basicSetup)
- `@codemirror/lang-markdown@6.3.0` (markdown)
- `@codemirror/theme-one-dark@6.1.2` (oneDark)

## 更新方式

KaTeX 和 QRCode 可直接从 CDN 下载更新。CodeMirror 6 bundle 需通过 npm + esbuild 重新打包：

```bash
npm install codemirror@<ver> @codemirror/lang-markdown@<ver> @codemirror/theme-one-dark@<ver>
npx esbuild --bundle --format=esm --outfile=web/js/lib/codemirror/bundle.js cm-entry.js
```