# 벌레형 괴생명체 ④ 애벌레 (GRUB). 채택 3면도 output/cream-grub-turnaround-20261004/cream_grub_turnaround.png 기반.
# 크림색 낮은 돔 몸통 하나 · 베이지 가로 띠 2개 · 앞 아래쪽 회색 머리 캡슐 · 짙은 갈색 더듬이 한 쌍. 눈·발 없음.
# 빌드:  tools\blender.ps1 model models\src\bug_grub.py
#
# 몸통은 통짜 메시 하나(body)다. Godot 에서 GrubRig 가 몸 길이 방향으로 뼈 9개를 박아 스키닝하고,
# 뼈마다 앞뒤 위치·높이·굵기를 따로 움직여 진짜 애벌레처럼 꼬리부터 머리로 번지는 수축·이완(연동 운동)을 만든다.
# 그래서 몸통은 길이 방향으로 고른 고리(ring) 단면들로 만든다 (띠 경계마다 고리를 두어 색 경계가 반듯하다).
#
# 파츠 계층 (회전 0, 원점 = 관절):
#   body (원점 = 바닥 가운데)                     — 스키닝용 통짜 몸통, 재질 2개(크림 · 띠)
#   head (원점 = 몸 속 목 자리)                   — 회색 머리 캡슐 + 짙은 얼굴판. 리그가 맨 앞 뼈를 따라 움직인다
#     ├ feeler_l_1 > feeler_l_2 > feeler_l_3      — 더듬이 3마디 (원점 = 각 마디 뿌리) · _r 같음
#   부착점: pt_eye_l/r (얼굴판 — 공격 예고 발광) · pt_mouth · pt_tail (꼬리 끝, 체액 흔적) · pt_feeler_tip_l/r

from mathutils import Matrix

CREAM = hb.mat("grub_cream", "#f2e3cd", metal=0.0, rough=0.3)
BAND = hb.mat("grub_band", "#b3a496", metal=0.0, rough=0.34)
HEAD = hb.mat("grub_head", "#a39890", metal=0.0, rough=0.32)
FACE = hb.mat("grub_face", "#857a73", metal=0.0, rough=0.36)
FEELER = hb.mat("grub_feeler", "#3d251d", metal=0.0, rough=0.28)

L = 1.36          # 몸 길이 (y: 꼬리 -L/2 → 머리 +L/2)
W = 0.92          # 최대 폭
H = 0.50          # 최대 높이
PEAK = 0.06       # 가장 높은 자리 (t, 앞이 +1) — 3면도 측면은 가운데보다 살짝 앞이 가장 높다
NSE = 2.6         # 단면 초타원 지수 (2 = 반원, 클수록 옆면이 서고 윗면이 넓다 — 정면도의 아래가 거의 수직인 옆면)
BANDS = [(0.24, 0.09), (-0.42, 0.085)]   # (중심 t, 반폭 t) — 측면도의 띠 두 개
ARC = 26          # 단면 윗호 점 수
BOT = 5           # 바닥 현 나눔

_n = [0]


def nm(p):
	_n[0] += 1
	return "%s_%03d" % (p, _n[0])


def profile(t):
	"""(반폭, 높이) at t ∈ (-1, 1). 앞쪽은 조금 더 뭉툭하다."""
	u = (t - PEAK) / (1.0 - PEAK) if t > PEAK else (t - PEAK) / (1.0 + PEAK)
	a = abs(u)
	aw, ah = (2.5, 2.35) if t > PEAK else (2.4, 2.25)
	w = W / 2 * max(0.0, 1.0 - a ** aw) ** (1.0 / aw)
	h = H * max(0.0, 1.0 - a ** ah) ** (1.0 / ah)
	return w, h


def ring_ts():
	ts = []
	K = 34
	for i in range(1, K):
		s = -1.0 + 2.0 * i / K
		ts.append(math.sin(s * math.pi / 2) * 0.985)      # 끝으로 갈수록 촘촘하게 (둥근 끝)
	for c, hw in BANDS:
		ts += [c - hw, c + hw]
	ts.sort()
	out = []
	for t in ts:
		if out and abs(t - out[-1]) < 0.025:
			if any(abs(t - (c + s * hw)) < 1e-6 for c, hw in BANDS for s in (-1, 1)):
				out[-1] = t       # 띠 경계 고리가 이긴다
			continue
		out.append(t)
	return out


def section(t):
	"""닫힌 고리: 윗호(오른쪽 바닥 → 꼭대기 → 왼쪽 바닥) + 바닥 현."""
	w, h = profile(t)
	y = t * L / 2
	pts = []
	for j in range(ARC + 1):
		th = math.pi * j / ARC
		c, s = math.cos(th), math.sin(th)
		x = w * math.copysign(abs(c) ** (2.0 / NSE), c)
		z = h * abs(s) ** (2.0 / NSE)
		pts.append(Vector((x, y, z)))
	for k in range(1, BOT):
		pts.append(Vector((-w + 2 * w * k / BOT, y, 0.0)))
	return pts


def in_band(t):
	return any(abs(t - c) < hw for c, hw in BANDS)


def build_body():
	import bmesh
	bm = bmesh.new()
	ts = ring_ts()
	rings = [[bm.verts.new(p) for p in section(t)] for t in ts]
	n = len(rings[0])
	for r in range(len(rings) - 1):
		tm = (ts[r] + ts[r + 1]) / 2
		for j in range(n):
			a, b = rings[r][j], rings[r][(j + 1) % n]
			c, d = rings[r + 1][(j + 1) % n], rings[r + 1][j]
			f = bm.faces.new((a, d, c, b))
			f.material_index = 1 if in_band(tm) else 0
	# 양 끝: 극점 부채꼴 (낮은 곳에 둬서 끝이 바닥 쪽으로 둥글게 내려앉는다)
	for idx, sgn in ((0, -1), (len(rings) - 1, 1)):
		_, h = profile(ts[idx])
		pole = bm.verts.new((0.0, sgn * L / 2, h * 0.42))
		ring = rings[idx]
		for j in range(n):
			a, b = ring[j], ring[(j + 1) % n]
			f = bm.faces.new((pole, a, b) if sgn > 0 else (pole, b, a))
			f.material_index = 0
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	me = bpy.data.meshes.new("body")
	bm.to_mesh(me)
	bm.free()
	o = bpy.data.objects.new("body", me)
	hb.collection().objects.link(o)
	me.materials.append(CREAM)
	me.materials.append(BAND)
	hb.shade_smooth(o, 50)
	return o


def _rot_to(d):
	q = Vector(d).normalized().to_track_quat("Z", "Y")
	return tuple(math.degrees(v) for v in q.to_euler())


def seg(part, a, b, r1, r2, mat, verts=12):
	a, b = Vector(a), Vector(b)
	d = b - a
	return hb.cyl(nm(part), r=r1, r2=r2, depth=d.length + 0.012, loc=tuple((a + b) / 2), rot=_rot_to(d), mat=mat,
		verts=verts, part=part, smooth=True)


def blob(part, c, radii, mat, seg_n=20):
	return hb.sphere(nm(part), r=1.0, loc=tuple(c), scale=radii, mat=mat, seg=seg_n, rings=seg_n // 2 + 1, part=part)


HEAD_PIV = Vector((0.0, 0.45, 0.12))
FEELER_BASE = Vector((0.075, 0.708, 0.088))
# 더듬이 마디: 뿌리에서 앞·바깥으로 뻗다가 끝이 아래로 말린다 (3면도의 짧고 둥근 갈색 부품을 읽히게 늘인 것)
FEELER_DIRS = [(0.42, 1.0, -0.05), (0.32, 1.0, -0.42), (0.05, 1.0, -0.85)]
FEELER_LEN = [0.095, 0.085, 0.07]
FEELER_R = [(0.04, 0.034), (0.034, 0.028), (0.028, 0.022)]

PIV = {"head": HEAD_PIV}
PARENT = {"head": None}
POINTS = []


def feeler(side):
	sx = -1.0 if side == "l" else 1.0
	p = Vector((FEELER_BASE.x * sx, FEELER_BASE.y, FEELER_BASE.z))
	parent = "head"
	for i, (d, ln, (r1, r2)) in enumerate(zip(FEELER_DIRS, FEELER_LEN, FEELER_R)):
		part = "feeler_%s_%d" % (side, i + 1)
		dv = Vector((d[0] * sx, d[1], d[2])).normalized()
		q = p + dv * ln
		seg(part, p, q, r1, r2, FEELER)
		blob(part, p, (r1 * 1.05,) * 3, FEELER, 12)          # 마디 이음 (구부려도 틈이 안 보이게)
		if i == 2:
			blob(part, q, (r2 * 1.35, r2 * 1.5, r2 * 1.35), FEELER, 14)   # 둥근 끝
			POINTS.append(("pt_feeler_tip_" + side, tuple(q), part))
		PIV[part] = p.copy()
		PARENT[part] = parent
		parent = part
		p = q


build_body()
# 머리 캡슐: 밝은 회색 테 + 앞으로 살짝 나온 짙은 얼굴판 (3면도 정면의 두 겹 회색 아치)
blob("head", (0.0, 0.565, 0.115), (0.22, 0.16, 0.16), HEAD, 28)
blob("head", (0.0, 0.645, 0.10), (0.16, 0.09, 0.125), FACE, 24)
feeler("l")
feeler("r")
POINTS += [
	("pt_eye_l", (-0.055, 0.728, 0.135), "head"),
	("pt_eye_r", (0.055, 0.728, 0.135), "head"),
	("pt_mouth", (0.0, 0.745, 0.06), "head"),
	("pt_tail", (0.0, -L / 2 + 0.04, 0.05), "body"),
]


def after_join():
	for part, p in PIV.items():
		hb.rebase(hb.get(part), Matrix.Translation(p))
	for part, parent in PARENT.items():
		if parent:
			hb.attach(hb.get(part), hb.get(parent))
	for name, p, parent in POINTS:
		hb.empty(name, p, parent=hb.get(parent))
