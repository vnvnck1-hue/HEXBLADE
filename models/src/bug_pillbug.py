# 벌레형 괴생명체 ② 공벌레 (PILL BUG). 크림색 등딱지 8장 · 회색 줄무늬 · 줄무늬 더듬이 · 꼬리 돌기 한 쌍 · 다리 6쌍.
# 몸을 말아 지름 약 1.2m 의 공이 되어 구른다 (원화의 흰 공벌레와 공 모양 변형).
# 빌드:  tools\blender.ps1 model models\src\bug_pillbug.py
#
# 등딱지 설계: 먼저 "다 말린 공" 상태에서 판 i 가 공 껍질의 45° 조각(경도 방향)을 차지하도록 만든 뒤,
# 관절 회전을 거꾸로 적용해 펼친 자세로 되돌려 놓는다. 그래서 Godot 에서 이웃 판 사이 관절을 X 축으로
# CURL(45°)씩 굽히면 판들이 틈 없이 공을 이룬다. 펼친 자세에서는 앞 판의 뒤끝이 다음 판 앞끝 위로 겹친다 (기와처럼,
# 뒤로 갈수록 반지름을 조금씩 줄여 겹친 면이 깜빡이지 않는다).
#
# 파츠 계층 (회전은 모두 0, 원점 = 관절):
#   seg_3 (몸 중심 판, 루트)
#     ├ seg_2 > seg_1 > seg_0(머리)   앞쪽 사슬: 관절 = 뒤쪽 판과의 이음매
#     │                     seg_0 ├ antenna_l_1 > antenna_l_2 > antenna_l_3 · _r
#     ├ seg_4 > seg_5 > seg_6 > seg_7   뒤쪽 사슬: 관절 = 앞쪽 판과의 이음매
#     │                     seg_7 ├ tail_l_1 > tail_l_2 · _r   (꼬리 돌기)
#     └ 각 판 seg_1~6 아래 leg_<i>_l_1 > leg_<i>_l_2 · _r
#   부착점: pt_ball_center(seg_3, 다 말렸을 때 공 중심) · pt_eye_l/r · pt_mouth · pt_antenna_tip_l/r · pt_foot_<i>_l/r
#   Godot: 앞쪽 사슬 관절은 rotation.x = -CURL·k, 뒤쪽 사슬은 +CURL·k (k = 1 이면 공).

import bmesh
from mathutils import Matrix

SHELL = hb.mat("pill_shell", "#ece2cc", metal=0.0, rough=0.3)
STRIPE = hb.mat("pill_stripe", "#8f857c", metal=0.0, rough=0.38)
INNER = hb.mat("pill_inner", "#cfc3ad", metal=0.0, rough=0.6)
BELLY = hb.mat("pill_belly", "#6f6660", metal=0.0, rough=0.62)
FACE = hb.mat("pill_face", "#6a605a", metal=0.0, rough=0.45)
LEG = hb.mat("pill_leg", "#8d847d", metal=0.0, rough=0.5)
DARK = hb.mat("pill_dark", "#2e2826", metal=0.1, rough=0.3)
EYE = hb.mat("bug_eye", "#0c0606", metal=0.2, rough=0.12)
SHINE = hb.mat("bug_shine", "#fff4e8", emit="#fff4e8", emit_power=0.6)

N = 8                         # 등딱지 판 수
S = 0.2                       # 펼친 자세에서 관절 사이 거리
BETA = 2 * math.pi / N        # 다 말렸을 때 관절 하나가 굽는 각도 (45°)
Z0 = 0.26                     # 관절 선 높이 (펼친 자세)
Y0 = S * N / 2                # 첫 관절(머리 앞) y
R0 = 0.6                      # 등딱지 바깥 반지름 (머리 판). 뒤로 갈수록 R_STEP 씩 줄어든다
R_STEP = 0.008
THICK = 0.05                  # 등딱지 두께
XS = 0.8                      # 좌우 납작함 (공도 살짝 납작한 타원체)
LAT = math.radians(74)        # 옆으로 덮는 위도 한계 (그 아래로 다리가 보인다)
REAR_LAP = 0.16               # 판 뒤끝을 다음 판 위로 더 늘이는 비율 (말렸을 때 틈 방지)
STRIPE_K = 0.3                # 판 뒤쪽 이 비율만큼 회색 줄무늬

_n = [0]


def nm(p):
	_n[0] += 1
	return "%s_%03d" % (p, _n[0])


def rx(a):
	return Matrix.Rotation(a, 4, "X")


# 펼친 자세 관절 p_i 와 다 말린 자세 관절 c_i
P = [Vector((0, Y0 - i * S, Z0)) for i in range(N + 1)]
C = [P[0].copy()]
for i in range(N):
	C.append(C[i] + (rx(i * BETA).to_3x3() @ Vector((0, -S, 0))))
APO = S / (2 * math.tan(BETA / 2))
B = Vector((0, Y0 - S / 2, Z0 - APO))      # 다 말렸을 때 공 중심 (판 0 좌표계 = 월드)
RP = S / (2 * math.sin(BETA / 2))


def to_rest(i, x):
	"""Curled-ball position of plate i -> its rest position (inverse of the chain bend)."""
	return P[i] + (rx(-i * BETA).to_3x3() @ (Vector(x) - C[i]))


def ang(v):
	"""Angle of a YZ direction measured from +Y toward +Z."""
	return math.atan2(v.z, v.y)


def shell_plate(i):
	"""Plate i: a thick slice of the (x-squashed) ball between the rays through c_i and c_i+1, mapped to rest."""
	R = R0 - R_STEP * i
	a0 = ang(C[i] - B)
	a1 = ang(C[i + 1] - B)
	# 공 중심에서 본 판의 각도 폭 (부호 포함, 45°). 뒤끝을 REAR_LAP 만큼 늘인다.
	span = math.atan2(math.sin(a1 - a0), math.cos(a1 - a0))
	a1 = a0 + span * (1 + REAR_LAP)
	NU, NV = 7, 14
	bm = bmesh.new()

	def pos(u, v, rho):
		th = a0 + (a1 - a0) * u
		ph = -LAT + 2 * LAT * v
		d = Vector((0, math.cos(th), math.sin(th)))
		p = B + Vector((math.sin(ph) * rho * XS, 0, 0)) + d * (math.cos(ph) * rho)
		return to_rest(i, p)

	outer = [[bm.verts.new(pos(u / NU, v / NV, R)) for v in range(NV + 1)] for u in range(NU + 1)]
	inner = [[bm.verts.new(pos(u / NU, v / NV, R - THICK)) for v in range(NV + 1)] for u in range(NU + 1)]
	faces = []
	for u in range(NU):
		for v in range(NV):
			f = bm.faces.new((outer[u][v], outer[u + 1][v], outer[u + 1][v + 1], outer[u][v + 1]))
			f.material_index = 1 if u >= NU * (1 - STRIPE_K) - 0.01 else 0
			faces.append(f)
			g = bm.faces.new((inner[u][v + 1], inner[u + 1][v + 1], inner[u + 1][v], inner[u][v]))
			g.material_index = 2
	# 가장자리 벽 (앞뒤 · 양옆)
	for v in range(NV):
		for u, rev in ((0, False), (NU, True)):
			q = (outer[u][v], outer[u][v + 1], inner[u][v + 1], inner[u][v])
			bm.faces.new(q[::-1] if rev else q).material_index = 2
	for u in range(NU):
		for v, rev in ((0, True), (NV, False)):
			q = (outer[u][v], outer[u + 1][v], inner[u + 1][v], inner[u][v])
			bm.faces.new(q[::-1] if rev else q).material_index = 2
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	name = nm("seg_%d" % i)
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	o = bpy.data.objects.new(name, me)
	hb.collection().objects.link(o)
	for m in (SHELL, STRIPE, INNER):
		me.materials.append(m)
	o["hb_part"] = "seg_%d" % i
	hb.shade_smooth(o, 50)
	return o


def _rot_to(d):
	q = Vector(d).normalized().to_track_quat("Z", "Y")
	return tuple(math.degrees(v) for v in q.to_euler())


def limb(part, a, b, r1, r2, mat, verts=8, over=0.0):
	a, b = Vector(a), Vector(b)
	d = b - a
	return hb.cyl(nm(part), r=r1, r2=r2, depth=d.length + over * 2, loc=tuple((a + b) / 2), rot=_rot_to(d), mat=mat,
				  verts=verts, part=part)


def blob(part, c, radii, mat, rot=(0, 0, 0)):
	big = max(radii)
	seg = 20 if big > 0.12 else (12 if big > 0.04 else 8)
	return hb.sphere(nm(part), r=1.0, loc=tuple(c), rot=rot, scale=radii, mat=mat, seg=seg, rings=seg // 2 + 1, part=part)


PIV, PARENT, POINTS = {}, {}, []


def joint(part, pivot, parent):
	PIV[part] = Vector(pivot)
	PARENT[part] = parent


# ════════════════════════════════════════════════════════════════
#  등딱지 8장 + 배 판 (다 말리면 공 속으로 들어간다)
# ════════════════════════════════════════════════════════════════
for i in range(N):
	shell_plate(i)
	mid = (P[i] + P[i + 1]) / 2
	w = 0.34 - 0.025 * abs(i - 3.5)
	blob("seg_%d" % i, mid + Vector((0, 0, -0.04)), (w, S * 0.62, 0.075), BELLY)
# 관절: 루트 seg_3 은 몸 중심 아래 바닥, 앞쪽 사슬은 뒤쪽 이음매, 뒤쪽 사슬은 앞쪽 이음매
joint("seg_3", (0, (P[3].y + P[4].y) / 2, 0), None)
for i in (2, 1, 0):
	joint("seg_%d" % i, P[i + 1], "seg_%d" % (i + 1))
for i in (4, 5, 6, 7):
	joint("seg_%d" % i, P[i], "seg_%d" % (i - 1))
POINTS.append(("pt_ball_center", tuple(to_rest(3, B)), "seg_3"))

# ════════════════════════════════════════════════════════════════
#  머리 (seg_0 앞): 짙은 얼굴 판 · 검은 눈 · 입 · 줄무늬 더듬이 세 마디
# ════════════════════════════════════════════════════════════════
fy = P[0].y
HEAD = hb.mat("pill_head", "#d8ccb4", metal=0.0, rough=0.34)
blob("seg_0", (0, fy - 0.1, 0.27), (0.4, 0.2, 0.24), HEAD)          # 이마 방패: 등딱지 앞 구멍을 막는다
blob("seg_0", (0, fy + 0.02, 0.22), (0.28, 0.14, 0.14), FACE)
blob("seg_0", (0, fy + 0.1, 0.13), (0.15, 0.08, 0.06), DARK)       # 입
for s, k in ((-1, "l"), (1, "r")):
	blob("seg_0", (s * 0.2, fy + 0.08, 0.3), (0.05, 0.05, 0.055), EYE)
	blob("seg_0", (s * 0.215, fy + 0.12, 0.32), (0.012, 0.012, 0.012), SHINE)
	POINTS.append(("pt_eye_" + k, (s * 0.22, fy + 0.13, 0.3), "seg_0"))
POINTS.append(("pt_mouth", (0, fy + 0.18, 0.12), "seg_0"))
for s, k in ((-1, "l"), (1, "r")):
	a = Vector((s * 0.14, fy + 0.11, 0.24))
	b = Vector((s * 0.3, fy + 0.3, 0.24))
	c = Vector((s * 0.42, fy + 0.52, 0.17))
	d = Vector((s * 0.48, fy + 0.74, 0.07))
	names = ["antenna_%s_%d" % (k, n) for n in (1, 2, 3)]
	for (p0, p1, part, r0, r1, m) in ((a, b, names[0], 0.035, 0.03, SHELL), (b, c, names[1], 0.03, 0.024, SHELL),
									  (c, d, names[2], 0.024, 0.012, SHELL)):
		blob(part, p0, (r0 * 1.15,) * 3, STRIPE)
		limb(part, p0, p1, r0, r1, m)
		for f in (0.3, 0.65):
			hb.torus(nm(part), r=r0 + (r1 - r0) * f, thick=0.009, loc=tuple(p0.lerp(p1, f)), rot=_rot_to(p1 - p0),
					 mat=STRIPE, seg=12, ring=4, part=part)
	limb(names[2], c.lerp(d, 0.7), d, 0.018, 0.006, DARK, over=0.01)
	joint(names[0], a, "seg_0")
	joint(names[1], b, names[0])
	joint(names[2], c, names[1])
	POINTS.append(("pt_antenna_tip_" + k, tuple(d), names[2]))

# ════════════════════════════════════════════════════════════════
#  꼬리 돌기 (seg_7 뒤): 뒤로 뻗은 두 마디 줄무늬 가시
# ════════════════════════════════════════════════════════════════
ty = P[N].y
for s, k in ((-1, "l"), (1, "r")):
	a = Vector((s * 0.13, ty + 0.06, 0.2))
	b = Vector((s * 0.2, ty - 0.12, 0.16))
	c = Vector((s * 0.26, ty - 0.32, 0.12))
	t1, t2 = "tail_%s_1" % k, "tail_%s_2" % k
	blob(t1, a, (0.04, 0.04, 0.04), STRIPE)
	limb(t1, a, b, 0.035, 0.028, SHELL)
	blob(t2, b, (0.03, 0.03, 0.03), STRIPE)
	limb(t2, b, c, 0.028, 0.008, SHELL)
	hb.torus(nm(t2), r=0.022, thick=0.008, loc=tuple(b.lerp(c, 0.4)), rot=_rot_to(c - b), mat=STRIPE, seg=12, ring=4, part=t2)
	joint(t1, a, "seg_7")
	joint(t2, b, t1)

# ════════════════════════════════════════════════════════════════
#  다리 6쌍 (seg_1 ~ seg_6): 배 옆에서 나와 등딱지 가장자리 아래로 꺾여 바닥을 딛는다
# ════════════════════════════════════════════════════════════════
for i in range(1, 7):
	y = (P[i].y + P[i + 1].y) / 2
	spread = (i - 3.5) * 0.025       # 앞다리는 앞으로, 뒷다리는 뒤로 조금 벌린다
	for s, k in ((-1, "l"), (1, "r")):
		hip = Vector((s * 0.24, y, 0.2))
		knee = Vector((s * 0.47, y + spread, 0.17))
		foot = Vector((s * 0.53, y + spread * 2.2, 0.0))
		u, l = "leg_%d_%s_1" % (i, k), "leg_%d_%s_2" % (i, k)
		blob(u, hip, (0.035, 0.035, 0.035), LEG)
		limb(u, hip, knee, 0.032, 0.024, LEG, over=0.01)
		blob(l, knee, (0.028, 0.028, 0.028), STRIPE)
		limb(l, knee, foot, 0.024, 0.006, DARK, over=0.005)
		joint(u, hip, "seg_%d" % i)
		joint(l, knee, u)
		POINTS.append(("pt_foot_%d_%s" % (i, k), tuple(foot), l))


def after_join():
	# 회전 0 · 원점 = 관절 (합칠 때 첫 도형의 회전이 남지 않게 다시 잡는다)
	for part, p in PIV.items():
		hb.rebase(hb.get(part), Matrix.Translation(p))
	for part, parent in PARENT.items():
		if parent:
			hb.attach(hb.get(part), hb.get(parent))
	for name, p, parent in POINTS:
		hb.empty(name, p, parent=hb.get(parent))
