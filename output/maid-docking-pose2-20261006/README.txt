민트 메이드 합체 컷인 — 추가 포즈 1종 (2026-10-06)

사용자 요청: 게임에서 현재 합체 연출을 먼저 확인하고, 같은 캐릭터의 확연히 다른 포즈 한 장을 제작.

최종: mint_maid_docking_pose2.png (1122×1402, 투명 RGBA)
민트 머리, 분홍 눈, 한쪽 눈을 가린 앞머리, 머리 리본/꽃, 흑백 메이드 의상/분홍 포인트, 굵은 외곽선/셀 명암 유지.
현재 입가 손+디저트 트레이 정지 포즈와 달리, 양팔을 위/앞으로 펼치고 몸을 비틀며 한 다리를 접어 도약하는 포즈.
트레이/디저트/독립 소품/반짝이/빛 궤적은 새 원화에 넣지 않았다.
내장 image_gen 사용. 실제 프롬프트 전문은 prompt.txt, 입력 원본은 reference_character.png.
생성 원본을 픽셀 편집 없이 바이트 동일 복사했다. PNG 디코딩/크기/알파/네 모서리/원본 SHA256 일치 검사: validation.json, 재검사 validate.py.
캐릭터 그림의 알파 경계는 (25,7)~(1116,1388), 손발/머리 전체가 캔버스 안에 있다. 작은 외곽 여백은 정사각 컷인 가공 시 더 확보할 수 있다.

현재 게임 확인:
tools/godot.ps1을 거쳐 Godot 4.7.2.stable.official.ed1daf0bf, Forward+ / RTX 3060으로 실행.
기존 _capture/diagonal_cutin_show.gd가 허수아비 시험장에서 실제 PartnerDrone.whirl_link() (Q 합체)를 발생시켰다. 미리보기 모드 아님.
호출 인자: wait --fixed-fps 60 --resolution 1280x800 -s res://_capture/diagonal_cutin_show.gd '--' --out=res://_capture/maid-pose2-review-20261006 --cutin-char=mint --bossroom=off
80프레임 기록, 실제 합체 이벤트 dock_t=0.233, state=7(DOCKED) 확인, 진입/중앙 체류/퇴장 완료. 종료0, SCRIPT ERROR 0.
환경 ERROR 3개: user:// 로그 회전 접근, 로그 파일 쓰기 접근, Windows 루트 인증서 저장소 읽기. 렌더/캡처/합체는 완료했다.
current_game_hold.png는 새로 실행한 현재 본편 컷인의 30번째 실제 렌더, current_capture_log.txt는 타임라인 기록.
프레임 덤프는 git 제외 경로 _capture/maid-pose2-review-20261006/에만 보관.

이 추가 포즈는 원화 제작까지 완료. 본편 포트레이트 교체/추가, 레이아웃 조절, 새 머리/옷 마스크 제작은 아직 하지 않았다.
본편 적용 요청이 오면 기존 tools/cutin_mint_maid.py를 그대로 재사용하지 말고 새 포즈에 맞는 영역/피벗/얼굴 좌표/하단선/움직임 마스크를 다시 잡을 것.
output 폴더는 .gdignore로 Godot 임포트 제외.
게임 코드 변경/커밋/푸시 없음. 기존 변경 및 다른 도구가 만든 미추적 파일 보존.
