# 현재 색감을 유지한 핸드페인팅 배경 텍스처 3안

2026-10-06. 사용자 요청: 현재 게임 배경의 명도·채도를 거의 그대로 유지하고, 하스스톤을 참고한 손그림 재질을 실제 배경 프랍에 덮어 쓸 수 있게 제작.

## 결과

| 안 | 방향 | 표현 |
|---|---|---|
| A | 부드러운 도장 금속 | 넓은 붓 명암, 차분한 판 중앙, 작은 모서리 눌림 |
| B | 둥근 베벨·두꺼운 도장 | 기존 베벨의 둥근 밝고 어두운 면, 두꺼운 도막 느낌 |
| C | 선택적 마모·정비 흔적 | 짧은 얕은 홈, 비대칭 모서리 벗겨짐, 회청색 밑도장 |

안별 14장, 총 42장. 바닥·높은 벽·반쪽 벽·낮은 벽·엄폐·기둥·옆판·벤치·사물함·환기구·탱크·직선 배관·곡선 배관·설비 기둥을 포함한다. 녹·따뜻한 주황 금속·목재·석재로 소재를 바꾸지 않았다.

최종 측정: 실제 UV 픽셀 전체 평균 기준 HSV 명도 차이 최대 **0.1894%p**, 채도 차이 최대 **0.0755%p**. 최종 파일 42장 모두 2048² RGB, 생성 원본은 모두 1254²이며 원본 복사 SHA256 동일. 작고 누락된 UV에 현재 기준색을 보존한 비율은 최대 **0.5193%**. 원본 GLB 해시 동일, 바닥 반대 가장자리 RGB 차이 0. 16장 렌더는 종료0, ERROR/SCRIPT ERROR0. 전체 회귀 46종 중 43종 PASS/3종 FAIL이며 상세는 아래와 validation을 참조한다.

## 적용할 파일

- `png/A`, `png/B`, `png/C`: **최종 적용용 2048×2048 RGB PNG**. 기존 베이스컬러와 같은 파일명이다.
- `shared_emission`: 기존 환기구·탱크·설비 기둥의 발광 PNG 3장, 바이트 동일 복사.
- `comparison_walls.png`, `comparison_service.png`: 현재/A/B/C의 동일 모델·구도·조명 비교.
- `comparison_detail.png`: 벽과 엄폐물 근접 비교.
- `previews`: 원본 GLB에 직접 연결한 1920×1080 캡처 16장. `lit`은 조명 있음, `direct`는 무조명.
- `manifest.json`: 모델별 원래 GLB·텍스처 경로, 최종 PNG 해시, 명도·채도 측정값과 보정 내역.
- `validation.json`: 최종 규격·해시·원본 모델 보존·반복 가장자리·렌더와 기존 테스트 결과.
- `masters`: 내장 imagegen 생성 원본. **적용용 파일은 `png` 폴더**이며 masters는 제작 참조용이다.
- `references`: 현재 유효 베이스컬러와 실제 UV 커버리지를 2048²로 구운 입력 자료. 캡처 좌표계여서 위아래 방향이 적용 PNG와 반대다.
- `prompts.json`, `sources.json`: 실제 imagegen 프롬프트와 생성 원본 경로.

## 모델에 연결하는 방법

1. 원하는 안의 PNG를 해당 모델의 Base Color / Albedo 텍스처 슬롯에 지정한다. `manifest.json`의 모델·파일 대응을 따른다.
2. **바닥 외 13종은 원래 GLB의 UV 그대로** 사용한다. 모델링·UV를 다시 펴거나 새로 배치할 필요가 없다. UV 외부에는 12px 색 패딩을 넣었다.
3. **F01 바닥은 기존 게임의 월드 XZ 4m 반복 방식**이다. 한 PNG에 2m 판 4개가 들어간다. 샘플 좌표는 `(world_position.xz - offset) / 4.0`이고 repeat를 켠다. F01의 일반 모델 UV 슬롯에만 넣는 방식과 다르므로 기존 바닥 투영을 유지한다. 반대쪽 가장자리 RGB는 정확히 맞췄다. 맵 전체에서 4m 무늬가 반복된다.
4. 텍스처 색상 공간은 sRGB/Base Color, 틴트는 흰색, mipmap과 선형/이방성 필터를 사용한다. 기존 roughness와 발광은 유지한다. 노멀·높이·새 roughness 맵은 만들지 않았다. 홈과 베벨은 베이스컬러에 그린 표현이며 실제 형상은 기존 모델 그대로다.
5. 현재 게임의 붓 혼합·절차 마모·재착색을 **이 PNG 위에 다시 적용하면 색감이 달라진다**. 이 파일에는 현재 유효 베이스컬러의 색이 이미 반영되어 있다. 런타임 연결 시 직접 PNG를 샘플링하고, 기존 `handpaint`는 끄며 색상 배율은 중립으로 둔다. 실제 중립 설정 예시는 `preview.gd`의 `_add`와 `_floor`에 있다. 조명·발광은 별도로 유지한다.
6. 이 폴더는 `.gdignore`로 본편 임포트에서 제외했다. 실제 적용 단계에서 필요한 최종 PNG를 리소스 폴더로 옮기고 `.import`까지 함께 관리한다.

## 색 유지와 제작 방식

원래 PNG만으로는 현재 게임의 색을 재현하지 못해, 작업 시작 당시 현재 BrawlLook/청보라 재질의 **유효 ALBEDO**를 실제 UV에 구웠다. 동적 조명·발광을 제외한 색이 기준이다. 각 기준 이미지를 내장 imagegen에 직접 입력하여 42장을 각각 재작화했다.

생성 원본은 모델이 반환한 해상도 그대로 보존했다. 최종 파일에는 2048² 리샘플링, 원래 UV 커버리지 정리, 캡처 세로 방향 정규화, UV 영역별 평균 HSV V/S 보정, 색 패딩을 수행했다. 바닥의 반복 가장자리 8px 범위는 연결용으로 맞췄다. 붓결·홈·마모를 별도 프로그램이나 셰이더로 새로 그리지 않았다. 생성 과정에서 사라진 아주 작은 UV 픽셀은 현재 기준색으로 보존했고, 비율은 모델마다 manifest에 기록했다.

`delta_v`와 `delta_s`는 실제 UV가 차지하는 픽셀의 **평균** 차이다. 픽셀별 색·명암이 모두 같다는 뜻은 아니다. 일부 색상과 작은 볼트·홈의 디테일은 생성 재표현이 있다. 게임의 동적 조명 아래 모든 순간의 화면 밝기를 동일하게 보장하는 수치도 아니다.

하스스톤의 큰 면 명암·붓질·둥근 모서리 표현을 방향으로 삼았다. 외부 작품 이미지는 생성 입력으로 사용하지 않았다. 참고한 작가 설명: [Blizzard의 Ben Thompson 아트 소개](https://hearthstone.blizzard.com/en-us/news/13023802/hearthside-chat-art-with-ben-thompson-2-25-2014), [Ben Thompson의 The Box](https://benthompsonart.artstation.com/projects/d88Ro1), [Tiffa Chiu의 게임 보드 작업](https://tiffachiu.artstation.com/projects/8wAA0O).

## 검증과 범위

고정 Godot 4.7.2 표준 Forward+ 실행기를 통해 원본 GLB 14종에 최종 PNG를 직접 연결했다. 현재/A/B/C를 같은 BrawlLook 태양·환경광, 동일 카메라와 배치로 렌더한다. 비교 시 동적 light pool은 끈다. 생성 PNG를 셰이더로 재그리는 비교가 아니다.

본편 자동 플레이 30초(seed4, bot+dronebot)는 종료0, ERROR/SCRIPT ERROR0. 종료 시 ObjectDB 1개 누수 경고가 있었다. 기존 전체 회귀는 3종 실패: `diagonal_cutin_check`의 없는 보이스 7항목, `infest_check`의 포낭 밀어냄 1항목, `terrain_jump_check`의 턱 이동 2항목. 헤드리스 RID 오류도 로그에 남았다. 배경 검사들은 PASS지만 전체 회귀를 PASS라고 기록하지 않는다. 원본 게임 코드와 본편 텍스처는 이번에 변경하지 않았고, 새 텍스처는 독립 스튜디오에만 연결했다.

기존 10월 5일 롤백 상태·이전 시안·다른 작업은 보존했다. **본편 교체·커밋·푸시 없음.**

## 다시 렌더

프로젝트 루트에서:

```powershell
powershell -ExecutionPolicy Bypass -File tools/godot.ps1 wait --fixed-fps 60 -s res://output/hearthstone-prop-textures-20261006/preview.gd
```

출력은 이 폴더의 `previews`에 저장된다. `pack.mjs`는 Node+sharp로 최종 PNG와 manifest를 다시 만들며, `finish.mjs`는 전체 캡처 후 규격·해시를 검사하고 비교 이미지와 validation을 만든다. 기존 프로젝트의 고정 Godot 실행기를 유지한다.
