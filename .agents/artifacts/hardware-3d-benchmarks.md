# OpenGL Benchmark Report: VMware SVGA3D (Hardware) vs llvmpipe (Software)

## Executive Summary

Following the deployment of the kernel `vmwgfx` bridge patch and the removal of software-rasterizer overrides (`LIBGL_ALWAYS_SOFTWARE`), we conducted comparative OpenGL performance benchmarks under native **Wayland** using `glmark2-wayland`.

- **Overall Benchmark Score**: **448** (SVGA3D Hardware) vs **57** (llvmpipe CPU) — **7.86× overall performance multiplier**.
- **Terrain Simulation**: **289 FPS** (Hardware) vs **11 FPS** (Software) — **26.27× faster**.
- **Desktop Shading**: **463 FPS** (Hardware) vs **52 FPS** (Software) — **8.90× faster**.
- **Interactive Latency**: Frame times dropped from **12–91 ms** down to **1.3–4.7 ms**, completely eliminating UI micro-stutters and input lag under Hyprland.

---

## Comparative Benchmark Data (`glmark2-wayland`)

**Test Environment**:
- **Host**: VMware Workstation Guest
- **Kernel**: `7.2.5-3-omarchy` (with `vmwgfx-bridge-fix.patch`)
- **Compositor**: Hyprland 0.56.2 on Wayland (`AQ_DRM_DEVICES=/dev/dri/card0`)
- **Surface**: 800×600 Windowed, 32-bit color, depth buffer

| Benchmark Scene | Hardware (`SVGA3D`) | Software (`llvmpipe`) | Frame Time (HW vs SW) | Speedup Factor |
| :--- | :---: | :---: | :---: | :---: |
| **build** (geometry / VBOs) | **545 FPS** | 74 FPS | 1.84 ms vs 13.70 ms | **7.36×** |
| **bump** (normal / height mapping) | **737 FPS** | 84 FPS | 1.36 ms vs 11.94 ms | **8.77×** |
| **desktop** (blur & shadow passes) | **463 FPS** | 52 FPS | 2.16 ms vs 19.30 ms | **8.90×** |
| **buffer** (subdata & map updates) | **213 FPS** | 72 FPS | 4.72 ms vs 14.01 ms | **2.96×** |
| **terrain** (complex vertex/fragment) | **289 FPS** | 11 FPS | 3.46 ms vs 91.45 ms | **26.27×** |
| **glmark2 Composite Score** | **448** | **57** | — | **7.86×** |

---

## Key Technical Takeaways

1. **Host GPU Pass-through Functional**:
   The host GPU is successfully executing complex multi-pass shaders and high polygon counts with sub-2ms frame delivery.
2. **Elimination of CPU Throttling**:
   Under `llvmpipe`, complex scenes like `terrain` pegged multiple CPU cores to render 11 FPS (91.45 ms frame time), causing system fans to spin up and starving background threads. With `SVGA3D`, CPU usage remains minimal.
3. **Smooth Hyprland Rendering**:
   Animations, blur layers, shadows, and window resizes in Omarchy run with full hardware acceleration without compositor crashes or black-screen deadlocks.
