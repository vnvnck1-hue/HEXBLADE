# 튜토리얼 괴생명체 B — 카툰 저폴리 모델

사용자가 선택한 카툰 B안(노란 갑각·청록색 몸통·큰 입)을 기준으로 제작했다.
먼저 [정면·우측면·후면 3면도](../output/concepts/tutorial_alien_b_turnaround.png)를 PNG로 저장한 뒤 모델링했다.
3면도는 내장 이미지 생성 도구로 그린 참고 원화다. 생성 원화의 뷰 간 모순은 정면의 입 크기와 측면의 3쌍 다리 배치를 기준으로 절충했다.

## 결과물

- 현재 작업 원본: `models/src/tutorial_alien_b_v10.py` (v1~v9는 이전 제작 기록이며 보존)
- 편집 모델: `output/models/tutorial_alien_b/tutorial_alien_b.blend`
- **카툰 셰이더·조명까지 저장한 장면**: `output/models/tutorial_alien_b/tutorial_alien_b_toon_studio.blend`
- 게임용 모델: `assets/models/tutorial_alien_b.glb`
- 텍스처: `assets/models/tutorial_alien_b_atlas.png` (512×256, GLB에도 포함)
- 카툰 렌더: `output/models/tutorial_alien_b/preview.png`, `model_three_views.png`, `toon_beauty.png`
- 실제 GLB 재임포트 검증: `output/models/tutorial_alien_b/validation.json`

높이 0.356m. 폭 약 0.451m, 길이 약 0.427m. **3,958삼각형**, 메시 10개, 공용 재질 1개, 텍스처 1장. 별도 경량본은 **1,925삼각형**이다.
눈 없음, 다리 정확히 6개, 둥근 이빨 4개(위 2·아래 2). 몸통·등딱지·위턱·아래턱·다리 6개로 분리했다.
발 부착점 6개와 입 부착점, 애니메이션을 위한 피벗을 포함한다. 리깅/애니메이션·전투 로직·본편 스폰은 연결하지 않았다.

## 면과 텍스처

Subsurf·Bevel 모디파이어 없이 적은 정점으로 곡면을 만들고 스무스 노멀을 사용한다.
현재 갑각은 둥근 단면의 겹판이다. 서로 겹친 다리 부품·몸통·갑각 속에 완전히 묻힌 면을 보수적으로 제거했다. 갑각 얼룩, 테두리, 위아래 명암, 몸통의 마디선, 장식 돌기와 발끝의 하이라이트는 아틀라스에 칠했다.
UV는 각 파츠를 아틀라스의 8개 팔레트 영역에 재사용 배치한다. 단일 재질이라 메시별 추가 재질 분할이 없다.

## 원화 대조 후 재제작 (v2)

1차는 원화보다 폭이 넓고 껍질이 얇은 띠, 다리가 막대, 입이 구멍처럼 보였다. 파일 검증 통과를 외형 재현 성공으로 취급한 것이 잘못이었다.
1차 결과는 `output/models/tutorial_alien_b_v1/`에 보존하고, 현재 GLB와 Blender 파일을 새 형상으로 갱신했다.
갑각은 정면 아치와 측면 볼록 곡선을 별도로 정의한 겹판, 위턱은 두꺼운 부피, 아래턱은 둥근 U자 입체로 다시 만들었다.
다리는 청록 관절·짧은 노란 갑각·둥근 회색 발의 세 덩어리로 구성했다. 혀의 볼륨과 네 이빨의 위치도 다시 맞췄다.
곡면은 분석적 커스텀 노멀로 보완하고, 윤곽선은 합성 단계에서 1픽셀 확장한다.

`reference_compare.png`는 행마다 정면/측면/후면, 열마다 **원화 / 실제 Blender 렌더 / 실루엣 겹침**이다.
겹침은 흰색=공통, 빨강=원화에만 있음, 청록=모델에만 있음. `reference_compare.json`은 같은 바닥·높이·배율에서 측정한 보조 지표다.
마스크는 색으로 추정하므로 수치는 완전한 동일성이나 소재·표정 재현의 증명이 아니다. 측면 턱·갑각 끝 곡선, 장식 위치와 손으로 칠한 명암은 여전히 차이가 있다.

## 카툰 스튜디오

EEVEE의 `Diffuse → Shader to RGB → 밝기 ÷3 → 3색 EASE Color Ramp` 결과를 페인팅 아틀라스와 곱한 뒤 Emission으로 출력한다. 램프 위치는 0.16/3, 0.95/3, 2.65/3이며, 저장한 노드와 연결을 재열기 검사한다. v3에서는 원화의 부드러운 명암을 따라 보석처럼 끊기던 명암을 완화했다.
v7은 청록색 영역에 별도의 차가운 3색 램프를 사용한다. 텍스처의 G>R 마스크로 금색/청록색 톤을 나눠 몸통에 갈색 그림자가 섞이는 것을 줄였다. 추가 재질이나 텍스처는 없다.
v8은 이빨용 크림색 3색 램프를 추가했다. 아틀라스의 밝은 R/B 영역으로 이빨을 분리해 어두운 곳에서도 흰 크림색을 유지한다. 반짝이는 사실적 재질이나 추가 재질을 쓰지 않는다.
따뜻한 주광·차가운 보조광·뒤쪽 빛 3개, 무광 배경, 납작한 접지 그림자, Normal 패스 기반 윤곽선 합성을 저장했다.
윤곽선은 렌더 후처리이므로 게임용 GLB 면 수를 늘리지 않는다.
**EEVEE 노드와 합성 설정은 GLB에 옮겨지지 않는다.** GLB는 동일 텍스처의 일반 PBR 재질이며 게임에서 같은 셀 셰이딩을 쓰려면 Godot 재질 적용이 별도로 필요하다.
Blender 파일에는 텍스처가 패킹돼 있어 단독으로 열어 확인할 수 있다.

Blender 5.2의 합성 노드는 [공식 5.0 마이그레이션 문서](https://developer.blender.org/docs/release_notes/5.0/migration/compositor_migration/)에 맞춰 별도 노드 그룹과 Group Output을 사용했다.

## 재생성

프로젝트의 고정 실행기를 사용한다.

```powershell
tools\blender.ps1 model models\src\tutorial_alien_b_v10.py --no-preview
tools\blender.ps1 wait -b --python-exit-code 1 --python tools\blender\tutorial_alien_b_studio.py
tools\blender.ps1 wait -b --python-exit-code 1 --python tools\blender\tutorial_alien_b_compare.py
tools\blender.ps1 wait -b --python-exit-code 1 --python tools\blender\tutorial_alien_b_verify.py
tools\blender.ps1 wait -b --python-exit-code 1 --python tools\blender\tutorial_alien_b_size_review.py
tools\blender.ps1 wait -b --python-exit-code 1 --python tools\blender\tutorial_alien_b_lod.py
tools\blender.ps1 wait -b --python-exit-code 1 --python tools\blender\tutorial_alien_b_verify.py -- --lod
tools\blender.ps1 wait -b --python-exit-code 1 --python tools\blender\tutorial_alien_b_size_review.py -- --lod
tools\blender.ps1 wait -b --python-exit-code 1 --python tools\blender\tutorial_alien_b_oral_probe.py
tools\blender.ps1 wait -b --python-exit-code 1 --python tools\blender\tutorial_alien_b_oral_probe.py -- --lod
tools\blender.ps1 wait -b --python-exit-code 1 --python tools\blender\tutorial_alien_b_export_parity.py
tools\blender.ps1 wait -b --python-exit-code 1 --python tools\blender\tutorial_alien_b_export_parity.py -- --lod
tools\godot.ps1 wait --headless --import
tools\run_tests.ps1
```

`.blend` 안에서 F12는 설정된 카툰 렌더다. 원형 윤곽의 각짐은 초저폴리 실루엣을 유지한 결과다.
루트 `tutorial_alien_b_model.cmd`를 더블클릭하면 셰이더·조명이 저장된 Blender 장면을 연다.
별도 동시 작업 `bug_chomper`와 다른 모델이며 해당 파일은 보존했다.

검증: v2 고정 Godot 4.7.2 임포트 성공. 최종 GLB를 Blender에 재임포트해 3,060삼각형·공용 재질 1개·UV·퇴화 삼각형 0·높이·접지·발 부착점을 확인했고, 저장한 스튜디오 파일의 셰이더·텍스처 패킹·3광원·합성 설정도 검사했다. v1의 전체 회귀 19종 PASS 결과는 외형 품질의 근거가 아니다.
v2 작업 중 전체 회귀 21종의 테스트 판정은 PASS였으나, `spider_check`에서 `The axis Vector3 ... must be normalized` ERROR가 반복되었다. 거미 코드는 이 모델 작업에서 수정하지 않았으며, 오류 없는 전체 회귀로 취급하면 안 된다. Blender의 사용자 썸네일 캐시 저장 오류는 실제 PNG/BLEND 저장과 재열기 성공 여부를 분리해 확인했다.

## 원화 대조 3차 (v3, 진행 중)

v2 결과는 `output/models/tutorial_alien_b_v2/`에 별도로 보존했다. v3 스크립트와 결과(`output/models/tutorial_alien_b_v3/`)도 남겼다.
위턱을 타원 단면의 닫힌 스윕, 아래턱을 비선형 앞뒤 곡선과 접선에 수직인 단면으로 재구성했다.
정면 원화의 아래턱 폭·입 내부 폭을 다시 재서 몸통 양옆이 드러나게 축소했으며, 혀는 두 둥근 덩어리로 바꿨다.
이마 돌기는 떠 있는 타원 대신 갑각에 이어지는 테이퍼 형상이다. 발의 수직 윤곽과 다리 갑각의 둥근 선에 정점을 추가했고, 다리 갑각의 얼룩을 제거했다.
3,828삼각형은 실루엣 곡률을 보강한 수치이며 Subsurf/Bevel 모디파이어·윤곽선 추가 메시를 쓰지 않는다.

v3 실루엣 추정 IoU: 정면 0.8751, 측면 0.7370, 후면 0.8806. **측면은 v2의 0.7620보다 낮으므로 v3 전체 외형을 완성으로 취급하지 않는다.**
특히 위턱/아래턱의 측면 둥근 외곽, 갑각 끝의 돌출·세 갑각의 뒤쪽 노출 비율, 페인팅 명암이 원화와 다르다. 이 목표는 계속 진행 중이다.
최종 v3 저장 파일의 셰이더·패킹·GLB 재임포트·UV·6족·접지·퇴화 삼각형 0은 검증 PASS, Godot 임포트 성공. 이 구조 검증은 원화 재현 성공 판정과 별개다.

## 원화 대조 4차 (v4, 미완성)

v3 결과를 따로 보존하고 실제 형상과 셰이더를 수정했다.

- 위턱의 단면을 앞으로 숙인 타원으로 바꾸고 옆 모서리는 뒤로 물렸다. 아래턱은 앞뒤 곡선을 다시 맞췄다.
- 몸통 앞면을 강제로 납작하게 자르지 않고 둥근 몸통을 입 뒤에 배치했다. 혀는 하나의 둥근 메시와 중앙의 얕은 홈으로 만들었다.
- 네 이빨 끝은 작은 링으로 둥글게 닫고, 위쪽 뿌리는 위턱 안으로 넣었다.
- 측면 입 안쪽 벽을 추가하고 안쪽을 향한 면만 보이게 해 앞쪽에서 막처럼 드러나지 않게 했다. 열린 면의 방향과 GLB back-face culling을 명시했다.
- 갑각의 앞뒤 겹침, 후면 갑각의 돔형 윤곽, 모서리 곡률과 2cm 테두리를 조정했다. 앞 갑각 안쪽은 팬으로 막았고, 몸통 속에 완전히 묻힌 관절 삼각형은 제거했다.
- 실제 저장 장면의 조명값을 `tutorial_alien_b_light_probe.py`로 측정했다. diffuse 밝기 10/50/90 백분위는 약 0.32/1.29/2.65였다. 기존 밝은 색 문턱 0.65는 대부분의 곡면을 한 색으로 잘라냈다. 새 3색 램프 위치는 0.16/0.95/2.65로 넓혀 곡면 명암이 남게 했다.

이 수정은 완성 판정이 아니다. v4도 정면의 입/턱 비율과 이마 돌기, 측면 위턱 외곽, 후면 세 갑각의 노출 비율, 원화처럼 둥근 발/이빨과 칠을 더 맞춰야 한다. v3보다 모든 시점이 좋아진 것도 아니다. 파일 구조 검사와 회귀 PASS를 원화 재현 성공으로 취급하지 않는다.
최종 검증·대조 수치는 `validation.json`·`reference_compare.json`을 참고한다. 게임 적용·애니메이션 연결·커밋·푸시는 하지 않았다.

최종 v4 실루엣 추정 IoU는 정면 0.8348 / 측면 0.7578 / 후면 0.8447이다. v3의 정면/후면 수치보다 낮으며, 이 수정본을 원화 재현 완료로 판정하지 않는다. 저장 파일과 최종 GLB 재임포트 검사 PASS(3,984삼각형·재질 1개·UV·패킹·6발 접지·퇴화 면 0), 최종 Godot 임포트와 `blender_models_check` PASS. 수정 중 전체 회귀 21종 PASS였고, 마지막 갑각 마감/숨은 면 제거 이후 모델 검사를 다시 실행했다. 게임 씬 코드는 변경하지 않았다.

## 원화 대조 5~6차 (v6, 진행 중)

v4 결과는 `output/models/tutorial_alien_b_v4/`, v5는 `output/models/tutorial_alien_b_v5/`에 모델/원본/렌더 스냅샷으로 보존했다. 아래는 당시 v6 기록이며 최신 파일은 v9이다.

- v5에서 갑각을 얇은 패치 대신 닫힌 볼록 단면의 겹판으로 바꿨다. v6에서는 겹침 위치와 곡률을 조정하고 뒤에서 몸통이 갑각 사이로 솟지 않게 했다.
- 위턱의 세로 두께를 늘리고 앞뒤 길이를 줄였다. 옆 끝은 뒤로 물려 앞 갑각과 연결했다. 아래턱은 깊이와 두께를 부위별로 바꿔 날개처럼 튀던 접점을 줄였다.
- 입 안쪽 가장자리를 위턱 안으로 넣어 붉은 면의 돌출을 줄였다. 혀·아래 이빨 높이를 낮추고, 네 이빨의 둥근 끝과 뿌리를 조정했다.
- 이마 돌기 뿌리를 갑각 표면에 이어 붙이고 턱 아래에 청록색 배 볼륨을 보강했다. 마디선은 텍스처에 칠했다.
- 다리 관절/갑각/발과 몸통이 겹치는 면, 갑각에 깊이 묻힌 돌기의 면은 **면의 모든 정점이 다른 부피 안에 들어간 경우에만** 제거했다. 보이는 윤곽을 일괄 Decimate로 줄이지 않았다. 커스텀 노멀도 제거 후 다시 계산했다.
- 셰이더에서 diffuse 밝기를 3으로 나눈 뒤 램프에 넣는다. 저장된 스케일과 세 램프 위치를 별도 검사했다.

최종 v6 실제 렌더의 추정 IoU는 정면 **0.8695**, 측면 **0.8280**, 후면 **0.8792**다. v4의 세 시점보다 높지만, 이것은 실루엣 보조 지표이며 원화와 동일하다는 증거가 아니다. 특히 앞/중간 갑각의 측면 기울기와 노출 비율, 둥근 발/장식/이빨의 윤곽, 원화의 붓질·칠한 하이라이트는 차이가 남아 있다. **전체 목표는 진행 중이며 완료로 판정하지 않는다.**

최종 3,996삼각형 GLB 재임포트 검사 PASS(재질 1개·UV·퇴화 삼각형 0·높이·접지·6개 발 부착점). 최신 저장 스튜디오의 셰이더/밝기 정규화/패킹/3광원/합성 검사 PASS. 고정 Godot 4.7.2 최신 임포트 성공. 수정 중 전체 회귀 **21종 PASS**(ERROR 출력 없음), 마지막 입/혀 위치 변경 후 Blender 재임포트 검증·Godot 재임포트·`blender_models_check`를 다시 실행해 PASS. 게임 씬 코드·스폰·애니메이션 연결은 변경하지 않았다. Blender의 썸네일 캐시 OpenImageIO 오류는 남지만 실제 PNG/BLEND 저장과 재열기 검사 성공을 확인했다.

## 원화 대조 7차 (v7, 진행 중)

v6 원본·GLB·Blender 파일·렌더·검증 기록은 `output/models/tutorial_alien_b_v6/`에 보존했다.

- 발·장식·네 이빨을 80삼각형의 지오데식 타원체로 바꿨다. 이전 위도 링보다 정점을 고르게 배치해 면 수를 줄이면서 둥근 윤곽을 보강했다.
- 앞/중간/뒤 갑각의 기울기·겹침·돔 높이를 수정했다. 이마 돌기 뿌리와 뒤쪽 청록 장식을 갑각에 붙였다.
- 아래턱 안쪽 높이를 낮추고 양쪽 끝을 올렸다. 혀의 정점 배치와 중앙 홈을 바꿔 두 볼록한 덩어리를 드러냈고, 변형에 맞춰 커스텀 노멀을 다시 계산했다.
- 청록 장식의 밝은 타원 하이라이트와 몸통용 별도 셰이더 톤을 추가했다. 눈을 만든 것이 아니다.
- 몸통 깊숙이 들어간 갑각 면만 추가 제거했다. 원본 모델에는 일괄 Decimate를 적용하지 않았다.

최신 실제 렌더의 실루엣 추정 IoU는 정면 **0.8861**, 측면 **0.8557**, 후면 **0.8899**다. 비교용 정면/측면/후면 카메라와 배율은 유지했다. 별도 3/4 감상용 카메라만 원화의 낮은 시점에 가깝게 내렸다.
수치 향상은 동일성의 증명이 아니다. 원화보다 등딱지 끝이 직선적이고 이마 돌기가 얇으며, 입·혀·발의 윤곽과 손으로 칠한 하이라이트가 다르다. **원화 재현 목표는 아직 완료가 아니다.**

최신 3,560삼각형 GLB 재임포트·UV·재질 1개·퇴화 면 0·6발 접지와 저장한 셰이더/패킹/조명/합성 검사 PASS. Godot 4.7.2 임포트 성공. 이는 파일 구조 검사이며 외형 품질 판정이 아니다. Blender 썸네일 캐시 OpenImageIO 오류와 실제 파일 저장/재열기 성공은 구분한다.
최종 v7 원본/경량본 임포트 뒤 전체 회귀 **21종 PASS**(표시된 ERROR/SCRIPT ERROR 없음). 게임 씬·스폰·애니메이션 코드는 변경하지 않았다.

### 작은 화면과 별도 경량본

`small_screen_review.png`는 실제 Blender 메시를 게임 방향의 카메라에서 투영 높이 64/96/128px로 렌더한 시트다. 원화를 축소한 이미지나 Godot 플레이 화면이 아니다. 투영 치수는 같은 이름의 JSON에 기록했다.

v7 당시 별도 경량본 `assets/models/tutorial_alien_b_lod.glb`는 **1,718삼각형**이었다. 원본에서 파츠별 Decimate 후 원래 곡면 노멀을 전달하고 크기·접지를 보정했다. 당시 3,560삼각형 원본은 v7 스냅샷에 보존했다. 경량본도 10메시·재질 1개·공유 아틀라스와 피벗/발 부착점을 유지한다. 최신 경량본 수치는 아래 v8 기록을 따른다.
편집/셰이더 장면은 `tutorial_alien_b_lod.blend`·`tutorial_alien_b_lod_toon_studio.blend`, 렌더는 `toon_beauty_lod.png`·`small_screen_review_lod.png`, 구조 검증은 `validation_lod.json`이다. 재임포트·UV·퇴화 면 0·6발 접지·셰이더 검사 PASS.
**무손실 경량화가 아니다.** 큰 렌더와 128px에서는 각짐이 더 보인다. 아주 작은 개체를 위한 비교 후보이며 본편에 자동 적용하지 않았다. 경량 GLB 역시 PBR 재질이고 Blender 셀 셰이더는 별도 저장 장면에만 있다.

## 원화 대조 8차 (v8, 진행 중)

v7 원본·GLB·Blender 파일·렌더·검증 기록을 `output/models/tutorial_alien_b_v7/`에 보존했다.

- 발과 이빨은 가장 넓은 외곽에 12정점이 놓이는 타원체로 변경했다. 작은 지오데식 형상의 불균일한 외곽을 보완하려고 면을 재배분했고, 이빨은 위/아래 방향으로 완만하게 테이퍼했다.
- 위턱 단면 수를 16→12로 줄여 절약한 면을 혀의 좌우 굴곡(16→24정점)에 사용했다. 전체 원본은 3,878삼각형으로 4천 이내다.
- 위턱을 중앙에서 12mm 높이고 조금 얇게 하여 입이 크게 벌어진 형태를 보강했다. 입 안쪽과 윗니 위치도 함께 변경했다.
- 이마 돌기 중간 단면을 두껍게 하고 갑각의 밝은 붓질을 굽혔다.
- 이빨에 따로 밝은 크림색 톤을 적용해 갈색 그림자가 강하게 섞이는 것을 줄였다. 원본·경량본 저장 장면 모두 해당 노드와 마스크를 재열기 검사했다.
- 갑각 양끝을 좁혀 둥글게 만드는 시도는 렌더에서 뾰족한 주름이 생겨 **채택하지 않고 되돌렸다**. 갑각 끝의 직선적인 모습은 미해결이다.

최종 원본 **3,878삼각형**, 경량본 **1,891삼각형**. 둘 다 높이 0.356m, 폭/길이 약 0.451/0.421m, 10메시·재질 1개·512×256 아틀라스다. 실제 저장 장면과 GLB 재임포트 검사 PASS, Godot 4.7.2 최신 임포트 성공. 두 작은 화면 비교 시트도 최신 메시로 다시 렌더했다.
최종 실루엣 추정 IoU는 정면 **0.8870**, 측면 **0.8439**, 후면 **0.8899**. **측면은 v7의 0.8557보다 낮다.** 큰 입/둥근 발 등의 부분 개선이지 모든 시점의 개선이나 원화 재현 완료가 아니다. 현재 가장 큰 미해결 항목은 갑각 끝/측면 곡선, 입·혀·발의 부드러운 외곽과 원화의 손그림 명암이다. 본편 적용·애니메이션 연결·커밋·푸시는 없다.
v8 모델 임포트 이후 전체 회귀 **21종 PASS**(표시된 ERROR/SCRIPT ERROR 없음). 마지막 크림색 톤은 Blender 스튜디오에만 적용됐으며 원본/경량본 저장 파일 검사를 다시 통과했다. 경량본 갱신 중 이전 장면을 먼저 읽은 검사는 실패했으나, 생성 완료를 확인하고 최종 저장 장면을 다시 읽은 검사는 PASS다.

## 원화 대조 9차 (v9, 진행 중)

v8 원본·GLB·Blender 파일·렌더·검증 기록은 `output/models/tutorial_alien_b_v8/`에 보존했다.

- 갑각의 앞뒤 중심선에 비선형 곡률을 추가했다. 앞·중간·뒤 갑각을 각각 반대 방향으로 약하게 굽혔고, 돌기 위치와 묻힌 면 검사에도 같은 변형을 반영했다. 강한 굽힘은 틈을 드러내므로 낮췄다. 새 갑각 표면 분할은 추가하지 않았다.
- 아래턱 중심선 폭 0.126→0.140m, 양끝 높이 0.149→0.165m로 바꾸되 중앙 바닥 높이는 유지했다. 위턱 옆까지 올라오는 U자 테두리로 입 둘레를 이어 원화의 둥근 프레임을 보강했다.
- 앞다리 관절을 바깥쪽으로 12mm, 아래로 10mm 옮겨 입 안에 청록 관절이 비치던 것을 줄였다. 발 부착점은 유지했다.
- 혀는 24각/5단에서 20각/6단으로 면을 재배분했다. 위쪽 두 곡면에 높이 샘플을 집중했다.
- 먼 입 모서리는 두 열린 볼 팬으로 막히지 않았다. 실제 저장 장면의 광선 검사에서 배경 노출을 발견했다. 팬을 **닫힌 안쪽 지향 타원체**로 교체했다. 가까운 면은 뒷면 숨김으로 보이지 않고 먼 안쪽 면이 입 내부를 채운다. 추가 내부 치아/눈/사실적 잇몸은 없다.

최종 원본 **3,944삼각형**, 경량본 **1,917삼각형**. 10메시·공유 재질1개·512×256 아틀라스·6발 접지·퇴화 면0 및 저장 셰이더/패킹/3광원/합성 검사 모두 PASS. 원본/경량본 카툰 장면 모두 `oral_corner_probe*.json`의 같은 다섯 위치를 검사해 배경 노출 없이 턱/입 내부 면에 닿았다. 광선 검사는 재질의 뒷면 숨김을 반영한다. 검사한 위치의 근거이며 모든 시점의 완전한 폐쇄성 증명이 아니다. 큰 렌더와 작은 화면 시트도 실제 최신 메시로 갱신했다. Godot 4.7.2 임포트 성공.

최신 실루엣 추정 IoU는 정면 **0.8873**, 측면 **0.8464**, 후면 **0.8902**. v8보다 조금 높지만 원화 동일성의 증거가 아니다. 입 프레임 연결과 실제 구멍은 개선했으나 갑각의 부드러운 외곽, 발/장식 실루엣, 페인팅의 하이라이트와 붓질 차이가 남는다. **외형 재현 목표는 계속 진행 중이다.** 게임 코드·스폰·애니메이션 연결·커밋·푸시는 없다.

v9 최종 두 모델 임포트 이후 전체 회귀 **23종 PASS**(표시된 ERROR/SCRIPT ERROR 없음). 새로 추가된 다른 작업의 배경 테스트도 포함한 개수다. 본 작업에서 게임 씬/공용 코드는 수정하지 않았다.
`export_parity*.json`은 최종 GLB의 메시/노멀/UV/내장 텍스처를 새로 불러와 **같은 Blender 카툰 셰이더·카메라·조명**으로 렌더한 대조다. 평균 RGB 절대 차이는 원본 0.0000256, 경량본 0.0000143이며 두 검사 PASS. 결과 `glb_toon_parity*.png`. 이는 내보내기 과정의 시각 보존 근거이며 원화 재현 성공이나 Godot 카툰 셰이더 검증이 아니다.

## 원화 대조 10차 (v10, 진행 중)

v9 원본·GLB·Blender·렌더·검증을 `output/models/tutorial_alien_b_v9/`에 보존했다.

- 이마의 얇은 세로 돌기를 Y/Z 곡선을 따라 뒤로 말린 넓은 갑각 조각으로 다시 만들었다. 곡면 미분으로 노멀을 계산하고, 아래쪽 볼륨을 내려 기존 갑각에 뿌리가 이어지도록 했다. 기존 단면/정점 수는 유지했다.
- 갑각 양끝 단면을 22%만 완만하게 줄여 끝의 선을 수정했다. 크게 줄인 초기 시도는 외곽을 과도하게 좁혀 채택하지 않았다.
- 위턱 중앙의 앞뒤 반경을 8mm 늘려 측면 앞쪽 볼륨을 보강했다.
- 다리 갑각을 더 넓고 짧은 타원체로 바꾸고 발을 조금 앞으로 벌렸다. 관절을 모두 낮춘 초기 시도는 3면도 대조에서 다리 위치가 어긋나 **원래 관절 높이로 되돌렸다**. 그 시도는 `output/models/tutorial_alien_b_v10_trial_low_legs/reference_compare.*`에 남겼다.
- 크림색 붓질의 폭/곡선을 비대칭으로 바꾸고 갑각 끝에 늘어나던 어두운 텍스처 경계를 제거했다. 텍스처 수·해상도·재질 수는 늘리지 않았다.

최종 원본 **3,958삼각형**, 경량본 **1,925삼각형**, 높이 .356m·폭/길이 .451/.427m. 실제 두 GLB 재임포트·UV·공유 재질1개·퇴화면0·접지·6발 부착점과 저장된 EEVEE 셰이더/패킹/3광원/합성 검사 PASS. Godot 4.7.2 임포트 성공. 최신 원본/경량본의 64/96/128px 실제 메시 시트도 저장했다. 이는 Blender 검토용이며 Godot 플레이 화면이 아니다.

최종 실루엣 추정 IoU는 **정면 .8865 / 측면 .8469 / 후면 .8925**다. v9 대비 측면/후면은 소폭 높고 정면은 .0008 낮다. 지표 최적화만으로 성공을 판단하지 않는다. 실제 렌더에서 돌기의 뿌리/굽힘과 다리 부피는 달라졌지만, 원화의 두툼한 꽃잎 같은 갑각과 둥근 입/혀/발 윤곽, 밝고 부드러운 손그림 채색에는 여전히 차이가 있다. **완성으로 판정하지 않았으며 목표는 계속 진행 중이다.**

같은 Blender 셰이더·조명으로 최종 GLB의 메시/노멀/UV/내장 텍스처를 다시 렌더한 대조는 원본/경량본 모두 PASS(평균 RGB 차이 .0000197 / .0000135). 원화 재현 성공이나 Godot 카툰 재질 검증의 근거가 아니다. 입 모서리 동일5위치의 광선 검사도 두 모델 모두 배경 노출 없이 면에 닿았다. Blender 썸네일 캐시 오류는 남으나 실제 모델·렌더 저장과 재열기는 성공했다.

게임 코드·본편 스폰·애니메이션 연결·커밋·푸시는 없으며 다른 작업 파일은 보존했다.

## 3면도 생성 프롬프트 (내장 image_gen)

참조 이미지: `output/concepts/tutorial_alien_basic_3concepts_cartoon_v2.png`.

```text
Create a MODELING TURNAROUND SHEET of ONLY creature B, the middle yellow-shell turquoise six-legged cartoon alien from the reference. Preserve its exact appealing cartoon design, exaggerated squat proportions and color palette. Do not include A or C.
One landscape sheet with THREE equally scaled strict ORTHOGRAPHIC views aligned to the same ground baseline: FRONT on left (perfectly symmetrical), RIGHT SIDE in middle (head and open mouth pointing left), BACK on right (perfectly symmetrical). No perspective, no 3/4 views. Label only FRONT, SIDE, BACK in small clear letters above.
Character construction: low squat turquoise pear-shaped insect body, large friendly horizontal open mouth occupying front face, coral tongue and burgundy simple mouth interior. Exactly FOUR widely spaced rounded ivory stubby teeth in total (2 upper, 2 lower), NO extra teeth. NO eyes. Exactly SIX very short chunky legs arranged as three bilateral pairs. Turquoise upper legs, mustard shell sleeves and blunt dark-gray rounded feet. Golden yellow overlapping scalloped shell plates on the back, three broad plates along its length and a large curved yellow brow/upper jaw above mouth, small upward shell fin/ridge at center. Turquoise round shell bumps are decorative, NOT eyes. Low-poly-friendly simple big masses; small ochre spots painted on shell rather than complex geometry. Broad lower yellow jaw rim. Body around 70% of height, feet close to floor. Model intended about 0.36 meters tall; do not write dimensions.
Maintain consistent actual construction between views: same plate count, proportions, leg placement and bump placement; side view shows three legs on visible side; front/back views show six symmetric legs with depth overlap. Keep mouth big and cheerful, shell soft and chunky. Clean bold outlines, 2-3 tone cel shading, smooth matte cartoon finish, flat light warm-gray background with thin faint horizontal alignment guides, minimal soft oval ground shadows. Enough blank space between views to crop separately. No slime, no wet flesh, no anatomical gums, no realistic pores, no horror, no dense teeth, no claws. This is a cute pathetic tutorial enemy, not a boss.
```
