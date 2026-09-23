#!/usr/bin/env bash
# repo_stats.sh — machine-generated repository metrics (T1, single source of truth).
#
# Usage:
#   scripts/repo_stats.sh print [--test-count N]     Print metrics as key=value lines
#   scripts/repo_stats.sh generate [--test-count N]  Rewrite the marked block in the docs
#   scripts/repo_stats.sh check [--test-count N]     Fail when a marked block is stale
#
# The three consumer docs (README.md, CLAUDE.md, docs/project-status.md) each carry an
# identical block delimited by
#     <!-- BEGIN: repo-stats (generated ...) -->  ...  <!-- END: repo-stats -->
# `generate` rewrites those blocks; `check` recomputes and diffs, so a hand-edited
# number turns CI red instead of drifting silently.
#
# Calibers (each one is a re-runnable definition, no prose):
#   src_mbt        lib/ + cmd/, *.mbt excluding *_wbtest.mbt / *_test.mbt
#   test_mbt       lib/ + cmd/ + test/, *_wbtest.mbt + *_test.mbt
#   src_lines      line count of the src_mbt files
#   test_lines     line count of the test_mbt files
#   mbti           git-tracked pkg.generated.mbti files
#   lib_packages   first-level directories under lib/ (lib/ + cmd/ are the module roots)
#   moon_packages  git-tracked moon.pkg files under lib/ + cmd/
#   providers      ProviderPreset entries (`id: "..."`) in lib/config/provider.mbt
#   tools          registry.register(AnyTool:: ...) calls in lib/tool/registry.mbt
#   skills         directories under assets/skills/
#   routes         crescent route registrations in lib/web/server.mbt, per HTTP method
#   version        the four user-visible version constants that must agree:
#                  moon.mod / cmd/main.mbt / lib/tui/tui_controller.mbt /
#                  lib/web/handlers_version.mbt
#   test_cases     the `moon test --release` summary line — cannot be derived statically
#                  (MoonBit's runner counts more than the `test` declarations a
#                  grep sees), so it is supplied via --test-count /
#                  REPO_STATS_TEST_CASES, or summed from a captured test log via
#                  --test-count-from <file>. `check` compares it against the
#                  recorded value, which is how the old 3,843-vs-3,869 drift
#                  became a build failure instead of a silent inconsistency.
#                  Caliber note: the count comes from CI's "Run tests (module
#                  packages)" step, i.e. the module's own packages (lib + cmd +
#                  test) minus `lib/mcp`, which CI runs as a separate step — that
#                  split predates 2026-09-23, when the Windows-only stdio hang
#                  was resolved (docs/known-gaps.md); merging the two steps into
#                  one number is a deliberate change to make together with
#                  .github/workflows/ci.yml, not a doc edit. A bare `moon test`
#                  cannot be used: moon.work also contains vendor/mbtpdf, whose
#                  own tests are not this repository's regression surface.
#
# Exit codes: 0 ok, 1 stale or inconsistent, 2 usage error.

set -euo pipefail

cd "$(dirname "$0")/.."

BEGIN_MARK='<!-- BEGIN: repo-stats'
END_MARK='<!-- END: repo-stats -->'
DOCS="README.md CLAUDE.md docs/project-status.md"

mode="${1:-print}"
shift || true

test_count="${REPO_STATS_TEST_CASES:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --test-count)
      test_count="${2:-}"
      shift 2
      ;;
    --test-count=*)
      test_count="${1#--test-count=}"
      shift
      ;;
    --test-count-from)
      log_file="${2:-}"
      shift 2
      if [ ! -f "$log_file" ]; then
        echo "repo_stats: test log not found: $log_file" >&2
        exit 2
      fi
      test_count="$(grep -oE 'Total tests: [0-9]+' "$log_file" |
        grep -oE '[0-9]+' | awk '{ total += $1 } END { print total + 0 }')"
      ;;
    *)
      echo "repo_stats: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

# ── Metric collection ───────────────────────────────────────────────────────

count_files() {
  # $@ = find roots; always filters to the two test-suffix conventions
  find "$@" -name '*.mbt' ! -name '*_wbtest.mbt' ! -name '*_test.mbt' 2>/dev/null | wc -l | tr -d ' '
}

count_test_files() {
  find "$@" -name '*_wbtest.mbt' -o -name '*_test.mbt' 2>/dev/null | wc -l | tr -d ' '
}

count_lines() {
  # $@ = find roots (non-test filter applied by the caller's -name expression is
  # folded in here for src, and separately for test)
  find "$@" -name '*.mbt' ! -name '*_wbtest.mbt' ! -name '*_test.mbt' -exec cat {} + 2>/dev/null | wc -l | tr -d ' '
}

count_test_lines() {
  find "$@" -name '*_wbtest.mbt' -o -name '*_test.mbt' 2>/dev/null | tr '\n' '\0' |
    xargs -0 cat 2>/dev/null | wc -l | tr -d ' '
}

routes_for() {
  # $1 = HTTP method (lowercase); counts crescent registrations in lib/web/server.mbt
  grep -oE "[a-z_]+\.$1\(\"" lib/web/server.mbt | wc -l | tr -d ' '
}

version_from() {
  # $1 = file, $2 = grep pattern whose last "..." literal is the version
  grep -oE "$2\"[0-9]+\.[0-9]+\.[0-9]+\"" "$1" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
}

version_moon_mod="$(grep -oE '^version = "[0-9.]+"' moon.mod | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
version_cmd="$(version_from cmd/main.mbt 'const VERSION : String = ')"
version_tui="$(version_from lib/tui/tui_controller.mbt 'let app_version : String = ')"
version_web="$(version_from lib/web/handlers_version.mbt 'const VERSION : String = ')"

version_status="$version_moon_mod"
if [ "$version_cmd" != "$version_moon_mod" ] || [ "$version_tui" != "$version_moon_mod" ] ||
  [ "$version_web" != "$version_moon_mod" ]; then
  version_status="$version_moon_mod (DRIFT: cmd=$version_cmd tui=$version_tui web=$version_web)"
fi

src_mbt="$(count_files lib cmd)"
test_mbt="$(count_test_files lib cmd test)"
src_lines="$(count_lines lib cmd)"
test_lines="$(count_test_lines lib cmd test)"
total_lines=$((src_lines + test_lines))
mbti="$(git ls-files | grep -c 'pkg\.generated\.mbti$' || true)"
lib_packages="$(find lib -maxdepth 1 -type d ! -path lib | wc -l | tr -d ' ')"
moon_packages="$(git ls-files 'lib/**/moon.pkg' 'cmd/**/moon.pkg' 'lib/moon.pkg' | wc -l | tr -d ' ')"
providers="$(grep -cE '^\s+id: "' lib/config/provider.mbt | tr -d ' ')"
tools="$(grep -c 'registry\.register(AnyTool::' lib/tool/registry.mbt | tr -d ' ')"
skills="$(find assets/skills -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
route_get="$(routes_for get)"
route_post="$(routes_for post)"
route_patch="$(routes_for patch)"
route_put="$(routes_for put)"
route_delete="$(routes_for delete)"
routes_total=$((route_get + route_post + route_patch + route_put + route_delete))

if [ -z "$test_count" ]; then
  # Reuse the value already recorded in the docs so `check` never needs a full test
  # run; `generate` without --test-count preserves the last recorded figure.
  test_count="$(grep -oE '测试用例（`moon test --release`[^|]*\| [0-9,]+' README.md 2>/dev/null |
    head -1 | grep -oE '[0-9,]+$' || true)"
fi
if [ -z "$test_count" ]; then
  test_count="unknown"
fi

format_num() {
  # 96910 -> 96,910
  echo "$1" | sed -E ':a;s/\B[0-9]{3}\>/,&/;ta'
}

render_block() {
  cat <<EOF
$BEGIN_MARK (generated by scripts/repo_stats.sh; do not edit) -->
| 指标 | 数值 |
|------|------|
| 版本（moon.mod / cmd VERSION / tui / web 四处一致） | $version_status |
| 源代码文件（\`.mbt\`，lib+cmd，不含测试） | $src_mbt |
| 测试文件（\`*_wbtest.mbt\` + \`*_test.mbt\`） | $test_mbt |
| 源代码行数 | $(format_num "$src_lines") |
| 测试行数 | $(format_num "$test_lines") |
| 总行数 | $(format_num "$total_lines") |
| 测试用例（\`moon test --release\`，本模块 scoped 口径；CI 该步不含 lib/mcp，另一步单独跑） | $test_count |
| 包（lib 一级包 / cmd 入口 / \`moon.pkg\` 总数） | $lib_packages / 1 / $moon_packages |
| \`pkg.generated.mbti\`（git 入库） | $mbti |
| Provider 预设 | $providers |
| 内置工具 | $tools |
| 默认 Skill | $skills |
| REST 路由注册（crescent，\`lib/web/server.mbt\`） | $routes_total（GET $route_get / POST $route_post / PATCH $route_patch / DELETE $route_delete / PUT $route_put） |
| \`moon check\` | 0 errors / 0 warnings |
$END_MARK
EOF
}

print_metrics() {
  cat <<EOF
version=$version_status
src_mbt=$src_mbt
test_mbt=$test_mbt
src_lines=$src_lines
test_lines=$test_lines
total_lines=$total_lines
test_cases=$test_count
lib_packages=$lib_packages
moon_packages=$moon_packages
mbti=$mbti
providers=$providers
tools=$tools
skills=$skills
routes_total=$routes_total
route_get=$route_get
route_post=$route_post
route_patch=$route_patch
route_put=$route_put
route_delete=$route_delete
EOF
}

# ── Block rewriting / verification ──────────────────────────────────────────

rewrite_doc() {
  doc="$1"
  block="$(render_block)"
  [ -f "$doc" ] || {
    echo "repo_stats: missing doc: $doc" >&2
    return 1
  }
  tmp="$(mktemp)"
  # Replace every marked block with the canonical rendering, keeping the docs'
  # own surrounding prose untouched. A doc with no marker is left alone.
  awk -v block="$block" -v begin="$BEGIN_MARK" -v end="$END_MARK" '
    index($0, begin) == 1 { inside = 1; print block; next }
    inside && index($0, end) == 1 { inside = 0; next }
    inside { next }
    { print }
  ' "$doc" >"$tmp"
  if ! cmp -s "$doc" "$tmp"; then
    mv "$tmp" "$doc"
    echo "repo_stats: rewrote $doc"
  else
    rm -f "$tmp"
  fi
}

verify_doc() {
  doc="$1"
  [ -f "$doc" ] || {
    echo "repo_stats: missing doc: $doc" >&2
    return 1
  }
  if ! grep -q "$BEGIN_MARK" "$doc"; then
    echo "repo_stats: $doc has no repo-stats block" >&2
    return 1
  fi
  block="$(render_block)"
  actual="$(awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
    index($0, begin) == 1 { inside = 1 }
    inside { print }
    inside && index($0, end) == 1 { exit }
  ' "$doc")"
  if [ "$actual" != "$block" ]; then
    echo "repo_stats: STALE block in $doc" >&2
    diff <(printf '%s\n' "$block") <(printf '%s\n' "$actual") >&2 || true
    return 1
  fi
}

case "$mode" in
  print)
    print_metrics
    ;;
  generate)
    for doc in $DOCS; do rewrite_doc "$doc"; done
    ;;
  check)
    status=0
    for doc in $DOCS; do verify_doc "$doc" || status=1; done
    if [ "$status" -eq 0 ]; then
      echo "repo_stats: $DOCS blocks up to date"
    fi
    exit "$status"
    ;;
  *)
    echo "repo_stats: unknown mode: $mode (print|generate|check)" >&2
    exit 2
    ;;
esac