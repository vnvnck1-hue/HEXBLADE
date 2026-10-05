# S02 냉각 탱크 (Claude, 1번 설비실 합성안) — 본체 지름 1.20 x 총높이 1.65 m (낮은 십자 밸브 포함). 기준: S02_coolant_tank.png
# 빌드:  powershell -File tools\blender.ps1 model models\src\bg_claude_service_s02_tank.py --engine=eevee
# 피벗 = 바닥 중심(원통 축). 정면 +Y (Godot -Z). 낮고 넓은 원통: 남색 받침 · 청록 몸통 · 남색 상단 캡 · 십자 밸브,
# 정면 세로 상태등, 정면 하부 배관 포트. 포트는 배관 규격(중심 높이 0.30 · 몸통 외경 0.50)과 같은 축이며
# 끝면이 원통 중심에서 0.80 앞 (pt_port). 지름 1.20 은 원통 본체(받침·캡) 기준, 포트 돌출은 따로.

import math

import claude_background_bake as cbb
import claude_service as svc

M = svc.mats()
P = "tank"
Y = svc.PIPE_Y

hb.cyl("base", r=0.6, depth=0.24, loc=(0, 0, 0.12), verts=32, mat=M["navy_r"], bevel=0.03, part=P)
hb.cyl("base_ring", r=0.57, depth=0.05, loc=(0, 0, 0.265), verts=32, mat=M["dark"], part=P)
hb.cyl("body", r=0.55, depth=0.8, loc=(0, 0, 0.69), verts=32, mat=M["teal_r"], part=P)
for z in (0.33, 1.06):
	hb.cyl("ring_%d" % (z * 100), r=0.565, depth=0.05, loc=(0, 0, z), verts=32, mat=M["navy_r"], part=P)
hb.cyl("cap", r=0.6, depth=0.27, loc=(0, 0, 1.225), verts=32, mat=M["navy_r"], bevel=0.02, part=P)
hb.cyl("cap_top", r=0.6, r2=0.47, depth=0.08, loc=(0, 0, 1.4), verts=32, mat=M["navy_r"], part=P)
hb.cyl("lid", r=0.3, r2=0.27, depth=0.05, loc=(0, 0, 1.465), verts=24, mat=M["navy_r"], part=P)
# 십자 밸브 (낮게)
hb.cyl("valve_stem", r=0.07, depth=0.08, loc=(0, 0, 1.53), verts=12, mat=M["dark"], part=P)
hb.box("valve_x", (0.36, 0.08, 0.07), loc=(0, 0, 1.6), mat=M["navy"], bevel=0.02, part=P)
hb.box("valve_y", (0.08, 0.36, 0.07), loc=(0, 0, 1.6), mat=M["navy"], bevel=0.02, part=P)
hb.cyl("valve_hub", r=0.075, depth=0.1, loc=(0, 0, 1.6), verts=12, mat=M["navy_r"], part=P)
# 몸통 볼트 받침 (네 방향)
for k, a in enumerate((45, 135, 225, 315)):
	t = math.radians(a)
	hb.box("lug_%d" % k, (0.06, 0.06, 0.12), loc=(math.cos(t) * 0.555, math.sin(t) * 0.555, 0.42), rot=(0, 0, a), mat=M["dark"],
		   bevel=0.01, seg=1, part=P)
# 정면 세로 상태등
hb.box("lamp_frame", (0.12, 0.06, 0.38), loc=(0, 0.535, 0.78), mat=M["dark"], bevel=0.015, seg=1, part=P)
hb.box("lamp", (0.06, 0.04, 0.29), loc=(0, 0.56, 0.78), mat=M["lamp"], bevel=0.012, seg=1, part=P)
# 정면 하부 배관 포트 (축 Y, 끝면 y=0.80)
hb.cyl("port", r=0.21, depth=0.36, loc=(0, 0.6, Y), rot=(90, 0, 0), verts=24, mat=M["navy_r"], part=P)
hb.cyl("port_flange", r=0.27, depth=0.07, loc=(0, 0.765, Y), rot=(90, 0, 0), verts=24, mat=M["navy_r"], bevel=0.012, part=P)
hb.cyl("port_hole", r=0.15, depth=0.004, loc=(0, 0.801, Y), rot=(90, 0, 0), verts=20, mat=M["hole"], part=P)
for k in range(6):
	t = math.radians(30 + k * 60)
	hb.cyl("flange_bolt_%d" % k, r=0.022, depth=0.02, loc=(math.cos(t) * 0.22, 0.802, Y + math.sin(t) * 0.22), rot=(90, 0, 0),
		   verts=6, mat=M["dark"], part=P, smooth=False)


def after_join():
	svc.finish(P)
	hb.empty("pt_port", loc=(0, 0.8, Y))
	cbb.bake_model("bg_claude_service_s02_tank", hidden=("bottom",), emit=(svc.LAMP,))
