LANCASTER 보스전 BGM — 다크 신스웨이브 (2026-10-07, Claude)

생성: tools/music/lancaster_bgm.py (numpy/scipy 합성만, 샘플·외부 음원·AI 음악 서비스 없음)
  uv run --no-project --with numpy --with scipy python tools/music/lancaster_bgm.py
스펙트로그램: tools/music/spectro_png.py

124 BPM · D 단조 · 44.1kHz 16bit 스테레오 · 피크 -1 dBFS · RMS 약 -10 dBFS

파일
- lancaster_bgm_loop.wav        루프 32마디 (61.94초). 처음~끝을 그대로 반복하면 이어진다 (잔향 꼬리를 앞에 감아 둠).
- lancaster_bgm_intro_loop.wav  미리듣기: 인트로 8마디(15.48초) + 루프 두 번. 루프 시작 = 682839 샘플.
- spectrogram.png               미리듣기 파일의 스펙트로그램
- validation.json               음량 · 대역 · 이음새 측정

구성
- 인트로 (한 번만): 거대 기체 발소리 쿵 · 금속 울림이 점점 잦아짐, 경보 사이렌, 닫힌 패드
                     → Dm Bb C A 진행과 함께 베이스 필터가 열리고 킥 → 하이햇 → 스네어 롤 · 라이저
- A  (8마디) Dm Bb C Am      주제 리드 + 16분 옥타브 베이스(킥 사이드체인) + 4박 킥
- B  (8마디) Gm Dm Bb A      고조, 아르페지오, 높은 리드, 탐 필인 → 라이저
- A' (8마디) Dm Bb C Am      주제 + 옥타브 아래 겹침 + 아르페지오
- BR (8마디) Dm Eb Dm Eb Bb C A A   하프타임, 일그러진 베이스, 화음 찌르기, 발소리, D-Eb 반음 충돌로 위협감
                     → 마지막 두 마디 스네어 롤 · 사이렌 · 라이저 → A 로 되돌아감

게임 적용 시: 인트로 파일과 루프 파일을 따로 쓰거나, intro_loop 를 루프 시작 682839 샘플로 지정.
아직 게임에 연결하지 않음 (assets 로 복사 · 임포트 · 재생 코드 없음).
