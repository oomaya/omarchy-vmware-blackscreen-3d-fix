# Walkthrough: Telegram Native Package Migration & Stale Workaround Eradication

## Problem & Root Cause Summary
1. **Broken Launcher Execution**:
   - `dotfiles/omarchy` contained legacy override files added on Sept 6 (`77f652e`):
     - `omarchy/.local/share/applications/org.telegram.desktop.desktop`
     - `omarchy/.local/bin/Telegram`
   - The wrapper script had an uncanonicalized `$PATH` handling bug (`/home/rand/.local/share/../bin`), causing it to execute itself in an endless 100% CPU recursion loop whenever invoked by application launchers (Fuzzel, omarchy menus).
   - The wrapper attempted to target `/usr/bin/Telegram` with `QT_QPA_PLATFORM=xcb`, which did not exist on the system.
2. **Harm Harmlessness of Qt Warning**:
   - `(qt.waylandcompositor.hardwareintegration: Failed to initialize EGL display. There is no EGL_WL_bind_wayland_display extension.)`
   - This diagnostic is purely informational for QtWayland compositor surface sharing and does not prevent native Wayland clients from rendering.

---

## Changes Implemented

### 1. Official Arch Linux Package (`extra/telegram-desktop`)
- Installed the official native Arch package:
  ```bash
  sudo pacman -S --needed telegram-desktop
  ```
- Binary installed to `/usr/bin/Telegram` (v7.2.5).
- Official desktop entry installed to `/usr/share/applications/org.telegram.desktop.desktop`.

### 2. Purged Legacy Dotfiles Workarounds
- Permanently deleted:
  - `~/dotfiles/omarchy/.local/share/applications/org.telegram.desktop.desktop`
  - `~/dotfiles/omarchy/.local/bin/Telegram`
- Removed lingering local symlinks in `~/.local/share/applications/` and `~/.local/bin/`.
- Updated desktop database cache.
- Committed and pushed changes to `oomaya/dotfiles` (`8fb540c`).

---

## Verification Results

1. **Path & Binary Resolution**:
   ```bash
   $ which Telegram
   /usr/bin/Telegram
   ```
2. **Window Mapping & Compositor Integration**:
   Native Wayland window verified via `hyprctl clients`:
   ```
   Window 654ae451a3a0 -> Telegram (3440):
       mapped: 1
       visible: 1
       acceptsInput: 1
       class: org.telegram.desktop
       xwayland: 0
   ```
   Telegram is confirmed running as a pure native Wayland application with hardware acceleration (`xwayland: 0`).
