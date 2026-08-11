# CLAUDE.md

MBOpenClacky is a MoonBit rewrite of the openclacky AI Agent CLI — an LLM-powered autonomous agent with tool calling, skill plugins, session management, TUI, and a web server.

> 开发规范（编码风格、测试指南、提交规范）请参阅 [AGENTS.md](AGENTS.md)。
> **开发效率协议**（模型分层、文件读取、构建确认、失败诊断、会话管理）见 AGENTS.md 的 `Development Efficiency Protocol` 章节，完整数据与案例见 [docs/development-efficiency.md](docs/development-efficiency.md)。

## Build & Test

```bash
moon check                                          # Type-check (0 errors expected)
moon build --target native --release cmd            # Build native binary (always specify cmd)
moon run cmd                                        # Run CLI
moon run cmd --message "Hello"                   # Non-interactive mode
moon run cmd -- server                              # Web server (port 7071)
moon test                                           # White-box tests (native only)
moon update && moon install                         # Sync dependencies
```

- Tests are co-located `*_wbtest.mbt` files. `moon test --target wasm-gc` fails due to FFI in `tty`/`crescent`.
- Always use `moon build --target native --release cmd` (not bare `moon build`) — [moon#1488](https://github.com/moonbitlang/moon/issues/1488).

## Architecture

24 lib packages + 1 cmd entry. All three interfaces (CLI, TUI, Web) share the same `Agent` core via the hook system.
```
cmd/          — CLI entry (clap parsing, agent lifecycle, session management)
lib/
  agent/      — Agent struct, ReAct loop, LLM caller, system prompt, session persistence,
                hook system, memory store, todo manager, subagent pool, cost tracker,
                compressor, time machine, profile, idle timer, session restore
  client/     — LLM API client (OpenAI/Anthropic/Bedrock formats), stream aggregators,
                platform HTTP client with domain failover, 12 provider presets
  tool/       — Tool trait + 14 built-in tools (FileReader, Write, Edit, Grep, Glob,
                Terminal/PTY, WebSearch, WebFetch, InvokeSkill, MemoryTool, TodoTool,
                RequestUserFeedback, TrashManager, Browser) + registry with 70+ aliases
  skill/      — SKILL.md parsing, registry, discovery, executor, evolution engine
                (Reflector/AutoCreator), 17 default skills
  extension/  — Extension lifecycle: loader, verifier, packager, scaffold,
                marketplace, API extension dispatcher/loader, route contributions
  mcp/        — MCP protocol: Transport trait (Stdio/HTTP), JSON-RPC 2.0 client,
                registry, virtual skill mapping, skill provider
  channel/    — 6 IM adapters (Feishu/Wecom/Telegram/Discord/DingTalk/Weixin) via AnyAdapter enum
  web/        — crescent HTTP server: 216 REST routes (incl. aliases), WebSocket (token-level
                streaming), auth/logging middleware, timeout/error-envelope, broadcast
                hub, template processor, static server with SPA fallback
                (native JS frontend in web/)
  tui/        — Inline scrolling TUI: line-level repaint + commit-scrollback
                (tui_controller_render.mbt) + mizchi/signals reactive state on
                moonbit-community/tty; async event loop
                (Queue[TuiEvent]), dialog system (approval/config/form),
                thinking live view, LineEditor (CJK-aware), StatusBar,
                InputArea, TodoArea, markdown rendering, slash commands, themes,
                progress stack, block-font (see docs/tui-architecture.md)
  server/     — Cron parser, scheduler, browser manager, backup manager, discover,
                master/worker, session registry, git panel
  config/     — TOML loader, 12 provider presets, capabilities, permission modes, env compat
  billing/    — Billing records, token tracking, cost calculation
  brand/      — White-label config, license validation, device binding, identity
                persistence, AES-GCM/HMAC/SHA256 (C FFI)
  media/      — Image/video/audio generation logic (OpenAI/Gemini/DashScope); REST handlers are 501 stubs
  parser/     — PDF, DOCX (ZIP+XML), PPTX, XLSX parsers
  vision/     — Vision OCR + SHA256 caching
  pricing/    — Model pricing table (677 lines), cost calculator
  message/    — Message/Role/ContentBlock/ToolCall types, message history
  hook/       — Shell hook system (7 event types)
  telemetry/  — Anonymous telemetry (fire-and-forget)
  errors/     — Error type hierarchy
  i18n/       — Internationalization (en/zh translations)
  utils/      — Env vars, path, encoding, logger, proxy config, gitignore parser, etc.
  zip/        — ZIP compression/decompression
```

### Agent Core

- **ReAct Loop**: `think()` → `act()` → `observe()` with truncation handling
- **LLM Calling**: Retry logic, fallback state machine (PrimaryOk → FallbackActive → Probing)
- **System Prompt**: Multi-layer construction (brand, role, rules, project rules, working dir, model info, skills, memory, tasks)
- **Session**: JSON file-based CRUD with cap enforcement and restore
- **Compressor**: LLM-driven message summarization
- **Time Machine**: File snapshot undo/redo with ancestor chain restoration

### Key Patterns

- **Hook system**: Observer pattern — `HookManager::register(cb)` / `emit(event)`. TUI and Web UI subscribe to agent lifecycle events.
- **Fallback state machine**: 3 consecutive RetryableErrors → switch to fallback model; cooldown → probe primary; success → revert.
- **Tool aliases**: 70+ name mappings bridge LLM-invented tool names to canonical registrations.
- **AnyAdapter enum**: Channel adapters use enum-based type erasure (not trait objects) for 6 IM platforms.
- **AnyTool enum**: Zero-cost dispatch for 14 tool implementations.

## Development Workflow (spec-driven)

Follow the Harness v2 loop — see [specs/decisions/harness-methodology-v2-upgrade.md](specs/decisions/harness-methodology-v2-upgrade.md):

1. **Read all relevant specs in one batch** (single message, parallel `file_reader` calls).
2. **Verify gap claims against real code** (`grep`/`glob`) before writing anything.
3. **Split work with todo_manager**, implement one small unit at a time.
4. **Validate in a tight loop**: `moon check` → targeted `moon test` → `moon fmt` → `moon info`.
5. **Commit small and often** (`feat:`/`fix:` prefixes), archive specs to `specs/completed/` after acceptance.
6. Respect the **Efficiency Protocol** in AGENTS.md — especially model tiering and "read full errors before retrying".

## Current Metrics

| Indicator | Value |
|-----------|-------|
| `.mbt` source files (lib + cmd) | 291 |
| Test files (`_wbtest.mbt` + test/) | 178 |
| Source lines | ~80,900 |
| Test lines | ~46,500 |
| Total lines (incl. test/) | ~127,500 |
| Test cases | 3,100+ |
| Packages | 24 lib + 1 cmd |
| Built-in tools | 14 |
| Provider presets | 13 |
| Default skills | 18 |
| REST API endpoints | 216 routes (incl. aliases) |
| `moon check` | 0 errors |
| CI/CD | ✅ GitHub Actions |
| Phase coverage | ~95% |