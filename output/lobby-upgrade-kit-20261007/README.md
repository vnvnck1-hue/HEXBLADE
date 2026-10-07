# HEXBLADE 로비 업그레이드 리소스

사용자가 제공한 이전 로비 콘셉트 기준, 2026-10-07 제작. **리소스와 합성 미리보기 완료, 본편은 미적용.**

**우선 작업(사용자 요청 2026-10-07): 빠른 시일 안에 실제 로비에 적용할 것.** 다음 로비 작업에서 완성 배경01 + 실제 메뉴 UI부터 적용하고 검증한다.

- [Claude 인수인계](../../docs/lobby-upgrade-claude-handoff.md)
- [완성 배경 구성](preview_static_1920x1080.png) · [분리 구성](preview_layered_1920x1080.png) · [테스트 패널](preview_test_drawer.png)
- `preview.html`을 브라우저에서 열어 구성 전환/메뉴 포커스/목록을 확인한다. 네트워크/서버 없이 로컬에서 동작하며 게임을 실행하지 않는다.
- `png/`: 내장 imagegen PNG4장. `ui/`: 코드로 만든 SVG17종. `ui_png/`: 같은 그래픽의 PNG17장. 독립 디자인21종/실파일38개.
- `layout.json`: 배치·문구·색. `manifest.json`: 크기·알파 영역·SHA256. `validation.json`: 검증 결과.
- `prompts.json`: 실제 내장 imagegen5회 프롬프트. CLI/API키는 사용하지 않았다. `sources.json`: 생성 출처.

1차는 `png/01_keyart_clean.png` + 실제 UI로 적용한다. 그 배경에 기체·드론·그래픽이 이미 있으므로 분리본을 중복 배치하지 않는다. 분리 모션 구성은 `02_hangar_plate.png`부터 시작한다. AI 분리본과 네이티브 그래픽은 원안과 세부차이가 있다.

Godot용은 필요한 파일을 `assets/ui/lobby/`로 복사한다. 출력 폴더 전체는 `.gdignore`로 임포트 제외. 검증 도구는 게임 코드로 가져가지 않는다. 새 `.import`는 원본과 함께 관리한다.

재현 순서: `build_wordmark.ps1` → `build_kit.py`(Python/Pillow) → `render_preview.cjs`(Node/sharp/Playwright, 설치된 Chrome/Edge) → 고정 `tools/godot.ps1`로 `engine_validate.gd` → `pack_kit.py`. 원본 생성 PNG는 스크립트로 수정하지 않는다. imagegen을 다시 실행하지 않는 한 같은 파일/구성을 재현한다. 동봉 `test_scene_data.js`는 제작 당시13개 항목 스냅샷이며 본편은 현행 `Lobby.TEST_SCENES`를 사용한다.

검증: PNG/알파·SVG 검사 PASS, 네 화면 비율 HTML 메뉴/↑↓ PASS, Godot4.7.2 원본38개 디코딩 성공/실패0. 최종 엔진 시작의 루트 인증서 환경 ERROR1건은 로그와 인수인계에 구분 기록. 게임 임포트/UI/전체 테스트는 다음 적용 단계에서 수행한다.

ZIP은 `docs/`와 `output/lobby-upgrade-kit-20261007/`를 포함하는 **프로젝트 상대 경로 구조**다. 프로젝트 루트에 풀면 링크와 검증 경로가 유지된다. 기존 파일과 충돌하면 새 파일 내용을 확인하고 합친다. 기존 AGENTS.md나 게임 코드는 ZIP에 포함하지 않는다.
