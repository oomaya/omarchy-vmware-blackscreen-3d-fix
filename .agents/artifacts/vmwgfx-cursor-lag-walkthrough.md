# VMware (`omarchy-vm`) 마우스 커서 지연 해결 및 영구 가드 적용 Walkthrough

- **완료일**: 2026-11-12
- **대상 노드**: `omarchy-vm` (Hyprland Wayland + `vmwgfx` DKMS + `open-vm-tools`)

---

## 1. 근본 원인 요약
1. **HyprMod 덮어쓰기 충돌**: `~/.config/hypr/hyprland.lua`의 VMware 가드(`no_hardware_cursors = true`)를 맨 마지막(68행)에 로드되는 `~/.config/hypr/hyprland-gui.lua`의 `no_hardware_cursors = 0`이 덮어써서 `vmwgfx` 하드웨어 커서가 재활성화되고 있었음.
2. **레거시 환경변수 무효화**: `/etc/environment`의 `WLR_NO_HARDWARE_CURSORS=1`은 Aquamarine 기반 최신 Hyprland에서 무시됨.
3. **고해상도 감도 저하**: `Virtual-1` (`2558x1374@60`) + `accel_profile = "flat"` 조합에서 `sensitivity = 0`으로 동작.

---

## 2. 최종 적용 사항

### A. Win11 호스트 (VMware Workstation)
- `Edit → Preferences → Input → Optimize mouse for games` = **`Never`**

### B. 게스트 Hyprland 설정 (`~/.config/hypr/`)
1. **`~/.config/hypr/hyprland-gui.lua`** & 활성 HyprMod 프로파일(`~/.config/hypr/hyprmod/profiles/f9ea2a576f72/hyprland-gui.lua`):
   - `no_hardware_cursors = 1` 적용 (백업 완료)
2. **`~/.config/hypr/hyprland.lua`** (`require("hyprland-gui")` 이후 최종 가드 추가):
   ```lua
   -- Enforce software cursor in VMware after HyprMod overrides
   if virt_env == "vmware" then
     hl.config({
       cursor = {
         no_hardware_cursors = true,
       },
     })
   end
   ```
   - `bootstrap.lua` 리로드 구조상 `hyprctl reload` 시에도 항상 최종 우선순위로 적용되어 HyprMod 회귀를 원천 차단함.
3. **`~/.config/hypr/input.lua`**:
   - `sensitivity = 0.35` 추가 (백업 완료)

### C. 시스템 환경변수 정리 (`/etc/environment`)
- `/etc/environment.bak.*` 백업 후 아래 두 줄 주석 처리:
  - `WLR_NO_HARDWARE_CURSORS=1` (Aquamarine Hyprland에서 deprecated)
  - `AQ_NO_MODIFIERS=1` (`~/.config/uwsm/env-hyprland` 및 `hyprland.lua`의 VM 전용 동적 분기로 일원화)

---

## 3. 검증 결과
- `hyprctl reload` → `ok`
- `hyprctl configerrors` → 오류 0건
- `hyprctl getoption cursor:no_hardware_cursors` → `int: 1` (`set: true`)
- `hyprctl getoption input:sensitivity` → `float: 0.350000` (`set: true`)
- `vmtoolsd.service` / `vmwgfx-boot-guard.service` → `active`, `SVGA3D` OpenGL 4.3 가속 유지

---

## 4. 다른 테크리드를 위한 기록 위치 (Discovery Map)
1. **프로젝트 로컬 인덱스**: `.agents/artifacts/INDEX.md` (본 저장소 내 계획·회귀테스트·워크스루 일괄 등록)
2. **크로스 머신 Handoff**: `~/Documents/artifacts/handoffs/LATEST.md` (`antigravity-handoff view` 로 세션 시작 시 자동 조회)
3. **글로벌 스킬 지식 수확**: `oomaya/antigravity-skills` → `omarchy` 스킬 레퍼런스 및 `docs/harvest_log.md` (`antigravity-harvest`)

