# Web UI 对齐状态

> 更新日期：2026-10-14
> 本文记录 Web UI（`lib/web` + `web/`）与上游 openclacky 的对齐结论；日常回归走 [testing.md](testing.md) 层 4/9 与 `test/web-e2e/`。

## 结论

Web UI 已完成三轮对齐和根因修复，当前不是“功能清单未实现”，而是保留少量有意差异和已登记边界。

已修复的主要问题包括：历史消息丢失、模型下拉/选择、工作目录规范化、会话自动命名、头像静态路由、历史分页重复、响应字段契约。对应修复过程在 `specs/completed/2026-07-26_web-ui2-*.md` 与 `specs/completed/2026-07-24_web-ui-fix-*.md`。

## 当前边界

- `BeforeLlmCall` 的 `phase_start` 事件由 `web/ws-dispatcher.js` 的折叠卡隔离，不会把子代理阶段混入外层正文。
- 媒体端点已接线：`/api/media/image`、`/video`、`/audio/speech`、`/audio/transcriptions`、`/video/understand`。
- 第三方前端依赖已全部 vendor 到 `web/vendor/`（2026-10-14 刷新到 highlight.js 11.12.0 / marked 18.1.1 / KaTeX 0.19.0 / qrcode-generator 2.0.4 / CodeMirror 6 重打包），运行时不依赖 CDN；版本与来源见 [web/vendor/README.md](../web/vendor/README.md)，许可见 [NOTICE](../NOTICE)。`weixin-qr.html` 曾从 jsDelivr 取 qrcodejs，现已改为同源 vendor 副本。
- `/health` 与 `GET /api/version` 是公开探测端点；其他 API 使用 `MBOPENCLACKY_WEB_API_KEY` 认证。
- 默认绑定 `127.0.0.1:7071`。非回环绑定必须提供 Web API key；`MBOPENCLACKY_DEV_ALLOW_LOOPBACK=1` 仅限开发，不能作为安全边界。

## 回归方式

```bash
moon run cmd -- server
moon run cmd -- eval --web test/scenarios/web/ --format markdown
cd test/web-e2e && npm test
```

旧 `--web-eval` 顶层旗标仍兼容但已弃用。REST 契约单测在 `lib/web/*_wbtest.mbt`，真实浏览器覆盖在 `test/web-e2e/`。

## 与上游全面对比

前端是上游 v1.5.0 的托管 fork。同步流程见 [web/UPSTREAM_SYNC.md](../web/UPSTREAM_SYNC.md)，补丁登记见 [web/PATCHES.md](../web/PATCHES.md)。怀疑漂移时：

1. `diff -rq` 比较 `web/` 与上游 `lib/clacky/web/`，排除 `ext_ui/`、`PATCHES.md`、`UPSTREAM_SYNC.md`。
2. 对照 `lib/web/server.mbt` 的 crescent 路由和 API 响应做结构 diff。
3. 用 Playwright 双开浏览器走新会话、聊天、WS、设置、My Data、Skills、Extensions 等流程。
4. 用相同帧序列比较 `/ws` 事件类型与字段。
5. 功能缺失登记 gap，行为错误登记 bug；端口、认证变量和 `web/ext_ui/` 是有意差异。

有意差异：端口 7071 vs 上游 7070；认证变量 `MBOPENCLACKY_WEB_API_KEY` vs `CLACKY_ACCESS_KEY`；本项目新增 `web/ext_ui/` 面板。
