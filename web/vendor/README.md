# Vendored browser libraries

These files are checked into the repository so the Web UI has no runtime CDN dependency.
Versions below were refreshed on 2026-10-14.

| Library | Version | Source |
|---|---|---|
| highlight.js | 11.12.0 | `highlight.js/lib/common` browser bundle; preserves the existing 36-language common build |
| marked | 18.1.1 | `marked/lib/marked.umd.js` |
| KaTeX | 0.19.0 | `katex/dist/katex.min.js`, `katex/dist/katex.min.css`, `katex/dist/contrib/auto-render.min.js`, and the 20 bundled `woff2` fonts |
| qrcode-generator | 2.0.4 | `dist/qrcode.js`, minified with esbuild |
| qrcodejs | 1.0.0 | qrcode.min.js; used only by web/weixin-qr.html |
| CodeMirror 6 | codemirror 6.0.2, @codemirror/lang-markdown 6.5.2, @codemirror/theme-one-dark 6.1.3 | esbuild IIFE bundle exposing the `CM` globals used by `web/components/code-editor.js` |

The CodeMirror bundle exports the same 27 names as the previous bundle:
`EditorState`, `EditorView`, `bracketMatching`, `crosshairCursor`,
`defaultHighlightStyle`, `defaultKeymap`, `drawSelection`, `dropCursor`,
`foldGutter`, `foldKeymap`, `highlightActiveLine`, `highlightActiveLineGutter`,
`highlightSelectionMatches`, `highlightSpecialChars`, `history`, `historyKeymap`,
`indentOnInput`, `indentWithTab`, `keymap`, `lineNumbers`, `markdown`,
`markdownLanguage`, `oneDark`, `rectangularSelection`, `search`, `searchKeymap`,
and `syntaxHighlighting`.

Licenses and upstream notices are disclosed in the repository-level `NOTICE`.