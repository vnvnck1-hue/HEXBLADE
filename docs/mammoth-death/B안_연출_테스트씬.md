# MAMMOTH 죽음 연출 B안 — 로비 테스트씬

로비의 **「연출 테스트 · MAMMOTH B안」** 버튼으로 들어간다. [mammoth_death_test.cmd](../../mammoth_death_test.cmd)를 실행해 바로 열 수도 있다. 씬 파일은 `res://scenes/mammoth_death_lab.tscn`이다.

기존 보스 모델과 추격 도로를 복제해 보여 주는 독립된 연출 공간이다.

> **2026-10-01 본선 적용**: 강화판 감독 `scripts/lab_mammoth_b/mammoth_b_director.gd`(5.7초, 로비 「MAMMOTH 죽음 연출 · B안」 씬)를 본선 `boss.tscn` 격파에 연결했다. `BossEnemy._begin_dying` 이 판정상 격파(점수·드롭)를 끝낸 뒤 감독을 시작하고, 감독이 끝나면 `defeated` → `BossMain._win` 이 바로 호출된다. 연출 중에는 플레이어가 자동 비행·무적이고, 하던 궁극기·지속 레이저는 끊긴다. 예전 연쇄 폭발(`_update_dying`·`_final_blast`)은 쓰지 않는다. 확인: `tests/mammoth_ingame_check.gd`, 캡처 `_capture/mammoth_ingame_show.gd`. 이 문서의 아래 내용(5.20초 `mammoth_death_lab.tscn`)은 이전 B안 관람실 설명이다.

## 관람과 조작

입장 후 0.6초 동안 준비한 뒤 자동 재생한다. 연출은 5.20초이며, 기본 설정에서는 완료 후 1.5초 간격으로 반복한다.

| 조작 | 기능 |
|---|---|
| Space / 재생 버튼 | 재생·일시정지. 완료 상태에서는 처음부터 재생 |
| R / F5 / 처음부터 | 모델과 잔해를 초기화해 다시 재생 |
| 타임라인 슬라이더 | 원하는 시점으로 이동한 뒤 정지 |
| 1–6 / 컷 버튼 | 해당 컷의 장면으로 이동한 뒤 정지 |
| 배속 메뉴 | 0.25 / 0.5 / 1 / 1.5배속 |
| 반복 | 자동 반복 켜기·끄기 |
| 흔들림 / 섬광 | 카메라 흔들림과 화면 섬광 켜기·끄기 |
| 고정 카메라 | 쿼터뷰 시점으로 모델 동작과 효과 확인 |
| 소리 | 합성 엔진음·마찰음·파손음·폭발음 켜기·끄기 |
| H | 테스트 UI 숨기기·표시하기 |
| Esc / 로비로 | 로비로 복귀 |

일시정지와 배속은 연출 공간의 시계에만 적용한다. 엔진의 `Engine.time_scale`이나 본선 전투 상태는 바꾸지 않는다. 타임라인 끝으로 이동하면 마지막 화면을 유지한다.

## 5.20초 구성

| 시간 | 모델·시각효과 | 카메라 |
|---|---|---|
| 0.00–0.20 | 붉은 코어 피격, 오른쪽 궤도 이탈, 금속 스파크 | 진입 쿼터뷰, 짧은 섬광 |
| 0.20–1.00 | 오른쪽 2m 미끄러짐, 방향 20° 틀어짐, 마찰 흔적 | 낮은 측면으로 부드럽게 이동 |
| 1.00–2.00 | 차체 0→35° 기울어짐, 포신 처짐, 연기 | 차체와 도로가 함께 보이는 전복 준비 구도 |
| 2.00–2.85 | 차체 35→90° 전복, 2.70초 충돌, 짧은 정지와 반동 | 낮은 충돌 구도, 폭발 전에 뒤로 이동 |
| 2.85–3.60 | 2차 폭발, 포탑 분리, 파편·충격파·연기 | 넓은 폭발 구도, 제한된 흔들림 |
| 3.60–5.20 | 보스 잔해 후방 이동, 플레이어가 왼쪽 안전 경로로 통과 | 원래 쿼터뷰로 복귀 |

궤도와 포탑은 미리 정한 속도·중력·회전으로 움직인다. 전복은 지면 모서리 축을 기준으로 진행하며 매 단계 바닥 높이를 보정한다. 자유 래그돌에 의존하지 않으므로 컷 이동과 재생 결과를 재현할 수 있다. 포탑 분리 후에도 차체의 바닥 접촉을 다시 계산한다.

## 구현 파일과 조정 위치

| 파일 | 책임 |
|---|---|
| `scenes/mammoth_death_lab.tscn` | 테스트 공간 진입점 |
| `scripts/mammoth_death_lab.gd` | 관람 UI, 입력, 로비 복귀, 조명·환경 |
| `scripts/presentation/mammoth_death_b.gd` | 6컷 시간표, 모델 포즈, 카메라, 단발 이벤트 |
| `scripts/presentation/mammoth_death_lab_fx.gd` | 스파크·연기·파편·잔해·폭발·오디오 수명 |
| `scripts/lobby.gd` | 테스트 공간을 여는 전용 버튼 |

씬의 `Presentation` 노드 인스펙터에서 `skid_distance`, `shake_strength`, `flash_strength`, `fixed_camera`, `seed_value`를 조정한다. 카메라 위치·주시점·FOV는 `_camera_pose()`, 전복 각도와 플레이어 동작은 `_apply_pose()`, 효과 발생은 `_cues()` / `_emit_continuous()`에서 조정한다.

스파크는 최대 160개, 연기는 최대 48개다. 같은 재생에서 피격·궤도 파손·충돌·폭발은 각각 한 번만 발생한다. 다시 재생하거나 컷을 이동하면 해당 공간이 소유한 모델·잔해·효과를 초기화한다. 마찰 루프음은 일시정지 중 멈추고, 로비 복귀 시 모든 연출음을 정리한다.

합성 효과음은 타이밍 확인용이다. 승인 후 본선 연결 시에는 실제 죽음 트리거, 전투 입력 차단 범위, 승리·보상 시점, 본선 카메라의 복구를 별도로 연결해야 한다.

## 확인 결과와 재현

Godot 4.6.3에서 30·60·144FPS 시뮬레이션, 10회 초기화·컷 이동, 단발 이벤트와 완료 신호, 지면 접촉, 일시정지·배속, 흔들림·섬광 끄기, 고정 카메라, 로비 왕복을 자동 검증했다. 테스트 공간에서 `Main`을 생성하지 않으며 런의 체력·점수·코인·처치·섹터 값을 유지한다.

실제 Forward+ / Vulkan / RTX 3070에서 1280×800 화면을 캡처해 구도를 확인했다. 고정 프레임 캡처는 동작 검증이며 성능 벤치마크는 아니다. 다른 GPU와 해상도, 실제 스피커 청감 검증은 별도 확인 대상이다.

```powershell
# 자동 검증
& '<Godot 콘솔 실행 파일>' --headless --path . -s tests/mammoth_death_lab_check.gd

# 실제 엔진 영상 프레임 캡처 (60FPS, 4프레임마다 저장)
& '<Godot 콘솔 실행 파일>' --path . --scene res://scenes/mammoth_death_lab.tscn --fixed-fps 60 --resolution 1280x800 --audio-driver Dummy -- --lab-capture=res://_capture/mammoth_death_b_render --lab-every=4 --lab-seconds=7

# 정지 화면: 위 명령 끝에 --lab-seek=2.70 추가
# UI 없이 확인: --lab-clean 추가, 관람 중에는 H 키

# 로비 캡처
& '<Godot 콘솔 실행 파일>' --path . --resolution 1280x800 -s docs/mammoth-death/tools/capture_lobby.gd
```

실제 엔진 캡처는 `output/mammoth-death-b/engine-preview.gif`, 6컷 비교는 `engine-contact-sheet.jpg`에 저장한다. 기존 [B안 콘티](storyboard-B.png)와 [기능명세서](맘모스_죽음연출_기능명세서.md)를 함께 참고한다.
