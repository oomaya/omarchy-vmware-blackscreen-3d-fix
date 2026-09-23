#!/usr/bin/env bash
#
# install-automation.sh -- Install the pacman hook and automation handler
# to automatically rebuild vmwgfx whenever linux or linux-omarchy is upgraded.
#

set -euo pipefail

BUNDLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="/usr/local/lib/vmwgfx-patch"
HOOK_DIR="/etc/pacman.d/hooks"
HOOK_FILE="$HOOK_DIR/95-vmwgfx-patch.hook"

DRY_RUN=no
UNINSTALL=no

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)   DRY_RUN=yes ;;
        --uninstall) UNINSTALL=yes ;;
        -h|--help)
            cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --dry-run     Print commands without making changes
  --uninstall   Remove the pacman hook and installed files
  -h, --help    Show this help message
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
    shift
done

run() {
    printf '\033[2m   $ %s\033[0m\n' "$*"
    [[ $DRY_RUN == yes ]] && return 0
    "$@"
}

if [[ $UNINSTALL == yes ]]; then
    echo ":: Uninstalling vmwgfx automation hook..."
    run sudo rm -f "$HOOK_FILE"
    run sudo rm -rf "$TARGET_DIR"
    echo ":: vmwgfx automation uninstalled."
    exit 0
fi

echo ":: Installing vmwgfx pre-reboot rebuild hook..."

run sudo mkdir -p "$TARGET_DIR" "$HOOK_DIR"
run sudo cp -a "$BUNDLE/install-kernel-patch.sh" "$TARGET_DIR/"
run sudo cp -a "$BUNDLE/patches" "$TARGET_DIR/"
run sudo mkdir -p "$TARGET_DIR/tools"
run sudo cp -a "$BUNDLE/tools/vmwtest.c" "$TARGET_DIR/tools/" 2>/dev/null || true
run sudo cp -a "$BUNDLE/tools/pacman-hook-handler.sh" "$TARGET_DIR/"
run sudo chmod 755 "$TARGET_DIR/install-kernel-patch.sh" "$TARGET_DIR/pacman-hook-handler.sh"

run sudo cp "$BUNDLE/tools/95-vmwgfx-patch.hook" "$HOOK_FILE"
run sudo chmod 644 "$HOOK_FILE"

echo ":: Automation hook installed successfully at $HOOK_FILE"
echo ":: The vmwgfx patch will now rebuild automatically before reboot on every kernel update."
