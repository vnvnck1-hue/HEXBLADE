# 로비 업그레이드 실제 적용 — 2026-10-11

10월 7일 준비된 리소스의 A 구성(완성 배경 + 실제 메뉴)을 실제 게임에 적용했다. 추가 이미지 생성이나 모델 교체는 없다. 원본 키트는 `../lobby-upgrade-kit-20261007/`에 보존한다.

- 게임 코드: `scripts/lobby.gd`, `scripts/presentation/lobby_art.gd` 및 `.uid`.
- 게임 리소스: `assets/ui/lobby/`의 PNG 1장·SVG 10종, 각각 `.import`. 배경 밉맵/선형 필터, 워드마크 벡터, 시스템 CJK 글꼴과 합성 기울임.
- 네 메뉴: 섹터 런(`Run.new_run`), MAMMOTH B 연출 테스트, 현행 전체 테스트 씬 목록, 종료. 신규 테스트 씬도 현재 목록에서 읽는다.
- 로비 전용 1920×1080 캔버스를 비율 유지 축소하고 중앙 정렬한다. 프로젝트 해상도 설정은 변경하지 않는다. 배경은 정지 상태이며 Tween이나 중복 캐릭터 레이어는 없다.
- 테스트 목록: 긴 제목/설명 줄바꿈, 세로 스크롤, ↑↓·Tab·Enter·마우스, 뒤 메뉴 입력 차단, Esc/닫기 후 테스트 메뉴 포커스 복구, 재개방 선택 유지. 축소 배율의 정수 스크롤 반올림까지 보정한다.
- 기존 자동 플레이 로비 건너뛰기, `--test` 아레나 선택, 게임 Esc 복귀, F11, 진입 중복 방지를 유지한다.
- 기본 메뉴의 `Button.text` 제목도 보존한다. 접근성과 기존 연출 검사/도구는 이 속성을 읽고, 실제 표시는 별도 Label로 정확히 배치한다.
- 연출 테스트의 Esc 처리만 좁게 수정했다. 씬을 교체하기 전에 입력을 소비하고 반환해, 트리에서 제거된 노드의 뷰포트 접근 오류를 없앴다.

## 실제 캡처

`lobby_1280x800.png`, `lobby_1280x720.png`, `lobby_1920x1080.png`, `lobby_1920x800.png`: 실제 Forward+ 로비 전체 화면. `focus_death_test.png`: 선택색. `drawer_top.png`, `drawer_long_title.png`, `drawer_bottom.png`, `drawer_closed.png`: 목록과 포커스 복구. `training_entry.png`, `death_test_entry.png`, `sector_run_entry.png`: 실제 버튼으로 진입한 화면.

`_capture/lobby_upgrade_show.gd`로 캡처/실제 입력 재현. `HEX_LOBBY_VISUAL=1` 환경변수는 캡처만 한 뒤 종료한다. 기본 실행은 F11, 허수아비 3회 진입·Esc 복귀/노드 수, 연출 테스트와 섹터 런 진입·복귀, 새 런 초기화, 시간/물리 복구, 종료 버튼 Enter까지 수행한다. 생성 프레임 덤프는 없다.

## 검증 기록

최종: 전체 57종 PASS(최초 53종 + 수정 후 4종 재검사), 로비 전용 73항목 PASS, 실제 Forward+ 조작 20항목 PASS, 실제 캡처 13장/4비율 육안 확인. 최종 임포트·조작/렌더·섹터/아레나 자동 bypass·일반 로비 실행 모두 ERROR0/SCRIPT ERROR0. 최초 전체 피격 검사 빈 메시 ERROR1은 단독 재검사에서 재현되지 않았다. 중간 실패를 포함한 전체 로그는 보존한다.

- `tests/lobby_upgrade_check.gd`/`.uid`: 실제 엔진 키보드/포인터 입력, 4비율, 긴 목록, 선택 복원, 10회 열기/닫기, 전체 씬 경로 연결.
- `interaction-validation.json`: 실제 화면 조작/진입/복귀 항목별 결과. `interaction-final.log`와 `visual-final.log`: 렌더와 입력 로그.
- `bypass-run.log`, `bypass-test.log`: 로비를 통해 자동 플레이로 섹터 런/아레나 연결.
- `all-tests.log`: 전체 회귀. 작업 중 글꼴 변환 생성자의 잘못된 6개 실수 표기로 발생한 3종 파싱 오류는 수정 후 `regression-recheck.log`에서 재검증한다. 최초 피격 검사에서 나온 빈 메시 오류는 `hit-react-recheck.log`로 재확인한다.
- `lobby-compatibility-recheck.log`: Button.text 보완 후 로비 입력 73항목과 기존 MAMMOTH 연출 검사(30/60/144fps·10회 재설정·진입/복귀) 모두 PASS. 처음의 버튼 식별 assertion 중단도 전체 로그에 보존한다.
- `import-final.log`: 정상 환경 고정 Godot 임포트. 초기 제한 환경 로그의 인증서/사용자 설정 오류 및 중간 실패 로그도 보존한다.
- `validation.json`: 최종 검증 결과, 리소스 원본 복사 해시, 캡처/코드 해시.

모든 Godot 실행은 `tools/godot.ps1` 경유 4.7.2-stable 표준 빌드다. 커밋·푸시는 하지 않았다. 다른 작업의 변경과 미추적 파일은 보존했다.
