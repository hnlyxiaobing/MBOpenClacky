# Web Browser E2E（Playwright）

本目录用 Playwright 驱动真实 Chromium，补充验证 Web UI、REST 和 WebSocket 的组合行为。它是手动/本地套件，不替代 `docs/testing.md` 层 4 的场景回放，也不替代层 9 Journey。

## 当前范围

- 21 个 `scenarios/*.spec.ts` 文件。
- 114 个 `test(...)` 用例，另有 4 个依赖模型数量或运行环境的条件跳过。
- 覆盖基础启动、会话生命周期、多轮上下文、模型切换、附件/图片、设置、Skills、Extensions、Trash、Profile、搜索、会话操作、消息交互、导出 API、错误处理、键盘可访问性、Billing、MCP、Channels、Tasks。

## 运行

```bash
moon build --target native --release cmd
cd test/web-e2e
npm install
npm test
```

调试：

```bash
npm run test:headed
npm run test:debug
```

`playwright.config.ts` 会启动 release 二进制的 `server --port 7071`，并访问 `http://localhost:7071/health`。

## 运行前注意

1. 配置中的 Chromium `executablePath` 与 MBOpenClacky release 二进制目前是本机绝对路径；换机器或换工作区前必须修改。
2. 套件会启动真实 Web 服务，并可能创建会话/上传文件。使用隔离的 `HOME`/`USERPROFILE` 和测试模型配置，避免污染真实用户数据。
3. `04-model-switch` 中部分断言只有在配置多个模型时才执行；模型不足时会按设计 skip。
4. `node_modules/`、`test-results/`、`playwright-report/` 已忽略，不入库。

## 与其他层的关系

| 层 | 作用 |
|---|---|
| 层 4 | 进程内 TUI/Web 场景断言，轻量、可重复 |
| 层 9 | 真实二进制用户旅程，mock LLM、进程隔离 |
| 本目录 | 真实浏览器 DOM/交互/API 组合，依赖较重 |

本套件当前不进 CI；是否纳入 CI、如何参数化浏览器/二进制路径，属于 `specs/draft/2026-10-10-user-scenario-automation-design.md` 的后续决策。
