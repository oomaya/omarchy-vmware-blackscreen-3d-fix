# Implementation Plan: Harden, Decouple & Automate vmwgfx Patch

## Goal
Harden and operationalize the community `vmwgfx` kernel patch from [ClaireDuSoleil/Omarchy-Black-Screen-VMware-Fix](https://github.com/ClaireDuSoleil/Omarchy-Black-Screen-VMware-Fix) for continuous, unattended reliability on VMware Omarchy guests under the new repository [oomaya/omarchy-vmware-blackscreen-3d-fix](https://github.com/oomaya/omarchy-vmware-blackscreen-3d-fix).

---

## Architectural Review & Root-Cause Resolution

### 1. Omarchy Kernel Source & PGP Verification (Verified)
- **Running Kernel:** `linux-omarchy 7.2.5-3` (from repository `[omarchy]`).
- **Authoritative Source:** `https://github.com/omacom/omarchy-pkgs.git` at `pkgbuilds/linux-omarchy/`.
- **GPG Key Discovery:** `omarchy-pkgs` already bundles the official signing keys in tree under `pkgbuilds/linux-omarchy/keys/pgp/`:
  - `ABAF11C65A2970B130ABE3C479BE3E4300411886.asc` (Linus Torvalds)
  - `647F28654894E3BD457199BE38DBBDC86092693E.asc` (Greg Kroah-Hartman)
  - `12D27D5D8C8E9BF1AABC7C7C7C64768D3DE334E7.asc` (Omarchy Release Key)
- **Hardening Action:** Automatically import these local keys into the user's `$HOME/.gnupg` keyring via `gpg --import "$PKGSUBDIR/keys/pgp/"*.asc`. This eliminates `--skippgpcheck` without relying on flaky remote keyservers.

### 2. Pre-Reboot Automation (Eliminating Black Screen & Forced Double Boots)
- **Flaw in Sonnet's Proposal:** Post-reboot rebuild causes Hyprland to launch into the unpatched stock driver, triggering a **black screen** and a forced secondary reboot while building in the background.
- **Architectural Fix:** Use an ALPM `PostTransaction` hook that triggers during `pacman -Syu` before the system ever reboots. The installer decouples from `uname -r` via `--target-kver <kver>` and compiles against `/usr/lib/modules/<target-kver>/build`, installs the module, and triggers `mkinitcpio`. The VM boots directly into the patched driver on first boot.

### 3. Fail-Safe Continuity & Living Handoff
- In accordance with the user's directive, cross-machine continuity is preserved in `~/Documents/artifacts/handoffs/LATEST.md` via `antigravity-handoff`. Even if the guest VM encounters boot issues during kernel experiments, all state, diffs, and recovery steps are federated in the cloud vault (`oomaya/vault`).

---

## User Review Required

> [!NOTE]
> All core architectural points have been aligned:
> 1. **Pre-Reboot Pacman Hook:** Approved.
> 2. **Kernel Source:** Verified to `omacom/omarchy-pkgs` with embedded `.asc` PGP keys.
> 3. **Kernel Patch Defensiveness:** Approved for 1st iteration (`NULL file_priv` check, `WARN_ON_ONCE`).
> 4. **WORK Path Validation:** 100% safety checks enforced.

---

## Quota & Token Budget Analysis (Go/No-Go Decision Gate)

| Metric | Current Value | Threshold | Rationale / Status |
|---|---|---|---|
| **Gemini Weekly Quota** | > 99.9% remaining (0.09% used) | > 15% | **GO:** Abundant quota for deep review and surgical scripting |
| **Gemini 5h Window** | > 99.4% remaining (0.52% used) | > 20% | **GO:** Negligible usage |
| **Claude Weekly Quota** | 100% utilized (resets 2026-09-26) | N/A | Claude exhausted; Gemini executing surgical shell & patch hardening |
| **Projected Task Cost** | ~12k–18k tokens | N/A | Highly token-efficient |

---

## Proposed Changes

### Track A — Installer Hardening & Decoupling (`install-kernel-patch.sh`)

#### [MODIFY] [install-kernel-patch.sh](file:///home/rand/Omarchy-Black-Screen-VMware-Fix/install-kernel-patch.sh)
1. **Target Kernel Decoupling (`--target-kver <kver>`):**
   - Accept `--target-kver` command-line argument.
   - If set, build against `/usr/lib/modules/<target-kver>/build` and install to `/usr/lib/modules/<target-kver>/kernel/drivers/gpu/drm/vmwgfx/`.
   - Default to `uname -r` if omitted.
2. **Safe `WORK` Validation:**
   - Enforce that `WORK` is strictly within non-root, non-home root paths:
     `[[ $WORK != "/" && $WORK != "$HOME" && $WORK != "$HOME/" && $WORK != "$BUNDLE" ]] || die "Unsafe WORK path: $WORK"`
3. **PGP Key Auto-Import:**
   - Detect `$PKGSUBDIR/keys/pgp/*.asc` and run `gpg --batch --import "$PKGSUBDIR/keys/pgp/"*.asc`.
   - Run `makepkg -o --nodeps` (without `--skippgpcheck`).
4. **Hardened Sudo Keepalive:**
   - Track `PPID` and terminate background keepalive safely.
5. **Secure Log & File Permissions:**
   - Create logfile with `install -m 600 /dev/null "$LOGFILE"`.

---

### Track B — Kernel Patch Defensiveness (`patches/vmwgfx-bridge-fix.patch`)

#### [MODIFY] [patches/vmwgfx-bridge-fix.patch](file:///home/rand/Omarchy-Black-Screen-VMware-Fix/patches/vmwgfx-bridge-fix.patch)
1. **Defensive Pointer Guards:**
   - In `vmw_prime_resolve_handle()`, add early null-pointer check:
     ```c
     if (!file_priv)
         return NULL;
     ```
2. **Double-Free & Orphan Assertion:**
   - In `vmw_prime_import_bridge_free()`, add:
     ```c
     WARN_ON_ONCE(!bridge->base_obj);
     ```
3. **Contract Header Annotation:**
   - Comment lifetime invariants on `struct vmw_prime_import_bridge`.
4. **Clean Application Check:**
   - Validate with `patch -p1 --dry-run` against kernel source.

---

### Track C — Pre-Reboot Pacman Automation (Zero Black Screen)

#### [NEW] `tools/95-vmwgfx-patch.hook`
ALPM hook in `/etc/pacman.d/hooks/95-vmwgfx-patch.hook`:
```ini
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux
Target = linux-omarchy

[Action]
Description = Pre-reboot rebuild of vmwgfx module for upgraded kernel...
When = PostTransaction
Depends = base-devel
Exec = /usr/local/lib/vmwgfx-patch/pacman-hook-handler.sh
```

#### [NEW] `tools/pacman-hook-handler.sh`
- Detects the upgraded kernel version from the transaction.
- Executes `install-kernel-patch.sh --target-kver "$TARGET_KVER" --yes --no-reboot`.
- Regenerates initramfs for `$TARGET_KVER`.

#### [NEW] `tools/install-automation.sh`
- Sets up `/usr/local/lib/vmwgfx-patch/` and installs the ALPM hook with correct permissions.

---

### Track D — Git Remote Federation & Vault Handoffs

1. **Git Remote Setup:**
   - `origin`: `git@github.com:oomaya/omarchy-vmware-blackscreen-3d-fix.git`
   - `upstream`: `git@github.com:ClaireDuSoleil/Omarchy-Black-Screen-VMware-Fix.git`
2. **Living Handoff Maintenance:**
   - Keep `~/Documents/artifacts/handoffs/LATEST.md` continuously updated at each implementation milestone.

---

## Verification Plan

### Automated Checks
- `bash -n install-kernel-patch.sh tools/*.sh`
- `shellcheck install-kernel-patch.sh tools/*.sh`
- `patch -p1 --dry-run` against kernel source tree
- `tools/vmwtest` reproducer run

### Manual Verification
- Execute `./install-kernel-patch.sh --dry-run` to test argument parsing and path validation.
- Test `./tools/install-automation.sh --dry-run`.
