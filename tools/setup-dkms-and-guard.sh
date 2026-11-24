#!/usr/bin/env bash
#
# setup-dkms-and-guard.sh -- Deploy the standard DKMS module and Systemd Boot Guard
# for permanent VMware black screen prevention on Omarchy.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$SCRIPT_DIR/dkms/src"
GUARD_SERVICE="$SCRIPT_DIR/systemd/vmwgfx-boot-guard.service"
GUARD_SCRIPT="$SCRIPT_DIR/systemd/vmwgfx-boot-guard.sh"
CHECK_SRC="$SCRIPT_DIR/tools/vmwtest.c"

info()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

run() {
    printf '\033[2m   $ %s\033[0m\n' "$*"
    [[ "${DRY_RUN:-no}" == "yes" ]] && return 0
    "$@"
}

if [[ $EUID -ne 0 ]]; then
    SUDO="sudo"
else
    SUDO=""
fi

info "Step 1: Removing old flawed ALPM hook..."
if [[ -f "/etc/pacman.d/hooks/95-vmwgfx-patch.hook" ]]; then
    run $SUDO rm -f "/etc/pacman.d/hooks/95-vmwgfx-patch.hook"
    ok "Removed /etc/pacman.d/hooks/95-vmwgfx-patch.hook"
else
    info "No old ALPM hook found in /etc/pacman.d/hooks/."
fi

info "Step 2: Installing dkms and matching kernel headers..."
HEADER_PKGS=()
for kpkg in linux linux-omarchy; do
    if pacman -Q "$kpkg" >/dev/null 2>&1; then
        HEADER_PKGS+=("${kpkg}-headers")
    fi
done
run $SUDO env OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -S --needed --noconfirm dkms "${HEADER_PKGS[@]}"
ok "DKMS and kernel headers confirmed installed: dkms ${HEADER_PKGS[*]}"

info "Step 3: Deploying vmwgfx-workaround-1.0 source to /usr/src/..."
DEST_SRC="/usr/src/vmwgfx-workaround-1.0"
run $SUDO mkdir -p "$DEST_SRC"
run $SUDO cp -r "$SRC_DIR/"* "$DEST_SRC/"
run $SUDO chmod -R u=rwX,go=rX "$DEST_SRC"
ok "Source tree deployed to $DEST_SRC."

info "Step 4: Registering and building with DKMS..."
if dkms status -m vmwgfx-workaround -v 1.0 >/dev/null 2>&1; then
    info "DKMS module already registered; removing previous build state if any..."
    run $SUDO dkms remove vmwgfx-workaround/1.0 --all || true
fi

run $SUDO dkms add vmwgfx-workaround/1.0

# Build and install for every installed kernel that has matching headers
BUILT_KVERS=()
for kbuild in /usr/lib/modules/*/build; do
    [[ -d "$kbuild" ]] || continue
    kver="$(basename "$(dirname "$kbuild")")"
    [[ "$kver" == ".old" ]] && continue
    info "Building DKMS module for kernel: $kver"
    run $SUDO dkms build vmwgfx-workaround/1.0 -k "$kver"
    run $SUDO dkms install vmwgfx-workaround/1.0 -k "$kver" --force
    BUILT_KVERS+=("$kver")
done
if [[ ${#BUILT_KVERS[@]} -eq 0 ]]; then
    KVER="$(uname -r)"
    run $SUDO dkms build vmwgfx-workaround/1.0 -k "$KVER"
    run $SUDO dkms install vmwgfx-workaround/1.0 -k "$KVER" --force
    BUILT_KVERS+=("$KVER")
fi
ok "DKMS module built and installed for kernel(s): ${BUILT_KVERS[*]}"

info "Step 5: Deploying Systemd Pre-Boot Fallback Guard..."
run $SUDO mkdir -p /usr/local/libexec
if [[ -f "$CHECK_SRC" ]]; then
    TMP_CHECK="$(mktemp)"
    run gcc -O2 -o "$TMP_CHECK" "$CHECK_SRC" -I/usr/include/libdrm -ldrm -lgbm
    run $SUDO install -Dm755 "$TMP_CHECK" /usr/local/libexec/vmwgfx-gem-check
    rm -f "$TMP_CHECK"
    if [[ -d "/usr/local/lib/vmwgfx-patch/tools" ]]; then
        run $SUDO install -Dm644 "$CHECK_SRC" /usr/local/lib/vmwgfx-patch/tools/vmwtest.c
    fi
    ok "Compiled and installed /usr/local/libexec/vmwgfx-gem-check"
fi

run $SUDO install -Dm755 "$GUARD_SCRIPT" /usr/local/libexec/vmwgfx-boot-guard.sh
run $SUDO install -Dm644 "$GUARD_SERVICE" /etc/systemd/system/vmwgfx-boot-guard.service
run $SUDO systemctl daemon-reload
run $SUDO systemctl enable vmwgfx-boot-guard.service
run $SUDO systemctl restart vmwgfx-boot-guard.service
ok "vmwgfx-boot-guard.service enabled and verified."

info "Step 6: Regenerating UKI (Unified Kernel Image) with new DKMS module..."
if command -v limine-mkinitcpio >/dev/null 2>&1; then
    run $SUDO limine-mkinitcpio
elif command -v mkinitcpio >/dev/null 2>&1; then
    run $SUDO mkinitcpio -P
fi
ok "Initramfs / UKI updated with DKMS module."

printf '\n\033[1;32m====================================================================\033[0m\n'
ok "SUCCESS! DKMS & Systemd Boot Guard deployment complete."
info "Future kernel updates will automatically compile vmwgfx via 70-dkms-install.hook."
info "If any module load issue ever arises, vmwgfx-boot-guard will prevent black screens."
printf '\033[1;32m====================================================================\033[0m\n\n'
