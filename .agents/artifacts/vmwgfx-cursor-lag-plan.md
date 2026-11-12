# VMware (`omarchy-vm`) 마우스 커서 지연 개선 적용 계획 및 진행 현황

- **작성일**: 2026-11-12
- **대상 환경**: Windows 11 Host (VMware Workstation) + `omarchy-vm` Guest (Hyprland Wayland / `vmwgfx`)

---

## 1. 단계별 적용 계획 및 현황

### Phase 1: Win11 호스트 (VMware UI) — ✅ 완료
1. **VMware 입력 최적화 설정 변경**
   - 경로: `Edit → Preferences → Input → Optimize mouse for games`
   - 변경: `Automatic` → **`Never`** (사용자 적용 완료)
   - 효과: Wayland 게스트와 호스트 간 상대/절대 포인터 자동 전환 충돌 방지.

---

### Phase 2: `omarchy-vm` 게스트 (Hyprland 설정) — ✅ 적용 및 검증 완료
1. **기존 설정 백업**
   - `~/.config/hypr/hyprland-gui.lua` 및 `~/.config/hypr/input.lua` 타임스탬프 백업 생성 완료.
2. **하드웨어 커서 충돌 해제 (`no_hardware_cursors = 1`)**
   - 원인: `~/.config/hypr/hyprland.lua`의 VMware 가드(`no_hardware_cursors = true`)를 `~/.config/hypr/hyprland-gui.lua`의 `no_hardware_cursors = 0`이 마지막에 덮어쓰고 있었음.
   - 조치: `~/.config/hypr/hyprland-gui.lua` 및 활성 HyprMod 프로파일(`~/.config/hypr/hyprmod/profiles/f9ea2a576f72/hyprland-gui.lua`)을 **`no_hardware_cursors = 1`** 로 수정해 소프트웨어 커서 강제 복원.
3. **고해상도(`2558x1374`) 포인터 감도 보정**
   - 조치: `~/.config/hypr/input.lua`에 `sensitivity = 0.35` 추가 (`flat` 프로파일 유지).
4. **실시간 리로드 및 검증 (`hyprctl`)**
   - `hyprctl reload` → `ok`
   - `hyprctl configerrors` → 오류 0건
   - `cursor:no_hardware_cursors` = `int: 1` (`set: true`)
   - `input:sensitivity` = `float: 0.350000` (`set: true`)

---

### Phase 3: Win11 호스트 `.vmx` 튜닝 — ⏸️ 선택 사항 (필요 시 VM 종료 후 진행)
Phase 1 + Phase 2 적용 후 마우스 움직임을 체감해보시고, 여전히 간헐적 끊김이나 포인터 어긋남이 느껴질 때만 VM 완전 종료 후 `.vmx` 파일에 아래 옵션을 추가하세요.

```ini
mouse.vusb.enable = "TRUE"
mouse.vusb.useBasicMouse = "FALSE"
usb.generic.allowHID = "TRUE"
mks.vsync = "TRUE"
```
- **참고**:
  - `mouse.vusb.*` + `usb.generic.allowHID`: 레거시 `vmmouse` 대신 표준 USB HID 마우스 경로 우선 사용.
  - `mks.vsync`: 호스트 프레임 동기화 조정(환경에 따라 `"TRUE"` 또는 `"FALSE"` 비교 테스트 권장).
  - VM 디스플레이 설정의 `Accelerate 3D graphics`는 유지하고 VRAM은 512MB~2GB 이상 권장.

---

## 2. 롤백 / 미세 조정 가이드
- 커서가 너무 빠르거나 느리면 `~/.config/hypr/input.lua`의 `sensitivity` 값(`-1.0` ~ `1.0`, 현재 `0.35`)만 조정 후 저장하면 즉시 반영됩니다.
- 가속 커브가 필요할 경우 `~/.config/hypr/hyprland-gui.lua`의 `accel_profile`을 `"flat"` → `"adaptive"`로 변경할 수 있습니다.

