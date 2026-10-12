# 바닥·벽 저채도/저명도 수정

사용자 요청: “전반적으로 채도 명도를 매우 낮춰줘. 지금은 너무 높아서 캐릭터나 아이템이 안보일 것 같아”.

실제 정비실의 바닥·벽 재질에만 색 보정을 연결했다. 원본 PNG·붓질·줄눈·UV·조명은 보존한다. 캐릭터/표식/UI에는 보정을 적용하지 않는다. 새 이미지 생성/재작화 없이 Godot의 표면 셰이더에서 원본 텍스처를 직접 샘플링해 보정한다. 선형 RGB 휘도와의 혼합 채도0.18, 밝기 배수0.22. 지각 명도를 정확히22%로 만드는 의미는 아니다.

최신 실제 화면:

- `10_floor_wall_only.png` / `15_previous_bright_floor_wall.png`: 같은 카메라/중립 조명에서 낮춘 바닥·벽과 이전 밝은 색 비교.
- `13_static_mech_markers.png` / `16_previous_bright_mech_markers.png`: 같은 카메라/게임 조명에서 실제 메카 GLB 정지 모델과 단순 청록/코랄 표식 비교. 실제 아이템이나 전투 시뮬레이션은 아니다.
- `17_static_mech_real_pickups.png` / `18_previous_bright_real_pickups.png`: 본편 Pickup의 에너지 셀/미사일 실제 메시·재질을 정지시켜 추가 비교. 위치/크기/색은 동일하며 줍기·이동·전투 판정은 실행하지 않는다.
- `01_after_neutral.png`, `03_after_game_light.png`: 가구/설비를 포함한 결과.
- `05_corrected_color.png`: 조명 없이 보정한 표면색.
- `06_floor_top.png`, `07_wall_front.png`, `08_reverse_angle.png`: 다른 시점.
- `09_controls.png`, `12_controls_1280.png`: 조작 UI.

로비 → 테스트 씬 → **핸드페인팅 정비실 · 크림 / 연보라**. `launchers/scenes/painted_room_study.cmd`도 동일한 최신 색을 실행한다. B는 본편 원본과 비교하며 보정색↔조명 버튼은 두 모드 모두 낮춘 색을 유지한다. 이전 밝은 색은 비교 캡처와 원본 PNG에 보존한다. 본편 랜덤 방 연결은 아직 하지 않았다.

`check.log`: 전용24항목 검사. `render.log`: 실제 Forward+13화면. `readability.log`: 메카/표식 비교3화면, `pickups.log`: 실제 Pickup 포함5화면. `bot.log`: 실제 자동 조작12초8단계. `all_tests.log`: 전체회귀59종. 최종 결과/색 계수는 `validation.json`, 화면 측정은 `palette_metrics.json` 참조. 기존 다른 세션 변경 보존, 커밋/푸시 없음.

**최종 검증:** 전체59종 모두 PASS. 전용24항목/실제 렌더/정지 메카·아이템 비교/자동 조작 ERROR0/SCRIPT ERROR0. 초기 적용 때 실패했던 포낭·드론·재화 검사도 이번 전체 실행에서는 모두 PASS. 원본 PNG3장 SHA256 불변 확인.
