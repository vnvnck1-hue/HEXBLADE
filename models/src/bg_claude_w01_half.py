# W01 반쪽 모듈 (Claude 배경, 본편 적용) — 1 x 3 x 0.25 m. 본편 뒤 벽 직선 구간에서 2m 로 나누고 남는 한 칸 · 수납장 벽감 뒷벽.
# 빌드:  powershell -File tools\blender.ps1 model models\src\bg_claude_w01_half.py --engine=eevee
# 피벗·축은 W01 과 같다 (좌측 앞 바닥, 정면 +Y). 형상은 claude_background_shapes.w01(1.0).

import claude_background_bake as cbb
import claude_background_shapes as shapes

shapes.w01(1.0)


def after_join():
	hb.set_origin(hb.get("wall"), (0, 0, 0))
	cbb.bake_model("bg_claude_w01_half", hidden=("back",), lowres=("w01_core",))
