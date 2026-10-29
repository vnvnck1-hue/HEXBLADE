# 무한 비행 모드 플레이 영상 (2026-10-29)

최종 영상: `stream_flight_play_30s.mp4` — 1600×1000 · 60fps · 30.00초 · AAC 소리. 기술별 장면 `skills_sheet.png`.

## 속도
- 게임을 실시간으로 돌리며 ffmpeg `ddagrab`(주 모니터 창 영역)으로 녹화. ffmpeg 기록 58.0초 분량을 실제 58.06초에 씀(0.999배), 프레임 손실 2장.
- Movie Maker(`--write-movie`)는 쓰지 않음 — 실제 시계로 재는 히트스톱·슬로우모션이 압축돼 빨라 보인다.
- 동기: 게임 시작 1초 전 흰 화면 → 영상 10.617초. 흰 화면 + 2.167초(장면 로딩 포함)에 첫 게임 프레임이 예측 12.784초 · 실제 12.817초. 25초 뒤 지속 레이저 임팩트 프레임도 예측과 약 0.06초 차이.
- 소리: Godot `AudioEffectRecord`(Master). 녹음 33.69초 = 녹음 시작~끝 실제 시간 33.68초.
- 게임 시간은 실제 30초 동안 약 26초 흐른다: 처치 히트스톱(0.07초 × 약 40회)·검 히트스톱·궁극기 슬로우모션 때문이며, 사람이 플레이할 때와 같은 정상 동작이다(녹화하지 않은 시험에서도 같은 차이).

## 기술 순서 (영상 기준 초)
| 초 | 기술 |
|---|---|
| 0~1.1 | 등장 연출 (화면 아래에서 날아와 착지) · 이후 내내 기본 사격 |
| 3.9 | 광선검 콤보 (3단까지) |
| 6.0 | 콤보 중 좌+우 = 회피 레이저 |
| 8.4 | 충전 레이저 (1단) |
| 10.2 | 대시 → 2단 대시 PERFECT → 휠윈드 |
| 12.8 | 대시 중 검 = 일격참 (PIERCE) |
| 16.3 | 좌클릭 길게 = 기 모으기 돌진 최대 (TEMPEST) |
| 18.4 | E = 도약 내려찍기 |
| 20.2 | R 궁극기: 조준 0.55초 → 준비동작 0.42초 → 21.2초 미사일 8발 (LOCK ×8) |
| 23.4 | 최대 충전 → 24.5초 지속 레이저 2초 (FULL BURST) |
| 28.9 | 마무리 콤보 |

무한 비행 씬에는 패링 시스템(Parry)과 파트너 드론(Q/X/Z)이 붙지 않아 패링·합체는 들어가지 않는다.
플레이어는 `--godmode`(피해 무시, 화면 표시 없음). 재화(에너지·미사일)는 손대지 않고 게임 규칙대로 쓰고 회복했다.

## 다시 찍기
`_capture/stream_play_video.gd`(녹화 구동) + `_capture/stream_play_main.gd`(각본 봇). ffmpeg 을 먼저 켜고 게임을 띄운다:
```
ffmpeg -f lavfi -i "ddagrab=output_idx=0:framerate=60:draw_mouse=0:offset_x=480:offset_y=220:video_size=1600x1000" -t 58 -vf "hwdownload,format=bgra" -c:v libx264 -preset ultrafast -crf 14 -pix_fmt yuv420p raw.mkv
powershell -NoProfile -ExecutionPolicy Bypass -File tools\godot.ps1 wait -s res://_capture/stream_play_video.gd -- --bot --godmode --entrance=on --seconds=999
```
- `--seconds=999` 필수: 자동 플레이 모드는 기본 게임 시간 20초 뒤 저절로 끝난다.
- 이 PC 는 NVIDIA 드라이버가 낮아 `h264_nvenc` 가 안 열린다 → libx264.
- 창 좌표는 실행 로그 `STREAMVID_WIN` (2560×1440 주 모니터 가운데). 자르기: 영상의 흰 화면 시각 + `events.json` 의 `clip_unix − flash_unix`, 소리는 같은 차이만큼 앞에서 자른다.
