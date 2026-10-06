# Substance 3D Painter 리서치 — 청보라 스타일라이즈드 철판

2026-10-06. 새 그림을 제작하기 전에 Adobe 공식 문서와 실제 Painter 재질 작업을 읽고 공개 원본 네 장을 확인했다. Painter는 도구이고 고유한 단일 그림체는 아니다. 이번 방향은 사용자 요청인 큰 붓·단순한 면을 유지하는 **스타일라이즈드 도장 금속**이다.

## 공식 자료에서 확인한 내용

- [Japanese animation style with Painter](https://www.adobe.com/learn/substance-3d-painter/web/japanese-animation-style-with-painter?learnIn=1): Fill Layer로 시작하고 작은 노이즈를 줄여 단순한 형태로 만든다. Blur 뒤 Histogram Scan으로 형태를 정리하는 예제다. 큰 형태와 작은 형태를 나눠 작업한다. 예제의 러프니스 약 0.5는 해당 작업의 선택이며 모든 재질의 고정 규칙이 아니다.
- [Metal Edge Wear](https://experienceleague.adobe.com/en/docs/substance-3d-painter/using/effects/generators/metal-edge-wear): 곡률·AO·위치·월드 노멀 등의 입력으로 마모 마스크를 만든다. 모서리 형태와 접근하기 어려운 부분을 구분한다. 이번 그림 생성에서 실제 모델 베이크나 이 필터를 실행한 것은 아니다.
- [PBR Guide Part 2](https://www.adobe.com/learn/substance-3d-designer/web/the-pbr-guide-part-2?learnIn=1): 도장 코팅과 노출 금속을 서로 다른 표면으로 취급한다. 러프니스가 넓고 흐린 반사와 좁고 선명한 반사를 구분한다. 실제 PBR은 베이스컬러·메탈릭·러프니스·노멀 등 채널과 조명에 의해 표현된다. 생성 PNG 한 장을 완성 PBR 재질 세트로 주장하지 않는다.
- [Painter Stylization](https://experienceleague.adobe.com/en/docs/substance-3d-painter/using/effects/filters/advanced-filters/stylization): 붓 크기·양·면 방향 정렬·색·거칠기·모서리/홈과 베이크 조명 등의 조정이 제공된다. 도구에서 스타일라이징과 채널 구분이 가능하다는 근거이지 이번 생성 그림에 해당 필터를 적용했다는 뜻은 아니다.

## 실제 작가 이미지

[Alberto Ángel Manzano — Stylized Metal / Substance Smart Material](https://manzanoidus.artstation.com/projects/Vdo40g). 작가는 이 재질을 Painter로 만들었다고 명시하고 Fortnite와 비슷한 인상을 목표로 설명한다. 공개 원본 `images/manzano_01.jpg`~`03.jpg`는 재질 구체, `04_painter.jpg`는 실제 Painter 화면이다. URL·해시·크기는 `images.json`에 보관했고 네 장 모두 육안 확인했다. 금속 시트 UV가 아닌 **구체에 적용된 렌더와 작업 화면**으로 구분한다. 참고 이미지는 로컬 자료로 보존하고 공개 저장소 커밋 대상에서 제외했다. 재질 상품이나 파일을 구매/다운로드하지 않았다.

화면에서 관찰한 점: 차분한 도장면, 매끈한 큰 반사 면, 형태가 단순한 벗겨짐, 접합부의 깊이와 모서리 강조. Painter 레이어 패널에는 Base, Edges, Roughness Var가 보인다. 세부 레이어 파라미터나 실제 원본 프로젝트 구조는 확인하지 않았다.

## 새 철판에 옮길 기준

1. 기존 네 판·볼트·청보라 팔레트와 전체 밝기 균형 유지.
2. 큰 붓 면을 유지하되 판 전체의 반복 대각선 덧칠보다 도장면 자체의 큰 색 덩어리와 표면 차이를 설계.
3. 도장과 노출 금속이 경계에서 읽히게 단순한 일부 벗겨짐을 배치하고, 볼트·베벨에 재질 차이를 표현.
4. 넓은 면은 조용하게, 모서리와 접합부에 디테일 집중. 미세 노이즈·과도한 녹·빽빽한 잔긁힘 제외.
5. 최종 산출물은 직접 사용할 수 있는 평면 바닥 PNG 시안 한 장. 실제 Painter 사용·.spp 생성·메시 베이크·PBR 채널 세트 제작·인게임 적용은 이번 요청에 포함하지 않는다. 실제 생성 방식은 내장 imagegen이며 원본과 프롬프트를 보관한다.
