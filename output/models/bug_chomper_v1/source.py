# 벌레형 괴생명체 ③ 촘퍼 (CHOMPER) — 튜토리얼에 나오는 하찮은 우주 벌레. 사용자 3면도(정면·측면·후면) 기반.
# 노란 갑각 판(주황 반점) 여러 장 · 청록 몸통 · 앞면 전체를 차지하는 큰 입(이빨 4개 · 분홍 혀) · 짧은 다리 6개 · 청록 구슬 장식.
# 빌드:  tools\blender.ps1 model models\src\bug_chomper.py   (텍스처 확인은 --engine=eevee)
#
# 크기: 높이 0.72m(뿔 끝) · 길이 약 0.95m · 폭 약 1.0m(발 벌림). 플레이어 허리 아래 오는 작은 벌레.
#
# 갑각 판은 하나의 "돔 타원체" 위 띠 조각이다. 각도 th 는 YZ 평면에서 앞(+Y, 0°) → 위(90°) → 뒤(180°),
# 위도 ph 는 좌우(+X 쪽이 +). 판마다 반지름 배율 s 를 앞쪽일수록 크게 해 앞 판이 뒤 판 위에 기와처럼 얹힌다.
# 판 바깥면은 가운데가 볼록한 쿠션 모양 (가장자리는 얇고 가운데는 두껍다 — 원화의 통통한 판).
#
# 텍스처: 노란 갑각(주황 반점 · 작은 구멍) · 청록 피부(얼룩) 두 장을 numpy 로 그려 GLB 에 넣는다 (반복 무늬라 UV 이음매가 티 나지 않는다).
#  판은 판 매개변수(u, v)로 UV 를 펴고, 나머지 도형은 상자 투영 UV.
#
# 파츠 계층 (회전은 모두 0, 원점 = 관절):
#   body (몸통 · 입속, 루트)
#     ├ head  (앞 차양 판 · 윗입술 · 윗니)        rotation.x + = 윗턱이 들림 (입 벌림)
#     ├ jaw   (아랫입술 · 턱 · 아랫니) > tongue   rotation.x - = 아래턱이 내려감
#     ├ shell_1 (정수리 판 · 뿔 · 앞 구슬 2) > shell_2 (가운데 판) > shell_3 (뒤 판)   rotation.x - = 판 뒤끝이 들림
#     ├ pad_l / pad_r (옆 판, 다리 위)            rotation.z × side - = 바깥으로 들림
#     └ leg_<1|2|3>_<l|r>_1 (구슬 고관절 · 노란 마디) > _2 (검은 발톱)   1 = 앞다리
#   부착점: pt_eye_l/r (정수리 구슬 — 공격 예고 때 빛남) · pt_mouth · pt_drip_* (체액이 떨어지는 곳) · pt_horn · pt_foot_<i>_<l|r>

import bmesh
import numpy as np
from mathutils import Matrix

# ════════════════════════════════════════════════════════════════
#  텍스처 (512px 반복 무늬)
# ════════════════════════════════════════════════════════════════
TEX = 512
TILE = 0.32            # 텍스처 한 장이 덮는 길이 (m)
rng = np.random.default_rng(7)


def _hex(h):
	h = h.lstrip("#")
	return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def _blobs(count, r_lo, r_hi, cluster=(2, 5)):
	"""반복(타일) 가능한 덩어리 장: 가우스 점 몇 개를 뭉쳐 찍어 불규칙한 얼룩을 만든다."""
	y, x = np.mgrid[0:TEX, 0:TEX].astype(np.float32)
	field = np.zeros((TEX, TEX), np.float32)
	for _ in range(count):
		cx, cy = rng.uniform(0, TEX, 2)
		for _ in range(rng.integers(*cluster)):
			px = (cx + rng.normal(0, r_hi * 0.7)) % TEX
			py = (cy + rng.normal(0, r_hi * 0.7)) % TEX
			r = rng.uniform(r_lo, r_hi)
			dx = np.abs(x - px)
			dx = np.minimum(dx, TEX - dx)
			dy = np.abs(y - py)
			dy = np.minimum(dy, TEX - dy)
			field += np.exp(-(dx * dx + dy * dy) / (2 * r * r))
	return field


def _smooth(a, b, x):
	t = np.clip((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)


def _lowfreq(amp):
	"""아주 느린 밝기 흔들림 (반복 가능): 몇 개의 큰 사인 합."""
	y, x = np.mgrid[0:TEX, 0:TEX].astype(np.float32) / TEX * 2 * np.pi
	f = np.zeros((TEX, TEX), np.float32)
	for _ in range(5):
		kx, ky = rng.integers(1, 4, 2)
		f += np.sin(kx * x + ky * y + rng.uniform(0, 6.3))
	return f / 5 * amp


def _image(name, rgb):
	img = bpy.data.images.new(name, TEX, TEX, alpha=False)
	px = np.concatenate([np.clip(rgb, 0, 1), np.ones((TEX, TEX, 1), np.float32)], axis=2)
	img.pixels.foreach_set(px[::-1].ravel())
	img.pack()
	return img


def shell_texture():
	base = _hex("f2b538")
	spot = _hex("d98a22")
	pale = _hex("fcd35e")
	pore = _hex("c27818")
	f = _blobs(13, 12, 30)
	m = _smooth(0.55, 0.75, f)                     # 주황 반점 (가장자리 부드럽게)
	ring = _smooth(0.4, 0.55, f) - m               # 반점 둘레 살짝 진한 테
	l = _smooth(0.6, 0.85, _blobs(12, 4, 9, (1, 3)))  # 밝은 작은 얼룩
	p = _smooth(0.75, 0.95, _blobs(26, 1.5, 3, (1, 2)))  # 작은 구멍
	img = np.ones((TEX, TEX, 3), np.float32) * base
	img *= (1 + _lowfreq(0.05))[..., None]
	img = img * (1 - l[..., None] * 0.7) + pale * l[..., None] * 0.7
	img = img * (1 - m[..., None]) + spot * m[..., None]
	img *= (1 - ring * 0.06)[..., None]
	img = img * (1 - p[..., None] * 0.6) + pore * p[..., None] * 0.6
	return _image("chomper_shell", img)


def skin_texture():
	base = _hex("2fa8a2")
	dark = _hex("23918d")
	lite = _hex("47bfb6")
	m = _smooth(0.5, 0.9, _blobs(26, 10, 26))
	l = _smooth(0.7, 0.95, _blobs(40, 2, 5, (1, 3)))
	img = np.ones((TEX, TEX, 3), np.float32) * base
	img *= (1 + _lowfreq(0.04))[..., None]
	img = img * (1 - m[..., None] * 0.55) + dark * m[..., None] * 0.55
	img = img * (1 - l[..., None] * 0.5) + lite * l[..., None] * 0.5
	return _image("chomper_skin", img)


def tex_mat(name, img, preview, rough=0.55, spec=0.35):
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	nt = m.node_tree
	b = nt.nodes.get("Principled BSDF")
	t = nt.nodes.new("ShaderNodeTexImage")
	t.image = img
	nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
	b.inputs["Roughness"].default_value = rough
	b.inputs["Metallic"].default_value = 0.0
	b.inputs["Specular IOR Level"].default_value = spec
	m.diffuse_color = (*hb._lin(preview), 1.0)
	hb._mats[name] = m
	return m


SHELL = tex_mat("chomper_shell", shell_texture(), "#f6bb3c", rough=0.5)
SKIN = tex_mat("chomper_skin", skin_texture(), "#2fa8a2", rough=0.45)
RIM = hb.mat("chomper_rim", "#cf8a22", rough=0.6)            # 판 가장자리 · 안쪽
LIP = hb.mat("chomper_lip", "#f6c852", rough=0.4)
MOUTH = hb.mat("chomper_mouth", "#a3303a", rough=0.5)
THROAT = hb.mat("chomper_throat", "#6a1622", rough=0.6)
TONGUE = hb.mat("chomper_tongue", "#ec6b70", rough=0.3)
TOOTH = hb.mat("chomper_tooth", "#f6e8c8", rough=0.35)
STUD = hb.mat("chomper_stud", "#36c0b5", rough=0.18)
CLAW = hb.mat("chomper_claw", "#4c4846", rough=0.4)
LINE = hb.mat("chomper_line", "#1f7f7b", rough=0.5)

_n = [0]


def nm(p):
	_n[0] += 1
	return "%s_%03d" % (p, _n[0])


# ════════════════════════════════════════════════════════════════
#  치수
# ════════════════════════════════════════════════════════════════
D = Vector((0, -0.06, 0.22))       # 갑각 돔 중심
RX, RY, RZ = 0.44, 0.46, 0.40      # 돔 반지름
BC = Vector((0, -0.04, 0.29))      # 몸통 중심
BR = Vector((0.36, 0.42, 0.27))    # 몸통 반지름
MC = Vector((0, 0.40, 0.27))       # 입 구멍(자르는 타원체) 중심
MR = Vector((0.27, 0.28, 0.2))
THICK = 0.045
BULGE = 0.04


def dome(th, ph, rho):
	th, ph = math.radians(th), math.radians(ph)
	return D + Vector((math.sin(ph) * RX, math.cos(ph) * math.cos(th) * RY, math.cos(ph) * math.sin(th) * RZ)) * rho


def dome_side(a, b, rho, sgn):
	"""옆 판용 매핑: 극점이 앞뒤(±Y)에 있다. a = 옆(0°)에서 위(90°)로, b = 앞(+)뒤(-)."""
	a, b = math.radians(a), math.radians(b)
	return D + Vector((sgn * math.cos(b) * math.cos(a) * RX, math.sin(b) * RY, math.cos(b) * math.sin(a) * RZ)) * rho


def _map(th, ph, rho, side):
	return dome_side(th, ph, rho, side) if side else dome(th, ph, rho)


def plate(part, th0, th1, ph0, ph1, s, mat=None, nu=10, nv=14, front_push=0.0, uv_off=(0, 0), side=0):
	"""돔 띠 조각 판. 바깥면은 쿠션처럼 볼록, 가장자리는 THICK 두께. front_push: 앞끝을 더 내밀기(차양)."""
	bm = bmesh.new()
	uv = bm.loops.layers.uv.new("UVMap")

	def prof(u, v):
		return (math.sin(math.pi * u) * math.sin(math.pi * v)) ** 0.55

	def pos(u, v, outer):
		th = th0 + (th1 - th0) * u
		ph = ph0 + (ph1 - ph0) * v
		k = s * (1 + front_push * (1 - u) ** 2)
		rho = k + (BULGE * prof(u, v) / RX if outer else -THICK / RX)
		return _map(th, ph, rho, side)

	outer = [[bm.verts.new(pos(u / nu, v / nv, True)) for v in range(nv + 1)] for u in range(nu + 1)]
	inner = [[bm.verts.new(pos(u / nu, v / nv, False)) for v in range(nv + 1)] for u in range(nu + 1)]
	lu = math.radians(abs(th1 - th0)) * RY * s / TILE
	lv = math.radians(abs(ph1 - ph0)) * RX * s / TILE

	def face(vs, uvs, mi):
		f = bm.faces.new(vs)
		f.material_index = mi
		for loop, c in zip(f.loops, uvs):
			loop[uv].uv = (c[0] * lu + uv_off[0], c[1] * lv + uv_off[1])
		return f

	for u in range(nu):
		for v in range(nv):
			a, b = (u / nu, v / nv), ((u + 1) / nu, (v + 1) / nv)
			c4 = [(a[0], a[1]), (b[0], a[1]), (b[0], b[1]), (a[0], b[1])]
			face((outer[u][v], outer[u + 1][v], outer[u + 1][v + 1], outer[u][v + 1]), c4, 0)
			face((inner[u][v + 1], inner[u + 1][v + 1], inner[u + 1][v], inner[u][v]), c4[::-1], 1)
	for v in range(nv):
		for u, rev in ((0, False), (nu, True)):
			q = (outer[u][v], outer[u][v + 1], inner[u][v + 1], inner[u][v])
			c = [(0, v / nv), (0, (v + 1) / nv), (0.05, (v + 1) / nv), (0.05, v / nv)]
			face(q[::-1] if rev else q, c[::-1] if rev else c, 1)
	for u in range(nu):
		for v, rev in ((0, True), (nv, False)):
			q = (outer[u][v], outer[u + 1][v], inner[u + 1][v], inner[u][v])
			c = [(u / nu, 0), ((u + 1) / nu, 0), ((u + 1) / nu, 0.05), (u / nu, 0.05)]
			face(q[::-1] if rev else q, c[::-1] if rev else c, 1)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	name = nm(part)
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	o = bpy.data.objects.new(name, me)
	hb.collection().objects.link(o)
	me.materials.append(mat or SHELL)
	me.materials.append(RIM)
	o["hb_part"] = part
	hb.shade_smooth(o, 60)
	return o


def plate_top(th, ph, s, th0, th1, ph0, ph1, side=0):
	"""판 바깥면 위의 점 (구슬·뿔 자리)."""
	u = (th - th0) / (th1 - th0)
	v = (ph - ph0) / (ph1 - ph0)
	p = (math.sin(math.pi * u) * math.sin(math.pi * v)) ** 0.55
	return _map(th, ph, s + BULGE * p / RX, side)


def _rot_to(d):
	q = Vector(d).normalized().to_track_quat("Z", "Y")
	return tuple(math.degrees(v) for v in q.to_euler())


def limb(part, a, b, r1, r2, mat, verts=12):
	a, b = Vector(a), Vector(b)
	d = b - a
	return hb.cyl(nm(part), r=r1, r2=r2, depth=d.length, loc=tuple((a + b) / 2), rot=_rot_to(d), mat=mat, verts=verts, part=part)


def blob(part, c, radii, mat, rot=(0, 0, 0), seg=None):
	big = max(radii)
	seg = seg or (24 if big > 0.12 else (14 if big > 0.04 else 10))
	return hb.sphere(nm(part), r=1.0, loc=tuple(c), rot=rot, scale=radii, mat=mat, seg=seg, rings=seg // 2 + 1, part=part)


def stud(part, p, r=0.042):
	"""청록 구슬: 판에 반쯤 박힌 납작한 공 + 위의 작은 밝은 점."""
	n = (p - D).normalized()
	o = blob(part, p - n * 0.008, (r, r, r * 0.8), STUD, rot=_rot_to(n), seg=14)
	return o


PIV, PARENT, POINTS = {}, {}, []


def joint(part, pivot, parent):
	PIV[part] = Vector(pivot)
	PARENT[part] = parent


# ════════════════════════════════════════════════════════════════
#  몸통 + 입속 (몸통 앞을 타원체로 파내고 잘린 면은 입속 색)
# ════════════════════════════════════════════════════════════════
body = blob("body", BC, tuple(BR), SKIN, seg=32)
cut = hb.sphere("_mouth_cut", r=1.0, loc=tuple(MC), scale=tuple(MR), mat=MOUTH, seg=32, rings=16)
mod = body.modifiers.new("bool", "BOOLEAN")
mod.operation = "DIFFERENCE"
mod.object = cut
mod.solver = "EXACT"
mod.material_mode = "TRANSFER"
hb.apply_mods(body)
bpy.data.objects.remove(cut, do_unlink=True)
# 목구멍: 입속 깊은 곳을 살짝 어둡게
blob("body", (0, MC.y - MR.y + 0.022, MC.z + 0.05), (0.06, 0.012, 0.045), THROAT)
# 배 마디선: 몸통을 두르는 가는 고리 (뒤·아래에서 보인다)
for y in (-0.16, -0.26, -0.35):
	k = math.sqrt(max(0.0, 1 - ((y - BC.y) / BR.y) ** 2))
	o = hb.torus(nm("body"), r=1.0, thick=0.016, loc=(0, y, BC.z), rot=(90, 0, 0), mat=LINE, seg=40, ring=4, part="body")
	o.scale = (BR.x * k * 1.004, BR.z * k * 1.004, 0.3)
joint("body", BC, None)


def body_surface_y(x, z):
	"""몸통 앞면의 y (입 테두리 계산용)."""
	q = 1 - (x / BR.x) ** 2 - ((z - BC.z) / BR.z) ** 2
	return BC.y + BR.y * math.sqrt(max(q, 0.0))


def mouth_rim(a):
	"""입 테두리 점 (각도 a: 0 = 오른쪽, 90 = 위). 자르는 타원체와 몸통 겉면이 만나는 곳을 이분법으로 찾는다."""
	ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
	lo, hi = MC.y - MR.y + 0.01, MC.y
	for _ in range(40):
		y = (lo + hi) / 2
		k = math.sqrt(max(0.0, 1 - ((y - MC.y) / MR.y) ** 2))
		x, z = MR.x * k * ca, MC.z + MR.z * k * sa
		if y > body_surface_y(x, z):
			hi = y
		else:
			lo = y
	return Vector((x, y, z))


# ════════════════════════════════════════════════════════════════
#  입: 입술 고리 (위 = head, 아래 = jaw) · 이빨 4 · 혀 · 턱
# ════════════════════════════════════════════════════════════════
def lip(part, a0, a1, r, push):
	pts = []
	for i in range(25):
		a = a0 + (a1 - a0) * i / 24
		p = mouth_rim(a)
		n = Vector((p.x, 0, p.z - MC.z)).normalized()
		pts.append(tuple(p + n * r * 0.55 + Vector((0, push * max(0.0, -math.sin(math.radians(a))), 0))))
	o = hb.tube(nm(part), pts, r=r, mat=LIP, verts=12, part=part)
	return o


lip("head", -8, 188, 0.038, 0.0)
lip("jaw", 178, 362, 0.05, 0.05)
# 턱: 아랫입술 밑을 받치는 노란 바가지 (옆에서 보면 입이 앞으로 튀어나와 보인다)
blob("jaw", (0, 0.22, 0.085), (0.25, 0.17, 0.075), LIP)


def tooth(part, base, down):
	d = Vector((0, 0.15, -1.0 if down else 1.0)).normalized()
	tip = Vector(base) + d * 0.075
	o = hb.cyl(nm(part), r=0.04, r2=0.024, depth=0.075, loc=tuple((Vector(base) + tip) / 2), rot=_rot_to(d), mat=TOOTH, verts=12, part=part)
	blob(part, tip - d * 0.006, (0.025, 0.025, 0.02), TOOTH, rot=_rot_to(d), seg=10)
	return o


for s in (-1, 1):
	up = mouth_rim(90 - s * 50)
	tooth("head", up + Vector((0, 0.0, -0.035)), True)
	lo = mouth_rim(270 + s * 42)
	tooth("jaw", lo + Vector((0, 0.03, 0.04)), False)
# 혀: 가운데 홈이 있는 두 덩어리
for s in (-1, 1):
	blob("tongue", (s * 0.07, 0.25, 0.13), (0.11, 0.14, 0.055), TONGUE)
blob("tongue", (0, 0.3, 0.155), (0.022, 0.07, 0.03), MOUTH, seg=10)   # 홈 그늘
POINTS.append(("pt_mouth", (0, 0.34, 0.25), "head"))
POINTS.append(("pt_drip_mouth", tuple(mouth_rim(270) + Vector((0, 0.06, -0.02))), "jaw"))

# ════════════════════════════════════════════════════════════════
#  갑각 판
# ════════════════════════════════════════════════════════════════
# 앞 차양 (head): 입 위로 모자 챙처럼 튀어나온다
V = (24, 74, -62, 62, 1.11)
plate("head", V[0], V[1], V[2], V[3], V[4], front_push=0.04, uv_off=(0.1, 0.3))
joint("head", (0, 0.04, 0.43), "body")
joint("jaw", (0, 0.05, 0.12), "body")
joint("tongue", (0, 0.1, 0.11), "jaw")

# 정수리 판 (shell_1) + 뿔 + 앞 구슬 2개 (눈 역할)
C1 = (64, 114, -58, 58, 1.065)
plate("shell_1", *C1, uv_off=(0.5, 0.1))
horn_base = plate_top(92, 0, C1[4], *C1[:4])
hn = (horn_base - D).normalized()
horn_dir = (hn + Vector((0, -0.12, 0))).normalized()
h = hb.cyl(nm("shell_1"), r=0.062, r2=0.01, depth=0.12, loc=tuple(horn_base + horn_dir * 0.05), rot=_rot_to(horn_dir),
		   mat=SHELL, verts=16, part="shell_1")
h.scale = (0.6, 1.35, 1.0)
blob("shell_1", horn_base + horn_dir * 0.108, (0.011, 0.014, 0.011), SHELL, seg=8)
POINTS.append(("pt_horn", tuple(horn_base + horn_dir * 0.115), "shell_1"))
for s, k in ((-1, "l"), (1, "r")):
	p = plate_top(80, s * 30, C1[4], *C1[:4])
	stud("shell_1", p, 0.045)
	POINTS.append(("pt_eye_" + k, tuple(p + (p - D).normalized() * 0.02), "shell_1"))
joint("shell_1", dome(66, 0, C1[4] - 0.05), "body")

# 가운데 판 (shell_2) + 구슬 2
C2 = (104, 154, -64, 64, 1.035)
plate("shell_2", *C2, uv_off=(0.2, 0.7))
for s in (-1, 1):
	stud("shell_2", plate_top(126, s * 38, C2[4], *C2[:4]), 0.04)
joint("shell_2", dome(108, 0, C2[4] - 0.05), "shell_1")

# 뒤 판 (shell_3) + 가운데 구슬
C3 = (144, 197, -52, 52, 1.0)
plate("shell_3", *C3, uv_off=(0.8, 0.4))
stud("shell_3", plate_top(168, 0, C3[4], *C3[:4]), 0.045)
joint("shell_3", dome(148, 0, C3[4] - 0.05), "shell_2")
POINTS.append(("pt_drip_tail", tuple(dome(196, 0, 1.0) + Vector((0, 0.02, -0.02))), "shell_3"))

# 옆 판 (다리 위 어깨받이) + 구슬
for s, k in ((-1, "l"), (1, "r")):
	# a: 옆 아래(6°) → 위(46°), b: 뒤(-46°) → 앞(30°)
	P = (6, 46, -46, 30, 1.08)
	plate("pad_" + k, *P, nu=8, nv=12, uv_off=(0.3 * s, 0.6), side=s)
	stud("pad_" + k, plate_top(24, -8, P[4], *P[:4], side=s), 0.04)
	joint("pad_" + k, dome_side(44, -8, P[4] - 0.05, s), "body")
	POINTS.append(("pt_drip_" + k, tuple(dome_side(6, -8, 1.06, s) + Vector((0, 0, -0.02))), "pad_" + k))

# ════════════════════════════════════════════════════════════════
#  다리 6개: 청록 구슬 고관절 · 굵은 노란 마디 · 검은 발톱
# ════════════════════════════════════════════════════════════════
LEG_Y = (0.17, -0.04, -0.25)
SPREAD = (0.06, 0.0, -0.06)
for i, (y, sp) in enumerate(zip(LEG_Y, SPREAD), start=1):
	for s, k in ((-1, "l"), (1, "r")):
		z = 0.15
		q = 1 - ((y - BC.y) / BR.y) ** 2 - ((z - BC.z) / BR.z) ** 2
		hx = BR.x * math.sqrt(max(q, 0.0)) - 0.015
		hip = Vector((s * hx, y, z))
		knee = Vector((s * (hx + 0.13), y + sp, 0.105))
		foot = Vector((s * (hx + 0.165), y + sp * 1.7, 0.0))
		u, l = "leg_%d_%s_1" % (i, k), "leg_%d_%s_2" % (i, k)
		blob(u, hip, (0.058, 0.058, 0.058), STUD, seg=14)
		limb(u, hip.lerp(knee, 0.25), knee, 0.056, 0.05, SHELL)
		blob(u, knee, (0.05, 0.05, 0.05), SHELL, seg=14)
		blob(l, knee.lerp(foot, 0.45), (0.047, 0.047, 0.062), CLAW, rot=_rot_to(foot - knee), seg=14)
		limb(l, knee.lerp(foot, 0.5), foot + Vector((0, 0, 0.012)), 0.044, 0.016, CLAW)
		blob(l, foot + Vector((0, 0, 0.014)), (0.016, 0.016, 0.014), CLAW, seg=8)
		joint(u, hip, "body")
		joint(l, knee, u)
		POINTS.append(("pt_foot_%d_%s" % (i, k), tuple(foot), l))
POINTS.append(("pt_drip_belly", (0, -0.12, 0.03), "body"))


# ════════════════════════════════════════════════════════════════
#  UV: 판이 아닌 도형은 상자 투영 (텍스처가 반복 무늬라 이음매가 티 나지 않는다)
# ════════════════════════════════════════════════════════════════
def box_uv(o):
	me = o.data
	if me.uv_layers:
		return
	layer = me.uv_layers.new(name="UVMap")
	mw = o.matrix_world
	nm3 = mw.to_3x3()
	for p in me.polygons:
		n = nm3 @ p.normal
		ax = max(range(3), key=lambda i: abs(n[i]))
		a, b = [(1, 2), (0, 2), (0, 1)][ax]
		for li in p.loop_indices:
			w = mw @ me.vertices[me.loops[li].vertex_index].co
			layer.data[li].uv = (w[a] / TILE, w[b] / TILE)


bpy.context.view_layer.update()
for o in list(bpy.context.scene.objects):
	if o.type == "MESH":
		box_uv(o)


def after_join():
	for part, p in PIV.items():
		hb.rebase(hb.get(part), Matrix.Translation(p))
	for part, parent in PARENT.items():
		if parent:
			hb.attach(hb.get(part), hb.get(parent))
	for name, p, parent in POINTS:
		hb.empty(name, p, parent=hb.get(parent))
