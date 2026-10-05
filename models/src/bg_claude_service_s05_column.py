# S05 설비 기둥 (Claude, 1번 설비실 합성안) — 폭 0.50 x 높이 1.60 x 깊이 0.50 m. 기준: S05_service_column.png
# 빌드:  powershell -File tools\blender.ps1 model models\src\bg_claude_service_s05_column.py --engine=eevee
# 피벗 = 바닥 중심. 정면 +Y (Godot -Z). 사각 받침 · 이음 띠 · 가는 몸통 · 베벨 캡, 정면의 상태등 창과 긴 점검 패널.
# 상태등은 발광 마스크로 구워 게임에서 노랑/민트 재질 변형(제어함 느낌)을 고른다. 원화의 사선 제어 콘솔을 대신한다.

import claude_background_bake as cbb
import claude_service as svc

M = svc.mats()
P = "column"

hb.box("base", (0.5, 0.5, 0.28), loc=(0, 0, 0.14), mat=M["slate"], bevel=0.035, part=P)
for sx in (-1, 1):
	for i, (nx, ny) in enumerate(((0, 1), (1, 0), (0, -1), (-1, 0))):
		o = sx * 0.17
		loc = (o, ny * 0.248, 0.13) if nx == 0 else (nx * 0.248, o, 0.13)
		size = (0.07, 0.006, 0.13) if nx == 0 else (0.006, 0.07, 0.13)
		hb.box("slot_%d_%d" % (sx, i), size, loc=loc, mat=M["hole"], part=P)
hb.box("collar", (0.42, 0.42, 0.05), loc=(0, 0, 0.305), mat=M["dark"], bevel=0.01, seg=1, part=P)
hb.box("shaft", (0.38, 0.38, 1.06), loc=(0, 0, 0.86), mat=M["slate"], bevel=0.02, part=P)
# 옆면 세로 패널 (좌우·뒤)
for i, (nx, ny) in enumerate(((1, 0), (-1, 0), (0, -1))):
	size = (0.02, 0.26, 0.9) if nx else (0.26, 0.02, 0.9)
	hb.box("side_panel_%d" % i, size, loc=(nx * 0.19, ny * 0.19, 0.83), mat=M["slate"], bevel=0.008, seg=1, part=P)
# 정면: 상태등 창 + 긴 점검 패널
hb.box("lamp_box", (0.22, 0.03, 0.18), loc=(0, 0.195, 1.2), mat=M["dark"], bevel=0.012, seg=1, part=P)
hb.box("lamp", (0.13, 0.03, 0.075), loc=(0, 0.207, 1.2), mat=M["lamp"], bevel=0.01, seg=1, part=P)
hb.box("front_panel", (0.22, 0.025, 0.62), loc=(0, 0.195, 0.72), mat=M["slate"], bevel=0.01, seg=1, part=P)
for sx in (-1, 1):
	for z in (0.44, 1.0):
		hb.box("rivet_%d_%d" % (sx, z * 10), (0.025, 0.012, 0.025), loc=(sx * 0.085, 0.21, z), mat=M["dark"], part=P)
hb.box("cap", (0.5, 0.5, 0.23), loc=(0, 0, 1.485), mat=M["slate"], bevel=0.06, seg=2, part=P)


def after_join():
	svc.finish(P)
	cbb.bake_model("bg_claude_service_s05_column", hidden=("bottom",), emit=(svc.LAMP,))
