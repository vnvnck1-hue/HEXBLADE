# A02 수납장 (Claude 배경 첫 제작) — 1 x 2 x 0.5 m. 기준: output/background-modular-kit-20261003/sheets/A02_v2.png
# 빌드:  powershell -File tools\blender.ps1 model models\src\bg_claude_a02.py --engine=eevee
# 피벗 = 바닥 중심. Blender x -0.5~0.5, y -0.25~0.25 (정면 +Y), z 0~2.
# 보라 몸통 + 높이가 다른 앞문 2개(밝은 보라, 모서리 깎음, 왼쪽 경첩) + 코랄 손잡이(정면에만) + 낮은 발 4개.
# 하위 메시: body · door_upper · door_lower. 문의 원점은 경첩 축 (개폐 애니메이션은 만들지 않음).

import claude_background_bake as cbb

FRAME = cbb.paint_mat("a02_frame", "purple", hi="#8474BC", lo="#342A5C", wear="#B45E5A", wear_amt=0.5, grad_h=2.0)
DOOR = cbb.paint_mat("a02_door", "door", hi="#BBAEDA", lo="#4E4180", wear="#C4B8E0", wear_amt=0.3, grad_h=2.0, hgrad=0.1)
HANDLE = cbb.paint_mat("a02_handle", "coral", hi="#F4A88E", lo="#8C3F47", grad_h=2.0, hgrad=0.0)
DARK = cbb.paint_mat("a02_dark", "dark", hi="#5A4C88", lo="#221B3C", grad_h=2.0)

FRONT = 0.20         # 몸통 앞면
DOOR_F = 0.225       # 문 앞면
HINGE_X = -0.395

hb.box("carcass", (1.0, 0.25 + FRONT, 1.88), loc=(0, (FRONT - 0.25) / 2, 0.12 + 0.94), mat=FRAME, bevel=0.035, part="body")
for sx in (-1, 1):
	for sy in (-1, 1):
		hb.box("foot_%d_%d" % (sx, sy), (0.2, 0.13, 0.125), loc=(sx * 0.36, sy * 0.15, 0.0625), mat=FRAME, bevel=0.02, part="body")
# 몸통 정면 모서리 나사 4개
for x in (-0.44, 0.44):
	for z in (0.19, 1.93):
		hb.sphere("screw_%d_%d" % (x * 100, z * 100), r=0.022, loc=(x, FRONT, z), scale=(1, 0.45, 1), seg=10, rings=5,
				  mat=DARK, part="body")

DOORS = (("door_lower", 0.24, 0.88, 0.56, 0.17), ("door_upper", 0.95, 1.86, 1.41, 0.21))
for name, z0, z1, hz, hl in DOORS:
	x0, x1, c = -0.36, 0.33, 0.045
	pts = [(x0 + c, z0), (x1 - c, z0), (x1, z0 + c), (x1, z1 - c), (x1 - c, z1), (x0 + c, z1), (x0, z1 - c), (x0, z0 + c)]
	hb.prism(name + "_leaf", pts, depth=DOOR_F - FRONT + 0.006, loc=(0, (DOOR_F + FRONT - 0.006) / 2, 0), axis="Y",
			 mat=DOOR, bevel=0.016, part=name)
	# 손잡이 (코랄, 정면에만)
	hb.box(name + "_handle", (0.055, 0.025, hl), loc=(0.245, DOOR_F + 0.0125, hz), mat=HANDLE, bevel=0.012, part=name)
	# 리벳
	for x in (x0 + 0.07, x1 - 0.07):
		for z in (z0 + 0.07, z1 - 0.07):
			hb.sphere(name + "_rivet_%d_%d" % (x * 100, z * 100), r=0.022, loc=(x, DOOR_F, z), scale=(1, 0.4, 1), seg=10,
					  rings=5, mat=FRAME, part=name)
	# 경첩 2개
	for z in (z0 + 0.12, z1 - 0.12):
		hb.cyl(name + "_hinge_%d" % (z * 100), r=0.02, depth=0.1, loc=(HINGE_X, FRONT + 0.012, z), verts=10, mat=DARK, part=name)


def after_join():
	body = hb.get("body")
	hb.set_origin(body, (0, 0, 0))
	for name, z0, z1, _hz, _hl in DOORS:
		d = hb.get(name)
		hb.set_origin(d, (HINGE_X, FRONT + 0.012, (z0 + z1) / 2))
		hb.attach(d, body)
	cbb.bake_model("bg_claude_a02", hidden=("bottom",))
