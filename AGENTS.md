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
| Blender (모델링) | `setup_blender.cmd` · `blender_live.cmd` · `powershell -File tools\blender.ps1 model models\src\<이름>.py` — [docs/blender-modeling.md](docs/blender-modeling.md) |
| 씬 바로 실행 | `training.cmd`(허수아비 전투 테스트) · `dialogue_test.cmd`(캐릭터 대화) · `gimmick_test.cmd`(필드 기믹) · `sector_run.cmd` · `boss_battle.cmd` · `forge_battle.cmd` · `abyss_battle.cmd` · `spider_boss.cmd`(거미 보스) · `mammoth_death_test.cmd` · `reference_mech_studio.cmd` |

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
- 캡처 **프레임 덤프**(수십~수백 장 연속 PNG)는 git 에 올리지 않는다. 최종 이미지·시트·GIF·프롬프트만 올리고, 프레임 폴더는 `.gitignore` 에 추가한다 (`_capture/*/`, `output/spider-boss-20261001/*/` 처럼).
- 커밋·푸시는 사용자가 요청할 때만 한다. 작업 브랜치는 `feature/<이름>`.
- 같은 폴더에서 다른 도구(Codex 등)가 동시에 작업할 수 있다. 내가 만들지 않은 미추적 파일(`output/…` 이미지 등)은 지우거나 커밋하지 말고 사용자에게 알린다.

## 4. 검증 습관

- 코드를 바꾸면 최소한 `run_tests.cmd` 와, 바꾼 씬의 자동 플레이(`--bot`)를 돌려 `ERROR` / `SCRIPT ERROR` 가 0인지 본다.
  예: `powershell -File tools\godot.ps1 wait --fixed-fps 60 res://scenes/main.tscn -- --bot --seed=1 --seconds=60`
- 로비는 실행 인자(`--bot`, `--capture=` 등)가 있으면 건너뛰고 섹터 런으로 간다 (`--test` 면 방 탐색 아레나).
- 그 밖의 검증 인자는 README "검증용 실행 인자" 참고.
- 누수 확인: `_capture/leak_probe.gd` 가 한 씬을 여러 번 다시 불러오며 객체·노드·고아 노드 수와 정적 캐시 크기를 찍는다. 로드마다 같은 시점 값이 늘면 무언가 남는 것이다.
  예: `powershell -File tools\godot.ps1 wait --headless --fixed-fps 60 -s res://_capture/leak_probe.gd -- --probe=res://scenes/boss.tscn --frames=1200 --loads=5 --bot --godmode --capture= --seconds=9999` (`--keys` 를 붙이면 캐시 키도 찍는다)
- 정적 캐시(`Pal.lit`, `Build.box/bevel_mesh`, `BossTank._mesh`, `FX._spark_pm` …)는 색·크기 값이 키라서 **무작위 실수를 그대로 넘기면 씬을 불러올 때마다 끝없이 커진다**. 무작위 크기·색은 `snappedf` 등으로 몇 단계로 묶어서 넘긴다.

## 5. 현재 상태 (작업을 마칠 때 갱신한다)

마지막 갱신: 2026-10-02

- 2026-10-02 (미커밋): **벌레형 괴생명체 적 2종 — 개미 병정 `BugAnt` · 공벌레 `BugPill`** (Claude 작업) — [docs/bug-enemies.md](docs/bug-enemies.md). 사용자 원화 기반.
  모델: `models/src/bug_ant.py`·`bug_pillbug.py` → `assets/models/bug_ant.glb`(1.1만 삼각형)·`bug_pillbug.glb`(1.3만). 모든 파츠 회전 0 · 원점 = 관절(`hb.rebase`), 더듬이 3마디.
  공벌레 등딱지 8장은 "다 말린 공"에서 45° 조각으로 만든 뒤 펼친 자세로 되돌려 둔 것 → 관절당 45° 굽히면 틈 없는 공.
  애니메이션은 Godot 절차(`scripts/bugs/ant_rig.gd`·`pill_rig.gd`, 판정 없음), 적은 `bug_enemy.gd`(공통: 땅에서 기어 나옴·체액·죽음 3종)·`bug_ant.gd`·`bug_pill.gd`, 효과음 `bug_sound.gd`(Sfx 캐시에 이름만 추가).
  시험장 `scenes/bugs.tscn` · `bug_test.cmd` · 로비 항목(4 키 애니메이션 전시), 캡처 `_capture/bug_show.gd` → `output/bugs-20261002/`(`.gdignore`), 테스트 `tests/bug_enemies_check.gd`(37항목).
  **본편 스폰 큐에는 넣지 않았다** — 같은 시간 다른 작업자가 같은 요청으로 `InsectEnemy`(`insect_ant/insect_grub.glb`, `scripts/insects/`, `scenes/insects.tscn`)를 만들어 `main.gd` 스폰에 넣는 중이었다. 둘 중 무엇을 쓸지는 사용자 결정. 기존 코드 변경은 `lobby.gd` 목록 한 줄뿐.

- 2026-10-02 (미커밋, Codex): **벌레형 괴생명체 2종 게임 적용** — [docs/insect-enemies.md](docs/insect-enemies.md). Blender 원본 `models/src/insect_{ant,grub}.py` + 공통 `tools/blender/insect.py` → `assets/models/insect_{ant,grub}.glb`(13,464 / 20,616 삼각형), 편집 `.blend`·4방향 시트는 `output/models/insect_{ant,grub}/`. 붉은 개미(긴 3관절 더듬이·6다리·턱·뾰족한 배), 아이보리 굼벵이(6몸마디·기문·짧은 다리·3관절 더듬이). **애니메이션은 Godot** `scripts/insects/insect_motion.gd`: idle/walk/windup/attack/recover/hurt/stagger/death/emerge 9종, 발 지지점 월드 고정 + 2관절 IK, 개미 교대 삼각 지지·굼벵이 시차 수축·더듬이 지연. GLB/.blend에는 베이크 클립 없음. `InsectEnemy`는 Enemy 피격·체력바·락온·처치 계약, 자체 추적·물기 돌진·공격 취소·근접 패링·생물형 쓰러짐. Main 소환 큐 개미 12%·굼벵이 10%(이월, 드론 몫 사용), 방 탐색/섹터 런 연결. 재사용 씬 `scenes/enemies/insect_{ant,grub}.tscn`, 시험장 `insect_battle.cmd`·`scenes/insects.tscn`·로비 **벌레형 괴생명체**(1 재배치, 2 스튜디오, 3 다음 동작, 4 무리). `tests/insect_check.gd`, 전체 회귀 21종 PASS, 미리보기/검증 `output/insects-20261002/`(.gdignore), 프레임 폴더 git 제외. 동시 생성된 다른 도구의 `bug_ant`/`bug_pillbug`·`scripts/bugs/`는 별도 결과로 보존; 커밋·푸시 없음.

- 2026-10-02 (미커밋): **필드 기믹 4종** — [docs/gimmicks.md](docs/gimmicks.md), 코드 `scripts/gimmicks/`, 시험장 `scenes/gimmicks.tscn` · `gimmick_test.cmd` · 로비 "필드 기믹". 방 탐색·섹터 런의 **전투방**에 자동 배치(`Main._ready` 의 `Gimmicks.attach`, 시드 고정 시 같은 배치), 보스·허수아비 씬에는 없음.
  ① 연기 구역 `SmokeZone`: 안에서는 `Player.hidden`(2m 안에 붙은 적에게는 들킴) → 드론·요격기·포탑·크롤러가 새 공격을 시작하지 않음, 대신 `Player.no_attack`(이동·대시·부스터·점프만). 기체는 빗금 홀로그램(`GimmickHolo`, material_override 를 기억했다 되돌림 — 피격 섬광의 material_overlay 와 안 겹침), 빠져나오면 0.8초 동안 연기 가닥이 몸을 따라 끌려 나옴. ② 레일 `RailBelt`: `Player.carry`(5m/s)를 `move_and_slide` 직전에 더했다 뺌, 적도 실려 감. ③ 가스통 `GasCanister`: `Enemy` 상속이라 모든 무기 판정이 그대로 닿지만 `Enemy.prop` 이라 처치 수·방 진행·소환 상한·봇 표적·미니맵 적 점에서 빠짐. 반경 3.6m 플레이어 1피해+밀침 · 적 거리별 · 가스통 연쇄, 자리에 `BlastScorch`(데칼 + 불꽃, 연출 전용). ④ 수리키트 해치 `RepairHatch`: 전투 중 가끔 솟음, 레버 옆에서 **F(`interact`) 연타 16번** → 열림 → 키트 체력 +2. 돌리는 동안 `Player.rooted`+`no_attack`, 손잡이 앞으로 끌어 세우고 `Player.gimmick_pose` 로 과장된 크랭크 자세(대시로 탈출, 피격 시 손 놓음). F 는 레버 범위 밖에서는 그대로 검.
  기존 코드 변경은 플래그 훅뿐: `player.gd`(플래그 · 입력 차단 · carry · 자세 호출) · `enemy/striker/turret/crawler.gd`(`not player.hidden`) · `main.gd`(interact 키 · attach · prop 제외) · `hud.gd`(미니맵) · `lobby.gd`(목록). 주의: `Enemy` 에 `_explode` 가 이미 있어 가스통 폭발은 `_detonate`. 테스트 `tests/gimmicks_check.gd`(28항목), 캡처 `output/gimmicks-20261002/`(`.gdignore`, `frames/` 는 올리지 말 것). main 90초 bot(seed 2·5) · run 5개 방 · training · gimmicks bot ERROR 0.
  같은 시간 다른 작업자가 `hud_presets.gd`·`player.gd`·`main.gd`(E 키 돌진 스킬)를 수정 중이었다 — 돌진 스킬도 `tech_ok` 를 거쳐 연기 속·레버 중에 막힌다.

- 2026-10-02 (미커밋): **E = 돌진 스킬** (검 키에서 제외, 검 키보드 단축은 F 만). E 를 누르는 동안 바닥에 푸른 민트(`BladeTech.SKILL_COL`) 메카닉 조준 인디케이터(돌진 경로 폭 1.1m × 길이 5.2m, 벽 앞에서 잘림. ImmediateMesh 로 매 틱 그림: 펼침 애니메이션 · 점선 레일+0.5m 눈금 · 모서리 꺾쇠 · 순차 점등 쉐브론 · 스캔 띠 · 도착점 회전 4분할 링+십자선 · 거리 Label3D, 벽에 막히면 주황 LIMIT. 모든 면의 투명도는 `_fade` 로 발밑 4% → 끝 100%, f^4 라 끝에서 가파르게 진해짐)가 마우스 방향으로 뜨고, 떼면 기 모으기 돌진의 1단계(`SKILL_K` 0)를 `SKILL_REACH` 1.3배 거리로(`_launch(dir, reach)`, 시간도 같은 배율이라 속도 동일) 낸다. 쿨타임 `SKILL_CD` 3초, 이 돌진으로 처치하면 남은 쿨타임을 `SKILL_KILL_CD` 1.5초로 줄인다("RESET" 팝업). 코드는 `blade_tech.gd` ③ 절(`skill_feed`, 기존 `_release` 를 `_launch(dir)` 로 분리해 공용), `player.gd` 는 입력 한 줄 + `tech.skill_feed` 호출, 입력 액션 `rush_skill`(main.gd), 봇은 `"skill"` 키. HUD 는 STRIKER 프리셋에만 E 버튼(쿨다운 부채꼴·남은 초) 추가 — 다른 프리셋은 미표시. 테스트 `tests/rush_skill_check.gd`, 캡처 `_capture/rush_skill_show.gd` → `output/rush-skill-20261002/`(`.gdignore`).

- 2026-10-02 (미커밋): 패링 공격이 올 때 플레이어 둘레에 조여들던 노란 타이밍 링·목표 링·방향 쐐기(`parry.gd` cue) 삭제, 대시 시작·끝·2단 대시 때 바닥 충격파 원(`player.gd` `FX.shockwave`) 삭제. 패링 판정·별빛 알림, 대시 불꽃·기류·발밑 쿨다운 링(`dodge_ring`)은 그대로. 전체 테스트 21종 PASS, main 60초 bot ERROR 0(패링 2회 성공).

- 2026-10-02 (미커밋): **새 메카 플레이어 게임 적용** — 모든 전투 씬의 플레이어가 기본으로 `mech_volume_preserved.glb`. 어댑터 `scripts/mech_player.gd`(`MechPlayer.build(body)`)가 GLB 외피를 기존 `Build.robot` 관절 계약(j) 피벗 아래로 옮긴다(부위 배율 1, 메시 변형 없음, 전체 이동 SHIFT z-0.25 만). **`--player=robot`** 이면 예전 보라 로봇.
  좌우: 기존 동작은 왼손 총·오른손 검 기준이라 상체·하체를 각각 거울(X 반전) 노드 안에 두고 메시는 다시 반전 → 기존 코드 값 그대로, 화면엔 좌우 대칭 동작(총 +X·검 -X). 조준 yaw 는 거울 밖 `Legs`/`Upper` 에 쓰여 방향 불변. 그래서 `j.blade`·`j.muzzle`·`j.jet_*` 의 전역 basis 는 행렬식이 음수다(방향 벡터·to_global 은 정상, 회전 분해(get_euler/quaternion)는 쓰지 말 것).
  총 팔 기본 자세는 코드 계산(`GUN_LIFT` 어깨 들기 + 팔꿈치로 총신 축 `GUN_AXIS` 를 정면 수평) — 시각 총구 높이 약 0.75m, 판정 탄도는 기존대로 0.95m(규칙 미변경, 약 0.2m 차). 상·하체 독립 회전, `j.gun` 명시 피벗(`PlayerMotion.rig` 가 위치로 부품을 고르지 않음), 발 기준점은 `pt_foot` 0.12 위(러시 불꽃 오프셋 중복 방지), 발목 `MechPlayer.settle` 이 허벅지·무릎을 되받아 발바닥 수평, 비균일 squash 대신 상체 상하 눌림. 충돌 캡슐(0.42/1.4)은 그대로.
  광선검은 `pt_grip`(펼친 손가락)에 코드 생성 검 부착 — 쥐는 손 모양은 미가공. 테스트 `tests/mech_player_check.gd`, 확인 캡처 `_capture/mech_player_show.gd [--pose=slash|spin|overhead|walk|crouch]` → `output/mech-player-20261002/`(`.gdignore`). training/main/boss/forge/abyss/spider bot ERROR 0, 전체 테스트 PASS. 하스스톤 칠(K 키)은 코드 단색 파츠만 바꾸므로 메카 텍스처 외피는 그대로(검·불꽃만 칠해짐) — `painted_look_check` 는 `MechPlayer._choice = "robot"` 으로 예전 로봇을 검사한다.

- 2026-10-02: **Claude용 새 메카 플레이어 적용 인수인계** [docs/mech-player-integration-handoff.md](docs/mech-player-integration-handoff.md) 작성. 적용 대상은 `mech_volume_preserved.glb`이며 이전 `tripo_mecha_proto`와 구분. 사용자 부피 보존 원칙, 실제 관절/부착점, 현재 `Build.robot`·`Player`·`PlayerMotion`·검술 연결 지점, 좌우 반전 관계·상하체 이중 회전·고정 높이·GunSpin 재부모화·탄도 높이·부스터/발 FX·비균일 squash 주의점과 검증 명령을 정리했다. 문서 작성만 수행했으며 게임 코드·모델 변경 및 새 메카 본편 적용은 없음.

- 2026-10-02 (미커밋): **새 메카 원본 부피 보존 관절 분리**. 사용자 명시 원칙: **관절 간 일부 겹침을 허용하며 간섭 해소 때문에 장갑·팔다리의 부피를 줄이거나 작은 대체 형상으로 바꾸지 말 것.** 이후 메카 가공에도 유지한다. 새 원본 `models/source/mech_user/original.glb`(Downloads의 `mech suit 3d model.glb`와 동일 SHA256, `.gdignore`) → `models/src/mech_volume_preserved.py` → `assets/models/mech_volume_preserved.glb`. 높은 등 장식 1/2/14와 바닥 액체 8/15 제외, 남긴 17개 원본 파츠의 외부 표면을 전부 보존하여 외피 27개로 분리. 양팔 어깨/상완/팔꿈치/손목(총 포함), 양다리 고관절/무릎/발목, 골반/허리/중앙 얼굴 계층. 외피 축소·간섭 회피용 재성형 없음, UV/노멀 보간 절단과 내부 마감 및 무릎/발목 연결부 4개만 추가. 총 13,429 삼각형, 전체 균일 배율 2.35. 원본별 유실 표면적 0, 실제 GLB 재임포트 원본 정점 최대 오차 약 2.41e-7m, 4방향 512px 실루엣 원본영역 유지율 100%(측면 연결부 3픽셀 추가). 검증 도구 `tools/blender/mech_volume_{review,verify}.py`, 결과·근거 `output/models/mech_volume_preserved/`. `mech_volume_pose.cmd`로 `pose_trial.blend` 확인: 1 중립 / 40 총 조준 / 80 팔 들기 / 120 웅크림 / 160 중립, 영상 `pose_trial.mp4`. 원본의 열린 경계 때문에 일부 절단면 내부 마감이 남으며, 기존 게임 애니메이션·플레이어 교체는 미실시. 이전 `tripo_mecha_proto`의 작아진 장갑을 이 모델에 이식하지 말 것. 전체 회귀 17종 PASS; 최종 GLB 별도 재임포트/모델 검사 및 기존 training bot 결과는 결과 폴더 `validation.json` 참조. 다른 작업의 파일 변경은 보존하고 커밋·푸시하지 않음.

- 2026-10-02: [우주 청소업체 오프닝과 첫 의뢰](docs/우주_청소업체_오프닝과_첫_의뢰.md) 추가, 대안 본문 0.3에서 연결. 사용자가 제시한 골목·희미한 간판·수리 중인 여성 사장에 첫 대화, 기체 대여와 양도 약속, 창고 청소 의뢰 카드, 첫 전투와 짧은 귀환 연결을 제안했다. 대사·3~4분 도입 목표·누적 정산 매출 기반 기체 양도 진척은 미확정 초안. 기존 구출 서사와 게임 코드·테스트 대본은 변경하지 않았다.

- 2026-10-02: 우주 출장 청소업체 대안 문서 0.2에 **빚을 갚으러 온 무일푼 주인공 → 히로인의 낡은 정비기 대여 → 몇 차례 의뢰와 목표 수입 달성 → 기체 양도 → 업체 운영 위임과 여성 직원 영입**을 추가. 히로인의 정비·업체 소유 역할, 신뢰를 쌓는 귀환 장면, 초반 의뢰 3건과 대사, 상환·사업 자금 구분은 보완 제안으로 표시했다. 기존 구출 서사는 보존하고 게임 코드·다른 작업 파일은 변경하지 않았다.

- 2026-10-02 (미커밋): **패링 효과음 후보 3종 (게임 미적용)** — 참고음 RoR2 Railgunner headshot_03(git 제외 폴더)의 짜임(예비 타격 → 본 타격·저음 쿵 → 약 0.3초에 1.77kHz '팅' + 배수가 아닌 지속음 26개 금속 울림)을 측정해 노이즈·사인으로 합성. `tools/sfx/parry_synth.py`(모드 목록 `MODES`)·`parry_fit.py`(대역 분포 + 꼬리 1/12옥타브 오차)·`parry_fit_params.json`·`parry_candidates.py`(손 보정 포함) → `output/parry-sound-candidates-20261002/`(`.gdignore`, `index.html`). A_close(참고음 시간 구조) · B_instant(판정 즉시 팅) · C_crystal(B 바탕 +9% 높고 긴 울림). **1차는 "휘익·철판 충돌·튕기는 메아리가 안 느껴진다"로 반려** → 2차 `parry2_synth.py`(사건 단위: 도플러 휘익 2k→330Hz, 충돌 클릭 + 10.5ms 빗살 금속 떨림, 철판 모드, 도탄 핑 2.2k→3.1k→1.77k + 0.13초 간격 메아리 + 튕긴 뒤 1~3kHz 떨림 + 0.25초 뒤 두 번째 핑)·`parry2_fit.py`·`parry2_fit_params.json`·`parry2_candidates.py` → `…/v2/`: A_close · B_snappy(휘익 45ms) · C_echo. **2차는 "길다, 철판 무게감(중저음) 부족"** → 3차 `parry3_candidates.py`(버전당 1개, 0.45~0.75초, `parry2_synth` 에 몸통 모드 `body`/`BODY`·`pl_hi`·`dur` 추가, 충돌 노이즈 125~400Hz 를 낮춰 몸통 음이 드러나게) → `…/v3/`: S1_short · S2_heavy · S3_anvil · S4_gong. **3차는 "젠존제 패링스럽게, 버전끼리 다 똑같이 들린다"** → 4차 `tools/sfx/parry4_zzz.py`(젠레스 존 제로 소리는 설치돼 있으나 Wwise 이벤트 이름 목록이 없어 찾지 못함 — 실제 소리 미참고, 액션 게임 패링 연출 재료로 직접 설계) → `…/v4/`: Z1_clash(검격 챙, 고역 금속 배음) · Z2_slam(서브 낙하·철판 몸통 쾅) · Z3_timestop(차오름→칭→음이 내려가는 슬로모 꼬리) · Z4_spark(전기 지글거림·딩·끊기는 반복). 버전 간 분포 차이 3차 85 → 4차 361. **이후 사용자가 1차 B_instant 를 기본으로 "더 명쾌하게" 지시** → 5차 `tools/sfx/parry5_clear.py`(측정 도구 `clarity.py`: 첫 정점·시작 날카로움·200~800Hz 탁함·팅 선명도). 늦게 오던 쿵(저음 노이즈가 200~800Hz 로 샘, `parry_synth` 에 `th_g` 추가)이 정점 지연·탁함의 주원인 → 쿵을 충돌과 동시에·필터 가파르게, 본 타격 0.07~0.11초에 끊음, 시작 클릭 → `…/v5/`: C1_clean · C2_crisp · C3_bell (정점 47→11ms, 탁함 -10→-19~-22dB, 팅 22→27~40dB). 사용자가 고르면 GunSound 처럼 GDScript 로 옮겨 `Sfx` 의 `"parry"`(`parry.gd:140`)를 교체할 예정.

- 2026-10-02 (미커밋): **플레이어 기관총 발사음 교체** — 사용자가 고른 후보 A_close. 새 모듈 `scripts/gun_sound.gd`(`GunSound`, 노이즈·사인만, 샘플 없음)가 변형 8개(0.38초, 44.1kHz)를 만들고, `Sfx` 의 `"shoot"` 은 이제 **스트림 배열**이라 `Sfx.play` 가 재생마다 하나를 고른다(배열이면 `pick_random`). `_wav(samples, rate)` 에 속도 인자 추가, 재생기 풀 16→24(한 발이 길어 연사 중 5개쯤 겹침). `player.gd` 는 음량만 -8→-12dB(일반 사격)·-4→-8dB(콤보 공중 사격). 합성은 첫 로드 때 한 번 약 0.5초.
  설계: RoR2 MUL-T 기관총(참고용으로만 추출, git 제외 `output/ror2-gun-sounds/`)의 1/3옥타브×5~10ms 에너지 분포에 합성 수치를 자동 탐색으로 맞췄다(`tools/sfx/mg_fit.py`·`mg_synth.py`, 기준 수치 `mg_fit_params.json`, 후보 생성 `mg_candidates.py`, 반려된 1차 `mg_candidates_v1.py`). 파이썬판은 FFT 대역 분할, GDScript 판은 같은 폭 바이쿼드라 약간 다르다(분포 차 7, 원본↔A_close 12). 후보 미리듣기 `output/mg-sound-candidates-20261002/`(`.gdignore`, v2 가 2차). **원작 효과음 파일은 게임·git 에 넣지 않는다.** 확인 `_capture/gun_sound_dump.gd`(wav 저장), 테스트 `tests/gun_sound_check.gd`(전체 16종 PASS), main 60초 bot ERROR 0. 실제 귀로 듣는 음량 균형 확인은 사용자 몫.

- 2026-10-02: **사용자 추가 가공 메카 읽기 전용 검토**. 새 파일 `C:/Users/Loadcomplete/Downloads/mech suit 3d model.glb`(이전 `mecha`와 다른 이름, SHA256 `a3f3197a004c23281769d53fac7fd82988a8bd33ef65d10c0c2920d5af93d259`)은 `tripo_part_0~21` 독립 메시 22개·14,716 삼각형·재질 22개·텍스처 66개(파츠별 basecolor/normal/metallic-roughness), 스킨/애니메이션 없음. 모든 파츠 피벗은 원점, 모두 RootNode 직계 자식. 등 장식(주로 1/2/14), 총(4), 얼굴/콕핏 형상(9), 바닥 액체(8/15)가 분리되어 있으나 다리 주요 메시(3/5)는 발까지, 손 쪽 팔(6)은 여러 관절 구간이 연결되어 추가 분리 필요. 높은 장식/바닥 액체는 새 파일에 여전히 존재. 새 외형을 기준으로 필요한 관절부만 가공하는 것을 권장했으며 자동으로 기존 시제품을 덮어쓰지 않음. 렌더·22파츠 도감·측정·보고서 `output/models/mech-user-review-20261002/`; 원본과 게임 에셋/코드 변경, 포즈 시험 및 Godot 적용 없음. 검사 스크립트는 `.tools/mech_user_review/`.

- 2026-10-02 (미커밋): **Tripo 메카 2차 — 관절 주변 부분 재구성**. `models/src/tripo_mecha_proto.py`에서 골반 아래 잔재와 상완·전완·양쪽 허벅지·정강이 장갑을 단순한 닫힌 메시로 교체(팔다리 장갑은 쿼드 측면+팔각 캡), 어깨·무릎 덮개와 관절 간격 조정. 몸통·손·발·고정 총은 원본 텍스처 유지. 1차 21,082 → 14,782 삼각형. `tools/blender/tripo_pose_review.py`는 0.11m 웅크림 깊이를 유지한 채 IK를 매 프레임 저장하고 저장한 `.blend`를 다시 열어 160프레임 검사: 지정된 몸통/가동 장갑과 서로 다른 관절의 외부 장갑 쌍 표면 교차 프레임 0, 발 기준점 높이 최대 오차 약 5.8e-8m. 내부 베어링·프레임 및 같은 관절 부품은 검사 제외이며 임의 모션/연속 충돌 보증 아님. `output/models/tripo_mecha_proto/pose_trial.mp4`·`pose_review.png`·`pose_trial.blend` 갱신, 실행은 `tripo_mecha_pose.cmd`. 새 장갑은 단색의 각진 작업용 형태로 디테일·UV/텍스처, 고정 총 팔 분리, 무기 그립, 머리·허리 및 본편 모션 연결이 남음. Godot 임포트 ERROR 0, 전체 15종 PASS, 기존 training 20초 bot ERROR 0(새 모델 전투 검증은 아님). 사용자 Downloads 원본은 변경하지 않음.

- 2026-10-02: [우주 출장 청소업체 내러티브 대안](docs/우주_출장_청소업체_내러티브.md) 추가. 우주여행 보편화 이후 방치 시설의 외계생물·종족·증식물 문제, 청소용 기체로 의뢰 수행과 보수 획득, 기체와 여성 소유자의 영입·전투·대화·개인 스토리를 기록했다. 계약 방식과 실제 조종자 등은 미확정이며 보완 제안과 원안을 구분했다. 기존 신소재 구출 내러티브 두 문서는 수정하지 않았고 대안을 통합·채택하지 않았다. README에 링크 추가. 문서만 변경하며 다른 작업의 코드 수정·미추적 파일 보존, 커밋·푸시 없음.

- 2026-10-02 (미커밋): **Tripo 메카 관절 가공 1차 시제품** `models/src/tripo_mecha_proto.py` → `assets/models/tripo_mecha_proto.glb`(21,082 삼각형, 최고 높이 약 1.687m). 사용자 요청대로 높은 쌍두 장식·해골·지지봉·상단 배선 삭제, 상부 절단면·낮은 덮개 마감, 배낭 짧은 배기구 3개 재제작. 바닥 액체 및 낮은 후면 호스 일부 제거. 손 있는 팔의 어깨/상완/팔꿈치/전완/손목과 양다리 고관절/무릎/발목을 분리하고 내부 프레임·관절·무릎 덮개 추가. 반대 총 팔은 몸통 고정, 머리·허리 독립 리그와 본편 연결은 미구현.
  원본은 `models/source/tripo_mecha/original.glb`로 복사 보존(`.gdignore`, Downloads 원본과 SHA256 동일). Godot가 추출한 베이스컬러 JPG와 `.import`, 새 테스트 `.uid`도 원본과 함께 보존할 것. `tools/blender/tripo_pose_review.py`가 `output/models/tripo_mecha_proto/pose_trial.blend` 및 비교 시트·측정 JSON 생성. **`tripo_mecha_pose.cmd`**로 고정 Blender 라이브 열기, 프레임 **1 중립 / 40 사격 / 80 베기 / 120 웅크리기**, 임시 총·검은 그립 방향 확인용. 저장 후 다시 열어 키 포즈 일치 검증. 키 포즈 사이 자동 보간의 접지는 미보장.
  1차 결과: 키 포즈 양발 기준점 바닥 유지(실제 발 최저점 0~2.3mm), 사격·베기에서 손/전완과 몸통 표면 교차 0. **웅크리기에서 골반·다리 장갑 간섭 및 전완/몸통 교차 후보가 남음**. 다음은 골반 아래·무릎 뒤 접힘 공간, 어깨 경계, 손 그립의 부분 리토폴로지. 완성 게임 모델로 취급하지 말 것. 상세 `output/models/tripo_mecha_proto/NOTES.txt`. 고정 Godot 임포트 및 새 `tripo_model_check` 포함 **전체 15종 PASS**, 기존 training 씬 20초 `--bot` ERROR/SCRIPT ERROR 0(기존 종료 ObjectDB 경고 있음). 게임 코드와 기존 수정·미추적 `_capture/leak_probe.gd`는 보존, 커밋·푸시 없음.

- 2026-10-02: **Tripo 메카 플레이어 후보 읽기 전용 검토**. 원본 `C:/Users/Loadcomplete/Downloads/mecha suit 3d model.glb`(SHA256 `8cff56cfbd2994d404a76fac9c06a8d63d5ab5d322a54f92e8ebbbac317be501`)을 고정 Blender로 검사. 메시·재질 각 1개, 삼각형 20,550개, GLB 정점 24,639개, 4K 베이스컬러 1장, 스킨·애니메이션 없음. 중복 위치 정점을 임시 메모리에서 합쳐 검사하면 정점 10,558개·경계 에지 536개이며 몸 대부분은 연결되어 있어 자동 loose-part 분리만으로 관절 분리 불가. 제안은 외형 보존 + 관절·손·호스 부분 재구성, 바닥 액체 제거, UV/재질 보정 후 기존 `Build.robot` 관절 계약과 총구·검·부스터 연결점을 맞추는 것. 높은 등 장식 때문에 전체 높이 기준 스케일은 몸을 너무 작게 만들 수 있음. 검토 이미지·측정 JSON: `output/models/tripo-mecha-review-20261002/`, 검사 스크립트는 git 제외 `.tools/mecha_inspect/`. 원본·게임 코드 변경 및 게임 적용 없음. 기존 다른 작업의 수정 파일과 미추적 `_capture/leak_probe.gd` 보존.

- 2026-10-02 (미커밋): **전수조사 — 누수·최적화·리팩터링**. 4개 영역(코어·연출/HUD·보스전·심연/거미/대화) 정적 감사 + 씬별 자동 플레이 + `_capture/leak_probe.gd` 재로딩 측정. 고아 노드 0, 재로딩 후 노드 수 일정 확인.
  누수: 무작위 크기·색이 키로 들어가 정적 캐시가 끝없이 커지던 곳(`BossTank` 격파 파편·그을음, 거미 공구함·화면, 심연 뼈, 벽 착탄 파편 색) 양자화, 캐시 크기가 재로딩에도 그대로임을 측정으로 확인. 꺼진 포탑 해치 조명 숨김, 보스바·맘모스 죽음 연출이 끝난 뒤에도 매 프레임 돌던 것 정지, 심연이 바꾼 전역 볼류메트릭 안개 해상도 복원, `inst` 정적 참조 `_exit_tree` 에서 비움(Main·Debris·ImpactFrame·ToonOutline·Sfx·GustFX).
  버그: 맘모스 레이저 피격 들림이 X/Z 위치를 누적시켜 모델이 판정에서 최대 3m 미끄러지던 것(테스트 추가), 플레이어가 패턴 도중 죽으면 용광로 브레스 빔·카메라 흔들림·어두운 조명이 영구히 남던 것, 맘모스 미사일 경고가 페이즈 전환·격파 연출 중에도 착탄하던 것, 용광로 웅덩이가 격파 후에도 피해를 주던 것, 칼로 죽인 참회자의 경고 원·돌진선이 남던 것, 심연 페이즈가 드문 경우 끝나지 않던 것(소환 실패 시 목표 수 차감), 충전 해제가 풀의 다른 소리를 끄던 것, M 음소거가 씬 전환에 풀리던 것, `Parry.inst` null 접근.
  최적화: `FX.sparks`·`GunFX._spray`·`RushFX` 파티클 머티리얼·그라디언트 캐시(호출마다 텍스처를 GPU 로 올리던 것), `Sfx` 합성은 첫 로드 한 번만, `FX.setup` 셰이더 재컴파일 방지, 총구 조명 노드 풀, 지속 레이저 조각 노드 풀, 미사일 연기 고속 구간 간격 확대, 잔상·피격 섬광 메시 목록 캐시(`FX.mesh_parts`), 총알·적 분리의 그룹 조회 프레임 캐시(`Enemy.live`), 체력바·HUD·탄약 아이콘은 바뀔 때만 갱신, 화로 조명·거대 레이저 조명 그림자 끔, 심연 소품 고해상도 구 → 공용 저폴리 구, 파편 그림자 끔, 실행 인자 매 프레임 조회 제거(`Main.cmd_args`) 등.
  리팩터링: 죽은 코드 정리(BossEnemy `DYING`·`_update_dying`·`_final_blast`, `ForgeBoss._hurt` → `_hurt_player`, `cine_active`·`carry`·`P_BULLET` 등), 심연 호위 배치가 주석 의도대로 동작하게. 전체 테스트 14종 PASS, 전 씬 자동 플레이 ERROR 0.
  남은 일(위험 대비 효과가 작아 보류): 보스전 연기·불 노드 풀링, 보스 공통 기반 클래스·아레나 Main 공통화, 종료 시 `ObjectDB leaked` 경고(정적 캐시가 들고 있는 리소스라 실행 중 누수 아님).

- 2026-10-02: **이 PC의 Blender 직접 접근 검증 완료**. 프로젝트 `.tools/blender/`의 고정 버전 `5.2.2 LTS`를 `tools/blender.ps1 setup`으로 확인하고, `blender_live.cmd`와 같은 `live` 명령으로 예제 포탑 `.blend`를 열었다. `send`로 열린 창 안에서 Python 실행·임시 메시 생성/좌표 수정·선택 GLB 내보내기·`snap()` 화면 캡처 성공. 파일 다시 열기 후에도 라이브 연결 유지 확인. 임시 메시를 제거하고 예제 파일을 다시 열었으며 모델 원본·게임 코드 변경 없음. 검사 스크립트·GLB·캡처는 git 제외인 `.tools/blender_live/`에만 둔다. 창을 닫으면 연결이 끝나므로 다음 작업은 `blender_live.cmd [파일.blend]`로 시작한다. 별도 MCP 애드온 없이 기존 파일 큐 브리지로 제어한다.

- 2026-10-01 (미커밋): **캐릭터 대화 시스템 테스트 씬** `scenes/dialogue.tscn` · `dialogue_test.cmd` · 로비 테스트 씬 목록. 리서치·문법·구조 [docs/dialogue.md](docs/dialogue.md). 코드는 모두 `scripts/dialogue/`, 대본은 `data/dialogue/*.dlg`(자체 텍스트 문법), 그림은 `output/character-dialogue-20261001/` 시안을 그대로 씀(`DialogueCast.DIR`).
  타자기(문장부호 자동 멈춤 · `{p}` · `{fast}`) · 화자 강조 · 표정 교차 전환 · 감정 반동 · 인물별 글자음 · 선택지(꼬리표 · 조건부 · ✓) · 자동 A · 읽은 대사 넘기기 S · Ctrl 빨리 넘기기 · Tab 선택지까지 건너뛰고 요약 · 기록 L · 숨기기 H · 글자 크기/속도 · 움직임 줄이기 M. 본편 연결은 아직.
  기존 코드 변경은 `lobby.gd` 목록 한 줄뿐. 테스트 `tests/dialogue_check.gd`, 캡처 `_capture/dialogue_show.gd` → `output/dialogue-20261001/`(`.gdignore`).
  주의: 코드로 만든 Control 은 `set_anchors_and_offsets_preset` 을 써야 한다(`set_anchors_preset` 은 크기 0 을 오프셋으로 남김). 인물 z_index 가 UI 를 덮지 않게 UI 층은 z 50 이상. PowerShell 에서 `& tools\godot.ps1 ... -- --bot` 으로 부르면 `--` 가 먹혀 인자가 안 넘어간다 — `powershell -File` 로 부를 것.

- 2026-10-01 (미커밋): 루트 `.cmd` 실행기 13개가 `powershell` 을 전체 경로 `"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"` 로 부른다. 시스템 PATH 에서 Windows 기본 경로가 빠진 PC(이 PC가 그랬다)에서도 더블클릭으로 실행된다. 새 `.cmd` 를 만들 때도 같은 식으로 쓴다. Blender 쪽 `blender_live.cmd`·`setup_blender.cmd` 는 다른 작업 중인 파일이라 아직 그대로다.

- 2026-10-01 (미커밋): **거미 보스 Blender 모델 — 원화 재현판** `models/src/spider_boss.py` → `assets/models/spider_boss.glb`(약 5.2만 삼각형), 비교 `output/models/spider_boss/compare.png`, 3/4 렌더 `preview.png`.
  원화 3면도를 미터 단위로 재서 처음부터 다시 만듦(리그 치수 맞춤판은 폐기). 실루엣 IoU 정면 0.65→0.85 · 측면 0.45→0.87 (`--compare` 수동 18회 + `tools/blender/sweep.py` 좌표 하강 탐색 2회 약 150빌드, 최적값은 스크립트 기본값에 반영). 평면 0.45 는 원화 자체 모순(평면은 네 다리를 모두 앞으로 접고 개틀링이 2m 더 김) 때문이라 정면·측면을 기준으로 함.
  원화를 따라 팔은 2개(오른쪽 +X 용접기 · 왼쪽 집게+원형 톱), 눈 2개, 머리+가슴 한 덩어리, 높은 뒤 몸통 · 공구 칸 · 태블릿. 시점끼리 모순인 곳(개틀링 높이 · 용접기 자세 · 무릎 높이 · 톱날 방향)은 사이값, 정강이 판과 고관절 원판은 정면·측면 양쪽에서 보이게 대각선으로 돌림. 원화에 없는 속은 메카닉 관례(프레임 위 장갑판 · 볼트 원판 관절 · 유압 · 지렛대 · 판 이음 선)로 채움.
  계층 `body > head > gatling`, `body > abdomen > tablet`, `body > leg_<k>_coxa > _femur > _tibia > _foot`, `body > arm_<welder|saw>_upper > _fore > _tool (> arm_saw_disc)`, 부착점 `pt_*`. **게임 리그(`spider_rig.gd`, 눈 3 · 팔 4 · 다른 치수)에는 연결하지 않았다.**
  비교 도구: `models/ref/spider_boss.json`, `tools/blender/{compare,ref_masks,ref_grid,zoom_compare,overlay_zoom,sweep}.py`(compare 는 실루엣 IoU + 색 계열 일치율 `colour`, 탐색은 `HB_OVERRIDE` JSON 으로 치수를 바꿔 빌드). 주의: 실루엣만 보는 탐색은 앞 무릎을 머리 앞으로 옮기는 식으로 점수를 속이므로 결과는 눈으로 확인할 것, hb 에 `deform`·`prism(cuts=)`·`box(taper_axis=)` 추가. 덤으로 테스트 `blender_models_check` 를 새 계층에 맞춤(전체 14종 PASS).

- 2026-10-01 (미커밋): **Blender 모델링 파이프라인** — [docs/blender-modeling.md](docs/blender-modeling.md). Blender 도 Godot 처럼 버전 고정: `blender-version.txt`(5.2.2 LTS), `tools/blender.ps1` 이 `.tools/blender/` 에 공식 포터블 zip 을 받아 SHA256 검증. 
  모델은 `models/src/<이름>.py`(도우미 `tools/blender/hb.py`) → `tools\blender.ps1 model ...`(`tools/blender/build.py`) 이 `assets/models/<이름>.glb` + `output/models/<이름>/`(미리보기 시트·stats·.blend) 생성. 정면 = Blender +Y = Godot -Z, `part=` 로 파츠 합치기, `after_join()` 에서 피벗·계층, 부착점은 `pt_` 접두어(`@` 는 Godot 노드 이름 불가).
  라이브 모드 `blender_live.cmd` + `tools\blender.ps1 send code.py` (`tools/blender/live.py`, `snap()` 뷰포트 캡처). `output/models/.gdignore` 필수(없으면 Godot 이 .blend 임포트를 시도해 오류). 예제 `models/src/sample_turret.py`, 테스트 `tests/blender_models_check.gd`(전체 13종 PASS).
  덤으로 `tools/run_tests.ps1` 이름 지정 실행이 항상 0개였던 버그 수정(`Where-Object` 안의 `$args`).

- 2026-10-01 (미커밋): **거미 보스 SHIPWRIGHT 전용 테스트 씬** `scenes/spider.tscn` · `spider_boss.cmd` · 로비 테스트 씬 목록. 코드는 모두 `scripts/spider/`, 설계 [docs/spider-boss.md](docs/spider-boss.md). 본편 이식은 사용자가 요청할 때.
  3면도 기반 기계 거미(다리 넷 3관절 IK · 공구 팔 넷 · 개틀링 · 태블릿 · 새끼 해치). 발은 `SpiderStage.project()` 로 바닥·벽·기둥 어디든 붙고, 경로(`route`)는 바닥↔벽↔기둥↔구멍을 L 자 모서리로 잇는다.
  전장 54×46m · 48m 벽 · 바닥 굴 4 · 배관 구멍 4 · 190m 기둥 7(카메라 곁·플레이어 가림 부분은 점묘로 지움). 패턴 8종(거미줄 포격/그물 · 매복 돌격 · 기둥 사이 배회 · 산란 · 천장 낙하 · 기관포 · 질주), 2페이즈 50%.
  기존 코드 변경은 `player.gd` 의 `slow_mul`(감속 배율 훅, 3줄)과 `lobby.gd` 목록 한 줄뿐. 테스트 `tests/spider_check.gd` 추가(전체 PASS), 캡처 `_capture/spider_show.gd` → `output/spider-boss-20261001/`.
  주의: `Enemy._warn` 이 이미 있어 보스의 예고 원은 `_warn_at`. 셰이더 문자열은 `shader_type` 줄이 맨 앞이어야 해서 노이즈 함수는 `_shader_n()` 으로 붙인다. 캡처 1회가 시작 직후 메모리 할당 실패로 죽었으나 재시도 후 재현되지 않음.

- 2026-10-01: 궁극기 콘티를 **형태·명암 중심 그레이박스 8컷**으로 추가 제작. `output/ultimate-storyboard-20261001/ultimate-storyboard-graybox.png`, 생성·수정 프롬프트 `graybox-prompts.txt`. 기획서 대표 이미지를 새 버전으로 바꾸고 컬러 원본 링크를 보존했다. 회색 블록 플레이어·검은 원기둥 일반 적·큰 상자 최강 적, 가는 미사일 궤적·굵은 흰 레이저로 구분. 07의 직선은 배분 설명용이며 실제 궤적·발수 확정안이 아니다. 게임 코드 변경 없음.

- 2026-10-01: **신규 궁극기 8컷 콘티와 기본 기획** — [공중 포화와 동시 레이저](docs/궁극기_공중_포화와_동시_레이저.md), 이미지 `output/ultimate-storyboard-20261001/ultimate-storyboard.png`, 내장 image_gen 최종 프롬프트 `prompts.txt`. 순간 도약 → 미사일 균등 분배 → 착탄 전 급속 응축 → 미사일 타격과 최강 적 레이저 동시 발사. 시작부터 후방 초광각, 극적인 조명과 단계별 반동. 01~06은 시간 흐름, 07~08은 다수/단일 적 비교. 시간·강한 적 선정 기준·착탄 동기화 방식은 제안이며 게임 미구현. 게임 코드는 변경하지 않았고 기존 수정·미추적 파일을 보존했다.

- 2026-10-01 (미커밋): **흐르는 공간 연출 (추격 보스전)** — 새 모듈 `scripts/presentation/world_flow.gd` (`WorldFlow`). `boss_main.gd`·`lab_mammoth_b.gd` 가 `WorldFlow.attach(world, stage, 30)` 하면 도로 속도를 읽는다. 다른 씬은 attach 안 해서 동작이 그대로다.
  ① 운반 노드 `WorldFlow.holder(a)`: 연출 노드를 그 아래에 넣으면 v = 도로속도·(1−e^(−a·나이)) 로 흐른다 (AIR 2.2 = 연기·폭발·불꽃, GROUND 80 = 바닥 흔적). Tween 이 `position` 을 움직여도 같이 흐르지만 **`global_position` 을 Tween 하는 연출은 흐르지 않으니** 넣으려면 로컬 `position` Tween 으로 바꿔야 한다 (missile `_billow` 가 그 예).
  ② `FX._add(n, pos, flow)`: puffs·sparks(흐를 때 local_coords)·flash·smoke·ring·shockwave·fire_explosion 은 AIR, 레이저 바닥 그을음은 GROUND. 레이저 총구 쪽 ring/flash/shockwave 와 `FX.muzzle` 은 0(기체에 붙음). 폭발 그을음은 `StylizedExplosion._scorch_z` 로 도로 속도만큼 앞서 간다. Distortion.burst 도 AIR.
  ③ 자체 물리: GunFX 탄피·파편, Debris 조각은 바닥 마찰을 도로 기준(`WorldFlow.road_v()`)으로 걸고, 멈추면 도로와 함께 흐르며, `WorldFlow.gone()`(z>30)이면 지운다. 흐르는 씬에서는 z 방향 `is_blocked` 튕김을 끈다(추격전 경계 z>18 에 튕겨 돌아오지 않게). ToonGunFX 착탄 연기·왕관 불꽃·파편은 `"flow"` 옵션.
  테스트 `tests/world_flow_check.gd`(전체 11종 PASS), 캡처 `_capture/world_flow_show.gd` → `output/world-flow-20261001/`.

- 2026-10-01: 거미형 기계 보스 모델링 참고 3면도 `output/spider-boss-20261001/spider-boss-three-views.png` 제작(정면·우측면·평면). 사용자 레퍼런스의 푸른 장갑·청록색 눈 2개·보행 다리 4개·전면 공구 팔을 반영, 내장 image_gen 프롬프트는 같은 폴더 `prompts.txt`에 보관. 생성형 콘셉트 참고도이며 뷰 간 치수·투영이 완전히 일치하는 CAD 도면은 아니다. 실제 모델링에서 피벗·치수를 확정해야 한다. 게임 코드는 변경하지 않았고 기존 수정·미추적 파일은 보존했다.

- 2026-10-01 (미커밋): **MAMMOTH 죽음 연출 B안 본선 적용 · 레이저 피격 들림 · 보스전 기본총 가시성**.
  ① 로비 연출 테스트 씬의 강화판 감독 `scripts/lab_mammoth_b/mammoth_b_director.gd`(5.7초 궤도 파손과 전복)를 더미·BossEnemy 공용으로 일반화(visual·model·tank·shadow 만 씀, `pick_side`)하고 `BossEnemy._begin_dying` 에서 시작한다. 판정상 격파는 즉시(점수·드롭), 연출이 끝나면 `defeated` → `BossMain._win` 즉시. 연출 중 플레이어 자동 비행·무적, 궁극기·지속 레이저 취소(`boss_main.gd _process/bot_input`). 예전 연쇄 폭발 `_update_dying`/`_final_blast` 는 남아 있지만 호출 안 함. 주의: `Enemy` 에 이미 `death` 멤버가 있어 감독 변수는 `death_fx`.
  ② 강력 레이저(충전·지속) 피격 시 맞은 쪽이 들리고 반대 모서리가 축이 되어 떨림 → 내려앉을 때 모서리 착지 불꽃 (`scripts/presentation/mammoth_hit_lift.gd`, `BossEnemy._laser_lift` 가 플레이어 위치·빔 방향으로 접촉점을 계산 — player.gd 는 그대로).
  ③ 보스전 기본총이 안 보이던 원인 2가지: 착탄 판정점(반지름 3.3, 높이 ~1m)이 차체(반폭 3.45·반길이 3.6) 안에 묻혀 깊이 테스트로 가려졌고, 추격전 카메라(22m·FOV 50)가 일반(17m·FOV 36)보다 화면상 0.54배로 작게 보였다. → `BossEnemy.fx_point`(연출 위치만 겉면으로, bullet.gd 가 `fx_point` 있으면 사용) + `ToonGunFX.view_k`(보스전 1.6, `BossMain.VIEW_K`).
  테스트 `tests/mammoth_ingame_check.gd`(전체 10종 PASS), 캡처 `_capture/mammoth_ingame_show.gd`·`_capture/boss_gun_show.gd` → `output/mammoth-ingame-20261001/`. 200초 자동 플레이에서 2페이즈→격파→연출→WIN, ERROR 0.

- 2026-10-01: [카툰 캐릭터와 대화 포트레이트](output/character-dialogue-20261001/README.md) 제작. 세나·노아·에이린 전신 3장, 미라 포함 4명×표정 3종의 투명 PNG 12장, 임시 대화 UI 1장으로 신규 이미지 총 16장. `preview.html`로 전체 비교, 프롬프트와 `asset-check.json` 보관. 내러티브 수집 기획서의 단독 1장 검토 범위를 확장 내용으로 갱신했다. 게임 코드는 변경하지 않았고 다른 작업의 수정·미추적 파일을 유지했다.

- 2026-10-01 (미커밋): **광선검 특수기** `scripts/blade_tech.gd` (`BladeTech`, Player 소유). 좌클릭 길게 → 기 모으기 돌진(최대면 드릴 회오리 TEMPEST · 잔상 줄기 · 지연 연기), 콤보 중 좌+우 동시 → 회피 레이저(에너지 소모 없음, 링크 유지 `SwordCombo.suspend()`). 마우스 좌클릭 검은 이제 BladeTech 가 탭/홀드를 가려서 낸다(대기 중 첫 클릭만 최대 0.2초 기다림, 콤보 중 클릭은 즉시). `player.gd` 에는 입력·이동·자세·부스터 훅만. 테스트 `tests/blade_tech_check.gd`, 확인 `training.tscn -- --bot --techshow`. 기 모으기 중 카메라 계단식 줌아웃(`CameraRig.charge_zoom`/`set_charge_zoom`), TEMPEST 폭·원형 참격·칼 길이·연기 절반, 나선 잔상(리본 수명 0.5초).
- 2026-10-01 (미커밋): **F11 전체화면 멈춤 수정** — 게임 코드 문제가 아니라 Bandicam 이 깔아 둔 Vulkan 암시적 레이어(`bdcamvk64.dll`)가 창 모드 전환 때 스왑체인 재생성에 실패해(VkResult -2) 화면이 멈추고 이어서 크래시했다. `tools/godot.ps1` 이 Godot 실행 전에 `VK_LAYER_bandicam_helper_DEBUG_1=1`(레이어 자체의 비활성화 스위치)을 설정한다. 그래서 Godot 을 실행기 없이 직접 띄우면 이 PC에서는 여전히 멈출 수 있다.

- 2026-10-01: 구출 수집 기획서 0.2에 **정제 신소재를 플레이로 획득해 성인 구출 캐릭터의 체형·헤어를 변경**하는 사용자 아이디어 추가. 보스 제한시간·고난도 적·어려운 업적·숨은 보상이 획득 경로이며, 비용·수치·재선택 방식은 미확정. 내러티브 문서 0.3에 **헬테이커풍 카툰 캐릭터 아트** 방향 반영(진지한 서사 톤은 유지). 시각 검토는 미라 단독 1장으로 축소, 이전 반실사 UI 시안은 아트 기준 아님. 게임 코드는 변경하지 않는다.

- 2026-10-01: [사운드와 BGM 제작 리서치](docs/sound-bgm-research.md) 추가. Moebius FM의 공식 설명을 토대로 Synthwave·Retrowave·Chillwave와 주변 장르를 조사하고, AI 음악 도구 8종의 현행 기능·가격·게임 이용 조건을 비교했다. Suno·Stable Audio 시안 비교 후 DAW 편집을 제안하며, Udio 다운로드 중단과 Eleven Music의 Studio Games 제한·회사 라이선스 조건을 기록했다. 원음 직접 청취·BPM 측정·도구별 생성 실험은 하지 않았고 Moebius FM의 음악 제작 도구도 미확정이다. 문서만 변경했으며 기존 수정·미추적 파일은 보존했다.

- 2026-10-01: [파일럿 구출 분기와 캐릭터 수집](docs/구출_분기와_캐릭터_수집_기획서.md) 추가, 기존 내러티브 문서 0.2로 갱신. 여성 파일럿의 동조·신체 변이, 명부 기반 목표 설정, 선행 경로, 제한된 보유와 구출·처치 선택, 후반 재수집을 기록했다. 선행 클리어와 구조 전용 경로의 구분·초기 2자리·6인 예시 명부·사망 후 복원 방식은 제안이며 미확정. 게임 구현은 없고 동시 작업 코드와 미추적 파일은 유지했다.

- 2026-10-01 (미커밋): **핸드 페인팅 질감 — 하스스톤 식(HEARTH) 게임 연결** — [docs/hearthstone-look.md](docs/hearthstone-look.md)(관찰·적용·기술 스택), 일반 리서치 [docs/hand-painted-look.md](docs/hand-painted-look.md). 모듈 `scripts/presentation/painted_look.gd`: 파츠 메시 AABB 를 인스턴스 파라미터로 넘겨 파츠마다 위 밝고 아래 어두운 그라디언트·윗모서리 밝은 선/아랫모서리 짙은 선·리벳·따뜻한 그림자를 칠한다. 맵 벽은 표면 덮어쓰기(월드 모드) + 지형 전용 모서리 패스(러프니스 0.95 표식), 바닥은 바탕색만 따뜻하게, 주광·환경광 보정. **K 키 / `--look=hearth`, 기본 꺼짐**, 상태는 static 이라 씬 재로딩에도 유지. `main.gd` 는 `PaintedLook.attach(self, env, sun)` 한 줄 + K 키 분기만 추가. 나중에 생기는 적·파편은 `node_added` 로 변환. 비교 씬 `painted_look.cmd`(1~8 키), 캡처 `output/painted-look-20261001/`(`.gdignore`), 테스트 `tests/painted_look_check.gd`(전체 8종 PASS). 주의: 색 연산은 감마 공간(sqrt)에서 해야 과포화가 안 난다. P 키는 abyss·맘모스 랩이 이미 써서 K 로 했다.

- 2026-10-01 (미커밋): 좌상단 플레이어 상태 HUD 를 **프리셋 5종**으로 정리 — H / Shift+H 로 실시간 전환, `--hud=이름`, 씬을 다시 불러도 유지(`HudPresets.current` static). STRIKER(기본·ZZZ식) · CORNERS(하단 분할) · COCKPIT(디제틱 호) · TACTICAL(압축 패널) · LEGACY(기존). 그리기는 새 모듈 `scripts/presentation/hud_presets.gd`, `hud.gd` 는 기존 세로 나열을 LEGACY 일 때만 보이고 에너지·미사일 아이콘 줄을 프리셋 자리로 옮긴다. 리서치·설계 [docs/hud-presets.md](docs/hud-presets.md), 테스트 `tests/hud_preset_check.gd` 추가, `ammo_check` 의 "아이콘 줄 항상 보임" 검사는 프리셋별 규칙으로 바꿈(전체 7종 PASS). **사용자가 하나를 고르면** 나머지를 정리할 예정.
- 2026-10-01 (미커밋): **전투 테스트 · 허수아비** 씬 추가 (`scenes/training.tscn`, `training.cmd`, 로비 테스트 씬 목록 2번째 — 1번째는 `--test` 가 쓰므로 그대로 둠). 코드는 `scripts/training/` (`TrainingMain` extends Main, `TrainingDummy` extends Enemy). 숫자 키 1~8 설정, 피해 숫자·DPS 표시. 기존 스크립트는 `lobby.gd` 목록 한 줄만 바꿨다.
- 2026-10-01 (미커밋): **LAYER 01 · 심연 성소** 테스트 씬 추가 (`scenes/abyss.tscn`, `abyss_battle.cmd`, 로비 테스트 씬 목록). KILL KNIGHT 리서치·스테이지 분석·설계는 [docs/abyss-layer.md](docs/abyss-layer.md).
  코드는 모두 `scripts/abyss/` 에 따로 있고 기존 스크립트는 `lobby.gd` 목록 한 줄만 바꿨다. 페이즈마다 판이 솟고 가라앉는 15×15 부유 아레나, 적 3종(허스크·애가꽃·갑각 참회자), 함정 2종, 중간보스 HALO WARDEN(2페이즈), 체액 데칼·초승달 탄·후처리 셰이더. 테스트 `tests/abyss_check.gd` 추가(전체 6종 PASS).
  주의: 값 노이즈를 문턱으로 자르면 바닥에 격자 계단 무늬가 생겨 석판 셰이더는 그래디언트 노이즈(`gnoise`/`gfbm`)를 쓴다. 같은 높이의 판끼리 그림자를 드리우면 그림자 여드름이 생겨 기둥만 그림자를 드리운다. 데칼은 석판(2번 층)에만 투영한다.
- 2026-10-01: [내러티브 콘셉트와 초반 플로우](docs/내러티브_콘셉트와_초반_플로우.md) 작성. 로봇과 유기체가 결합한 적, 남성 주인공·여성 캐릭터 방향을 기록하고 캐주얼·엉뚱함 조건을 해제했다. 첫 출격·MAMMOTH 변이·귀환 검사는 제안이며 게임 미구현. README에 문서 링크 추가. 이 작업은 문서만 변경했고 동시 작업 중인 코드·미추적 파일은 유지했다.

- 2026-10-01 (미커밋): 적 처치 시 부스터 게이지 회복 — 1킬당 `Player.BOOST_KILL`(0.12, 약 0.24초 비행분), 비행 중에도 찬다. `Main.on_enemy_killed` → `Player.gain_boost()` 라서 모든 전투 씬에 적용.

- `main`: 로비(메인 게임 = 헥스 섹터 런 / 연출 테스트 / 테스트 씬) 시작. 넓은 방·5웨이브·탄창 30발 반영.
- `feature/zzz-presentation` (ZZZ풍 연출: 붉은 위험 섬광·컷인·격파 쇼타임): 2026-10-01 main 에 병합. MAMMOTH 는 격파 연출 감독(`mammoth_b_director.gd`)이 시간·카메라를 쥐므로 쇼타임 대신 `MAMMOTH DOWN` 컷인만 쓴다 (VULCAN 은 쇼타임 그대로).
- `feature/hex-sector-run`: main 에 병합 후 원격 브랜치 삭제.
- 보스전 검증 인자 `--seconds=` 는 `--capture=` 가 있어야 종료한다 (없으면 끝나지 않음). 캡처 폴더는 미리 만들어 둔다.
- 2026-10-01: Godot 4.7.2 고정 실행기 도입, 크롤러 도탄 생성 순서 오류(`!is_inside_tree()`) 수정. 4.7.2 기준 테스트 4종 PASS.
- 2026-10-01 (미커밋): 적 피격 섬광(`scripts/presentation/hit_spark.gd`)을 기본총 예광탄과 같은 납작한 방추(SPINDLE) 조합으로 교체 — 외곽선 없음, ToonGunFX 로 그린다. 기본총 착탄(`GunFX.impact_body`)은 그대로. 예전 시트(`assets/fx/hit_spark_sheet.png`·`tools/make_hit_spark_sheet.py`)는 이제 쓰이지 않는다. 근접 캡처: `_capture/hit_spark_show.gd`.
- 2026-10-01 (미커밋): 플레이어 액션 애니메이션 ZZZ풍 개편. 광선검 5단 → **6단 콤보**(삼연참 · 반동 사격(공중제비+공중 4연사) · 순간이동 난무 · 5바퀴 회전 선풍 · 2연 올려베기 · 낙월+지연 참격), cut 확장 키 `hits`/`blink`/`gun`/`spin`/`dashin`/`after` (`scripts/sword_combo.gd`).
  재장전·사격·충전·레이저 반동·지속 레이저·미사일 락온/일제 사격 동작은 새 모듈 `scripts/presentation/player_motion.gd`(기본 자세 위에 오프셋을 pre/post 로 덧입힘, 사격 팔 총 부분을 `GunSpin` 축으로 옮김). 회피 첫 2프레임 사라짐.
  확인 씬 `--actshow` 추가(`main.gd`). 설계표: `docs/sword-combo.md`. 캡처 폴더 경로에 공백이 있으면 `godot.ps1` 이 인자를 쪼개므로 공백 없는 경로를 쓴다.
- 2026-10-01 (미커밋): 궁극기 미사일 분배 변경 — 락온한 일반 적에게는 1발씩만, 남는 미사일은 보유량에 남김. 보스(`Enemy.is_boss`: 맘모스·VULCAN·VULCAN 팔)를 락온하면 남은 미사일을 모두 보스에게 (`Player.plan_ult`). 락온 없으면 예전처럼 전부 바닥에 흩뿌림. 미사일 비행은 사출→제동(멈칫)→제곱 가속 돌진 3단으로 바꾸고 명중 시간 약 1.58배 빨라짐(7m 평균 0.611→0.386초), 연기는 푸른색. 테스트 `tests/missile_check.gd` 추가.
- 2026-10-01 (미커밋): 궁극기 2차 — 락온 시야 전환 즉시 줌아웃(`CameraRig.ULT_K_IN`, 단단한 줌 스프링; 줌·FOV·반동 스프링은 프레임 끊김에 발산하지 않게 1/240초로 쪼개 적분). 자석 조준(`Player.MAGNET_PX`: 마우스 근처 아직 락온 안 한 적에게 조준점이 달라붙음, `ult_raw`=실제 마우스). 락온 표식 `scripts/presentation/lock_marker.gd`(발밑 고리·머리 위 화살표·빛기둥) + HUD 괄호 강화·LOCK 순번. R 을 떼면 준비동작 `ULT_WINDUP`(0.42초 실제 시간, `PlayerMotion.windup`) 후 발사, 슬로우모션·줌아웃은 준비동작 끝에 함께 풀림 (`Player.ult_busy()/ult_winding()`). 미사일 1.8배 크기·3겹 푸른 연기, 7m 명중 평균 0.386→0.300초, 연사 간격 0.05→0.035초.
- 2026-10-01 (미커밋): 궁극기 3차 — 락온 줌아웃 약 0.4초로 완화(`ULT_K_IN` 6.5, 줌 스프링 70/15). 원인이던 순간이동 수정: 슬로우 전환 프레임에 (프레임 시간÷배율)로 재던 카메라 실시간 dt 를 실제 시계로 잼(`Main._update_camera`). 조준 중 마우스를 붙잡고(CAPTURED) 이동량으로 월드 조준점 `Player.ult_aim_w` 를 옮기며, 카메라가 그 점을 화면 가운데 가깝게 따라감(`CameraRig.ULT_FOCUS` 0.88, 보스전 카메라는 `_ult_aim_shift`). 락온마다 `CameraRig.lock_impact`(적 쪽 끌림·줌인 펀치·떨림).
- 2026-10-02 (미커밋): 궁극기 4차 — 락온 조준점 10m 거리 제한 해제. 이제 화면 가장자리(`Player.ULT_EDGE_PX`)까지만 묶어 화면에 보이는 적은 모두 조준 가능(안전 상한 `ULT_REACH` 40m). 먼 곳을 조준해도 플레이어가 화면에 남게 시선 이동은 `CameraRig.ULT_LOOK_MAX`(7.5m)까지.
