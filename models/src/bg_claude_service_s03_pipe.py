# S03 직선 배관 (Claude, 1번 설비실 합성안) — 길이 2.00 / 몸통 외경 0.50 / 밴드 외경 0.60 m. 기준: S03_pipe_straight.png
# 빌드:  powershell -File tools\blender.ps1 model models\src\bg_claude_service_s03_pipe.py --engine=eevee
# 긴 축 = X (Godot X). 피벗 = 배관 중앙 바로 아래 바닥 (축 중심 높이 0.30, 밴드가 바닥에 닿음).
# 끝단 x = ±1.00, 축에 수직인 평면 (pt_end_a · pt_end_b). 남색 몸통 + 회크림 연결밴드 2개 (폭 0.12, 끝에서 0.18 안쪽).
# 벽면 얇은 라인은 이 모델을 0.25배 균일 축소해 재사용한다 (굵은 배관과 접속하지 않음).

import claude_background_bake as cbb
import claude_service as svc

M = svc.mats()
P = "pipe"
Y = svc.PIPE_Y

hb.cyl("body", r=svc.PIPE_R, depth=1.94, loc=(0, 0, Y), rot=(0, 90, 0), verts=24, mat=M["navy_r"], part=P)
for s in (-1, 1):
	svc.pipe_end("end_%d" % s, s * 1.0, "X", s, M, P)
	hb.cyl("band_%d" % s, r=svc.BAND_R, depth=svc.BAND_W, loc=(s * 0.76, 0, Y), rot=(0, 90, 0), verts=24, mat=M["cream_r"],
		   bevel=0.015, part=P)
	# 이음 줄 (얇은 짙은 띠)
	hb.cyl("seam_%d" % s, r=svc.PIPE_R + 0.004, depth=0.012, loc=(s * 0.3, 0, Y), rot=(0, 90, 0), verts=24, mat=M["dark"], part=P)


def after_join():
	svc.finish(P)
	hb.empty("pt_end_a", loc=(-1.0, 0, Y))
	hb.empty("pt_end_b", loc=(1.0, 0, Y))
	cbb.bake_model("bg_claude_service_s03_pipe", hidden=("bottom",))
