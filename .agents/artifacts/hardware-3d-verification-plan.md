# Plan: Disable Software Rendering in Hyprland & Verify Hardware 3D Acceleration

This plan details the step-by-step procedure to disable the `LIBGL_ALWAYS_SOFTWARE` override in `hyprland.lua`, verify hardware-accelerated 3D rendering (`SVGA3D`) under Hyprland, and ensure a seamless, zero-risk fallback path.

---

## Quota & Token Budget Analysis (Go/No-Go Decision Gate)

| Metric | Status / Value | Assessment |
|---|---|---|
| **Gemini Weekly Allowance** | **96.4%** remaining | 🟢 Safe (threshold > 15%) |
| **Gemini 5-Hour Rolling** | **78.7%** remaining | 🟢 Safe |
| **Claude Weekly Allowance** | **0.0%** remaining | 🔴 Quota exhausted |
| **Projected Phase Tokens** | ~2,500 - 4,000 tokens | Minimal budget footprint |
| **Model Selection Rationale** | **Gemini Flash (Active)** | Fast, low latency, surgical edits with abundant quota. Zero risk of 429 throttling. |
| **Decision Gate** | **GO** | Proceed with Gemini execution. |

---

## User Review Required

> [!IMPORTANT]
> **Session Restart Required for Compositor GL Context**:
> Environment variables defined in `hyprland.lua` take effect when the Hyprland process initializes. Therefore, testing the compositor's own hardware rendering requires logging out and back in (`omarchy-system-logout`).
>
> **Safety Guarantee**:
> In the unlikely event of a compositor hang, TTY console is immediately accessible via **`Ctrl+Alt+F3`**, where a simple one-liner immediately restores the software rendering fallback.

---

## Open Questions

None. The kernel patch has been verified with `vmwtest` (`RESULT: PATCH IS NOT REQUIRED`), and a live Wayland EGL client already confirmed `OpenGL core profile renderer: SVGA3D; build: RELEASE; LLVM;` without crashing.

---

## Proposed Changes

### Hyprland Dotfiles Configuration

#### [MODIFY] [hyprland.lua](file:///home/rand/dotfiles/hyprland/.config/hypr/hyprland.lua)
- Comment out `hl.env("LIBGL_ALWAYS_SOFTWARE", "1")`.
- Keep `AQ_DRM_DEVICES = "/dev/dri/card0"` and `AQ_NO_MODIFIERS = "1"` intact (safe baseline for VMware virtual KMS).
- Keep cursor & dialog safeguards (`no_hardware_cursors = true`, `enable_anr_dialog = false`) to avoid known Aquamarine virtual driver quirks.

```lua
-- Before:
if virt_env == "vmware" or virt_env == "qemu" or virt_env == "kvm" or virt_env == "oracle" then
  hl.env("AQ_DRM_DEVICES", "/dev/dri/card0")
  hl.env("LIBGL_ALWAYS_SOFTWARE", "1")
  hl.env("AQ_NO_MODIFIERS", "1")
  ...

-- After:
if virt_env == "vmware" or virt_env == "qemu" or virt_env == "kvm" or virt_env == "oracle" then
  hl.env("AQ_DRM_DEVICES", "/dev/dri/card0")
  -- hl.env("LIBGL_ALWAYS_SOFTWARE", "1") -- Hardware 3D enabled via patched vmwgfx
  hl.env("AQ_NO_MODIFIERS", "1")
  ...
```

---

## Verification Plan

### Phase 1: Pre-Restart Sanity
1. Verify `hyprland.lua` syntax.
2. Confirm the backup file exists prior to modification.

### Phase 2: Session Transition
1. User logs out cleanly via `omarchy-system-logout` (or `hyprctl dispatch exit`).
2. Log back into Omarchy Hyprland desktop session.

### Phase 3: Hardware 3D Diagnostics
1. **Compositor EGL Profile**:
   ```bash
   eglinfo -B | grep -E 'renderer|version|vendor'
   ```
   *Expected*: `OpenGL core profile renderer: SVGA3D; build: RELEASE; LLVM;` (No longer `llvmpipe`).
2. **GLX Check (if XWayland active)**:
   ```bash
   glxinfo -B | grep -E 'OpenGL renderer|OpenGL version'
   ```
   *Expected*: `OpenGL renderer string: SVGA3D; build: RELEASE; LLVM;`
3. **Hyprland Diagnostics**:
   ```bash
   hyprctl systeminfo
   journalctl --user -u hyprland -b 0 | grep -iE 'gl|render|svga|error'
   ```
   *Expected*: Clean startup with no GPU crash, no buffer import failure, and no black screen.
4. **Desktop Responsiveness**:
   - Verify smooth window dragging and workspace transitions with minimal CPU load (no llvmpipe CPU thrashing).

### Fallback / Rollback Plan
If any issue occurs upon login:
1. Switch to TTY3 (`Ctrl+Alt+F3`).
2. Re-enable software render:
   ```bash
   sed -i 's/-- hl.env("LIBGL_ALWAYS_SOFTWARE", "1")/hl.env("LIBGL_ALWAYS_SOFTWARE", "1")/' ~/.config/hypr/hyprland.lua
   ```
3. Switch back to TTY1 (`Ctrl+Alt+F1`) or run `systemctl restart greetd` / `omarchy-system-logout`.
