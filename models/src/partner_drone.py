# 파트너 청소 드론 (TRIAD) — 미소녀 파트너가 탑승하는 소형 청소 드론. 사용자가 Tripo 로 만든 모델을 관절 단위로 나눈 것.
# 원본: models/source/partner_drone_tripo/original.glb ("futuristic robot 3d model.glb", 파츠 27개 · 4,960 삼각형 · 파츠별 베이스컬러 27장)
# 빌드:  tools\blender.ps1 model models\src\partner_drone.py   (텍스처 확인은 --engine=eevee)
#
# 원칙: 원본 외형(부피·표면·텍스처)은 그대로 둔다. 하는 일은
#  ① 정면을 +Y 로 돌림(원본은 세 모듈이 -Y) · 게임 크기로 균일 확대(SCALE)
#  ② 파츠별 텍스처 27장 → 2048 아틀라스 1장 · 재질 1개 (UV 는 타일 위치로 옮길 뿐 다시 펴지 않음)
#  ③ 관절 단위로 묶기 — 원본이 이미 다리 지지대 · 무릎 구슬 · 발로 나뉘어 있어 자르기는 없다
#  ④ 세 모듈의 민트색 원판(발광부)을 같은 표면 그대로 떼어 core_* 로 (게임에서 발광 재질로 덮는다)
#  ⑤ 관절 피벗 · 계층 · 부착점
#
# 파츠 계층 (회전 0, 원점 = 관절) — DroneRig 계약:
#   body (구형 몸통 · 위 돌기 3)
#     ├ triad (가운데 축 단추) — 세 모듈 묶음, 원점 = 고리 중심. rotation.z = 고리 안에서 회전 (Godot -Z 가 정면)
#     │    └ mod_1 / mod_2 / mod_3 (모듈 고리, 원점 = 모듈 중심) > core_1 / core_2 / core_3 (민트 원판)
#     │         mod_*.position.z - = 앞으로 튀어나옴 (펌프)
#     ├ pod_l / pod_r (옆 원형 부품 + 연결 소켓, 원점 = 몸통 쪽 소켓) rotation.x = 바퀴처럼 돎 · rotation.z × side = 귀처럼 들림
#     └ leg_<fl|fr|bl|br>_1 (지지대, 원점 = 몸통 쪽 고관절) > _2 (무릎 구슬 + 뾰족한 발, 원점 = 무릎 구슬 중심)
#   부착점: pt_foot_<fl|fr|bl|br> (발끝, _2 아래) · pt_nozzle (세 모듈 앞 중심, triad 아래) · pt_top (몸통 꼭대기)
#           pt_dock (몸통 뒤 — 메카 등에 붙는 면) · pt_hatch (등 위 탑승 해치 자리)

import os

import bmesh
import numpy as np
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "models", "source", "partner_drone_tripo", "original.glb")
OUT = os.path.join(ROOT, "output", "models", "partner_drone")
ATLAS = 2048
SCALE = 1.3          # 원본 높이 0.88m → 약 1.15m (플레이어 메카보다 살짝 작은 동료 기체)

# 원본 파츠 번호 → 관절. 좌우는 정면을 +Y 로 돌린 뒤 기준 (-X = 왼쪽): 원본 +X 쪽 파츠가 왼쪽이 된다.
GROUPS = {
	"body": [0, 14, 13, 3],
	"triad": [20],
	"mod_1": [10], "mod_2": [8], "mod_3": [6],          # 1 = 위, 2 = 오른쪽 아래(원본 +X → 돌린 뒤 -X…) 이름은 순번일 뿐
	"pod_l": [1, 17, 19, 22], "pod_r": [2, 18, 21],
	"leg_fl_1": [24], "leg_fl_2": [11, 9],
	"leg_fr_1": [23], "leg_fr_2": [7, 5],
	"leg_bl_1": [26], "leg_bl_2": [15, 4],
	"leg_br_1": [25], "leg_br_2": [16, 12],
}
LEGS = ("fl", "fr", "bl", "br")

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
assert sorted(parts) == list(range(27)), sorted(parts)


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
	co = (np.array([x, y]) + np.clip(co, 0.0, 1.0) * s) / ATLAS
	uv.foreach_set("uv", co.ravel())

os.makedirs(OUT, exist_ok=True)
atlas_img = bpy.data.images.new("drone_atlas", ATLAS, ATLAS, alpha=False)
atlas_img.pixels.foreach_set(atlas.ravel())
atlas_img.filepath_raw = os.path.join(OUT, "drone_atlas.png")
atlas_img.file_format = "PNG"
atlas_img.save()
atlas_img.pack()

MAT = bpy.data.materials.new("partner_drone")
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
#  묶기 · 발광부 떼기
# ════════════════════════════════════════════════════════════════
def group(name, ids):
	o = hb.join([parts[i] for i in ids], name)
	o.matrix_world = Matrix.Identity(4)
	return o


def verts(o):
	a = np.empty(len(o.data.vertices) * 3, dtype=np.float64)
	o.data.vertices.foreach_get("co", a)
	return a.reshape(-1, 3)


def wverts(o):
	return np.array([(o.matrix_world @ v.co)[:] for v in o.data.vertices])


def is_mint(rgb):
	r, g, b = rgb
	return g > 0.35 and g > r + 0.18 and g > b + 0.08


def split_core(o, core_name):
	"""민트 원판 면을 그대로 떼어 core_name 으로. 떼어낸 자리는 같은 면이 덮으므로 막지 않는다."""
	uv = o.data.uv_layers[0].data
	mint = set()
	for p in o.data.polygons:
		u = np.mean([uv[li].uv[:] for li in p.loop_indices], 0)
		if is_mint(atlas_rgb(*u)):
			mint.add(p.index)
	core = o.copy()
	core.data = o.data.copy()
	core.name = core.data.name = core_name
	hb.collection().objects.link(core)
	for obj, keep_mint in ((core, True), (o, False)):
		bm = bmesh.new()
		bm.from_mesh(obj.data)
		bm.faces.ensure_lookup_table()
		kill = [f for f in bm.faces if (f.index in mint) != keep_mint]
		bmesh.ops.delete(bm, geom=kill, context="FACES")
		bm.to_mesh(obj.data)
		bm.free()
		obj.data.update()
	print("%s: %d mint faces of %d" % (core_name, len(mint), len(o.data.polygons) + len(mint)))
	return core


# 무릎 = 무릎 구슬(원본 파츠)의 중심. 발과 합치기 전에 잰다.
KNEE = {}
for s in LEGS:
	_V = wverts(parts[GROUPS["leg_%s_2" % s][0]])
	KNEE[s] = (_V.min(0) + _V.max(0)) / 2

G = {k: group(k, ids) for k, ids in GROUPS.items()}
for i in (1, 2, 3):
	G["core_%d" % i] = split_core(G["mod_%d" % i], "core_%d" % i)


# ════════════════════════════════════════════════════════════════
#  피벗 · 계층 · 부착점
# ════════════════════════════════════════════════════════════════
def bounds(o):
	V = wverts(o)
	return V.min(0), V.max(0), V


def after_join():
	piv = {}
	blo, bhi, BV = bounds(hb.get("body"))
	body_c = (blo + bhi) / 2
	piv["body"] = (0.0, float(body_c[1]), float(body_c[2]))
	# 세 모듈: 각자의 중심(정점 평균) · triad = 가운데 단추의 앞쪽 끝을 지나는 축
	mods = {}
	for i in (1, 2, 3):
		lo, hi, V = bounds(hb.get("mod_%d" % i))
		mods[i] = (lo + hi) / 2
		piv["mod_%d" % i] = tuple(mods[i])
		piv["core_%d" % i] = tuple(mods[i])
	lo, hi, V = bounds(hb.get("triad"))
	tri_c = np.mean(list(mods.values()), 0)
	piv["triad"] = (float((lo[0] + hi[0]) / 2), float(tri_c[1]), float((lo[2] + hi[2]) / 2))
	# 옆 부품: 몸통에 가장 가까운(안쪽) 끝 = 소켓
	for k, sgn in (("pod_l", -1), ("pod_r", 1)):
		lo, hi, V = bounds(hb.get(k))
		inner = V[np.argsort(V[:, 0] * sgn)[:40]]
		piv[k] = (float(inner[:, 0].mean()), float((lo[1] + hi[1]) / 2), float((lo[2] + hi[2]) / 2))
	# 다리: 지지대의 몸통 쪽 끝 = 고관절, 무릎 구슬 중심 = 무릎
	feet = {}
	for s in LEGS:
		lo, hi, V = bounds(hb.get("leg_%s_1" % s))
		d = np.linalg.norm(V - body_c, axis=1)
		hip = V[np.argsort(d)[:6]].mean(0)
		piv["leg_%s_1" % s] = tuple(hip)
		piv["leg_%s_2" % s] = tuple(KNEE[s])
		lo2, hi2, V2 = bounds(hb.get("leg_%s_2" % s))
		tip = V2[V2[:, 2].argmin()].copy()
		feet[s] = tip
	for k, p in piv.items():
		hb.rebase(hb.get(k), Matrix.Translation(p))
	parent = {"triad": "body", "pod_l": "body", "pod_r": "body"}
	for i in (1, 2, 3):
		parent["mod_%d" % i] = "triad"
		parent["core_%d" % i] = "mod_%d" % i
	for s in LEGS:
		parent["leg_%s_1" % s] = "body"
		parent["leg_%s_2" % s] = "leg_%s_1" % s
	for k, p in parent.items():
		hb.attach(hb.get(k), hb.get(p))

	for s in LEGS:
		hb.empty("pt_foot_" + s, tuple(feet[s]), parent=hb.get("leg_%s_2" % s), size=0.04)
	lo, hi, V = bounds(hb.get("triad"))
	hb.empty("pt_nozzle", (piv["triad"][0], float(max(m[1] for m in mods.values())) + 0.06, piv["triad"][2]),
		parent=hb.get("triad"), size=0.06)
	hb.empty("pt_top", (0.0, float(body_c[1]), float(bhi[2])), parent=hb.get("body"), size=0.05)
	back = BV[BV[:, 1] < blo[1] + 0.03]
	hb.empty("pt_dock", (0.0, float(blo[1]), float(back[:, 2].mean())), parent=hb.get("body"), size=0.06)
	hb.empty("pt_hatch", (0.0, float(body_c[1]) - 0.12, float(bhi[2]) - 0.05), parent=hb.get("body"), size=0.05)
	for s in LEGS:
		print("leg %s hip %s knee %s foot %s" % (s, np.round(piv["leg_%s_1" % s], 3), np.round(piv["leg_%s_2" % s], 3), np.round(feet[s], 3)))
	print("triad", np.round(piv["triad"], 3), "mods", {i: np.round(m, 3) for i, m in mods.items()})
	print("pods", np.round(piv["pod_l"], 3), np.round(piv["pod_r"], 3), "body", np.round(piv["body"], 3))
