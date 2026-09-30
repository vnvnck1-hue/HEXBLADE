# 산업 시설 벽면 프랍 3종

레퍼런스의 회백색 분할 장갑판, 민트색 탱크, 검은 고정 밴드와 잠금쇠를 바탕으로 만든 Godot 3D 메시입니다.

- `scenes/props/coolant_manifold.tscn`: 상부 냉각 매니폴드, 이중 탱크, 상태 표시기.
- `scenes/props/power_distribution.tscn`: 배전함, 케이블 접속부, 통풍구, 경고 표식.
- `scenes/props/service_locker.tscn`: 이중 정비 도어, 경첩, 손잡이, 하부 배관.

각 씬은 독립 인스턴스로 사용할 수 있습니다. 정면은 +Z, 바닥 피벗은 Y=0, 크기는 약 3 × 3.2 × 0.95m입니다. 원본 생성 코드는 `scripts/wall_props.gd`에 있습니다. 머티리얼별로 메시를 결합하고 같은 종류의 배치끼리는 메시 리소스를 공유합니다.

`ArenaMap.build()`에서 섹터 런과 방 탐색 아레나의 후면 직선 벽 구간에 자동 배치합니다. 방당 최대 6개이며, 5칸의 직선 구간과 바닥/벽 상태를 검사하고 출입구를 피합니다. 기존 벽 충돌과 게임 격자는 유지하고 해당 구간의 낮은 벽 외형을 교체합니다. 충분한 직선 벽이 없는 방에는 배치되지 않습니다. 보스 전용 스테이지에는 적용하지 않습니다.

검증: `_capture/wall_props_check.gd`는 8종 방 형태 × 3개 시드에서 격자 불변, 벽 영역 내 메시 경계, 정면 바닥을 검사합니다.

캡처 및 씬 재생성:

```powershell
& '..\3D 쿼터뷰 슈팅게임\.tools\godot\Godot_v4.6.3-stable_win64_console.exe' --path . --resolution 1600x1000 --script _capture/wall_props_show.gd -- --seed=7
```

실제 `run.tscn`의 생성된 방과 조명을 사용합니다. detail/ingame/개별 프랍 캡처에서는 확인을 위해 HUD와 포탈 표시만 숨기며, gameplay 캡처는 포탈과 HUD를 복구하고 TACTICAL 카메라 프리셋을 사용합니다. PNG는 `_capture/`에 저장됩니다. 이 스크립트를 다시 실행하면 위의 3개 프랍 씬도 현재 생성 코드로 갱신합니다.
