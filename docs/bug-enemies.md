# 벌레형 괴생명체 적 — 개미 병정 · 공벌레

사용자 원화(적갈색 직립 개미 / 크림색 공벌레·공 변형)를 바탕으로 만든 적 두 종.
모델은 Blender 스크립트로 만들고, 애니메이션은 Godot 코드(절차 애니메이션)로 만든다.

| | 개미 병정 `BugAnt` | 공벌레 `BugPill` |
|---|---|---|
| 모델 | `models/src/bug_ant.py` → `assets/models/bug_ant.glb` (1.1만 삼각형, 높이 1.77m) | `models/src/bug_pillbug.py` → `assets/models/bug_pillbug.glb` (1.3만 삼각형, 길이 1.9m, 공 지름 1.2m) |
| 리그 | `scripts/bugs/ant_rig.gd` (`AntRig`) | `scripts/bugs/pill_rig.gd` (`PillRig`) |
| 적 | `scripts/bugs/bug_ant.gd` | `scripts/bugs/bug_pill.gd` |
| 체력 | 5 (× `Enemy.HP_SCALE`) | 6 (×) |
| 공격 | 산 5발 부채꼴 (배를 다리 사이로 말아 쏨) · 근접 물기 돌진(금빛 예고 = 패링 가능) | 몸을 말아 굴러 박치기 (벽 2회까지 튕김) |
| 특징 | 짧게 후다닥 달렸다 멈췄다 하는 지그재그 접근 | 공 상태에선 총알을 튕김 · 멈추면 펴고 어질어질(노릴 틈) |

공통 `scripts/bugs/bug_enemy.gd` (`BugEnemy extends Enemy`): GLB 사용 · 땅을 뚫고 기어 나오는 등장 · 초록 체액 피격 ·
죽음 3종(뒤집혀 다리 버둥 → 터짐 / 광선검이면 머리·앞몸이 잘려 날아감 / 미사일·레이저 과부하는 즉시 터짐) · 바닥 체액 얼룩.
효과음 `scripts/bugs/bug_sound.gd` (`BugSound`, 합성): 큰턱 딸깍 · 찍찍 · 산 분사 · 철퍽 · 다다닥 · 땅 파기. `Sfx` 본체는 수정하지 않고 캐시에 이름만 더한다.

## 모델 (Blender)

빌드: `powershell -File tools\blender.ps1 model models\src\bug_ant.py` (공벌레도 같음). 미리보기 `output/models/bug_*/preview.png`.

- **모든 파츠 회전 0, 원점 = 관절** (`after_join` 에서 `hb.rebase`). 그래서 Godot 에서 `rotation` 을 그대로 관절 각도로 쓴다.
- 개미 계층: `pelvis > thorax > head > mandible_l/r · antenna_l_1 > _2 > _3`, `thorax > arm_*_upper > _fore > _claw`, `thorax > mid_*_upper > _lower`,
  `pelvis > gaster_1 > gaster_2`, `pelvis > leg_*_thigh > _shin > _foot`. 부착점 `pt_eye_l/r · pt_mouth · pt_stinger · pt_foot_l/r · pt_antenna_tip_l/r`.
- 공벌레 계층: 루트 `seg_3`, 앞 사슬 `seg_2 > seg_1 > seg_0(머리, 더듬이 3마디)`, 뒤 사슬 `seg_4 > … > seg_7(꼬리 돌기)`, 판마다 다리 `leg_<i>_<l|r>_1 > _2` (6쌍).
  부착점 `pt_ball_center`(다 말렸을 때 공 중심) · `pt_eye_l/r` · `pt_foot_<i>_<l|r>`.
- **공벌레 등딱지 설계**: 판 8장을 "다 말린 공" 상태에서 공 껍질의 45° 조각으로 만든 뒤 관절 굽힘을 거꾸로 적용해 펼친 자세로 되돌렸다.
  그래서 관절마다 45° 굽히면 틈 없는 공이 된다 (테스트: 바깥면 반지름 0.544~0.600m). 펼친 자세는 판이 기와처럼 겹치고, 평소엔 관절당 0.1rad 굽혀 둥근 등으로 쓴다.

## 애니메이션 (Godot 절차)

Blender 키프레임 대신 코드로 만든 이유: 이 프로젝트의 모든 적이 코드 애니메이션이라 AI 상태(달리기 속도·공격 준비 진행도·피격)와
그대로 섞이고, 무작위 경련처럼 매번 달라야 벌레답게 보이는 동작을 만들기 쉽다. 리그는 판정을 하지 않고 입력 값만 받아 관절을 돌린다.

| 개미 입력 | 동작 |
|---|---|
| `speed` · `turn` | 짧은 보폭 걸음, 발 디딜 때 통통 튐, 회전 쪽으로 기울임, 가운데 다리 노 젓기 |
| (항상) | 더듬이: 느린 탐색 + 불규칙 경련(스프링, 바깥 마디가 채찍처럼 늦게 따라옴) · 머리 끊어 꺾기 · 큰턱 딸깍 · 배 숨쉬기 |
| `acid_k` · `fire_k` | 몸을 젖히고 배를 다리 사이로 말아 앞으로 겨눔 → 발사 반동 |
| `bite_k` · `lunge_k` | 웅크림·큰턱 활짝·집게 들기 → 앞으로 쭉 뻗으며 닫기 |
| `alarm` · `dead_k` · `kick_power` · `emerge_k` | 피격 버둥 / 다리 말아 올리고 따로 움찔 / 땅에서 허우적 |

| 공벌레 입력 | 동작 |
|---|---|
| `speed` · `turn` | 다리 6쌍이 뒤에서 앞으로 번지는 물결 걸음, 몸판 꿈틀·좌우 비틀기 |
| `curl` · `stretch` | 0~1 말기 (다리·더듬이·꼬리를 공 안으로 접음, 말림별 최저점 표로 바닥 위 유지) / 반동·기지개 젖힘 |
| `roll` | 공 중심을 축으로 굴림 |
| `sniff` · `alarm` · `dead_k` · `emerge_k` | 멈춰 더듬이로 바닥 두드리기 / 버둥 / 뒤집혀 버둥대다 반쯤 말림 / 땅에서 허우적 |

## 확인

- 시험장: `bug_test.cmd` (= `scenes/bugs.tscn`, 로비 "벌레 괴생명체 · 개미 병정 · 공벌레"). 1 개미 · 2 공벌레 · 3 지우기 · **4 애니메이션 전시** · 5 무적 · 6 자동 보충.
  실행 인자 `--gallery` `--bot` `--only=ant|pill`.
- 근접 캡처: `powershell -File tools\godot.ps1 wait --fixed-fps 30 -s res://_capture/bug_show.gd -- --out=<폴더> --kind=ant|pill [--view=side|front|top]`
- 결과 시트 `output/bugs-20261002/` (`ant_animation_sheet.png` · `pill_animation_sheet.png` · `combat_bot_sheet.png`, 클립 순서는 `*_clips.txt`).
- 테스트 `tests/bug_enemies_check.gd` (37항목: 계층·회전 0·발 접지·공 닫힘·말리는 중 접지·리그 유한값·더듬이 움직임·산 발사·굴림·공 상태 총알 튕김·죽음 3종).

## 본편 연결

아직 본편 스폰 큐(`main.gd _fill_queue`)에는 넣지 않았다 — 같은 시기 다른 작업자가 `InsectEnemy`(insects.tscn)를 그 자리에 넣고 있었다.
넣을 때는 `_spawn` 의 `match` 에 `BugAnt.new()` / `BugPill.new()` 를 추가하고 비율 상수를 하나 더 두면 된다 (`Enemy` 계약을 그대로 따른다).
