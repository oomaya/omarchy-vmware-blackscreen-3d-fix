# VMware (`omarchy-vm`) 마우스 커서 지연 수정 회귀 테스트 계획 (Regression Test Plan)

- **작성일**: 2026-11-12
- **기준 상태(Baseline)**:
  - Host: VMware `Optimize mouse for games = Never`
  - Guest: `cursor:no_hardware_cursors = 1` (`~/.config/hypr/hyprland-gui.lua`), `input:sensitivity = 0.35` (`~/.config/hypr/input.lua`)

---

## 1. 주요 회귀(Regression) 위험 요인

| 우선순위 | 위험 요인 | 발생 시나리오 | 예상 증상 |
| :--- | :--- | :--- | :--- |
| **높음 (P0)** | **HyprMod 덮어쓰기** | `hyprmod` GUI에서 설정 저장 또는 프로파일 전환 시 `hyprland-gui.lua` 재생성 | `no_hardware_cursors`가 `0`으로 복귀 → 커서 끊김 재발 |
| **높음 (P0)** | **Omarchy 설정 초기화** | `omarchy refresh hyprland` 또는 일부 `omarchy update` 마이그레이션 실행 | `input.lua`의 `sensitivity = 0.35` 소실 |
| **중간 (P1)** | **커널/패키지 업데이트 후 재부팅** | 커널 업그레이드 후 DKMS 미빌드, `vmtoolsd` 중단, Hyprland 옵션 스키마 변경 | SVGA3D 가속 해제 또는 `hyprctl configerrors` 발생 |
| **낮음 (P2)** | **Win11 VMware 설정 초기화** | VMware Workstation 업데이트 또는 VM 재등록 시 Preferences/VMX 변경 | 포커스 진입·이탈 시 포인터 튐/지연 재발 |

---

## 2. 회귀 테스트 케이스 (Test Cases)

### TC-1. 라이브 Hyprland 런타임 불변성 검증 (즉시 실행)
- **목적**: 실제 동작 중인 Hyprland 메모리에 수정값이 반영되어 있고 문법 오류가 없는지 확인.
- **검증 커맨드**:
  ```bash
  hyprctl configerrors
  hyprctl getoption cursor:no_hardware_cursors
  hyprctl getoption input:sensitivity
  hyprctl getoption input:accel_profile
  ```
- **Pass 기준**:
  - `configerrors`: 출력 없음(빈 문자열)
  - `cursor:no_hardware_cursors`: `int: 1` (`set: true`)
  - `input:sensitivity`: `float: 0.350000` (`set: true`)
  - `input:accel_profile`: `str: flat`

### TC-2. HyprMod 재저장 / 프로파일 전환 회귀 테스트 (P0)
- **절차**:
  1. `hyprmod` GUI를 열어 임의 설정 변경/저장 또는 프로파일(`Omarchy_HW_Cursor_Off`) 재적용.
  2. `~/.config/hypr/hyprland-gui.lua` 내용 및 `TC-1` 재실행.
- **Pass 기준**: `no_hardware_cursors`가 `0`으로 덮어씌워지지 않고 `1` 유지.
- **실패 시 대응**: `~/.config/hypr/hyprland.lua`의 `require("hyprland-gui")` **뒤쪽**에 VMware 전용 강제 가드(`no_hardware_cursors = true`)를 배치해 HyprMod가 덮어쓰지 못하도록 구조적으로 차단.

### TC-3. 재부팅 및 커널/드라이버 파이프라인 유지 테스트 (P1)
- **트리거**: VM 재부팅 직후, 또는 `pacman -Syu` (커널 / `mesa` / `hyprland` / `open-vm-tools` 업데이트) 후.
- **검증 커맨드**:
  ```bash
  dkms status | grep vmwgfx-workaround
  systemctl is-active vmtoolsd.service vmwgfx-boot-guard.service
  eglinfo -B -p gbm 2>/dev/null | grep -E "OpenGL core profile renderer|version"
  ```
- **Pass 기준**:
  - `vmwgfx-workaround` 상태가 `installed`
  - `vmtoolsd.service`, `vmwgfx-boot-guard.service` 모두 `active`
  - 렌더러가 `SVGA3D` (소프트웨어 `llvmpipe` 폴백 아님) + `TC-1` 전체 Pass.

### TC-4. Omarchy 업데이트/리프레시 후 회귀 점검 (P0)
- **트리거**: `omarchy update` 또는 `omarchy refresh hyprland` 실행 직후.
- **검증**: `TC-1` 실행 및 `~/.config/hypr/input.lua` 내 `sensitivity = 0.35` 존재 확인.

### TC-5. 호스트-게스트 포인터 체감 테스트 (수동 Smoke Test)
- **절차**:
  1. Win11 호스트에서 VM 창 안팎으로 마우스 5회 연속 진입/이탈 (`Optimize mouse for games = Never` 동작 확인).
  2. `2558x1374` 화면 대각선 고속 왕복 및 창 리사이즈/드래그 수행.
  3. 30초 유휴 상태 후 커서 첫 이동 시 뚝 끊김 여부 확인.
- **Pass 기준**: 포인터 좌표 튐, 눈에 띄는 프레임 드랍, 유휴 후 첫 이동 멈춤 없음.

---

## 3. 원클릭 회귀 점검 커맨드 (터미널 복붙용)

```bash
echo "=== 1. Hyprland Errors ===" && hyprctl configerrors
echo "=== 2. Cursor & Input ===" && hyprctl getoption cursor:no_hardware_cursors && hyprctl getoption input:sensitivity
echo "=== 3. VMware Services & DKMS ===" && systemctl is-active vmtoolsd.service && dkms status | grep vmwgfx
echo "=== 4. 3D Renderer ===" && eglinfo -B -p gbm 2>/dev/null | grep "core profile renderer"
```

---

## 4. (권장) 구조적 재발 방지 강화 옵션
현재는 `~/.config/hypr/hyprland-gui.lua`와 HyprMod 프로파일을 직접 수정한 상태입니다. 만약 앞으로 `hyprmod` GUI를 자주 쓰실 계획이라면, `~/.config/hypr/hyprland.lua` 맨 마지막(`require("hyprland-gui")` 이후)에 `if virt_env == "vmware" then hl.config({ cursor = { no_hardware_cursors = true } }) end` 가드를 한 번 더 두면 **어떤 경우에도 하드웨어 커서 회귀를 원천 차단**할 수 있습니다.

