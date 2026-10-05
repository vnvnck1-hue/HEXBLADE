# W01 벽 패널 (Claude 배경 첫 제작) — 2 x 3 x 0.25 m. 기준: output/background-modular-kit-20261003/sheets/W01.png
# 빌드:  powershell -File tools\blender.ps1 model models\src\bg_claude_w01.py --engine=eevee
# 피벗 = 좌측 앞 바닥. Blender x 0~2, z 0~3, y -0.25~0 (정면 +Y = Godot -Z, 정면 면이 y=0 → Godot Z=0~0.25).
# 구성: 보라 프레임(모서리 판·세로 기둥·가로대·가운데 고정쇠) + 안쪽 회보라 패널(모서리 깎음) + 볼트/리벳.
# 형상은 tools/blender/claude_background_shapes.py (반쪽 모듈 bg_claude_w01_half 와 공용).
# 텍스처는 claude_background_bake 가 아틀라스에 굽는다 (뒷면은 안 보이므로 저해상도).

import claude_background_bake as cbb
import claude_background_shapes as shapes

shapes.w01(2.0)


def after_join():
	hb.set_origin(hb.get("wall"), (0, 0, 0))
	cbb.bake_model("bg_claude_w01", hidden=("back",), lowres=("w01_core",))
