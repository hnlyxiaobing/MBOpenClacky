#!/usr/bin/env bash
# ============================================================
# MBOpenClacky uninstaller (macOS / Linux).
#
# Usage:
#   ./scripts/uninstall.sh            # interactive, keeps user data
#   ./scripts/uninstall.sh --yes      # non-interactive, keeps user data
#   ./scripts/uninstall.sh --purge    # also remove config & data
#   ./scripts/uninstall.sh --yes --purge
#
# By default we ONLY remove the installed binary. User data under
# ~/.mbopenclacky (config, sessions, skills, logs, memory) is preserved
# unless --purge is given.
# ============================================================
set -euo pipefail

BIN_NAME="mbopenclacky"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"

purge=false
auto_yes=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --purge) purge=true; shift;;
        --yes|-y) auto_yes=true; shift;;
        *) echo "Unknown option: $1"; echo "Usage: $0 [--purge] [--yes]"; exit 1;;
    esac
done

confirm() {
    if [ "$auto_yes" = true ]; then
        return 0
    fi
    local prompt="$1 [y/N] "
    read -r -p "$prompt" answer
    case "$answer" in
        [yY][eE][sS]|[yY]) return 0;;
        *) return 1;;
    esac
}

step()  { printf "\033[36m>> %s\033[0m\n" "$1"; }
ok()    { printf "  \033[32m[OK]\033[0m %s\n" "$1"; }
warn()  { printf "  \033[33m[!]\033[0m %s\n" "$1"; }

step "Removing MBOpenClacky binary..."

BIN_PATH="$INSTALL_PREFIX/bin/$BIN_NAME"
if [ -f "$BIN_PATH" ]; then
    if confirm "Remove $BIN_PATH?"; then
        rm -f "$BIN_PATH"
        ok "Removed $BIN_PATH"
    else
        warn "Skipped binary removal."
    fi
else
    ok "No binary at $BIN_PATH (already removed)."
fi

if [ "$purge" = true ]; then
    step "Purging user data (--purge requested)..."
    CONFIG_DIR="$HOME/.mbopenclacky"
    if [ -d "$CONFIG_DIR" ]; then
        if confirm "PERMANENTLY remove $CONFIG_DIR (config, sessions, skills, logs, memory)?"; then
            rm -rf "$CONFIG_DIR"
            ok "Removed $CONFIG_DIR"
        else
            warn "Skipped data purge; $CONFIG_DIR kept."
        fi
    else
        ok "No data directory at $CONFIG_DIR."
    fi
else
    step "Keeping user data at ~/.mbopenclacky (use --purge to remove)."
fi

printf "\033[35m=============================================\033[0m\n"
printf "\033[35m  MBOpenClacky uninstalled.\033[0m\n"
printf "\033[35m=============================================\033[0m\n"
if [ "$purge" = false ]; then
    echo "  User data was preserved under ~/.mbopenclacky."
fi
