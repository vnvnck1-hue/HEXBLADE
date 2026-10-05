# 현재 합체 연출에 선택 보이스 9개 적용 — 인수인계

작성: 2026-10-05 · Codex · 대상: HEXBLADE / Godot 4.7.2 표준 빌드

## 1. 요청과 현재 완료 범위

사용자는 스파랜드 여성 보이스 청음 목록에서 **공격·기합 9개를 사용 체크**했고, 이 소리들을 **현재 합체 연출에 넣기 위해 인수인계 Markdown 문서를 작성**해 달라고 요청했다.

- 현재 합체 연출은 **Q 즉시 합체의 사선 DOCKING 컷인**이며, 캐릭터는 보라 양갈래 정비사다.
- 이 문서를 작성하면서 실제 음성 적용이나 게임 코드 변경은 하지 않았다. 다음 작업자가 구현한다.
- 9개 사용 선택은 확정이다. 각 파일의 역할, 재생 시점, 선택 방식, 볼륨은 사용자가 별도로 지정하지 않았다. 아래 구현 기본안은 **제안**이다.
- 선택 기록은 `output/spaland-voices-20261005/selections.json`, revision **13**, 갱신 시각 **2026-10-05 17:59:10 KST** 기준이다. 9개 모두 메모는 비어 있다.
- `wao.mp3`는 체크 해제 상태다. 아래 9개만 적용 대상으로 삼는다. 나머지 494개는 이번 적용 대상이 아니다.

## 2. 확정 에셋 목록

현재 PC의 원본 폴더는 프로젝트 루트 기준:

```text
output/spaland-voices-20261005/audio/battle_attack/
```

| 파일명 | 보이스 코드 | 청음 목록의 일본어 설명 | 길이 | 제작자 원본 다운로드 URL |
|---|---|---|---:|---|
| `shozyo2-torya.mp3` | shozyo2 | 설명 없음 | 0.744초 | [원본 MP3](https://blog-imgs-101.fc2.com/s/p/a/spaluna/shozyo2-torya.mp3) |
| `shozyo2-atare.mp3` | shozyo2 | 설명 없음 | 1.368초 | [원본 MP3](https://blog-imgs-101.fc2.com/s/p/a/spaluna/shozyo2-atare.mp3) |
| `shozyo2-eiya.mp3` | shozyo2 | えいや！ | 0.864초 | [원본 MP3](https://blog-imgs-101.fc2.com/s/p/a/spaluna/shozyo2-eiya.mp3) |
| `shozyo2-ta.mp3` | shozyo2 | たあ！ | 0.816초 | [원본 MP3](https://blog-imgs-101.fc2.com/s/p/a/spaluna/shozyo2-ta.mp3) |
| `shozyo1-to.mp3` | shozyo1 | とお！ | 0.480초 | [원본 MP3](https://blog-imgs-116.fc2.com/s/p/a/spaluna/shozyo1-to.mp3) |
| `shozyo1-ya.mp3` | shozyo1 | やあ！ | 0.600초 | [원본 MP3](https://blog-imgs-116.fc2.com/s/p/a/spaluna/shozyo1-ya.mp3) |
| `shozyo1-atattekudasai.mp3` | shozyo1 | あたってください | 1.320초 | [원본 MP3](https://blog-imgs-116.fc2.com/s/p/a/spaluna/shozyo1-atattekudasai.mp3) |
| `shozyo1-ei.mp3` | shozyo1 | えい！ | 0.384초 | [원본 MP3](https://blog-imgs-116.fc2.com/s/p/a/spaluna/shozyo1-ei.mp3) |
| `zyosei4-ta.mp3` | zyosei4 | 攻撃２ | 0.696초 | [원본 MP3](https://blog-imgs-116.fc2.com/s/p/a/spaluna/zyosei4-ta.mp3) |

위 두 설명 없는 파일의 발화 내용은 파일명에서 추측해 확정하지 않는다. 코드는 사이트의 구분값이며 실제 성우 인원수를 뜻한다고 단정하지 않는다.

9개는 모두 48 kHz MP3이며 총 **89,304바이트**다. 원본 바이트를 보존했다. 이번 문서 작성 시 9개 모두 존재하고 보관 manifest의 SHA256과 일치함을 다시 확인했다. 앞선 다운로드 작업에서는 고정 Godot 4.7.2에서 전체 503개 PCM 디코딩·유한값·비무음 검증을 통과했다. 실제 합체와의 믹스 청음은 아직 하지 않았다.

## 3. 현재 코드의 실제 연결 지점

설명 문서: [사선 DOCKING 구현 기록](diagonal-docking-cutin.md), [드론](partner-drone.md).

| 위치 | 현재 동작 | 음성 적용 시 의미 |
|---|---|---|
| [PartnerDrone.whirl_link](../scripts/drone/partner_drone.gd) | 게이지 `WHIRL_COST = 30` 이상일 때 `_begin_recall(true)` 호출 | Q 거절·재입력 차단 상태에서는 음성이 나오면 안 됨 |
| `PartnerDrone._begin_recall(fast)` | `fast=true`에서 컷인 생성, 비행 시작. `launch`, `drone_hop` 효과음 | 음성 선행 재생을 택할 때의 후보. 기본안은 여기서 음성을 재생하지 않음 |
| `PartnerDrone._recall(dt)` | 실제 등에 붙으면 DOCKED로 전환. 즉시 합체는 `_gattai_impact()`, 이후 휠윈드 시작 | Q를 눌렀다는 사실 대신 실제 합체 성공에 맞춰 재생 가능 |
| `PartnerDrone._gattai_impact()` | 컷인 `notify_dock` 호출, 섬광·충격·기존 합체 효과음 재생 | **본편 음성 재생 기본 연결 지점** |
| [DiagonalDockingCutin.notify_dock](../scripts/drone/diagonal_docking_cutin.gd) | 실제 합체 순간 띠·인물·선 펄스. 재호출 방어 있음 | 음성 중복 호출을 만들지 말 것 |
| `DiagonalDockingCutin._process` | F3 미리보기는 약 0.22초에 스스로 `notify_dock()` 호출 | 본편과 분리된 청음 미리보기 연결 가능 |
| `DiagonalDockingCutin.prewarm` | 씬 시작 때 투명 3프레임으로 렌더 준비 | **음성 재생 금지**. 미리보기와 같은 `preview=true`이므로 구분 필요 |
| [Sfx.play](../scripts/sfx.gd) | 공용 AudioStreamPlayer 24개 중 빈 플레이어 사용, 무작위 피치, 음소거면 새 재생 생략 | 기본 함수는 합성 효과음용. 보이스 수명·피치·음소거를 따로 검토 |

현재 시간 흐름:

```text
Q 승인 → 컷인/비행 시작 → 약 0.22초에 실제 합체 → 휠윈드 → 자동 분리
          세계 0.1배속       notify_dock + 기존 합체 효과음
```

사선 컷인과 합체 비행은 실제 경과 시간에 맞춘다. 컷인 정상 정리는 약 1.13초이며, 세계 슬로우모션과 물리 틱 고정 규칙은 유지한다.

## 4. 다음 작업자의 구현 기본안 — 제안

### 재생 규칙

1. **Q 즉시 합체가 실제로 성공하는 순간에 9개 중 1개를 한 번 재생**한다. 현재 기본인 사선 DOCKING을 대상으로 한다.
2. 9개를 모두 후보로 사용하고, 직전 파일의 연속 반복은 피한다. 음성 선택은 독립 RNG를 사용해 게임의 적 배치·봇 seed 등에 영향을 주지 않는다.
3. Q 입력, 컷인 시작, `notify_dock`, 휠윈드 시작에 각각 음성을 붙이지 않는다. 한 합체에 재생 경로는 하나다.
4. 게이지 부족, 비행 중 취소, 합체 실패에는 성공 음성이 없어야 한다. 일반 G 합체, 이미 붙은 상태에서 Q로 휠윈드만 시작하는 경우, 자동 분리에는 추가하지 않는다.
5. 예전 `cockpit`/`off` 비교 모드의 동작은 보존한다. 이번 작업에서 음성 적용 범위를 그 모드들로 확대할 필요는 없다.
6. 피치는 **1.0 고정**, 루프는 끈다. 최초 볼륨은 **-6 dB를 청음용 시작값**으로 삼되, 기존 합체 효과음과 함께 듣고 조정한다. 확정 믹스 값은 아니다.

사용자가 선택한 9개는 서로 다른 사이트 보이스 코드를 포함한다. 한 캐릭터의 음색을 통일하려고 임의로 일부를 제외하거나, 다른 음성을 새로 추가하지 않는다. 긴 두 파일도 선택 대상에 포함한다.

### 재생 노드와 수명

- 전용 2D `AudioStreamPlayer` 하나를 드론 또는 Main 아래에 둔다. 화면 컷인 음성이므로 거리 감쇠가 있는 3D 재생은 기본안에 필요하지 않다.
- 전용 플레이어를 **짧게 사라지는 컷인 노드의 자식으로 두지 않는다**. `shozyo2-atare`는 합체 시점부터 끝까지 약 1.37초, `shozyo1-atattekudasai`는 약 1.32초여서 컷인이 먼저 사라질 수 있다. 정상 컷인 종료·자동 분리는 음성 끝을 자르지 않는다.
- 음성 때문에 컷인 체류를 늘리거나, 슬로우모션을 더 오래 유지하지 않는다. 시각 연출 종료 후에도 음성만 자연스럽게 끝나도록 한다.
- 새 합체 음성이 시작될 때 이전 음성이 남아 있으면 교체해 동시 보이스를 최대 1개로 제한한다. 사망·씬 전환·소유자 제거에는 재생을 정리한다.
- 게임 일시정지에서는 보이스도 멈추고, 재개하면 이어서 재생한다. 컷인은 `PROCESS_MODE_ALWAYS`를 쓰므로 이 모드를 그대로 복사해 일시정지 중 음성만 계속 나오게 하지 않는다.
- 기존 M 키 음소거는 `Sfx.inst.muted`를 바꾼다. 별도 보이스 플레이어도 이 값을 따라야 한다. 새 재생 차단뿐 아니라 **이미 재생 중인 보이스의 음소거**도 처리한다.
- 슬로우모션·히트스탑 동안 목소리 피치와 재생 속도는 1.0을 유지한다. 시간 배율에 따라 목소리가 늘어지게 하지 않는다.

### 미리보기와 효과음

- 허수아비 시험장 F3에도 선택 보이스를 확인할 수 있는 경로를 제공하는 것을 권장한다. F3의 미리보기 `notify_dock` 때 같은 보이스 선택/재생 헬퍼를 호출하되, 본편 호출과 겹치지 않게 한다.
- `prewarm`은 `preview=true`이기도 하다. 미리보기 여부만 검사해 재생하지 말고 **`_warm > 0`이면 항상 무음**임을 보장한다.
- 9개를 각각 강제로 재생해 확인할 수 있는 개발용 선택값을 두면 튜닝과 검증이 쉽다. 기본 플레이는 9개 중 한 개 선택으로 둔다.
- 기존 `launch`/`drone_hop` 및 합체 순간 `drone_dock`(+2 dB), `boom`(-6 dB), `drone_burst`(-3 dB)는 현재 남아 있다. 이 소리와 보이스를 함께 청음한다. 필요하면 합체 구간 효과음 볼륨을 국소 조정하되, 전역 `Sfx` 볼륨이나 다른 전투 효과음을 일괄 변경하지 않는다.

## 5. 리소스 배치·다른 PC·배포

현재 다운로드 폴더는 **`.gdignore` 때문에 Godot 임포트 대상이 아니며, `.gitignore` 때문에 Git에도 올라가지 않는다**. 본편에서 이 폴더에 직접 의존하지 않는다. `selections.json`이나 청음 서버에 런타임 의존성도 만들지 않는다.

구현 때 선택한 9개만 다음 경로로 원본 파일명 그대로 복사하는 것을 권장한다:

```text
assets/audio/voices/spaland_docking/<위 표의 파일명>.mp3
```

위 경로는 **예정 경로**이며 아직 생성하지 않았다. Godot에서 임포트된 `AudioStreamMP3`를 로드해 사용하고, 루프 꺼짐·리소스 로딩 성공을 확인한다. 첫 합체 프레임에 9개를 동기 다운로드하거나 디코딩하지 않는다. 로컬 리소스를 미리 로드한다. Godot 버전에 따라 생기는 `.import`/`.uid`는 프로젝트 인수인계 규칙대로 원본과 함께 관리한다.

다른 PC에는 기존 다운로드 폴더가 Git으로 따라가지 않는다. 위 표의 제작자 원본 URL에서 9개를 다시 받거나, 제작자가 허용한 범위의 내부 전달로 준비하고, 아래 SHA256을 확인한다. 공개 원본 소재 ZIP이나 공개 Git 저장소에 MP3를 그대로 올리는 방식으로 해결하지 않는다. 별도 공개 저장소에서 구현할 경우 원본 MP3와 관련 임포트 메타데이터의 제외 규칙을 명시하고, 문서·코드·다운로드 절차로 재현한다.

출처: [스파랜드 소재 사이트](https://soalunashosya.jimdofree.com/), [선택 파일 게시 페이지](https://soalunashosya.jimdofree.com/戦闘系/), [공식 이용약관](https://soalunashosya.jimdofree.com/利用規約/).

보관된 약관은 갱신일 2026/4/30, 확인·다운로드일 2026-10-05 기준이다. 상업 게임 사용·편집·피치 변경 허용, 보고·링크·크레딧 선택 사항, 원본 소재의 별도 판매·재배포 및 AI 학습 금지. 소재를 넣은 게임의 배포는 허용한다고 안내한다. 실제 배포 전 원문을 재확인한다. 보관 원문은 `output/spaland-voices-20261005/terms_original.txt`다.

선택 사항인 크레딧을 넣는다면 제작자 표기 예시는 다음과 같다:

```text
フリーボイス素材屋すぱらんど。/すぱるな瀟洒
https://soalunashosya.jimdofree.com/
```

## 6. 구현 후 확인할 것

- 허수아비 `training.cmd`: Q 합체 때 보이스가 실제 합체 충격과 맞고, 1회만 나오는지 확인한다. 기본 재화 무한으로 반복 청음한다.
- 9개를 각각 재생해 누락·무음·파일 혼동이 없는지 확인한다. 긴 두 음성은 컷인이 사라져도 정상 끝까지 재생되어야 한다.
- 실제 시작/끝 시각, 선택 파일명, 한 합체의 호출 횟수를 개발 로그로 확인한다. 슬로우모션·히트스탑 중에도 음성이 정상 속도로 나오는지 귀로 확인한다.
- Q 연타·게이지 부족·합체 전 취소·사망·씬 재진입·일시정지/재개·재생 중 M 음소거를 확인한다.
- F3 미리보기 음성은 나오고, 씬 시작 `prewarm`에서는 나오지 않아야 한다. 일반 G 합체·분리·이미 붙은 상태의 휠윈드에는 이번 보이스가 추가되지 않아야 한다.
- 기존 사선 컷인 위치·트위닝·슬로우모션 복귀, 게이지 30 비용, 휠윈드 무적·자동 분리 기능을 유지한다. 예전 컷인 삭제는 이번 범위에 포함하지 않는다.
- 필요한 음성 검사와 기존 `diagonal_cutin_check`, `partner_drone_check`, `training_whirl_check` 등을 포함해 전체 검사를 실행한다. 헤드리스 검사는 청음 믹스 평가를 대신하지 않는다.

엔진은 반드시 프로젝트의 고정 실행기를 사용한다. Windows PowerShell의 프로젝트 루트 예시:

```powershell
# 신규 리소스 임포트
powershell -NoProfile -ExecutionPolicy Bypass -File tools/godot.ps1 wait --headless --import

# 전체 회귀 검사
./run_tests.cmd

# 본편 자동 플레이, 합체 동작 포함
powershell -NoProfile -ExecutionPolicy Bypass -File tools/godot.ps1 wait --fixed-fps 60 res://scenes/main.tscn -- --bot --dronebot --seed=4 --seconds=60
```

`powershell`이 PATH에 없으면 `$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe`를 사용한다. PowerShell에서 배치 실행은 `./run_tests.cmd`로 실행할 수 있다. 새 리소스의 임포트 결과와 실제 재생 확인, 자동 플레이의 `ERROR`/`SCRIPT ERROR` 0을 기록한다. 커밋·푸시는 사용자 요청이 있을 때만 한다.

## 7. 선택 원본의 SHA256

아래 값은 다운로드 manifest와 이번 실파일 재검사의 일치값이다. 선택 원본이 바뀌었는지 확인할 때 사용한다.

```text
8d899310f6ea37584cfab7387910c8f9dbc3260714d0a978227877d138959b32  shozyo2-torya.mp3
4cad3bdcae4776e9e6fc3b589da2b495e1bb83d29037439bad5b8222ada2861e  shozyo2-atare.mp3
147cbc9d86591c29751c1b9a31ee4969f1408337cee9d37d9cd4b6f7fff9e962  shozyo2-eiya.mp3
b4dc29d4740bd4913359d751ea5433d39cd5d602caa6596e981cab075d4f684c  shozyo2-ta.mp3
132851bff080f6e47140c5d37af46f462dfeea809d2131f418d118d13b291981  shozyo1-to.mp3
56666e8a5ade752f33492feae26556fcd5a60e673b52bd388487a14d301757d6  shozyo1-ya.mp3
93d587686fd6d5120aab0a91edfca6e9a2df0ba0e32d6a5049128b4ac44f3c09  shozyo1-atattekudasai.mp3
89a81a746d8a70fd60b4a035578c748bbc969bf58764f8e1a333845729d4e6a1  shozyo1-ei.mp3
2e88126f81902e034391ff7e0fd79e5be9e36759ccc7b3877a3ccd741293ae32  zyosei4-ta.mp3
```
