# S01 환기 장치 (Claude, 1번 설비실 합성안) — 폭 1.50 x 높이 1.00 x 깊이 1.50 m. 기준: output/service-machinery-kit-20261004/S01_ventilation_unit.png
# 빌드:  powershell -File tools\blender.ps1 model models\src\bg_claude_service_s01_vent.py --engine=eevee
# 피벗 = 바닥 중심. 정면 +Y (Godot -Z). 높이 1.00 은 발밑부터 상단 격자 프레임 윗면까지 (프레임을 밖에 더하지 않음).
# 두툼한 파란 회색 하우징 + 짙은 받침 · 모서리 범퍼 · 낮은 발, 네 옆면의 얕은 점검 패널, 정면 아래 작은 상태등,
# 상단 수평 격자(정면·측면에선 프레임 가장자리만 보임). 오른쪽 펌프는 이 모델을 0.8배 균일 축소해 재사용한다.

import claude_background_bake as cbb
import claude_service as svc

M = svc.mats()
P = "vent"

# 발 · 받침
for sx in (-1, 1):
	for sy in (-1, 1):
		hb.box("foot_%d_%d" % (sx, sy), (0.26, 0.26, 0.06), loc=(sx * 0.52, sy * 0.52, 0.03), mat=M["dark"], bevel=0.015, part=P)
hb.box("base", (1.36, 1.36, 0.2), loc=(0, 0, 0.16), mat=M["navy"], bevel=0.025, part=P)
# 몸체
hb.box("body", (1.42, 1.42, 0.62), loc=(0, 0, 0.57), mat=M["steel"], bevel=0.07, seg=2, part=P)
# 모서리 범퍼 (아래 절반, 몸체 모서리를 감쌈)
for sx in (-1, 1):
	for sy in (-1, 1):
		hb.box("bumper_%d_%d" % (sx, sy), (0.2, 0.2, 0.44), loc=(sx * 0.65, sy * 0.65, 0.28), mat=M["dark"], bevel=0.03, part=P)
# 네 옆면 점검 패널 (얕게 도드라진 판)
for i, (nx, ny) in enumerate(((0, 1), (1, 0), (0, -1), (-1, 0))):
	size = (0.9, 0.024, 0.28) if nx == 0 else (0.024, 0.9, 0.28)
	hb.box("panel_%d" % i, size, loc=(nx * 0.716, ny * 0.716, 0.64), mat=M["steel"], bevel=0.01, seg=1, part=P)
# 정면 상태등
hb.box("lamp_frame", (0.2, 0.03, 0.09), loc=(0.42, 0.716, 0.38), mat=M["dark"], bevel=0.01, seg=1, part=P)
hb.box("lamp", (0.14, 0.03, 0.05), loc=(0.42, 0.728, 0.38), mat=M["lamp"], bevel=0.008, seg=1, part=P)
# 상단 격자: 프레임(가운데를 파냄) + 수평 날개 8장
frame = hb.box("grille_frame", (1.06, 1.06, 0.12), loc=(0, 0, 0.94), mat=M["steel"], bevel=0.025, part=P)
cut = hb.box("grille_cut", (0.84, 0.84, 0.1), loc=(0, 0, 1.0))
hb.boolean(frame, cut)
hb.box("grille_floor", (0.86, 0.86, 0.02), loc=(0, 0, 0.9), mat=M["hole"], part=P)
for k in range(8):
	y = -0.33 + k * (0.66 / 7)
	hb.box("slat_%d" % k, (0.82, 0.05, 0.035), loc=(0, y, 0.965), rot=(-25, 0, 0), mat=M["dark"], bevel=0.008, seg=1, part=P)
# 프레임 볼트 4개
for sx in (-1, 1):
	for sy in (-1, 1):
		hb.cyl("bolt_%d_%d" % (sx, sy), r=0.025, depth=0.012, loc=(sx * 0.47, sy * 0.47, 0.994), verts=6, mat=M["dark"], part=P,
			   smooth=False)


def after_join():
	svc.finish(P)
	cbb.bake_model("bg_claude_service_s01_vent", hidden=("bottom",), emit=(svc.LAMP,), res=2048)   # 4096 은 낭비 (게임 화면 약 75px/m)
