# Repository Guidelines

MBOpenClacky is a MoonBit rewrite of the openclacky AI Agent CLI — an LLM-powered autonomous agent with tool calling, skill plugins, session management, TUI, and a web server.

## Project Structure & Module Organization

The module root is defined in `moon.mod` (`hnlyxiaobing/MBOpenClacky`, `preferred_target = native`).

```
cmd/              CLI entry point (clap parsing, agent lifecycle; billing subcommand wired to BillingStore; hooks/patches execute real shell commands via shell_exec.mbt with CLACKY_* env context; extension registration validates duplicate names/routes)
lib/              22 top-level packages (27 total with web subpackages + cmd)
  agent/          ReAct loop, LLM caller, session/memory/todo, time machine
  client/         LLM API client (OpenAI/Anthropic/Bedrock), SSE streaming
  config/         TOML loader, 12 provider presets, permissions
  tool/           Tool trait + 14 built-in tools (Terminal now PTY-based), registry, security
  skill/          SKILL.md parsing, registry, evolution engine; 17 default skills
  mcp/            MCP protocol (Stdio/HTTP), JSON-RPC 2.0, skill provider/virtual skill
  channel/        6 IM adapters (Feishu/Wecom/Telegram/Discord/DingTalk/Weixin)
  server/         cron scheduler, browser/backup manager, git panel
  tui/            Inline scrolling TUI (moonbit-community/tty), block_font/thinking_verbs
  web/            crescent REST server, 95+ endpoints
  parser/  media/  vision/  billing/  pricing/  ...
test/             Eval framework (module-agnostic, zero-intrusion to lib/)
  eval/           Generic eval engine (result types, file loading, reporting)
  tui/            TUI eval adapter (VirtualScreen, headless simulator, scenarios)
  scenarios/      Scenario JSON definitions (by module subdirectory)
    tui/          TUI scenarios (basic_startup, type_and_submit, input_editing)
assets/           agents, skills, web (CSS/JS), gep templates
docs/             changelog and development plans
specs/            Harness methodology (templates, active specs, completed archive)
codemaps/         Code terrain indexes for 10 core packages + 1 subsystem
.github/          CI/CD workflows (ci.yml, docker.yml)
```

Package boundaries live in `moon.pkg` files; generated public APIs in `pkg.generated.mbti`.

## Build, Test, and Development Commands

```bash
moon build --target native --release cmd  # 推荐：显式指定 cmd 包，避免 moon #1488 bug
moon build --target native cmd            # Debug 构建
moon check                              # Type-check whole project (0 errors expected)
moon run cmd                            # Run the CLI
moon run cmd -- --server                # Start web UI server (port 7070)
moon run cmd -- --message "Hello"       # Non-interactive agent mode
# TUI 交互模式推荐直接运行编译好的二进制（moon run cmd 包装器在某些终端下可能不启动 TUI）
./_build/native/debug/build/cmd/cmd.exe
moon test                               # Run white-box tests (native only)
moon test lib/agent --filter "session*" # Targeted test run
moon update && moon install             # Sync dependencies
moon fmt                                # Format source
moon info                               # Verify public API changes (mbti diff)
```

`moon test --target wasm-gc` fails on FFI in `moonbit-community/tty`/`crescent`; use `moon check` to validate.

`moon test` native requires `-lcurl` to be enabled in `lib/client/moon.pkg` and libcurl-dev installed; the flag is currently commented by default and will cause link errors otherwise.

## Coding Style & Naming Conventions

- MoonBit idioms: `struct` + `trait`, snake_case for functions/values, PascalCase for types/traits.
- Use `///|` top-level delimiters; split code into cohesive files per responsibility.
- Format with `moon fmt`. No extra linter; `moon check --warn-list +unnecessary_annotation` surfaces redundant annotations.
- Prefer `moon ide doc`/`outline`/`peek-def`/`find-references` to discover APIs before adding new code; use `moon ide rename` for refactors.

## Testing Guidelines

- Tests are co-located white-box files named `*_wbtest.mbt` next to source (e.g. `lib/agent/session_restore_wbtest.mbt`).
- Eval framework tests live in `test/` (e.g. `test/eval/eval_engine_wbtest.mbt`, `test/tui/tui_eval_adapter_wbtest.mbt`).
- Name tests descriptively around the behavior under test; keep them package-local.
- Validate after every edit with `moon check` then the relevant `moon test` scope. Use `moon test --update` for snapshot changes.
- Run TUI eval scenarios: `moon build --target native --release cmd` then `cmd.exe --tui-eval test/scenarios/tui/`

## Commit & Pull Request Guidelines

Follow the conventions in `git log`: lowercase type prefixes such as `feat:`, `fix:`, `docs:`, `chore:`, plus scoped forms like `feat(config):`. Examples: `feat(config): add TOML config loader`, `fix: migrate to moonc v0.9.3`.

- Keep commits focused; one logical change per commit.
- PRs should include a description of the change, linked issues, and `moon check`/`moon test` results.
- After edits run `moon fmt` and `moon info`; report changed files, the public API (`pkg.generated.mbti`) diff, and any residual risk.

## Agent-Specific Instructions

Keep edits minimal and package-local. Run `moon check` in a tight loop after edits. Use `#alias(old_api, deprecated)` when backward compatibility matters. Do not commit `_build/`, `.mooncakes/`, `.qoder/`, or `.repos/` — they are build/tool caches. Follow Harness methodology: create specs in `specs/active/` before starting non-trivial work, move completed specs to `specs/completed/`.
