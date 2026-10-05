# 벽감 옆판 (Claude 배경, 본편 적용) — 0.12 x 3 x 0.55 m. 본편 뒤 3m 벽에 작업대·수납장이 들어가는 벽감의 양옆을 막는다.
# 빌드:  powershell -File tools\blender.ps1 model models\src\bg_claude_jamb.py --engine=eevee
# 피벗 = 앞 왼쪽 바닥: Blender x 0~0.12, y -0.55~0 (y=0 쪽이 벽 뒷면에 붙음), z 0~3.

import claude_background_bake as cbb
import claude_background_shapes as shapes

shapes.jamb()


def after_join():
	hb.set_origin(hb.get("wall"), (0, 0, 0))
	cbb.bake_model("bg_claude_jamb", hidden=("bottom",))
