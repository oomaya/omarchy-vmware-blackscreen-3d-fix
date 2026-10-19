# Gap Analysis & Future Prevention Plan: Kernel Update VMware Black Screen Automation

## Executive Summary

On 2026-10-18 at 23:49 KST, a full system upgrade (`omarchy upgrade`) updated both `linux` (7.2.3 -> 7.2.11) and `linux-omarchy` (7.2.5 -> 7.2.8-9). Upon reboot, the VM booted into a black screen because the patched `vmwgfx` module had **not** been built for `linux-omarchy 7.2.8-9`. The user had to enter TTY from another VM with Tech Lead assistance to apply the patch manually.

Our empirical investigation of `/var/log/pacman.log`, ALPM hook configurations, and `/usr/local/lib/vmwgfx-patch/` reveals that **the automated hook (`95-vmwgfx-patch.hook`) DID trigger, but immediately crashed due to a fatal architectural anti-pattern:**
`install-kernel-patch.sh` attempted to run `pacman -S ...` while ALPM was actively holding `/var/lib/pacman/db.lck`. This aborted the entire hook script before it could build the module for the booted kernel.

---

## 1. Timeline & Empirical Evidence from System Logs

### Pacman Log Trajectory (`/var/log/pacman.log`)

```text
[2026-10-18T23:46:22+0900] [ALPM] upgraded linux (7.2.3.arch1-3 -> 7.2.11.arch1-1)
[2026-10-18T23:46:37+0900] [ALPM] upgraded linux-omarchy (7.2.5-3 -> 7.2.8-9)
[2026-10-18T23:46:40+0900] [ALPM] upgraded linux-omarchy-headers (7.2.5-3 -> 7.2.8-9)
...
[2026-10-18T23:49:03+0900] [ALPM-SCRIPTLET] Building UKI for linux-omarchy (7.2.8-9-omarchy)
[2026-10-18T23:49:09+0900] [ALPM-SCRIPTLET] Copied: /tmp/.../linux-omarchy.efi -> /boot/EFI/Linux/omarchy_linux-omarchy.efi
[2026-10-18T23:49:14+0900] [ALPM] running '95-vmwgfx-patch.hook'...
[2026-10-18T23:49:14+0900] [ALPM-SCRIPTLET] :: [vmwgfx-patch] Pre-reboot rebuild of vmwgfx for kernel: 7.2.11-arch1-1...
[2026-10-18T23:49:14+0900] [ALPM-SCRIPTLET] == 4. Build dependencies
[2026-10-18T23:49:14+0900] [ALPM-SCRIPTLET]    $ sudo env OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -S --needed --noconfirm base-devel linux-headers git patch
[2026-10-18T23:49:14+0900] [PACMAN] Running 'pacman -S --needed --noconfirm base-devel linux-headers git patch'
[2026-10-18T23:49:14+0900] [ALPM-SCRIPTLET] error: failed to init transaction (unable to lock database)
[2026-10-18T23:49:14+0900] [ALPM-SCRIPTLET] error: could not lock database: File exists
[2026-10-18T23:49:14+0900] [ALPM-SCRIPTLET]   if you're sure a package manager is not already
[2026-10-18T23:49:14+0900] [ALPM-SCRIPTLET]   running, you can remove /var/lib/pacman/db.lck
[2026-10-18T23:49:14+0900] [ALPM] running '99-omarchy-limine.hook'...
```

### What Happened During the Upgrade: Step-by-Step
1. **Pacman began transaction**: Acquired write lock `/var/lib/pacman/db.lck`.
2. **Package unpack & install**: Unpacked `linux 7.2.11.arch1-1`, `linux-omarchy 7.2.8-9`, and `linux-omarchy-headers 7.2.8-9`.
3. **Initramfs hook executed (`90-mkinitcpio-install.hook`)**: Generated UKI `omarchy_linux-omarchy.efi` using the **unpatched stock vmwgfx module** extracted from the new `linux-omarchy` package.
4. **Automation hook executed (`95-vmwgfx-patch.hook`)**:
   - `pacman-hook-handler.sh` collected targets: `linux` and `linux-omarchy`.
   - Identified kernel versions: `7.2.11-arch1-1` and `7.2.8-9-omarchy`.
   - In alphabetical order, it started with `7.2.11-arch1-1`.
   - It executed `install-kernel-patch.sh --target-kver 7.2.11-arch1-1 --allow-root --yes --no-reboot`.
5. **The Fatal Crash at Step 4**:
   - In `install-kernel-patch.sh`:
     ```bash
     BUILD_DEPS=(base-devel "${KPKG}-headers" git patch)
     run "${PACMAN[@]}" -S --needed --noconfirm "${BUILD_DEPS[@]}"
     ```
   - For `7.2.11-arch1-1`, `$KPKG` is `linux`, so it invoked `pacman -S --needed base-devel linux-headers git patch`.
   - Because pacman was actively running the transaction, `/var/lib/pacman/db.lck` was locked.
   - Child `pacman` failed immediately with exit code 1 (`error: could not lock database: File exists`).
   - Because `install-kernel-patch.sh` runs with `set -euo pipefail`, the script exited instantly.
6. **Failure Cascade**:
   - `pacman-hook-handler.sh` also ran with `set -euo pipefail`.
   - The crash on `7.2.11-arch1-1` killed `pacman-hook-handler.sh` before it ever reached `7.2.8-9-omarchy`.
   - Pacman logged the error and moved to `99-omarchy-limine.hook`.
7. **Reboot into Black Screen**:
   - The VM booted `7.2.8-9-omarchy` using the UKI built at step 3.
   - The loaded module was unpatched stock `vmwgfx`.
   - Hyprland launched, issued `DRM_IOCTL_GEM_CLOSE` on imported dmabufs, failed with `-EINVAL`, and killed Wayland clients -> **Black screen**.
8. **Manual TTY Intervention**:
   - In TTY, running `install-kernel-patch.sh` manually succeeded because pacman was no longer running, so `pacman -S --needed` could acquire the lock without conflict.

---

## 2. Root Cause & Gap Analysis (4 Structural Flaws)

| Flaw | Location | Impact | Why It Escaped Previous Testing |
|---|---|---|---|
| **Flaw 1: Invoking `pacman -S` inside an ALPM hook** | `install-kernel-patch.sh:373` | Fatal database lock contention (`db.lck`). ALPM hooks can NEVER invoke `pacman -S`. | In the initial September test, the author tested only with `--dry-run`. In `--dry-run`, `run()` skips command execution, so the locking failure was masked. |
| **Flaw 2: Loop Abort in Multi-Kernel Upgrades** | `pacman-hook-handler.sh:61-65` | `set -e` in handler caused first kernel failure to kill processing of the booted kernel. | Tested only in isolation with a single kernel target (`echo linux-omarchy \| ...`). |
| **Flaw 3: Inverted Hook Execution Order (`90` vs `95`)** | `/etc/pacman.d/hooks/` | `90-mkinitcpio-install.hook` bundles stock module into UKI *before* `95-vmwgfx-patch.hook` runs. | Even if 95 succeeded, it had to run `limine-mkinitcpio` a second time; if 95 failed, the stale UKI was left on disk. |
| **Flaw 4: Network & Build Bloat inside ALPM Hook** | `install-kernel-patch.sh:430-524` | Git clone and 150MB kernel tarball download during `pacman -Syu` blocks transaction and fails if offline. | In initial setup, source was already cloned in `$WORK`. On a fresh kernel version, it must fetch from network. |

---

## 3. Prevention Strategies & Architectural Options

### Evaluation Matrix

| Criterion | Option A: Hardened Pre-Reboot Hook (Order 85 + No Pacman) | Option B: DKMS Module (`vmwgfx-workaround-dkms`) | Option C: Systemd Pre-Boot Fallback Guard |
|---|---|---|---|
| **Zero Black Screen Guarantee** | High (builds before UKI is sealed) | Highest (standard Arch kernel module lifecycle) | High (fallback to software rendering / safe mode) |
| **ALPM Lock Free** | Yes (eliminates `pacman -S`) | Yes (handled by `dkms-install.hook`) | Yes (runs at boot time) |
| **Network Independence** | Requires local source bundle | 100% offline (source shipped in package) | Offline |
| **Implementation Effort** | Low (~1 day, surgical shell fixes) | Medium (packaging `PKGBUILD` + `dkms.conf`) | Low (one systemd unit + wrapper) |
| **Recommendation** | **Phase 1: Immediate Fix** | **Phase 2: Canonical Standard** | **Safety Net (Defense-in-depth)** |

---

### Detailed Architecture of the Recommended Solutions

#### Track 1 (Immediate Fix): Hardened Pre-Reboot Hook (`85-vmwgfx-patch.hook`)
1. **Hook Renumbering**: Rename `95-vmwgfx-patch.hook` -> `85-vmwgfx-patch.hook`.
   - Runs *before* `90-mkinitcpio-install.hook`.
   - When pacman finishes unpacking the kernel, the hook replaces `vmwgfx.ko` *before* `mkinitcpio` or `limine-mkinitcpio` packages it into the UKI.
   - Eliminates the redundant secondary UKI rebuild.
2. **Zero `pacman -S` inside Hook Mode**:
   - If invoked with `--allow-root` (hook mode), **never invoke `pacman -S`**.
   - Instead, perform a read-only check: verify that `/usr/lib/modules/<target-kver>/build` exists.
   - If missing, log an explicit warning to `/var/log/vmwgfx-hook.log` and skip that specific kernel without crashing.
3. **Target Kernel Filtering**:
   - Inspect `/etc/default/limine` or `/boot/limine.conf`.
   - Prioritize or strictly target the default boot kernel (`linux-omarchy`).
   - If `linux` (Arch default) lacks headers, silently skip it rather than crashing.
4. **Fault-Tolerant Loop (`set +e` boundary)**:
   - In `pacman-hook-handler.sh`, isolate each kernel rebuild in a subshell or `if ... then` block so failure on an auxiliary kernel never stops the primary kernel.

#### Track 2 (Definitive Arch Standard): DKMS Module (`vmwgfx-workaround-dkms`)
- Package the patched `vmwgfx` driver (~500 KB C source) as a DKMS package.
- File tree:
  ```text
  /usr/src/vmwgfx-workaround-1.0/
  ├── dkms.conf
  ├── Makefile
  ├── Kconfig
  ├── *.c, *.h (patched source)
  ```
- `dkms.conf`:
  ```ini
  PACKAGE_NAME="vmwgfx-workaround"
  PACKAGE_VERSION="1.0"
  BUILT_MODULE_NAME[0]="vmwgfx"
  DEST_MODULE_LOCATION[0]="/kernel/drivers/gpu/drm/vmwgfx"
  AUTOINSTALL="yes"
  ```
- **How it works with Pacman:**
  - Arch's official `70-dkms-install.hook` runs at order 70.
  - Automatically compiles and installs `vmwgfx.ko` for every upgraded kernel.
  - Then `90-mkinitcpio-install.hook` runs at order 90 and automatically bundles the DKMS module into the UKI.
  - Zero custom ALPM hooks, zero network traffic during upgrade, zero `db.lck` conflicts.

#### Track 3 (Defense-in-Depth): Early Boot Black Screen Fallback Guard
- A systemd one-shot service: `vmwgfx-boot-guard.service` (`Before=display-manager.service`).
- Inspects `/sys/module/vmwgfx/srcversion`.
- If `vmwtest` reproduces the GEM_CLOSE bug (unpatched module loaded):
  - Automatically sets `WLR_RENDERER=pixman` or switches to a lightweight rescue desktop/TTY notification.
  - Rebuilds and replaces the module in background, then alerts the user instead of hanging on a frozen black screen.

---

## 4. Quota & Token Budget Analysis (Go/No-Go Decision Gate)

| Metric | Current Value | Threshold | Rationale / Status |
|---|---|---|---|
| **Gemini Weekly Quota** | 99.49% remaining (0.51% used) | > 15% | **GO:** Extreme budget surplus; perfect for architectural planning and audit |
| **Gemini 5h Window** | 99.69% remaining (0.31% used) | > 20% | **GO:** Negligible consumption |
| **Claude Weekly Quota** | 100% available (0% used) | > 10% | **GO:** Claude Sonnet available if deep C driver refactoring is requested |
| **Projected Task Cost** | ~15k–22k tokens | N/A | High efficiency |

---

## 5. Implementation Roadmap & Tollgates

### Phase 1: Surgical Fix for Current Hook (Immediate)
1. Edit `install-kernel-patch.sh`:
   - Guard Step 4: When `EUID == 0` (or `--allow-root` is set), bypass `pacman -S`.
   - Verify `/usr/lib/modules/$KVER/build` directly; if missing, fail gracefully.
2. Edit `tools/pacman-hook-handler.sh`:
   - Check if `/usr/lib/modules/$kver/build` exists before invoking installer.
   - Isolate loop execution with `try_patch_kernel()`.
   - Renumber hook to `85-vmwgfx-patch.hook` in `tools/install-automation.sh`.
3. Re-run `sudo ./tools/install-automation.sh` to update `/etc/pacman.d/hooks/`.

### Phase 2: Live Upgrade Simulation & Verification
- Create mock kernel module directory or run non-dry-run test with `pacman -S --reinstall linux-omarchy`.
- Verify `/var/log/pacman.log` confirms clean build and packaging without database lock collision.

---

## Tollgate Questions for User Alignment

1. **Adoption Strategy**: Would you like to proceed with **Phase 1 (Surgical Hook Hardening to Order 85 + Zero Pacman Lock)** immediately, or do you prefer migrating straight to the **DKMS Package (Track 2)**?
2. **Generic `linux` Kernel**: Since Limine boots `linux-omarchy`, should we remove the unused generic `linux` package (`sudo pacman -R linux`) to avoid duplicate kernel upgrades and confusion?
