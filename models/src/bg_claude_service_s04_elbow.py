# S04 90도 배관 (Claude, 1번 설비실 합성안) — 중심선 반경 0.75 / 몸통 외경 0.50 / 밴드 외경 0.60 m. 기준: S04_pipe_elbow.png
# 빌드:  powershell -File tools\blender.ps1 model models\src\bg_claude_service_s04_elbow.py --engine=eevee
# 바닥 수평면에서 휘는 꺾임. 피벗 = 두 배관 축이 만나는 모서리점 바로 아래 바닥 (축 높이 0.30).
# 끝단 A: Blender (-0.75, 0) 축 X → Godot (-0.75, 0.3, 0), -X 를 향함 (pt_end_a)
# 끝단 B: Blender (0, -0.75) 축 Y → Godot (0, 0.3, +0.75), +Z 를 향함 (pt_end_b)
# 굽힘 중심 Blender (-0.75, -0.75). 끝단 단면은 축에 수직이라 S03 끝단과 그대로 맞물린다. 양 끝에 회크림 밴드.

import math

import claude_background_bake as cbb
import claude_service as svc

M = svc.mats()
P = "elbow"
Y = svc.PIPE_Y
R = 0.75
C = (-R, -R)
BAND_DEG = math.degrees(svc.BAND_W / R)
LIP_DEG = math.degrees(0.03 / R)

# 몸통: 0도 = 끝단 B (0, -0.75), 90도 = 끝단 A (-0.75, 0). 양 끝 0.03 은 끝 테
svc.sweep_arc("body", C, R, svc.PIPE_R, LIP_DEG, 90 - LIP_DEG, Y, M["navy_r"], P, steps=16)
svc.sweep_arc("lip_b", C, R, svc.PIPE_R + 0.012, 0, LIP_DEG, Y, M["navy_r"], P, steps=1, cap0=True)
svc.sweep_arc("lip_a", C, R, svc.PIPE_R + 0.012, 90 - LIP_DEG, 90, Y, M["navy_r"], P, steps=1, cap1=True)
# 구멍 (끝단 바로 바깥의 짙은 원판)
hb.cyl("hole_a", r=svc.PIPE_R - 0.06, depth=0.004, loc=(-R - 0.001, 0, Y), rot=(0, 90, 0), verts=20, mat=M["hole"], part=P)
hb.cyl("hole_b", r=svc.PIPE_R - 0.06, depth=0.004, loc=(0, -R - 0.001, Y), rot=(90, 0, 0), verts=20, mat=M["hole"], part=P)
# 양 끝 밴드 (끝단에서 0.06 안쪽부터 폭 0.12)
off = math.degrees(0.06 / R)
svc.sweep_arc("band_b", C, R, svc.BAND_R, off, off + BAND_DEG, Y, M["cream_r"], P, steps=2, cap0=True, cap1=True)
svc.sweep_arc("band_a", C, R, svc.BAND_R, 90 - off - BAND_DEG, 90 - off, Y, M["cream_r"], P, steps=2, cap0=True, cap1=True)
# 가운데 이음 줄
svc.sweep_arc("seam", C, R, svc.PIPE_R + 0.004, 44.5, 45.5, Y, M["dark"], P, steps=1, cap0=True, cap1=True)


def after_join():
	svc.finish(P)
	hb.empty("pt_end_a", loc=(-R, 0, Y))
	hb.empty("pt_end_b", loc=(0, -R, Y))
	cbb.bake_model("bg_claude_service_s04_elbow", hidden=("bottom",))
