# Repository Guidelines

MBOpenClacky is a MoonBit rewrite of the openclacky AI Agent CLI. For project architecture and key patterns, see [CLAUDE.md](CLAUDE.md).

## Build, Test, and Development Commands

```bash
moon build --target native --release cmd    # Build (always specify cmd, avoid moon#1488)
moon check                                  # Type-check (0 errors expected)
moon run cmd                                # Run CLI
moon run cmd -- server                    # Web server (port 7071)
moon run cmd --message "Hello"           # Non-interactive mode
./_build/native/debug/build/cmd/cmd.exe     # TUI mode (recommended over moon run)
moon test                                   # Native only
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

**Codebase-memory MCP 优先**: 查询代码时优先使用 codebase-memory-mcp 工具（项目名 `D-MoonBit-MBOpenClacky`）以提高效率、节省 token：
- 查找定义/实现/关系 → `search_graph`（BM25 全文）、`search_code`（grep + 图增强）
- 找调用方/依赖/影响分析/数据流 → `trace_path`
- 读函数/类源码 → `get_code_snippet`（先 `search_graph` 拿 qualified_name）
- 架构概览 → `get_architecture`；复杂多跳查询 → `query_graph`
- 大量代码改动后运行 `index_repository` 更新索引
仅当 MCP 无法覆盖时（如精确字符串匹配、非代码文件）再退回 Grep/Glob/Read。

**Harness v2 key rules**:
- Gap document is a hypothesis, not ground truth - verify every "missing" claim with `grep`/`glob` before writing spec
- Specs start in `specs/draft/`, require adversarial review before entering `specs/active/`
- All template sections marked [必填] must be filled - incomplete specs are rejected
- MoonBit AOT constraint: runtime-loaded extensions cannot implement traits - use shell commands instead
- Verify crescent API capabilities (PATCH/PUT/DELETE) with `grep` before claiming "not supported"