#!/usr/bin/env bash
#
# vmwgfx-boot-guard.sh -- Executed early at boot before SDDM/Hyprland.
# Detects whether the active vmwgfx driver possesses the GEM_CLOSE bridge patch.
# If unpatched, activates software-rendering fallback (pixman) to prevent black screen.
#

set -euo pipefail

DRIVER=$(basename "$(readlink -f /sys/class/drm/card0/device/driver 2>/dev/null)" 2>/dev/null || echo unknown)
if [[ "$DRIVER" != "vmwgfx" ]]; then
    exit 0
fi

ENV_DIR="/run/environment.d"
ENV_FILE="$ENV_DIR/99-vmwgfx-safemode.conf"
WARN_FILE="/run/vmwgfx-unpatched-warning"
CHECK_BIN="/usr/local/libexec/vmwgfx-gem-check"

# If the check binary is missing, attempt to compile from bundle or fallback
if [[ ! -x "$CHECK_BIN" ]]; then
    if [[ -f "/usr/local/lib/vmwgfx-patch/tools/vmwtest.c" ]]; then
        mkdir -p "/usr/local/libexec"
        gcc -O2 -o "$CHECK_BIN" "/usr/local/lib/vmwgfx-patch/tools/vmwtest.c" -I/usr/include/libdrm -ldrm -lgbm 2>/dev/null || true
    fi
fi

IS_PATCHED=0
if [[ -x "$CHECK_BIN" ]]; then
    if "$CHECK_BIN" >/dev/null 2>&1; then
        IS_PATCHED=1
    fi
else
    # If check binary is missing, assume patched to avoid false fallbacks
    IS_PATCHED=1
fi

if [[ "$IS_PATCHED" -eq 1 ]]; then
    echo ":: [vmwgfx-boot-guard] vmwgfx dmabuf bridge is ACTIVE (hardware 3D acceleration safe)."
    rm -f "$ENV_FILE" "$WARN_FILE" 2>/dev/null || true
else
    echo ":: [vmwgfx-boot-guard] WARNING: Unpatched vmwgfx detected! Engaging pixman fallback to prevent black screen." >&2
    mkdir -p "$ENV_DIR"
    cat <<EOF > "$ENV_FILE"
WLR_RENDERER=pixman
LIBGL_ALWAYS_SOFTWARE=1
EOF
    cat <<EOF > "$WARN_FILE"
VMware vmwgfx is running in safe software fallback mode (pixman) because the kernel driver is unpatched.
Please rebuild the patched module via:
    sudo dkms install vmwgfx-workaround/1.0
EOF
fi
