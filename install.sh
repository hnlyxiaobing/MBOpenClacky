#!/usr/bin/env bash
# MBOpenClacky installation script for macOS/Linux.
#
# Usage:
#   chmod +x install.sh
#   ./install.sh
#
# Or from a custom project root:
#   PROJECT_ROOT=/path/to/MBOpenClacky ./install.sh

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"

# ── Helpers ─────────────────────────────────────────────────────────────────

step()  { printf "\n\033[36m>> %s\033[0m\n" "$1"; }
ok()    { printf "  \033[32m[OK]\033[0m %s\n" "$1"; }
warn()  { printf "  \033[33m[!]\033[0m %s\n" "$1"; }
err()   { printf "  \033[31m[ERROR]\033[0m %s\n" "$1"; }

# ── Step 1: Check moon ──────────────────────────────────────────────────────

step "Checking MoonBit toolchain..."

if ! command -v moon &>/dev/null; then
    err "moon command not found."
    echo "  Please install MoonBit from https://www.moonbitlang.com/download/"
    echo "  Then add it to PATH and re-run this script."
    echo ""
    echo "  Quick install (if available):"
    echo "    curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash"
    exit 1
fi

MOON_VERSION=$(moon version 2>&1 | head -1)
ok "moon found: $MOON_VERSION"

# ── Step 2: Check C compiler ────────────────────────────────────────────────

step "Checking C compiler..."

HAS_CC=false
CC_NAME=""

if command -v cc &>/dev/null; then
    CC_NAME=$(cc --version 2>&1 | head -1 || echo "cc")
    HAS_CC=true
elif command -v gcc &>/dev/null; then
    CC_NAME=$(gcc --version 2>&1 | head -1 || echo "gcc")
    HAS_CC=true
elif command -v clang &>/dev/null; then
    CC_NAME=$(clang --version 2>&1 | head -1 || echo "clang")
    HAS_CC=true
fi

if [ "$HAS_CC" = true ]; then
    ok "C compiler found: $CC_NAME"
else
    warn "No C compiler (cc/gcc/clang) found in PATH."
    echo "  Native builds require a C compiler."
    echo ""
    echo "  macOS:"
    echo "    xcode-select --install"
    echo ""
    echo "  Ubuntu/Debian:"
    echo "    sudo apt-get install build-essential"
    echo ""
    echo "  Fedora:"
    echo "    sudo dnf install gcc"
    echo ""
    echo "  You can still build for wasm-gc without a C compiler."
fi

# ── Step 3: Update & install dependencies ───────────────────────────────────

step "Updating MoonBit package index..."

cd "$PROJECT_ROOT"
moon update
ok "Package index updated."

step "Installing project dependencies..."

moon install
ok "Dependencies installed."

# ── Step 4: Build ────────────────────────────────────────────────────────────

if [ "$HAS_CC" = true ]; then
    BUILD_TARGET="native"
else
    BUILD_TARGET="wasm-gc"
fi

step "Building project (target: $BUILD_TARGET)..."

if ! moon build --target "$BUILD_TARGET"; then
    err "moon build failed (exit code: $?)"
    echo "  Run 'moon check' for detailed error information."
    exit 1
fi
ok "Build succeeded."

# ── Step 5: Verify build artifacts ──────────────────────────────────────────

step "Verifying build artifacts..."

BUILD_DIR="$PROJECT_ROOT/_build/$BUILD_TARGET/release/build"

if [ "$BUILD_TARGET" = "native" ]; then
    # Look for executable in cmd subdirectory
    EXE=$(find "$BUILD_DIR" -maxdepth 3 -type f -perm -u+x -name "*.exe" -o -type f -perm -u+x -name "cmd" 2>/dev/null | head -1 || true)
    if [ -n "$EXE" ]; then
        ok "Build artifact found: $EXE"
    else
        warn "No executable found in $BUILD_DIR"
        echo "  The build succeeded but no executable was produced."
        echo "  Check that cmd/main.mbt contains a main() entry point."
    fi
else
    WASM_COUNT=$(find "$BUILD_DIR" -name "*.wasm" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    if [ "$WASM_COUNT" -gt 0 ]; then
        ok "Found $WASM_COUNT wasm artifact(s) in $BUILD_DIR"
    else
        ok "wasm-gc build artifacts are in $BUILD_DIR"
    fi
fi

# ── Step 6: Configuration guidance ──────────────────────────────────────────

CONFIG_DIR="$HOME/.mbopenclacky"
CONFIG_FILE="$CONFIG_DIR/config.toml"

echo ""
printf "\033[35m=============================================\033[0m\n"
printf "\033[35m  MBOpenClacky installation complete!\033[0m\n"
printf "\033[35m=============================================\033[0m\n"
echo ""
printf "\033[33mNext steps:\033[0m\n"
echo "  1. Configure an API key (choose one method):"
echo ""
echo "     # Shell environment variable (session-scoped)"
echo '     export CLACKY_API_KEY="your-api-key"'
echo '     export CLACKY_BASE_URL="https://api.anthropic.com"'
echo '     export CLACKY_MODEL="claude-sonnet-4-6"'
echo ""
echo "     # Or create a config file at:"
echo "     #   $CONFIG_FILE"
echo ""
echo "  2. Run the agent:"
echo ""
if [ "$BUILD_TARGET" = "native" ] && [ -n "${EXE:-}" ]; then
    echo "     $EXE --message \"Hello\" --mode auto_approve"
else
    echo "     moon run cmd -- --message \"Hello\" --mode auto_approve"
fi
echo ""
echo "  3. For full documentation, see:"
echo "     docs/getting-started.md"
echo ""
