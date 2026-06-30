# Repository Guidelines

MBOpenClacky is a MoonBit rewrite of the openclacky AI Agent CLI — an LLM-powered autonomous agent with tool calling, skill plugins, session management, TUI, and a web server.

## Project Structure & Module Organization

The module root is defined in `moon.mod` (`hnlyxiaobing/MBOpenClacky`, `preferred_target = native`).

```
cmd/              CLI entry point (clap parsing, agent lifecycle)
lib/              21 top-level packages
  agent/          ReAct loop, LLM caller, session/memory/todo, time machine
  client/         LLM API client (OpenAI/Anthropic/Bedrock), SSE streaming
  config/         TOML loader, 12 provider presets, permissions
  tool/           Tool trait + 14 built-in tools, registry, security
  skill/          SKILL.md parsing, registry, evolution engine
  mcp/            MCP protocol (Stdio/HTTP), JSON-RPC 2.0
  channel/        6 IM adapters (Feishu/Wecom/Telegram/Discord/DingTalk/Weixin)
  server/         cron scheduler, browser/backup manager, git panel
  tui/  web/  parser/  media/  vision/  billing/  pricing/  ...
assets/           agents, skills, web (CSS/JS), gep templates
docs/             changelog and development plans
```

Package boundaries live in `moon.pkg` files; generated public APIs in `pkg.generated.mbti`.

## Build, Test, and Development Commands

```bash
moon check                              # Type-check whole project (0 errors expected)
moon build                              # Build native binary
moon run cmd                            # Run the CLI
moon run cmd -- --message "Hello"       # Non-interactive agent mode
moon run cmd -- --server                # Start web UI server (port 4000)
moon test                               # Run white-box tests (native only)
moon test lib/agent --filter "session*" # Targeted test run
moon update && moon install             # Sync dependencies
moon fmt                                # Format source
moon info                               # Verify public API changes (mbti diff)
```

`moon test --target wasm-gc` fails on FFI in `onebit-tui`/`crescent`; use `moon check` to validate.

## Coding Style & Naming Conventions

- MoonBit idioms: `struct` + `trait`, snake_case for functions/values, PascalCase for types/traits.
- Use `///|` top-level delimiters; split code into cohesive files per responsibility.
- Format with `moon fmt`. No extra linter; `moon check --warn-list +unnecessary_annotation` surfaces redundant annotations.
- Prefer `moon ide doc`/`outline`/`peek-def`/`find-references` to discover APIs before adding new code; use `moon ide rename` for refactors.

## Testing Guidelines

- Tests are co-located white-box files named `*_wbtest.mbt` next to source (e.g. `lib/agent/session_restore_wbtest.mbt`).
- Name tests descriptively around the behavior under test; keep them package-local.
- Validate after every edit with `moon check` then the relevant `moon test` scope. Use `moon test --update` for snapshot changes.

## Commit & Pull Request Guidelines

Follow the conventions in `git log`: lowercase type prefixes such as `feat:`, `fix:`, `docs:`, `chore:`, plus scoped forms like `feat(config):`. Examples: `feat(config): add TOML config loader`, `fix: migrate to moonc v0.9.3`.

- Keep commits focused; one logical change per commit.
- PRs should include a description of the change, linked issues, and `moon check`/`moon test` results.
- After edits run `moon fmt` and `moon info`; report changed files, the public API (`pkg.generated.mbti`) diff, and any residual risk.

## Agent-Specific Instructions

Keep edits minimal and package-local. Run `moon check` in a tight loop after edits. Use `#alias(old_api, deprecated)` when backward compatibility matters. Do not commit `_build/`, `.mooncakes/`, `.qoder/`, or `.repos/` — they are build/tool caches.
