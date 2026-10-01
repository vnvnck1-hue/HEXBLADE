# 작업 인수인계 (모든 PC · 모든 에이전트 공통)

이 파일은 PC를 옮겨도 git 으로 따라오는 **유일한 인수인계 문서**다. 에이전트 메모리나 PC별 설정은 다른 PC로 넘어가지 않으므로,
다음 작업자가 알아야 할 규칙·상태는 여기에 적는다. 게임 내용·조작·파일 설명은 [README.md](README.md) 에 있다.

- 원격: https://github.com/vnvnck1-hue/HEXBLADE.git (기본 브랜치 `main`)
- 엔진: Godot (GDScript, Forward+). 모델·이펙트·효과음은 모두 코드로 생성한다.
- 사용자에게는 **항상 한국어로** 답한다.

## 1. Godot 버전 고정 — 반드시 지킬 것

- 버전은 루트의 [`godot-version.txt`](godot-version.txt) 한 곳에서만 정한다 (현재 `4.7.2-stable`, 표준 빌드, Mono 아님).
- Godot 은 **항상 `tools/godot.ps1` 을 거쳐** 실행한다. PC에 깔린 다른 Godot(4.6.3, Mono, winget 등)을 직접 부르지 않는다.
  버전마다 물리·임포트 결과가 달라 테스트 결과가 바뀐다 (예: 4.6.3 에서는 `terrain_jump_check` 가 실패한다).
- 실행기는 `<프로젝트>/.tools/godot/` (git 제외)에 고정 버전을 두고 쓴다. 없으면 같은 버전이 설치된 곳
  (`GODOT_HOME`, 옆 폴더의 `.tools/godot`, winget 표준 빌드)에서 복사하고, 그것도 없으면 공식 `godotengine/godot-builds`
  릴리스에서 내려받아 `SHA512-SUMS.txt` 로 검증한다. 버전이 다르면 실행하지 않고 멈춘다.

| 하고 싶은 것 | 명령 |
|---|---|
| 게임 실행 (로비) | `run_game.cmd` |
| 편집기 | `open_editor.cmd` |
| 새 PC 첫 준비 | `setup_godot.cmd` |
| 테스트 전체 | `run_tests.cmd` 또는 `powershell -File tools\run_tests.ps1 [이름...]` |
| 자동 플레이·캡처 등 임의 인자 | `powershell -File tools\godot.ps1 wait <Godot 인자...>` (`--path` 는 자동) |
| 씬 바로 실행 | `sector_run.cmd` · `boss_battle.cmd` · `forge_battle.cmd` · `mammoth_death_test.cmd` · `reference_mech_studio.cmd` |

**버전을 올릴 때**: `godot-version.txt` 와 `project.godot` 의 `config/features` 를 함께 바꾸고 → `setup_godot.cmd` →
`--headless --import` 로 다시 임포트 → `run_tests.cmd` 통과 확인 → 바뀐 `.import`/`.uid` 파일까지 한 커밋으로 올린다.

## 2. 새 PC에서 시작할 때

1. `git clone` (또는 `git pull`) 후 `git status` 로 브랜치 확인 — 아래 "현재 상태"의 브랜치 현황을 본다.
2. `setup_godot.cmd` → `run_tests.cmd` 가 모두 PASS 인지 확인.
3. `run_game.cmd` 로 로비가 뜨는지 확인.

## 3. git 규칙

- 줄바꿈은 [`.gitattributes`](.gitattributes) 가 정한다 (텍스트 LF, `.cmd`/`.ps1` CRLF). PC의 `core.autocrlf` 설정과 무관하게 같다.
- Godot 이 새로 만든 `.uid` / `.import` 파일은 원본(.gd, .png …)과 **같은 커밋**에 올린다. 빠뜨리면 다른 PC에서
  pull 할 때 "untracked working tree files would be overwritten" 로 막힌다.
- 커밋·푸시는 사용자가 요청할 때만 한다. 작업 브랜치는 `feature/<이름>`.
- 같은 폴더에서 다른 도구(Codex 등)가 동시에 작업할 수 있다. 내가 만들지 않은 미추적 파일(`output/…` 이미지 등)은 지우거나 커밋하지 말고 사용자에게 알린다.

## 4. 검증 습관

- 코드를 바꾸면 최소한 `run_tests.cmd` 와, 바꾼 씬의 자동 플레이(`--bot`)를 돌려 `ERROR` / `SCRIPT ERROR` 가 0인지 본다.
  예: `powershell -File tools\godot.ps1 wait --fixed-fps 60 res://scenes/main.tscn -- --bot --seed=1 --seconds=60`
- 로비는 실행 인자(`--bot`, `--capture=` 등)가 있으면 건너뛰고 섹터 런으로 간다 (`--test` 면 방 탐색 아레나).
- 그 밖의 검증 인자는 README "검증용 실행 인자" 참고.

## 5. 현재 상태 (작업을 마칠 때 갱신한다)

마지막 갱신: 2026-10-01

- `main`: 로비(메인 게임 = 헥스 섹터 런 / 연출 테스트 / 테스트 씬) 시작. 넓은 방·5웨이브·탄창 30발 반영.
- `feature/zzz-presentation` (`cef07d2`, ZZZ풍 연출: 붉은 위험 섬광·보스 등장·컷인): 원격에 있으나 **main 에 아직 병합 안 됨**.
- `feature/hex-sector-run`: main 에 병합 완료 (`d38a362`).
- 2026-10-01: Godot 4.7.2 고정 실행기 도입, 크롤러 도탄 생성 순서 오류(`!is_inside_tree()`) 수정. 4.7.2 기준 테스트 4종 PASS.
