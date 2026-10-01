# 파이프라인 확인용 예제: 고정 포탑 (높이 약 1.05m). 정면 = +Y.
# 빌드:  tools\blender.ps1 model models\src\sample_turret.py
# 파츠: base(고정) · turret(좌우 회전, 원점 = 회전축) · barrel(상하, 원점 = 포이), 총구 pt_muzzle_l/r

ARMOR = hb.mat("armor", "#3d6fb3", metal=0.3, rough=0.45)
DARK = hb.mat("dark", "#22262d", metal=0.6, rough=0.4)
GLOW = hb.mat("glow", "#38f2e0", emit="#38f2e0", emit_power=4)

# --- base: 육각 받침 + 다리 4
hb.cyl("base_plate", r=0.75, depth=0.18, loc=(0, 0, 0.09), verts=6, mat=DARK, bevel=0.03, part="base", smooth=False)
hb.cyl("base_ring", r=0.5, depth=0.3, loc=(0, 0, 0.33), mat=ARMOR, bevel=0.02, part="base")
for i in range(4):
	a = math.radians(45 + 90 * i)
	hb.box("foot%d" % i, (0.22, 0.5, 0.12), loc=(math.cos(a) * 0.72, math.sin(a) * 0.72, 0.06),
		   rot=(0, 0, math.degrees(a) + 90), mat=DARK, bevel=0.02, part="base")

# --- turret: 측면 실루엣을 잘라 만든 몸통 (u = 앞, v = 위)
turret = hb.prism("turret_body", [(-0.55, 0.0), (0.45, 0.0), (0.6, 0.25), (0.3, 0.55), (-0.45, 0.55), (-0.6, 0.3)],
				  depth=0.9, loc=(0, 0, 0.5), mat=ARMOR, bevel=0.04, part="turret")
hb.box("visor", (0.6, 0.06, 0.12), loc=(0, 0.42, 0.88), rot=(-40, 0, 0), mat=GLOW, part="turret")
side = hb.box("side_pod_l", (0.18, 0.6, 0.35), loc=(0.53, -0.05, 0.75), mat=DARK, bevel=0.03, part="turret")
hb.mirror_copy(side)
hb.tube("cable", [(0.4, -0.5, 0.7), (0.3, -0.7, 0.5), (0.0, -0.6, 0.35)], r=0.035, mat=DARK, part="turret")

# --- barrel: 쌍열 포신, 원점을 포이(피벗)에 둔다
for x in (-0.14, 0.14):
	hb.cyl("barrel%+.0f" % (x * 10), r=0.07, depth=0.9, loc=(x, 0.85, 0.8), rot=(90, 0, 0), mat=DARK, part="barrel")
	hb.cyl("brake%+.0f" % (x * 10), r=0.1, depth=0.14, loc=(x, 1.28, 0.8), rot=(90, 0, 0), mat=ARMOR, verts=8,
		   bevel=0.01, part="barrel", smooth=False)
hb.box("mantlet", (0.5, 0.2, 0.3), loc=(0, 0.45, 0.8), mat=ARMOR, bevel=0.04, part="barrel")


def after_join():
	base, turret, barrel = hb.get("base"), hb.get("turret"), hb.get("barrel")
	hb.set_origin(base, (0, 0, 0))
	hb.set_origin(turret, (0, 0, 0.5))      # 좌우 회전축
	hb.set_origin(barrel, (0, 0.45, 0.8))   # 포이
	hb.attach(turret, base)
	hb.attach(barrel, turret)
	hb.empty("pt_muzzle_l", (-0.14, 1.36, 0.8), parent=barrel)
	hb.empty("pt_muzzle_r", (0.14, 1.36, 0.8), parent=barrel)
