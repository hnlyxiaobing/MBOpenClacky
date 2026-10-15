# Web Browser E2E（Playwright）

本目录用 Playwright 驱动真实 Chromium，补充验证 Web UI、REST 和 WebSocket 的组合行为。它是手动/本地套件，不替代 `docs/testing.md` 层 4 的场景回放，也不替代层 9 Journey。

## 当前范围

- 21 个 `scenarios/*.spec.ts` 文件。
- 114 个 `test(...)` 用例，另有 7 处条件跳过：3 处在 `04-model-switch`（配置模型不足 2 个），4 处在本轮无模型响应时触发。跳过必须是显式 `test.skip`，不能是静默 `return`。
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

## 等待语义（改动用例前必读）

- **一轮对话"结束"的唯一 DOM 事实是 WS `complete` 事件渲染出的 `✓ …` `.msg-info` 行**（`web/ws-dispatcher.js` → `Sessions.appendInfo`）。`.msg-assistant` 计数不是结束信号：ReAct 每一轮迭代都会产生一个助手气泡，第一个气泡是工具调用前的旁白，用它判定会读到半成品回答。
- `waitForAgentResponse()` 在等待期间会自动应答 `#modal-yes`：默认 `permission_mode = "confirm_safes"` 会在模型要写文件时暂停整轮运行，不回答就永远等不到 `complete`。这些用例测的是对话上下文，不是权限 UX（后者由 Journey 覆盖），因此自动批准；上限 5 次，超过就抛错而不是无限烧实时请求。每次批准后重新计时，因为运行会从头继续。
- **等不到结果会抛错**。旧实现超时后静默 `return`，调用方就对着屏幕上残留的气泡断言，坏掉的运行也能变绿。
- 无模型可用时用 `test.skip(true, …)` 显式跳过，不再 `return; // LLM unavailable` 静默通过——那会让用例在没测任何东西时报告成功。
- 单测默认预算 180s（`playwright.config.ts`），helper 内部 90s，`03-multi-turn-context` 覆盖到 300s；Playwright 原生的 30s 默认会在一轮流式对话中途杀掉用例。
- 本套件依赖**实时模型**，不是确定性回归面：结论会随模型漂移，判定产品契约请优先用层 4 场景回放或层 9 Journey。

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
