# 배경 첫 제작 — Claude 작업 기록

2026-10-03~04 사용자 착수 지시를 받은 Claude 가 진행했다. 기준은 [background-first-pass-handoff.md](background-first-pass-handoff.md) 의 F01/W01/A01/A02 4종이다.
같은 시간 Codex 도 같은 4종을 따로 만든다([background-first-pass-codex.md](background-first-pass-codex.md)). 두 결과물은 **서로 다른 파일**이며 무엇을 쓸지는 사용자가 정한다.

## 파일 소유 범위 (Claude)

- `models/src/bg_claude_*.py`
- `tools/blender/claude_background_*.py`
- `assets/models/bg_claude_*.glb` 와 딸린 추출 텍스처/임포트
- `scripts/claude_background/`
- `scenes/claude_background_first_pass.tscn`
- `claude_background_test.cmd`
- `tests/claude_background_check.gd`
- `output/models/bg_claude_*/`, `output/claude-background-first-pass/`

Claude 는 `bg_codex_*`·`codex_background*` 파일과 인수인계 문서의 일반 이름(`bg_floor_f01`, `background_first_pass.tscn`)을 쓰지 않는다.
기존 플레이어/카메라/본편/로비/훈련장 파일과 공용 Blender/Godot 실행기는 수정하지 않았다 (로비 목록에도 넣지 않음 — 실행은 `claude_background_test.cmd`).

## 현재 상태: 1차 완성 · 본편 적용됨

| 파츠 | 원본 | 크기 (Godot X×Y×Z) | 삼각형 | 텍스처 | 하위 메시 |
|---|---|---|---|---|---|
| F01 바닥 | `models/src/bg_claude_f01.py` | 2 × 0.2 × 2, 피벗 좌측 앞 윗모서리 | 108 | 2048px = 4m 월드 반복 (512px/m) | — |
| W01 벽 | `models/src/bg_claude_w01.py` | 2 × 3 × 0.25, 피벗 좌측 앞 바닥, 정면 -Z | 3,536 | 2048 아틀라스 350px/m | — |
| A01 작업대 | `models/src/bg_claude_a01.py` | 2 × 1 × 0.75, 피벗 바닥 중심 | 3,012 | 2048 아틀라스 323px/m | body / top / drawers |
| A02 수납장 | `models/src/bg_claude_a02.py` | 1 × 2 × 0.5, 피벗 바닥 중심 | 2,300 | 2048 아틀라스 492px/m | body / door_upper / door_lower (문 원점 = 경첩) |

### 텍스처링 방식

1. **붓질 원본** `tools/blender/claude_background_paint.py` (numpy): 재질별 반복 텍스처(보라·회보라·문 보라·코랄·암부)를 승인 v6 팔레트
   (`#56438A/#423665/#6E4382/#CE5F54`)로 그린다. 넓고 부드러운 색 변화 → 낮은 대비의 큰 평붓 자국 → 아주 약한 결. 거친 노이즈·긁힘 없음.
   바닥 `floor_4m` 은 2m 타일 4장(4m 주기)에 3px 줄눈, 위·왼쪽 안쪽 밝은 베벨 칠, 아래·오른쪽 짙은 칠, 가운데 조용한 칠한 부피감, 타일마다 한두 모서리만 마모.
2. **베이크** `tools/blender/claude_background_bake.py` (Cycles): 붓질 텍스처를 오브젝트 좌표로 상자 투영하고, 실제 모디파이어 베벨 면에 밝은 칠(아래 베벨은 짙게),
   국소 AO 를 유색 그림자(#3A2F62 계열)로, 아주 약한 면 방향/높이 명암, 노이즈로 고른 일부 베벨에만 코랄 마모를 섞어 UV 아틀라스에 굽는다.
   씬 방향 그림자·조명 글로우는 굽지 않는다. 결과는 메시당 "구운 텍스처 1장 + Roughness .85 + 비금속" PBR 재질로 GLB 에 들어간다 (Godot 이 그대로 StandardMaterial3D 로 받음).
3. 원본 붓질 캐시: `output/claude-background-first-pass/src_textures/` (재현 가능, 지우면 다시 그림). 구운 아틀라스: `output/models/bg_claude_*/bg_claude_*_albedo.png`, 베이크 정보 `bake.json`.

**인수인계 규격과 다른 점 (의도적)**
- 텍셀 밀도: 붓질은 월드 좌표 텍스처에서 굽기 때문에 아틀라스 밀도가 낮아도 붓 크기(m)는 같고 선명도만 준다. W01·A01 은 512px/m 로는 2048 에 안 들어가(패킹 효율이 낮음) 4096(VRAM 4배) 대신 2048 에 323~350px/m 로 넣었다. 게임 카메라에서 벽은 화면상 약 75px/m 라 차이가 보이지 않고, 근접 캡처에서도 붓 결은 유지된다. 밀도를 반드시 맞춰야 하면 `bake_model(res=4096)`.
- PROP 공용 아틀라스 대신 프랍마다 아틀라스 1장 (GLB 가 이미지를 품으면 Godot 이 GLB 마다 따로 꺼내므로 실제 공유가 안 된다).
- 바닥 4m 위상: GLB 의 UV 는 월드와 같은 위상(UV = X/4, Z/4)이라 단독 사용 시 4m 그림의 1/4 이 보인다. 시험 씬은 `scripts/claude_background/bg_floor.gdshader` 가 같은 텍스처를 월드 XZ/4 로 읽어 타일 위치·90도 회전과 무관하게 4m 주기를 잇는다 (16장이 재질 하나 공유).

### 시험 씬

- `claude_background_test.cmd` → `scenes/claude_background_first_pass.tscn` (`ClaudeBgMain extends TrainingMain`).
- 8×8m 바닥(F01 16장) + ㄱ자 벽(뒤 4장이 모서리 0.25×0.25 소유, x -4.25~3.75 · 왼쪽 4장 z -4~4) + 뒤 벽 앞 작업대(중심 x -2)·수납장(중심 x 2.5), 벽에서 0.05m.
- 판정은 ArenaMap 8×8 방(1m 칸), 프랍 칸은 막힘. 충돌은 렌더 메시와 별도의 단순 상자.
- 조명 기본 = 현재 전투 환경 그대로(`Main._build_environment`). **9 키** 로 시험 조정판(환경광 조금 밝고 덜 파랗게, 해 조금 약하고 따뜻하게)과 비교. **0 키** 진짜 적(드론 2·돌격기 1) 소환. 1~8 은 전투 테스트장과 같음(허수아비·반격·무적…).
- 확인용 인자: `--bglight=1` · `--bgfoes` · `--bgview=0~3`(고정 시점: 전체 · 바닥 이음 근접 · 프랍 근접 · 벽 모서리).

### 검증

```powershell
powershell -File tools\blender.ps1 model models\src\bg_claude_w01.py --engine=eevee     # f01 / a01 / a02 도 같음
powershell -File tools\godot.ps1 wait --headless --import
powershell -File tools\run_tests.ps1 claude_background_check
powershell -File tools\godot.ps1 wait --fixed-fps 60 res://scenes/claude_background_first_pass.tscn -- --bot --bgfoes --seconds=60 --capture=
powershell -File tools\godot.ps1 wait --fixed-fps 60 --resolution 1600x900 res://scenes/claude_background_first_pass.tscn -- --bot --bgview=0 --capture=<공백 없는 폴더> --every=60 --seconds=2.2
```

- `tests/claude_background_check.gd` 30항목 PASS: GLB 4종 크기·피벗·축, 구운 텍스처 연결(비금속·거친 면), 하위 메시·문 경첩 원점, 바닥 16장 면적 64m²·겹침 0·윗면 Y=0·셰이더 재질 공유,
  벽 범위·관통 0·정면 방향, 프랍 벽 간격 0.05·접지·서로 안 겹침·칸 막힘, 플레이어 시작 위치.
- 2026-10-04 전체 회귀 23종 PASS (Codex 의 `codex_background_check` 포함), 시험 씬 60초 bot(적 소환) ERROR/WARNING 0.
- 캡처 `output/claude-background-first-pass/`: `overview_base_light.png`(기준 조명) · `overview_tuned_light.png`(조정 조명) · `game_camera_follow.png`(실제 추적 카메라) ·
  `floor_seam_close.png` · `props_close.png` · `wall_corner_close.png` · `models_preview_sheet.png` · `floor_4m_texture_half.png` · `summary.json`.

### 본편 적용 (2026-10-04, 사용자 지시: Claude 판 채택 → 2차: 시험 씬과 같은 모델로)

1차는 바닥 텍스처만 같고 벽은 그림 띠를 입힌 낮은 상자라 시험 씬과 많이 달랐다. 2차에서 **시험 씬과 같은 W01·F01 텍스처·A01·A02 를 실제로 쓰고**,
본편 구조(1m 칸·0.8m 벽·임의 방 모양)에 맞는 W01 계열 모델을 Blender 로 더 만들었다. 그림 띠 방식(벽 띠 텍스처·`bg_wall.gdshader`)은 지웠다.

`scripts/map.gd` 의 `ArenaMap.build()` 에 두 줄: `ClaudeBgDress.plan(self, wall_prop_cells)`(벽 상자를 만들기 전) · `ClaudeBgDress.apply(self)`(끝).
방 탐색(`main.tscn`)·섹터 런(`run.tscn`)·ArenaMap 을 쓰는 시험장(전투 테스트·기믹)이 모두 바뀐다. **판정(칸 막힘·충돌 상자)·지형·방 구성은 그대로**, 보이는 것만 바뀐다.
코드 `scripts/claude_background/claude_bg_dress.gd` (`ClaudeBgDress`).

| 본편 요소 | 쓰는 모델 | 규칙 |
|---|---|---|
| 뒤쪽(-Z) 벽 직선 구간 | **W01 (3m)** 2m 모듈 · 남는 한 칸은 **W01 반쪽** `bg_claude_w01_half` (1m) | 바로 앞이 평평한 바닥, 출입구 아님, **뒤 3칸에 바닥·기둥 없음**(다른 방을 가리지 않게), 3칸 이상 이어진 구간만. 앞면이 바닥 경계 |
| 벽감 | W01/반쪽을 (프랍 깊이+0.05) 뒤로 물리고 양옆 **옆판** `bg_claude_jamb`(0.12×3×0.55) + 바닥 + **A01/A02** | 방마다 작업대 1·수납장 1(큰 방 2씩), 3m 구간 가운데쪽, 양옆 한 칸씩 3m 벽 유지. 벽 칸 자리라 전투 바닥 불변 |
| 나머지 벽(0.8) · 낮은 엄폐물(0.7) · 기둥(1.5) | **낮은 W01 블록** `bg_claude_block_{wall,cover,pillar}` (1m 칸 하나, 1,268 삼각형) | 칸마다 MultiMesh. 네 옆면에 3cm 파낸 자리 + 모서리 깎은 회보라 패널 · 볼트, 윗덮개 보라회보라(바닥과 명도 분리), 바닥 아래는 짙은 단색. 예전 단색 상자는 숨김 |
| 방·통로 바닥 | **F01 4m 텍스처** (`bg_floor.gdshader`, 시험 씬과 같은 셰이더) | 방마다 2m 줄눈이 방의 왼쪽·뒤 벽에서 시작하도록 `offset`(0/1m) — 재질 많아야 4개 공유 |

- 모델 원본: `models/src/bg_claude_{w01,w01_half,jamb,block_wall,block_cover,block_pillar}.py`, 공용 형상 `tools/blender/claude_background_shapes.py` (`w01(W)` · `jamb()` · `block(top, bottom)`).
- 끄기: 실행 인자 `--bg=old` (또는 `ClaudeBgDress.enabled = false`). `painted_look_check`(K 칠 모드)는 예전 재질 기준 검사라 시작에서 끈다.
- 동시 작업 연결: 다른 세션의 `BrawlLook`(브롤스타즈 식 화면, 기본 켜짐)이 이 바닥 셰이더·블록 MultiMesh 를 자기 셰이더로 덮어쓴다. 바닥 `offset` 이 이어지도록 `brawl_look.gd` 의 바닥 셰이더·`_floor_for` 에 offset 전달 3줄을 더했다.
- 검사(`claude_background_check` 본편 항목, seed 3): 바닥 11개 모두 새 셰이더 · 방마다 줄눈 위상 · 예전 벽 상자 숨김 · 막힌 칸이 블록/3m 벽/벽감/WallProps 로 빈틈없이 덮임 · 3m 벽 뒤 3칸 바닥 없음 · 벽감 프랍이 벽 칸(막힘)에 섬 · 끄면 예전 그대로.
  헤드리스 렌더러는 MultiMesh 변환을 돌려주지 않아 블록 자리는 `claude_spots` 메타로 검사한다.
- 캡처: `output/claude-background-first-pass/main_game_v2_*.png` (1차 그림 띠 판은 `main_game_*.png` 로 남김).

### 남은 문제 / 다음 판단

- 현재 전투 조명(푸른 환경광 0.5 + 해 1.25)에서는 바닥이 원화보다 조금 파랗고 밝게 보인다 → 바닥 그림을 한 번 어둡고 덜 파랗게 고쳤다. 남은 차이는 조명 쪽(9 키 조정판) 결정 사항.
- 코랄 마모 얼룩이 벽 프레임 모서리에 조금 많다 (`wear_amt` 로 조절).
- 아틀라스 패킹 효율이 낮다 (채움 28~49%). 텍스처 메모리를 줄이려면 보이지 않는 틈 면을 더 줄이거나 직접 UV 를 잡아야 한다.
- 바닥 밉맵/먼 거리 번짐은 고정 시점 캡처로만 확인했다(눈에 띄는 번짐 없음). 프랍 근접은 경계 번짐 없음.
- 본편: 낮은 블록이 칸마다 1m 이음을 가진다(연속 2m 패널은 3m 뒤 벽만). 짧은 뒤 벽(1~2칸)·앞쪽·옆쪽 벽은 모두 낮은 블록.
- 기존 WallProps(회색·민트 기계 장식)는 다른 작업물이라 그대로 — 새 팔레트와 색이 다르다.
- 범위 밖으로 두었다: 감염 레이어, 문·배관·난간·안전선·작은 소품, 보스전 등 자체 스테이지, 로비 목록 연결.
