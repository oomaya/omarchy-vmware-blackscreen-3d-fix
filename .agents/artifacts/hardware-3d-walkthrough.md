# Walkthrough: Hardware 3D Acceleration Enabled in Hyprland

## Summary of Accomplishments
1. **Backed up** [hyprland.lua](file:///home/rand/dotfiles/hyprland/.config/hypr/hyprland.lua) before modification.
2. **Commented out `LIBGL_ALWAYS_SOFTWARE`**:
   Removed the forced CPU software rasterization (`llvmpipe`) override in `~/dotfiles/hyprland/.config/hypr/hyprland.lua`.
3. **Validated syntax**:
   Confirmed clean Lua syntax and immediate reflection across the `~/.config/hypr/hyprland.lua` symlink.

---

## Changes Made

In [~/dotfiles/hyprland/.config/hypr/hyprland.lua](file:///home/rand/dotfiles/hyprland/.config/hypr/hyprland.lua#L22-L26):
```diff
 if virt_env == "vmware" or virt_env == "qemu" or virt_env == "kvm" or virt_env == "oracle" then
   hl.env("AQ_DRM_DEVICES", "/dev/dri/card0")
-  hl.env("LIBGL_ALWAYS_SOFTWARE", "1")
+  -- hl.env("LIBGL_ALWAYS_SOFTWARE", "1") -- Hardware 3D enabled via patched vmwgfx
   hl.env("AQ_NO_MODIFIERS", "1")
```

---

## Next Step: Session Restart & Verification

Because compositor environment variables are read at Hyprland process startup:

### 1. Log Out / Restart the Desktop Session
Run in your terminal or via keybinding:
```bash
omarchy-system-logout
```
*(or `hyprctl dispatch exit`)*

### 2. Post-Login Hardware 3D Verification Commands
Once logged back in to the graphical session, run:
```bash
eglinfo -B | grep -E 'renderer|version|vendor'
```
**Expected Output:**
```text
OpenGL core profile vendor: VMware, Inc.
OpenGL core profile renderer: SVGA3D; build: RELEASE; LLVM;
```

You can also run `glxinfo -B`:
```bash
glxinfo -B | grep -E 'OpenGL renderer|OpenGL version'
```
**Expected Output:**
```text
OpenGL renderer string: SVGA3D; build: RELEASE; LLVM;
```

---

## Emergency Rollback One-Liner (TTY3)
If you encounter any graphical issue upon login:
1. Switch to plain console: **`Ctrl+Alt+F3`**
2. Re-enable software render:
   ```bash
   sed -i 's/-- hl.env("LIBGL_ALWAYS_SOFTWARE", "1")/hl.env("LIBGL_ALWAYS_SOFTWARE", "1")/' ~/.config/hypr/hyprland.lua
   ```
3. Return to graphical login: `omarchy-system-logout` or `systemctl restart greetd`
