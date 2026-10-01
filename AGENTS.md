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
| 씬 바로 실행 | `training.cmd`(허수아비 전투 테스트) · `dialogue_test.cmd`(캐릭터 대화) · `sector_run.cmd` · `boss_battle.cmd` · `forge_battle.cmd` · `abyss_battle.cmd` · `spider_boss.cmd`(거미 보스) · `mammoth_death_test.cmd` · `reference_mech_studio.cmd` |

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

## 5. 현재 상태 (작업을 마칠 때 갱신한다)

마지막 갱신: 2026-10-01

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
