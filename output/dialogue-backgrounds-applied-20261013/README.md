# 포트레이트 대화 배경 실제 적용

2026-10-13. 제작한 두 배경을 사용자의 적용 요청으로 실제 대화 장면에 연결했다.

## 실행

로비의 캐릭터 대화 또는 `launchers/scenes/dialogue_test.cmd`를 실행한다.

- F1 첫 출근 / F4 정비 동료 / F5 청소 파트너: 먹청색 정비 격납고.
- F2 격납고 브리핑 / F3 기능 시연: 적갈색 브리핑룸.
- R: 현재 대본 재시작. Esc: 로비 복귀.

## 연결과 리소스

실제 PNG는 `assets/ui/dialogue_backgrounds/blue_service_hangar.png`와 `dusty_brick_briefing_room.png`다. 시안 원본을 수정 없이 복사했다. lossless PNG 임포트·미프맵·선형 필터를 사용한다. `scripts/dialogue/hangar_backdrop.gd`에서 비율을 유지하며 중앙 크롭으로 화면을 채운다. 두 이미지를 preload해 내보내기에서도 참조를 유지한다. `DialogueView.play`에서 대본 파일 ID로 장소를 선택해 제목 변경에 따라 배경이 바뀌지 않는다. 파일 경로가 없는 임시 대본은 격납고를 기본으로 사용한다.

배경에 추가 색 보정이나 어두운 오버레이를 덧씌우지 않았다. 기존 포트레이트 리소스·대본·모션·깜빡임·인물 배치·대화창 동작은 그대로 사용한다.

## 실제 캡처

Godot 4.7.2 Forward+로 실제 `scenes/dialogue.tscn`을 실행해 저장했다. 이미지 생성으로 만든 합성 목업이 아니다. 캡처에서 눈이 감긴 순간을 피하기 위해 저장 직전에 눈을 뜬 프레임을 사용했다.

1. `01_blue_owner_solo.png`: 격납고 / 사장 단독.
2. `02_blue_pilot_reply.png`: 격납고 / 주인공 대사창 초상.
3. `03_red_briefing_pair.png`: 브리핑룸 / 사장과 정비사.
4. `04_red_briefing_three.png`: 브리핑룸 / 세 인물.
5. `05_red_briefing_choices.png`: 브리핑룸 / 선택지.
6. `06_blue_mechanic_pair.png`: 격납고 / 정비사 소개.
7. `07_blue_partner_pair.png`: 격납고 / 파트너 소개.
8. `08_red_partner_solo.png`: 브리핑룸 / 파트너 단독.
9. `09_red_solo_16x9.png`: 브리핑룸 / 1280×720.
10. `10_blue_solo_4x3.png`: 격납고 / 1024×768.

기본1~8장은1280×800이다. 캡처 재현: `powershell -File tools/godot.ps1 wait --fixed-fps 60 -s res://_capture/dialogue_background_show.gd`.

## 검증 기록

`render_validation.json`은 실제 F1~F5/R 입력·배경 선택·무대 전체 채움·추가 색 배수 없음·PNG 저장을 확인한다. 캡처10장 및57항목 모두 PASS. 세 화면 비율에서 실제 픽셀과 인물/대화창을 육안 확인했다.

전체 회귀는 `tools/run_tests.ps1`로 모든60종을 검사한다. 직렬 실행에서 먼저 완료한15종은 `all_tests_part1.log`, 남은45종은 독립 프로세스3그룹에서 각15종씩 검사한 `all_tests_group1.log`~`all_tests_group3.log`에 보관한다. `test_groups.json`에 전체 배분을 기록해 누락/중복을 확인한다. 각 프로세스의 사용자 데이터 폴더도 분리했다.

최종 결과: **전체60종 모두 PASS**, 검사 누락/중복0. 합친 결과는 `all_tests.log`, 전체 요약은 `validation.json`. 최종 임포트와 실제 캡처는 ERROR0/SCRIPT ERROR0. 5대본 bot 모두 완료하며 ERROR0/SCRIPT ERROR0. `hangar_briefing`은 종료 시 ObjectDB4개, `coworker_introduction`은12개 경고가 있어 해당 로그에 그대로 남겼다. 별도 캡처 하네스는 씬을 명시적으로 해제한 뒤 종료하며 경고/오류가 없다. 이번 배경 작업에서 종료 수명 전반을 수정하지 않았다.

`import.log`와 `import_self_contained_initial.log`는 첫 임포트의 사용자 AppData 쓰기 권한 오류를 포함한다. `.tools/godot/_sc_`로 고정 엔진의 편집기 데이터를 자체 폴더에 두고, 검증 프로세스의 APPDATA만 `.tools/godot-user-data/`로 지정해 런타임 로그/셰이더 캐시도 프로젝트 내부에 저장했다. 검사 뒤 환경 변수는 복원했다. `.tools/`는 기존 git 제외 대상이며 일반 게임 실행 설정은 변경하지 않는다. 최종 임포트/캡처 로그는 `import_verified.log`와 `capture.log`에 있다. 권한 오류로 중단한 최초 회귀는 `all_tests_initial_permissions.log`, 최초 캡처는 `capture_initial_permissions.log`에 보존했다.

자동 플레이는 PowerShell 외부 호출로 `--` 뒤 인자를 보존해 실행했다. `bot_initial_argument_separator.log`는 인자 구분자가 전달되지 않아 중단한 최초 실행 기록이다. 최종5대본 로그에는 모두 `DIALOGUE_DONE`이 있으며 `ERROR`/`SCRIPT ERROR`는 없다. 종료 때 ObjectDB 경고가 있는 대본은 별도 집계한다. 전체 회귀와5대본 bot 결과는 별도 로그 및 `validation.json`에 기록한다.

원본 시안/실제 프롬프트는 `output/dialogue-backgrounds-20261013/`에 보존했다. 기존 다른 세션의 BGM 파일과 AGENTS.md 변경은 보존했다. 커밋·푸시 없음.
