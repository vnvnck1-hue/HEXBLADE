# 배경 첫 제작 — Codex 작업 기록

2026-10-03 사용자 착수 지시를 받은 Codex가 진행한다. 기준은 `background-first-pass-handoff.md`의 F01/W01/A01/A02 4종이다.

## 파일 소유 범위

- `models/src/bg_codex_*.py`
- `tools/blender/codex_background_*.py`
- `assets/models/bg_codex_*.glb`와 이에 딸린 추출 텍스처/임포트
- `assets/textures/codex_background/`
- `scripts/codex_background/`
- `scenes/codex_background_first_pass.tscn`
- `codex_background_test.cmd`
- `tests/codex_background_check.gd`
- `output/models/bg_codex_*/`, `output/codex-background-first-pass/`

Claude는 인수인계 문서의 일반 이름 또는 별도 접두사를 사용할 수 있다. Codex는 일반 `bg_floor_f01` 등과 `background_first_pass.tscn`을 사용하지 않는다. 기존 플레이어/카메라/훈련장/본편/로비 파일 및 공용 Blender/Godot 실행기는 수정하지 않는다.

공용 `AGENTS.md`는 상태 연결만 최소 추가하며, 완료 후 이 문서에 실제 실행법·검증 결과를 기록한다. 텍스처 원본과 개별 Blender 파일은 Codex 고유 경로에 저장한다.

현재: 원화·규격·기존 파이프라인 확인. 제작 진행 중.
