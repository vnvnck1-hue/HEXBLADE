# 초반 캐릭터 대화 씬 적용

2026-10-11 · 승인 전신4명을 투명 상체 PNG7장으로 가공해 실제 대화 씬에 연결했다.

## 실행

- 로비 → **캐릭터 대화** 또는 `launchers/scenes/dialogue_test.cmd`: F1 첫 출근, F4 정비사 소개, F5 첫 청소 파트너 소개.
- `launchers/scenes/coworker_dialogue.cmd`: 사장과 정비사 대화.
- `launchers/scenes/partner_dialogue.cmd`: 새 현장 청소 파트너 소개.
- 진행: 클릭/Space/Enter, 선택지 숫자1~2. A 자동, L 기록, H UI 숨기기, R 재시작, Esc 로비.

## 에셋과 연결

`assets/portraits/opening_cast/`에 1254×1254 투명 PNG7장과 Godot `.import`7개를 저장했다. 사장 welcome/briefing/encouragement3종, 정비사 introduction/cheerful2종, 파트너 greeting1종, 파일럿 neutral1종이다. 사장 introduction은 welcome을 사용한다. 기존 사장/정비사 원화는 그대로 보존했다.

DialogueCast의 경로와 표정을 새 에셋으로 연결했다. 사장/정비사/파트너는 기존 단독 또는 좌우 무대 포트레이트를 쓰며, 주인공은 자신의 대사 때 하단 창의 작은 원화로 나타난다. 본문 시작 위치를 원화 오른쪽으로 옮기고, 다른 화자나 선택지에서는 작은 원화를 숨긴다. 새 파트너 대본은 기존 첫 출근과 동료 소개를 보존하는 별도 F5 소개다. 두 질문 분기가 소개 완료로 합류한다.

가공은 내장 image_gen을 사용했다. 승인된 각 전신은 편집 대상이고, 유일한 그림체 참고 입력은 최초 사용자 첨부4장의 영구 사본이다. 얼굴·머리색·의상·직무 소품을 유지하는 허리 위 구도로 재구성했으며, 단순 픽셀 크롭과 달리 자세/세부 재표현이 있다. 최종 이미지 원본은 추가 변형 없이 복사했고 투명 알파를 보존했다. 실제 편집 대상·참고4장·프롬프트·생성 원본 위치는 `prompts.json`, PNG 크기/알파 샘플/SHA256/임포트 확인은 `asset_validation.json`에 있다.

## 실제 화면

- `01_owner_welcome.png`: 사장 단독 첫 인사.
- `02_pilot_reply.png`: 첫 출근의 주인공 대사창 원화.
- `03_owner_briefing.png`: 사장 설명 포즈.
- `04_mechanic_introduction.png`: 사장과 새 정비사 상체 원화.
- `05_mechanic_cheerful.png`: 정비사 표정/손동작 전환.
- `06_partner_greeting.png`: 새 파트너 소개.
- `07_partner_pilot_reply.png`: 좌우 인물을 유지하는 파일럿 대사.
- `08_partner_choices.png`: 하단 선택지, 파일럿 원화 숨김.
- `09_owner_encouragement.png`: 격려 포즈 전환.

고정 Godot 4.7.2 Forward+ 실제 화면9장을 육안으로 확인했다. 헤어 실루엣/얼굴/손/소품이 읽히고, 대사/선택지/화자 이름/상단 조작과 겹치지 않는다. 프로그램 검증은 `tests/opening_cast_check.gd`와 기존 `dialogue_check.gd`/`coworker_dialogue_check.gd`, 전체 회귀 및 3씬 bot 실행이다. 최종 결과는 `validation.json`에 기록한다. 첫 제한 환경 실행은 사용자 로그/인증서 저장소/편집기 설정 접근 오류가 있었고, 접근이 가능한 검증 실행 로그를 별도로 보존한다.

이 대화의 플래그는 대화 진행기 내부 시안 상태이며 본편 출격/정산/기체 양도 로직을 바꾸지 않는다. 커밋·푸시는 하지 않았다.

최종 검증: 전체54종 PASS, SCRIPT ERROR0. 전체 실행에서 기존 `whirl_props_check`에 메시 생성 ERROR1이 출력됐지만 단독 재검사는 PASS/ERROR0이었다. 대화3씬은 headless bot으로 실제 분기와 끝 대사까지 정상 완료했고 ERROR0이었다. Forward+ 최종 캡처9장도 ERROR0이다. 재현 시 PowerShell에서 배열 인자로 `@('wait','--headless','--fixed-fps','60','res://scenes/partner_dialogue.tscn','--','--bot','--seed=7','--seconds=180')`를 만든 뒤 `tools/godot.ps1`에 전달하면 사용자 인자 구분자를 보존한다. 초기 Forward+ 자동 진행은 첫 출근만 완료됐고 다음 씬은 중단했으므로, 최종 자동 진행 근거는 `bot_verified_*.log`만 사용한다.
