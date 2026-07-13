# Repository Guidelines

MBOpenClacky is a MoonBit rewrite of the openclacky AI Agent CLI. For project architecture and key patterns, see [CLAUDE.md](CLAUDE.md).

## Build, Test, and Development Commands

```bash
moon build --target native --release cmd    # Build (always specify cmd, avoid moon#1488)
moon check                                  # Type-check (0 errors expected)
moon run cmd                                # Run CLI
moon run cmd -- --server                    # Web server (port 7070)
moon run cmd -- --message "Hello"           # Non-interactive mode
./_build/native/debug/build/cmd/cmd.exe     # TUI mode (recommended over moon run)
moon test                                   # Native only; needs -lcurl in lib/client/moon.pkg
moon test lib/agent --filter "session*"     # Targeted test run
moon update && moon install                 # Sync dependencies
moon fmt                                    # Format source
moon info                                   # Verify public API changes
```

`moon test --target wasm-gc` fails on FFI in `tty`/`crescent`; use `moon check` to validate.

## Coding Style

- **Naming**: snake_case for functions/values, PascalCase for types/traits.
- **Architecture**: `struct` + `trait`, `enum` for ADTs, `Option[T]` instead of nil.
- Use `///|` top-level delimiters; split code into cohesive files per responsibility.
- Format with `moon fmt`. No extra linter.
- Prefer `moon ide doc`/`outline`/`peek-def`/`find-references` to discover APIs before adding new code.

## Testing

- Tests are co-located white-box files: `*_wbtest.mbt` next to source.
- Eval framework tests live in `test/` (e.g. `test/eval/eval_engine_wbtest.mbt`).
- Validate after every edit: `moon check` then relevant `moon test` scope.
- Run TUI eval scenarios: `moon build --target native --release cmd` then `cmd.exe --tui-eval test/scenarios/tui/`

## Commit Guidelines

Follow lowercase type prefixes: `feat:`, `fix:`, `docs:`, `chore:`, plus scoped forms like `feat(config):`.

- Keep commits focused; one logical change per commit.
- After edits run `moon fmt` and `moon info`; report changed files and any residual risk.

## Agent Instructions

Keep edits minimal and package-local. Run `moon check` in a tight loop after edits. Do not commit `_build/`, `.mooncakes/`, `.qoder/`, or `.repos/`. Follow Harness methodology: create specs in `specs/draft/` first, pass adversarial review (see `specs/decisions/harness-methodology-v2-upgrade.md`), then move to `specs/active/` for development, finally archive to `specs/completed/` after acceptance.

**Harness v2 key rules**:
- Gap document is a hypothesis, not ground truth - verify every "missing" claim with `grep`/`glob` before writing spec
- Specs start in `specs/draft/`, require adversarial review before entering `specs/active/`
- All template sections marked [必填] must be filled - incomplete specs are rejected
- MoonBit AOT constraint: runtime-loaded extensions cannot implement traits - use shell commands instead
- Verify crescent API capabilities (PATCH/PUT/DELETE) with `grep` before claiming "not supported"