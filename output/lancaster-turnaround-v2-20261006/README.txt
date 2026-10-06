Lancaster 개별 모델링 3면도 v2 (2026-10-06)

최종 이미지: 각 1774×887 PNG, 내장 image_gen 독립 생성.
01_front_tpose.png — 정면 T 포즈, 팔 길이/관절 비율의 우선 기준.
02_right_side_tpose.png — 우측면 T 포즈, 몸통 정면은 화면 왼쪽, 팔은 카메라 축으로 단축 투영.
03_back_tpose.png — 후면 T 포즈, 무장 좌우 반전, 보이지 않던 후면 구조는 보완 제안.

팔 구조·추정 비율·최종 정면 육안 좌표 및 뷰 간 차이: arm_analysis.txt.
실제 프롬프트: prompt_front.txt / prompt_front_refine.txt / prompt_front_drum.txt / prompt_back.txt / prompt_back_refine.txt / prompt_back_reach_match.txt / prompt_side.txt.
원화: reference.png. 파일 규격 및 생성 원본 SHA256 동일 확인: file_validation.json.
front_draft.png / front_reach_refined.png / back_draft.png / back_before_reach_match.png 는 중간 작업으로 최종3면도가 아님.

이전 lancaster-turnaround-20261006의 한 장짜리 시트는 팔 비율 수정 전 자료로 보존.
정면을 기준으로 모델링하고 후면의 폭/세부 차이를 맞춘다. 원화만으로 숨은 관절축·정확한 물리적 치수는 확정할 수 없다.
본편 모델·게임 코드 변경, 엔진 실행, 커밋·푸시 없음. 다른 작업자의 변경/미추적 파일 보존.
