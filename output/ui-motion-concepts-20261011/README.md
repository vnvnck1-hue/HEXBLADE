# 알림·텍스트 UI 모션 컨셉 v2 · 2026-10-12

10종 알림을 더 빠르고 강하게 수정했습니다. 게임 적용 전 독립 시안입니다.

- **index.html**: 최신 모션 재생.14개 독립 레이어(결과25개),재생/정지/시간축/속도/움직임 줄이기/레이어 숨김/퇴장 보기.인터넷이나 서버 없이 엽니다.
- **v2/contact_sheet.png**: 최신10종 전체 목록.
- **v2/*_layered.png/.html**: 실제 HTML 모션에서 렌더한 조립 상태와5단계 키프레임,레이어 시작 시각.
- **motion_v2.js / motion_v2_data.json / index_v2.template.html**: 모션·타이밍·레이아웃 소스.수정 후 node rebuild_v2.cjs로 index.html 재생성.
- **verify_v2.cjs / validation_v2.json**: 브라우저 동작·10종 레이어 분리/속도/상태·화면 크기·게임파일 보존 검사.검증 실행 시 보드도 재생성.
- **../../docs/ui-notification-motion-concepts.md**: 알림58개 상황/실제 코드 근거/화면별 타이밍/우선순위/동시노출/후속 적용 기준.
- **index_v1.html / design_v1.md / validation_v1.json / verify_v1.cjs**: 이전 버전 비교·기록.
- **01_stage_start.png ~ 10_route_dialogue_system.png**: 기존 내장 image_gen 정지 디자인 참고.모션 v2 소스와 구분합니다.
- **prompts.json / correction_prompts.json / sources.json**: 기존 생성 이미지의 실제 프롬프트·입력·원본·해시.
- **drafts/**: 교정 전07 비교안 보존.

패널·테두리·망점·장식·제목·번호·설명·영수증을 따로 조립하고 퇴장시킵니다.부모 패널 묶음의 애니메이션은 없습니다.개별 진입20~34ms,반동24~48ms.출격 제목 임팩트108ms,출격 전체226ms 정착.위험 문구는0ms부터 표시합니다.지원/장비/위험/결과는 실제 상태 종료 또는 입력까지 유지하는 제안입니다.

배경과 데이터는 컨셉 예시이며 게임 캡처/확정 리소스가 아닙니다.기존 AI PNG를 레이어 분해한 것이 아니라 네이티브 HTML/CSS 요소로 새 모션을 구성했습니다.캐릭터·게임 코드·씬·조작 변경 및 커밋/푸시 없음.
