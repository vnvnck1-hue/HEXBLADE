"""claude_background_bake — 배경 첫 제작(Claude) 모델의 UV 펼치기 + 핸드페인팅 베이크 (Blender 5.2, Cycles).

모델 스크립트(models/src/bg_claude_*.py)의 after_join() 에서 부른다:

    import claude_background_bake as cbb
    PURPLE = cbb.paint_mat("frame", "purple", hi="#7E6CB6", lo="#3A2F62", wear="#B05A5A")
    ...                                                   # 도형에 mat=PURPLE 등으로 칠한다
    def after_join():
        cbb.bake_model("bg_claude_w01", height=3.0, hidden=("back",))

paint_mat 재질은 베이크 전용이다: 반복 붓질 텍스처(claude_background_paint.tile)를 오브젝트 좌표로 상자 투영하고,
면 방향(위 밝게·아래 어둡게) · 높이(바닥 쪽 어둡게) · 베벨 면(실제 모디파이어 베벨) 밝은 칠 · 아래 베벨 짙은 칠 ·
틈 AO(국소, 약하게) · 선택 모서리 마모를 섞어 Emission 으로 낸다. bake_model 이 이것을 UV 아틀라스(512px/m)에 구운 뒤
모든 메시를 '구운 텍스처 하나 + Roughness .85' 의 단일 PBR 재질로 바꿔서 GLB 로 나간다 (Godot 에 그대로 연결).
씬 전체 방향 그림자·조명 글로우는 굽지 않는다 (면 방향 명암은 아주 약하게만).
"""

import json
import os

import bmesh
import bpy
from mathutils import Vector

import claude_background_paint as paint

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC_DIR = os.path.join(ROOT, "output", "claude-background-first-pass", "src_textures")
PX_PER_M = 512
TEX_VERSION = 2          # 붓질 생성기를 바꾸면 올린다 (캐시 무효화)
FLOOR_VERSION = 3        # 바닥 그림(floor_4m)을 바꾸면 올린다
SEEDS = {"purple": 21, "lilac": 22, "door": 23, "coral": 24, "dark": 25,
		 "navy": 31, "steel": 32, "slate": 33, "teal": 34, "cream": 35, "lamp": 36,
		 "deep": 37, "void": 38}

_paint_mats = {}


# ---------------------------------------------------------------- 원본 붓질 텍스처 (캐시)

def source_texture(kind):
	"""재질 반복 텍스처(2m = 1024px) 경로. 없으면 그려서 저장한다."""
	os.makedirs(SRC_DIR, exist_ok=True)
	gd = os.path.join(os.path.dirname(SRC_DIR), ".gdignore")
	if not os.path.exists(gd):
		open(gd, "w").close()
	p = os.path.join(SRC_DIR, "tile_%s_v%d_s%d.png" % (kind, TEX_VERSION, SEEDS[kind]))
	if not os.path.exists(p):
		paint.save_png(p, paint.tile(kind, 1024, SEEDS[kind]))
	return p


def floor_texture():
	os.makedirs(SRC_DIR, exist_ok=True)
	p = os.path.join(SRC_DIR, "floor_4m_v%d.png" % FLOOR_VERSION)
	if not os.path.exists(p):
		paint.save_png(p, paint.floor_4m(7))
	return p


def _img(path, colorspace="sRGB"):
	name = os.path.basename(path)
	im = bpy.data.images.get(name) or bpy.data.images.load(path)
	im.colorspace_settings.name = colorspace
	return im


# ---------------------------------------------------------------- 노드 도우미

class _G:
	def __init__(self, nt):
		self.nt = nt
		self.x = 0

	def node(self, kind, **props):
		n = self.nt.nodes.new(kind)
		n.location = (self.x, 0)
		self.x += 180
		for k, v in props.items():
			setattr(n, k, v)
		return n

	def link(self, a, b):
		self.nt.links.new(a, b)

	def math(self, op, a, b=None, clamp=False):
		n = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
		for i, v in enumerate((a, b)):
			if v is None:
				continue
			if isinstance(v, (int, float)):
				n.inputs[i].default_value = v
			else:
				self.link(v, n.inputs[i])
		return n.outputs[0]

	def ramp(self, v, a, b):
		"""smoothstep(a, b, v)"""
		n = self.node("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP", clamp=True)
		self.link(v, n.inputs["Value"])
		n.inputs["From Min"].default_value = a
		n.inputs["From Max"].default_value = b
		return n.outputs["Result"]

	def mix(self, fac, a, b, blend="MIX"):
		n = self.node("ShaderNodeMix", data_type="RGBA", blend_type=blend, clamp_result=True)
		if isinstance(fac, (int, float)):
			n.inputs[0].default_value = fac
		else:
			self.link(fac, n.inputs[0])
		for sock, v in ((n.inputs[6], a), (n.inputs[7], b)):
			if isinstance(v, tuple):
				sock.default_value = (*v, 1.0)
			else:
				self.link(v, sock)
		return n.outputs[2]

	def scale_col(self, col, s):
		n = self.node("ShaderNodeVectorMath", operation="SCALE")
		self.link(col, n.inputs[0])
		if isinstance(s, (int, float)):
			n.inputs["Scale"].default_value = s
		else:
			self.link(s, n.inputs["Scale"])
		return n.outputs[0]


def paint_mat(name, kind, hi, lo, wear=None, wear_amt=0.0, period=2.0, bevel_hi=0.65, ao=0.5, hgrad=0.14,
			  grad_h=1.0, rough=0.85):
	"""베이크용 칠 재질. kind = 붓질 텍스처 종류, hi/lo = 베벨 밝은 칠/짙은 칠 색, wear = 마모 색,
	grad_h = 바닥에서 이 높이(m)까지 위로 갈수록 밝아지는 그라디언트 (벽은 0.9 정도)."""
	if name in _paint_mats:
		return _paint_mats[name]
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	nt = m.node_tree
	nt.nodes.clear()
	g = _G(nt)
	lin = paint_lin_c
	hi_c, lo_c = lin(hi), lin(lo)

	# 붓질 텍스처: 오브젝트 좌표 상자 투영, period m 마다 반복
	tc = g.node("ShaderNodeTexCoord")
	mp = g.node("ShaderNodeMapping")
	mp.inputs["Scale"].default_value = (1.0 / period,) * 3
	g.link(tc.outputs["Object"], mp.inputs["Vector"])
	tex = g.node("ShaderNodeTexImage", projection="BOX", projection_blend=0.35, interpolation="Cubic")
	tex.image = _img(source_texture(kind))
	g.link(mp.outputs["Vector"], tex.inputs["Vector"])
	col = tex.outputs["Color"]

	# 면 방향: 실제 면 법선(True Normal)
	geo = g.node("ShaderNodeNewGeometry")
	sep = g.node("ShaderNodeSeparateXYZ")
	g.link(geo.outputs["True Normal"], sep.inputs[0])
	nx, ny, nz = (g.math("ABSOLUTE", sep.outputs[i]) for i in range(3))
	mx = g.math("MAXIMUM", g.math("MAXIMUM", nx, ny), nz)
	edge = g.math("SUBTRACT", 1.0, mx)               # 축 정렬 면 0, 베벨 면 > 0.05
	bev = g.ramp(edge, 0.02, 0.06)
	zsig = sep.outputs[2]
	up = g.ramp(zsig, 0.15, 0.6)                     # 위쪽을 향함
	down = g.ramp(zsig, -0.15, -0.6)                 # 아래쪽을 향함

	# 면 방향 명암 (아주 약하게): 위 +6% · 아래 -22%
	dirf = g.math("ADD", g.math("ADD", 0.97, g.math("MULTIPLY", up, 0.09)), g.math("MULTIPLY", down, -0.22))
	# 높이 그라디언트: 바닥 쪽이 조금 어둡다 (칠한 부피감)
	zpos = g.node("ShaderNodeSeparateXYZ")
	g.link(tc.outputs["Object"], zpos.inputs[0])
	hf = g.math("ADD", 1.0 - hgrad, g.math("MULTIPLY", g.ramp(zpos.outputs[2], 0.0, grad_h), hgrad))
	col = g.scale_col(col, g.math("MULTIPLY", dirf, hf))

	# 틈 AO (국소, 약하게) → 유색 그림자
	aon = g.node("ShaderNodeAmbientOcclusion", only_local=True, samples=12)
	aon.inputs["Distance"].default_value = 0.14
	aod = g.math("MULTIPLY", g.ramp(aon.outputs["AO"], 0.95, 0.35), ao)
	col = g.mix(aod, col, lo_c)

	# 베벨 칠: 위·옆 베벨은 밝게, 아래 베벨은 짙게
	bev_top = g.math("MULTIPLY", bev, g.math("SUBTRACT", 1.0, down))
	bev_bot = g.math("MULTIPLY", bev, down)
	col = g.mix(g.math("MULTIPLY", bev_top, bevel_hi), col, hi_c)
	col = g.mix(g.math("MULTIPLY", bev_bot, 0.55), col, lo_c)

	# 선택 모서리 마모: 큰 노이즈로 고른 일부 베벨에만
	if wear and wear_amt > 0:
		nz_t = g.node("ShaderNodeTexNoise")
		nz_t.inputs["Scale"].default_value = 2.2
		nz_t.inputs["Detail"].default_value = 3.0
		g.link(tc.outputs["Object"], nz_t.inputs["Vector"])
		pick = g.ramp(nz_t.outputs["Fac"], 0.56, 0.62)
		col = g.mix(g.math("MULTIPLY", g.math("MULTIPLY", pick, bev), wear_amt), col, lin(wear))

	em = g.node("ShaderNodeEmission")
	g.link(col, em.inputs["Color"])
	out = g.node("ShaderNodeOutputMaterial")
	g.link(em.outputs[0], out.inputs["Surface"])
	m["cbb_rough"] = rough
	m.diffuse_color = (*paint_lin_c(paint.PALETTES[kind][0]), 1.0)
	_paint_mats[name] = m
	return m


def paint_lin_c(c):
	if isinstance(c, str):
		c = tuple(paint.hexc(c))
	return tuple(((v / 12.92) if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4) for v in c[:3])


# ---------------------------------------------------------------- UV

def _meshes():
	return [o for o in bpy.context.scene.objects if o.type == "MESH" and not o.name.startswith("_")]


def _islands(bm, uv):
	"""UV 섬 목록 (같은 UV 좌표를 공유하는 변으로 이어진 면들)."""
	seen = set()
	out = []
	for f in bm.faces:
		if f.index in seen:
			continue
		stack = [f]
		seen.add(f.index)
		isl = []
		while stack:
			a = stack.pop()
			isl.append(a)
			for l in a.loops:
				e = l.edge
				for lf in e.link_faces:
					if lf.index in seen:
						continue
					# 변의 양 끝 UV 가 같으면 이어진 것
					la = [x for x in a.loops if x.edge == e][0]
					lb = [x for x in lf.loops if x.edge == e][0]
					ua = {(round(la[uv].uv.x, 6), round(la[uv].uv.y, 6)), (round(la.link_loop_next[uv].uv.x, 6), round(la.link_loop_next[uv].uv.y, 6))}
					ub = {(round(lb[uv].uv.x, 6), round(lb[uv].uv.y, 6)), (round(lb.link_loop_next[uv].uv.x, 6), round(lb.link_loop_next[uv].uv.y, 6))}
					if ua == ub:
						seen.add(lf.index)
						stack.append(lf)
		out.append(isl)
	return out


def unwrap(objs, res, hidden=(), hidden_scale=0.2, margin_px=16, lowres=(), fit_scale=False):
	"""스마트 UV → 512px/m 로 맞춤 → 안 보이는 면(hidden: back=-Y, bottom=-Z)의 섬은 hidden_scale 배로 줄임 → 배율 고정 패킹.
	반환: (맞았는지, 실제 px/m)."""
	for o in objs:
		for l in list(o.data.uv_layers):
			o.data.uv_layers.remove(l)
		o.data.uv_layers.new(name="UVMap")
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_all(action="SELECT")
	bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.0, area_weight=0.0, scale_to_bounds=False)
	bpy.ops.object.mode_set(mode="OBJECT")
	target = PX_PER_M / float(res)                    # UV 단위 / m
	area3, area_uv = 0.0, 0.0
	for o in objs:
		me = o.data
		uvl = me.uv_layers.active.data
		for p in me.polygons:
			area3 += p.area * _scale2(o)
			pts = [uvl[i].uv for i in p.loop_indices]
			a = 0.0
			for i in range(len(pts)):
				a += pts[i].x * pts[(i + 1) % len(pts)].y - pts[(i + 1) % len(pts)].x * pts[i].y
			area_uv += abs(a) * 0.5
	cur = (area_uv / max(area3, 1e-9)) ** 0.5
	k = target / max(cur, 1e-9)
	for o in objs:
		bm = bmesh.new()
		bm.from_mesh(o.data)
		bm.faces.ensure_lookup_table()
		uv = bm.loops.layers.uv.active
		for f in bm.faces:
			for l in f.loops:
				l[uv].uv *= k
		if hidden or lowres:
			slot_names = [s.material.name if s.material else "" for s in o.material_slots]
			for isl in _islands(bm, uv):
				n = Vector()
				for f in isl:
					n += f.normal * f.calc_area()
				n.normalize()
				hide = ("back" in hidden and n.y < -0.85) or ("bottom" in hidden and n.z < -0.85)
				# 거의 가려지는 재질(속판 등)은 섬 전체를 작게
				if lowres and all(slot_names[f.material_index] in lowres for f in isl if f.material_index < len(slot_names)):
					hide = True
				if hide:
					c = Vector((0.0, 0.0))
					cnt = 0
					for f in isl:
						for l in f.loops:
							c += l[uv].uv
							cnt += 1
					c /= cnt
					for f in isl:
						for l in f.loops:
							l[uv].uv = c + (l[uv].uv - c) * hidden_scale
		bm.to_mesh(o.data)
		bm.free()
	a_before = uv_fill(objs)
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_all(action="SELECT")
	bpy.ops.uv.select_all(action="SELECT")
	m = margin_px * 2.0 / res
	bpy.ops.uv.pack_islands(udim_source="CLOSEST_UDIM", rotate=True, scale=fit_scale, margin_method="FRACTION", margin=m, shape_method="CONCAVE")
	bpy.ops.object.mode_set(mode="OBJECT")
	pxm = PX_PER_M * (uv_fill(objs) / max(a_before, 1e-9)) ** 0.5
	lo, hi = Vector((9, 9)), Vector((-9, -9))
	for o in objs:
		for d in o.data.uv_layers.active.data:
			lo.x, lo.y = min(lo.x, d.uv.x), min(lo.y, d.uv.y)
			hi.x, hi.y = max(hi.x, d.uv.x), max(hi.y, d.uv.y)
	fits = lo.x >= -1e-4 and lo.y >= -1e-4 and hi.x <= 1.0001 and hi.y <= 1.0001
	return fits, pxm


def _scale2(o):
	s = o.matrix_world.to_scale()
	return abs(s.x * s.y)  # 오브젝트 배율은 1 로 둔다 (참고용)


# ---------------------------------------------------------------- 베이크

def bake_model(name, hidden=(), res=None, samples=48, lowres=(), emit=()):
	"""모든 메시를 UV 아틀라스에 굽고 단일 재질로 바꾼다. 결과 PNG: output/models/<name>/<name>_albedo.png.
	emit = 상태등 재질 이름들: 그 면만 흰색인 발광 마스크(<name>_emit.png)를 같은 UV 로 한 번 더 구워 최종 재질의
	Emission 텍스처로 연결한다 (Godot 이 emission_texture 로 받는다 — 색·세기는 게임 코드가 정한다)."""
	objs = _meshes()
	for o in objs:
		if o.modifiers:
			bpy.context.view_layer.objects.active = o
			for md in list(o.modifiers):
				bpy.ops.object.modifier_apply(modifier=md.name)
	# 512px/m 그대로 들어가는 가장 작은 크기 → 안 되면 2048 에 맞춰 줄이되 280px/m 이상 → 4096.
	# 붓질은 월드 좌표 텍스처에서 굽기 때문에 밀도가 낮아도 붓 크기(m)는 같고 선명도만 조금 준다. 4096 은 VRAM 이 4배.
	tries = [(res, False), (res, True)] if res else [(1024, False), (2048, False), (2048, True), (4096, False)]
	used = None
	pxm = PX_PER_M
	for r, sc_fit in tries:
		fits, pxm = unwrap(objs, r, hidden, lowres=lowres, fit_scale=sc_fit)
		print("  uv try %dpx scale=%s fits=%s %.0fpx/m" % (r, sc_fit, fits, pxm))
		if fits and (pxm >= 280 or res):          # res 를 정해 주면 그 크기에 맞춰 밀도를 낮춰도 받는다
			used = r
			break
	if used is None:
		raise RuntimeError("UV 가 %dpx 아틀라스에 들어가지 않는다" % sizes[-1])
	out_dir = os.path.join(ROOT, "output", "models", name)
	os.makedirs(out_dir, exist_ok=True)
	img = bpy.data.images.new(name + "_albedo", used, used, alpha=False)
	img.colorspace_settings.name = "sRGB"
	sc = bpy.context.scene
	sc.render.engine = "CYCLES"
	sc.cycles.device = "CPU"
	sc.cycles.samples = samples
	sc.cycles.use_denoising = False
	sc.render.bake.margin = 16
	sc.render.bake.margin_type = "EXTEND"
	sc.render.bake.use_clear = True
	mats = set()
	for o in objs:
		for s in o.material_slots:
			if s.material:
				mats.add(s.material)
	for m in mats:
		n = m.node_tree.nodes.new("ShaderNodeTexImage")
		n.name = "_bake_target"
		n.image = img
		n.location = (-300, -400)
		for x in m.node_tree.nodes:
			x.select = False
		n.select = True
		m.node_tree.nodes.active = n
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	bpy.ops.object.bake(type="EMIT")
	path = os.path.join(out_dir, name + "_albedo.png")
	img.filepath_raw = path
	img.file_format = "PNG"
	img.save()
	emit_img = None
	if emit:
		emit_img = bpy.data.images.new(name + "_emit", used, used, alpha=False)
		emit_img.colorspace_settings.name = "sRGB"
		for m in mats:
			nt = m.node_tree
			nt.nodes["_bake_target"].image = emit_img
			e = nt.nodes.new("ShaderNodeEmission")
			v = 1.0 if m.name in emit else 0.0
			e.inputs["Color"].default_value = (v, v, v, 1.0)
			out = [x for x in nt.nodes if x.type == "OUTPUT_MATERIAL"][0]
			nt.links.new(e.outputs[0], out.inputs["Surface"])
		sc.cycles.samples = 4
		bpy.ops.object.bake(type="EMIT")
		sc.cycles.samples = samples
		emit_img.filepath_raw = os.path.join(out_dir, name + "_emit.png")
		emit_img.file_format = "PNG"
		emit_img.save()
	# 최종 재질: 구운 텍스처 하나 (Godot 은 StandardMaterial3D 로 받는다)
	rough = max([m.get("cbb_rough", 0.85) for m in mats] or [0.85])
	final = final_material(name, img, rough, emit_img)
	for o in objs:
		o.data.materials.clear()
		o.data.materials.append(final)
	for m in mats:
		bpy.data.materials.remove(m)
	_paint_mats.clear()
	info = {"atlas_px": used, "px_per_m": round(pxm, 1), "samples": samples, "albedo": os.path.relpath(path, ROOT).replace("\\", "/"),
			"uv_fill": uv_fill(objs)}
	with open(os.path.join(out_dir, "bake.json"), "w", encoding="utf-8") as f:
		json.dump(info, f, ensure_ascii=False, indent=1)
	print("bake: %s %dpx  %.0fpx/m  fill %.2f" % (name, used, pxm, info["uv_fill"]))
	return img


def final_material(name, img, rough=0.85, emit_img=None):
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	nt = m.node_tree
	b = nt.nodes.get("Principled BSDF")
	t = nt.nodes.new("ShaderNodeTexImage")
	t.image = img
	nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
	if emit_img is not None:
		te = nt.nodes.new("ShaderNodeTexImage")
		te.image = emit_img
		nt.links.new(te.outputs["Color"], b.inputs["Emission Color"])
		b.inputs["Emission Strength"].default_value = 1.0
	b.inputs["Metallic"].default_value = 0.0
	b.inputs["Roughness"].default_value = rough
	b.inputs["Specular IOR Level"].default_value = 0.25
	m.diffuse_color = (0.4, 0.33, 0.6, 1)
	return m


def uv_fill(objs):
	a = 0.0
	for o in objs:
		uvl = o.data.uv_layers.active.data
		for p in o.data.polygons:
			pts = [uvl[i].uv for i in p.loop_indices]
			s = 0.0
			for i in range(len(pts)):
				s += pts[i].x * pts[(i + 1) % len(pts)].y - pts[(i + 1) % len(pts)].x * pts[i].y
			a += abs(s) * 0.5
	return a
