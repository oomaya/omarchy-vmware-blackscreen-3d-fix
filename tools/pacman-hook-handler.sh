#!/usr/bin/env bash
#
# pacman-hook-handler.sh -- Invoked by /etc/pacman.d/hooks/95-vmwgfx-patch.hook
# Rebuilds the patched vmwgfx module for newly installed/upgraded kernels
# during pacman PostTransaction, preventing black screen on next boot.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
if [[ ! -x "$SCRIPT_DIR/install-kernel-patch.sh" ]]; then
    SCRIPT_DIR="/usr/local/lib/vmwgfx-patch"
fi
INSTALL_SCRIPT="$SCRIPT_DIR/install-kernel-patch.sh"

[[ -x "$INSTALL_SCRIPT" ]] || {
    echo ":: [vmwgfx-patch] ERROR: $INSTALL_SCRIPT not found or not executable" >&2
    exit 1
}

# Collect target packages from stdin (passed by ALPM NeedsTargets)
TARGET_PACKAGES=()
while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && TARGET_PACKAGES+=("$pkg")
done

if [[ ${#TARGET_PACKAGES[@]} -eq 0 ]]; then
    # Fallback if invoked manually without stdin: detect from installed kernels
    echo ":: [vmwgfx-patch] No targets on stdin, inspecting /usr/lib/modules..."
    for pkg in linux linux-omarchy; do
        if pacman -Q "$pkg" >/dev/null 2>&1; then
            TARGET_PACKAGES+=("$pkg")
        fi
    done
fi

TARGET_KVERS=()
for pkg in "${TARGET_PACKAGES[@]}"; do
    for pkgbase in /usr/lib/modules/*/pkgbase; do
        [[ -f "$pkgbase" ]] || continue
        if [[ "$(< "$pkgbase")" == "$pkg" ]]; then
            kver="$(basename "$(dirname "$pkgbase")")"
            TARGET_KVERS+=("$kver")
        fi
    done
done

# Deduplicate versions
mapfile -t UNIQUE_KVERS < <(printf '%s\n' "${TARGET_KVERS[@]}" | sort -u)

if [[ ${#UNIQUE_KVERS[@]} -eq 0 ]]; then
    echo ":: [vmwgfx-patch] No matching kernel modules found under /usr/lib/modules/ for targets: ${TARGET_PACKAGES[*]}"
    exit 0
fi

DRY_RUN_ARG=()
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN_ARG=("--dry-run")
fi

for kver in "${UNIQUE_KVERS[@]}"; do
    echo ":: [vmwgfx-patch] Pre-reboot rebuild of vmwgfx for kernel: $kver..."
    "$INSTALL_SCRIPT" --target-kver "$kver" --allow-root --yes --no-reboot "${DRY_RUN_ARG[@]}"
    echo ":: [vmwgfx-patch] Kernel $kver successfully patched with vmwgfx bridge fix."
done
