# Repository Guidelines

MBOpenClacky is a MoonBit rewrite of the openclacky AI Agent CLI — an LLM-powered autonomous agent with tool calling, skill plugins, session management, TUI, and a web server.

## Build, Test, and Development Commands

```bash
moon build --target native --release cmd    # Build (always specify cmd, avoid moon#1488)
moon check                                  # Type-check (0 errors expected)
moon run cmd                                # Run CLI
moon run cmd -- server                    # Web server (port 7071)
moon run cmd --message "Hello"           # Non-interactive mode
./_build/native/debug/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe   # TUI mode (recommended over moon run)
moon test --release $(find lib cmd test -name moon.pkg | sed 's|/moon.pkg$||')   # Full suite (native, scoped)
moon test lib/agent --filter "session*"     # Targeted test run
cmd.exe eval --offline --repo .             # Layer 6 deterministic tool eval (in CI)
cmd.exe journey --repo .                    # Layer 9 user-journey E2E (real binary + mock upstream, 18 journeys)
moon update && moon install                 # Sync dependencies
moon fmt <changed files>                    # Format only what you touched
moon info                                   # Verify public API changes
```

- **Never bare `moon test`**: `moon.work` includes `vendor/mbtpdf`, so a bare run also executes that dependency's own tests (6 of them fail on the current toolchain and are not this repo's regression surface). Use the scoped command above; CI additionally publishes its test count from the same scope minus `lib/mcp` (run separately) — see `docs/improvement-execution-plan.md` §1.1.
- Scoped tests (the command above) work in both debug and release mode. The old compiler ICE was in vendor/mbtpdf's own test driver, which the scoped command excludes. CI uses debug mode for speed; use `--release` locally only when testing release-specific behavior.

`moon test --target wasm-gc` fails on FFI in `tty`/`crescent`; use `moon check` to validate.

## Architecture

25 lib packages + 1 cmd entry (machine-generated count — see Current Metrics). All three interfaces (CLI, TUI, Web) share the same `Agent` core via the hook system.

```
cmd/          — CLI entry (clap parsing, agent lifecycle, session management)
lib/
  agent/      — Agent struct, ReAct loop, LLM caller, system prompt, session persistence,
                hook system, memory store, todo manager, subagent pool, cost tracker,
                compressor, time machine, profile, idle timer, session restore
  client/     - LLM API client (OpenAI/Anthropic/Bedrock formats), stream aggregators,
                platform HTTP client with domain failover, 13 provider presets
  tool/       — Tool trait + 14 built-in tools (FileReader, Write, Edit, Grep, Glob,
                Terminal/PTY, WebSearch, WebFetch, InvokeSkill, MemoryTool, TodoTool,
                RequestUserFeedback, TrashManager, Browser) + registry with 70+ aliases
  skill/      - SKILL.md parsing, registry, discovery, executor, evolution engine
                (Reflector/AutoCreator), 18 default skills
  extension/  — Extension lifecycle: loader, verifier, packager, scaffold,
                marketplace, API extension dispatcher/loader, route contributions
  mcp/        — MCP protocol: Transport trait (Stdio/HTTP), JSON-RPC 2.0 client,
                registry, virtual skill mapping, skill provider
  channel/    — 6 IM adapters (Feishu/Wecom/Telegram/Discord/DingTalk/Weixin) via AnyAdapter enum
  web/        — crescent HTTP server: 214 REST routes (crescent registrations in server.mbt), WebSocket (token-level
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
  config/     - TOML loader, 13 provider presets, capabilities, permission modes, env compat
  billing/    — Billing records, token tracking, cost calculation
  brand/      — White-label config, license validation, device binding, identity
                persistence, AES-GCM/HMAC/SHA256 (C FFI)
  media/      — Image/video/audio generation logic (OpenAI/Gemini/DashScope); the four REST
                generation endpoints call these for real (binary HTTP transport lives in lib/client)
  parser/     — PDF, DOCX (ZIP+XML), PPTX, XLSX parsers
  protocol/   — 协议层（引擎事件与 wire 词表）
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

## Coding Style

- **Naming**: snake_case for functions/values, PascalCase for types/traits.
- **Architecture**: `struct` + `trait`, `enum` for ADTs, `Option[T]` instead of nil.
- Use `///|` top-level delimiters; split code into cohesive files per responsibility.
- Format **only the files you changed** (`moon fmt <file>`); a repo-wide `moon fmt` reflows unrelated files and pollutes the diff. No extra linter.
- Prefer `moon ide doc`/`outline`/`peek-def`/`find-references` to discover APIs before adding new code.

## Testing

- Tests are co-located white-box files: `*_wbtest.mbt` next to source.
- Eval framework tests live in `test/` (e.g. `test/eval/eval_engine_wbtest.mbt`).
- Validate after every edit: `moon check` then relevant `moon test` scope. To judge the whole repo as clean use `moon check -d` — `moon check <pkg-path>` can miss errors in sub-packages (and may report "no work to do").
- Layer 4 scenario replay (in-process, manual): `moon build --target native --release cmd` then `cmd.exe eval --tui test/scenarios/tui/` (Web: `eval --web test/scenarios/web/`; `--format text|json|markdown`). The unified `eval` subcommand replaced the old top-level `--tui-eval`/`--web-eval` flags.
- **Layer 9 user-journey E2E (automated, replaces manual daily testing)**: drives the REAL binary through 18 end-to-end journeys (Web WS chat 9 / TUI 3 / CLI 6) against an in-process mock LLM upstream, with sandboxed per-journey homes and three-level watchdogs (never hangs). Trigger: `moon build --target native --release cmd` then `cmd.exe journey --repo .` (add `--filter <id-prefix> --verbose` to debug one area). Exit codes: `0` all green, `1` product red (≥1 journey failed), `2` usage, `3` runner/infra broken. Failures auto-write an evidence bundle to `_build/journey/<stamp>/<id>/` and upsert the committed ledger `docs/journey-failures.md` — a scenario that goes green again auto-closes its ledger row (the fix loop). Unattended: a Windows scheduled task `MBOpenClacky Journey E2E` (daily 08:30, build-then-run) is registered on this machine; runbook and full schema in `test/journey/README.md`, spec in `specs/draft/2026-09-23_journey-e2e-runner.md`.

## Commit Guidelines

Follow lowercase type prefixes: `feat:`, `fix:`, `docs:`, `chore:`, plus scoped forms like `feat(config):`.

- Keep commits focused; one logical change per commit.
- After edits run `moon fmt <changed files>` (never repo-wide) and `moon info`; report changed files and any residual risk.

## Development Workflow (spec-driven)

Keep edits minimal and package-local. Run `moon check` in a tight loop after edits. Do not commit `_build/`, `.mooncakes/`, `.qoder/`, or `.repos/`. Follow Harness v2 methodology: create specs in `specs/draft/` first, pass adversarial review (see `specs/decisions/harness-methodology-v2-upgrade.md`), then move to `specs/active/` for development, finally archive to `specs/completed/` after acceptance.

**Harness v2 key rules**:
- Gap document is a hypothesis, not ground truth - verify every "missing" claim with `grep`/`glob` before writing spec
- Specs start in `specs/draft/`, require adversarial review before entering `specs/active/`
- All template sections marked [必填] must be filled - incomplete specs are rejected
- MoonBit AOT constraint: runtime-loaded extensions cannot implement traits - use shell commands instead
- Verify crescent API capabilities (PATCH/PUT/DELETE) with `grep` before claiming "not supported"

**Codebase-memory MCP 优先**（仅当当前会话确实连接了该 server 时；未连接就直接用 Grep/Glob/Read，不要反复试错）: 查询代码时优先使用 codebase-memory-mcp 工具（项目名 `D-MoonBit-MBOpenClacky`）以提高效率、节省 token：
- 查找定义/实现/关系 → `search_graph`（BM25 全文）、`search_code`（grep + 图增强）
- 找调用方/依赖/影响分析/数据流 → `trace_path`
- 读函数/类源码 → `get_code_snippet`（先 `search_graph` 拿 qualified_name）
- 架构概览 → `get_architecture`；复杂多跳查询 → `query_graph`
- 大量代码改动后运行 `index_repository` 更新索引
仅当 MCP 无法覆盖时（如精确字符串匹配、非代码文件）再退回 Grep/Glob/Read。

## Development Efficiency Protocol

Empirically derived from 113 recorded development sessions (2026-06 → 2026-08). These rules prevent the top token/cost wasters. Detailed data and case studies: `docs/development-efficiency.md`.

1. **Model tiering (biggest cost lever — up to 3000×)**. Execution-type work (implementing specs, fixing compile errors, writing tests, refactoring) must run on cheap models. Reserve expensive models for genuinely complex reasoning (architecture design, FFI memory layout, adversarial spec review). Never run a whole harness/spec batch on a premium model.

2. **Read whole files, never grep-bite**. When exploring a file, use `file_reader` once to read it fully instead of 5-9 small `grep` probes against the same file. Grep only when you need precise matches across many files. For API discovery prefer `moon ide doc`; for codebase queries prefer the codebase-memory MCP (above).

3. **Confirm build commands before guessing**. At the start of any session touching code: `moon version`, then confirm the build command from this file's Build section or README. Never try `warren build`, `moon build` bare, etc. in a trial-and-error loop — it wastes 5-10 iterations.

4. **Read the full error before retrying**. On `moon check`/`moon build`/`moon test` failure, capture the complete error (`2>&1 | tail -50`, or `moon check --output-json 2>&1 | jq`), diagnose the root cause, then fix. Do not blindly retry or tweak random code — this is the #2 token waster.

5. **Keep sessions short; offload knowledge**. Tasks that exceed ~50 messages should be split: commit progress to git, then start a new session that loads only the spec + git state. After reading a large document, immediately write its key points into the todo list or a notes file — long-session compression makes the agent forget what it read, causing 3-4× re-reads.

6. **Batch independent tool calls**. Combine independent reads/checks into a single assistant message (e.g. read all related spec files at once). Reduces round-trips and overhead tokens.

## Current Metrics

Machine-generated by `scripts/repo_stats.sh` (`generate`), verified by `scripts/repo_stats.sh check` in CI — a hand-edited number turns the build red. Calibers are defined in the script header.

<!-- BEGIN: repo-stats (generated by scripts/repo_stats.sh; do not edit) -->
| 指标 | 数值 |
|------|------|
| 版本（moon.mod / cmd VERSION / tui / web 四处一致） | 0.2.0 |
| 源代码文件（`.mbt`，lib+cmd，不含测试） | 316 |
| 测试文件（`*_wbtest.mbt` + `*_test.mbt`） | 240 |
| 源代码行数 | 105,921 |
| 测试行数 | 65,633 |
| 总行数 | 171,554 |
| 测试用例（`moon test --release`，本模块 scoped 口径；CI 该步不含 lib/mcp，另一步单独跑） | 4074 |
| 包（lib 一级包 / cmd 入口 / `moon.pkg` 总数） | 25 / 1 / 30 |
| `pkg.generated.mbti`（git 入库） | 32 |
| Provider 预设 | 13 |
| 内置工具 | 14 |
| 默认 Skill | 16 |
| REST 路由注册（crescent，`lib/web/server.mbt`） | 214（GET 86 / POST 86 / PATCH 15 / DELETE 18 / PUT 9） |
| `moon check` | 0 errors / 0 warnings |
<!-- END: repo-stats -->
