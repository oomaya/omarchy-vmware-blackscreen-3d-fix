# Walkthrough: Hardened & Automated vmwgfx 3D Fix for Omarchy on VMware

## Summary of Accomplishments

We reviewed Sonnet's implementation plan, addressed three critical operational traps, and fully implemented the hardening, defensiveness, and unattended pre-reboot automation in [oomaya/omarchy-vmware-blackscreen-3d-fix](https://github.com/oomaya/omarchy-vmware-blackscreen-3d-fix).

---

## Key Changes by Track

### Track A — Installer Hardening & Target Kernel Decoupling
- **Target Kernel Decoupling:** Added `--target-kver <kver>` and `--no-update` to [install-kernel-patch.sh](file:///home/rand/Omarchy-Black-Screen-VMware-Fix/install-kernel-patch.sh), allowing pre-reboot builds for newly installed kernels without dependency on `uname -r`.
- **Root Mode for Hooks:** Added `--allow-root` so ALPM hooks can trigger unattended builds without sudo password roadblocks; non-root user is automatically resolved for `makepkg`.
- **Embedded PGP Key Auto-Import:** Directly imports embedded signing keys from `$PKGSUBDIR/keys/pgp/*.asc` (Linus Torvalds, Greg Kroah-Hartman, and Omarchy packager) into the build user's keyring, eliminating reliance on flaky remote keyservers.
- **Safe WORK Validation:** Enforces strict boundary checks to prevent accidental operations on `/`, `$HOME`, or the bundle root.
- **Process-Aware File Replacement:** Installed kernel module using `install -Dm644` and compressed with `zstd` if original module was `.zst`.

### Track B — Kernel Patch Defensiveness
- In [patches/vmwgfx-bridge-fix.patch](file:///home/rand/Omarchy-Black-Screen-VMware-Fix/patches/vmwgfx-bridge-fix.patch):
  - Added `if (!file_priv) return NULL;` null pointer guard in `vmw_prime_resolve_handle()`.
  - Added `WARN_ON_ONCE(!bridge->base_obj);` assertion in `vmw_prime_import_bridge_free()`.
  - Annotated `struct vmw_prime_import_bridge` with lifetime comments.
  - Adjusted patch hunk line counts and offsets; validated clean patch syntax.

### Track C — Pre-Reboot Pacman Automation (Zero Black Screen)
- **ALPM Trigger Hook:** Created [tools/95-vmwgfx-patch.hook](file:///home/rand/Omarchy-Black-Screen-VMware-Fix/tools/95-vmwgfx-patch.hook) targeting `linux` and `linux-omarchy` on `PostTransaction`.
- **Hook Handler:** Created [tools/pacman-hook-handler.sh](file:///home/rand/Omarchy-Black-Screen-VMware-Fix/tools/pacman-hook-handler.sh) that maps target packages to `/usr/lib/modules/*/pkgbase`, invokes `install-kernel-patch.sh --target-kver "$kver" --allow-root --yes --no-reboot`, and regenerates initramfs/UKI before the user reboots.
- **Automation Installer:** Created [tools/install-automation.sh](file:///home/rand/Omarchy-Black-Screen-VMware-Fix/tools/install-automation.sh) with `--dry-run` and `--uninstall` support.

### Track D — Git Remote Federation & Documentation
- Configured git remotes: `origin` pointing to `git@github.com:oomaya/omarchy-vmware-blackscreen-3d-fix.git` and `upstream` pointing to `ClaireDuSoleil/Omarchy-Black-Screen-VMware-Fix`.
- Added clean [.gitignore](file:///home/rand/Omarchy-Black-Screen-VMware-Fix/.gitignore).
- Committed 4 logical commits and pushed `main` to `origin`.

---

## Verification & Test Results

### 1. Shell Syntax & Static Linting
```bash
bash -n install-kernel-patch.sh tools/*.sh
shellcheck tools/pacman-hook-handler.sh tools/install-automation.sh
```
- **Result:** Exited 0 with zero errors or warnings.

### 2. Standalone Installer Dry-Run
```bash
./install-kernel-patch.sh --dry-run --yes --no-reboot
```
- **Result:** Successfully detected `7.2.5-3-omarchy`, DRM driver `vmwgfx`, ran `vmwtest` reproducer, detected `linux-omarchy` package, and mapped `/usr/lib/modules/7.2.5-3-omarchy/build`.

### 3. Decoupled `--target-kver` Dry-Run
```bash
./install-kernel-patch.sh --target-kver 7.2.5-3-omarchy --dry-run --yes --no-reboot
```
- **Result:** Target kernel decoupled from running kernel; skipped system update prompt cleanly.

### 4. Pacman Hook Handler Simulation
```bash
echo "linux-omarchy" | bash tools/pacman-hook-handler.sh --dry-run
```
- **Result:** Hook handler correctly read `linux-omarchy` from stdin, resolved kernel version `7.2.5-3-omarchy` from `/usr/lib/modules/7.2.5-3-omarchy/pkgbase`, and completed dry-run rebuild successfully.

### 5. Automation Installer Dry-Run
```bash
bash tools/install-automation.sh --dry-run
```
- **Result:** Clean dry-run verifying directory layout in `/usr/local/lib/vmwgfx-patch/` and hook placement in `/etc/pacman.d/hooks/95-vmwgfx-patch.hook`.

---

## How to Deploy Automation

When you are ready to activate automatic rebuilds across future kernel updates:
```bash
~/Omarchy-Black-Screen-VMware-Fix/tools/install-automation.sh
```
