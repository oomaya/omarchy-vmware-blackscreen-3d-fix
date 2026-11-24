# `vmwgfx` Post-Update Audit, Auto-Update Remediation & Dual-Kernel DKMS Walkthrough

- **Date**: 2026-11-24
- **Kernels Covered**: `7.2.15-4-omarchy` (`linux-omarchy`) + `7.2.11-arch1-1` (`linux`)
- **Commit**: `b9171e9` (`fix(boot-guard,dkms): scan all DRM cards, cover all installed kernels, add CI`)
- **CI Run**: https://github.com/oomaya/omarchy-vmware-blackscreen-3d-fix/actions/runs/45362612754 (`success`)

## 1. Post-Update Audit Findings (`7.2.15-1` → `7.2.15-4`)

- **Patched `vmwgfx` Active**: DKMS rebuilt `/lib/modules/7.2.15-4-omarchy/updates/dkms/vmwgfx.ko.zst` (`srcversion: DF747BDBD110AA5B4CBBA35`), matching `/sys/module/vmwgfx/srcversion`. `vmwtest` returned exit `0` (`PATCH IS NOT REQUIRED`) and `eglinfo -B` confirmed `SVGA3D`.
- **5 Auto-Update / Safety Defects Found**:
  1. Legacy `/etc/pacman.d/hooks/95-vmwgfx-patch.hook` remained installed and fired post-UKI against stale `7.2.15-1-omarchy` before failing.
  2. `vmwgfx-boot-guard.sh` (both installed and in-repo) hardcoded `/sys/class/drm/card0/device/driver`; because `simpledrm` claims `card0` and unbinds leaving `vmwgfx` on `card1`, the boot guard silently exited `0` every boot without running `vmwgfx-gem-check`. Additionally, the installed script and binary had drifted from the Nov 12 exit-code contract commits (`cda5373`, `4c3a7ac`).
  3. `/usr/src/vmwgfx-workaround-1.0/dkms.conf` still contained deprecated `CLEAN=`.
  4. Secondary kernel `linux` (`7.2.11-arch1-1`) lacked `linux-headers`, leaving its `vmwgfx.ko.zst` unpatched.
  5. Unsigned module warning during DKMS build (benign while Secure Boot enforcement is off) and future kernel 7.3+ ABI drift watchlist.

## 2. Remediations Applied

- Updated [systemd/vmwgfx-boot-guard.sh](../../systemd/vmwgfx-boot-guard.sh) and [install-kernel-patch.sh](../../install-kernel-patch.sh) to dynamically scan `/sys/class/drm/card[0-9]*` for `vmwgfx`.
- Enhanced [tools/setup-dkms-and-guard.sh](../../tools/setup-dkms-and-guard.sh) to:
  - Install `*-headers` for every installed kernel (`linux`, `linux-omarchy`).
  - Build and install `vmwgfx-workaround/1.0` for every `/usr/lib/modules/*/build`.
  - Atomically deploy `vmwgfx-gem-check` (`install -Dm755`), sync `vmwtest.c`, and run `systemctl restart vmwgfx-boot-guard.service` (since `enable --now` is a no-op on active `RemainAfterExit=yes` units).
- Added [.github/workflows/ci.yml](../../.github/workflows/ci.yml) (`bash -n`, no `card0` regression check, no `CLEAN=` in `dkms.conf`, `gcc -Wall -Wextra -Werror` build of `tools/vmwtest.c`).
- Ran `~/Omarchy-Black-Screen-VMware-Fix/tools/setup-dkms-and-guard.sh` on the live VM.

## 3. Verification Evidence

- **Legacy Hook Removed**: `/etc/pacman.d/hooks/` contains only `90-mkinitcpio-install.hook` and `99-omarchy-limine.hook`.
- **Zero-Diff Sync**: `/usr/src/vmwgfx-workaround-1.0/dkms.conf`, `/usr/local/libexec/vmwgfx-boot-guard.sh`, and `/usr/local/lib/vmwgfx-patch/tools/vmwtest.c` match the repo with zero diff.
- **Boot Guard Live Proof**:
  ```text
  vmwgfx-boot-guard.sh[71311]: :: [vmwgfx-boot-guard] vmwgfx dmabuf bridge is ACTIVE (hardware 3D acceleration safe).
  ```
- **Dual-Kernel DKMS Proof**:
  ```text
  vmwgfx-workaround/1.0, 7.2.11-arch1-1, x86_64: installed (Original modules exist)
  vmwgfx-workaround/1.0, 7.2.15-4-omarchy, x86_64: installed (Original modules exist)
  ```
  Both modules verified for matching `vermagic`, bridge symbols (`vmw_prime_import_bridge`, `vmw_prime_import_bridge_free`, `vmw_prime_import_bridge_funcs`, `vmw_prime_resolve_handle`), `modules.dep` resolution to `updates/dkms/vmwgfx.ko.zst`, and UKI regeneration via `limine-mkinitcpio`.
