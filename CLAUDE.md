# CLAUDE.md

MBOpenClacky is a MoonBit rewrite of the openclacky AI Agent CLI — an LLM-powered autonomous agent with tool calling, skill plugins, session management, TUI, and a web server.

> 开发规范（编码风格、测试指南、提交规范）请参阅 [AGENTS.md](AGENTS.md)。

## Build & Test

```bash
moon check                                          # Type-check (0 errors expected)
moon build --target native --release cmd            # Build native binary (always specify cmd)
moon run cmd                                        # Run CLI
moon run cmd -- --message "Hello"                   # Non-interactive mode
moon run cmd -- --server                            # Web server (port 7070)
moon test                                           # White-box tests (native only, needs -lcurl)
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
  mcp/        — MCP protocol: Transport trait (Stdio/HTTP), JSON-RPC 2.0 client,                registry, virtual skill mapping, skill provider
  channel/    — 6 IM adapters (Feishu/Wecom/Telegram/Discord/DingTalk/Weixin) via AnyAdapter enum
  web/        — crescent HTTP server: ~154 REST endpoints, SSE, WebSocket, auth/logging
                middleware, timeout/error-envelope, broadcast hub, template processor,
                static server with SPA fallback  tui/        — Inline scrolling TUI (moonbit-community/tty): async event loop
                (Queue[TuiEvent]) + Elm-style Msg/update state transition, Node component
                tree rendering, dialog system (approval/config/form), Agent Shell
                (file browser), thinking live view, ScreenBuffer, OutputBuffer,
                LineEditor (CJK-aware), LayoutManager, StatusBar, InputArea, TodoArea,
                markdown rendering, slash commands, themes, progress stack, block-font
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
  utils/      — Env vars, path, encoding, logger, proxy config, gitignore parser, etc.
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

## Current Metrics

| Indicator | Value |
|-----------|-------|
| `.mbt` source files (lib + cmd) | 309 |
| Test files (`_wbtest.mbt`) | 103 |
| Source lines | ~62,000 |
| Test lines | ~23,000 |
| Total lines (incl. test/) | ~85,000 |
| Test cases | 1,850+ |
| Packages | 24 lib + 1 cmd |
| Built-in tools | 14 |
| Provider presets | 12 |
| Default skills | 17 |
| REST API endpoints | ~154 |
| `moon check` | 0 errors, ~500 warnings |
| CI/CD | ✅ GitHub Actions |
| Phase coverage | ~95% |