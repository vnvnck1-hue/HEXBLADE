REFERENCE MECH / 실제 3D 모델

사용자가 제공한 컨셉 원화와 이 대화에서 제작한 3면도를 기준으로 재구성했습니다.
240개 메시 부품, 73,728 삼각형, 7개 PBR 재질.
정면 -Z / 상단 +Y / 발바닥 Y=0. 전체 높이 약 4.695 모델 단위.

파일
reference-mech.glb : Blender, Godot 등에서 열 수 있는 실제 3D 모델.
reference-mech.tscn : 메시와 재질이 내장된 Godot 모델 리소스.
hero.png : 실제 모델의 정면 사선 렌더.
front.png / right.png / back.png : 동일 모델의 정투영 렌더.
back-three-quarter.png / game-angle.png : 후면 사선 및 쿼터뷰 렌더.
model-audit.json / verification.json : 내보내기, 재불러오기 및 조작 확인 결과.

확인 창 실행
프로젝트 루트의 reference_mech_studio.cmd를 실행합니다.
Godot 씬: res://scenes/reference_mech_studio.tscn
드래그: 회전 / 휠: 확대·축소 / Space: 자동 회전
1: 정면 / 2: 측면 / 3: 후면 / 4: 사선 / C: 회색 재질 / Esc: 닫기

형태 구현
전면 장갑은 외곽선·두께·모따기가 있는 독립 메시입니다.
원통 외피와 캡, 하단 소켓은 회전체 메시이며 연결관은 곡선 튜브입니다.
관절 베어링과 집게손의 손가락 마디, 장갑 이음선은 실제 기하로 구성됩니다.
팔과 다리, 집게 마디는 노드 계층으로 분리되어 있습니다.
스킨 리깅·보행 애니메이션·게임 플레이어 교체는 포함하지 않습니다.

원화의 사선 시점을 중립 자세로 해석한 재구성입니다. 가려진 후면 장갑과 장비 결합부는 추정 설계입니다.
생성 이미지가 아닌 Godot에서 실제 메시를 렌더한 결과입니다.

재생성 소스
scripts/modeling/reference_mech.gd : 모델 제작
scripts/modeling/mech_studio.gd : 확인 창과 렌더·내보내기
scripts/modeling/verify_mech.gd : GLB 재불러오기와 조작 검증
