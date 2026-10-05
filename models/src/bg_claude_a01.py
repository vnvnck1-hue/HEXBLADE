# A01 작업대 (Claude 배경 첫 제작) — 2 x 1 x 0.75 m. 기준: output/background-modular-kit-20261003/sheets/A01.png
# 빌드:  powershell -File tools\blender.ps1 model models\src\bg_claude_a01.py --engine=eevee
# 피벗 = 바닥 중심. Blender x -1~1, y -0.375~0.375 (정면 +Y), z 0~1.
# 코랄 상판(모서리 보라 덮개) + 보라 서랍장 2개(서랍 2단·코랄 손잡이) + 가운데 무릎 공간(짙은 가림판) + 짧은 발.
# 하위 메시: top(상판) · drawers(서랍 앞판·손잡이) · body(나머지). 애니메이션 없음, 원점은 모두 바닥 중심.

import claude_background_bake as cbb

CORAL = cbb.paint_mat("a01_coral", "coral", hi="#F09A82", lo="#8C3F47", wear="#6E4382", wear_amt=0.45, grad_h=1.0, hgrad=0.08)
FRAME = cbb.paint_mat("a01_frame", "purple", hi="#8070B8", lo="#342A5C", wear="#B45E5A", wear_amt=0.5, grad_h=0.9)
DRAWER = cbb.paint_mat("a01_drawer", "purple", hi="#9283C6", lo="#3A2F62", wear="#B45E5A", wear_amt=0.35, grad_h=0.9, hgrad=0.08)
DARK = cbb.paint_mat("a01_dark", "dark", hi="#54477F", lo="#221B3C", grad_h=0.9)
HANDLE = cbb.paint_mat("a01_handle", "coral", hi="#F4A88E", lo="#8C3F47", grad_h=1.0, hgrad=0.0)

HW, HD = 1.0, 0.375

# --- 상판
hb.box("slab", (1.994, 0.744, 0.13), loc=(0, 0, 0.93), mat=CORAL, bevel=0.02, part="top")
for sx in (-1, 1):
	for sy in (-1, 1):
		hb.box("cap_%d_%d" % (sx, sy), (0.13, 0.13, 0.133), loc=(sx * (HW - 0.065), sy * (HD - 0.065), 1.0 - 0.0665),
			   mat=FRAME, bevel=0.015, part="top")

# --- 서랍장 몸통 2개 + 발
for sx in (-1, 1):
	cx = sx * 0.67
	hb.box("ped_%d" % sx, (0.6, 0.65, 0.805), loc=(cx, -0.005, 0.06 + 0.4025), mat=FRAME, bevel=0.02, part="body")
	for fx in (-0.22, 0.22):
		for fy in (-0.24, 0.24):
			hb.box("foot_%d_%d_%d" % (sx, fx * 100, fy * 100), (0.13, 0.12, 0.062), loc=(cx + fx, fy, 0.031),
				   mat=DARK, bevel=0.01, part="body")
	# 상판 아래 이음 띠
	hb.box("band_%d" % sx, (0.62, 0.66, 0.035), loc=(cx, -0.005, 0.85), mat=DARK, bevel=0.008, part="body")
	# --- 서랍 앞판 2단 + 손잡이
	for i, (z0, z1) in enumerate(((0.095, 0.455), (0.48, 0.835))):
		zc = (z0 + z1) / 2
		hb.box("drawer_%d_%d" % (sx, i), (0.52, 0.03, z1 - z0), loc=(cx, 0.33, zc), mat=DRAWER, bevel=0.018, part="drawers")
		hb.box("handle_%d_%d" % (sx, i), (0.25, 0.026, 0.055), loc=(cx, 0.358, zc + 0.04), mat=HANDLE, bevel=0.012, part="drawers")
		for hx in (-0.1, 0.1):
			hb.box("hpost_%d_%d_%d" % (sx, i, hx * 100), (0.035, 0.02, 0.035), loc=(cx + hx, 0.348, zc + 0.04), mat=DARK,
				   part="drawers")

# --- 무릎 공간: 뒤쪽 가림판 + 앞쪽 상판 아래 띠
hb.box("modesty", (0.76, 0.04, 0.5), loc=(0, -0.31, 0.6), mat=DARK, bevel=0.01, part="body")
hb.box("apron", (0.76, 0.05, 0.07), loc=(0, 0.29, 0.83), mat=DARK, bevel=0.012, part="body")


def after_join():
	body, top, drawers = hb.get("body"), hb.get("top"), hb.get("drawers")
	for o in (body, top, drawers):
		hb.set_origin(o, (0, 0, 0))
	hb.attach(top, body)
	hb.attach(drawers, body)
	cbb.bake_model("bg_claude_a01", hidden=("bottom",))
