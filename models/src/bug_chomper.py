# 벌레형 괴생명체 ③ 촘퍼 (CHOMPER) — 튜토리얼에 나오는 하찮은 우주 벌레. v2: 사용자가 Tripo 로 만든 모델을 관절 단위로 나눈 것.
# 원본: models/source/chomper_tripo/original.glb ("cartoon shell creature 3d model.glb", 파츠 28개 · 1.06만 삼각형 · 파츠별 베이스컬러 28장)
# 빌드:  tools\blender.ps1 model models\src\bug_chomper.py   (텍스처 확인은 --engine=eevee)
# 이전 v1(스크립트로 직접 깎은 모델)은 output/models/bug_chomper_v1/ 에 보존.
#
# 원칙: 원본 외형(부피·표면·텍스처)은 그대로 둔다. 하는 일은
#  ① 정면을 +Y 로 돌림(원본은 입이 -Y) ② 파츠별 텍스처 28장 → 2048 아틀라스 1장 · 재질 1개(UV 는 타일 위치로 옮길 뿐 다시 펴지 않음)
#  ③ 관절 단위로 묶고 자르기: 몸통에서 아랫입술(턱)을 평면으로 떼고, 다리는 주황 마디/갈색 발톱 경계에서 자름 (잘린 면은 막음)
#  ④ 발끝이 바닥에 닿게 다리를 고관절 기준으로 몇 도 돌림(모양은 그대로) ⑤ 관절 피벗 · 계층 · 부착점
#
# 파츠 계층 (회전 0, 원점 = 관절) — ChomperRig 계약:
#   body (몸통 · 옆구리 이음 띠)
#     ├ head  (앞 차양 · 입천장 · 윗니 2 · 차양 구슬)    rotation.x + = 윗턱이 들림
#     ├ jaw   (아랫입술 · 아랫니 2) > tongue (입 바닥 · 혀)   rotation.x + = 아랫입술이 닫힘(턱 밑이 경첩)
#     ├ shell_1 (위 갑각 두 장 · 구슬 2 = 눈 역할) ├ shell_2 (가운데 볏)  └ shell_3 (뒤 꼬리 판)   rotation.x - = 뒤끝이 들림
#     ├ pad_l / pad_r (옆·뒤를 덮는 큰 갑각, 경첩 = 등 위 안쪽 모서리)   rotation.z × side + = 바깥으로 벌어짐
#     └ leg_<1|2|3>_<l|r>_1 (주황 마디 · 청록 띠) > _2 (갈색 발톱)   1 = 앞다리
#   부착점: pt_eye_l/r · pt_mouth · pt_horn · pt_drip_{belly,tail,l,r,mouth} · pt_foot_<i>_<l|r>

import os

import bmesh
import numpy as np
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "models", "source", "chomper_tripo", "original.glb")
OUT = os.path.join(ROOT, "output", "models", "bug_chomper")
ATLAS = 2048

# 원본 파츠 번호 → 관절 (좌우는 정면을 +Y 로 돌린 뒤 기준: -X = 왼쪽)
GROUPS = {
	"body": [0, 22, 27],
	"head": [1, 26, 23, 25, 16],
	"jaw_teeth": [11, 24],
	"tongue": [18],
	"shell_1": [2, 3, 20, 21],
	"shell_2": [8],
	"shell_3": [14],
	"pad_l": [19],
	"pad_r": [10],
	"leg_1_l": [5], "leg_1_r": [4],
	"leg_2_l": [15, 17, 13], "leg_2_r": [9, 12],
	"leg_3_l": [6], "leg_3_r": [7],
}
EYES = {"pt_eye_l": (-0.183, 0.11), "pt_eye_r": (0.281, 0.021)}   # 원본 구슬 20 · 21 의 (x, y) 중심 (돌린 뒤)
# 아랫입술을 떼는 평면: 턱 밑 (y .42, z .04) 을 지나 위로 갈수록 뒤로 눕는다. 앞다리 구멍(y .24~.35, z .12~.18)은 몸통 쪽에 남는다.
JAW_CO = (0.0, 0.42, 0.04)
JAW_NO = (0.0, 0.923, 0.385)
HEAD_PIVOT = (0.0, 0.06, 0.46)

# ════════════════════════════════════════════════════════════════
#  불러오기 · 정면 돌리기
# ════════════════════════════════════════════════════════════════
bpy.ops.import_scene.gltf(filepath=SRC)
TURN = Matrix.Rotation(math.pi, 4, "Z")
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
	while sz > s:              # 큰 칸을 넷으로 쪼개 하나를 쓰고 셋은 빈칸으로
		sz //= 2
		free += [(x + sz, y, sz), (x, y + sz, sz), (x + sz, y + sz, sz)]
	px = np.empty(s * s * 4, dtype=np.float32)
	im.pixels.foreach_get(px)
	atlas[y:y + s, x:x + s] = px.reshape(s, s, 4)
	uv = o.data.uv_layers[0].data
	co = np.empty(len(uv) * 2, dtype=np.float32)
	uv.foreach_get("uv", co)
	co = co.reshape(-1, 2)
	co = (np.array([x, y]) + co * s) / ATLAS
	uv.foreach_set("uv", co.ravel())

os.makedirs(OUT, exist_ok=True)
atlas_img = bpy.data.images.new("chomper_atlas", ATLAS, ATLAS, alpha=False)
atlas_img.pixels.foreach_set(atlas.ravel())
atlas_img.filepath_raw = os.path.join(OUT, "chomper_atlas.png")
atlas_img.file_format = "PNG"
atlas_img.save()
atlas_img.pack()

MAT = bpy.data.materials.new("chomper")
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


# ════════════════════════════════════════════════════════════════
#  묶기 · 자르기 도우미
# ════════════════════════════════════════════════════════════════
def group(name, ids):
	o = hb.join([parts[i] for i in ids], name)
	o.matrix_world = Matrix.Identity(4)
	# glTF 가져오기는 UV 이음매마다 정점을 나눠 둔다 → 같은 자리 정점을 합쳐야 잘린 고리가 닫혀 막을 수 있다 (UV·노멀은 꼭짓점마다 그대로)
	bm = bmesh.new()
	bm.from_mesh(o.data)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
	bm.to_mesh(o.data)
	bm.free()
	return o


def verts(o):
	a = np.empty(len(o.data.vertices) * 3, dtype=np.float64)
	o.data.vertices.foreach_get("co", a)
	return a.reshape(-1, 3)


def _cap_uv(bm, faces):
	"""막은 면은 옆 원래 면의 UV 한 점을 써서 그 자리 색 한 가지로 칠한다."""
	uvl = bm.loops.layers.uv.active
	new = set(faces)
	for f in faces:
		pick = None
		for v in f.verts:
			for lp in v.link_loops:
				if lp.face not in new:
					pick = lp[uvl].uv.copy()
					break
			if pick:
				break
		if pick:
			for lp in f.loops:
				lp[uvl].uv = pick


def cut(o, co, no, front_name):
	"""o 를 평면으로 나눈다: 법선 쪽(앞) → 새 물체 front_name, 뒤 → o. 잘린 고리는 둘 다 막는다."""
	front = o.copy()
	front.data = o.data.copy()
	front.name = front.data.name = front_name
	hb.collection().objects.link(front)
	capped = 0
	for obj, keep_front in ((front, True), (o, False)):
		bm = bmesh.new()
		bm.from_mesh(obj.data)
		res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no,
			clear_inner=keep_front, clear_outer=not keep_front)
		edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge) and e.is_valid and e.is_boundary]
		if edges:
			filled = bmesh.ops.holes_fill(bm, edges=edges, sides=0)["faces"]
			capped += len(filled)
			_cap_uv(bm, filled)
		bm.to_mesh(obj.data)
		bm.free()
		obj.data.update()
	print("cut %s / %s: %d cap faces" % (front_name, o.name, capped))
	return front


# ════════════════════════════════════════════════════════════════
#  관절 묶음
# ════════════════════════════════════════════════════════════════
G = {k: group(k, ids) for k, ids in GROUPS.items()}

# 아랫입술(턱): 몸통에서 떼어 아랫니와 합친다
lip = cut(G["body"], JAW_CO, JAW_NO, "jaw_lip")
G["jaw"] = hb.join([lip, G.pop("jaw_teeth")], "jaw")


# ── 다리: 축(주성분) · 고관절 · 발끝 · 접지 · 무릎 자르기 ─────────
def leg_axis(o):
	V = verts(o)
	c = V.mean(0)
	X = V - c
	ev, evec = np.linalg.eigh(X.T @ X)
	ax = evec[:, -1]
	tip = V[V[:, 2].argmin()]
	if (tip - c) @ ax < 0:
		ax = -ax
	return V, c, ax


def brown_t(o, c, ax):
	"""갈색 발톱 면들의 축 위치 (주황 마디와 경계를 찾는다)"""
	uv = o.data.uv_layers[0].data
	out = []
	for p in o.data.polygons:
		u = np.mean([uv[li].uv[:] for li in p.loop_indices], 0)
		r, g, b = atlas_rgb(*u)
		if r < 0.6 and g < 0.52 and abs(r - g) < 0.13 and b > 0.26:
			out.append((np.array(p.center[:]) - c) @ ax)
	return np.array(out)


LEGS = {}
for i in (1, 2, 3):
	for s in ("l", "r"):
		name = "leg_%d_%s" % (i, s)
		o = G.pop(name)
		V, c, ax = leg_axis(o)
		t = (V - c) @ ax
		hip = c + ax * (t.min() + 0.025)
		# 발끝이 바닥(z 0.003)에 닿도록 고관절 기준으로 다리 전체를 살짝 돌린다
		tip = V[V[:, 2].argmin()]
		d = tip - hip
		d[2] = 0.0
		axis = np.cross(d / np.linalg.norm(d), (0, 0, 1))      # + 회전 = 발끝이 들림
		lo_a, hi_a = -0.6, 0.6
		for _ in range(40):
			a = (lo_a + hi_a) / 2
			M = Matrix.Translation(hip) @ Matrix.Rotation(a, 4, axis) @ Matrix.Translation(-hip)
			zmin = min((M @ v.co).z for v in o.data.vertices)
			lo_a, hi_a = (a, hi_a) if zmin < 0.003 else (lo_a, a)
		M = Matrix.Translation(hip) @ Matrix.Rotation(lo_a, 4, axis) @ Matrix.Translation(-hip)
		o.data.transform(M)
		R3 = np.array(M.to_3x3())
		c = np.array((M @ Vector(c.tolist()))[:])
		ax = R3 @ ax
		bt = brown_t(o, c, ax)
		t_cut = float(np.percentile(bt, 3)) - 0.004
		knee = c + ax * t_cut
		lower = cut(o, tuple(knee), tuple(ax), name + "_2")
		o.name = o.data.name = name + "_1"
		V2 = verts(lower)
		foot = V2[V2[:, 2].argmin()].copy()
		foot[2] = 0.0
		LEGS[(i, s)] = (hip, knee, foot, round(math.degrees(lo_a), 1))
		print("%s: grounded %.1f deg, knee t %.3f" % (name, math.degrees(lo_a), t_cut))


# ════════════════════════════════════════════════════════════════
#  피벗 · 계층 · 부착점
# ════════════════════════════════════════════════════════════════
def bounds(o):
	V = verts(o)
	return V.min(0), V.max(0), V


def after_join():
	piv = {"body": (0.0, 0.0, 0.29), "head": HEAD_PIVOT}
	lo, hi, V = bounds(hb.get("jaw"))
	piv["jaw"] = (0.0, float(lo[1]) + 0.02, float(lo[2]) + 0.02)            # 턱 밑 = 경첩
	lo, hi, V = bounds(hb.get("tongue"))
	piv["tongue"] = (0.0, float(lo[1]) + 0.02, float(V[V[:, 1].argmin()][2]))
	for k in ("shell_1", "shell_2"):                                        # 앞끝 = 경첩
		lo, hi, V = bounds(hb.get(k))
		front = V[V[:, 1] > hi[1] - 0.04]
		piv[k] = (0.0, float(hi[1]) - 0.03, float(front[:, 2].mean()))
	lo, hi, V = bounds(hb.get("shell_3"))                                   # 꼬리 판: 위 앞 모서리
	piv["shell_3"] = (0.0, float(hi[1]) - 0.02, float(hi[2]) - 0.03)
	for k in ("pad_l", "pad_r"):                                            # 옆 판: 가장 높은 곳(등 위 안쪽)
		lo, hi, V = bounds(hb.get(k))
		top = V[V[:, 2].argmax()]
		piv[k] = (float(top[0]), float((lo[1] + hi[1]) / 2), float(top[2]) - 0.02)
	for (i, s), (hip, knee, foot, _) in LEGS.items():
		piv["leg_%d_%s_1" % (i, s)] = tuple(hip)
		piv["leg_%d_%s_2" % (i, s)] = tuple(knee)
	for k, p in piv.items():
		hb.rebase(hb.get(k), Matrix.Translation(p))
	parent = {"head": "body", "jaw": "body", "tongue": "jaw", "shell_1": "body", "shell_2": "shell_1",
		"shell_3": "shell_1", "pad_l": "body", "pad_r": "body"}
	for (i, s) in LEGS:
		parent["leg_%d_%s_1" % (i, s)] = "body"
		parent["leg_%d_%s_2" % (i, s)] = "leg_%d_%s_1" % (i, s)
	for k, p in parent.items():
		hb.attach(hb.get(k), hb.get(p))

	# 눈 역할 구슬: shell_1 에서 구슬 자리(원본 20 · 21 의 중심) 근처 정점의 중심 · 바깥으로 1cm
	lo, hi, V = bounds(hb.get("shell_1"))
	mw = hb.get("shell_1").matrix_world
	Vw = np.array([(mw @ Vector(v))[:] for v in V])
	for k, (cx, cy) in EYES.items():
		near = Vw[np.hypot(Vw[:, 0] - cx, Vw[:, 1] - cy) < 0.05]
		top = near[near[:, 2] > near[:, 2].max() - 0.06]
		p = top.mean(0)
		p[2] = near[:, 2].max() - 0.01
		hb.empty(k, tuple(p), parent=hb.get("shell_1"), size=0.05)

	def world_v(k):
		o = hb.get(k)
		return np.array([(o.matrix_world @ v.co)[:] for v in o.data.vertices])

	H = world_v("head")
	hb.empty("pt_mouth", (0.0, float(H[:, 1].max()) - 0.06, 0.3), parent=hb.get("head"), size=0.05)
	J = world_v("jaw")
	jf = J[J[:, 1] > J[:, 1].max() - 0.03]
	hb.empty("pt_drip_mouth", (0.0, float(J[:, 1].max()) - 0.01, float(jf[:, 2].min()) + 0.03), parent=hb.get("jaw"), size=0.05)
	C = world_v("shell_2")
	hb.empty("pt_horn", tuple(C[C[:, 2].argmax()]), parent=hb.get("shell_2"), size=0.05)
	T = world_v("shell_3")
	hb.empty("pt_drip_tail", (0.0, float(T[:, 1].min()) + 0.02, float(T[:, 2].min()) + 0.01), parent=hb.get("shell_3"), size=0.05)
	for k, sgn in (("pad_l", -1), ("pad_r", 1)):
		P = world_v(k)
		low = P[P[:, 2] < P[:, 2].min() + 0.03]
		e = low[np.argmax(low[:, 0] * sgn)]
		hb.empty("pt_drip_" + k[-1], (float(e[0]), float(e[1]), float(e[2]) - 0.01), parent=hb.get(k), size=0.05)
	hb.empty("pt_drip_belly", (0.0, 0.0, 0.045), parent=hb.get("body"), size=0.05)
	for (i, s), (hip, knee, foot, _) in LEGS.items():
		hb.empty("pt_foot_%d_%s" % (i, s), tuple(foot), parent=hb.get("leg_%d_%s_2" % (i, s)), size=0.04)
