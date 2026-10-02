# 원본 부피 보존 메카의 플레이어 적용 인수인계

작성: 2026-10-02 · Codex → Claude

새 메카의 관절 분리 작업은 완료했으며 **실제 플레이어 연결은 아직 하지 않았다.** 다음 작업은 아래 GLB를 전투 테스트 씬의 플레이어로 연결하고 기존 조작·무기·연출이 작동하도록 만드는 것이다. 현재 구현 상태와 미구현 제안을 구분해 기록했다.

프로젝트 루트: `C:/Users/Loadcomplete/Documents/ChatGPT/3D 쿼터뷰 슈팅게임_Claude`

먼저 루트 [AGENTS.md](../AGENTS.md)를 읽는다. 엔진은 Godot이며 SlimeForge 전용 스킬 규칙은 적용하지 않는다. 다른 작업의 미커밋 변경이 많으므로 기존 수정·미추적 파일을 되돌리거나 일괄 정리하지 않는다. 커밋·푸시는 사용자 요청이 있을 때만 한다.

## 1. 가장 중요한 사용자 요구

> 부위를 나누되, 원본의 부피를 최대한으로 보존하는데 신경써줘. 원본의 부피감을 보존하지 못한다면 디자인이 완전 바뀌어버려서 의미를 잃으니까 말이야.
> 일부분은 겹쳐도 되고, 그것때문에 외형의 부피를 줄여버리는 것은 하지마.

- 팔다리·어깨·골반의 두께와 장갑 실루엣을 유지한다.
- 관절이 조금 겹치는 것은 허용한다. 교차 검사 0을 목표로 장갑을 줄이거나 가늘게 만들지 않는다.
- 큰 간섭은 **피벗, 기본 자세, 동작 각도, 내부 마감**부터 조정한다.
- 이전 `tripo_mecha_proto`의 단순하고 작아진 장갑을 이식하지 않는다.
- 크기 조정이 필요하면 전체 루트의 균일 배율을 검토한다. 부위별 축소·비균일 스케일로 체형을 바꾸지 않는다.
- 높은 등 장식은 삭제 상태를 유지한다. 낮은 원본 배낭·배기구는 남아 있다.

## 2. 사용할 파일

아래 경로는 프로젝트 루트 기준이다.

| 용도 | 경로 |
|---|---|
| **실제 적용할 GLB** | `assets/models/mech_volume_preserved.glb` |
| 모델링 작업본 | `output/models/mech_volume_preserved/mech_volume_preserved.blend` |
| 자세 시험 파일 | `output/models/mech_volume_preserved/pose_trial.blend` |
| Blender 확인 실행기 | `mech_volume_pose.cmd` |
| 가동 시험 영상 | `output/models/mech_volume_preserved/pose_trial.mp4` |
| 분리 전후 외형 비교 | `output/models/mech_volume_preserved/preservation_compare.png` |
| 네 자세 비교 | `output/models/mech_volume_preserved/pose_review.png` |
| 제작 스크립트 | `models/src/mech_volume_preserved.py` |
| 자세 시험·렌더 | `tools/blender/mech_volume_review.py` |
| 독립 GLB 보존 검사 | `tools/blender/mech_volume_verify.py` |
| Godot 모델 검사 | `tests/mech_volume_check.gd` |
| 상세 제작 기록 | `output/models/mech_volume_preserved/NOTES.txt` |
| 측정 근거 | 같은 폴더의 `build_audit.json`, `review_metrics.json`, `export_verification.json`, `validation.json`, `stats.txt` |

새 원본은 `C:/Users/Loadcomplete/Downloads/mech suit 3d model.glb`, 보존 사본은 `models/source/mech_user/original.glb`다. 원본 폴더의 `.gdignore`를 유지한다.

이전 원본은 **`mecha suit 3d model.glb`**였다. `mech`와 `mecha`를 혼동하지 말 것. `assets/models/tripo_mecha_proto.glb`, `models/src/tripo_mecha_proto.py`, `tripo_mecha_pose.cmd`는 이전 시제품이다. 보존은 하되 이번 적용 대상으로 쓰지 않는다.

제작 완료 시 SHA256:

```text
새 원본
a3f3197a004c23281769d53fac7fd82988a8bd33ef65d10c0c2920d5af93d259

mech_volume_preserved.glb
85912898d42f77bce2764bfa92082ef389659b6b82bb316a9249fc3310850d39
```

모델 수정·재생성 후에는 다시 검증한다. Godot가 추출한 `mech_volume_preserved_*` 텍스처와 `.import`, 테스트의 `.uid`도 함께 관리한다.

## 3. 모델의 현재 상태

- 높은 등 장식 원본 파츠 1/2/14 삭제, 바닥 액체 8/15 제외.
- 남은 원본 17개 파츠의 외피를 모두 보존하여 관절별 외피 27개로 분리.
- 무릎·발목 내부 연결부 4개 추가. 총 메시 오브젝트 31개, 삼각형 13,429개.
- 외부 표면의 축소·평활화·데시메이션·간섭 회피용 재성형 없음. 분할 경계에서 새 점과 UV·노멀을 보간하고 내부 마감 면 추가.
- 전체 2.35배 배율과 전방 축 회전은 **이미 메시 좌표에 반영되어 있다. 다시 2.35배 하지 말 것.**
- Blender 크기 X 2.094 / Y 1.513 / Z 1.797m. Godot에서는 대략 폭 2.094 / 높이 1.797 / 깊이 1.513m.
- Blender +Y가 전방, Godot에서는 -Z가 전방이다. 바닥은 Godot Y=0.
- 스키닝된 골격이 아니라 **Node3D 부모 자식 계층으로 움직이는 단단한 파츠 리그**다. Skeleton3D는 필수가 아니다.
- 엔진 GLB는 중립 자세다. 시험 애니메이션은 별도 `pose_trial.blend`에 있다.

일부 원본의 열린 경계 때문에 절단면 안쪽 마감이 덜 된 곳이 있다. 큰 각도에서 틈이나 겹침이 보일 수 있다. 손가락 개별 리그·검 그립·완성 전투 모션·재질 아틀라스 통합은 미완성이다.

## 4. 관절과 부착점

아래는 메시를 생략한 주요 변환 노드다. GLB 안의 `body` 관절과 `Player.body`라는 외부 시각 루트 변수는 다르다.

```text
MechRoot
└─ pelvis
   ├─ body
   │  ├─ head
   │  ├─ shoulder_hand → arm_hand_upper → arm_hand_fore → hand → pt_grip
   │  ├─ shoulder_gun → arm_gun_upper → arm_gun_fore → gun_mount → pt_muzzle
   │  ├─ pt_booster_hand
   │  └─ pt_booster_gun
   ├─ hip_hand → knee_hand → ankle_hand → pt_foot_hand
   └─ hip_gun → knee_gun → ankle_gun → pt_foot_gun
```

`*_original`은 외피 메시, `inner_*`는 추가 연결부다. 모두 한 메시로 합치면 관절 분리를 잃는다. `pt_*`는 위치를 잡은 시험용 마커이며 **총구·검·불꽃의 최종 방향과 그립까지 확정한 것이 아니다.** 실제 총신과 무기 궤적에 맞춰 자식 보정 노드나 자세를 조정한다.

## 5. 기존 플레이어 코드 연결 지점

문서 작성 시 확인한 내용이다. 작업 시작 때도 해당 함수를 읽는다.

| 파일·함수 | 현재 역할 |
|---|---|
| `scripts/player.gd` `_ready()` | `visual → lean → body`를 만들고 `j = Build.robot(body)`로 관절 사전을 얻는다. 직후 `PlayerMotion.rig()`, 무기 FX, 리본 등을 연결 |
| `scripts/build.gd` `robot()` | 현재 보라색 코드 생성 플레이어. `robot_mech()`는 별도의 크림색 기체이므로 혼동 금지 |
| `scripts/player.gd` `_animate()` | 상·하체 회전, 걷기, 다리, 반동, 검 자세 등. `j`의 노드를 직접 갱신 |
| `scripts/presentation/player_motion.gd` | 사격·재장전·레이저·미사일 연출. `rig()`에서 총 부품 재배치 |
| `scripts/sword_combo.gd` | 6단 콤보. 팔·검·상체·다리 각도와 검 길이 방향에 의존 |
| `scripts/blade_tech.gd` | 기 모으기·돌진·회전·회피 레이저. 팔·다리·검·부스터 조작 |
| `scripts/training/training_main.gd`, `scenes/training.tscn` | 최초 실제 적용과 전투 검증에 사용할 테스트 씬 |

기존 `j`의 필수 노드는 `legs`, `upper`, `torso`, `hip_l/r`, `knee_l/r`, `foot_l/r`, `arm_l/r`, `muzzle`, `blade`, `jet_l/r`다. 몸 리본용 로컬 좌표 `arm_base`, `arm_tip_l/r`, `leg_trail`도 필요하며, 현재 `robot()`은 반동용 `shoulder_l/r`도 제공한다.

**구현 제안:** GLB 로더와 이 계약을 제공하는 별도 어댑터를 둔다. 단순 이름 치환만으로는 충분하지 않다.

### 반드시 처리할 호환성 문제

1. **좌우가 반대다.** 기존 `arm_l`은 사격, `arm_r`은 검 담당. 기존 총은 -X 쪽이지만 새 GLB의 총은 +X, 손은 -X 쪽이다. 팔은 역할 기준으로 `arm_l → gun 쪽`, `arm_r → hand 쪽` 연결을 검토한다. 다리 l/r은 이동 좌표 기준으로 별도 결정한다(-X는 `hip_hand`, +X는 `hip_gun`). 전신 좌우를 일괄 교환하거나 음수 스케일로 원형을 뒤집지 않는다.
2. **상·하체 이중 회전.** 기존 `upper`와 `legs`는 독립 회전을 전제로 하지만 새 `body`는 `pelvis`의 자식이다. `legs=pelvis`, `upper=body`로 바로 연결하면 하체 회전에 상체 회전이 중첩된다. 독립 제어 래퍼나 부모 회전 보상이 필요하다. 재부모화 시 중립 자세의 전역 변환을 유지한다.
3. **고정값이 휴지 자세를 덮어쓴다.** `_animate()`는 `upper.position.y=0.74` 부근을 직접 대입하고 팔·무릎도 기존 리그 기준 각도로 설정한다. 새 관절의 위치와 길이를 보존하도록 휴지 변환에 차이를 더하거나 호환 노드를 둔다. 기존 리그에 부족한 팔꿈치·손목의 기본 자세도 정해야 한다.
4. **GunSpin이 잘못된 부품을 옮길 수 있다.** `PlayerMotion.rig()`는 `arm_l` 직계 자식 중 `position.z < -0.05`를 총 부품으로 간주해 `GunSpin`으로 옮긴다. 새 전완 등을 잘못 옮기지 않도록 `gun_mount` 등의 명시적 참조를 사용하고 어깨·팔꿈치 계층을 보존한다.
5. **총구와 탄도 높이가 다르다.** `_fire()`는 총구 전역 위치를 얻고도 Y를 `player.global_position.y + 0.95`로 덮어써 수평탄을 발사한다. 새 총신과 탄/섬광이 어긋날 수 있다. 판정용 탄도와 시각적 발사점을 구분하고 다른 레이저 경로도 점검한다. 모델 연결 때문에 판정 규칙을 무심코 바꾸지 않는다.
6. **검을 별도로 연결한다.** 새 모델에 게임용 광선검은 없다. `pt_grip` 근처에 검 제어 노드·검날·기존 FX를 붙인다. 기존 콤보는 검의 로컬 -Z와 `to_global(Vector3(0,0,-1.3))` 등을 사용하므로 방향과 길이를 맞춘다. 펼친 손가락의 그립은 아직 가공하지 않았다.
7. **부스터는 마커만으로 부족하다.** `jet_l/r`은 늘이기·숨기기·회전을 적용할 불꽃 루트다. `pt_booster_*`에 실제 불꽃을 연결하고, 배낭이나 장갑 자체를 늘이거나 숨기지 않는다. 미사일 발사점도 제트 참조를 사용한다.
8. **발 FX의 고정 오프셋.** `_update_rush()`는 `j.foot_*`에서 `(0,-0.12,-0.05)`를 더한 위치를 발밑으로 본다. 새 `pt_foot_*`는 이미 바닥 기준이라 그대로 대입하면 오프셋이 중복된다. 마찰 불꽃 위치를 맞춘다.
9. **기존 찌그러짐 연출.** `_animate()`는 `Player.body.scale`에 비균일 squash 값을 넣는다. 새 메카에서는 끄거나 원형 보존에 맞게 조정하는 방안을 검토한다. 원본 부피를 보존한다면서 지속적으로 비균일 축소하지 않는다.
10. **충돌체와 외형은 별개다.** 현재 플레이어 캡슐은 반지름 0.42, 높이 1.4, 중심 Y=0.7이다. 새 기체는 폭이 넓다. 팔을 줄여 맞추지 말고 카메라·그림자·가림·좁은 통로의 시각적 겹침을 확인한다. 충돌체 확대는 조작감·난이도를 바꾸므로 외형에 자동으로 맞추지 않는다.

## 6. 권장 구현 순서

아래는 **아직 구현하지 않은 적용 계획**이다.

1. 새 메카 로더/어댑터를 만들고 기존 `Build.robot`으로 복귀할 수 있는 전환을 남긴다. 먼저 training에서 검증한다.
2. 중립 자세에서 원형·좌우·발바닥·크기를 확인한다. 비교 이미지와 같은 두께인지 확인하고 원점 정렬 때문에 메시를 변형하지 않는다.
3. 상·하체 독립 회전과 보행을 연결한다. 휴지 자세를 유지하면서 무릎·발목과 접지를 조정한다.
4. 총 기본 자세, 사격·재장전·충전·레이저를 연결한다. `GunSpin`의 잘못된 재부모화를 먼저 막는다.
5. 검·6단 콤보·기 모으기 돌진·회피를 연결하고 리본의 로컬 좌표도 다시 계산한다.
6. 부스터·비행·미사일·착지·발 마찰·피격·사망 표시를 확인한다.
7. 실제 화면과 입력 확인 후 본편에 적용한다. 코드 변경 후 전체 테스트와 변경 씬 bot을 실행하고 AGENTS.md를 갱신한다.

안쪽 틈이나 클리핑을 발견해도 외피를 작게 만들어 해결하지 않는다. 조금의 겹침을 허용하고 외관을 지키는 대처를 우선한다.

## 7. 검증 범위

- 원본과 보관 사본 SHA256 일치, 이전 모델 보존.
- 남긴 17개 파츠의 원본 삼각형별 표면적 추적 결과 유실 면적 0.
- 실제 출력 GLB 재임포트 후 원본 정점 최대 위치 차이 약 `2.41e-7m`.
- 네 방향 512px 실루엣의 원본 영역 유지율 100%. 내부 연결부 때문에 측면만 3픽셀 추가.
- 시험 클립 160프레임 저장 후 주요 자세 재검증. 웅크림 하강 0.11m, 발 기준점 높이 최대 오차 약 `7.53e-8m`.
- Godot 전체 17종 PASS. 이후 최종 GLB 재임포트와 모델 검사 2종도 PASS.
- 기존 training 20초 bot ERROR/SCRIPT ERROR 0. **이 실행은 새 모델을 사용하지 않았다. 새 메카의 전투 검증 완료를 뜻하지 않는다.**
- 종료 시 ObjectDB 경고 34건이 있었으며 이번 모델 작업에서는 원인을 조사하지 않았다. 오류 0을 경고 0으로 해석하지 않는다.

새 모델의 실제 이동·전체 액션·충돌 판정·무기 궤적·게임 FPS는 미검증이다. 중립 실루엣 검사는 모든 애니메이션의 외관을 보장하지 않는다. 원본에 열린 메시가 있으므로 닫힌 입체의 수학적 부피를 직접 측정한 것도 아니다. 근거는 외피·정점·UV·렌더 실루엣 보존이다.

## 8. 실행 및 검증 명령

프로젝트 루트에서 실행한다. Godot는 `tools/godot.ps1`, Blender는 `tools/blender.ps1`을 반드시 거친다. 버전은 각 `*-version.txt` 기준이며 제작 검증은 Godot 4.7.2 표준 빌드와 Blender 5.2.2 LTS였다.

```powershell
# 자세 시험: 1 중립 / 40 총 조준 / 80 팔 들기 / 120 웅크림 / 160 중립
.\mech_volume_pose.cmd

# 임포트
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File tools\godot.ps1 wait --headless --import

# 모델 검사
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File tools\run_tests.ps1 mech_volume_check blender_models_check

# 코드 변경 후 전체 테스트
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File tools\run_tests.ps1

# 새 모델 선택 기능을 구현했다면 해당 선택 인자도 붙일 것
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File tools\godot.ps1 wait --headless --fixed-fps 60 res://scenes/training.tscn -- --bot --seed=1 --seconds=20

# 창을 띄워 동작을 눈으로 확인
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File tools\godot.ps1 wait --fixed-fps 60 res://scenes/training.tscn -- --bot --actshow --seconds=30
```

캡처 시 폴더를 미리 만들고 공백 없는 프로젝트 상대 경로를 `--capture=...`로 넘긴다. 추가한 선택 기능이 실제 새 메카를 선택했는지 로그와 화면 모두로 확인한다.

모델 재생성이 필요한 경우만 `NOTES.txt`의 Blender 명령을 사용한다. 제작 스크립트 재실행은 출력 GLB/BLEND를 덮어쓰므로 수동 편집본이 있다면 먼저 보존한다.

이번 인수인계 문서 작성에서는 게임 코드와 모델을 변경하지 않았다.
