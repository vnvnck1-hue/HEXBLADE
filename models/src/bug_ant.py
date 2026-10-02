# 벌레형 괴생명체 ① 개미 병정 (ANT SOLDIER). 두 다리로 선 개미 — 큰 투구 머리 · 검은 큰턱 · 팔꿈치처럼 꺾인 더듬이 ·
# 세 쌍의 다리(뒷다리 = 걷는 다리, 가운데 다리 = 작게 버둥, 앞다리 = 집게 팔) · 뒤로 솟은 줄무늬 배(배 끝에서 산을 쏜다).
# 참고: 사용자 원화(적갈색 개미 두 장, 반들거리는 하이라이트와 짙은 줄무늬). 높이 약 1.75m(더듬이 끝), 머리 꼭대기 약 1.42m.
# 빌드:  tools\blender.ps1 model models\src\bug_ant.py
#
# 파츠 계층 (모든 파츠의 회전은 0 — Godot 에서 관절 피벗을 축으로 돌려 애니메이션한다):
#   pelvis (허리 마디, 원점 = 몸 중심 · 바닥에서 0.66m)
#     ├ thorax (가슴, 원점 = 허리 위)
#     │   ├ head (원점 = 목)
#     │   │   ├ mandible_l / _r (큰턱, 원점 = 턱 경첩)
#     │   │   └ antenna_l_1 > antenna_l_2 > antenna_l_3   (더듬이: 밑마디 · 꺾인 채찍 · 끝 곤봉, 원점 = 각 관절) · _r 같음
#     │   ├ arm_l_upper > arm_l_fore > arm_l_claw           (앞다리 집게 팔) · _r
#     │   └ mid_l_upper > mid_l_lower                       (가운데 다리) · _r
#     ├ gaster_1 > gaster_2                                 (배 두 마디, 원점 = 이음매)
#     └ leg_l_thigh > leg_l_shin > leg_l_foot               (뒷다리) · _r
#   부착점: pt_eye_l/r · pt_mouth · pt_stinger(산 발사구) · pt_foot_l/r(발바닥) · pt_antenna_tip_l/r

from mathutils import Matrix

RED = hb.mat("ant_red", "#b04a2c", metal=0.0, rough=0.32)
RED2 = hb.mat("ant_red_dark", "#8a3420", metal=0.0, rough=0.36)
STRIPE = hb.mat("ant_stripe", "#5a2014", metal=0.0, rough=0.4)
JOINT = hb.mat("ant_joint", "#6e2a1a", metal=0.0, rough=0.5)
JAW = hb.mat("ant_jaw", "#2b120c", metal=0.1, rough=0.28)
EYE = hb.mat("bug_eye", "#0c0606", metal=0.2, rough=0.12)
SHINE = hb.mat("bug_shine", "#fff4e8", emit="#fff4e8", emit_power=0.6)

_n = [0]


def nm(p):
	_n[0] += 1
	return "%s_%03d" % (p, _n[0])


def _rot_to(d):
	"""Euler degrees that turn local +Z toward direction d."""
	q = Vector(d).normalized().to_track_quat("Z", "Y")
	return tuple(math.degrees(v) for v in q.to_euler())


def limb(part, a, b, r1, r2, mat, verts=8, over=0.0):
	"""Tapered segment from a to b (radius r1 at a, r2 at b). over = extra length past both ends (overlap joints)."""
	a, b = Vector(a), Vector(b)
	d = b - a
	L = d.length
	c = (a + b) / 2
	return hb.cyl(nm(part), r=r1, r2=r2, depth=L + over * 2, loc=tuple(c), rot=_rot_to(d), mat=mat, verts=verts, part=part)


def blob(part, c, radii, mat, rot=(0, 0, 0), seg=None, rings=None):
	big = max(radii)
	seg = seg or (20 if big > 0.12 else (12 if big > 0.04 else 8))
	rings = rings or seg // 2 + 1
	return hb.sphere(nm(part), r=1.0, loc=tuple(c), rot=rot, scale=radii, mat=mat, seg=seg, rings=rings, part=part)


def band(part, c, r, thick, axis, mat, scale=(1, 1, 1)):
	"""Stripe ring around a body segment (flattened torus) facing `axis`."""
	o = hb.torus(nm(part), r=r, thick=thick, loc=tuple(c), rot=_rot_to(axis), mat=mat, seg=20, ring=5, part=part)
	o.scale = scale
	return o


def mirror_x(p):
	return (-p[0], p[1], p[2])


PIV, PARENT, POINTS = {}, {}, []


def joint(part, pivot, parent):
	PIV[part] = Vector(pivot)
	PARENT[part] = parent


# ════════════════════════════════════════════════════════════════
#  허리 · 가슴
# ════════════════════════════════════════════════════════════════
blob("pelvis", (0, -0.03, 0.66), (0.13, 0.12, 0.11), RED2)
blob("pelvis", (0, -0.12, 0.67), (0.07, 0.08, 0.07), JOINT)      # 배로 이어지는 잘록한 자루마디
joint("pelvis", (0, -0.02, 0.66), None)

blob("thorax", (0, 0.05, 0.9), (0.165, 0.15, 0.24), RED, rot=(-16, 0, 0))
blob("thorax", (0, 0.11, 0.98), (0.13, 0.12, 0.13), RED2, rot=(-16, 0, 0))     # 앞가슴 판
band("thorax", (0, 0.06, 0.86), 0.15, 0.022, (0, -0.28, 1), STRIPE, scale=(1.0, 0.92, 1.0))
blob("thorax", (0.07, 0.15, 1.0), (0.035, 0.02, 0.05), SHINE, rot=(-16, 0, 20))   # 반들거리는 하이라이트
joint("thorax", (0, 0.0, 0.72), "pelvis")

# ════════════════════════════════════════════════════════════════
#  머리: 앞으로 길게 뻗은 투구 · 옆의 검은 큰 눈 · 아래 검은 입 · 큰턱
# ════════════════════════════════════════════════════════════════
blob("head", (0, 0.13, 1.14), (0.07, 0.07, 0.07), JOINT)      # 목
blob("head", (0, 0.32, 1.25), (0.2, 0.3, 0.18), RED, rot=(-12, 0, 0))
blob("head", (0, 0.27, 1.36), (0.16, 0.21, 0.09), RED2, rot=(-12, 0, 0))     # 정수리 능선
blob("head", (0, 0.5, 1.13), (0.14, 0.12, 0.09), JAW, rot=(-20, 0, 0))     # 입 둘레 검은 판
band("head", (0, 0.19, 1.27), 0.18, 0.02, (0, 1, 0.25), STRIPE, scale=(1.0, 1.0, 0.9))
for s in (-1, 1):
	blob("head", (s * 0.16, 0.38, 1.28), (0.06, 0.08, 0.075), EYE)
	blob("head", (s * 0.18, 0.41, 1.31), (0.014, 0.018, 0.018), SHINE)
	POINTS.append(("pt_eye_" + ("l" if s < 0 else "r"), (s * 0.18, 0.42, 1.28), "head"))
blob("head", (0.06, 0.37, 1.41), (0.045, 0.08, 0.02), SHINE, rot=(-12, 0, 10))
POINTS.append(("pt_mouth", (0, 0.66, 1.06), "head"))
joint("head", (0, 0.13, 1.13), "thorax")

# 큰턱: 경첩에서 앞으로 뻗었다 안쪽으로 휘는 낫 모양 (두 마디 + 끝 갈고리)
for s, k in ((-1, "l"), (1, "r")):
	part = "mandible_" + k
	hinge = (s * 0.1, 0.52, 1.1)
	mid = (s * 0.15, 0.68, 1.02)
	tip = (s * 0.04, 0.8, 0.96)
	blob(part, hinge, (0.06, 0.065, 0.055), JAW)
	limb(part, hinge, mid, 0.06, 0.045, JAW, over=0.02)
	blob(part, mid, (0.045, 0.045, 0.045), JAW)
	limb(part, mid, tip, 0.045, 0.008, JAW, over=0.01)
	limb(part, (s * 0.135, 0.64, 1.04), (s * 0.085, 0.67, 1.03), 0.016, 0.004, JAW)     # 안쪽 톱니
	limb(part, (s * 0.12, 0.73, 1.0), (s * 0.07, 0.75, 0.99), 0.013, 0.003, JAW)
	joint(part, hinge, "head")

# 더듬이: 정수리 앞쪽에서 위로 솟은 밑마디 → 팔꿈치처럼 꺾여 앞으로 뻗은 채찍 → 짙은 곤봉 끝
for s, k in ((-1, "l"), (1, "r")):
	base = Vector((s * 0.08, 0.5, 1.35))
	elbow = Vector((s * 0.2, 0.44, 1.66))
	knot = Vector((s * 0.32, 0.7, 1.74))
	tip = Vector((s * 0.38, 0.95, 1.67))
	p1, p2, p3 = "antenna_%s_1" % k, "antenna_%s_2" % k, "antenna_%s_3" % k
	blob(p1, base, (0.035, 0.035, 0.035), JOINT)
	limb(p1, base, elbow, 0.026, 0.02, RED2)
	blob(p2, elbow, (0.028, 0.028, 0.028), STRIPE)
	limb(p2, elbow, knot, 0.02, 0.017, RED)
	for f in (0.33, 0.66):
		band(p2, elbow.lerp(knot, f), 0.019, 0.007, knot - elbow, STRIPE)
	blob(p3, knot, (0.022, 0.022, 0.022), STRIPE)
	limb(p3, knot, knot.lerp(tip, 0.55), 0.017, 0.022, RED2)
	limb(p3, knot.lerp(tip, 0.55), tip, 0.024, 0.012, STRIPE, over=0.01)     # 곤봉 끝
	joint(p1, base, "head")
	joint(p2, elbow, p1)
	joint(p3, knot, p2)
	POINTS.append(("pt_antenna_tip_" + k, tuple(tip), p3))

# ════════════════════════════════════════════════════════════════
#  앞다리 = 집게 팔 · 가운데 다리
# ════════════════════════════════════════════════════════════════
for s, k in ((-1, "l"), (1, "r")):
	sh = Vector((s * 0.14, 0.13, 1.02))
	el = Vector((s * 0.27, 0.17, 0.8))
	wr = Vector((s * 0.25, 0.38, 0.84))
	tip = Vector((s * 0.2, 0.5, 0.78))
	u, f, c = "arm_%s_upper" % k, "arm_%s_fore" % k, "arm_%s_claw" % k
	blob(u, sh, (0.05, 0.05, 0.05), JOINT)
	limb(u, sh, el, 0.048, 0.035, RED, over=0.01)
	blob(f, el, (0.04, 0.04, 0.04), JOINT)
	limb(f, el, wr, 0.04, 0.028, RED2, over=0.01)
	band(f, el.lerp(wr, 0.75), 0.03, 0.008, wr - el, STRIPE)
	blob(c, wr, (0.032, 0.032, 0.032), JAW)
	limb(c, wr, tip, 0.028, 0.006, JAW)
	limb(c, wr, wr + Vector((s * 0.06, 0.08, -0.09)), 0.022, 0.005, JAW)     # 아래 갈고리
	joint(u, sh, "thorax")
	joint(f, el, u)
	joint(c, wr, f)

	mh = Vector((s * 0.13, 0.02, 0.82))
	mk = Vector((s * 0.32, 0.02, 0.8))
	mf = Vector((s * 0.43, 0.12, 0.62))
	mu, ml = "mid_%s_upper" % k, "mid_%s_lower" % k
	blob(mu, mh, (0.04, 0.04, 0.04), JOINT)
	limb(mu, mh, mk, 0.035, 0.026, RED2, over=0.01)
	blob(ml, mk, (0.03, 0.03, 0.03), JOINT)
	limb(ml, mk, mf, 0.026, 0.008, JAW, over=0.01)
	joint(mu, mh, "thorax")
	joint(ml, mk, mu)

# ════════════════════════════════════════════════════════════════
#  배: 자루마디 뒤로 두 마디, 뒤로 갈수록 굵어지며 위로 솟는다 (원화의 다람쥐 꼬리 같은 줄무늬 배)
# ════════════════════════════════════════════════════════════════
g1c = Vector((0, -0.3, 0.71))
blob("gaster_1", g1c, (0.17, 0.19, 0.16), RED, rot=(25, 0, 0))
for f, r in ((-0.06, 0.16), (0.07, 0.15)):
	band("gaster_1", g1c + Vector((0, f - 0.02, f * 0.45)), r, 0.02, (0, 0.9, -0.45), STRIPE, scale=(1.0, 1.0, 0.95))
blob("gaster_1", (0.07, -0.25, 0.83), (0.04, 0.05, 0.02), SHINE, rot=(25, 0, 15))
joint("gaster_1", (0, -0.12, 0.67), "pelvis")

g2c = Vector((0, -0.62, 0.92))
blob("gaster_2", g2c, (0.24, 0.27, 0.25), RED, rot=(40, 0, 0))
for f, r in ((-0.15, 0.2), (-0.02, 0.235), (0.11, 0.21)):
	band("gaster_2", g2c + Vector((0, f * 0.75, -f * 0.65)), r, 0.024, (0, 0.75, -0.65), STRIPE, scale=(1.0, 1.0, 0.98))
blob("gaster_2", (0.1, -0.52, 1.1), (0.05, 0.08, 0.03), SHINE, rot=(40, 0, 20))
limb("gaster_2", (0, -0.82, 0.74), (0, -0.92, 0.64), 0.04, 0.008, JAW)     # 배 끝 침(산 발사구)
joint("gaster_2", (0, -0.42, 0.76), "gaster_1")
POINTS.append(("pt_stinger", (0, -0.93, 0.63), "gaster_2"))

# ════════════════════════════════════════════════════════════════
#  뒷다리 (걷는 다리): 고관절 → 앞으로 꺾인 넓적다리 → 뒤로 내려오는 정강이 → 앞으로 누운 발목마디
# ════════════════════════════════════════════════════════════════
for s, k in ((-1, "l"), (1, "r")):
	hip = Vector((s * 0.12, -0.03, 0.62))
	knee = Vector((s * 0.2, 0.14, 0.36))
	ank = Vector((s * 0.21, -0.04, 0.1))
	toe = Vector((s * 0.21, 0.12, 0.012))
	t, sh, ft = "leg_%s_thigh" % k, "leg_%s_shin" % k, "leg_%s_foot" % k
	blob(t, hip, (0.07, 0.07, 0.07), JOINT)
	limb(t, hip, knee, 0.07, 0.05, RED, over=0.01)
	blob(t, hip.lerp(knee, 0.4) + Vector((s * 0.02, 0, 0)), (0.06, 0.07, 0.09), RED2, rot=(-35, 0, 0))   # 허벅지 근육 덩이
	blob(sh, knee, (0.05, 0.05, 0.05), JOINT)
	limb(sh, knee, ank, 0.05, 0.032, RED2, over=0.01)
	band(sh, knee.lerp(ank, 0.3), 0.045, 0.01, ank - knee, STRIPE)
	blob(ft, ank, (0.035, 0.035, 0.035), JAW)
	limb(ft, ank, toe, 0.032, 0.014, JAW, over=0.005)
	limb(ft, toe + Vector((0, -0.02, 0.0)), toe + Vector((s * 0.03, 0.06, -0.005)), 0.012, 0.003, JAW)   # 발톱
	joint(t, hip, "pelvis")
	joint(sh, knee, t)
	joint(ft, ank, sh)
	POINTS.append(("pt_foot_" + k, (s * 0.21, 0.04, 0.0), ft))


def after_join():
	# 회전 0 · 원점 = 관절 (합칠 때 첫 도형의 회전이 남지 않게 다시 잡는다)
	for part, p in PIV.items():
		hb.rebase(hb.get(part), Matrix.Translation(p))
	for part, parent in PARENT.items():
		if parent:
			hb.attach(hb.get(part), hb.get(parent))
	for name, p, parent in POINTS:
		hb.empty(name, p, parent=hb.get(parent))
