// Historical script superseded by the user correction: dialogue changes only; retain original fusion characters.
throw new Error("Do not replay: fusion restoration is recorded in output/cutin-restored-20261011.");
const fs=require('fs');const edit=(p,f)=>fs.writeFileSync(p,f(fs.readFileSync(p,'utf8')).replace(/\r\n/g,'\n'));
const intro=`# 캐릭터 대화 시스템

갱신: 2026-10-11. 대화 테스트 씬은 로비 → 캐릭터 대화 또는 \`launchers/scenes/dialogue_test.cmd\`로 실행한다. 본편 출격/정산 연결은 아직 하지 않았다.

현재 출연진은 **사장(owner) · 정비사(worker) · 청소 파트너(partner) · 남주(me)**다. 사용자가 남주 포트레이트 유지로 확정했다. 이전 여성 캐릭터의 등록과 대본은 제거했으며, 이전 여성 원화는 \`output/retired-characters-20261011/\`에 게임 임포트 제외 상태로 옮겼다. 과거 생성 시안은 역사 자료로만 보관한다. 합체 사선/조종석 컷인도 현재 캐릭터 원화로 교체했다. 사선 기본은 청소 파트너, [키로 사장/정비사/파트너 또는 번갈아 모드 선택.

**F1** 청소업체 첫 출근 · **F2** 새 팀의 격납고 브리핑 · **F3** 기능 시연 · **F4** 정비 동료 소개 · **F5** 첫 청소 파트너 소개 · **R** 현재 대본 재시작. 사장/정비사/파트너는 큰 무대 포트레이트, 남주는 하단 대화창의 정지 포트레이트를 사용한다. 별도 실행은 \`coworker_dialogue.cmd\`와 \`partner_dialogue.cmd\`(launchers/scenes/).

**포트레이트**: \`assets/portraits/opening_cast/\`. 사장 환영/업무 설명/격려3종, 정비사 소개/신남2종, 파트너 인사1종, 남주 기본1종. 여성6개의 각 원화에 \`_closed.png\` 닫힌 눈 프레임을 추가했다. 내장 imagegen으로 눈 감은 모습을 제작하고 눈 영역만 합성했다. 최종 1254×1254 RGBA의 눈 밖 픽셀과 전체 알파는 원본과 완전 동일하며 원본은 바꾸지 않았다. 실제 프롬프트/생성 원본/눈 영역 좌표/픽셀 검증은 \`output/portrait-blink-20261011/\`에 보관한다. 최초 원본 참고4장만 그림체 기준으로 사용한다.

**아이들링과 눈 깜빡임**: 여성 세 명은 기존 숨쉬기/머리/옷자락/리본 셰이더 움직임을 유지한다. \`DialogueIdleMotion\`은 합체 셰이더를 재사용하되 사선 클립과 가슴 모핑을 끈다. 표정 전환의 이전/새 그림과 그림자를 각각 처리한다. 마스크 캐시는 원본6장으로 고정하며 닫힌 프레임은 동일 마스크를 사용한다. \`DialogueBlink\`는 각 포트레이트 전용 난수 생성기로2.8~6.2초 기다린 뒤0.12초간 눈을 감는다. 말하는 동안과 듣는 동안 모두 작동하고 게임 전역 난수에 영향을 주지 않는다. 표정 전환 중에도 두 프레임이 같은 눈 상태를 사용한다. **M** 움직임 줄이기를 켜면 눈을 뜬 채 유지하고 아이들링이 부드럽게 멎는다. 다시 끄면 이어진다.

**화면 배치**: 대화창은 항상 하단. 넓은 화면의 단독 포트레이트는 중앙에, 두 명은25%/75% 위치에 서며 손/얼굴은 창 위로 보인다. 허리 밑단만 창 뒤로 연결한다. 선택지는 하단 창 안에 표시한다. 상단 메뉴 아래 여유는 호흡 확대/표정 점프를 고려한다. 좌우 반전은 인물 몸 방향에 따르며 시선은 원화대로 플레이어 쪽이다. 세 명/좁은 화면은 기존 다인 배치다.

검증: \`tests/dialogue_check.gd\`(파서/선택/화면/5대본), \`dialogue_idle_check.gd\`(모션/전환/M/캐시), \`dialogue_blink_check.gd\`(6장 픽셀/알파 불변/교체/주기/남주/컷인), \`coworker_dialogue_check.gd\`와 \`opening_cast_check.gd\`. 실제 화면 캡처는 \`tools/godot.ps1 wait -s res://_capture/dialogue_blink_show.gd\`, 결과는 \`output/portrait-blink-20261011/\`.

`;
edit('docs/dialogue.md',s=>intro+s.slice(s.indexOf('## 1. 리서치')).replaceAll('mira','owner').replaceAll('미라','사장').replaceAll('trust_mira','trust_owner').replace(/owner angry/g,'owner briefing').replace(/owner confident/g,'owner welcome').replace(/사장 300Hz 사각 · 세나 470Hz 삼각 · 노아 390Hz 사인 · 에이린 250Hz 사인/,'사장 290Hz 사인 · 정비사 380Hz 삼각 · 파트너 430Hz 삼각').replace(/화자 id 와 표정은[^\n]+/,'화자 id와 표정은 `scripts/dialogue/dialogue_cast.gd`에 있다 (owner: welcome/briefing/encouragement/introduction · worker: introduction/cheerful · partner: greeting · me: neutral · 무전 radio).'));
edit('scripts/drone/diagonal_docking_cutin.gd',s=>s.replace(/## 캐릭터 2명[\s\S]*?\n\nconst FONT/,'## 승인 캐릭터: 사장 · 정비사 · 청소 파트너. 기본은 청소 파트너이며 [키로 선택한다.\n## 머리/옷자락 관성과 뒤쪽 그림자·소품은 기존 합체 연출을 유지한다.\n\nconst FONT').replace(/static var char_mode := "partner"[^\n]*\n[\s\S]*?static var hidden_chars: Array = \[\]/,'static var char_mode := "partner"  ## --cutin-char=alt|owner|worker|partner\nstatic var hidden_chars: Array = []').replace('## 포즈가 여럿인 캐릭터(민트 메이드):','## 포즈가 여럿인 캐릭터(사장/정비사):'));
edit('scripts/training/training_main.gd',s=>s.replace('번갈아 → 보라 정비사 고정 → 초록 메이드 고정 → …','번갈아 → 사장 → 정비사 → 청소 파트너'));
edit('scripts/drone/partner_drone.gd',s=>s.replace('## 민트 메이드 컷인으로 합체했으면','## 청소 파트너 컷인으로 합체했으면'));
edit('_capture/dialogue_idle_show.gd',s=>s.replace('res://output/dialogue-idle-20261011/','res://output/portrait-blink-20261011/idle/').replace('var pos := Vector2(23 + i * 320, 112) if i < 4 else Vector2(183 + (i - 4) * 320, 461)','var pos := Vector2(83 + i * 420, 240)'));
