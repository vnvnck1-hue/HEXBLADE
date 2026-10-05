# 부드러운 청보라 바닥과 벽 텍스처 작업 재개 기록

작성일: 2026-10-06 · 작업 및 롤백일: 2026-10-05

이 문서는 사용자가 선택한 비대칭 핸드페인팅 바닥 원화와, 취소한 게임 적용 작업을 나중에 이어가기 위한 기록이다. **현재 본편은 적용 직전 상태로 롤백되어 있다. 이번 요청은 문서 작성만이며 재적용 지시가 아니다.** 원화와 캡처는 보존했고, 사용자에게서 새 작업 지시를 받기 전에는 게임을 다시 바꾸지 않는다.

## 사용자 취향과 선택

사용자는 롤 필드 배경, 월드 오브 워크래프트, 하스스톤처럼 부드러운 핸드드로잉을 원했다. 색은 청보라 계열이다. 넓은 면에는 부드러운 붓질과 명암을 남기고, 타일별로 위치와 방향이 다른 얕은 홈, 눌린 모서리, 작은 페인트 벗겨짐을 넣는다. 거친 긁힘과 과도한 손상은 피한다.

사용자는 생성한 이미지를 실제 모델링 텍스처로 사용하기 전에 그 **실제 PNG 형태**를 보고 선택하길 원했다. 승인한 그림을 엔진에서 다시 절차적으로 그리거나, 붓질만 추출해 색과 디테일을 재해석하는 방식은 원하는 결과와 달랐다. PNG를 그대로 샘플링하되 게임 조명과 그림자가 더해지는 것은 구분해서 설명한다.

진행 순서는 다음과 같다.

| 단계 | 결과 및 사용자 반응 |
| --- | --- |
| 최초 청보라 적용 | 붓질 혼합과 셰이더 재착색을 사용했다. 사용자는 평이하고 표현이 적다고 평가했다. |
| 직접 텍스처 시안 | 사용자는 너무 거칠고 표현이 심하다고 평가했다. |
| 부드러운 A/B/C | A는 차분한 낮은 대비, B는 넓고 둥근 베벨, C는 밝은 라벤더와 크림빛 가장자리로 제작했다. |
| 비대칭 A/B/C 수정 | 타일별 얕은 홈과 작은 도장 벗겨짐을 추가했다. |
| 선택 및 적용 | 사용자가 비대칭 **A 바닥 PNG**를 첨부하고 “이게 좋겠어. 이걸로 적용해봐 게임에”라고 요청했다. |
| 중단 및 롤백 | 이후 “멈춰. 다시 롤백해줘”라고 요청했다. 적용 직전 상태로 복원했다. **중단 이유는 설명하지 않았으므로 추측하지 않는다.** |

바닥 선택은 명시적이다. 같은 A안 벽을 맞추고 다른 벽 모듈에 바닥 PNG를 재사용한 것은 당시 에이전트의 적용 판단이었다. 이를 사용자가 별도로 확정한 벽 제작 방식으로 취급하지 않는다.

## 선택한 원본과 보존 자료

재개할 때는 PC별 생성 이미지 폴더보다 아래 프로젝트 내부 원본을 기준으로 삼는다. PNG는 모두 1254×1254이며, 제작 원문은 [prompts.json](../output/soft-handpaint-asym-20261005/prompts.json)에 있다. 내장 imagegen으로 제작했고, 적용 단계에서 추가 재그림이나 리사이즈는 하지 않았다.

| 자료 | 경로 및 용도 |
| --- | --- |
| 사용자 선택 바닥 | [A_floor.png](../output/soft-handpaint-asym-20261005/A_floor.png) |
| 함께 제작한 A 벽 | [A_wall.png](../output/soft-handpaint-asym-20261005/A_wall.png) · W01 전용 UV 아틀라스 |
| 선택 전 실제 모델 미리보기 | [A_model_direct.png](../output/soft-handpaint-asym-20261005/A_model_direct.png) · 조명 없는 직접 연결 |
| 선택 전 중립 조명 참고 | [A_model_lit.png](../output/soft-handpaint-asym-20261005/A_model_lit.png) |
| 취소된 적용의 실제 본편 화면 | [game_0180.png](../output/soft-handpaint-applied-20261005/game_0180.png) · 당시 기본 카메라와 조명 |
| 취소된 적용의 모델별 확인 | [modules.png](../output/soft-handpaint-applied-20261005/modules.png) |
| 당시 적용 상세 기록 | [NOTES.txt](../output/soft-handpaint-applied-20261005/NOTES.txt) |
| 당시 검증 결과 | [validation.json](../output/soft-handpaint-applied-20261005/validation.json) · 취소된 적용 상태의 기록 |
| 실제 롤백 결과 | [rollback.json](../output/soft-handpaint-applied-20261005/rollback.json) |

선택 바닥의 생성 파일명은 `exec-e903b743-1f83-4b3a-82cc-fbbf55288421.png`다. 첨부에 표시된 `/C:/...`는 Windows에서 잘못된 경로였으며, 앞 슬래시를 제거한 `C:/...`로 정상 열람했다. 프로젝트의 A_floor와 바이트가 동일하다.

원본 SHA256:

```text
A_floor.png
b36328ff190ee71207272a202e5095f72b84bab1627cf54e91805d3ce97befc7

A_wall.png
0004fd9c4fb18e0cd83f054a51122fa473de28335b6d494b64c6962aec5954d5
```

B/C 수정안은 같은 `soft-handpaint-asym-20261005` 폴더에 있다. 손상을 넣기 전 부드러운 원본은 `output/soft-handpaint-concepts-20261005/`, 그 이전 직접 텍스처는 `output/handpaint-direct-textures-20261005/`에 보존되어 있다.

## 현재 본편 상태와 롤백 범위

2026-10-06 문서 작성 때 아래 8개 파일을 `rollback.json`의 SHA256과 다시 비교했고 **8개 모두 일치**했다. 현재 `hp_sample`은 네 개의 겹친 반크기 샘플을 혼합하는 기존 코드다. 최신 A 비대칭 PNG가 본편에 적용된 상태가 아니다.

| 복원 대상 | 파일 |
| --- | --- |
| 바닥과 벽 PNG | `assets/textures/handpaint_blue/floor_brush.png`, `wall_brush.png` |
| 텍스처 설정 | `scripts/claude_background/blue_handpaint.gd` |
| 공통 샘플링 | `scripts/claude_background/blue_handpaint_common.gdshaderinc` |
| 바닥 표현 | `scripts/claude_background/blue_handpaint_floor.gdshaderinc` |
| 벽 표현 | `scripts/claude_background/blue_handpaint_wall.gdshaderinc` |
| 본편 재질 연결 | `scripts/presentation/brawl_look.gd` |
| 재질 검사 | `tests/blue_handpaint_check.gd` |

작업 직전 백업은 `output/soft-handpaint-applied-20261005/before/`에 있다. README의 이번 적용 설명도 되돌렸다. 최초 청보라 구현과 다른 작업자의 변경을 취소한 것은 아니다. 원본 이미지, 캡처, 로그, 캡처 스크립트는 미적용 이력으로 남겼으며 해당 출력 폴더는 `.gdignore`로 게임 임포트에서 제외한다.

커밋과 푸시는 하지 않았다. 이 문서와 원화가 다른 PC에서도 필요하면 사용자가 요청한 커밋·푸시 때 함께 포함해야 한다. 백업은 과거 기준점이다. **향후 본편 파일을 백업으로 통째로 덮으면 이후의 다른 변경을 지울 수 있으므로, 재개 시 최신 코드와 비교해서 필요한 부분만 수정한다.**

## 취소된 적용의 구현 방식

아래는 재개 참고용 구현 이력이다. 그대로 재적용하라는 지시가 아니다.

1. 선택 PNG 두 장을 `assets/textures/handpaint_blue/floor_brush.png`와 `wall_brush.png`로 바이트 동일 복사했다. 기존 `.import`의 UID, 고품질 VRAM 압축, 미프맵 설정은 유지했다.
2. 공통 샘플링을 `texture(paint_tex, uv).rgb`로 바꾸어 네 붓 샘플 혼합을 제거했다. 바닥 셰이더의 추가 줄눈, 턱, 임의 밝기와 절차적 마모도 없앴다. 홈·벗겨짐·볼트는 PNG 안에 그려진 것을 사용했다.
3. 바닥은 `(월드 XZ - 방별 offset) / 4.0`으로 읽었다. 네 개의 2m 판이 4m마다 반복한다. 모든 타일을 고유하게 만든 방식은 아니다. 경계는 승인한 이미지에 이미 그려져 있어 추가 격자를 겹치지 않았다.
4. 높은 W01은 A_wall을 원래 UV로 직접 읽었다. W01 정면은 모델의 -Z이며, 본편의 뒤쪽 벽과 비교 미리보기에서는 180° 회전하여 +Z를 향했다. 뒷면을 정면으로 착각해 비교하지 않는다.
5. 반쪽 벽, 옆판, 낮은 벽, 엄폐물, 기둥은 서로 다른 UV 아틀라스를 쓴다. 당시에는 A_floor를 월드 축으로 투영하여 1m 판으로 재사용했다. W01 아틀라스를 이들 UV에 그대로 연결하면 맞지 않는다. 모델 형상과 충돌은 바꾸지 않았다.
6. BrawlLook의 기본 바닥 `lift`는 1.0, 선택 벽 경로는 `value_k`로 다시 재착색하지 않도록 했다. 기존 해, 환경광, 셀 음영, 그림자, 플레이어 조명 풀은 유지했다. 따라서 최종 화면은 조명 없는 원본과 픽셀 색이 같지는 않다.
7. 바닥 파괴 `GroundBreak`는 같은 재질을 상속했다. 들리거나 튀는 조각의 기존 밝기 강조를 유지하려고 바닥의 `* lift` 연결 자체는 남겼다. 일반 바닥은 1.0이고 파편 복제만 값을 올린다. 이를 전부 제거하면 파편 강조가 끊긴다.
8. 기본 BrawlLook에서 벽 변경이 적용되었다. N으로 다른 룩을 선택하면 벽은 해당 룩의 원래 재질 정책을 따랐다. `--bgpaint=old`는 최초 청보라 작업 이전 재질 비교이며, 직전 핸드페인팅으로 되돌리는 옵션은 아니다.

당시 `blue_handpaint.gd.configure`에는 원본 머티리얼을 선택적 인자로 넘겼다. 원본 텍스처 경로가 `res://assets/models/bg_claude_w01_bg_claude_w01_albedo.png`이면 W01 아틀라스 사용 플래그와 A_wall을 설정하고, 다른 벽 모듈에는 A_floor를 설정했다. 이 분기와 전체 검사 코드 변경은 현재 롤백되어 있다. `before/`에는 취소된 새 구현이 아닌 **적용 전 코드만** 있으므로 새 구현 복사본으로 오해하지 않는다.

## 검증 결과와 한계

취소된 적용 상태는 고정 Godot **4.7.2-stable 표준 빌드, Forward+**에서 확인했다. 모든 실행은 `tools/godot.ps1`을 거쳤다.

- [tests.log](../output/soft-handpaint-applied-20261005/tests.log): 전체 **46개 테스트 PASS**.
- [final_material_checks.log](../output/soft-handpaint-applied-20261005/final_material_checks.log): 최종 바닥 밝기·파괴 재질 수정 뒤 `blue_handpaint_check`, `ground_break_check` 두 검사 PASS.
- [legacy.log](../output/soft-handpaint-applied-20261005/legacy.log): `--bgpaint=old` 재질 검사 PASS.
- [game.log](../output/soft-handpaint-applied-20261005/game.log): 실제 `main.tscn`, `--bot --dronebot --seed=4`, 무적 없이 물리 프레임 1800개를 실행했다. 1920×1080 캡처 다섯 장 저장, 종료 0, ERROR/SCRIPT ERROR 0.
- [modules.log](../output/soft-handpaint-applied-20261005/modules.log): W01 및 다른 벽 모듈의 실제 PNG 연결 확인, 캡처 저장 성공, 종료 0, ERROR/SCRIPT ERROR 0.
- [rollback_import.log](../output/soft-handpaint-applied-20261005/rollback_import.log): 롤백 PNG의 캐시 재임포트 종료 0, ERROR/SCRIPT ERROR 0.

**46개 PASS는 취소된 적용 상태의 결과다.** 롤백 뒤 전체 테스트나 게임을 다시 실행하지 않았다. 복원은 8개 파일의 바이트 일치와 재임포트로 확인했다. 문서 작성일에도 그 8개 파일 및 선택 원본의 해시만 재확인했다.

유의할 시각적 한계는 4m 반복 패턴, 같은 W01 복제의 반복 손상, 다른 벽 모듈에 바닥 PNG를 재사용한 점이다. 전체 맵의 모든 타일이 서로 고유하거나 모든 벽에 전용 원화가 마련된 상태는 아니다. 생성된 아틀라스의 UV 패딩과 반복 경계도 향후 최종 게임 시점에서 다시 확인한다.

## 재개 순서

새 재개 지시를 받으면 먼저 최신 `AGENTS.md`, git 상태, 본편 재질 코드와 이 문서를 읽는다. 바닥 기준 원화는 위 A_floor로 명확하지만, 취소 이유와 벽 모듈별 최종 처리 방식은 미확정이다. 새 사용자 지시에 맞춰 범위를 정하고, 기존 원화 선택과 아직 결정되지 않은 벽 방식을 구분한다.

선택 PNG의 해시와 최신 모델의 UV를 확인하고, 필요한 코드만 수정한다. 기존 붓 샘플 혼합을 유지한 채 PNG만 교체하면 승인한 홈·벗겨짐이 흐려질 수 있다. 본편 적용 전에 동일 모델·구도에서 직접 샘플링 결과와 게임 조명 결과를 비교할 수 있도록 자료를 남긴다.

재적용을 지시받아 코드를 수정했다면 다음 순서로 검증한다. 사용자 요청이 문서 확인이나 시안 수정에 한정되면 게임 적용은 하지 않는다.

```powershell
powershell -File tools\godot.ps1 wait --headless --import --editor --quit
powershell -File tools\run_tests.ps1 blue_handpaint_check ground_break_check
powershell -File tools\run_tests.ps1
powershell -File tools\godot.ps1 wait --fixed-fps 60 res://scenes/main.tscn -- --bot --dronebot --seed=4 --seconds=30
```

당시 캡처 스크립트는 `output/soft-handpaint-applied-20261005/capture_game.gd`와 `capture_modules.gd`다. 나중에 다시 쓸 때는 최신 코드와의 호환성을 확인하고 저장 경로를 새 출력 폴더로 바꾸어 **취소된 적용의 원본 캡처와 로그를 덮지 않는다.** 최종 결과, 미확정 사항, 검증 로그와 상태를 `AGENTS.md`에 갱신한다. 커밋·푸시는 사용자 요청 때만 수행한다.
