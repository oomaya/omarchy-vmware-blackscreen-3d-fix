# Security & Safety Review
## Omarchy-Black-Screen-VMware-Fix
**Review Date:** 2026-09-23  
**Scope:** All files in `~/Omarchy-Black-Screen-VMware-Fix` as applied to a VMware Omarchy Quattro guest  
**Reviewer:** Antigravity (Claude Sonnet 4.6 Thinking)

---

## Executive Summary

This repository provides a **community-maintained kernel module patch** for the `vmwgfx` DRM driver, targeting a real and well-documented kernel bug. The code quality is high for a community workaround. There are **no backdoors, credential harvesters, or obviously malicious constructs**. However, several meaningful security and operational risk factors apply before running this on any VM you care about.

**Threat level: LOW-to-MODERATE** for a disposable VMware guest; the code is straightforward and the risks are intrinsic to the task (kernel patching) rather than to bad intent.

---

## File-by-File Findings

### 1. `install-kernel-patch.sh` (613 lines)

#### ✅ What it does right

| Practice | Evidence |
|---|---|
| `set -euo pipefail` | Line 55 — exits on any error, unset variable, or pipeline failure |
| No root required by design | Line 174 — actively refuses EUID=0; `sudo` called surgically only when needed |
| All `sudo`-escalated calls are explicit and narrow | Lines 335, 539–546, 568–570, 594–596 — only: package install, module copy, depmod, mkinitcpio/limine-mkinitcpio, reboot |
| Sudo keepalive as a background job with `$$` liveness check | Lines 215–217 — properly killed via `trap EXIT` |
| Dry-run mode (`--dry-run`) that changes nothing | Line 132 — the `run()` wrapper honours it for every command |
| SSH session protected by auto-relaunching in tmux | Lines 108–116 — prevents a dropped connection from leaving `pacman` mid-transaction |
| Version mismatch guards | Lines 338–345 — dies if headers don't match running kernel |
| Module integrity checked via `vermagic` | Lines 513–515 — refuses to install a mismatched module |
| Backup of original stock module before overwrite | Lines 537–543 — creates `*.orig`; does not overwrite an existing backup |
| `patch --dry-run` before applying | Line 485 — will die cleanly rather than partially patching |

#### ⚠️ Risks / Concerns

**[MEDIUM] Unauthenticated git clone of kernel packaging repo**

Lines 392–397:
```bash
run git clone --sparse "$PKG_CLONE_URL" "$PKGDIR"
run git clone "$PKG_CLONE_URL" "$PKGDIR"
```
- `https://gitlab.archlinux.org/archlinux/packaging/packages/linux.git` and `https://github.com/omacom/omarchy-pkgs.git` are cloned over HTTPS with no signature verification.
- `makepkg` subsequently calls `--skippgpcheck` (line 456) — so the kernel source tarball's PGP signature is **not verified**.
- Risk: a MITM or a compromise of the upstream GitLab/GitHub account could deliver a trojanised kernel source or PKGBUILD. This is a real, if low-probability, risk in the general case; on a VM behind a corporate proxy or captive portal with TLS inspection it is a higher concern.
- **Mitigation absent in the script.** A hardened version would pin a known-good commit hash and verify the kernel tarball PGP key.

**[MEDIUM] `makepkg -o --nodeps --skippgpcheck` (line 456)**

`--skippgpcheck` skips all PGP verification of the kernel source tarball and any patch source files listed in `source=()` of the PKGBUILD. This is a deliberate pragmatic choice (the author's keys may not be in the VM's keyring), but it means you are trusting the transport layer alone.

**[LOW] Sudo keepalive loop can outlive the script under unexpected exits**

Lines 215–216:
```bash
( while true; do sleep 50; sudo -n true 2>/dev/null || exit; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
```
The `trap EXIT` at line 217 kills `$SUDO_KEEPALIVE_PID` on script exit. However, if the script is killed with `SIGKILL` (not catchable), the background job orphans and the sudo credential cache remains hot for up to another 50 seconds. Low impact in a VM, but worth noting.

**[LOW] `rm -rf "$WORK"` if user answers yes to stale build dir prompt (line 204)**

`$WORK` defaults to `$HOME/vmwgfx-kernel-build` (line 63). The script checks `[[ -d $WORK ]]` and then confirms before removing it. No path traversal risk (value comes from `$HOME`, not user-supplied input on this path), but if someone sets `WORK=/` from the environment, `rm -rf /` would be proposed. The `confirm` guard prevents accidental deletion, but environment override is unchecked.

**[LOW] `$MAKEFLAGS_OVERRIDE` passed unquoted to `make`**

Line 506:
```bash
run env MAKEFLAGS="$MAKEFLAGS_OVERRIDE" make -C ... modules
```
The variable is shell-quoted here (`"$MAKEFLAGS_OVERRIDE"`), which is correct. However `make` itself will word-split its `MAKEFLAGS` environment variable; an adversarial value could inject extra make flags. Since only the legitimate user sets this in their environment, this is only a self-inflicted risk.

**[INFO] Log file world-readable by default**

Line 118:
```bash
LOGFILE="${LOGFILE:-$HOME/vmwgfx-kernel-patch-$(date +%Y%m%d-%H%M%S).log}"
```
The log captures all command output including `pacman -Qu` results and system info. It is written to `$HOME` (user-only directory on Arch), so this is not a leak vector under normal circumstances. Worth noting if the VM is shared.

---

### 2. `tools/post-install.sh` (323 lines)

#### ✅ What it does right

| Practice | Evidence |
|---|---|
| `set -euo pipefail` | Line 29 |
| Refuses to run as root | Line 142 |
| `--dry-run` mode throughout | Line 99 via `run()` wrapper |
| Re-entrant / idempotent config writes | Lines 116–133 — `write_block()` replaces its own marker block, never stacks copies |
| Backup before every file edit | Line 124 — `backup()` creates a timestamped `.bak-YYYYMMDD-HHmmss` copy |
| Explicit `sed` regex on known field name only | Line 264 — only rewrites `omarchy_gdk_scale = <value>` |
| Uses Omarchy's own `omarchy-toggle-idle` / `omarchy-toggle-screensaver` | Lines 233, 244 — does not directly manipulate Hyprland internals |
| `confirm()` reads from `/dev/tty` directly | Line 103 — immune to stdin redirection |

#### ⚠️ Risks / Concerns

**[LOW] Unquoted variable injection in `write_block` heredoc** 

Lines 277–284:
```bash
write_block "$MON_FILE" <<LUA
hl.monitor({
    output   = "$MONITOR_OUTPUT",
    mode     = "$MONITOR_MODE",
    ...
})
LUA
```
`MONITOR_OUTPUT`, `MONITOR_MODE`, `MONITOR_POSITION`, `MONITOR_SCALE` and `GDK_SCALE_VALUE` are all environment-overrideable. An adversarial value like `MONITOR_OUTPUT='"; os.execute("rm -rf ~") --'` would be injected verbatim into the Lua config. Since this config is read by Hyprland (a Lua interpreter), this is a **Lua code injection** vector — but only if the user themselves sets a malicious environment variable before running the script. Self-inflicted risk; not exploitable by a third party through normal use.

**[LOW] `mktemp` without `--suffix`; temp file in default `/tmp`**

Line 125:
```bash
local tmp; tmp=$(mktemp)
```
`/tmp` files are world-readable on creation before being written to. The written content (a Hyprland config fragment) is not sensitive. Symlink attacks on `/tmp` are mitigated by the `mv "$tmp" "$f"` pattern (it replaces by inode, not name). Low risk.

**[LOW] `hyprctl monitors all | grep -q "$WANT"` — unanchored grep (line 175)**

`$WANT` is `${MONITOR_MODE%@*}` (e.g. `1920x1200`). If a mode like `1920x1200` appears as a substring of another mode string, the check silently passes. This is a cosmetic validation false-positive, not a security risk — it only affects whether the script warns you before writing.

**[INFO] `omarchy-system-logout` executed via `exec` on user consent (line 319)**

This replaces the current shell process. It is correct behaviour (intended to close the desktop session) but if anything went wrong in the preceding config writes, a logout would prevent easy inspection. The `--dry-run` flag avoids this step entirely.

---

### 3. `patches/vmwgfx-bridge-fix.patch` (454 lines)

This is a **kernel-level patch** to `drivers/gpu/drm/vmwgfx/`. It touches six kernel source files.

#### Summary of what the patch does

| File | Change |
|---|---|
| `vmwgfx_prime.c` | Introduces `struct vmw_prime_import_bridge` — a minimal GEM wrapper around a TTM base object; adds `vmw_prime_resolve_handle()` for transparent handle redirection; rewrites `vmw_prime_fd_to_handle()` to return a standard GEM handle instead of a raw TTM handle |
| `vmwgfx_bo.c` | Adds a type check (`gobj->funcs != &vmw_gem_object_funcs`) before `to_vmw_bo()` to prevent an unchecked `container_of` on a non-vmw_bo object |
| `vmwgfx_drv.h` | Adds `file_priv` parameter to `vmw_user_resource_lookup_handle()` signature; declares `vmw_prime_resolve_handle()` |
| `vmwgfx_resource.c` | Adds bridge-handle resolution before TTM lookup; updates `vmw_user_object_lookup()` callsite |
| `vmwgfx_execbuf.c` | Updates two `vmw_user_resource_lookup_handle()` callsites to pass `filp` |
| `vmwgfx_ioctl.c` | Updates one `vmw_user_resource_lookup_handle()` callsite |
| `vmwgfx_surface.c` | Adds bridge-pinning around `ttm_ref_object_base_unref()` in the surface-destroy and surface-reference paths |

#### ✅ What the patch gets right

- **Reference counting is careful.** The bridge object takes its own independent `ttm_base_object` reference on creation (via `ttm_base_object_lookup_for_ref`), separate from the transient TTM ref-object entry that `ttm_prime_fd_to_handle()` creates. The bridge's own reference is released in `vmw_prime_import_bridge_free()` — correctly called only when the GEM refcount hits zero.
- **Race window explicitly documented and closed.** `vmw_prime_resolve_handle()` returns the GEM reference to the bridge *to the caller*, requiring the caller to hold it across the entire operation, not just during resolution. The comments in the patch (lines 179–197 of the patch diff) clearly document the cross-process handle-recycling race it prevents.
- **Type guard in `vmw_user_bo_lookup()`** prevents the existing unchecked `to_vmw_bo(container_of)` from being reached on a bridge object, eliminating a potential type-confusion / OOB pointer dereference.
- **`kzalloc` used for the bridge structure** — zeroes memory before use, no uninitialized field exposure.
- **`drm_gem_private_object_init` with `PAGE_SIZE`** — acceptable size for a non-backing GEM object; the bridge has no real memory backing.
- **Error paths are clean:** allocation failure frees `base_obj` before returning `-ENOMEM`; `ttm_ref_object_base_unref` is called on `drm_gem_handle_create` failure.

#### ⚠️ Risks / Concerns

**[MEDIUM] Not reviewed by upstream kernel maintainers**

The README is explicit and honest: *"it is not a substitute for a real upstream fix"*. The patch has had *no kernel review process* (no linux-kernel mailing list posting found, no Linus or DRM maintainer sign-off). Kernel code at this level (handle table lifetime, TTM/GEM bridging) is a well-known area for subtle use-after-free and double-free bugs. The design appears sound and the comments are thorough, but **without upstream review, latent concurrency bugs may exist** that only manifest under load or specific guest configurations.

**[MEDIUM-LOW] Deliberate TTM ref-object entry left alive after `vmw_prime_fd_to_handle()`**

Lines 261–278 of the patch (comment in `vmw_prime_fd_to_handle`):
> On success, deliberately leave the transient `ttm_ref_object` entry `ttm_prime_fd_to_handle()` created in place — do not touch it.

This is justified (Mesa's `vmw_surface_handle_reference()` requires `require_exist=true` to find it), but it means each `vmw_prime_fd_to_handle()` call leaves one `ttm_ref_object` entry alive in the tfile for the lifetime of the process's device fd. Repeated calls to `drmPrimeFDToHandle()` on the same fd without closing the device will accumulate these entries. The README documents this as a known, non-memory-unsafe limitation. In a VM that imports many buffers over a long session this could cause unnecessary resource consumption; it is not a security issue.

**[LOW] `vmw_prime_resolve_handle()` performs a GEM object lookup on every call**

`vmw_prime_resolve_handle()` is called at several high-frequency paths (`vmw_user_resource_lookup_handle`, `vmw_surface_destroy_ioctl`, etc.). Each call acquires and releases a reference on a GEM object. On a fast path this is a spinlock acquire/release plus an IDR lookup. For a VM workload this is negligible; on a high-throughput native render workload it could add measurable latency. Not a security concern, but a performance note.

**[LOW] `bridge->ttm_handle` is a uint32 stored in a heap-allocated struct**

If the struct is ever freed while the `ttm_handle` is still in use by a caller that held only a `uint32_t` copy (not the GEM reference), the handle can be recycled. The design requires callers to hold the GEM reference across use, and all callsites in the patch do so — but a future callsite added without reading the contract could violate this. This is a code-review / maintenance risk, not a current bug.

---

### 4. `tools/vmwtest.c` (72 lines)

A minimal diagnostic reproducer. Opens `/dev/dri/renderD128`, creates a GBM BO, exports a dma-buf, re-imports it via `drmPrimeFDToHandle`, then attempts `drmCloseBufferHandle` (the failing path) and `DRM_VMW_UNREF_SURFACE` (the workaround path).

#### ✅ Clean

- No network access, no file writes, no privilege escalation.
- Hardcodes `/dev/dri/renderD128` — non-configurable but harmless for a diagnostic tool.
- `drmVersionPtr` is freed after use (`drmFreeVersion`).
- All return codes checked.
- No dynamic memory leaks visible (GBM device/BO not explicitly destroyed, but process exit is imminent either way).

#### ⚠️ Minor

**[INFO] Hardcoded `/dev/dri/renderD128`** — will silently test the wrong device on a multi-GPU system or if `renderD128` is not the vmwgfx node. Not a security issue, but could give a misleading `PATCH IS NOT REQUIRED` result on unusual hardware.

---

## Summary Risk Table

| Finding | File | Severity | Exploitable by third party? |
|---|---|---|---|
| Unauthenticated git clone + `--skippgpcheck` | `install-kernel-patch.sh` | MEDIUM | Requires MITM or upstream repo compromise |
| Unverified kernel source tarball | `install-kernel-patch.sh` | MEDIUM | Requires MITM or upstream repo compromise |
| Patch not upstream-reviewed | `vmwgfx-bridge-fix.patch` | MEDIUM | Latent kernel bug risk only |
| TTM ref-object entry accumulation | `vmwgfx-bridge-fix.patch` | LOW | No — resource usage only |
| `WORK` env override could target arbitrary dir | `install-kernel-patch.sh` | LOW | No — self-inflicted |
| Lua code injection via env vars | `post-install.sh` | LOW | No — self-inflicted |
| Sudo credential cache window after SIGKILL | `install-kernel-patch.sh` | LOW | Requires local attacker on same UID |
| `mktemp` in `/tmp` (config fragment) | `post-install.sh` | LOW | No — content is non-sensitive |
| Hardcoded `/dev/dri/renderD128` | `vmwtest.c` | INFO | No |
| Unanchored grep for mode validation | `post-install.sh` | INFO | No |

---

## Recommendations (no code changes — per /plan scope)

1. **For a VMware guest VM you trust:** The package is safe to run as-is. The risks are intrinsic to community kernel patching, not to hostile intent. Read and accept the README's caveats.

2. **For higher assurance:** Manually verify the `git clone` URLs match the expected upstreams, pin the packaging repo to a specific commit hash after inspection, and drop `--skippgpcheck` (adding the Arch signing key to the VM's pacman keyring first).

3. **After running:** Verify the loaded module's `srcversion` against what the build printed (`cat /sys/module/vmwgfx/srcversion`), and run `vmwtest` post-reboot to confirm the fix is active.

4. **Watch for upstream resolution:** The `vmwgfx` bug is real and documented. Check the Linux kernel DRM mailing list for an official fix; once one lands, uninstall this module and restore from the `*.orig` backup.

---

> [!NOTE]
> This review covers only the files in `~/Omarchy-Black-Screen-VMware-Fix`. It does not cover packages installed as build dependencies (`base-devel`, `linux-headers`, `git`, `patch`, `open-vm-tools`) or the Omarchy/Arch package mirror infrastructure.

> [!WARNING]
> The patched `vmwgfx.ko` is a **kernel module** — it runs in ring 0. A bug in it can crash the guest or cause silent memory corruption. On a VMware guest the blast radius is limited to the VM, but treat any kernel rebuild on a production VM with appropriate caution.
