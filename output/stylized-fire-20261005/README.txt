스타일라이징된 불꽃 — 참고 GIF 기반 게임용 에셋

미리보기: fire_preview.gif (참고처럼 남보라 배경)
투명 GIF: fire_loop.gif
게임용 원본: fire_atlas.png (RGBA 1536×1536, 4열×3행)
프레임: 384×512, 12장, 각80ms, 총960ms 무한 반복, 약12.5fps
편집 파일: fire_loop.aseprite
배포 묶음: game_asset_pack.zip
적용 명세: animation.json

게임에서 쓸 때
- GIF는 256색과 이진 투명도 제한이 있으므로 동작 확인용으로 보고, 실제 게임에는 RGBA PNG 시트를 쓴다.
- 프레임 순서는 왼쪽→오른쪽, 위→아래. 정방향 반복, ping-pong 아님.
- 셀 크기384×512를 유지한다. 자동 트림 금지.
- 공통 불꽃 바닥 기준점은 (192,464), 정규화(0.5,0.90625).
- Godot AnimatedSprite2D는 centered=false, offset=(-192,-464), 또는 상위 노드에서 위치 보정.
- SpriteFrames에서 셀12개를 atlas region으로 나누고 speed=12.5, loop=true로 설정.
- Sprite2D flipbook은 hframes=4, vframes=3; 프레임 인덱스=floor(time/0.08)%12.
- 기본 알파 혼합으로도 읽히는 형태다. Additive는 원본의 진한 주황 면을 바꾸므로 연출 필요에 따라 선택.
- 그림이 아래에서 잘린 평평한 근원이므로 지면/분출구에 기준점을 붙여 배치한다.
- 이번 작업은 에셋 제작이다. 본편 코드나 씬에는 적용하지 않았다.

참고 분석과 제작
analysis.txt / reference_analysis.json / reference_contact.png에 관찰과 원본 정보 기록.
내장 imagegen 사용, 실제 입력은 참고 GIF 전체 프레임 시트+대표 PNG3장.
실제 생성 프롬프트: prompt.txt. 생성 원본은 source_sheet_v1.png (1254×1254).
요청 시트 해상도1536×1536과 달리 생성은1254×1254로 나와, 동일배율1.10/공통 기준점으로384×512셀에 배치했다.
pack.ps1은 생성그림을 다시 그리지 않고 셀 분리·동일배율 조정·바닥 정렬·RGBA시트 조립만 수행.
assemble.lua는 Aseprite로 PNG 타임라인과 GIF를 저장한다.
PNG의 연속 알파 보존, GIF에서는 알파128을 경계로 이진 투명도 변환.
원본의 선명한 두 색 구조를 따라 새로 그렸으며 내부에 약한 명도 변화가 남아 있다.

검증
validate.ps1 / validation.json: GIF 재디코딩12프레임/960ms/무한루프, RGBA12장 캔버스/알파 경계, 공통 기준점 변환, 전체 실루엣 변화 측정.
마지막→첫 실루엣 변화0.2271, 내부 평균0.4090/최대0.5891. 급한 변화는 특히 몸통이 끊기는 구간에 있음.
이 수치는 픽셀 실루엣 차이이며 프레임의 광학 흐름이나 물리 정확성을 의미하지 않음.
본편 엔진 검증은 하지 않았다. 게임 코드 수정·커밋·푸시 없음.
