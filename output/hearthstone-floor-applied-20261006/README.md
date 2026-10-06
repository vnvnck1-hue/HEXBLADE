# 하스스톤풍 바닥 실제 적용

**최신 상태: 사용자가 실제 바닥을 산만하다고 평가하여 `../hearthstone-conservative-floor-20261006/`에 새 시안을 제작했다. 새 시안은 본편 미적용이며 이 적용안은 최종 채택되지 않았다. 아래 초기 톤 수치는 봇 인자가 전달되지 않은 정지 장면에서 측정한 중간 기록이다. 이후 실제 봇 전후 PNG를 같은 파일명으로 덮었고 프레임480 마스크의 유효 선택이 부족해 재측정이 완료되지 않았다. `tone_validation.json`과 `game_comparison.png`를 현재 PNG에 대한 최종 검증으로 사용하지 않는다. 초기 unquoted 봇 실행은 무효이며 실제 정상 봇 로그는 `bot_final.log`, 섹터 런 최종 로그는 `run_compare_final.log`다.**

전체 회귀 검사는 종료1로 완료, `diagonal_cutin_check`(없는 보이스7항목)와 `infest_check` 실패. 바닥·GroundBreak·BrawlLook 세 검사는 통과했다. `infest_check` 원인은 이번 작업에서 해결·분류하지 않았으며, 이를 전부 통과했다고 취급하지 않는다.

2026-10-06 사용자 지시: 최신 은색 벗겨짐 절반 PNG를 실제 게임에 적용하고 기존 바닥 톤이 크게 변하지 않았는지 확인.

원본 `../hearthstone-blocky-floor-20261006/floor_4m_half_silver.png`를 `assets/textures/handpaint_blue/floor_hearthstone.png`에 바이트 동일 복사했다. 1254² RGB, SHA256 `0b6b19b45baf60fe57cf732d6b5126dca3bb793abfb2f5e10ac71363e88ac0ea`. 고품질 BPTC·미프맵·이방성 필터·반복 설정으로 임포트했다. 그림을 새로 생성하거나 색을 후처리하지 않았다.

`blue_handpaint.gd`는 기본 바닥에 새 PNG와 `floor_direct`를 설정한다. `blue_handpaint_floor.gdshaderinc`는 월드 XZ/4m(방별 기존 offset)으로 직접 샘플링하며 이전 붓 혼합·절차적 줄눈·마모 분기는 비교용으로 남겼다. 두께 옆면도 기존 축 투영을 쓰고 원화의 색을 읽는다. `BrawlLook._floor_for`의 밝기 배율은 1.05이며, 조명·플레이어 조명 풀·벽 재질·모델·UV·판정은 유지했다. `GroundBreak`의 기존 복제 경로로 새 텍스처와 직접 투영을 상속하고 `lift` 강조도 유지한다.

`--bgfloor=previous`로 직전 바닥 PNG+붓 혼합+밝기0.82를 선택한다. `--bgpaint=old`는 이전부터 있던 최초 청보라 구현 전 비교 옵션이다. 원화는 네 판 구성의 4m 반복이며 맵의 모든 판이 고유한 그림은 아니다.

## 톤 확인

[실제 게임 비교](game_comparison.png)는 `main.tscn`의 같은 상태를 일시정지하여 바닥 재질만 전환했다. 카메라·플레이어·벽·조명 위치가 같다. 유체는 비교 촬영에서만 끄고, 별도 기본 설정 봇 실행에서는 유지했다. 보이는 바닥은 마젠타 셰이더 마스크로 선택하고 경계2px를 제외했다. 동영상 프레임 전체 평균으로 HUD/캐릭터까지 섞어 측정한 값이 아니다.

[tone_validation.json](tone_validation.json)과 [검사·비교 배치 스크립트](check_tone.py)에 원자료와 계산을 보관했다. 두 시점(물리 프레임120/480)의 바닥 평균 HSV 명도 차는 +0.199/+0.185%p, 채도 차는 +1.671/+1.688%p, sRGB 가중 명도 차는 +0.416/+0.332%였다. 조명을 제외한 실제 셰이더 ALBEDO 전체 4m 텍스처는 명도 +1.039%p·채도 +1.102%p다. 큰 색면·둥근 파임·은색 벗겨짐은 실제 화면에서 확인되며 기존 청보라 톤과 가깝다. 개별 위치의 명암은 새 원화에 따라 달라지고, 전체 반복 패턴은 더 눈에 띈다.

## 자료와 검증

- `before_effective.png` / `after_effective.png`: 실제 기본 바닥 셰이더 ALBEDO 렌더. 최초 before 촬영은 sandbox 환경 오류(로그 경로/셰이더 캐시/인증서) 3건 있으나 PNG 저장 성공. 이후 임포트·검증·촬영은 해당 접근이 허용된 실행을 사용한다.
- `game_0120/0480_before/after.png`: 동일 장면 전후. `*_floor_mask.png` / `*_floor_selection.png`: 측정용 가시 바닥 마스크.
- `capture_game_compare.gd`: 실제 main.tscn 1800 물리 프레임, 전후 캡처.
- `capture_run_compare.gd` / `run/`: 섹터 런 기본 설정 실제 검증.
- `before/`: 이 작업 직전 다섯 변경 파일 백업. 이후 다른 변경을 덮지 않도록 통째로 복구하지 말고 비교한다.
- 임포트·재질 검사·비교 옵션 검사·전체 회귀 검사·기본 설정 봇 로그 보존. 최종 결과는 `validation.json`과 AGENTS.md 참조.

고정 Godot4.7.2 표준 Forward+ 및 프로젝트 실행기 사용. 커밋·푸시 없음. 다른 작업자의 변경과 기존 시안 보존.
