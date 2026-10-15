# Repository Guidelines

MBOpenClacky is a MoonBit rewrite of the openclacky AI Agent CLI — an LLM-powered autonomous agent with tool calling, skill plugins, session management, TUI, and a web server.

## Build, Test, and Development Commands

```bash
moon build --target native --release cmd    # Build (always specify cmd, avoid moon#1488)
moon check -d                               # Whole-repo type check (0 errors/warnings)
moon run cmd                                # Run CLI/TUI
moon run cmd -- server                    # Web server (default 127.0.0.1:7071)
moon run cmd --message "Hello"           # Non-interactive mode
./_build/native/release/build/cmd/cmd.exe   # Binary produced by the build command above
moon test --release $(find lib cmd test -name moon.pkg | sed 's|/moon.pkg$||')   # Full module suite
moon test lib/agent --filter "session*"     # Targeted test run
cmd.exe eval --offline --repo .             # Layer 6 deterministic eval
cmd.exe journey --repo .                    # Layer 9 user journeys (25 scenarios)
moon update                                 # Resolve dependencies
moon fmt <changed files>                    # Format only changed files
moon info                                   # Verify public API changes
```

- **Binary path trap**: `moon build --target native --release cmd` writes `_build/native/release/build/cmd/cmd.exe`. A stale `_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe` from a full-module build also sits in the tree and is *not* refreshed by that command. Verifying against it silently tests old code — always use the `build/cmd/` path, or delete the nested one.
- **Never bare `moon test`**: it also walks `third_party/clap`, which is vendored upstream code (a package inside this module, no own `moon.mod`) and not this repo's regression surface. `moon.work` currently lists only `.`; the old `vendor/mizchi-*` members are gone. Use the scoped command above, which is also what CI and `scripts/repo_stats.sh` count.
- **A green run is not proof the test can fail.** `moon check ./lib/<pkg>` and package-scoped `moon test` can reuse a cached build immediately after you edit that package, so an edit may be judged against objects from before the edit. After adding or changing a test, break the thing it guards, re-run, and confirm it goes red — then restore. Only a demonstrated failure proves the assertion.
- CI runs `lib cmd test` minus `lib/mcp` in the main test step, then runs `lib/mcp` separately. `scripts/repo_stats.sh` records the main-step count; do not silently mix the two logs.
- Scoped tests work in debug and release. CI uses debug for speed; use `--release` for release-specific behavior.
- `moon test --target wasm-gc` fails on native FFI in `tty`/`crescent`; use `moon check` to validate wasm-gc typing.

## Architecture

25 `lib/` packages plus the `cmd/` entry. CLI, TUI, and Web consume the same Agent core through hooks.

```text
cmd/          CLI parsing, lifecycle, session management
lib/agent/    ReAct loop, LLM caller, prompts, sessions, hooks, memory, todos,
              subagents, cost tracking, compression, Time Machine, profiles
lib/client/   OpenAI/Anthropic/Bedrock formats, stream aggregation, HTTP/failover
lib/tool/     14 registered AnyTool implementations + aliases + PTY/security layers
lib/skill/    SKILL.md parsing/discovery/execution + GEP reflector/auto-creator
lib/extension/ loader, verifier, packager, scaffold, marketplace, Patch/API contributions
lib/mcp/      Stdio + Streamable HTTP/SSE transports, JSON-RPC, virtual skills
lib/channel/  Feishu/WeCom/Telegram/Discord/DingTalk/Weixin adapters
lib/web/      crescent server, 214 route registrations, WebSocket, middleware
lib/tui/      inline scrolling + commit-scrollback, signals, dialogs, editor
lib/server/   cron/scheduler, browser manager, backup, discover, git panel
lib/config/   TOML, 13 provider presets, capabilities, permission modes, env compat
lib/protocol/ typed engine events and wire vocabulary
others/       billing, brand, media, parser, vision, pricing, message, hook,
              telemetry, errors, i18n, utils, zip
web/          native JS frontend
test/         layers 1-9, Playwright browser E2E, fixtures
assets/       agent profiles, 16 default skills, 10 bundled extensions
```

Additional facts that documentation must keep precise:

- Tool count is 14 registered `AnyTool` values. PTY is a terminal capability; security is a policy layer.
- `assets/skills/` has 16 skills. Bundled extensions add `ext-develop`, `meeting-summarizer`, and `extend-openclacky`; the latter two ship with default-off extensions.
- Sessions use JSON snapshots plus append-only JSONL event logs. Legacy JSON/Debug-repr sessions are read-only compatibility inputs.
- Channel receive paths are wired: webhook, Telegram long polling, WeCom WebSocket, Discord Gateway, DingTalk Stream Mode. Platform-unsupported edit/delete paths return errors.
- Native is the release target. wasm-gc fallbacks and other limitations belong in `docs/known-gaps.md`.

## Agent Core

- ReAct loop: `think()` → `act()` → `observe()`, including truncation recovery.
- LLM fallback: primary success, retryable failure threshold, fallback activation, cooldown/probe, primary restoration.
- System prompt is assembled from identity/profile, rules, project context, model info, skills, memory, and tasks.
- Sessions are JSON snapshots; event history is append-only JSONL and replayable with `cmd inspect`.
- Hooks use observer semantics: `HookManager::register(cb)` / `emit(event)`.
- Tools use `AnyTool` enum dispatch; aliases bridge common LLM names to canonical tools.

## Coding Style

- snake_case functions/values, PascalCase types/traits.
- Prefer `struct` + `trait`, `enum` for ADTs, `Option[T]` instead of nil.
- Use `///|` top-level delimiters and split files by responsibility.
- Format only changed files with `moon fmt <file>`. Never run repo-wide formatting just to clean unrelated files.
- Prefer `moon ide doc`, `outline`, `peek-def`, and `find-references` before adding API surface.

## Testing

- Co-located white-box tests use `*_wbtest.mbt` next to source.
- Eval and harness tests live under `test/`.
- After edits run `moon check`, then the relevant `moon test` scope. Use `moon check -d` to judge the whole repo; package-only checks can miss subpackages.
- Layer 4 replay: `cmd.exe eval --tui test/scenarios/tui/` and `eval --web test/scenarios/web/`. The old `--tui-eval`/`--web-eval` flags remain deprecated compatibility paths.
- Layer 9 journey: build release, then `cmd.exe journey --repo .`; 25 scenarios cover Web 9 / TUI 5 / CLI 11. Failures write evidence under `_build/journey/` and update `docs/journey-failures.md`.
- Browser E2E is in `test/web-e2e/` and is manual/local; it currently contains machine-specific Playwright paths.

## Commit Guidelines

Use lowercase type prefixes: `feat:`, `fix:`, `docs:`, `chore:`, or scoped forms such as `feat(config):`.

Keep commits focused. After edits run `moon fmt <changed files>` and `moon info`; report changed files and residual risk. Do not commit `_build/`, `.mooncakes/`, `.qoder/`, or `.repos/`.

## Development Workflow

Keep edits minimal and package-local. Run `moon check` in a tight loop. Follow Harness v2:

1. Draft in `specs/draft/`.
2. Verify every gap claim against source before writing the spec.
3. Fill all `[必填]` template sections and pass adversarial review.
4. Move to `specs/active/` for development.
5. Archive to `specs/completed/` after acceptance.

MoonBit AOT constraint: runtime-loaded extensions cannot implement traits; use shell commands for extension behavior. Verify crescent capabilities in source before documenting them.

### Codebase Knowledge Graph

When connected, prefer codebase-memory MCP for code discovery (project `D-MoonBit-MBOpenClacky`):

- `search_graph` for definitions/implementations/relationships.
- `search_code` for graph-enriched grep.
- `trace_path` for callers/dependencies/data flow.
- `get_code_snippet` after obtaining a qualified name.
- `get_architecture` / `query_graph` for overview and multi-hop analysis.
- Re-index after large code changes.

Current index coverage for this repository (verified 2026-10-14):

- The graph reliably exposes the native JavaScript frontend, C FFI, YAML/TOML/Bash configuration, and related call/config edges.
- MoonBit `.mbt` symbols are not reliably represented. For example, `AgentConfig::load_with_env`, `TelegramAdapter`, and `MediaGenerator` return no graph nodes even though they exist in source.
- Therefore, a zero-result `search_graph` for MoonBit is an index-coverage limitation, not proof that a symbol is absent. Switch to `moon ide` and direct source reads immediately.
- Repository-wide counts and generated claims remain authoritative in `scripts/repo_stats.sh`; TODO/stub state remains authoritative in `scripts/known_gaps.sh`.
- The current index excludes `.git`, `.mooncakes`, `_build`, `vendor`, `deploy`, `web/vendor`, Playwright output directories, and some asset directories.
- ADR-0002 records these coverage limits and the required truth-source fallbacks.

If the MCP is unavailable or incomplete, fall back to Grep/Glob/Read immediately rather than repeatedly retrying it. Use direct search for exact string literals, configs, scripts, and non-code files.

## Development Efficiency Protocol

Derived from recorded development sessions; details are in `docs/development-efficiency.md`.

1. Use cheap models for execution work and reserve expensive models for architecture/FFI/adversarial review.
2. Read target files whole; use grep for precise cross-file matches and `moon ide doc` for APIs.
3. Confirm `moon version` and build commands before guessing.
4. Read the full build/test error before changing code.
5. Split tasks beyond ~50 messages; record key facts outside the conversation.
6. Batch independent reads/checks.

## Current Metrics

Machine-generated by `scripts/repo_stats.sh`; do not edit the block.

<!-- BEGIN: repo-stats (generated by scripts/repo_stats.sh; do not edit) -->
| 指标 | 数值 |
|------|------|
| 版本（moon.mod / cmd VERSION / tui / web 四处一致） | 0.3.0 |
| 源代码文件（`.mbt`，lib+cmd，不含测试） | 316 |
| 测试文件（`*_wbtest.mbt` + `*_test.mbt`） | 241 |
| 源代码行数 | 106,287 |
| 测试行数 | 65,831 |
| 总行数 | 172,118 |
| 测试用例（`moon test --release`，本模块 scoped 口径；CI 该步不含 lib/mcp，另一步单独跑） | 4080 |
| 包（lib 一级包 / cmd 入口 / `moon.pkg` 总数） | 25 / 1 / 30 |
| `pkg.generated.mbti`（git 入库） | 32 |
| Provider 预设 | 13 |
| 内置工具 | 14 |
| 默认 Skill | 16 |
| REST 路由注册（crescent，`lib/web/server.mbt`） | 214（GET 86 / POST 86 / PATCH 15 / DELETE 18 / PUT 9） |
| `moon check` | 0 errors / 0 warnings |
<!-- END: repo-stats -->
