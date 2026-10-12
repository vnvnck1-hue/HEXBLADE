# 원화 3안 · 바닥/벽 실제 적용

**후속 최신 색(2026-10-12):** 사용자 요청으로 채도/명도를 크게 낮췄다. 현재 실행 기본값은 이 후속 보정이며, 최신 화면/검증은 `output/painted-room-muted-20261012/`. 이 폴더의 밝은 색 화면/검증은 최초 적용 당시 기록이다.

2026-10-12 사용자 요청에 따라 핸드드로잉 수정본3번의 연보라 바닥·크림 벽·보라 프레임을 실제 PNG로 제작하여 별도 정비실에 연결했다. 내장 image_gen 프롬프트는 `prompts.json`, 생성 원본 경로는 `sources.json`.

## 결과 확인

- `10_floor_wall_only.png`: 가구/설비를 숨긴 실제 Forward+ 바닥·벽 화면.
- `11_original_floor_wall_only.png`: 동일 조명/시점의 기존 바닥·벽.
- `01_after_neutral.png` / `02_before_neutral.png`: 기존 가구/설비를 함께 둔 전후 비교.
- `03_after_game_light.png` / `04_before_game_light.png`: 본편 색/광량의 조명 비교.
- `05_png_color.png`: PNG 원색(unshaded).
- `06_floor_top.png` / `07_wall_front.png` / `08_reverse_angle.png`: 바닥/정면/반대 각도.
- `09_controls.png` / `12_controls_1280.png`: 조작 UI, 1600×1000 및 1280×800.
- `13_static_mech_markers.png` / `14_static_mech_original.png`: 실제 메카 GLB 정지 모델과 단순 표식의 전후 비교. 전투 시뮬레이션은 아니다.
- `bot_views/`: 실제 자동 조작의 고정5시점. 프레임 덤프가 아니다.

로비 → 테스트 씬 → **핸드페인팅 정비실 · 크림 / 연보라** 또는 `launchers/scenes/painted_room_study.cmd`. 조작/연결 설명은 `docs/painted-room-floor-wall.md`.

## 연결/범위

`assets/textures/painted_room/`의 PNG3장을 흰색 배수·거칠기1·금속성0의 재질로 직접 샘플링한다. 원화 픽셀을 코드에서 다시 합성하지 않는다. 12개 바닥 판/설비 데크/11개 벽의 전용 메시 복사본에 UV를 새로 배정하며 원본 GLB·공유 재질·위치/형상은 유지한다. 원본 비교 시 원래 메시도 복원한다. 바닥 그림은 8×6m 방 전용이며 모든 랜덤 방에 적용한 상태는 아니다. 가구/벽 장치/탱크/배관은 기존 외형이다.

## 검증과 중간 기록

최종 상태는 `validation.json`에 기록한다. `check_final.log`는 전용24항목, `render_review.log`는 실제12화면, `readability_glb.log`는 정지 GLB 비교, `bot.log`와 `bot_render.log`는 헤드리스/Forward+ 자동 조작8단계, `main_bot.log`는 기존 아레나30초 자동 플레이다.

전체 `tools/run_tests.ps1` 59종 최초 결과는 56 PASS / `infest_check`, `partner_drone_check`, `stream_mode_check` 3종 FAIL(`all_tests.log`). 드론 보호막/재화 이동은 단독 재검사에서 모두 PASS(`other_recheck.log`). 포낭 밀어내기는 단독 재실행에도 FAIL(`infest_recheck.log`). 따라서 재검사 포함 최종58 PASS / 1 FAIL이며 전체 통과로 표시하지 않는다. 해당 관련 게임 코드는 이번 작업에서 변경하지 않았으며 다른 세션의 미커밋 변경을 보존했다. 최종 임포트는 `import_release.log`/`import_release_engine.log`다.

초기 임포트의 AppData 권한 오류, 시험 코드의 enum 문법 오류/잘못 전달된 종료 인자, 하늘 없는 시험 씬의 암부 문제, 정지 메카 어댑터의 자원 정리 오류를 수정하는 과정의 로그도 보존했다. 최종 실행 로그와 혼동하지 않는다. 정지 모델 비교는 최종에 GLB 원형을 사용해 종료 오류를 없앴다. 커밋/푸시 없음.
