# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MBOpenClacky is a MoonBit rewrite of the openclacky AI Agent CLI tool — an LLM-powered autonomous agent with tool calling, skill plugins, session management, TUI, and a web server.

## Build & Test Commands

```bash
moon check              # Type-check the entire project (0 errors expected)
moon build              # Build native binary (preferred_target = native)
moon run cmd            # Run CLI entry point
moon run cmd -- --message "Hello"   # Non-interactive agent mode
moon run cmd -- --server            # Start web UI server on port 7070
moon test               # Run all white-box tests (*_wbtest.mbt) — native target only
moon update && moon install         # Sync dependencies
```

- Tests are co-located as `*_wbtest.mbt` files next to source (MoonBit white-box test convention).
- `moon test --target wasm-gc` fails due to FFI dependencies in `tty` and `crescent`; use `moon check` for validation instead.
- No lint tool is configured beyond `moon check`.

## Architecture

### Package Layout (21 top-level packages)

```
cmd/          — CLI entry point (clap argument parsing, agent lifecycle orchestration)
lib/
  agent/      — Core: Agent struct, ReAct loop, LLM caller, system prompt, session persistence,
                hook system, memory store, todo manager, subagent pool, cost tracker, compressor,
                time machine, profile, idle timer, default profiles, session restore
  billing/    — Billing record creation, token usage tracking, cost calculation, storage
  brand/      — Brand white-label config, license key validation, heartbeat/grace period, crypto
                (AES-GCM/HMAC/SHA256 via C FFI native stub)
  channel/    — IM channel adapters (Feishu/Wecom/Telegram/Discord/DingTalk/Weixin) via AnyAdapter enum
  client/     — LLM API client (Client struct, format_anthropic/openai/bedrock, stream aggregator,
                platform HTTP client with domain failover)
  config/     — TOML config loader, model config, 12 provider presets, capabilities, permission
                modes, agent config, env compat layer
  errors/     — Error type hierarchy (AgentError, RetryableError, ToolCallError, etc.)
  hook/       — Shell hook system (7 event types) with shell loader
  mcp/        — MCP protocol: Transport trait (Stdio/HTTP), JSON-RPC 2.0 client, registry,
                virtual skill mapping, skill provider module
  media/      — Media generation (image/video/audio) via OpenAI/Gemini/DashScope compatible APIs
  message/    — Message/Role/ContentBlock/ToolCall types with JSON serialization, message history
  parser/     — Document parsers: PDF, DOCX (ZIP+XML), PPTX, XLSX
  pricing/    — Model pricing table (677 lines), cost calculator
  server/     — Ops: cron parser, scheduler, browser manager, backup manager, server discover,
                server master/worker, session registry, git panel
  skill/      — Skill system: SKILL.md parsing, registry, discovery, execution, evolution engine
                (Reflector/AutoCreator), default skills
  telemetry/  — Anonymous telemetry (fire-and-forget)
  tool/       — Tool trait + 14 built-in tools + registry with alias resolution, security,
                output cleaner; Terminal tool now uses PTY-based execution (pty/pty_ffi/
                pty_session/pty_stubs.c)
  tui/        — Terminal UI (moonbit-community/tty): inline scrolling TUI with
                ScreenBuffer (ANSI primitives), OutputBuffer (committed-line
                semantics), LineEditor (CJK-aware grapheme editor), LayoutManager
                (scroll region + fixed areas), StatusBar, InputArea, TodoArea,
                markdown rendering, slash commands, themes, progress stack,
                command suggestions, agent hook handler, CJK width,
                block-font rendering, thinking verbs
  utils/      — Env vars, path resolution, encoding, environment detector, EPIPE safe IO,
                file ignore helper, gitignore parser, limit stack, logger, proxy config,
                string matcher, trash directory, workspace rules
  vision/     — Vision OCR + SHA256 caching
  web/        — HTTP server (crescent): REST API (90+ endpoints), SSE, WebSocket, auth/logging
                middleware, timeout/error-envelope middleware, broadcast hub, template processor,
                router, static server, SPA serving; added handlers for exchange-rate,
                local-image proxy, onboarding, media, OCR config/test, version/upgrade, restart
```

### Agent Core (`lib/agent/`)

The `Agent` struct (25+ fields) is the central orchestrator:

1. **ReAct Loop** (`react.mbt`): `think()` → `act()` → `observe()` cycle with truncation handling
2. **LLM Calling** (`llm_caller.mbt`): Retry logic, fallback state machine (PrimaryOk → FallbackActive → Probing), context overflow recovery
3. **System Prompt** (`system_prompt.mbt`): Multi-layer prompt construction (brand confidentiality, role, rules, project rules, working dir, model info, skills, memory, tasks)
4. **Session Persistence** (`session_store.mbt`, `session_data.mbt`, `session_manager.mbt`, `session_restore.mbt`): JSON file-based CRUD with cap enforcement and restore
5. **Compressor** (`compressor.mbt`, `compressor_helper.mbt`): Message compression with LLM-driven summarization
6. **Time Machine** (`time_machine.mbt`): File snapshot undo/redo with ancestor chain restoration
7. **Profile** (`profile.mbt`, `default_profiles.mbt`): Agent profile loading (SOUL.md/USER.md integration)
8. **Idle Timer** (`idle_timer.mbt`): IdleCompressionTimer state machine (266s threshold)

### LLM Client (`lib/client/`)

- `Client` struct wraps API key, base URL, model name, and `ApiType`
- Triple protocol support: Anthropic Messages API, OpenAI-compatible API, Bedrock Converse API
- Stream aggregators for all three protocols (OpenAI/Anthropic/Bedrock)
- Platform HTTP client with domain failover and retry logic (`platform_http.mbt`)
- 12 Provider presets: OpenClacky, OpenRouter, Anthropic, OpenAI, DeepSeek, DeepSeekV4, Qwen, MiniMax, Kimi, Kimi-Coding, MiMo, GLM
- Response parsing unified into `LlmResponse` struct

### Tool System (`lib/tool/`)

- `pub(open) trait Tool` with methods: name, description, parameters (JSON Schema), execute, format_call/result, to_function_definition
- `AnyTool` enum dispatches to concrete implementations
- 14 built-in tools: FileReader, Write, Edit, Grep, Glob, Terminal, WebSearch, WebFetch, InvokeSkill, MemoryTool, TodoTool, RequestUserFeedback, TrashManager, Browser
- `ToolRegistry` with multi-strategy name resolution: exact → case-insensitive → alias map → hyphen/underscore normalization
- 70+ aliases mapping LLM-invented names to canonical tool names
- Security validation (`security.mbt`) and ANSI output cleaning (`output_cleaner.mbt`)

### Skill System (`lib/skill/`)

- Skills parsed from YAML-frontmatter `.md` files (SKILL.md format)
- `Skill` struct with name, description, allowed_tools, context, hooks, fork_agent, model, etc.
- Discovery scans configured directories, registry provides lookups, executor runs skill hooks
- Evolution engine (`evolution.mbt`): SkillReflector (post-execution review) + AutoCreator (pattern detection)
- Default skills (`default_skills.mbt`): 16 built-in skills in `assets/skills/`

### Enhanced Features (Phase 10+)

- **MemoryStore** (`memory.mbt`, `memory_types.mbt`): Category-based persistent memory with CRUD and context injection
- **TodoManager** (`todo.mbt`, `todo_types.mbt`): Task tracking with dependency blocking
- **SubAgent/AgentPool** (`subagent.mbt`, `agent_pool.mbt`): Concurrent sub-agents with lifecycle management
- **Billing** (`billing_record.mbt`, `billing_store.mbt`): Usage tracking and cost calculation
- **Pricing** (`model_pricing.mbt`, `cost_calculator.mbt`): Complete model pricing table
- **Message History** (`history.mbt`): Advanced message history management with UTF-8 cleaning
- **Server Infrastructure**: Master/worker process model, session registry, git panel integration

### Interfaces

| Interface | Technology | Location |
|-----------|-----------|----------|
| CLI | clap argument parser | `cmd/main.mbt` |
| TUI | moonbit-community/tty (inline scrolling) | `lib/tui/` (24+ files) |
| Web | crescent (REST + WebSocket + SSE) | `lib/web/` (33+ files, 90+ endpoints) |

All three interfaces share the same `Agent` core via the hook system (`lib/agent/hook.mbt`).

### Error Handling

- MoonBit suberror hierarchy: `AgentError`, `BadRequestError`, `ToolCallError`, `RetryableError`, `UpstreamTruncatedError`, `AgentInterrupted`, `BrowserNotReachableError`
- `is_agent_error()` / `is_retryable_error()` predicates for catch-all matching

### Configuration

TOML config loaded from `~/.mbopenclacky/config.toml`. Environment variable `MBOPENCLACKY_API_KEY` as fallback. Supports multiple model entries with permission modes: `auto_approve`, `confirm_safes` (default), `confirm_all`. Provider capabilities and env compat layer in `lib/config/`.

### Key Patterns

- **Hook system**: Observer pattern — `HookManager::register(cb)` / `HookManager::emit(event)`. The TUI and web server subscribe to agent lifecycle events via hooks rather than tight coupling.
- **Fallback state machine**: After 3 consecutive RetryableErrors → switch to fallback model; after cooldown → probe primary; on probe success → revert to primary.
- **Session as boundary**: Each conversation is a persisted session (JSON). `--continue` resumes most recent, `--attach <id>` attaches to specific.
- **Tool aliases**: 70+ name mappings bridge LLM-invented tool names to canonical registrations.
- **AnyAdapter enum**: Channel adapters use enum-based type erasure (not trait objects) for 6 IM platforms.

### Web API

90+ REST API endpoints organized by domain:
- Sessions: CRUD, chat, stream (SSE), WebSocket, status, cancel, cost, export, fork, rename, messages
- Config: get/put, models, permissions, OCR config/test
- Stats: session stats, aggregate stats
- MCP: server management endpoints
- Channels: IM channel management
- Schedules: cron task management
- Backup: configuration backup/restore
- Billing: usage and billing endpoints
- Skills: skill management, evolution history
- Browser: browser automation endpoints
- Trash: file trash management
- Brand / License: config, activate, status, heartbeat
- Files: list, read, write, upload, paths
- Onboarding: device start/poll, complete, skip-soul
- Local Image Proxy: `/api/local-image`
- Exchange Rate: `/api/exchange-rate`
- Media: image, video, audio/speech, audio/transcriptions, video/understand
- Internal OCR: `/api/internal/ocr-image`
- Version / Restart: upgrade, restart

Auth via `MBOPENCLACKY_WEB_API_KEY` env var. SPA frontend served from `web/`.

## Default Resources

```
web/                       # SPA frontend
  index.html
  css/
  js/

assets/
  agents/
    coding/
      config.toml
      system_prompt.md
    general/
      config.toml
      system_prompt.md
    SOUL.md
    USER.md
  skills/                    # 17 built-in skills
    browser_setup/
    channel_manager/
    code-explorer/
    cron-task-creator/
    deploy/
    extend-openclacky/
    mcp-manager/
    media-gen/
    new/
    onboard/
    persist-memory/
    personal_website/
    product-help/
    recall-memory/
    search-skills/
    skill_add/
    skill-creator/
```

## Current State Metrics

| Indicator | Value |
|-----------|-------|
| `.mbt` source files (total) | 272 |
| Test files (`*_wbtest.mbt`) | 62 |
| Source lines (non-test) | ~56,951 |
| Test lines (`*_wbtest.mbt`) | ~17,459 |
| Total lines (source + test) | ~74,410 |
| Test cases | 1,400+ |
| Top-level packages | 21 |
| Built-in tools | 14 |
| Provider presets | 12 |
| Default skills | 17 |
| REST API endpoints | 90+ |
| `moon check` | 0 errors, 426 warnings |
| CI/CD | ✅ GitHub Actions (`ci.yml` + `docker.yml`) |
| Specs | ✅ Harness methodology (`specs/` with templates) |
| Codemaps | ✅ 10 core packages (`codemaps/`) |
| Phase coverage | ~87-92% (backend ~95%, Web frontend ~40-50%, deploy infra ~50%) |
