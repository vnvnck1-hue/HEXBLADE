# 메카닉 배경 데칼

레퍼런스(사선 컷 타일, 벌집, 쉐브론, 경고 사선, 테크 라인, 각진 숫자)를 바탕으로 만든 스텐실 데칼입니다. 코드는 `scripts/mech_decals.gd`에 있습니다.

- 텍스처 파일은 없습니다. 도형을 다각형으로 정의하고 스캔라인(짝홀 규칙) 2배 초표본으로 런타임에 한 번 그린 뒤 공유합니다.
- 도형: `cut_tiles`, `tri_row`, `hex_cluster`, `chevron_col`, `hazard`, `tech_bar`, `arrow_bar`, `cross_bracket`, `bead_rail`, `hud_corner`, `ring_target`, `dots`, `slant_pair`, `bent_strip`, `chev_row`, `vent`, `num:<숫자>`.
- `ArenaMap.build()` 끝에서 `MechDecals.dress()`가 배치합니다.
  - 바닥: 방 넓이에 비례해 큰 표식과 가는 띠를 겹치지 않게 흩뿌립니다. 출입구·기둥·엄폐물 칸은 피하고, 숫자는 방 번호(방마다 하나)입니다.
  - 출입구: 방 안쪽을 가리키는 주황 쉐브론.
  - 벽 윗면: 곧은 벽 구간을 따라 띠를 두릅니다.
  - 벽 정면: 카메라를 향한 뒷벽(+Z 면)의 경고 사선·숫자·통풍판. 벽 프랍 칸은 제외합니다.
- `Decal.cull_mask = MechDecals.RECEIVER`(레이어 20)입니다. 이 레이어는 바닥·벽 메시에만 있어서 플레이어·적·탄에는 데칼이 찍히지 않습니다.
- 바탕 색은 `LIGHT`, `DARK`, `AMBER` 세 가지이고, 네온 점등이 눈에 띄도록 `albedo_mix`를 0.11~0.2로 아주 옅게 두었습니다.
- 네온 순차 점등: `ANIM` 표에 있는 반복 무늬(쉐브론, 경고 사선, 구슬 레일, 점, 삼각형 줄, 컷 타일, 벌집, 화살표 바)는 같은 크기의 발광 전용 데칼을 하나 더 겹칩니다. 부품을 하나씩 켜고 잔광(`trail`)을 남기는 프레임 텍스처를 미리 구워 두고, `MechDecalAnim`(`scripts/mech_decal_anim.gd`)이 `rate`에 맞춰 넘깁니다. 한 바퀴가 끝나면 `rest` 단계 동안 꺼집니다. 출입구 쉐브론은 항상 켜지고, 바닥은 `NEON_CHANCE`(60%), 벽 윗면은 75% 확률로 켜집니다. 데칼마다 시작 위상이 다릅니다.

캡처:

```powershell
& '..\3D 쿼터뷰 슈팅게임\.tools\godot\Godot_v4.6.3-stable_win64_console.exe' --path . --resolution 1600x1000 --script _capture/mech_decals_show.gd -- --scene=main
```

`--scene=run`(기본)은 섹터 런 시작 구역, `--scene=main`은 다중 방 맵입니다. 결과는 `_capture/decals_<scene>_{gameplay,overview,close}.png`에 저장되고, 네온 점등 12프레임은 `_capture/decals_seq/`에 저장됩니다.
