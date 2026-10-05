# 벌레형 괴생명체 적 — 개미 병정 · 공벌레 · 촘퍼 · 애벌레

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

**방 탐색 아레나(`main.tscn`)는 벌레 아레나다 (2026-10-04)**: `Main.bug_arena`(스크립트가 `main.gd` 그대로일 때만, `--enemies=classic` 이면 끔)면 `_activate_bug_room` · `_fill_bug_queue` 가
애벌레 · 촘퍼 · 개미 · 공벌레만 대기열에 넣는다(기계 적 없음). 위험도 레벨 = 정리한 방 수, 레벨별 표는 `Main.bug_count / bug_alive / bug_interval / bug_hp / bug_aggro / bug_weights`
(`hp_mul` 과 `BugEnemy.aggro` — 공격 쿨타임 `attack_cd`·`roll_cd` 를 배율만큼 빨리 돌림 — 을 소환 때 넣는다). 테스트 `tests/bug_arena_check.gd`.

아래는 그 전 기록 — 섹터 런 스폰 큐(`main.gd _fill_queue`)에는 아직 넣지 않았다 — 같은 시기 다른 작업자가 `InsectEnemy`(insects.tscn)를 그 자리에 넣고 있었다.
넣을 때는 `_spawn` 의 `match` 에 `BugAnt.new()` / `BugPill.new()` 를 추가하고 비율 상수를 하나 더 두면 된다 (`Enemy` 계약을 그대로 따른다).

## 촘퍼 (CHOMPER) — 튜토리얼용 하찮은 우주 벌레

사용자 3면도(정면·측면·후면: 노란 갑각 판 · 주황 반점 · 청록 몸통 · 얼굴 전체가 입 · 이빨 4 · 분홍 혀 · 짧은 다리 6 · 청록 구슬)를 바탕으로 추가 (2026-10-03).

**v2 (2026-10-04): 모델을 사용자가 Tripo 로 만든 것으로 교체.** 원본 `models/source/chomper_tripo/original.glb`
(Downloads 의 `cartoon+shell+creature+3d+model.glb` 와 SHA256 `2a00d45a…` 동일, 파츠 28개 · 1.06만 삼각형 · 파츠별 베이스컬러 28장, 스킨·애니메이션 없음)를
`models/src/bug_chomper.py` 가 관절 단위로 나눈다. 외형(부피·표면·텍스처)은 줄이거나 바꾸지 않고:
① 정면을 +Y 로 180° 돌림 ② 텍스처 28장을 2048 아틀라스 1장(`assets/models/bug_chomper_chomper_atlas.png`)으로 빈틈없이 모으고 UV 는 타일 자리로 옮기기만 함, 재질 1개(러프니스 .66 — BrawlLook 이 캐릭터로 분류)
③ 몸통에서 아랫입술 테를 평면으로 떼어 턱으로(경첩 = 턱 밑), 다리는 주황 마디/갈색 발톱 색 경계에서 잘라 두 마디(잘린 면은 막음)
④ 발끝이 바닥에 닿게 다리를 고관절 기준으로 -16°~+1° 돌림(모양 그대로) ⑤ 피벗·계층·부착점. 1.18만 삼각형, 0.88 × 1.00 × 0.73m.
몸통은 위가 열린 껍질이라 턱 이음매는 막지 않았다(재질이 양면이라 틈으로 안쪽 청록이 보임).
리그 변경: 다리 들기 축을 다리마다 "고관절→발끝 수평 방향 × 위" 로 계산(앞다리가 앞으로, 뒷다리가 뒤로 뻗어 옆 축 하나로는 발이 안 들림), 고정 `REACH` 대신 다리별 거리.
v1(스크립트로 깎은 모델) 원본·GLB·미리보기는 `output/models/bug_chomper_v1/` 에 보존. 캡처 `output/chomper-v2-20261004/`(`chomper_v2_animation_sheet.png` 9클립 · `chomp_close.png`).

| | 촘퍼 `BugChomper` |
|---|---|
| 모델 | `models/src/bug_chomper.py` (Tripo 원본 가공) → `assets/models/bug_chomper.glb` (1.18만 삼각형, 높이 0.73m · 폭 0.88m · 길이 1.0m) |
| 텍스처 | Tripo 파츠 텍스처 28장을 모은 2048 아틀라스 1장. GLB 에 들어가고 Godot 이 `assets/models/bug_chomper_chomper_atlas.png` 로 꺼낸다 (.import 와 함께 올릴 것) |
| 리그 | `scripts/bugs/chomper_rig.gd` (`ChomperRig`) |
| 적 | `scripts/bugs/bug_chomper.gd` (체력 2 × HP_SCALE, 반지름 0.5) |
| 공격 | 근접 덥석 물기만: 뒤로 웅크려 입을 쩍 벌리고 판을 곤두세움(정수리 구슬이 붉게 · 금빛 예고 = 패링 가능) → 콩 뛰어 2.3m 덥석 |
| 특징 | 돌아다니는 동안 노란 체액을 조금씩 떨어뜨린다 (방울 맺힘 → 떨어짐 → 작은 웅덩이 → 3~4.5초 뒤 마름, 서 있으면 입에서 침처럼). 맞으면 가끔 겁먹고 도망쳤다 돌아온다 |

- 모델 계층 (v2, 회전 0, 원점 = 관절): `body > head`(앞 차양 · 입천장 · 윗니 2 · 차양 구슬), `body > jaw`(아랫입술 테 · 아랫니 2) `> tongue`(입 바닥 · 혀),
  `body > shell_1`(위 갑각 두 장 · 구슬 2) `> shell_2`(가운데 볏) · `shell_1 > shell_3`(뒤 꼬리 판), `body > pad_l/r`(옆·뒤를 덮는 큰 갑각, 경첩 = 등 위 안쪽),
  `body > leg_<1|2|3>_<l|r>_1`(주황 마디) `> _2`(갈색 발톱, 1 = 앞다리). 부착점 `pt_eye_l/r`(위 갑각 구슬 — BugEnemy 의 예고 발광 자리) · `pt_mouth` · `pt_horn`(볏 끝) · `pt_drip_{belly,tail,l,r,mouth}` · `pt_foot_<i>_<l|r>`.
  (v1 은 `shell_1 > shell_2 > shell_3` 사슬이었다. 꼬리 판이 볏에 매달리면 볏이 들릴 때 함께 떠올라 v2 는 위 갑각 아래에 둔다.)
- 애니메이션 (Godot 절차, 입력 → 동작):

| 입력 | 동작 |
|---|---|
| `speed` · `turn` | 삼각 지지 걸음(1좌·2우·3좌 ↔ 1우·2좌·3우), 반 주기마다 콩 내려앉음 · 좌우 뒤뚱 · 가감속 관성 젖힘 · 걸음에 맞춰 입 덜렁. 음수 속도 = 뒷걸음 |
| (항상) | 숨쉬기(몸 눌림 · 판 들썩) · 헐떡이는 입 · 혀 꿈틀 · 짧게 끊어 두리번 · 가끔 이빨 딱딱 · 하품 · 서 있는 동안 다리 하나씩 꼼지락. 갑각 판은 몸 위아래 가속을 받는 스프링이라 걸음마다 출렁 |
| `windup` · `lunge` · `snap` · `chew` · `lick` | 웅크림·입 최대·판 곤두세움·부들부들·앞다리 땅 파기 → 앞으로 뻗기 → 입 꽉 닫힘 → 우물우물 → 혀로 입가 핥기 |
| `startle` · `alarm` · `dizzy` · `air` | 깜짝 콩 뛰기 + 다리·판 쫙 / 판 덜컹 + 다리 버둥 / 빙글빙글·헤벌레·혀 축·비틀걸음 / 공중에서 다리 늘어뜨림 |
| `dead_k` · `kick_power` · `emerge_k` | 다리 말아 올리고 따로 움찔, 혀 늘어짐 / 땅에서 허우적 |

  몸이 내려앉거나 기울면 각 고관절이 내려간 만큼 다리를 들어(펴서) 발이 바닥에 남는다 (테스트 v2: 걷기 최저 -0.005m, 웅크림 -0.029m).
- 확인: `chomper_test.cmd`(= `bugs.tscn -- --only=chomp`), 시험장 7 키 소환 · 4 키 전시(촘퍼는 9클립을 따로 돈다: IDLE · WANDER · CRAWL · NOTICE · CHOMP · HURT · DIZZY · DEATH · EMERGE).
  근접 캡처 `powershell -File tools\godot.ps1 wait --fixed-fps 30 -s res://_capture/chomper_show.gd -- --out=<폴더> [--view=three|side|front|back] [--zoom=1.5] [--clip=N] [--every=3]`,
  결과 `output/chomper-20261003/`(`chomper_animation_sheet.png` · `chomp_front.png` · `crawl_side.png` · `combat_bot_sheet.png`, 프레임 폴더 `frames_*` 는 git 제외). 테스트 `tests/bug_chomper_check.gd`(29항목).
- 공통 변경: `BugEnemy.goo`(체액 색) · `splat_kind`(바닥 얼룩 0 초록 / 1 노랑) · `_update_stagger` 덮어쓰기(Enemy 기본이 드론 높이 1m 를 절대값으로 써서 패링 경직 중 벌레가 떠 있던 것 수정, 개미·공벌레도 적용). 효과음 `bug_chomp` · `bug_drip` · `bug_squeak` 추가.
- 본편 스폰 큐에는 아직 넣지 않았다 (튜토리얼·초반 방에 넣을지 사용자 결정).

## 애벌레 (GRUB) — 가장 기본 몬스터

채택 3면도 `output/cream-grub-turnaround-20261004/cream_grub_turnaround.png`(정면·우측면·후면: 크림색 낮은 돔 · 베이지 띠 2개 · 앞 아래 회색 두 겹 아치 · 짙은 갈색 앞 부품, 눈·발 없음)를 바탕으로 추가 (2026-10-04).
3면도의 갈색 앞 부품은 사용자 요청대로 **더듬이 한 쌍**으로 해석해 3마디로 만들고, 게임 시점에서 읽히게 원화보다 길게(약 0.24m) 늘였다.

| | 애벌레 `BugGrub` |
|---|---|
| 모델 | `models/src/bug_grub.py` → `assets/models/bug_grub.glb` (4,926 삼각형, 길이 1.36m · 폭 0.92m · 높이 0.50m, 더듬이 포함 길이 1.64m) |
| 리그 | `scripts/bugs/grub_rig.gd` (`GrubRig`) — 몸통 스키닝 + 연동 운동 |
| 적 | `scripts/bugs/bug_grub.gd` (체력 3 × HP_SCALE, 반지름 0.55, 기는 속도 0.85m/s) |
| 점액 흔적 | `scripts/bugs/slime_trail.gd` (`SlimeTrail`) |
| 공격 | 근접 덮치기만: 몸을 꼬리 쪽으로 바짝 움츠려 앞몸을 쳐들고 더듬이를 활짝 벌려 떤다(0.75초, 금빛 예고 = 패링 가능) → 몸을 앞으로 확 늘이며 1.5m 덮쳐 더듬이로 덥석 → 1초 동안 몸을 추스름 |

- **모델**: 몸통 `body` 는 통짜 메시 하나 — 길이 방향으로 초타원 단면 고리(ring)를 이어 만든 돔(옆면이 서고 윗면이 넓은 정면도 실루엣, 측면은 가운데보다 살짝 앞이 가장 높음). 띠 두 개는 별도 갑각이 아니라 재질 영역이고 띠 경계마다 고리를 둬서 색 경계가 반듯하다.
  계층: `body`(원점 = 바닥 가운데, 재질 2개 크림 · 띠) · `head`(원점 = 몸 속 목 자리, 밝은 회색 캡슐 + 짙은 얼굴판) `> feeler_<l|r>_1 > _2 > _3`(원점 = 각 마디 뿌리).
  부착점 `pt_eye_l/r`(얼굴판 — 공격 예고 발광, 눈 없는 디자인이라 평소엔 안 보임) · `pt_mouth` · `pt_tail` · `pt_feeler_tip_l/r`.
- **스키닝**: 몸통에 Blender 뼈를 넣지 않고 Godot 이 처음 불러올 때 뼈 9개(`GrubRig.NB`, 부모 없음, 꼬리 → 머리 1.2m)를 박는다. 가중치는 정점의 길이 위치로 이차 B-스플라인(가까운 뼈 셋)이라 뼈 사이가 매끈하다. 스키닝한 메시·Skin 은 정적 캐시 1개를 모든 애벌레가 같이 쓴다.
- **연동 운동 (peristalsis)** — 진짜 애벌레처럼:
  한 주기(0.34m 전진) 동안 꼬리 고리부터 차례로 앞으로 옮긴다(고리 하나가 움직이는 시간 = 주기의 72%). 아직 안 옮긴 앞 고리는 바닥을 붙잡고 있어 그 사이 몸이 줄어들고(수축 물결이 꼬리 → 머리), 마지막에 머리가 내밀리며 늘어난다(이완).
  몸 중심(적 원점)은 일정 속도로 가고 고리 상대 위치 = STRIDE · (진행도 − 주기 진행도) 라서 **바닥을 붙잡은 고리는 월드에서 멈춰 있다**(미끄러지지 않음 — 테스트: 최소 속도 0.000~0.005m/s).
  옮기는 중인 고리는 살짝 들리고(혹), 고리 사이가 줄어든 곳은 부피를 지키듯 높고(λ^-0.5) 굵게(λ^-0.22), 늘어난 곳은 가늘고 납작해진다. 멈춰도 하던 수축 주기는 마저 끝낸다.
- 애니메이션 입력 → 동작:

| 입력 | 동작 |
|---|---|
| `speed` · `turn` | 연동 수축으로 기기 · 돌 때 지나온 길을 따라 몸이 활처럼 휨(머리는 도는 쪽, 꼬리는 반대) · 매 주기 끝에 머리를 쑥 내밂 · 수축 시작마다 `pulsed`(질척 소리) |
| (항상) | 숨쉬기(몸이 아주 작게 늘었다 줄었다) · 서 있으면 앞몸을 들고 짧게 끊어 두리번 · 가끔 제자리에서 작은 수축 물결이 지나감 |
| 더듬이 | 3마디 스프링(끝으로 갈수록 무름 → 채찍처럼 늦게 따라옴). 기는 동안 주기에 맞춰 번갈아 좌우를 쓸고, 서 있으면 번갈아 바닥을 톡톡, 가끔 혼자 움찔 |
| `windup` · `lunge` · `bite` | 꼬리 쪽으로 움츠리며 앞몸 쳐듦 · 더듬이 활짝 벌려 떪 · 부들부들 → 몸을 앞으로 확 늘이며 앞몸을 내리찍음 → 더듬이가 집게처럼 오므라듦 · 머리 끄덕 |
| `alarm` · `startle` · `dizzy` | 피격: 몸 전체가 움찔 줄며 S 자 몸부림 · 더듬이 뒤로 젖힘 / 알아챔: 앞몸 번쩍 · 더듬이 쭉 / 패링 경직: 앞몸이 느리게 휘청 · 더듬이 축 |
| `dead_k` · `kick_power` · `emerge_k` | 뒤집힌 채 양 끝을 배 쪽으로 C 자로 말며 꿈틀 / 땅에서 몸부림치며 올라옴 |

- **점액 흔적 (`SlimeTrail`)**: 애벌레마다 하나, `FX.root` 아래. 꼬리 끝이 0.09m 나아갈 때마다 점을 찍고 좌우로 벌려 바닥에 붙은 리본 띠(폭 0.6m, 길이를 따라 매끈하게 굽이침)를 만든다. 띠의 좌우는 몸 방향에서 정해 넉백으로 뒤로 밀려도 꼬이지 않고, 뒤로 밀리는 동안은 찍지 않으며, 0.9m 넘게 튀면 띠를 끊고 새로 시작한다.
  셰이더: 거의 투명한 몸 + 가장자리에 물기가 도톰하게 몰린 테(메니스커스) + 테·잔물결 노멀로 젖은 반사(러프니스 0.03) + 작은 기포 반짝임. 갓 나온 쪽은 조금 진하고, 9초에 걸쳐 가장자리 은빛 자국만 남기고 마르며 사라진다(마지막 4초).
  점마다 태어난 시각을 UV2 에 넣고 셰이더가 나이를 계산하므로 메시는 점이 늘거나 지워질 때만 다시 만든다(점 상한 150). 주인이 죽어도 흔적은 남았다가 다 마르면 스스로 사라진다.
- 효과음 `bug_squelch`(몸 수축 질척) · `bug_gnash`(덮치기 철퍽 + 더듬이 딱) 추가, 바닥 얼룩 `splat_kind` 2(크림) 추가.
- 확인: `grub_test.cmd`(= `bugs.tscn -- --only=grub`), 시험장 8 키 소환 · 4 키 전시(애벌레는 9클립: IDLE · CRAWL · WANDER · NOTICE · ATTACK · HURT · DIZZY · DEATH · EMERGE, 기는 클립은 실제로 앞으로 나아가며 흔적을 남긴다).
  근접 캡처 `powershell -File tools\godot.ps1 wait --fixed-fps 30 -s res://_capture/grub_show.gd -- --out=<폴더> [--view=side|three|top|front] [--clip=N] [--every=3]`(바닥에 0.5m 눈금 점 — 미끄러짐 확인용),
  결과 `output/grub-20261004/`(`sheet_crawl_side.png` 한 수축 주기 · `sheet_idle.png` · `sheet_attack.png` · `sheet_misc.png` · `combat_bot_sheet.png`, 프레임 폴더 `frames_*` 는 git 제외). 테스트 `tests/bug_grub_check.gd`(36항목).
- 방 탐색 아레나(벌레 아레나)에 등장한다 — 위 "본편 연결" 참고. 섹터 런에는 아직 없다.
