# LANCASTER — 버려진 시설의 광폭화된 보안 로봇 (보스). 사용자가 Tripo 로 만든 모델을 관절 단위로 나눈 것.
# 원본: models/source/lancaster_tripo/original.glb ("mech+robot+3d+model.glb", 파츠 94개 · 9,122 삼각형 · 파츠별 베이스컬러 94장)
# 빌드:  tools\blender.ps1 model models\src\lancaster.py   (텍스처 확인은 --engine=eevee)
#
# 원칙: 원본 외형(부피·표면·텍스처)은 그대로 둔다. 하는 일은
#  ① 정면을 +Y 로 돌림(원본 정면은 -Y) · 플레이어 메카(1.80m)의 두 배 높이 3.6m 로 균일 확대(SCALE)
#  ② 파츠별 텍스처 94장 → 2048 아틀라스 1장 · 재질 1개 (UV 는 타일 위치로 옮길 뿐 다시 펴지 않음)
#  ③ 관절 단위로 묶기 — 원본이 이미 관절마다 조각나 있어 자르기는 없다 (상체 · 하체 분리 포함)
#  ④ 위 청록 표시등 면을 그대로 떼어 lights 로 · 가슴 얼굴의 청록 눈 세 점(텍스처)은 자리만 재서 pt_eye_1~3 (게임에서 발광 덮개 · 광폭화 때 붉게)
#  ⑤ 관절 피벗 · 계층 · 부착점
#
# 파츠 계층 (회전 0, 원점 = 관절) — LancasterRig 계약. 왼쪽 = 개틀링 팔(-X), 오른쪽 = 집게 팔(+X):
#   pelvis (골반 · 허리 띠, 원점 = 양 고관절 높이 가운데)
#     ├ thigh_l / thigh_r (원점 = 고관절) > shin_* (무릎 구슬 포함, 원점 = 무릎) > foot_* (발목 구슬 포함, 원점 = 발목)
#     └ torso (가슴 · 등 탱크 · 배관, 원점 = 허리)  ← 상체. 하체와 따로 돈다
#          ├ lights (청록 표시등 면) · vent_l / vent_r (가슴 주황 통풍구) · pod_l / pod_r (어깨 위 보안 포드, 원점 = 받침)
#          ├ shoulder_l > upperarm_l > forearm_l (팔꿈치 구슬 · 총 몸통 · 탄창 드럼) > barrel_l (총열 둘, 원점 = 총열 뒤 축)
#          └ shoulder_r > upperarm_r > forearm_r (팔꿈치 · 전완) > hand_r (손목 · 가시) > claw_a (갈고리) / claw_b (엄지)
#   부착점: pt_muzzle (총열 앞 축 위, barrel_l 아래 — 원점→pt_muzzle 이 총열 축) · pt_eject (탄피 배출구, forearm_l)
#           pt_claw (집게 사이, hand_r) · pt_spike (가시 끝, hand_r) · pt_jet_l/r (등 탱크 뒤, torso) · pt_vent_l/r (위 탱크 꼭대기)
#           pt_eye_1~3 (가슴 얼굴 눈 세 점, torso) · pt_lens_l/r (포드 렌즈) · pt_foot_l/r (발바닥 가운데, foot) · pt_chest (가슴 앞)

import os

import bmesh
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "models", "source", "lancaster_tripo", "original.glb")
OUT = os.path.join(ROOT, "output", "models", "lancaster")
ATLAS = 2048
SRC_H = 0.788
TARGET_H = 3.6        # 플레이어 메카 1.80m × 2
SCALE = TARGET_H / SRC_H

# 원본 파츠 번호 → 관절. 원본 -X 쪽 파츠가 돌린 뒤 +X(오른쪽) 이 된다.
GROUPS = {
	"pelvis": [30, 61, 62, 20, 80],
	"torso": [0, 26, 12, 28, 54, 22, 23, 65, 66, 9, 15],
	"vent_l": [43, 36, 91], "vent_r": [42, 35, 92],
	"pod_l": [45, 55, 69, 90], "pod_r": [50, 31, 63],
	"shoulder_l": [16, 14, 4, 18], "upperarm_l": [48, 37, 77],
	"forearm_l": [7, 47, 86, 87, 39, 11, 68, 83, 34, 44], "barrel_l": [5, 29],
	"shoulder_r": [17, 41, 2, 19], "upperarm_r": [38], "forearm_r": [8, 51],
	"hand_r": [3, 40, 52, 81, 85, 70], "claw_a": [25], "claw_b": [57],
	"thigh_l": [1, 64], "shin_l": [33, 27, 56, 59], "foot_l": [46, 21, 67, 73, 84, 71, 79, 72, 89],
	"thigh_r": [6, 60], "shin_r": [32, 10, 53, 58], "foot_r": [49, 24, 74, 78, 88, 82, 75, 76, 93, 13],
}
_all = sorted(i for ids in GROUPS.values() for i in ids)
assert _all == list(range(94)), [i for i in range(94) if i not in _all] + ["dup"] + [i for i in _all if _all.count(i) > 1]

# ════════════════════════════════════════════════════════════════
#  불러오기 · 정면 돌리기 · 확대
# ════════════════════════════════════════════════════════════════
bpy.ops.import_scene.gltf(filepath=SRC)
TURN = Matrix.Scale(SCALE, 4) @ Matrix.Rotation(math.pi, 4, "Z")
parts = {}
for o in list(bpy.data.objects):
	if o.type == "MESH" and o.name.startswith("tripo_part_"):
		mw = o.matrix_world.copy()
		o.parent = None
		o.data.transform(TURN @ mw)
		o.matrix_world = Matrix.Identity(4)
		parts[int(o.name.rsplit("_", 1)[1])] = o
for o in list(bpy.data.objects):
	if o.type == "EMPTY":
		bpy.data.objects.remove(o, do_unlink=True)
assert sorted(parts) == list(range(94)), sorted(parts)


def wverts(o):
	return np.array([(o.matrix_world @ v.co)[:] for v in o.data.vertices])


def pbox(ids):
	V = np.vstack([wverts(parts[i]) for i in ids])
	return V.min(0), V.max(0), V


def pc(ids):
	lo, hi, _ = pbox(ids)
	return (lo + hi) / 2


# 묶기 전에 원본 파츠로 관절 자리를 잰다 (돌린 뒤 좌표: +Y 앞 · +X 오른쪽)
J = {}
for side, thigh, ball, knee, ankle in (("l", [1], [62], [33], [46, 21]), ("r", [6], [61], [32], [49, 24])):
	tc = pc(thigh)
	bc = pc(ball)
	J["hip_" + side] = np.array([tc[0], tc[1], bc[2]])
	J["knee_" + side] = pc(knee)
	J["ankle_" + side] = pc(ankle)
J["pelvis"] = np.array([0.0, (J["hip_l"][1] + J["hip_r"][1]) / 2, (J["hip_l"][2] + J["hip_r"][2]) / 2])
_w = pbox([20])
J["waist"] = np.array([0.0, (_w[0][1] + _w[1][1]) / 2, _w[1][2]])
for side, shell, sock in (("l", [14], [16]), ("r", [41], [17])):
	a = pc(shell)
	b = pc(sock)
	J["shoulder_" + side] = np.array([a[0], (a[1] + b[1]) / 2, (a[2] + b[2]) / 2])
J["elbow_l"] = pc([7])
J["elbow_r"] = pc([8])
J["wrist_r"] = pc([3, 40, 52])
J["claw_a"] = pc([85])
J["claw_b"] = pc([81])
for side, ids in (("l", [45, 55, 69, 90]), ("r", [50, 31, 63])):
	lo, hi, _ = pbox(ids)
	J["pod_" + side] = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]])
	J["lens_" + side] = np.array([(lo[0] + hi[0]) / 2, hi[1], (lo[2] + hi[2]) / 2])
# 총열 축: 두 총열 정점의 주성분
_, _, BV = pbox([5, 29])
_c = BV.mean(0)
_u, _s, _vt = np.linalg.svd(BV - _c)
_ax = _vt[0] if _vt[0][1] > 0 else -_vt[0]       # 앞(+Y) 쪽
_proj = (BV - _c) @ _ax
J["barrel_rear"] = _c + _ax * _proj.min()
J["muzzle"] = _c + _ax * (_proj.max() + 0.02)
# 탄피 배출구: 총 몸통(39) 바깥(-X) 옆면 가운데
_lo, _hi, _ = pbox([39])
J["eject"] = np.array([_lo[0] - 0.02, (_lo[1] + _hi[1]) / 2, (_lo[2] + _hi[2]) / 2 + 0.05])
# 집게: 갈고리(25) · 엄지(57) 아래 끝 사이 / 가시(70) 끝
_, _, V25 = pbox([25])
_, _, V57 = pbox([57])
J["claw"] = (V25[V25[:, 2].argmin()] + V57[V57[:, 2].argmin()]) / 2
_, _, V70 = pbox([70])
J["spike"] = V70[V70[:, 2].argmin()]
# 등 탱크(9 = 오른쪽, 15 = 왼쪽) 뒤 · 위 회색 탱크(23 = 오른쪽, 22 = 왼쪽) 꼭대기
for side, back, top in (("l", [15], [22]), ("r", [9], [23])):
	lo, hi, _ = pbox(back)
	J["jet_" + side] = np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2 - 0.1])
	lo, hi, _ = pbox(top)
	J["vent_" + side] = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, hi[2]])
_lo, _hi, _ = pbox([0])
J["chest"] = np.array([0.0, _hi[1], (_lo[2] + _hi[2]) / 2])
for k in ("l", "r"):
	J["foot_" + k] = np.array([J["ankle_" + k][0], J["ankle_" + k][1] + 0.12, 0.0])
for k, v in J.items():
	if v is not None:
		print("J %-12s %s" % (k, np.round(v, 3)))

# ════════════════════════════════════════════════════════════════
#  아틀라스: 파츠 텍스처(전부 2의 거듭제곱 정사각형)를 사분 트리로 빈틈없이 채운다
# ════════════════════════════════════════════════════════════════
def _src_image(o):
	for nd in o.data.materials[0].node_tree.nodes:
		if nd.type == "TEX_IMAGE":
			return nd.image
	raise RuntimeError("no texture on " + o.name)


atlas = np.zeros((ATLAS, ATLAS, 4), dtype=np.float32)
atlas[..., 3] = 1.0
free = [(0, 0, ATLAS)]
order = sorted(parts, key=lambda i: -_src_image(parts[i]).size[0])
for i in order:
	o = parts[i]
	im = _src_image(o)
	s = im.size[0]
	assert im.size[1] == s and s & (s - 1) == 0, (o.name, im.size[:])
	free.sort(key=lambda f: f[2])
	slot = next(f for f in free if f[2] >= s)
	free.remove(slot)
	x, y, sz = slot
	while sz > s:
		sz //= 2
		free += [(x + sz, y, sz), (x, y + sz, sz), (x + sz, y + sz, sz)]
	px = np.empty(s * s * 4, dtype=np.float32)
	im.pixels.foreach_get(px)
	atlas[y:y + s, x:x + s] = px.reshape(s, s, 4)
	uv = o.data.uv_layers[0].data
	co = np.empty(len(uv) * 2, dtype=np.float32)
	uv.foreach_get("uv", co)
	co = co.reshape(-1, 2)
	# 반 텍셀 안쪽으로 묶어 이웃 타일이 번지지 않게
	co = (np.array([x, y]) + 0.5 + np.clip(co, 0.0, 1.0) * (s - 1.0)) / ATLAS
	uv.foreach_set("uv", co.ravel())

os.makedirs(OUT, exist_ok=True)
atlas_img = bpy.data.images.new("lancaster_atlas", ATLAS, ATLAS, alpha=False)
atlas_img.pixels.foreach_set(atlas.ravel())
atlas_img.filepath_raw = os.path.join(OUT, "lancaster_atlas.png")
atlas_img.file_format = "PNG"
atlas_img.save()
atlas_img.pack()

MAT = bpy.data.materials.new("lancaster")
if MAT.node_tree is None:
	MAT.use_nodes = True
_nodes = MAT.node_tree.nodes
_bsdf = next(nd for nd in _nodes if nd.type == "BSDF_PRINCIPLED")
_tex = _nodes.new("ShaderNodeTexImage")
_tex.image = atlas_img
MAT.node_tree.links.new(_tex.outputs["Color"], _bsdf.inputs["Base Color"])
_bsdf.inputs["Roughness"].default_value = 0.66      # 0.42~0.58 이면 BrawlLook 이 배경으로 분류한다
_bsdf.inputs["Metallic"].default_value = 0.0
for o in parts.values():
	o.data.materials.clear()
	o.data.materials.append(MAT)
for im in list(bpy.data.images):
	if im is not atlas_img:
		bpy.data.images.remove(im)
for m in list(bpy.data.materials):
	if m is not MAT:
		bpy.data.materials.remove(m)


def atlas_rgb(u, v):
	return atlas[min(ATLAS - 1, int(v * ATLAS)), min(ATLAS - 1, int(u * ATLAS)), :3]


def is_cyan(rgb):
	r, g, b = rgb
	return g > 0.35 and b > 0.3 and g > r + 0.2 and b > r + 0.15


# ════════════════════════════════════════════════════════════════
#  묶기 · 발광부 떼기
# ════════════════════════════════════════════════════════════════
def group(name, ids):
	o = hb.join([parts[i] for i in ids], name)
	o.matrix_world = Matrix.Identity(4)
	return o


def split_glow(o, name):
	"""청록 발광 면을 그대로 떼어 name 으로. 떼어낸 자리는 같은 면이 덮으므로 막지 않는다."""
	uv = o.data.uv_layers[0].data
	sel = set()
	for p in o.data.polygons:
		u = np.mean([uv[li].uv[:] for li in p.loop_indices], 0)
		if is_cyan(atlas_rgb(*u)):
			sel.add(p.index)
	g = o.copy()
	g.data = o.data.copy()
	g.name = g.data.name = name
	hb.collection().objects.link(g)
	for obj, keep in ((g, True), (o, False)):
		bm = bmesh.new()
		bm.from_mesh(obj.data)
		bm.faces.ensure_lookup_table()
		kill = [f for f in bm.faces if (f.index in sel) != keep]
		bmesh.ops.delete(bm, geom=kill, context="FACES")
		bm.to_mesh(obj.data)
		bm.free()
		obj.data.update()
	print("%s: %d glow faces" % (name, len(sel)))
	return g


G = {k: group(k, ids) for k, ids in GROUPS.items()}
G["lights"] = split_glow(G["torso"], "lights")


def find_eyes(o):
	"""가슴 얼굴의 청록 눈 세 개는 큰 면 위의 텍스처 점이라 떼어낼 면이 없다 → 면 위를 촘촘히 찍어 청록 자리를 모아 셋으로 묶는다"""
	me = o.data
	me.calc_loop_triangles()
	uv = me.uv_layers[0].data
	pts = []
	for tri in me.loop_triangles:
		P = [Vector(me.vertices[v].co) for v in tri.vertices]
		if min(p.y for p in P) < 0.0 or min(p.z for p in P) < 1.9:
			continue                      # 앞면 위쪽만
		U = [Vector(uv[li].uv) for li in tri.loops]
		n = 14
		for a in range(n + 1):
			for b in range(n + 1 - a):
				w = (a / n, b / n, 1.0 - (a + b) / n)
				u = U[0] * w[0] + U[1] * w[1] + U[2] * w[2]
				if is_cyan(atlas_rgb(u.x, u.y)):
					pts.append(np.array(P[0] * w[0] + P[1] * w[1] + P[2] * w[2]))
	pts = np.array(pts)
	assert len(pts) >= 3, len(pts)
	# x 로 정렬해 세 덩이 초기값 → k-means 몇 번
	cs = pts[np.argsort(pts[:, 0])][[0, len(pts) // 2, -1]].copy()
	for _ in range(12):
		lab = np.argmin(((pts[:, None, :] - cs[None]) ** 2).sum(-1), 1)
		cs = np.array([pts[lab == k].mean(0) if (lab == k).any() else cs[k] for k in range(3)])
	print("eye samples", len(pts), "centers", np.round(cs, 3))
	return cs


EYES = find_eyes(G["torso"])


# ════════════════════════════════════════════════════════════════
#  피벗 · 계층 · 부착점
# ════════════════════════════════════════════════════════════════
def after_join():
	piv = {
		"pelvis": J["pelvis"], "torso": J["waist"], "lights": J["waist"],
		"vent_l": None, "vent_r": None,
		"pod_l": J["pod_l"], "pod_r": J["pod_r"],
		"shoulder_l": J["shoulder_l"], "upperarm_l": J["shoulder_l"], "forearm_l": J["elbow_l"], "barrel_l": J["barrel_rear"],
		"shoulder_r": J["shoulder_r"], "upperarm_r": J["shoulder_r"], "forearm_r": J["elbow_r"], "hand_r": J["wrist_r"],
		"claw_a": J["claw_a"], "claw_b": J["claw_b"],
		"thigh_l": J["hip_l"], "shin_l": J["knee_l"], "foot_l": J["ankle_l"],
		"thigh_r": J["hip_r"], "shin_r": J["knee_r"], "foot_r": J["ankle_r"],
	}
	for k in ("vent_l", "vent_r"):
		V = wverts(hb.get(k))
		piv[k] = (V.min(0) + V.max(0)) / 2
	for k, p in piv.items():
		hb.rebase(hb.get(k), Matrix.Translation(Vector(tuple(float(x) for x in p))))
	parent = {
		"torso": "pelvis", "lights": "torso", "vent_l": "torso", "vent_r": "torso", "pod_l": "torso", "pod_r": "torso",
		"shoulder_l": "torso", "upperarm_l": "shoulder_l", "forearm_l": "upperarm_l", "barrel_l": "forearm_l",
		"shoulder_r": "torso", "upperarm_r": "shoulder_r", "forearm_r": "upperarm_r", "hand_r": "forearm_r",
		"claw_a": "hand_r", "claw_b": "hand_r",
		"thigh_l": "pelvis", "shin_l": "thigh_l", "foot_l": "shin_l",
		"thigh_r": "pelvis", "shin_r": "thigh_r", "foot_r": "shin_r",
	}
	for k, p in parent.items():
		hb.attach(hb.get(k), hb.get(p))

	def pt(name, at, par):
		hb.empty(name, tuple(float(x) for x in at), parent=hb.get(par), size=0.12)

	pt("pt_muzzle", J["muzzle"], "barrel_l")
	pt("pt_eject", J["eject"], "forearm_l")
	pt("pt_claw", J["claw"], "hand_r")
	pt("pt_spike", J["spike"], "hand_r")
	for s in ("l", "r"):
		pt("pt_jet_" + s, J["jet_" + s], "torso")
		pt("pt_vent_" + s, J["vent_" + s], "torso")
		pt("pt_lens_" + s, J["lens_" + s], "pod_" + s)
		pt("pt_foot_" + s, J["foot_" + s], "foot_" + s)
	for i, e in enumerate(EYES):
		pt("pt_eye_%d" % (i + 1), e, "torso")
	pt("pt_chest", J["chest"], "torso")
