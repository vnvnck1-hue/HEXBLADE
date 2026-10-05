"""claude_background_shapes — 배경 첫 제작(Claude) 벽 계열 모델의 공용 형상. models/src/bg_claude_*.py 가 부른다.

  w01(W)           W01 벽 패널 (높이 3m · 두께 0.25m). W = 2 (기본 모듈) 또는 1 (본편 직선 구간의 남는 한 칸용 반쪽 모듈)
  jamb()           3m 벽의 벽감 옆판 (0.12 x 3 x 0.55) — 작업대·수납장이 들어가는 벽감의 양옆을 막는다
  block(top, bot)  본편 아레나 1m 칸 하나를 채우는 '낮은 W01' 블록 (x·z ±0.5, 높이 bot~top, 바닥면 0)
                   네 옆면에 모서리 깎은 회보라 패널이 들어가 있고 볼트, 회보라 윗덮개, 실제 베벨

좌표는 Blender (정면 +Y = Godot -Z, z 위). 모든 도형은 part="wall" 로 메시 하나가 된다.
"""

import hb
import claude_background_bake as cbb


def _mats(prefix, grad_h):
	frame = cbb.paint_mat(prefix + "_frame", "purple", hi="#8070B8", lo="#362B5E", wear="#B45E5A", wear_amt=0.55, grad_h=grad_h)
	bolt = cbb.paint_mat(prefix + "_bolt", "purple", hi="#9A8BCB", lo="#30264F", grad_h=grad_h)
	panel = cbb.paint_mat(prefix + "_panel", "lilac", hi="#D2C9E4", lo="#6C6090", wear="#8A7AAE", wear_amt=0.35, grad_h=grad_h, hgrad=0.12)
	core = cbb.paint_mat(prefix + "_core", "dark", hi="#54477F", lo="#241D40", grad_h=grad_h)
	return frame, bolt, panel, core


# ---------------------------------------------------------------- W01 (3m)

def w01(W=2.0):
	FRAME, BOLT, PANEL, CORE = _mats("w01", 1.3)
	H, D = 3.0, 0.25
	FRONT_MEMBER = -0.04      # 기둥·가로대 앞면
	FRONT_BLOCK = -0.02       # 모서리 판·고정쇠 앞면
	G = 0.0075                # 부재 사이 틈의 절반
	CW = 0.46 if W >= 2.0 else 0.32    # 모서리 판 크기 (반쪽 모듈은 작게)

	def member(name, x0, x1, z0, z1, front, mat=FRAME, bevel=0.03):
		"""정면 프레임 부재: 뒤(y=-D)부터 front 까지."""
		return hb.box(name, (x1 - x0, front + D, z1 - z0), loc=((x0 + x1) / 2, (front - D) / 2, (z0 + z1) / 2),
					  mat=mat, bevel=bevel, part="wall")

	# 몸체 판 (틈 사이로 보이는 짙은 속판). 위·끝면은 부재가 덮도록 2cm 안쪽 → 같은 평면 겹침 없음
	hb.box("core", (W - 0.04, 0.14, H - 0.04), loc=(W / 2, -0.17, H / 2), mat=CORE, bevel=0.01, part="wall")

	# 안쪽 패널: 모서리를 깎은 팔각 판, 프레임보다 들어가 있다
	P0, P1, PZ0, PZ1 = 0.22, W - 0.22, 0.22, H - 0.22
	C = 0.30 if W >= 2.0 else 0.16
	outline = [(P0 + C, PZ0), (P1 - C, PZ0), (P1, PZ0 + C), (P1, PZ1 - C), (P1 - C, PZ1), (P0 + C, PZ1), (P0, PZ1 - C), (P0, PZ0 + C)]
	hb.prism("panel", outline, depth=0.045, loc=(0, -0.0875, 0), axis="Y", mat=PANEL, bevel=0.022, part="wall")

	# 가로대 (위/아래)
	member("rail_bottom", CW + G, W - CW - G, 0.0, 0.22, FRONT_MEMBER)
	member("rail_top", CW + G, W - CW - G, H - 0.22, H, FRONT_MEMBER)
	# 세로 기둥 (가운데 고정쇠로 위/아래 나뉨)
	MID0, MID1 = H / 2 - 0.2, H / 2 + 0.2
	for side, (x0, x1) in (("l", (0.0, 0.22)), ("r", (W - 0.22, W))):
		member("stile_%s_lo" % side, x0, x1, CW + G, MID0 - G, FRONT_MEMBER)
		member("stile_%s_hi" % side, x0, x1, MID1 + G, H - CW - G, FRONT_MEMBER)
		# 가운데 고정쇠: 기둥보다 넓고 앞으로 나온 블록
		cx0, cx1 = (0.0, 0.28) if side == "l" else (W - 0.28, W)
		member("clamp_%s" % side, cx0, cx1, MID0, MID1, FRONT_BLOCK)
		bx = 0.14 if side == "l" else W - 0.14
		hb.cyl("clamp_bolt_%s" % side, r=0.05, depth=0.02, loc=(bx, -0.01, H / 2), rot=(90, 22.5, 0), verts=8, mat=BOLT,
			   bevel=0.006, part="wall", smooth=False)

	# 모서리 판: 안쪽 변이 대각선인 오각형 (모서리마다 뒤집어 놓는다)
	k = CW / 0.46
	corner = [(0.0, 0.0), (CW, 0.0), (CW, 0.22), (0.22 * k if k < 1 else 0.22, CW), (0.0, CW)]
	for name, fx, fz in (("bl", False, False), ("br", True, False), ("tl", False, True), ("tr", True, True)):
		pts = [((W - u) if fx else u, (H - v) if fz else v) for u, v in corner]
		if fx != fz:
			pts = pts[::-1]
		hb.prism("corner_%s" % name, pts, depth=D + FRONT_BLOCK, loc=(0, (FRONT_BLOCK - D) / 2, 0), axis="Y", mat=FRAME,
				 bevel=0.03, part="wall")
		bx = W - 0.13 * k if fx else 0.13 * k
		bz = H - 0.13 * k if fz else 0.13 * k
		hb.cyl("corner_bolt_%s" % name, r=0.055, depth=0.02, loc=(bx, -0.01, bz), rot=(90, 22.5, 0), verts=8, mat=BOLT,
			   bevel=0.006, part="wall", smooth=False)

	# 패널 리벳 4개 (깎인 모서리 안쪽)
	rx = 0.36 if W >= 2.0 else 0.3
	for x in (rx, W - rx):
		for z in (0.56, H - 0.56):
			hb.sphere("rivet_%d_%d" % (x * 10, z * 10), r=0.032, loc=(x, -0.065, z), scale=(1, 0.45, 1), seg=12, rings=6,
					  mat=BOLT, part="wall")


# ---------------------------------------------------------------- 벽감 옆판

def jamb():
	"""x 0~0.12, y -0.55~0 (정면 +Y 쪽 끝이 3m 벽 뒷면에 붙는다), z 0~3. 양옆 모두 보일 수 있어 좌우 대칭."""
	FRAME, BOLT, PANEL, CORE = _mats("jamb", 1.3)
	T, L, H = 0.12, 0.55, 3.0
	hb.box("jamb", (T, L, H - 0.2), loc=(T / 2, -L / 2, (H - 0.2) / 2 + 0.1), mat=FRAME, bevel=0.025, part="wall")
	for z, h in ((0.05, 0.1), (H - 0.05, 0.1)):
		hb.box("jamb_cap_%d" % (z * 10), (T, L, h), loc=(T / 2, -L / 2, z), mat=CORE, bevel=0.02, part="wall")
	for z in (0.6, H / 2, H - 0.6):
		for sx in (-1, 1):
			hb.sphere("jamb_bolt_%d_%d" % (z * 10, sx), r=0.026, loc=(T / 2 + sx * T / 2, -L / 2, z), scale=(0.45, 1, 1),
					  seg=10, rings=5, mat=BOLT, part="wall")


# ---------------------------------------------------------------- 낮은 W01 블록

def block(top, bottom, prefix):
	"""1m 칸 블록: x, y ±0.5, z bottom~top (바닥면 0). 몸체(보라) 네 옆면에 들어간 회보라 패널, 윗덮개(회보라), 볼트.
	옆 칸 블록과 맞닿는 면은 서로 가려진다 (블록끼리 같은 평면이 겹치지 않도록 모든 부품이 ±0.5 안에 있다)."""
	FRAME, BOLT, PANEL, CORE = _mats(prefix, top)
	CAP_MAT = cbb.paint_mat(prefix + "_cap", "door", hi="#B8AAD8", lo="#4E4180", wear="#B45E5A", wear_amt=0.35, grad_h=top, hgrad=0.0)
	cap = 0.09
	body = hb.box("body", (1.0, 1.0, top - cap), loc=(0, 0, (top - cap) / 2), mat=FRAME)
	# 바닥 아래(지형 단차를 덮는 부분)는 짙은 단색 상자 — 거의 안 보여 UV 를 작게 (bake lowres)
	hb.box("below", (0.998, 0.998, -bottom), loc=(0, 0, bottom / 2), mat=CORE, part="wall")
	hb.box("cap", (1.0, 1.0, cap), loc=(0, 0, top - cap / 2), mat=CAP_MAT, bevel=0.035, part="wall")
	# 패널: 바닥 위 0.16m ~ 윗덮개 아래 0.13m, 가로 0.13~0.87, 모서리 깎음. 몸체에서 3cm 파낸 자리에 2cm 판
	z0, z1 = 0.16, top - cap - 0.13
	x0, x1, c = -0.37, 0.37, 0.07
	outline = [(x0 + c, z0), (x1 - c, z0), (x1, z0 + c), (x1, z1 - c), (x1 - c, z1), (x0 + c, z1), (x0, z1 - c), (x0, z0 + c)]
	for i, rz in enumerate((0, 90, 180, 270)):
		cut = hb.prism("cut%d" % i, outline, depth=0.08, loc=_rot((0, 0.5, 0), rz), axis="Y")
		cut.rotation_euler = (0, 0, rz * 3.14159265 / 180)
		hb.boolean(body, cut)
		plate = hb.prism("plate%d" % i, outline, depth=0.03, loc=_rot((0, 0.5 - 0.035, 0), rz), axis="Y", mat=PANEL, bevel=0.012, seg=1, part="wall")
		plate.rotation_euler = (0, 0, rz * 3.14159265 / 180)
		# 볼트: 패널 바깥 프레임 네 귀퉁이
		for bx in (-0.43, 0.43):
			for bz in (0.09, top - cap - 0.06):
				b = hb.cyl("bolt%d_%d_%d" % (i, bx * 100, bz * 100), r=0.024, depth=0.016, verts=6, mat=BOLT, part="wall",
						   smooth=False, loc=_rot((bx, 0.496, bz), rz), rot=(90, 0, rz))
	body["hb_part"] = "wall"
	hb.add_bevel(body, 0.02, seg=1)


def _rot(p, deg):
	import math
	a = math.radians(deg)
	x, y, z = p
	return (x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a), z)
