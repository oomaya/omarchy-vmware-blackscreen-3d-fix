# Investigation: Why `eglinfo -B` Hangs Silently

## Executive Summary

When running `eglinfo -B | grep -E 'renderer|version|vendor'`, the command produces no output and appears completely silent because **it hangs indefinitely on an uncompleted X11 socket handshake**, and standard output is pipe-buffered by `libc`.

The root cause was an **infinite self-invocation loop** in the Xwayland wrapper script (`~/.local/bin/Xwayland`), which burned 100% of a CPU core while leaving `/tmp/.X11-unix/X0` in a zombie listen state. Additionally, `LIBGL_ALWAYS_SOFTWARE=1` in `/etc/environment` is forcing Mesa to use `llvmpipe` on Wayland despite hardware acceleration being functional on VMware.

---

## Technical Root Cause Analysis

### 1. The X11 Handshake Deadlock

1. In your desktop environment (Hyprland / Ghostty), `DISPLAY=:0` is exported.
2. `eglinfo -B` attempts to query **all** available platforms in sequence:
   - **GBM platform**: Succeeded (`VMware, Inc. SVGA3D`).
   - **Wayland platform**: Succeeded (`Mesa llvmpipe`).
   - **X11 platform**: Attempted to connect to `$DISPLAY` (`:0`).
3. Socket `/tmp/.X11-unix/X0` was open and listening, but the process listening was PID 1473:
   ```bash
   bash /home/rand/.local/share/../bin/Xwayland :0 -rootless -core -listenfd 48 -listenfd 49 -displayfd 77 -wm 74 -glamor off
   ```
4. `eglinfo` connected to `/tmp/.X11-unix/X0` and sent the standard X11 connection setup packet, then blocked on `read()` waiting for Xwayland to reply.
5. Because PID 1473 was trapped in an infinite `exec` loop, it never read from or accepted the client connection.
6. When piping `eglinfo` into `grep`, `libc` switched stdout from line-buffering to 4096-byte block-buffering. Because `eglinfo` blocked before filling the 4KB buffer or exiting, `grep` received zero bytes and output nothing.

---

### 2. Why `Xwayland` Was Trapped in a Loop

In [hyprland/.local/bin/Xwayland](file:///home/rand/dotfiles/hyprland/.local/bin/Xwayland):

```bash
# Naive string matching failed:
SYSTEM_PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "^${HOME}/\.local/bin$" | paste -sd:)
REAL_BIN=$(PATH="$SYSTEM_PATH" command -v Xwayland 2>/dev/null || echo "/usr/bin/Xwayland")
```

Because `. "$HOME/.local/share/../bin/env"` was sourced in `~/.bashrc` / `~/.bash_profile`, `$PATH` contained the uncanonicalized directory `/home/rand/.local/share/../bin`.
- `grep -v "^${HOME}/\.local/bin$"` did **not** match `/home/rand/.local/share/../bin`.
- `PATH="$SYSTEM_PATH" command -v Xwayland` resolved back to `/home/rand/.local/share/../bin/Xwayland` (the wrapper itself).
- The wrapper endlessly re-executed itself, consuming 100% of a CPU core without launching `/usr/bin/Xwayland`.

---

### 3. Wayland Using Software Rasterizer (`llvmpipe`)

Even after fixing the hang, running `DISPLAY= eglinfo -p wayland` reported:
```
OpenGL core profile vendor: Mesa
OpenGL core profile renderer: llvmpipe (LLVM 22.1.8, 256 bits)
```
Although you commented out `LIBGL_ALWAYS_SOFTWARE` in `hyprland.lua`, it is still defined in `/etc/environment`:
```ini
LIBGL_ALWAYS_SOFTWARE=1
WLR_NO_HARDWARE_CURSORS=1
AQ_NO_MODIFIERS=1
```
PAM sets this globally for all user sessions. When tested with `LIBGL_ALWAYS_SOFTWARE=0`, Mesa immediately activated the native VMware SVGA3D hardware driver:
```
OpenGL core profile vendor: VMware, Inc.
OpenGL core profile renderer: SVGA3D; build: RELEASE;  LLVM;
OpenGL core profile version: 4.3 (Core Profile) Mesa 26.2.2-arch1.1
```

---

## Surgical Fix Applied

1. **Patched [Xwayland](file:///home/rand/dotfiles/hyprland/.local/bin/Xwayland)**:
   Replaced naive regex path stripping with canonical path resolution (`realpath`) across all `$PATH` entries and added a recursion guard.
2. **Killed Runaway PID 1473**:
   Terminated the 100% CPU spinning bash loop.
3. **Verified [Xwayland](file:///home/rand/dotfiles/hyprland/.local/bin/Xwayland)**:
   Verified `~/.local/bin/Xwayland -version` executes `/usr/bin/Xwayland` cleanly.

---

## Recommended Next Steps

1. **Immediate eglinfo check without X11**:
   ```bash
   LIBGL_ALWAYS_SOFTWARE=0 DISPLAY= eglinfo -p wayland | grep -E 'renderer|version|vendor'
   ```
2. **Update `/etc/environment`**:
   Remove or comment out `LIBGL_ALWAYS_SOFTWARE=1` in `/etc/environment` so hardware acceleration takes effect across your whole desktop:
   ```bash
   sudo sed -i 's/^LIBGL_ALWAYS_SOFTWARE=1/# LIBGL_ALWAYS_SOFTWARE=1/' /etc/environment
   ```
3. **Restart Desktop Session**:
   Run `omarchy-system-logout` to reload PAM environment variables and cleanly initialize the patched Xwayland.
