# 거미 보스 SHIPWRIGHT — 원화 output/spider-boss-20261001/spider-boss-three-views.png 를 재현하는 모델.
# 빌드 · 원화 비교:  tools\blender.ps1 model models\src\spider_boss.py --compare
#
# 치수는 원화에서 직접 잰 값(미터, models/ref/spider_boss.json 의 축척: 정면 50px/m · 측면 56px/m).
# 원화는 생성 이미지라 세 시점이 서로 맞지 않는다 → 정면(X·Z)과 측면(Y·Z)을 기준으로 하고, 평면은 배치 참고.
#   예: 정면은 개틀링이 1.5m · 용접기가 아래로 늘어짐, 측면은 개틀링 2.5m · 용접기가 앞으로 뻗음 → 사이값.
# 원화에 없는 속(관절 안쪽 · 하부 기계 · 배선)은 메카닉 모델링 관례로 채웠다:
#   짙은 프레임 위에 푸른 장갑판을 겹침 · 관절은 볼트 원판 · 관절마다 유압 실린더/배선 · 모든 모서리 베벨 · 판 이음 선.
#
# 좌표: 1 = 1m, 정면 +Y, 위 +Z, 거미의 오른쪽 +X (용접기 팔), 왼쪽 -X (집게 + 원형 톱 팔).
# Godot 노드 계층 (원점 = 관절):
#   body ┬ head ─ gatling
#        ├ abdomen ─ tablet
#        ├ leg_<fl|fr|bl|br>_coxa(몸 옆 받침) ─ _femur(고관절) ─ _tibia(무릎) ─ _foot(발목)
#        └ arm_welder_upper(어깨) ─ _fore(팔꿈치) ─ _tool(손목) · arm_saw_upper ─ _fore ─ _tool ─ arm_saw_disc
#   다리·팔 마디: 로컬 +Y = 마디 방향, 로컬 +Z = 바깥(다리 평면 안에서 몸 반대쪽).

import json
import os

from mathutils import Matrix

# 매개변수 탐색용: HB_OVERRIDE='{"GZ": 2.2, ...}' 로 아래 기본값을 바꿔 빌드한다 (tools/blender/sweep.py)
OV = json.loads(os.environ.get("HB_OVERRIDE", "{}"))


def ov(key, default):
	return OV.get(key, default)

# 원화에서 뽑은 색
BLUE = hb.mat("blue", "#5b97d3", metal=0.25, rough=0.42)
BLUE_D = hb.mat("blue_seam", "#2f5f9e", metal=0.25, rough=0.5)
FRAME = hb.mat("frame", "#575861", metal=0.6, rough=0.45)
DARK = hb.mat("dark", "#33353c", metal=0.6, rough=0.5)
BLACK = hb.mat("black", "#222328", metal=0.3, rough=0.7)
GREY = hb.mat("grey", "#90939a", metal=0.7, rough=0.35)
GREY_L = hb.mat("grey_light", "#b4b8c0", metal=0.7, rough=0.3)
STEEL = hb.mat("steel", "#d2d6dc", metal=0.9, rough=0.22)
EYE = hb.mat("eye_glow", "#9ff8f3", emit="#5fe9e2", emit_power=0.9, rough=0.05)
TEAL = hb.mat("teal_glow", "#50f5f8", emit="#30e0e6", emit_power=1.4)
SCREEN = hb.mat("screen_glow", "#2f7f90", emit="#2aa6c0", emit_power=0.9)
LINE = hb.mat("screen_line", "#9ff7ff", emit="#9ff7ff", emit_power=2.0)
RED = hb.mat("red", "#e8463c", emit="#e8463c", emit_power=0.8)
BRASS = hb.mat("brass", "#c9a24e", metal=0.85, rough=0.3)
YELLOW = hb.mat("hazard_yellow", "#e0aa22", metal=0.2, rough=0.5)

_n = [0]


def nm(p):
	_n[0] += 1
	return "%s_%03d" % (p, _n[0])


def box(part, size, loc, mat, bevel=0.05, rot=(0, 0, 0), taper=None, taper_axis="Z", seg=2):
	return hb.box(nm(part), size, tuple(loc), rot=rot, mat=mat, bevel=bevel, seg=seg, part=part, taper=taper, taper_axis=taper_axis)


def cyl(part, r, depth, loc, mat, rot=(0, 0, 0), r2=None, verts=24, bevel=0.0, smooth=True):
	return hb.cyl(nm(part), r, depth, tuple(loc), rot=rot, mat=mat, verts=verts, r2=r2, bevel=bevel, part=part, smooth=smooth)


def side(part, pts, depth, x, mat, bevel=0.06, seg=2, cuts=0):
	"""Side-profile plate: outline (Y, Z) extruded across X, centred at x."""
	return hb.prism(nm(part), pts, depth, (x, 0, 0), mat=mat, bevel=bevel, seg=seg, part=part, cuts=cuts)


def _deg(axis):
	return tuple(math.degrees(v) for v in Vector(axis).normalized().to_track_quat("Z", "Y").to_euler())


def disc(part, r, depth, loc, axis, mat, verts=32, bolts=8):
	"""Bolted joint disc (plate · dark hub · bolt ring) with its axis along `axis`."""
	a = Vector(axis).normalized()
	deg = _deg(a)
	c = Vector(loc)
	cyl(part, r, depth, c, mat, rot=deg, verts=verts, bevel=min(0.04, depth * 0.3))
	cyl(part, r * 0.32, depth + 0.06, c, DARK, rot=deg, verts=16)
	q = a.to_track_quat("Z", "Y")
	for i in range(bolts):
		t = 2 * math.pi * i / bolts
		p = c + q @ Vector((math.cos(t) * r * 0.72, math.sin(t) * r * 0.72, 0)) + a * (depth / 2)
		cyl(part, r * 0.07, 0.05, p, DARK, rot=deg, verts=8, smooth=False)


def rivets(part, pts, normal, r=0.045):
	deg = _deg(normal)
	for p in pts:
		cyl(part, r, 0.05, p, DARK, rot=deg, verts=8, smooth=False)


def pipe(part, pts, r, mat):
	return hb.tube(nm(part), [tuple(p) for p in pts], r=r, mat=mat, part=part)


FRAMES, PARENT, POINTS = {}, {}, []


def at(part, matrix, parent):
	FRAMES[part] = matrix
	PARENT[part] = parent


def seg(part, fr, items, parent):
	"""Shapes given in a limb frame (local +Y along the segment, +Z outward)."""
	e = hb.empty("_f_" + part)
	e.matrix_world = fr
	for kind, kw in items:
		kw = dict(kw)
		kw["part"] = part
		kw["parent"] = e
		getattr(hb, kind)(nm(part), **kw)
	at(part, fr, parent)


# ════════════════════════════════════════════════════════════════
#  머리 (head) — 측면: 앞이 둥근 길고 낮은 푸른 투구, 옆에 창 달린 회색 판 · 정면: 큰 청록 눈 둘과 남색 콧날
# ════════════════════════════════════════════════════════════════
H = "head"
shell = side(H, [(1.0, 3.8), (4.35, 3.8), (4.82, 4.05), (4.98, 4.42), (4.85, 4.8), (4.4, 5.1), (3.6, 5.4), (2.6, 5.6), (1.0, 5.62)],
			 3.5, 0, BLUE, bevel=0.32, seg=4)
# 정면에서 위가 좁아 보이게: 정수리 쪽 옆면을 안으로 기울인다
hb.deform(shell, lambda p: Vector((p.x * (1.0 - 0.45 * max(0.0, min(1.0, (p.z - 4.5) / 1.1))), p.y, p.z)))
def chin(p):
	"""Face narrows toward the gatling below the eyes (front view: a rounded shield)."""
	k = max(0.0, min(1.0, (3.75 - p.z) / 1.0))
	return Vector((p.x * (1.0 - 0.42 * k), p.y, p.z))


for s in (-1, 1):
	# 볼 장갑: 눈 바깥을 감싸며 아래로 내려와 턱 쪽으로 모인다
	cheek = side(H, [(2.3, 2.85), (4.45, 2.85), (4.82, 3.35), (4.9, 4.55), (4.5, 5.05), (2.3, 5.05)], 0.42, s * 1.8, BLUE, bevel=0.14, seg=3)
	hb.deform(cheek, chin)
	# 옆 회색 판 + 창 (측면) · 뒤 회색 판
	box(H, (0.08, 1.95, 0.78), (s * 2.02, 3.05, 4.3), GREY_L, 0.03)
	box(H, (0.06, 1.15, 0.28), (s * 2.07, 3.0, 4.42), DARK, 0.03)
	box(H, (0.05, 0.5, 0.12), (s * 2.1, 3.05, 4.42), GREY, 0.02)
	box(H, (0.08, 1.0, 0.62), (s * 1.62, 1.6, 4.95), GREY_L, 0.03)
	rivets(H, [(s * 2.07, y, z) for y in (2.2, 3.9) for z in (4.0, 4.6)], (s, 0, 0))
	# 투구 옆면 볼트 · 판 이음 (원화 측면 투구의 점과 선)
	rivets(H, [(s * 1.42, y, 5.1) for y in (2.0, 2.7, 3.4)], (s, 0, 0.6))
	box(H, (0.04, 0.05, 1.0), (s * 1.95, 1.95, 4.4), BLUE_D, 0.0)
	box(H, (0.04, 2.2, 0.05), (s * 1.97, 3.0, 3.88), BLUE_D, 0.0)
	rivets(H, [(s * 1.67, y, z) for y in (1.25, 1.95) for z in (4.75, 5.15)], (s, 0, 0))
	# 투구 위 가장자리의 짙은 덧판 (측면 위쪽)
	side(H, [(2.2, 5.45), (3.6, 5.24), (4.2, 4.98), (4.3, 5.1), (3.66, 5.4), (2.2, 5.62)], 0.36, s * 0.82, DARK, bevel=0.04)
	box(H, (0.3, 0.55, 0.2), (s * 0.78, 1.9, 5.66), FRAME, 0.05)
	# 콧날 양옆의 세로 푸른 띠 (정면: 눈 사이에서 위로 이어지는 Y 자 판)
	box(H, (0.34, 0.16, 2.3), (s * 0.58, 4.86, 4.2), BLUE, 0.07, rot=(16, 0, 0), taper=(1.25, 1.0))
	# 콧날 옆 판 이음 선
	box(H, (0.04, 0.05, 1.45), (s * 0.38, 5.0, 4.25), BLUE_D, 0.0)
# 가운데 짙은 홈 (평면의 검은 줄기) + 카메라
# 머리 윗면 곡선을 따라가는 짙은 띠 (일자 판이면 둥근 앞머리 위로 떠 버린다)
TOP_STRIP = [(1.3, 5.52), (2.6, 5.52), (3.6, 5.32), (4.3, 5.02), (4.42, 5.16), (3.68, 5.48), (2.6, 5.7), (1.3, 5.7)]
side(H, TOP_STRIP, 0.9, 0, DARK, bevel=0.05)
box(H, (0.52, 0.6, 0.3), (0, 3.35, 5.65), FRAME, 0.06)
box(H, (0.34, 0.2, 0.18), (0, 3.62, 5.66), GREY, 0.04)
cyl(H, 0.08, 0.06, (0, 3.73, 5.66), BLACK, rot=(90, 0, 0), verts=12)
# 콧날: 남색 판 + 격자 (정면 가운데)
box(H, (0.68, 0.32, 1.25), (0, 4.95, 4.1), BLUE_D, 0.06)
for k in range(6):
	box(H, (0.42, 0.04, 0.05), (0, 5.12, 3.78 + k * 0.1), DARK, 0.0)
box(H, (0.68, 0.45, 0.75), (0, 4.62, 3.22), BLUE_D, 0.06)
# 콧날 위 짙은 카메라 상자 (정면 가운데 줄기: 격자 → 짙은 상자 → 정수리 카메라)
box(H, (0.92, 0.6, 0.78), (0, 4.42, 5.12), DARK, 0.08)
box(H, (0.5, 0.08, 0.32), (0, 4.74, 5.2), FRAME, 0.03)
cyl(H, 0.1, 0.06, (0, 4.79, 5.2), BLACK, rot=(90, 0, 0), verts=12)
# 아래 얼굴판 (짙은 회색) · 작은 청록 통풍구 둘
hb.deform(side(H, [(1.8, 2.75), (4.3, 2.75), (4.75, 3.15), (4.8, 3.8), (1.8, 3.8)], 3.3, 0, FRAME, bevel=0.12, cuts=4), chin)
for s in (-1, 1):
	cyl(H, 0.24, 0.16, (s * 1.24, 4.8, 3.04), GREY, rot=(90, 0, 0), verts=20, bevel=0.02)
	cyl(H, 0.17, 0.06, (s * 1.24, 4.88, 3.04), TEAL, rot=(90, 0, 0), verts=20)
	for k in range(3):
		box(H, (0.3, 0.04, 0.035), (s * 1.24, 4.92, 3.04 + (k - 1) * 0.09), DARK, 0.0)
# 눈 둘: 짙은 원통 받침 → 회색 테두리 → 청록 유리 돔 → 동공 점 셋
for s in (-1, 1):
	# 원화의 눈은 짙은 소켓에서 튀어나온 둥근 구슬이다 (납작한 원판이 아님)
	ex, ey, ez = s * 1.37, 4.6, 4.07
	cyl(H, 0.64, 0.5, (ex, ey - 0.05, ez), GREY, rot=(90, 0, 0), verts=32, bevel=0.06)
	cyl(H, 0.6, 0.12, (ex, ey + 0.2, ez), DARK, rot=(90, 0, 0), verts=32, bevel=0.03)
	hb.sphere(nm(H), 0.5, (ex, ey + 0.3, ez), mat=EYE, scale=(1, 0.95, 1), seg=32, rings=16, part=H)
	for k in range(3):
		a = 2 * math.pi * k / 3 + math.pi * 0.5
		hb.sphere(nm(H), 0.045, (ex + math.cos(a) * 0.09, ey + 0.77, ez - 0.05 + math.sin(a) * 0.09), mat=DARK, part=H)
	POINTS.append(("pt_eye_" + ("l" if s < 0 else "r"), (ex, ey + 0.8, ez), H))
# 안테나 (오른쪽 +X, 측면 Y 2.2 · 높이 6.65)
cyl(H, 0.16, 0.2, (0.67, 2.2, 5.72), FRAME, verts=16)
cyl(H, 0.11, 0.5, (0.67, 2.2, 6.05), GREY, verts=16)
cyl(H, 0.075, 0.4, (0.67, 2.2, 6.45), GREY_L, verts=12)
cyl(H, 0.09, 0.06, (0.67, 2.2, 6.66), DARK, verts=12)
box(H, (0.14, 0.14, 0.3), (0.84, 2.2, 5.95), FRAME, 0.03)
# 아래 기계 덩어리 (머리 밑 · 다리 받침 사이를 채움)
box(H, (3.2, 2.6, 0.9), (0, 2.6, 3.1), DARK, 0.12)
for s in (-1, 1):
	disc(H, 0.32, 0.18, (s * 1.62, 2.1, 3.0), (s, 0, 0), GREY, bolts=6)
	# 팔 받침 링크 (정면의 Z 2.7 회색 가로 막대)
	box(H, (1.0, 0.3, 0.22), (s * 2.15, 4.25, 2.72), GREY, 0.05)
	cyl(H, 0.14, 0.34, (s * 1.65, 4.25, 2.72), FRAME, verts=12)
	cyl(H, 0.12, 0.34, (s * 2.65, 4.25, 2.72), FRAME, verts=12)
# 개틀링 받침: 턱 밑에서 내려오는 짙은 목 + 회색 원통 집 (정면 개틀링 중심 1.5m · 측면 2.55m → 2.0m)
GZ = ov("GZ", 2.35)
box(H, (0.72, 0.75, 0.9), (0, 4.2, 2.55), FRAME, 0.08)
cyl(H, 0.5, 0.6, (0, 4.3, GZ), GREY, rot=(90, 0, 0), verts=24, bevel=0.03)
cyl(H, 0.4, 0.3, (0, 4.68, GZ), DARK, rot=(90, 0, 0), verts=24)
for k in range(8):
	t = 2 * math.pi * k / 8
	cyl(H, 0.05, 0.62, (math.cos(t) * 0.5, 4.3, GZ + math.sin(t) * 0.5), DARK, rot=(90, 0, 0), verts=8)
POINTS.append(("pt_mouth", (0, 4.98, 3.35), H))
POINTS.append(("pt_searchlight", (0, 3.75, 5.82), H))
at(H, Matrix.Translation((0, 1.2, 4.6)), "body")

G_ = "gatling"
for k in range(6):
	a = 2 * math.pi * k / 6
	cyl(G_, 0.09, 1.9, (math.cos(a) * 0.24, 5.6, GZ + math.sin(a) * 0.24), DARK, rot=(90, 0, 0), verts=10)
	cyl(G_, 0.05, 0.05, (math.cos(a) * 0.24, 6.56, GZ + math.sin(a) * 0.24), BLACK, rot=(90, 0, 0), verts=8)
for y, r, m in ((4.85, 0.42, FRAME), (5.6, 0.38, DARK), (6.4, 0.4, FRAME)):
	cyl(G_, r, 0.16, (0, y, GZ), m, rot=(90, 0, 0), verts=16, bevel=0.02, smooth=False)
cyl(G_, 0.12, 1.8, (0, 5.6, GZ), GREY, rot=(90, 0, 0), verts=12)
POINTS.append(("pt_gatling_muzzle", (0, 6.6, GZ), G_))
at(G_, hb.frame((0, 4.7, GZ), (0, 1, 0)), H)

# ════════════════════════════════════════════════════════════════
#  뒤 몸통 (abdomen) — 측면: 높은 상자 (앞 푸른 장갑 · 뒤 회색 공구 상자 · 아래 검은 하부) · 정면: 넓은 어깨
# ════════════════════════════════════════════════════════════════
A = "abdomen"


def top_k(p):
	"""Shoulder slope seen from the front: the top edge drops toward the sides."""
	if p.z < 5.6:
		return p
	k = 1.0 - 0.7 * max(0.0, min(1.0, (abs(p.x) - 1.0) / 1.6))
	return Vector((p.x, p.y, 5.6 + (p.z - 5.6) * k))


blue = side(A, [(1.15, 4.3), (1.15, 5.8), (0.75, 6.2), (-0.4, 6.55), (-1.15, 6.72), (-1.15, 4.3)], 5.1, 0, BLUE, bevel=0.34, seg=4, cuts=12)
hb.deform(blue, top_k)
# 앞 모서리를 비스듬히 깎는다 (정면의 청록등이 붙는 기울어진 면)
hb.deform(blue, lambda p: Vector((p.x, p.y - 0.6 * max(0.0, abs(p.x) - 1.75) if p.y > 0.4 else p.y, p.z)))
rear = side(A, [(-1.05, 4.45), (-1.05, 6.62), (-1.35, 6.85), (-3.3, 6.85), (-3.56, 6.55), (-3.56, 4.75), (-3.25, 4.45)], 4.9, 0, FRAME,
			bevel=0.3, seg=4, cuts=12)
hb.deform(rear, top_k)
side(A, [(1.1, 3.0), (1.1, 4.45), (-3.35, 4.45), (-3.35, 3.95), (-2.6, 3.0)], 4.7, 0, DARK, bevel=0.14)
for s in (-1, 1):
	for y in (0.3, -0.9, -2.1):
		box(A, (0.04, 0.05, 1.3), (s * 2.36, y, 3.75), BLACK, 0.0, rot=(25, 0, 0))
# 윗면 회색 판 (가운데) · 붉은 경고 삼각 · 이름판 · 카메라 소켓
side(A, [(1.25, 5.8), (0.85, 6.3), (-0.4, 6.66), (-1.1, 6.86), (-1.1, 6.71), (-0.4, 6.51), (0.78, 6.15), (1.1, 5.77)], 2.1, 0, GREY_L, bevel=0.03)
box(A, (2.1, 2.2, 0.1), (0, -2.25, 6.88), GREY_L, 0.04)
hb.prism(nm(A), [(-0.14, 0.0), (0.14, 0.0), (0.0, 0.24)], 0.03, (0, 0.95, 6.08), rot=(-50, 0, 0), mat=RED, part=A, axis="Y")
box(A, (0.55, 0.3, 0.12), (0, 0.3, 6.47), DARK, 0.03)
# 앞면: 가운데 회색 판(정면의 '96' 이름판 · 짙은 소켓) + 양옆 푸른 판을 가르는 비스듬한 이음 선
box(A, (1.9, 0.12, 0.95), (0, 1.22, 5.95), GREY_L, 0.04, taper=(0.9, 1.0))
box(A, (0.62, 0.1, 0.32), (0, 1.3, 5.75), DARK, 0.03)
box(A, (0.32, 0.06, 0.14), (0, 1.36, 5.75), FRAME, 0.0)
for s in (-1, 1):
	box(A, (0.06, 0.06, 1.25), (s * 1.25, 1.18, 5.75), BLUE_D, 0.0, rot=(0, s * 35, 0))
	box(A, (0.06, 0.06, 0.8), (s * 0.95, 1.18, 4.75), BLUE_D, 0.0)
box(A, (0.7, 0.9, 0.3), (0, -1.2, 6.75), DARK, 0.05)
cyl(A, 0.18, 0.12, (0, -1.15, 6.9), GREY, verts=16)
for s in (-1, 1):
	# 앞 모서리 청록 육각등 (정면 ±1.88, 4.97)
	box(A, (0.9, 0.2, 1.05), (s * 1.92, 1.1, 5.0), DARK, 0.08, rot=(0, 0, -s * 20))
	box(A, (0.34, 0.06, 0.46), (s * 1.92, 1.22, 5.0), TEAL, 0.05, rot=(0, s * 12, -s * 20), taper=(0.75, 1.0))
	# 옆 청록 세로등 (측면 Y 0.2)
	box(A, (0.1, 0.42, 0.8), (s * 2.56, 0.2, 4.6), DARK, 0.04)
	box(A, (0.05, 0.16, 0.5), (s * 2.6, 0.2, 4.6), TEAL, 0.03)
	# 옆 회색 판 (앞쪽)
	box(A, (0.06, 0.75, 1.4), (s * 2.57, 0.65, 5.2), GREY_L, 0.03)
	rivets(A, [(s * 2.61, 0.4, 4.7), (s * 2.61, 0.9, 5.7)], (s, 0, 0))
	# 공구 상자: 바깥 푸른 벽 · 검은 칸 · 렌치 둘 + 드라이버 (정면 위로 솟음)
	box(A, (0.8, 2.05, 0.62), (s * 2.25, -1.45, 5.98), BLACK, 0.05)
	box(A, (0.12, 2.1, 0.32), (s * 2.66, -1.45, 5.82), BLUE, 0.04)
	box(A, (0.86, 0.12, 0.62), (s * 2.25, -0.42, 5.98), BLUE, 0.04)
	box(A, (0.9, 2.15, 0.12), (s * 2.25, -1.45, 5.68), BLUE, 0.03)
	for k, (dy, dx, kind, hgt) in enumerate([(-0.85, -0.12, "wrench", 0.8), (-1.45, 0.12, "driver", 0.55), (-2.05, -0.05, "wrench", 0.9)]):
		x = s * 2.2 + s * dx
		y = dy - 0.05
		tilt = s * (8 - 8 * k)
		if kind == "wrench":
			box(A, (0.1, 0.06, hgt), (x, y, 5.95 + hgt / 2), STEEL, 0.02, rot=(0, tilt, 0))
			jaw = [(-0.15, 0.0), (0.15, 0.0), (0.15, 0.22), (0.06, 0.24), (0.05, 0.1), (-0.05, 0.1), (-0.06, 0.24), (-0.15, 0.22)]
			hb.prism(nm(A), jaw, 0.06, (x, y, 5.9 + hgt), rot=(0, tilt, 0), mat=STEEL, part=A, axis="Y", bevel=0.01)
		else:
			cyl(A, 0.04, hgt, (x, y, 5.95 + hgt / 2), STEEL, verts=8)
			cyl(A, 0.08, 0.35, (x, y, 6.05 + hgt), YELLOW, verts=10)
	# 공구 상자 안쪽의 긴 검은 손잡이 (정면 ±1.65 · 높이 7.35)
	box(A, (0.2, 0.22, 1.2), (s * 1.66, -1.2, 6.8), BLACK, 0.08)
	# 회색 반구 받침 (측면 공구 상자 아래)
	hb.sphere(nm(A), 0.36, (s * 2.62, -1.85, 5.1), mat=GREY, scale=(0.6, 1, 1), part=A)
	cyl(A, 0.4, 0.12, (s * 2.58, -1.85, 5.1), FRAME, rot=(0, 90, 0), verts=20)
	# 뒤 상자 옆 통풍 슬릿
	for k in range(6):
		box(A, (0.04, 0.05, 0.6), (s * 2.47, -2.95 - k * 0.09, 5.65), BLACK, 0.0)
	rivets(A, [(s * 2.47, y, z) for y in (-1.3, -3.3) for z in (4.75, 6.4)], (s, 0, 0))
	# 뒤 상자 옆 판 이음 · 앞 푸른 장갑 볼트 (원화 측면의 작은 점들)
	box(A, (0.04, 0.05, 1.8), (s * 2.46, -2.4, 5.6), BLACK, 0.0)
	box(A, (0.04, 2.2, 0.05), (s * 2.46, -2.3, 6.45), BLACK, 0.0)
	rivets(A, [(s * 2.56, y, z) for y, z in ((-0.6, 4.6), (-0.6, 6.0), (0.85, 4.5), (-1.0, 5.3))], (s, 0, 0))
	# 하부 짙은 판 볼트
	rivets(A, [(s * 2.36, y, 3.35) for y in (0.8, -0.3, -1.5, -2.6)], (s, 0, 0), r=0.05)
	# 등 배선 (머리 → 뒤 몸통)
	pipe(A, [(s * 0.55, 1.9, 5.62), (s * 0.6, 1.4, 5.95), (s * 0.55, 1.0, 6.25)], 0.08, BLACK)
# 뒤 해치 (원화에는 안 보이는 뒷면 · 게임용 새끼 해치)
box(A, (1.8, 0.16, 1.2), (0, -3.66, 5.4), GREY, 0.05)
for k in range(4):
	box(A, (0.2, 0.04, 1.0), (-0.6 + k * 0.4, -3.75, 5.4), YELLOW, 0.0, rot=(0, 30, 0))
POINTS.append(("pt_hatch", (0, -3.9, 5.4), A))
for s in (-1, 1):
	cyl(A, 0.2, 0.5, (s * 0.5, -3.3, 3.55), FRAME, rot=(90, 0, 0), r2=0.13, verts=16)
	POINTS.append(("pt_spinneret_" + ("l" if s < 0 else "r"), (s * 0.5, -3.6, 3.55), A))
at(A, Matrix.Translation((0, 1.0, 4.8)), "body")

T = "tablet"
tq = Matrix.Rotation(math.radians(28), 4, "X")
tc = Vector((0, -2.48, 7.52))
box(T, (0.55, 0.4, 0.3), (0, -2.2, 7.0), DARK, 0.05)
box(T, (1.92, 0.24, 1.32), tc, DARK, 0.07, rot=(28, 0, 0))
box(T, (1.6, 0.04, 1.0), tc + tq @ Vector((0, 0.12, 0.02)), SCREEN, 0.0, rot=(28, 0, 0))
for w, x, z in [(0.6, -0.3, 0.3), (0.35, 0.45, 0.32), (0.75, -0.2, 0.08), (0.4, 0.4, -0.05), (0.55, -0.3, -0.25), (0.3, 0.5, -0.3)]:
	box(T, (w, 0.02, 0.05), tc + tq @ Vector((x, 0.145, z)), LINE, 0.0, rot=(28, 0, 0))
at(T, Matrix.Translation((0, -2.2, 6.95)), A)

# ════════════════════════════════════════════════════════════════
#  몸 중심 (body) — 머리와 뒤 몸통 사이 허리 관절 · 아래 받침
# ════════════════════════════════════════════════════════════════
B = "body"
cyl(B, 0.75, 0.9, (0, 1.1, 4.85), FRAME, rot=(90, 0, 0), verts=24, bevel=0.05)
cyl(B, 0.55, 1.1, (0, 1.1, 4.85), DARK, rot=(90, 0, 0), verts=24)
box(B, (3.6, 1.6, 1.1), (0, 0.9, 3.6), DARK, 0.12)
# 배 밑 기계 (원화 정면·측면에서 몸 아래 2.3~3.4m 를 채우는 짙은 덩어리): 허리 아래 매달린 축 뭉치 ·
# 머리 밑 기어 상자 · 팔 팔꿈치 사이의 둥근 마디. 메카닉 관례대로 큰 덩어리 → 원판 → 볼트 순으로 쌓는다.
box(B, (2.2, 1.1, 0.8), (0, 1.9, 2.85), FRAME, 0.2, seg=3)
cyl(B, 0.45, 1.8, (0, 1.9, 2.65), DARK, rot=(0, 90, 0), verts=24, bevel=0.04)
for s in (-1, 1):
	disc(B, 0.38, 0.14, (s * 0.98, 1.9, 2.65), (s, 0, 0), GREY, bolts=6)
	box(B, (0.7, 0.9, 0.8), (s * 1.75, 3.3, 2.75), DARK, 0.22, seg=3)
	disc(B, 0.3, 0.12, (s * 2.12, 3.3, 2.75), (s, 0, 0), GREY, bolts=6)
	cyl(B, 0.32, 0.5, (s * 1.25, 2.6, 2.6), FRAME, rot=(0, 90, 0), verts=20)
	pipe(B, [(s * 0.9, 2.0, 2.4), (s * 1.6, 2.6, 2.3), (s * 2.1, 3.6, 2.5)], 0.07, BLACK)
box(B, (1.5, 1.2, 0.7), (0, 3.2, 2.55), DARK, 0.2, seg=3)
box(B, (1.8, 1.2, 0.5), (0, -1.2, 3.0), FRAME, 0.18, seg=3)
cyl(B, 0.32, 1.6, (0, -1.2, 2.95), DARK, rot=(0, 90, 0), verts=20)

# 원화 측정값에서 출발해 tools/blender/sweep.py 의 실루엣 탐색으로 다듬은 값 (고관절 · 무릎 · 발목 · 발, |X| Y Z)
LEGS = ov("LEGS", {
	# 앞 무릎 Y 는 탐색값(3.75)이 실루엣 점수는 높지만 무릎이 눈을 가려 원화와 달라 보여서, 원화 측면 값 2.75 로 고정
	"f": ((4.1, 2.4, 3.45), (4.55, 2.75, 4.9), (5.99, 3.5, 0.9), (6.09, 3.6, 0.0)),
	"b": ((4.1, -1.9, 3.3), (4.55, -1.9, 4.1), (5.99, -3.85, 0.95), (6.09, -4.2, 0.0)),
})
ROLL = ov("ROLL", (0.714, 0.7))  # 정강이 판 넓은 면이 보는 방향 (|X| 성분, |Y| 성분)


def build_leg(k):
	s = -1 if k[1] == "l" else 1
	hip, knee, ank, foot = (Vector((s * p[0], p[1], p[2])) for p in LEGS[k[0]])
	out = Vector((foot.x - hip.x, foot.y - hip.y, 0)).normalized()
	pre = "leg_" + k
	# 몸 옆 받침: 몸에서 고관절까지 뻗은 짙은 팔 + 윗면 둥근 마디 + 무릎으로 가는 유압 실린더
	base = Vector((s * 2.3, hip.y, 3.9))
	co = pre + "_coxa"
	box(co, (abs(hip.x - base.x) + 0.4, 0.95, 0.95), (base + hip) / 2 + Vector((0, 0, 0.1)), FRAME, 0.15)
	box(co, (0.85, 0.95, 0.7), (s * 3.2, hip.y, 4.5), DARK, 0.2)
	box(co, (0.55, 0.65, 0.16), (s * 3.2, hip.y, 4.9), FRAME, 0.06)
	pa = Vector((s * 3.2, hip.y, 4.7))
	pb = knee + Vector((-s * 0.3, 0, 0.05))
	mid = pa.lerp(pb, 0.55)
	pipe(co, [pa, mid], 0.13, GREY)
	pipe(co, [mid, pb], 0.075, STEEL)
	pipe(co, [base + Vector((0, 0.3, 0.4)), (s * 3.4, hip.y + 0.35, 4.3), hip + Vector((-s * 0.2, 0.35, 0.3))], 0.06, BLACK)
	# 고관절 아래로 매달린 지렛대 + 유압 (원화 측면: 고관절 밑 2.3m 까지 내려온 짙은 브래킷과 회색 마디)
	low = hip + Vector((-s * 0.5, -0.5 if k[0] == "f" else 0.85, -1.05))
	lf = hb.frame(hip, low - hip, (0, 0, 1))
	ll = (low - hip).length
	seg_items = [
		("box", dict(size=(0.5, ll, 0.55), loc=(0, ll / 2, 0), mat=DARK, bevel=0.14, seg=2)),
		("cyl", dict(r=0.26, depth=0.62, loc=(0, ll, 0), rot=(0, 90, 0), mat=GREY, verts=20, bevel=0.03)),
		("cyl", dict(r=0.1, depth=0.7, loc=(0, ll, 0), rot=(0, 90, 0), mat=DARK, verts=12)),
	]
	e = hb.empty("_f_" + co + "_lever")
	e.matrix_world = lf
	for kind, kw in seg_items:
		getattr(hb, kind)(nm(co), part=co, parent=e, **kw)
	pipe(co, [low + Vector((s * 0.1, 0, 0.1)), (base + low) / 2 + Vector((0, 0, -0.1)), base + Vector((s * 0.3, 0, -0.3))], 0.09, GREY)
	at(co, Matrix.Translation(base), B)
	# 넓적다리: 짧고 굵은 짙은 마디 → 무릎 마디(위의 검은 둥근 덩어리) · 고관절 원판(볼트 8)
	fr = hb.frame(hip, knee - hip, out)
	Lf = (knee - hip).length
	nrm = fr.col[0].to_3d()
	seg(pre + "_femur", fr, [
		("box", dict(size=(0.75, Lf + 0.3, 0.85), loc=(0, Lf / 2, 0), mat=FRAME, bevel=0.14, seg=2)),
		("box", dict(size=(1.0, 1.0, 1.05), loc=(0, Lf + 0.1, 0.05), mat=FRAME, bevel=0.28, seg=3)),
		("box", dict(size=(0.7, 0.55, 0.3), loc=(0, Lf + 0.42, 0.25), mat=FRAME, bevel=0.1)),
	], co)
	# 원화는 정면에서도 측면에서도 고관절 원판이 보인다 → 원판 축을 바깥 대각선(앞다리는 앞, 뒷다리는 뒤)으로
	dax = Vector((s * 0.55, 0.83 if k[0] == "f" else -0.83, 0))
	disc(pre + "_femur", 0.5, 0.14, hip + dax * 0.5 + Vector((-s * 0.25, 0, 0.1)), dax, GREY, bolts=8)
	disc(pre + "_femur", 0.4, 0.12, hip - dax * 0.45, -dax, GREY, bolts=6)
	# 정강이: 무릎에서 넓고 발목으로 좁아지는 큰 푸른 판 · 짙은 테두리 프레임 · 바깥 모서리 회색 띠 · 볼트
	# 원화는 정면에서도 측면에서도 판의 넓은 면이 보인다 → 판을 축 둘레로 비틀어 넓은 면이 바깥 대각선(앞다리는 앞·바깥,
	# 뒷다리는 뒤·바깥)을 보게 한다. 로컬 X = 넓은 면의 법선, 로컬 Z = 판의 폭 방향.
	ya = (ank - knee).normalized()
	want = Vector((s * ROLL[0], (ROLL[1] if k[0] == "f" else -ROLL[1]), 0))
	xa = (want - ya * want.dot(ya)).normalized()
	za = xa.cross(ya)
	if za.z < 0:  # 폭 방향의 + 쪽(짙은 테두리)이 위·바깥을 향하게
		xa, za = -xa, -za
	fr = Matrix((xa, ya, za)).transposed().to_4x4()
	fr.translation = knee
	Lt = (ank - knee).length
	seg(pre + "_tibia", fr, [
		("box", dict(size=(0.56, Lt * 0.95, 1.82), loc=(0, Lt * 0.5, 0.0), mat=FRAME, bevel=0.2, seg=3, taper=(1.0, 0.8), taper_axis="Y")),
		("box", dict(size=(0.8, Lt * 0.8, 1.45), loc=(0, Lt * 0.5, -0.1), mat=BLUE, bevel=0.2, seg=3, taper=(0.95, 0.8), taper_axis="Y")),
		("box", dict(size=(0.86, Lt * 0.24, 0.75), loc=(0, Lt * 0.24, -0.45), mat=BLUE_D, bevel=0.08, taper=(1, 0.8), taper_axis="Y")),
		("box", dict(size=(0.3, Lt * 0.62, 0.07), loc=(0, Lt * 0.5, 0.86), mat=GREY, bevel=0.03)),
		("box", dict(size=(0.86, 0.78, 0.9), loc=(0, 0.05, 0.05), mat=FRAME, bevel=0.26, seg=3)),
		("box", dict(size=(0.6, 0.5, 0.16), loc=(0, 0.02, 0.5), mat=FRAME, bevel=0.06)),
		("box", dict(size=(0.92, 0.7, 1.45), loc=(0, Lt - 0.12, 0.0), mat=FRAME, bevel=0.22, seg=2)),
		("cyl", dict(r=0.06, depth=0.86, loc=(0, Lt * 0.38, 0.1), rot=(0, 90, 0), mat=DARK, verts=8)),
		("cyl", dict(r=0.06, depth=0.86, loc=(0, Lt * 0.74, 0.05), rot=(0, 90, 0), mat=DARK, verts=8)),
		# 판 이음 선 (원화 정강이의 비스듬한 칸 나눔) · 무릎 쪽 볼트 줄
		("box", dict(size=(0.84, 0.05, 1.0), loc=(0, Lt * 0.36, -0.2), rot=(0, 0, 0), mat=BLUE_D)),
		("box", dict(size=(0.84, Lt * 0.3, 0.04), loc=(0, Lt * 0.2, 0.18), mat=BLUE_D)),
		("cyl", dict(r=0.045, depth=0.84, loc=(0, Lt * 0.12, 0.45), rot=(0, 90, 0), mat=DARK, verts=8)),
		("cyl", dict(r=0.045, depth=0.84, loc=(0, Lt * 0.12, -0.45), rot=(0, 90, 0), mat=DARK, verts=8)),
		("cyl", dict(r=0.045, depth=0.84, loc=(0, Lt * 0.88, 0.3), rot=(0, 90, 0), mat=DARK, verts=8)),
	], pre + "_femur")
	# 발목 원판 · 발굽 (짙은 회색 몸통 · 검은 밑창 · 바깥쪽 굴림 바퀴)
	z = Vector((0, 0, 1))
	x = out.cross(z)
	ff = Matrix((x, out, z)).transposed().to_4x4()
	ff.translation = ank
	seg(pre + "_foot", ff, [
		("cyl", dict(r=0.32, depth=0.95, loc=(0, 0, 0), rot=(0, 90, 0), mat=FRAME, verts=20, bevel=0.03)),
		("box", dict(size=(1.25, 1.55, 0.8), loc=(0, 0.05, -0.42), mat=FRAME, bevel=0.24, seg=3, taper=(0.85, 0.8))),
		("box", dict(size=(1.32, 1.65, 0.26), loc=(0, 0.05, -0.78), mat=DARK, bevel=0.1)),
		("box", dict(size=(0.75, 0.6, 0.18), loc=(0, -0.2, -0.05), mat=DARK, bevel=0.06)),
		("cyl", dict(r=0.33, depth=0.32, loc=(0.5, 0.62, -0.58), rot=(0, 90, 0), mat=DARK, verts=20)),
		("cyl", dict(r=0.33, depth=0.32, loc=(-0.5, 0.62, -0.58), rot=(0, 90, 0), mat=DARK, verts=20)),
		("cyl", dict(r=0.13, depth=1.25, loc=(0, 0.62, -0.58), rot=(0, 90, 0), mat=GREY, verts=12)),
	], pre + "_tibia")
	POINTS.append(("pt_foot_" + k, (foot.x, foot.y, 0.0), pre + "_foot"))


for k in ("fl", "fr", "bl", "br"):
	build_leg(k)


# ════════════════════════════════════════════════════════════════
#  공구 팔 — 오른쪽 용접기 · 왼쪽 집게손 + 원형 톱
# ════════════════════════════════════════════════════════════════
def arm(kind, sh, el, wr, tip):
	sh, el, wr, tip = Vector(sh), Vector(el), Vector(wr), Vector(tip)
	s = 1 if sh.x > 0 else -1
	pre = "arm_" + kind
	outv = Vector((s, 0, 0))
	# 어깨 마디 (몸 쪽 짙은 둥근 덩어리 · 정면 ±3.2, 4.8)
	box(B, (0.75, 0.8, 0.75), sh + Vector((-s * 0.1, -0.1, 0.1)), DARK, 0.22, seg=3)
	L1 = (el - sh).length
	seg(pre + "_upper", hb.frame(sh, el - sh, outv), [
		("cyl", dict(r=0.2, depth=L1, loc=(0, L1 / 2, 0), rot=(90, 0, 0), mat=FRAME, verts=16)),
		("box", dict(size=(0.72, L1 * 0.82, 0.74), loc=(0, L1 * 0.5, 0.1), mat=BLUE, bevel=0.14, seg=2, taper=(0.85, 0.85), taper_axis="Y")),
		("box", dict(size=(0.24, L1 * 0.4, 0.06), loc=(0, L1 * 0.5, 0.46), mat=GREY, bevel=0.02)),
		("cyl", dict(r=0.3, depth=0.5, loc=(0, L1, 0), rot=(0, 90, 0), mat=GREY, verts=20, bevel=0.03)),
		("cyl", dict(r=0.12, depth=0.56, loc=(0, L1, 0), rot=(0, 90, 0), mat=DARK, verts=12)),
	], B)
	L2 = (wr - el).length
	items = [
		("cyl", dict(r=0.17, depth=L2, loc=(0, L2 / 2, 0), rot=(90, 0, 0), r2=0.14, mat=GREY, verts=16)),
		("box", dict(size=(0.5, L2 * 0.62, 0.52), loc=(0, L2 * 0.42, 0.05), mat=BLUE, bevel=0.1, taper=(0.85, 0.85), taper_axis="Y")),
		("cyl", dict(r=0.21, depth=0.16, loc=(0, L2 * 0.88, 0), rot=(90, 0, 0), mat=DARK, verts=16)),
		("cyl", dict(r=0.21, depth=0.16, loc=(0, L2 * 0.12, 0), rot=(90, 0, 0), mat=DARK, verts=16)),
	]
	if kind == "saw":  # 측면 아래팔의 점 여섯
		for i in range(6):
			items.append(("cyl", dict(r=0.035, depth=0.03, loc=((i % 2 - 0.5) * 0.14, L2 * (0.3 + 0.08 * (i // 2)), 0.26), mat=DARK, verts=8)))
	seg(pre + "_fore", hb.frame(el, wr - el, outv), items, pre + "_upper")
	tool = pre + "_tool"
	L3 = (tip - wr).length
	if kind == "welder":
		items = [
			("cyl", dict(r=0.26, depth=0.34, loc=(0, 0.1, 0), rot=(90, 0, 0), mat=GREY, verts=16)),
			("box", dict(size=(0.75, 0.1, 0.65), loc=(0, 0.38, 0.05), mat=GREY_L, bevel=0.03, taper=(0.8, 1.0))),
			("cyl", dict(r=0.19, depth=L3 * 0.45, loc=(0, L3 * 0.42, 0), rot=(90, 0, 0), r2=0.15, mat=BLUE, verts=16)),
			("cyl", dict(r=0.08, depth=0.14, loc=(0, L3 * 0.7, 0), rot=(90, 0, 0), mat=BRASS, verts=12)),
			("cyl", dict(r=0.07, depth=L3 * 0.26, loc=(0, L3 * 0.86, 0), rot=(90, 0, 0), r2=0.015, mat=BLUE, verts=12)),
			# 정면의 큰 고리 배선 (손목에서 아래로 늘어졌다가 팔로 돌아감)
			("tube", dict(pts=[(-0.12, 0.2, -0.1), (-0.3, -0.2, -0.9), (-0.25, -0.9, -1.0), (-0.1, -1.5, -0.4)], r=0.06, mat=BLACK)),
			("tube", dict(pts=[(0.12, 0.2, 0.1), (0.45, -0.3, 0.2), (0.35, -1.2, 0.3)], r=0.05, mat=BLACK)),
		]
		POINTS.append(("pt_torch", tuple(tip), tool))
	else:
		items = [
			("box", dict(size=(0.45, 0.45, 0.42), loc=(0, 0.12, 0), mat=FRAME, bevel=0.1)),
			("box", dict(size=(0.2, 0.75, 0.3), loc=(-s * 0.15, 0.45, -0.25), mat=GREY, bevel=0.05)),
			("tube", dict(pts=[(0.0, 0.0, 0.15), (0.35, -0.5, 0.3), (0.3, -1.2, 0.2)], r=0.05, mat=BLACK)),
		]
		# 집게손: 원화 정면의 큰 검은 손가락 넷 (톱을 쥔 손)
		for i in range(4):
			a = (i - 1.5) * 0.45
			bx = Vector((math.sin(a) * 0.24, 0.5, math.cos(a) * 0.16))
			items.append(("box", dict(size=(0.17, 0.5, 0.17), loc=tuple(bx + Vector((0, 0.2, 0))), rot=(30, 0, math.degrees(a) * 0.5), mat=BLACK, bevel=0.05)))
			items.append(("box", dict(size=(0.14, 0.36, 0.14), loc=tuple(bx + Vector((0, 0.52, -0.17))), rot=(-25, 0, math.degrees(a) * 0.5), mat=DARK, bevel=0.04)))
	seg(tool, hb.frame(wr, tip - wr, outv), items, pre + "_fore")
	if kind == "saw":
		ditems = [
			("cyl", dict(r=0.74, depth=0.05, loc=(0, 0, 0), rot=(0, 90, 0), mat=STEEL, verts=48, smooth=False)),
			("cyl", dict(r=0.2, depth=0.16, loc=(0, 0, 0), rot=(0, 90, 0), mat=GREY, verts=16)),
			("cyl", dict(r=0.08, depth=0.22, loc=(0, 0, 0), rot=(0, 90, 0), mat=RED, verts=10)),
		]
		for i in range(24):
			t = 2 * math.pi * i / 24
			ditems.append(("prism", dict(points=[(0.0, 0.0), (0.14, 0.0), (0.0, 0.11)], depth=0.05,
										  loc=(0, math.cos(t) * 0.72, math.sin(t) * 0.72), rot=(math.degrees(t) + 90, 0, 0), mat=STEEL)))
		for i in range(8):
			t = 2 * math.pi * i / 8
			ditems.append(("cyl", dict(r=0.05, depth=0.07, loc=(0, math.cos(t) * 0.4, math.sin(t) * 0.4), rot=(0, 90, 0), mat=GREY, verts=8)))
		# 원화는 정면·측면 모두 톱날 면이 보인다 → 날의 축을 X 와 Y 사이 45° 로 둔다 (원판 로컬 X = 회전축)
		ax = Vector((s * 0.7071, 0.7071, 0))
		dfr = Matrix((ax, Vector((0, 0, 1)).cross(ax), Vector((0, 0, 1)))).transposed().to_4x4()
		dfr.translation = tip
		seg("arm_saw_disc", dfr, ditems, tool)


# 정면: 어깨(±3.2, 4.85)에서 거의 수직으로 내려오는 큰 위팔 · 측면: 눈 밑에서 앞으로 뻗음 → 앞·아래 대각선으로 절충
arm("welder", *ov("ARM_W", ((3.0, 4.0, 3.95), (3.15, 5.725, 3.725), (3.4, 6.8, 2.9), (3.55, 7.7, 1.25))))
arm("saw", *ov("ARM_S", ((-2.9, 4.0, 3.6), (-2.8, 4.6, 2.35), (-2.85, 5.05, 1.6), (-3.45, 5.5, 0.98))))
at(B, Matrix.Translation((0, 1.1, 4.85)), None)


# 덩어리 비율 보정 (sweep.py 가 찾은 값): 그룹 → (sx, sy, sz, dx, dy, dz). 배율은 그 파츠 원점 기준,
# head / abdomen / body 는 월드 축, tibia / foot 는 마디 로컬 축(x = 판 두께, z = 판 폭)으로 적용한다.
GROUPS = {
	"head": ["head", "gatling"], "abdomen": ["abdomen", "tablet"], "body": ["body"],
	"tibia": ["leg_%s_tibia" % k for k in ("fl", "fr", "bl", "br")], "foot": ["leg_%s_foot" % k for k in ("fl", "fr", "bl", "br")],
}
PART_T = ov("PART_T", {
	"head": (1.15, 1.0, 1.05, 0.0, 0.0, -0.1), "abdomen": (1.05, 1.0, 1.0, 0.0, 0.1, 0.0),
	# 발굽은 발목 기준으로 줄어들어 바닥에서 뜨므로 그만큼(발목 높이 0.9 × 0.16) 내린다
	"tibia": (1.1, 1.0, 1.0, 0.0, 0.0, 0.0), "foot": (0.84, 0.84, 0.84, 0.0, 0.0, -0.148),
})


def _reshape():
	for g, t in PART_T.items():
		sx, sy, sz, dx, dy, dz = t
		lead = FRAMES[GROUPS[g][0]]
		for part in GROUPS[g]:
			f = FRAMES[part] if g in ("tibia", "foot") else lead
			if g in ("tibia", "foot"):  # 마디 로컬 축
				m = Matrix.Translation(f.to_3x3() @ Vector((dx, dy, dz))) @ f @ Matrix.Diagonal((sx, sy, sz, 1)) @ f.inverted()
			else:  # 그룹 첫 파츠 원점 기준, 월드 축
				c = f.translation.copy()
				m = Matrix.Translation(c + Vector((dx, dy, dz))) @ Matrix.Diagonal((sx, sy, sz, 1)) @ Matrix.Translation(-c)
			hb.get(part).matrix_world = m @ hb.get(part).matrix_world
			fr = FRAMES[part].copy()
			fr.translation = m @ fr.translation
			FRAMES[part] = fr
			for i, (name, p, parent) in enumerate(POINTS):
				if parent == part:
					POINTS[i] = (name, tuple(m @ Vector(p)), parent)


def after_join():
	_reshape()
	for part, m in FRAMES.items():
		hb.rebase(hb.get(part), m)
	for part, parent in PARENT.items():
		if parent:
			hb.attach(hb.get(part), hb.get(parent))
	for o in [o for o in bpy.data.objects if o.name.startswith("_f_")]:
		bpy.data.objects.remove(o, do_unlink=True)
	for name, p, parent in POINTS:
		hb.empty(name, p, parent=hb.get(parent))
