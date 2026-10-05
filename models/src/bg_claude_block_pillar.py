# 낮은 W01 블록 'pillar' (Claude 배경, 본편 적용) — 본편 아레나 1m 칸 하나: x·z ±0.5, 높이 -0.4 ~ 1.5 m (바닥면 0).
# 빌드:  powershell -File tools\blender.ps1 model models\src\bg_claude_block_pillar.py --engine=eevee
# 본편 ArenaMap 의 벽(0.8) · 낮은 엄폐물(0.7) · 기둥(1.5) 칸을 이 블록으로 채운다 (판정 상자는 그대로, 보이는 것만).
# 네 옆면: 보라 프레임에 3cm 파낸 자리 + 모서리 깎은 회보라 패널 · 볼트 4개, 윗덮개 회보라. 형상은 claude_background_shapes.block.

import claude_background_bake as cbb
import claude_background_shapes as shapes

shapes.block(1.5, -0.4, "blk_pillar")


def after_join():
	hb.set_origin(hb.get("wall"), (0, 0, 0))
	cbb.bake_model("bg_claude_block_pillar", hidden=("bottom",), lowres=("blk_pillar_core",))
