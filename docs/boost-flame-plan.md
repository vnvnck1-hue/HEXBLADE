# 부스터 불꽃 시트 애니메이션 — 구현 계획 (미착수)

2026-10-06 작성. 사용자 요청 "부스터 바로 입구에, 이런 간단한 시트 애니메이션으로 부스터 불꽃 VFX 추가" 뒤
**"지금 하지 말고 계획만 문서로"** 로 바뀌어 게임 적용 전에 멈췄다. 다음 요청에서 이 문서대로 이어 간다.

## 레퍼런스

사용자 첨부: 2D 애니메이션 FX 튜토리얼 'BOOST PROCESS' (노란 비행체 뒤 부스터 불꽃).

- 4프레임 손그림 루프, **외곽선 없음**, 2톤 — 노랑 바탕 + 밝은 연노랑 안쪽.
  1. 물방울: 분사구 쪽이 둥글고 끝이 뾰족
  2. 길게 늘어남: 머리가 작아지고 꼬리가 가늘고 길게
  3. 끊김: 분사구에 작은 불씨 + 떨어져 나간 둥근 덩어리
  4. 터짐: 떨어진 덩어리가 울퉁불퉁 부풀어 퍼짐
- 이 넷을 빠르게 돌려 '퐁퐁' 끊어 뿜는 만화 불꽃.

## 지금까지 만든 것 (초안, 게임 미연결)

- 생성기 `tools/fx/boost_flame_sheet.py` (numpy 거리장 + 4배 슈퍼샘플, 색을 구워 넣은 RGBA).
  프레임 128×256, 분사구 = 프레임 위 가운데, 불꽃은 아래(+y)로. 시트 = 가로 4칸 512×256.
  색: 바깥 (250, 204, 70) · 안쪽 (255, 238, 150).
- 결과 초안: `output/boost-flame-20261006/draft_sheet.png`, 미리보기 `sheet_preview.png` · `preview.gif`(70ms/프레임), 폴더 `.gdignore`.
  - 생성기는 원래 `assets/vfx/boost_flame/boost_flame_sheet.png` 에 쓰도록 되어 있다.
  - 이번엔 미적용이라 그 파일을 `output/` 으로 옮기고 `assets/vfx/boost_flame/` 은 지웠다. 그래서 Godot 임포트 파일(`.import`)도 아직 없다.

![초안 시트](../output/boost-flame-20261006/sheet_preview.png)

## 적용 계획

### 1. 리소스
- `python -X utf8 tools/fx/boost_flame_sheet.py` → `assets/vfx/boost_flame/boost_flame_sheet.png`.
- 고정 Godot 으로 `--headless --import`.
- `.import` 는 3D 압축을 끄고 밉맵도 끈다. `assets/vfx/liquid/*.import` 처럼 `compress/mode=0` · `mipmaps/generate=false` · `detect_3d/compress_to=0`.
- PNG 와 `.import` 를 같은 커밋에 넣는다.

### 2. 연출 모듈 `scripts/presentation/boost_flame.gd` (`BoostFlame`)
- 분사구(`j.jet_l` · `j.jet_r`) 하나에 판(QuadMesh) 하나.
  - `top_level` 로 플레이어 자식에 둔다. 분사구 노드 `jet` 는 깜빡임 때문에 `scale.y` 가 계속 바뀌어서, 그 자식으로 두면 같이 찌그러진다.
- **배치:** 판의 위쪽 가장자리를 분사구 입구(`jet.global_position`)에 맞춘다.
  - 긴 축은 불꽃 방향(`-jet.global_basis.y`)을 따르고, 판의 면은 카메라를 향하게 그 축으로만 돌린다.
  - 축: `right = dir × (카메라 - 분사구)`, `normal = right × dir`.
  - `Basis(right·폭, -dir·길이, normal)`. 판 가운데는 `입구 + dir·길이/2`.
- **크기:** 길이 약 0.9m · 폭 약 0.45m (시트 1:2). 세기 `on`(부스터 1, 기 모으기 돌진 `tech.jet_k()`)만큼 길이를 키운다. `on` 이 거의 0 이면 숨긴다.
- **프레임:** 초당 약 14 (레퍼런스 미리보기 70ms).
  - 좌우 분사구는 시작 프레임을 엇갈려 동시에 끊기지 않게 한다.
  - 부스터를 켜는 순간은 1번 프레임부터 시작한다.
- **셰이더:** spatial, `unshaded` · `cull_disabled` · `shadows_disabled`.
  - 시트에서 `frame` (인스턴스 셰이더 매개변수 `instance uniform`) 칸을 읽는다.
  - 가장자리가 또렷한 만화 모양이라 **알파 잘라 내기**(ALPHA_SCISSOR 0.5)로 깊이를 쓰게 한다. 그러면 화면 연기(POST_TRANSPARENT 컴포지터)와 앞뒤가 맞는다.
  - 화면 번짐(glow)이 살짝 걸리도록 색에 약 1.2배를 곱하는 것도 검토한다.
- 판·재질은 인스턴스마다 만들고, 정적 캐시는 셰이더 하나만 둔다.
  - 색이나 크기를 키로 쓰는 캐시는 만들지 않는다 (AGENTS 4절 캐시 증가 주의).
- 끄기: `BoostFlame.on`(static) · 실행 인자 `--boostflame=off`.

### 3. 연결 (기존 코드는 한 줄)
- `player.gd` `_animate_jets(dt, on)` 안에 `BoostFlame.drive(self, [j.jet_l, j.jet_r], on, dt)` 한 줄.
  - 판 노드는 플레이어 메타(`_boost_flame`)에 보관해 플레이어와 함께 사라지게 한다.
- 예전 보라 로봇(`--player=robot`)도 같은 `j.jet_*` 계약이라 그대로 동작한다.
- **기존 원뿔 불꽃**(`MechPlayer._flame` · `Build.robot` 의 `Pal.JET` 원뿔): 시트 불꽃과 겹친다. 적용 뒤 화면을 보고 셋 중 하나로 정한다.
  - 숨긴다
  - 짧게 줄여 안쪽 심지로만 남긴다
  - 그대로 둔다
  - 사용자 확인이 필요하다.
- 유체 연소가스(`FluidSmoke._exhaust`)는 그대로 둔다 (불꽃 = 입구, 연소가스 = 바닥 꼬리).

### 4. 검증
- 화면 없는 테스트 `tests/boost_flame_check.gd`:
  - 부스터를 켜면 판 2개가 보이고, 끄면 숨는다.
  - 판의 위쪽 가장자리가 분사구 입구에서 1cm 안이다.
  - 긴 축이 불꽃 방향과 나란하다.
  - 프레임이 초당 약 14로 돈다.
  - 씬을 다시 불러도 정적 캐시가 늘지 않는다.
- 캡처 `_capture/boost_flame_show.gd` → `output/boost-flame-20261006/`: 허수아비 시험장에서 부스터로 달리기 · 꺾기 · 제자리. 가까이 확대한 사진과 프레임 4장을 시트로 묶는다.
- `run_tests.cmd` 전체와 main · training 자동 플레이(`--bot`)에서 `ERROR` / `SCRIPT ERROR` 가 0인지 본다.

## 열린 결정 (사용자 확인)
- 기존 원뿔 불꽃 처리 (위 3번).
- 색: 레퍼런스 노랑 그대로 vs 메카 분사구 색(`Pal.JET`)에 맞춘 주황/청록 변형.
- 기 모으기 돌진 · 대시 때도 같은 시트를 쓸지.
