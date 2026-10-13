HEX DEPTHS (로그라이크 모드) BGM 시안 2곡 — 신스웨이브 두 스타일 (2026-10-13, Claude)

생성: tools/music/rogue_bgm.py (악기·효과·마스터는 tools/music/lancaster_bgm.py 엔진 재사용)
  uv run --no-project --with numpy --with scipy python tools/music/rogue_bgm.py   (약 28초)
numpy/scipy 합성만. 샘플·외부 음원·AI 음악 서비스 없음. 44.1kHz 16bit 스테레오, 피크 -1 dBFS.

A. NEON DESCENT — 밝은 아웃런 신스웨이브 (초반 층 · 빠른 전투)
   132 BPM · A 단조 ↔ C 장조 · 루프 32마디 58.18초
   A  Am F C G        주제 리드 + 8분 옥타브 베이스 + 크게 울리는 스네어
   B  F G Em Am F G C E   올라가는 후렴 (마지막 E 장조로 긴장)
   A' Am F C G        주제 + 옥타브 아래 겹침 + 아르페지오
   BR F F C C Dm Dm E E   브레이크다운: 드럼 빠짐 → 킥 복귀 → 스네어 롤 · 라이저 → A

B. DEEP SIGNAL — 카펜터풍 호러 신스 (깊은 층 · 긴장)
   104 BPM · E 단조(프리지안 F) · 루프 32마디 73.85초
   진행 Em Em F Em Em C Am B 반복, 최면적 반복 아르페지오가 내내 깔림
   S1 드론 · 바람 · 심장박동 킥만 (성김)
   S2 하프타임 드럼 · 8분 베이스 · FM 종 선율
   S3 16분 베이스 · 톱니 리드 · 16분 하이햇
   S4 절정 (한 옥타브 위 선율 · 탐) → 마지막 마디에 가라앉아 S1 로

C. MIDNIGHT HEX (2차) — 80년대 신스팝 R&B (After Hours 시절 위켄드의 느린 곡 느낌. 멜로디는 새로 씀)
   1차(168 BPM · 탬버린 16분 · 쉬지 않는 리프 · 모음 필터 가짜 보컬)는 반려 → 2차로 교체
   104 BPM(DEEP SIGNAL 과 같음) · G 단조 · 루프 32마디 73.85초 · 생성 tools/music/rogue_bgm_c.py (약 8초)
   HOOK   Gm7 Ebmaj7 F Dm7   미끄러지는 신스 리드 훅 + FM 일렉트릭 피아노 엇박 화음 + 엇박 킥 · 클랩 겹친 큰 스네어 · 스윙 셰이커
   VERSE  같은 진행           낮은 리드 · 드럼 가볍게
   CHORUS 같은 진행           높은 리드 + 옥타브 아래 겹침 · 플럭 아르페지오
   BRIDGE Cm7 Ebmaj7 Bbmaj7 D7 ×2   하프타임 · 긴 화음 · 끝 2마디 롤 · 라이저 → HOOK

파일
- rogue_bgm_*_loop.wav     게임용 루프. 처음~끝 그대로 반복하면 이어짐 (잔향 꼬리를 앞에 감음)
- rogue_bgm_*_preview.wav  루프 두 번 (이음새 확인용)
- spectrogram_*.png        미리듣기 스펙트로그램 (마디선 4마디마다 진하게)
- validation.json          음량 · 구간 음량 · 대역 · 이음새 측정 (이음새 차이 0 = 곡 안에서 이어질 때와 동일)

아직 게임에 연결하지 않음 (assets 복사 · 임포트 · 재생 코드 없음).
