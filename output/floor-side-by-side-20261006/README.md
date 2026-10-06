# 현재 게임 바닥과 최신 시안 나란히 비교

2026-10-06. 왼쪽 `current_effective.png`는 현행 `BrawlLook._floor_for(ClaudeBgDress.floor_material())`의 ALBEDO를 고정 Godot4.7.2 Forward+에서 다시 캡처한 2048² PNG다. 현재 `floor_brush.png`의 네 샘플 혼합·2m 줄눈/마모·lift0.82를 유지하고 월드XZ 4m 영역을 정면 출력했다. 조명·그림자·플레이어 조명 풀은 제외해 텍스처와 재질의 색만 비교한다. raw brush PNG 한 장이 실제 바닥 모습과 다르므로 본편 기본 재질 분기를 사용했다.

오른쪽은 `../substance-painter-floor-20261006/floor_4m_chunky_groove.png` 최신1254² 시안이다. 두 이미지를 동일한1000² 표시 크기로 비율 유지 축소하여 `comparison.png`2064×1124에 배치했다. 비교 판넬 제작만 했으며 원본 텍스처의 색 변경·재그림·본편 교체 없음. `build_preview.py`·`validation.json`에 입력 경로·해시·규격과 판넬 픽셀 복사 확인을 기록했다.

엔진 실행은 `tools/godot.ps1 wait`를 사용했다. 렌더 저장0/종료0, 캡처 PNG 육안 확인. 샌드박스에서 user:// 로그/셰이더 캐시 폴더와 OS 인증서 읽기 오류3개가 출력되었으나 캡처는 정상 완료했다. SCRIPT ERROR 없음. 첫 실행은 PowerShell의 음수 위치 인자 분리 때문에 렌더 전 종료했고 문자열 인자로 수정하여 완료했다. 게임 코드 변경·커밋·푸시 없음, 이전 자료와 다른 작업 보존.
