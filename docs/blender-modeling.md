# Blender 모델링 파이프라인

에이전트(Claude/Codex)가 **Python 스크립트로 직접 모델을 만들고**, 렌더 미리보기로 결과를 눈으로 확인한 뒤,
Godot 용 `.glb` 로 내보내는 흐름이다. 사람도 같은 `.blend` 를 Blender 에서 열어 손볼 수 있다.

## 버전 고정

- 버전은 루트 [`blender-version.txt`](../blender-version.txt) 한 곳 (현재 `5.2.2` LTS, 공식 포터블 zip).
- 항상 `tools\blender.ps1` 로 실행한다. `<프로젝트>/.tools/blender/` (git 제외)에 없으면 `BLENDER_HOME` 이나 옆 폴더의
  `.tools/blender` 에서 복사하고, 없으면 download.blender.org 에서 받아 `blender-<버전>.sha256` 으로 검증한다.
- 새 PC: `setup_blender.cmd` 한 번.

## 명령

| 하고 싶은 것 | 명령 |
|---|---|
| Blender 창 열기 (일반) | `powershell -File tools\blender.ps1` |
| 모델 스크립트 빌드 (헤드리스) | `powershell -File tools\blender.ps1 model models\src\<이름>.py [--engine=eevee] [--no-export] [--no-preview]` |
| 라이브 창 열기 | `blender_live.cmd [파일.blend]` |
| 라이브 창에서 코드 실행 | `powershell -File tools\blender.ps1 send <코드.py> [제한초]` |
| 임의 인자로 실행 | `powershell -File tools\blender.ps1 wait <Blender 인자...>` |

## 빌드 결과 (`model`)

| 파일 | 내용 | git |
|---|---|---|
| `models/src/<이름>.py` | 모델 원본 스크립트 | 올림 |
| `assets/models/<이름>.glb` (+ `.import`) | Godot 용, Y-up, 모디파이어 적용 | 올림 (같은 커밋) |
| `output/models/<이름>/preview.png` | 2×2 시트: 정면(정투영) · 우측면(정투영) / 3/4 앞 · 3/4 뒤, 1m 격자 | 올림 |
| `output/models/<이름>/stats.txt` | 크기·삼각형 수·파츠·피벗·부착점 | 올림 |
| `output/models/<이름>/<이름>.blend` | 빌드된 장면 (사람이 열어 보기용) | 올림 |
| `output/models/<이름>/view_*.png` | 시트의 개별 타일 | 제외 |

`output/models/.gdignore` 가 있어서 Godot 은 `.blend`·미리보기를 임포트하지 않는다 (지우면 Godot 이 Blender 경로를 찾다가 오류를 낸다).

## 모델 스크립트 규칙

예제: [`models/src/sample_turret.py`](../models/src/sample_turret.py). 스크립트 안에서는 `hb`, `bpy`, `math`, `Vector` 를 바로 쓴다.
도우미 목록은 [`tools/blender/hb.py`](../tools/blender/hb.py) 머리말.

- 1 단위 = 1m, 발은 z = 0. Blender 는 Z-up 이고 내보낼 때 Godot Y-up 으로 바뀐다.
- **정면은 Blender +Y** → Godot -Z(앞). +X 는 양쪽 모두 오른쪽.
- 도형: `hb.box / cyl / sphere / torus / prism(측면 실루엣 압출) / tube(배관)`, 공통 인자 `loc rot(도) mat parent bevel part`.
  재질은 `hb.mat(이름, "#rrggbb", metal, rough, emit=)`.
- `part="이름"` 이 같은 도형은 빌드 때 메시 하나로 합쳐진다 → Godot 에서 그 이름의 노드 하나 (애니메이션 단위).
- 합친 뒤 `after_join()` 을 정의하면 불린다: `hb.set_origin`(피벗) · `hb.attach`(계층) · `hb.empty("pt_muzzle", ...)`(부착점).
- 부착점 이름은 `pt_` 로 시작한다 (`@` 등은 Godot 노드 이름에 못 쓴다). Godot 에서 `model.find_child("pt_muzzle")`.
- 좌우 대칭 파츠: `hb.mirror(o)`(같은 메시) 또는 `hb.mirror_copy(o)`(`_l` → `_r` 별도 파츠).

Godot 에서 쓰기: `var m := (load("res://assets/models/<이름>.glb") as PackedScene).instantiate()`.
검사 [`tests/blender_models_check.gd`](../tests/blender_models_check.gd) 가 모든 `.glb` 를 열어 보고, 예제의 계층·피벗·축을 확인한다.

## 라이브 모드

`blender_live.cmd` 로 연 창은 `.tools/blender_live/inbox/` 를 0.25초마다 보고, `send` 로 넣은 코드를 그 창 안에서 실행한 뒤
출력(첫 줄 `OK`/`ERROR`)을 돌려준다. 코드 안에서 `snap()` 을 부르면 가장 큰 3D 뷰포트를 `.tools/blender_live/snap.png` 로 저장한다.
사람이 보고 있는 장면을 에이전트가 같이 고치는 용도이고, 최종 결과물은 `models/src/*.py` + `model` 빌드로 남긴다
(라이브 모드에서는 `part` 합치기·`after_join` 이 자동으로 돌지 않는다).

## 원화와 맞추기 (`--compare`)

원화(3면도 등)를 똑같이 재현할 때 쓰는 반복 도구. 예: 거미 보스 [`models/ref/spider_boss.json`](../models/ref/spider_boss.json).

1. `models/ref/<이름>.json` 에 시점마다 원화에서 자를 영역(`crop`), 축척(`px_per_m`, 납작한 시점은 `py_per_m`),
   기준점(`origin` = 월드 원점이 찍히는 원화 픽셀), 카메라(`front`·`left`·`right`·`top`)를 적는다.
2. `python tools/blender/ref_masks.py models/ref/<이름>.json` → 원화 자르기 + 실루엣 마스크 (`output/models/<이름>/ref/`).
   배선 고리처럼 크게 뚫린 틈은 배경으로 남기고 작은 틈만 메운다.
3. `python tools/blender/ref_grid.py models/ref/<이름>.json` → 원화 위에 미터 눈금 (치수 읽기용).
4. `tools\blender.ps1 model models\src\<이름>.py --compare` → `compare.png`(원화 | 모델 | 겹침: 흰색 일치 · 빨강 원화에만 · 청록 모델에만)
   와 `compare.txt`(시점별 실루엣 IoU). `--compare=flat` 은 음영 없이 바탕색만.
5. 자세히 볼 때: `python tools/blender/zoom_compare.py <이름> <시점> x0 y0 x1 y1 [배율]`(원화·모델 부분 확대),
   `python tools/blender/overlay_zoom.py <이름> <시점>`(겹침 확대).

6. 매개변수 탐색: 모델 스크립트가 `HB_OVERRIDE`(JSON) 로 치수를 받게 해 두면 `python tools/blender/sweep.py models/src/<이름>.py [회차]`
   가 좌표 하강으로 IoU 를 올린다(`sweep.log`, `sweep_best.json`). `compare.txt` 의 `colour` 는 파랑 장갑 · 짙은 프레임 · 밝은 회색 ·
   청록 발광 색 계열이 원화와 같은 비율 — 실루엣만 맞추다 부품이 엉뚱한 곳을 가리는지 잡는 용도. 탐색 결과는 반드시 눈으로 확인한다.

생성 원화는 시점끼리 치수가 안 맞을 수 있다 → 시점마다 축척을 따로 두고, 어긋나는 부분은 기준 시점을 정해 절충한다
(거미 보스: 정면·측면 기준, 평면은 배치 참고).

## 에이전트 작업 순서

1. `models/src/<이름>.py` 작성 → `tools\blender.ps1 model ...`
2. `output/models/<이름>/preview.png` 를 이미지로 읽고 `stats.txt` 로 치수 확인 → 고치고 다시 빌드
3. `--engine=eevee` 로 조명 확인(선택) → `tools\godot.ps1 wait --headless --import` → `run_tests.cmd`
